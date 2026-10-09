import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/data/services/remote_console_launcher.dart';
import 'package:pve_manager/l10n/generated/app_localizations_en.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'API token console stays alive until the native activity exits',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('pve_manager/remote_console');
      final opened = Completer<Map<String, dynamic>>();
      final closed = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'open');
        opened.complete(Map<String, dynamic>.from(call.arguments as Map));
        await closed.future;
        return null;
      });
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      });

      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final browser = HttpClient();
        final client = ProxmoxClient(
          origin: 'http://${server.address.address}:${server.port}',
          username: 'root',
          password: '',
          authMode: ProxmoxAuthMode.apiToken,
          apiTokenId: 'mobile',
          apiTokenSecret: 'token-secret',
        );
        server.listen((request) async {
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'PVEAPIToken=root@pam!mobile=token-secret',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"data":{}}');
          await request.response.close();
        });
        try {
          await client.login();
          var finished = false;
          final opening = RemoteConsoleLauncher.open(
            context: _MountedContext(),
            title: 'Test VM VNC',
            uri: Uri.parse('${client.origin}/?console=kvm&novnc=1'),
            client: client,
            l10n: AppLocalizationsEn(),
          ).whenComplete(() => finished = true);
          final arguments = await opened.future.timeout(
            const Duration(seconds: 3),
          );
          final uri = Uri.parse(arguments['url'] as String);
          expect(uri.host, '127.0.0.1');
          expect(arguments['authCookie'], isNot(contains('token-secret')));
          expect(arguments['authCookieName'], startsWith('PVEConsole_'));
          expect(arguments['ignoreCertificateErrors'], isFalse);
          expect(finished, isFalse);
          final request = await browser.getUrl(uri);
          request.headers.set(
            HttpHeaders.cookieHeader,
            '${arguments['authCookieName']}=${arguments['authCookie']}',
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          expect(jsonDecode(await utf8.decoder.bind(response).join()), {
            'data': {},
          });
          closed.complete();
          await opening;
          expect(finished, isTrue);
          await expectLater(
            browser.getUrl(uri).then((request) => request.close()),
            throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
          );
        } finally {
          if (!closed.isCompleted) {
            closed.complete();
          }
          browser.close(force: true);
          client.close();
          await server.close(force: true);
        }
      }, _RealHttpOverrides());
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}

class _MountedContext implements BuildContext {
  @override
  bool get mounted => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
