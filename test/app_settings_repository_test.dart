import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/settings/auto_refresh_settings.dart';
import 'package:pve_manager/data/repositories/app_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  const storageKey = 'flutter.auto_refresh_seconds';
  final repository = AppSettingsRepository.instance;
  late Map<String, Object> persisted;
  Future<bool> Function(int)? beforeWrite;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted = {};
    beforeWrite = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') {
            return Map<String, Object>.of(persisted);
          }
          if (call.method == 'setInt') {
            final arguments = call.arguments as Map;
            final value = arguments['value'] as int;
            if (await beforeWrite?.call(value) == false) {
              return false;
            }
            persisted[arguments['key'] as String] = value;
            return true;
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  for (final value in [null, '30', true, -1, 0, 7, 30.0]) {
    test('uses the default for invalid saved interval $value', () async {
      if (value != null) {
        persisted[storageKey] = value;
      }
      expect(
        await repository.getAutoRefreshInterval(),
        defaultAutoRefreshInterval,
      );
    });
  }

  test('stores and reads every supported interval', () async {
    for (final interval in autoRefreshIntervalOptions) {
      await repository.setAutoRefreshInterval(interval);
      expect(persisted[storageKey], interval.inSeconds);
      expect(await repository.getAutoRefreshInterval(), interval);
    }
  });

  test('rejects unsupported intervals before updating storage', () async {
    await expectLater(
      repository.setAutoRefreshInterval(const Duration(seconds: 7)),
      throwsArgumentError,
    );
    expect(persisted, isEmpty);
  });

  test(
    'reports rejected writes and restores the last persisted value',
    () async {
      persisted[storageKey] = 10;
      beforeWrite = (_) async => false;

      await expectLater(
        repository.setAutoRefreshInterval(const Duration(seconds: 30)),
        throwsStateError,
      );
      expect(
        await repository.getAutoRefreshInterval(),
        const Duration(seconds: 10),
      );

      beforeWrite = null;
      await repository.setAutoRefreshInterval(const Duration(minutes: 1));
      expect(persisted[storageKey], 60);
    },
  );

  test('retains the original platform error after a failed write', () async {
    persisted[storageKey] = 10;
    beforeWrite = (_) async => throw PlatformException(code: 'unavailable');

    await expectLater(
      repository.setAutoRefreshInterval(const Duration(seconds: 30)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
    expect(
      await repository.getAutoRefreshInterval(),
      const Duration(seconds: 10),
    );
  });

  test('persists overlapping writes in invocation order', () async {
    final enteredWrite = Completer<void>();
    final releaseWrite = Completer<void>();
    final writtenValues = <int>[];
    beforeWrite = (value) async {
      writtenValues.add(value);
      if (value == 10) {
        enteredWrite.complete();
        await releaseWrite.future;
      }
      return true;
    };

    final first = repository.setAutoRefreshInterval(
      const Duration(seconds: 10),
    );
    await enteredWrite.future;
    final second = repository.setAutoRefreshInterval(
      const Duration(seconds: 30),
    );
    final read = repository.getAutoRefreshInterval();
    await pumpEventQueue();
    final valuesWhileFirstPending = List<int>.of(writtenValues);
    releaseWrite.complete();
    await Future.wait([first, second]);

    expect(valuesWhileFirstPending, [10]);
    expect(writtenValues, [10, 30]);
    expect(persisted[storageKey], 30);
    expect(await read, const Duration(seconds: 30));
  });
}
