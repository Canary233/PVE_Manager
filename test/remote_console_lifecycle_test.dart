import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/remote_console_screen.dart';

void main() {
  testWidgets('retry releases a partially initialized WebView', (tester) async {
    final runtime = _WebviewRuntime(tester, failFirstSetup: true);
    addTearDown(runtime.reset);
    await tester.pumpWidget(_screen());
    await tester.pump();
    expect(find.text('Console failed: setup failed'), findsOneWidget);

    final retry = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    await tester.runAsync(() async {
      retry();
      retry();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    for (var i = 0; i < 4 && runtime.initializations < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(runtime.initializations, 2);
    expect(runtime.disposals, [1]);
    expect(runtime.loadedUrls, ['https://[2001:db8::1]:8006/console']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(runtime.disposals, [1, 2]);
  });

  testWidgets(
    'closing during native initialization releases the late WebView',
    (tester) async {
      final initialization = Completer<void>();
      final runtime = _WebviewRuntime(
        tester,
        initialization: initialization.future,
      );
      addTearDown(runtime.reset);
      await tester.pumpWidget(_screen());
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());

      initialization.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(runtime.disposals, [1]);
      expect(runtime.loadedUrls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authentication bootstrap matches the full IPv6 origin', (
    tester,
  ) async {
    final runtime = _WebviewRuntime(tester);
    addTearDown(runtime.reset);
    await tester.pumpWidget(_screen());
    await tester.pump();

    expect(runtime.scripts.single, contains('location.origin.toLowerCase()'));
    expect(runtime.scripts.single, contains('"https://[2001:db8::1]:8006"'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  });
}

Widget _screen() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: RemoteConsoleScreen(
    title: 'Console',
    uri: Uri.parse('https://[2001:db8::1]:8006/console'),
    authCookie: 'ticket',
    ignoreCertificateErrors: false,
    loadFailedTemplate: 'Console failed: {description}',
    unknownErrorMessage: 'Unknown error',
    certificateErrorMessage: 'Certificate error',
    errorHint: 'Try again',
  ),
);

class _WebviewRuntime {
  _WebviewRuntime(
    this.tester, {
    this.failFirstSetup = false,
    this.initialization,
  }) {
    _mock(const MethodChannel('io.jns.webview.win'), (call) async {
      if (call.method == 'initialize') {
        final id = ++initializations;
        await initialization;
        _mock(
          MethodChannel('io.jns.webview.win/$id/events'),
          (_) async => null,
        );
        _mock(MethodChannel('io.jns.webview.win/$id'), (call) async {
          if (call.method == 'setPopupWindowPolicy' &&
              failFirstSetup &&
              id == 1) {
            throw PlatformException(code: 'setup', message: 'setup failed');
          }
          if (call.method == 'addScriptToExecuteOnDocumentCreated') {
            scripts.add(call.arguments as String);
            return 'script-$id';
          }
          if (call.method == 'loadUrl') {
            loadedUrls.add(call.arguments as String);
          }
          return null;
        });
        return {'textureId': id};
      }
      if (call.method == 'dispose') {
        disposals.add(call.arguments as int);
      }
      return null;
    });
  }

  final WidgetTester tester;
  final bool failFirstSetup;
  final Future<void>? initialization;
  final _channels = <MethodChannel>[];
  final disposals = <int>[];
  final loadedUrls = <String>[];
  final scripts = <String>[];
  int initializations = 0;

  void _mock(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
    _channels.add(channel);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      handler,
    );
  }

  void reset() {
    for (final channel in _channels) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  }
}
