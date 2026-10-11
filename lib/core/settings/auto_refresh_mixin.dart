import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Polls only while the app is active and this page is visible.
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  ValueListenable<Duration> get autoRefreshIntervalListenable;

  Future<void> onAutoRefresh();

  late ValueListenable<Duration> _intervalListenable;
  late final AppLifecycleListener _lifecycleListener;
  Timer? _autoRefreshTimer;
  bool _autoRefreshRunning = false;

  @override
  void initState() {
    super.initState();
    _intervalListenable = autoRefreshIntervalListenable;
    _intervalListenable.addListener(_restartAutoRefresh);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (_) => _restartAutoRefresh(),
    );
    _restartAutoRefresh();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_intervalListenable, autoRefreshIntervalListenable)) {
      _intervalListenable.removeListener(_restartAutoRefresh);
      _intervalListenable = autoRefreshIntervalListenable;
      _intervalListenable.addListener(_restartAutoRefresh);
      _restartAutoRefresh();
    }
  }

  void _restartAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final interval = _intervalListenable.value;
    if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        interval <= Duration.zero) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (!mounted ||
        _autoRefreshRunning ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _autoRefreshRunning = true;
    try {
      await onAutoRefresh();
    } finally {
      _autoRefreshRunning = false;
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _intervalListenable.removeListener(_restartAutoRefresh);
    _lifecycleListener.dispose();
    super.dispose();
  }
}
