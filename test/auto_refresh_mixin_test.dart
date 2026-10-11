import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/settings/auto_refresh_mixin.dart';

void main() {
  testWidgets('polling pauses in background and resumes in foreground', (
    tester,
  ) async {
    final interval = ValueNotifier(const Duration(seconds: 5));
    addTearDown(interval.dispose);
    var calls = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: _PollingPage(interval: interval, refresh: () async => calls++),
      ),
    );

    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slow requests are not duplicated and disposal stops polling', (
    tester,
  ) async {
    final interval = ValueNotifier(const Duration(seconds: 5));
    addTearDown(interval.dispose);
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _PollingPage(
          interval: interval,
          refresh: () {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
  });

  testWidgets('replacing settings detaches old notifier and honors interval', (
    tester,
  ) async {
    final original = ValueNotifier(const Duration(seconds: 5));
    final replacement = ValueNotifier(const Duration(seconds: 10));
    addTearDown(original.dispose);
    addTearDown(replacement.dispose);
    var calls = 0;
    Widget app(ValueListenable<Duration> interval) => MaterialApp(
      home: _PollingPage(interval: interval, refresh: () async => calls++),
    );
    await tester.pumpWidget(app(original));
    await tester.pumpWidget(app(replacement));
    original.value = const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    replacement.value = Duration.zero;
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    replacement.value = const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
  });

  testWidgets('covered pages do not poll', (tester) async {
    final interval = ValueNotifier(const Duration(seconds: 5));
    addTearDown(interval.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _PollingPage(interval: interval, refresh: () async => calls++),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _PollingPage extends StatefulWidget {
  const _PollingPage({required this.interval, required this.refresh});

  final ValueListenable<Duration> interval;
  final Future<void> Function() refresh;

  @override
  State<_PollingPage> createState() => _PollingPageState();
}

class _PollingPageState extends State<_PollingPage>
    with AutoRefreshMixin<_PollingPage> {
  @override
  ValueListenable<Duration> get autoRefreshIntervalListenable =>
      widget.interval;

  @override
  Future<void> onAutoRefresh() => widget.refresh();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('polling'));
}
