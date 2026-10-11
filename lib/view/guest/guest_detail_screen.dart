import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/core/settings/auto_refresh_mixin.dart';
import 'package:pve_manager/data/models/guest_action.dart';
import 'package:pve_manager/data/models/guest_rrd_point.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/data/services/remote_console_launcher.dart';
import 'package:pve_manager/core/utils/formatters.dart';
import 'package:pve_manager/core/widgets/status_pill.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';
import 'package:pve_manager/core/widgets/performance_history_card.dart';
import 'package:pve_manager/view/guest/guest_config_screen.dart';
import 'package:pve_manager/view/local_terminal_screen.dart';

class GuestDetailScreen extends StatefulWidget {
  const GuestDetailScreen({
    required this.client,
    required this.guest,
    required this.autoRefreshIntervalListenable,
    this.embedded = false,
    this.onActionCompleted,
    this.onOpenConfig,
    super.key,
  });

  final ProxmoxClient client;
  final PveResource guest;
  final ValueListenable<Duration> autoRefreshIntervalListenable;
  final bool embedded;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onOpenConfig;

  @override
  State<GuestDetailScreen> createState() => _GuestDetailScreenState();
}

class _GuestDetailScreenState extends State<GuestDetailScreen>
    with AutoRefreshMixin<GuestDetailScreen> {
  late PveResource _guest;
  late Future<List<GuestRrdPoint>> _historyFuture;
  bool _isRefreshing = false;
  bool _isHistoryLoading = false;
  int _historyGeneration = 0;
  bool _isGuestStatusRefreshing = false;
  bool _isActionRunning = false;
  int _guestStatusGeneration = 0;
  List<GuestRrdPoint>? _lastHistory;
  String _timeframe = 'hour';

  static const _timeframes = <String>['hour', 'day', 'week', 'month', 'year'];

  @override
  void initState() {
    super.initState();
    _guest = widget.client.applyCachedGuestDiskUsage(widget.guest);
    _historyFuture = _loadHistory();
    unawaited(_refreshGuestStatus(notifyStart: false));
  }

  @override
  void didUpdateWidget(GuestDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guest.id != widget.guest.id ||
        oldWidget.guest.node != widget.guest.node ||
        oldWidget.client != widget.client) {
      _guestStatusGeneration++;
      _isGuestStatusRefreshing = false;
      _isRefreshing = false;
      _guest = widget.client.applyCachedGuestDiskUsage(widget.guest);
      _lastHistory = null;
      _historyFuture = _loadHistory();
      unawaited(_refreshGuestStatus(notifyStart: false));
    }
  }

  @override
  ValueListenable<Duration> get autoRefreshIntervalListenable =>
      widget.autoRefreshIntervalListenable;

  @override
  Future<void> onAutoRefresh() => _refreshData();

  Future<List<GuestRrdPoint>> _loadHistory() async {
    final generation = ++_historyGeneration;
    _isHistoryLoading = true;
    try {
      final history = await widget.client.getGuestRrdData(
        _guest,
        timeframe: _timeframe,
      );
      if (mounted && generation == _historyGeneration) {
        _lastHistory = history;
      }
      return history;
    } finally {
      if (generation == _historyGeneration) {
        _isHistoryLoading = false;
      }
    }
  }

  Future<void> _refreshData() async {
    if (!mounted || _isRefreshing || _isHistoryLoading) {
      return;
    }

    _isRefreshing = true;
    final historyFuture = _loadHistory();
    final generation = _historyGeneration;
    setState(() {
      _historyFuture = historyFuture;
    });

    try {
      await Future.wait<Object?>([historyFuture, _refreshGuestStatus()]);
    } on Object {
      // FutureBuilder renders the error when there is no cached history.
    } finally {
      if (mounted && generation == _historyGeneration) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _refreshGuestStatus({bool notifyStart = true}) async {
    if (_isGuestStatusRefreshing) {
      return;
    }

    final generation = ++_guestStatusGeneration;
    _isGuestStatusRefreshing = true;
    if (notifyStart && mounted) {
      setState(() {});
    }

    try {
      final guest = await widget.client.getGuestCurrentStatus(_guest);
      if (mounted && generation == _guestStatusGeneration) {
        setState(() {
          _guest = guest;
        });
      }
    } on Object {
      // Keep the last visible resource usage if a refresh fails.
    } finally {
      if (mounted && generation == _guestStatusGeneration) {
        setState(() {
          _isGuestStatusRefreshing = false;
        });
      }
    }
  }

  void _setTimeframe(String value) {
    if (_timeframe == value) {
      return;
    }

    setState(() {
      _timeframe = value;
      _isRefreshing = false;
      _historyFuture = _loadHistory();
    });
  }

  Future<void> _openConsole() async {
    final guest = widget.guest;
    final l10n = context.l10n;
    try {
      if (guest.type == 'lxc') {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LocalTerminalScreen.guest(
              title: l10n.terminalTitle(guest.name),
              client: widget.client,
              guest: guest,
            ),
          ),
        );
        return;
      }

      await RemoteConsoleLauncher.open(
        context: context,
        title: guest.type == 'qemu'
            ? l10n.vncTitle(guest.name)
            : l10n.terminalTitle(guest.name),
        client: widget.client,
        uri: widget.client.guestConsoleUri(guest),
        l10n: l10n,
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(l10n, error))));
    }
  }

  Future<void> _showPowerActions() async {
    final action = await showModalBottomSheet<GuestAction>(
      context: context,
      useRootNavigator: widget.embedded,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: GuestAction.values.map((action) {
            return ListTile(
              leading: Icon(action.icon),
              title: Text(action.localizedLabel(context.l10n)),
              onTap: () => Navigator.of(context).pop(action),
            );
          }).toList(),
        ),
      ),
    );

    if (action != null && mounted) {
      await _runAction(action);
    }
  }

  Future<void> _openConfig() async {
    final onOpenConfig = widget.onOpenConfig;
    if (widget.embedded && onOpenConfig != null) {
      onOpenConfig();
      return;
    }

    await Navigator.of(context, rootNavigator: widget.embedded).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            GuestConfigScreen(client: widget.client, guest: widget.guest),
      ),
    );
    if (mounted) {
      await _refreshData();
    }
  }

  Future<void> _runAction(GuestAction action) async {
    setState(() {
      _isActionRunning = true;
    });

    try {
      await widget.client.executeGuestAction(widget.guest, action);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.guestActionSent(
              widget.guest.name,
              action.localizedLabel(context.l10n),
            ),
          ),
        ),
      );
      if (widget.embedded) {
        widget.onActionCompleted?.call();
        await _refreshData();
      } else {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isActionRunning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guest = _guest;
    final l10n = context.l10n;
    final isDiskUsageLoading = _isDiskUsageLoading(
      guest,
      isGuestStatusRefreshing: _isGuestStatusRefreshing,
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(guest.name),
        actions: [
          IconButton(
            tooltip: l10n.hardwareConfig,
            onPressed: _openConfig,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: l10n.powerActions,
            onPressed: _isActionRunning ? null : _showPowerActions,
            icon: const Icon(Icons.power_settings_new_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Icon(
                          guest.type == 'qemu'
                              ? Icons.desktop_windows_rounded
                              : Icons.inventory_2_rounded,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              guest.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${localizedResourceType(l10n, guest.type)} '
                              '${guest.vmid} · ${guest.node}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(status: guest.status),
                    ],
                  ),
                  const SizedBox(height: 20),
                  UsageLine(
                    label: 'CPU',
                    value: guest.cpu,
                    text: percent(guest.cpu),
                  ),
                  const SizedBox(height: 14),
                  UsageLine(
                    label: l10n.memory,
                    value: guest.memoryRatio,
                    text:
                        '${bytes(guest.memoryUsed)} / ${bytes(guest.memoryTotal)}',
                  ),
                  const SizedBox(height: 14),
                  UsageLine(
                    label: l10n.disk,
                    value: guest.diskRatio,
                    text: isDiskUsageLoading
                        ? ''
                        : '${bytes(guest.diskUsed)} / ${bytes(guest.diskTotal)}',
                    isLoading: isDiskUsageLoading,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.tonalIcon(
                onPressed: _openConsole,
                icon: Icon(
                  guest.type == 'qemu'
                      ? Icons.desktop_windows_rounded
                      : Icons.terminal_rounded,
                ),
                label: Text(
                  guest.type == 'qemu'
                      ? l10n.openRemoteVnc
                      : l10n.openRemoteTerminal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GuestTimeframeSelector(
            values: _timeframes,
            selected: _timeframe,
            onSelected: _setTimeframe,
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<GuestRrdPoint>>(
            key: ValueKey((widget.client, widget.guest.id, widget.guest.node)),
            future: _historyFuture,
            builder: (context, snapshot) {
              final points = snapshot.data ?? _lastHistory;
              if (snapshot.connectionState == ConnectionState.waiting &&
                  points == null) {
                return const Card(
                  child: SizedBox(
                    height: 212,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }

              if (snapshot.hasError && points == null) {
                return Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(localizedError(l10n, snapshot.error!)),
                  ),
                );
              }

              final historyPoints = points!;
              return PerformanceHistoryCard(
                points: historyPoints
                    .map(
                      (point) => PerformanceHistoryPoint(
                        time: point.time,
                        cpu: point.cpu,
                        memoryUsed: point.memoryUsed,
                        memoryTotal: point.memoryTotal,
                        netIn: point.netIn,
                        netOut: point.netOut,
                        diskRead: point.diskRead,
                        diskWrite: point.diskWrite,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

bool _isDiskUsageLoading(
  PveResource guest, {
  required bool isGuestStatusRefreshing,
}) {
  return guest.type == 'qemu' &&
      guest.status == 'running' &&
      guest.diskUsed <= 0 &&
      isGuestStatusRefreshing;
}

class _GuestTimeframeSelector extends StatelessWidget {
  const _GuestTimeframeSelector({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((value) {
            final active = value == selected;
            final label = _timeframeLabel(context, value);
            return SizedBox(
              width: 92,
              child: active
                  ? FilledButton.tonal(
                      onPressed: () => onSelected(value),
                      child: Text(label),
                    )
                  : OutlinedButton(
                      onPressed: () => onSelected(value),
                      child: Text(label),
                    ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _timeframeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'hour' => l10n.timeframeHour,
      'day' => l10n.timeframeDay,
      'week' => l10n.timeframeWeek,
      'month' => l10n.timeframeMonth,
      'year' => l10n.timeframeYear,
      _ => value,
    };
  }
}
