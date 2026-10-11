import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/data/services/proxmox_console_proxy.dart';

void main() {
  for (final authMode in ProxmoxAuthMode.values) {
    group(authMode.name, () {
      test('authenticates the noVNC page and static assets upstream', () async {
        final fixture = await _Fixture.create(authMode);
        fixture.handle = (request) async {
          fixture.expectAuthentication(request);
          expect(request.uri.path, '/novnc/app.js');
          expect(request.uri.queryParameters['ver'], '1.7.0-2');
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
          );
          request.response.write('export default {};');
          await request.response.close();
        };

        final response = await fixture.request('/novnc/app.js?ver=1.7.0-2');
        expect(response.statusCode, HttpStatus.ok);
        expect(await utf8.decoder.bind(response).join(), 'export default {};');
      });

      test('forwards vncproxy POST with the correct credentials', () async {
        final fixture = await _Fixture.create(authMode);
        fixture.handle = (request) async {
          fixture.expectAuthentication(request);
          expect(request.method, 'POST');
          expect(request.uri.path, '/api2/json/nodes/pve/qemu/100/vncproxy');
          expect(request.headers.value('origin'), fixture.upstreamOrigin);
          expect(
            request.headers.value(HttpHeaders.refererHeader),
            '${fixture.upstreamOrigin}/?console=kvm&vmid=100',
          );
          expect(await utf8.decoder.bind(request).join(), 'websocket=1');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"data":{"port":5900,"ticket":"vnc-ticket"}}',
          );
          await request.response.close();
        };

        final response = await fixture.request(
          '/api2/json/nodes/pve/qemu/100/vncproxy',
          method: 'POST',
          body: 'websocket=1',
          headers: {
            'origin': fixture.proxy.origin.origin,
            HttpHeaders.refererHeader:
                '${fixture.proxy.origin}/?console=kvm&vmid=100',
            HttpHeaders.authorizationHeader: 'Do not forward',
            'CSRFPreventionToken': 'null',
          },
        );
        expect(response.statusCode, HttpStatus.ok);
        final result = jsonDecode(await utf8.decoder.bind(response).join());
        expect(result['data']['ticket'], 'vnc-ticket');
      });

      test('relays binary VNC frames and WebSocket subprotocol', () async {
        final fixture = await _Fixture.create(authMode);
        fixture.handle = (request) async {
          fixture.expectAuthentication(request);
          expect(request.uri.queryParameters, {
            'port': '5900',
            'vncticket': 'PVEVNC:a+b/c==',
          });
          expect(request.headers.value('origin'), fixture.upstreamOrigin);
          final socket = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (protocols) =>
                protocols.contains('binary') ? 'binary' : null,
          );
          socket.listen(socket.add);
        };

        final socket = await WebSocket.connect(
          fixture.proxy.origin
              .replace(
                scheme: 'ws',
                path: '/api2/json/nodes/pve/qemu/100/vncwebsocket',
                queryParameters: {
                  'port': '5900',
                  'vncticket': 'PVEVNC:a+b/c==',
                },
              )
              .toString(),
          protocols: ['binary'],
          headers: {HttpHeaders.cookieHeader: fixture.cookie},
        );
        addTearDown(socket.close);
        expect(socket.protocol, 'binary');
        final received = StreamIterator<dynamic>(socket);
        addTearDown(received.cancel);
        socket.add([0, 1, 127, 128, 255]);
        expect(
          await received.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(received.current, [0, 1, 127, 128, 255]);
        socket.add('text frame');
        expect(
          await received.moveNext().timeout(const Duration(seconds: 3)),
          isTrue,
        );
        expect(received.current, 'text frame');
        await fixture.proxy.close();
        expect(
          await received.moveNext().timeout(const Duration(seconds: 3)),
          isFalse,
        );
      });
    });
  }

  test('does not start a proxy without an active session', () async {
    final client = ProxmoxClient(
      origin: 'https://pve.example:8006',
      username: 'root',
      password: 'secret',
    );
    addTearDown(client.close);
    await expectLater(
      ProxmoxConsoleProxy.start(client),
      throwsA(isA<ProxmoxApiException>()),
    );
  });

  for (final compressed in [false, true]) {
    test(
      'injects WebView compatibility before noVNC modules (gzip=$compressed)',
      () async {
        final fixture = await _Fixture.create(ProxmoxAuthMode.password);
        final html =
            '<!DOCTYPE html><html><head><script type="module" src="/novnc/app.js"></script></head><body></body></html>';
        fixture.handle = (request) async {
          fixture.expectAuthentication(request);
          expect(
            request.headers.value(HttpHeaders.acceptEncodingHeader),
            'identity',
          );
          request.response.headers.contentType = ContentType.html;
          request.response.headers.set(HttpHeaders.etagHeader, 'original');
          final bytes = compressed
              ? gzip.encode(utf8.encode(html))
              : utf8.encode(html);
          if (compressed) {
            request.response.headers.set(
              HttpHeaders.contentEncodingHeader,
              'gzip',
            );
          }
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        };
        final response = await fixture.request('/?console=kvm&novnc=1');
        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.value(HttpHeaders.contentEncodingHeader),
          isNull,
        );
        expect(response.headers.value(HttpHeaders.etagHeader), isNull);
        expect(
          response.headers.value(HttpHeaders.cacheControlHeader),
          'no-store',
        );
        final result = await utf8.decoder.bind(response).join();
        expect(
          result.indexOf('decoder.isConfigSupported ='),
          lessThan(result.indexOf('type="module"')),
        );
        expect(result, contains('supported: false'));
        expect(result, contains('<body></body>'));
      },
    );
  }

  test('rejects missing cookies, wrong cookies, and foreign origins', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.apiToken);
    for (final headers in [
      <String, String>{},
      {HttpHeaders.cookieHeader: '${fixture.proxy.authCookieName}=wrong'},
      {
        HttpHeaders.cookieHeader: fixture.cookie,
        'origin': 'https://other.example',
      },
      {
        HttpHeaders.cookieHeader: fixture.cookie,
        HttpHeaders.hostHeader: 'other.example',
      },
    ]) {
      final request = await fixture.httpClient.getUrl(fixture.proxy.origin);
      headers.forEach(request.headers.set);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
    }
    expect(fixture.forwardedRequests, 0);
  });

  test('rejects an unauthenticated WebSocket handshake', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.apiToken);
    await expectLater(
      WebSocket.connect(fixture.proxy.origin.replace(scheme: 'ws').toString()),
      throwsA(isA<WebSocketException>()),
    );
    expect(fixture.forwardedRequests, 0);
  });

  test(
    'preserves server query parameters without exposing credentials',
    () async {
      final fixture = await _Fixture.create(ProxmoxAuthMode.password);
      final remote = Uri.parse(
        '${fixture.upstreamOrigin}/?console=kvm&node=pve&vmid=100&vmname=Test%20VM&novnc=1',
      );
      final local = fixture.proxy.consoleUri(remote);
      expect(local.host, '127.0.0.1');
      expect(local.scheme, 'http');
      expect(local.queryParameters, {
        ...remote.queryParameters,
        'encrypt': '0',
      });
      expect(local.toString(), isNot(contains('secret')));
      expect(fixture.proxy.authCookie, isNot(contains('PVE:')));
      expect(
        () => fixture.proxy.consoleUri(Uri.parse('https://other.example/')),
        throwsArgumentError,
      );
    },
  );

  test('rewrites same-server redirects and strips server cookies', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.password);
    fixture.handle = (request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          '${fixture.upstreamOrigin}/?novnc=1',
        )
        ..cookies.add(Cookie('PVEAuthCookie', 'must-not-reach-browser'));
      await request.response.close();
    };
    final response = await fixture.request('/redirect', followRedirects: false);
    expect(response.statusCode, HttpStatus.found);
    expect(
      response.headers.value(HttpHeaders.locationHeader),
      '${fixture.proxy.origin}/?novnc=1&encrypt=0',
    );
    expect(response.cookies, isEmpty);
    await response.drain<void>();
  });

  test(
    'preserves repeated query values and fragments in console URLs',
    () async {
      final fixture = await _Fixture.create(ProxmoxAuthMode.password);
      final local = fixture.proxy.consoleUri(
        Uri.parse(
          '${fixture.upstreamOrigin}/?tag=first&tag=second&novnc=1#console',
        ),
      );
      expect(local.queryParametersAll['tag'], ['first', 'second']);
      expect(local.queryParameters['encrypt'], '0');
      expect(local.fragment, 'console');
    },
  );

  test('all concurrent close callers await the same shutdown', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.password);
    final first = fixture.proxy.close();
    final second = fixture.proxy.close();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
  });

  test(
    'does not fail forwarding when a relative Referer is supplied',
    () async {
      final fixture = await _Fixture.create(ProxmoxAuthMode.password);
      fixture.handle = (request) async {
        request.response.write('ok');
        await request.response.close();
      };
      final response = await fixture.request(
        '/asset',
        headers: {HttpHeaders.refererHeader: '/relative'},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(await utf8.decoder.bind(response).join(), 'ok');
    },
  );

  test('blocks redirects to a different upstream', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.apiToken);
    fixture.handle = (request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, 'https://other.example/');
      await request.response.close();
    };
    final response = await fixture.request('/redirect', followRedirects: false);
    expect(response.statusCode, HttpStatus.badGateway);
    expect(response.headers.value(HttpHeaders.locationHeader), isNull);
    await response.drain<void>();
  });

  test('handles repeated Connection headers returned by PVE APIs', () async {
    final fixture = await _Fixture.create(ProxmoxAuthMode.password);
    fixture.handle = (request) async {
      request.response.headers
        ..add(HttpHeaders.connectionHeader, 'keep-alive')
        ..add(HttpHeaders.connectionHeader, 'x-internal')
        ..set('x-internal', 'must-not-forward');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"data":{"status":"running"}}');
      await request.response.close();
    };
    final response = await fixture.request(
      '/api2/json/nodes/pve/qemu/100/status/current',
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('x-internal'), isNull);
    expect(jsonDecode(await utf8.decoder.bind(response).join()), {
      'data': {'status': 'running'},
    });
  });

  test(
    'isolates concurrent console sessions and closes the listener',
    () async {
      final fixture = await _Fixture.create(ProxmoxAuthMode.password);
      final other = await ProxmoxConsoleProxy.start(fixture.client);
      addTearDown(other.close);
      expect(other.authCookieName, isNot(fixture.proxy.authCookieName));
      expect(other.authCookie, isNot(fixture.proxy.authCookie));
      final request = await fixture.httpClient.getUrl(other.origin);
      request.headers.set(HttpHeaders.cookieHeader, fixture.cookie);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.forbidden);
      await response.drain<void>();
      final uri = other.origin;
      await other.close();
      await expectLater(
        fixture.httpClient.getUrl(uri).then((request) => request.close()),
        throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
      );
      await other.close();
    },
  );
}

class _Fixture {
  _Fixture(this.server, this.client, this.proxy);

  final HttpServer server;
  final ProxmoxClient client;
  final ProxmoxConsoleProxy proxy;
  final HttpClient httpClient = HttpClient();
  Future<void> Function(HttpRequest)? handle;
  int forwardedRequests = 0;

  String get upstreamOrigin => client.origin;
  String get cookie => '${proxy.authCookieName}=${proxy.authCookie}';

  static Future<_Fixture> create(ProxmoxAuthMode mode) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    _Fixture? fixture;
    server.listen((request) async {
      if (request.uri.path == '/api2/json/access/ticket' ||
          request.uri.path == '/api2/json/access/permissions') {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': {
              'ticket': 'PVE:root@pam:test',
              'CSRFPreventionToken': 'csrf-token',
            },
          }),
        );
        await request.response.close();
        return;
      }
      fixture!.forwardedRequests++;
      final handle = fixture.handle;
      if (handle == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } else {
        await handle(request);
      }
    });
    final client = ProxmoxClient(
      origin: 'http://${server.address.address}:${server.port}',
      username: 'root',
      password: 'secret',
      authMode: mode,
      apiTokenId: 'mobile',
      apiTokenSecret: 'token-secret',
    );
    addTearDown(client.close);
    await client.login();
    final proxy = await ProxmoxConsoleProxy.start(client);
    addTearDown(proxy.close);
    fixture = _Fixture(server, client, proxy);
    addTearDown(() => fixture!.httpClient.close(force: true));
    return fixture;
  }

  void expectAuthentication(HttpRequest request) {
    expect(
      request.headers.value(HttpHeaders.hostHeader),
      '${server.address.address}:${server.port}',
    );
    if (client.usesApiToken) {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'PVEAPIToken=root@pam!mobile=token-secret',
      );
      expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
      expect(request.headers.value('CSRFPreventionToken'), isNull);
    } else {
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(
        request.headers.value(HttpHeaders.cookieHeader),
        'PVEAuthCookie=PVE:root@pam:test',
      );
      expect(request.headers.value('CSRFPreventionToken'), 'csrf-token');
    }
  }

  Future<HttpClientResponse> request(
    String path, {
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    bool followRedirects = true,
  }) async {
    final request = await httpClient.openUrl(
      method,
      proxy.origin.resolve(path),
    );
    request.followRedirects = followRedirects;
    request.headers.set(HttpHeaders.cookieHeader, cookie);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    return request.close();
  }
}
