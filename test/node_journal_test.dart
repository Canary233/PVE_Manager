import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';

void main() {
  test('latest journal uses one bounded request and decodes gzip', () async {
    final requests = <Uri>[];
    final client = await _clientFor((request) async {
      requests.add(request.uri);
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add(
        gzip.encode(
          utf8.encode(
            jsonEncode({
              'data': [
                'oldest-cursor',
                for (var i = 1; i <= 30; i++) '日志 $i',
                'newest-cursor',
              ],
            }),
          ),
        ),
      );
      await request.response.close();
    });

    final page = await client.getNodeSyslog('pve');

    expect(requests, hasLength(1));
    expect(requests.single.path, '/api2/json/nodes/pve/journal');
    expect(requests.single.queryParameters, {'lastentries': '30'});
    expect(page.items.map((entry) => entry.text), [
      for (var i = 30; i >= 1; i--) '日志 $i',
    ]);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'oldest-cursor');
    expect(page.nextStart, isNull);
  });

  test(
    'cursor pagination preserves encoding and identical log messages',
    () async {
      const cursor = 's=opaque;i=abc;b=def;m=1;t=2;x=3+4&key=value/%?#';
      final requests = <Uri>[];
      final client = await _clientFor((request) async {
        requests.add(request.uri);
        await _respond(request, {
          'data': requests.length == 1
              ? [cursor, 'same message', 'same message', 'newest']
              : ['older-cursor', 'older message', 'same message', cursor],
        });
      });

      final latest = await client.getNodeSyslog('pve', limit: 2);
      final older = await client.getNodeSyslog(
        'pve',
        beforeCursor: latest.nextCursor,
        limit: 2,
      );

      expect(requests, hasLength(2));
      expect(requests.last.path, '/api2/json/nodes/pve/journal');
      expect(requests.last.queryParameters, {
        'lastentries': '2',
        'endcursor': cursor,
      });
      expect(requests.last.fragment, isEmpty);
      expect(latest.items.map((entry) => entry.text), [
        'same message',
        'same message',
      ]);
      expect(older.items.map((entry) => entry.text), [
        'same message',
        'older message',
      ]);
      expect(older.hasMore, isTrue);
      expect(older.nextCursor, 'older-cursor');
    },
  );

  for (final data in <List<String>>[
    [],
    ['anchor', 'anchor'],
    ['oldest', 'only log', 'newest'],
  ]) {
    test('empty or short journal page stops pagination: $data', () async {
      final client = await _clientFor(
        (request) => _respond(request, {'data': data}),
      );

      final page = await client.getNodeSyslog('pve', limit: 2);

      expect(
        page.items.map((entry) => entry.text),
        data.length == 3 ? ['only log'] : isEmpty,
      );
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
      expect(page.nextStart, isNull);
    });
  }

  for (final oldestCursor in ['', 'existing-cursor']) {
    test(
      'missing or nonadvancing cursor stops pagination: $oldestCursor',
      () async {
        final client = await _clientFor(
          (request) => _respond(request, {
            'data': [oldestCursor, 'older', 'newer', 'newest-cursor'],
          }),
        );

        final page = await client.getNodeSyslog(
          'pve',
          beforeCursor: 'existing-cursor',
          limit: 2,
        );

        expect(page.items.map((entry) => entry.text), ['newer', 'older']);
        expect(page.hasMore, isFalse);
        expect(page.nextCursor, isNull);
      },
    );
  }

  for (final data in <Object?>[
    null,
    {'unexpected': 'object'},
    ['only-one-cursor'],
    ['oldest', 123, 'newest'],
  ]) {
    test(
      'malformed journal data fails without legacy fallback: $data',
      () async {
        final paths = <String>[];
        final client = await _clientFor((request) async {
          paths.add(request.uri.path);
          await _respond(request, {'data': data});
        });

        await expectLater(
          client.getNodeSyslog('pve'),
          throwsA(
            isA<ProxmoxApiException>().having(
              (error) => error.code,
              'code',
              ProxmoxErrorCode.apiFormatInvalid,
            ),
          ),
        );
        expect(paths, ['/api2/json/nodes/pve/journal']);
      },
    );
  }

  for (final status in [HttpStatus.forbidden, HttpStatus.internalServerError]) {
    test('journal HTTP $status does not fall back to syslog', () async {
      final paths = <String>[];
      final client = await _clientFor((request) async {
        paths.add(request.uri.path);
        request.response.statusCode = status;
        await _respond(request, {'message': 'journal unavailable'});
      });

      await expectLater(
        client.getNodeSyslog('pve'),
        throwsA(_httpError(status)),
      );
      expect(paths, ['/api2/json/nodes/pve/journal']);
    });
  }

  for (final success in <Object>[0, false]) {
    test('streamed HTTP 200 failure is surfaced: success=$success', () async {
      final paths = <String>[];
      final client = await _clientFor((request) async {
        paths.add(request.uri.path);
        await _respond(request, {
          'success': success,
          'data': <String>[],
          'error': 'Failed to seek to cursor',
        });
      });

      await expectLater(
        client.getNodeSyslog('pve'),
        throwsA(
          isA<ProxmoxApiException>()
              .having(
                (error) => error.code,
                'code',
                ProxmoxErrorCode.requestFailed,
              )
              .having(
                (error) => error.message,
                'message',
                'Failed to seek to cursor',
              ),
        ),
      );
      expect(paths, ['/api2/json/nodes/pve/journal']);
    });
  }

  test(
    'unsupported initial journal falls back to bounded legacy syslog',
    () async {
      final requests = <Uri>[];
      final client = await _clientFor((request) async {
        requests.add(request.uri);
        if (request.uri.path.endsWith('/journal')) {
          request.response.statusCode = HttpStatus.notImplemented;
          await _respond(request, {'message': 'not implemented'});
        } else {
          await _respond(request, {
            'total': 2,
            'data': [
              {'n': 1, 't': 'old'},
              if (request.uri.queryParameters['limit'] == '30')
                {'n': 2, 't': 'new'},
            ],
          });
        }
      });

      final page = await client.getNodeSyslog('pve');

      expect(requests.map((uri) => uri.path), [
        '/api2/json/nodes/pve/journal',
        '/api2/json/nodes/pve/syslog',
        '/api2/json/nodes/pve/syslog',
      ]);
      expect(requests[1].queryParameters, {'start': '0', 'limit': '1'});
      expect(requests[2].queryParameters, {'start': '0', 'limit': '30'});
      expect(page.items.map((entry) => entry.text), ['new', 'old']);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'missing journal on continuation does not restart from syslog',
    () async {
      final paths = <String>[];
      final client = await _clientFor((request) async {
        paths.add(request.uri.path);
        request.response.statusCode = HttpStatus.notFound;
        await _respond(request, {'message': 'journal no longer available'});
      });

      await expectLater(
        client.getNodeSyslog('pve', beforeCursor: 'oldest-cursor'),
        throwsA(_httpError(HttpStatus.notFound)),
      );
      expect(paths, ['/api2/json/nodes/pve/journal']);
    },
  );

  test(
    'legacy final partial page uses an exclusive boundary without overlap',
    () async {
      final requests = <Uri>[];
      final client = await _clientFor((request) async {
        requests.add(request.uri);
        final start = int.parse(request.uri.queryParameters['start']!);
        final limit = int.parse(request.uri.queryParameters['limit']!);
        await _respond(request, {
          'total': 65,
          'data': [
            for (var n = start + 1; n <= start + limit; n++)
              {'n': n, 't': 'line $n'},
          ],
        });
      });

      final older = await client.getNodeSyslog('pve', start: 35);
      final finalPage = await client.getNodeSyslog(
        'pve',
        start: older.nextStart,
      );

      expect(
        requests.map((uri) => uri.path),
        everyElement('/api2/json/nodes/pve/syslog'),
      );
      expect(requests.map((uri) => uri.queryParameters), [
        {'start': '5', 'limit': '30'},
        {'start': '0', 'limit': '5'},
      ]);
      expect(older.hasMore, isTrue);
      expect(older.nextStart, 5);
      expect(
        [...older.items, ...finalPage.items].map((entry) => entry.lineNumber),
        [for (var n = 35; n >= 1; n--) n],
      );
      expect(finalPage.hasMore, isFalse);
      expect(finalPage.nextStart, isNull);
      expect(finalPage.nextCursor, isNull);

      final exhausted = await client.getNodeSyslog('pve', start: 0);
      expect(exhausted.items, isEmpty);
      expect(exhausted.hasMore, isFalse);
      expect(requests, hasLength(2));
    },
  );
}

Matcher _httpError(int status) => isA<ProxmoxApiException>()
    .having((error) => error.code, 'code', ProxmoxErrorCode.requestFailed)
    .having((error) => error.values['statusCode'], 'status', status);

Future<void> _respond(HttpRequest request, Object body) async {
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<ProxmoxClient> _clientFor(
  Future<void> Function(HttpRequest) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path.endsWith('/access/ticket')) {
      await request.drain<void>();
      await _respond(request, {
        'data': {'ticket': 'ticket', 'CSRFPreventionToken': 'csrf'},
      });
    } else {
      await handle(request);
    }
  });
  final client = ProxmoxClient(
    origin: 'http://${server.address.address}:${server.port}',
    username: 'root',
    password: 'test-password',
  );
  addTearDown(client.close);
  await client.login();
  return client;
}
