import 'package:shared_preferences/shared_preferences.dart';

import 'package:pve_manager/core/settings/auto_refresh_settings.dart';

class AppSettingsRepository {
  AppSettingsRepository._();

  static final AppSettingsRepository instance = AppSettingsRepository._();

  static const _autoRefreshSecondsKey = 'auto_refresh_seconds';
  Future<void> _pendingOperation = Future<void>.value();

  Future<Duration> getAutoRefreshInterval() =>
      _runExclusive(_getAutoRefreshInterval);

  Future<Duration> _getAutoRefreshInterval() async {
    final preferences = await SharedPreferences.getInstance();
    final seconds = preferences.get(_autoRefreshSecondsKey);
    if (seconds is! int) {
      return defaultAutoRefreshInterval;
    }

    final interval = Duration(seconds: seconds);
    if (!autoRefreshIntervalOptions.contains(interval)) {
      return defaultAutoRefreshInterval;
    }

    return interval;
  }

  Future<void> setAutoRefreshInterval(Duration interval) =>
      _runExclusive(() => _setAutoRefreshInterval(interval));

  Future<void> _setAutoRefreshInterval(Duration interval) async {
    if (!autoRefreshIntervalOptions.contains(interval)) {
      throw ArgumentError.value(interval, 'interval', 'Unsupported interval.');
    }
    final preferences = await SharedPreferences.getInstance();
    try {
      final saved = await preferences.setInt(
        _autoRefreshSecondsKey,
        interval.inSeconds,
      );
      if (!saved) {
        throw StateError('Failed to save the auto-refresh interval.');
      }
    } on Object {
      // SharedPreferences changes its cache before the platform write finishes.
      // A rejected write must not be reported as saved on the next read.
      try {
        await preferences.reload();
      } on Object {
        // Preserve the original write failure if the platform is unavailable.
      }
      rethrow;
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _pendingOperation.then((_) => operation());
    _pendingOperation = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
