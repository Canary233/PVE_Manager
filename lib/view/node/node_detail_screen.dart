import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/core/settings/auto_refresh_mixin.dart';
import 'package:pve_manager/data/models/node_power_action.dart';
import 'package:pve_manager/data/models/node_rrd_point.dart';
import 'package:pve_manager/data/models/node_status.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/core/utils/formatters.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';
import 'package:pve_manager/core/widgets/performance_history_card.dart';
import 'package:pve_manager/view/local_terminal_screen.dart';
import 'package:pve_manager/view/node/node_tasks_logs_screen.dart';

class NodeDetailScreen extends StatefulWidget {
  const NodeDetailScreen({
    required this.client,
    required this.node,
    required this.autoRefreshIntervalListenable,
    this.embedded = false,
    super.key,
  });

  final ProxmoxClient client;
  final PveNode node;
  final ValueListenable<Duration> autoRefreshIntervalListenable;
  final bool embedded;

  @override
  State<NodeDetailScreen> createState() => _NodeDetailScreenState();
}

class _NodeDetailScreenState extends State<NodeDetailScreen>
    with AutoRefreshMixin<NodeDetailScreen> {
  late Future<_NodeDetailData> _detailFuture;
  bool _isDetailLoading = false;
  int _detailGeneration = 0;
  bool _isExtendedThermalLoading = false;
  int _extendedThermalGeneration = 0;
  _NodeDetailData? _lastDetailData;
  NodeThermalState? _extendedThermalState;
  String _timeframe = 'hour';

  static const _timeframes = <String>['hour', 'day', 'week', 'month', 'year'];

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetailTracked();
  }

  @override
  void didUpdateWidget(NodeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.name != widget.node.name ||
        oldWidget.client != widget.client) {
      _extendedThermalGeneration++;
      _isExtendedThermalLoading = false;
      _extendedThermalState = null;
      _lastDetailData = null;
      _detailFuture = _loadDetailTracked();
    }
  }

  @override
  ValueListenable<Duration> get autoRefreshIntervalListenable =>
      widget.autoRefreshIntervalListenable;

  @override
  Future<void> onAutoRefresh() => _refresh();

  Future<_NodeDetailData> _loadDetail(int generation) async {
    final client = widget.client;
    final node = widget.node.name;
    final results = await Future.wait<Object>([
      client.getNodeStatus(node),
      client.getNodeRrdData(node, timeframe: _timeframe),
    ]);
    final status = results[0] as NodeStatus;
    if (!mounted || generation != _detailGeneration) {
      return _NodeDetailData(
        status: status,
        thermalState: status.thermalState,
        rrdPoints: results[1] as List<NodeRrdPoint>,
      );
    }
    final cachedExtendedThermalState = widget.client.cachedNodeThermalState(
      widget.node.name,
    );
    if (cachedExtendedThermalState != null) {
      _extendedThermalState = cachedExtendedThermalState;
    }
    final thermalState =
        _extendedThermalState == null || _extendedThermalState!.isEmpty
        ? status.thermalState
        : _extendedThermalState!;

    final detail = _NodeDetailData(
      status: status,
      thermalState: thermalState,
      rrdPoints: results[1] as List<NodeRrdPoint>,
    );
    _lastDetailData = detail;
    _loadExtendedThermalStateInBackground(thermalState);
    return detail;
  }

  Future<_NodeDetailData> _loadDetailTracked() async {
    final generation = ++_detailGeneration;
    _isDetailLoading = true;
    try {
      return await _loadDetail(generation);
    } finally {
      if (generation == _detailGeneration) {
        _isDetailLoading = false;
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _isDetailLoading) {
      return;
    }

    final future = _loadDetailTracked();
    setState(() {
      _detailFuture = future;
    });

    try {
      await future;
    } on Object {
      // FutureBuilder renders the error state when there is no cached detail.
    }
  }

  void _loadExtendedThermalStateInBackground(
    NodeThermalState visibleThermalState,
  ) {
    if (_isExtendedThermalLoading ||
        (widget.client.cachedNodeThermalState(widget.node.name) != null &&
            !_shouldLoadExtendedThermalState(visibleThermalState))) {
      return;
    }

    _isExtendedThermalLoading = true;
    final generation = ++_extendedThermalGeneration;
    unawaited(_loadExtendedThermalState(generation));
  }

  Future<void> _loadExtendedThermalState(int generation) async {
    try {
      final extendedThermalState = await widget.client.getNodeThermalState(
        widget.node.name,
      );
      if (!mounted ||
          generation != _extendedThermalGeneration ||
          extendedThermalState.isEmpty) {
        return;
      }

      _extendedThermalState = extendedThermalState;
      final lastDetailData = _lastDetailData;
      if (lastDetailData != null && !_isDetailLoading) {
        final updatedDetailData = lastDetailData.copyWith(
          thermalState: extendedThermalState,
        );
        _lastDetailData = updatedDetailData;
        _detailFuture = Future<_NodeDetailData>.value(updatedDetailData);
      }
    } on Object {
      // Extended SMART temperatures are best-effort and should not block details.
    } finally {
      if (mounted && generation == _extendedThermalGeneration) {
        setState(() {
          _isExtendedThermalLoading = false;
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
      _detailFuture = _loadDetailTracked();
    });
  }

  Future<void> _openTasksLogs() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            NodeTasksLogsScreen(client: widget.client, node: widget.node),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openTerminal() async {
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LocalTerminalScreen.node(
            title: context.l10n.terminalTitle(widget.node.name),
            client: widget.client,
            node: widget.node.name,
          ),
        ),
      );
      if (mounted) {
        await _refresh();
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    }
  }

  Future<void> _showPowerActions() async {
    final action = await showModalBottomSheet<NodePowerAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: NodePowerAction.values.map((action) {
            final label = action.localizedLabel(context.l10n);
            return ListTile(
              leading: Icon(action.icon),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(action),
            );
          }).toList(),
        ),
      ),
    );

    if (action == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final label = action.localizedLabel(context.l10n);
        return AlertDialog(
          title: Text(label),
          content: Text(context.l10n.nodePowerConfirm(widget.node.name, label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.confirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.client.executeNodePowerAction(widget.node.name, action);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.powerRequestSent(action.localizedLabel(context.l10n)),
          ),
        ),
      );
      await _refresh();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context.l10n, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(l10n.nodeDetails),
        actions: [
          IconButton(
            tooltip: l10n.tasksAndLogs,
            onPressed: _openTasksLogs,
            icon: const Icon(Icons.list_rounded),
          ),
          IconButton(
            tooltip: l10n.terminal,
            onPressed: _openTerminal,
            icon: const Icon(Icons.terminal_rounded),
          ),
          IconButton(
            tooltip: l10n.power,
            onPressed: _showPowerActions,
            icon: const Icon(Icons.power_settings_new_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_NodeDetailData>(
        key: ValueKey((widget.client, widget.node.name)),
        future: _detailFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? _lastDetailData;
          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && data == null) {
            return ErrorState(
              message: localizedError(l10n, snapshot.error!),
              onRetry: _refresh,
            );
          }

          final detailData = data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SystemInfoCard(
                  status: detailData.status,
                  thermalState: detailData.thermalState,
                  isDiskDetailsLoading:
                      _isExtendedThermalLoading &&
                      _shouldLoadExtendedThermalState(detailData.thermalState),
                ),
                const SizedBox(height: 16),
                _ResourceUsageCard(status: detailData.status),
                const SizedBox(height: 16),
                _TimeframeSelector(
                  values: _timeframes,
                  selected: _timeframe,
                  onSelected: _setTimeframe,
                ),
                const SizedBox(height: 16),
                PerformanceHistoryCard(
                  showDiskIo: false,
                  points: detailData.rrdPoints
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

bool _shouldLoadExtendedThermalState(NodeThermalState thermalState) {
  if (thermalState.isEmpty) {
    return true;
  }

  final diskTemperatures = thermalState.diskTemperatures;
  if (diskTemperatures.isEmpty) {
    return true;
  }

  return !diskTemperatures.any(
    (disk) => disk.type == NodeDiskTemperatureType.sata,
  );
}

class _NodeDetailData {
  const _NodeDetailData({
    required this.status,
    required this.thermalState,
    required this.rrdPoints,
  });

  final NodeStatus status;
  final NodeThermalState thermalState;
  final List<NodeRrdPoint> rrdPoints;

  _NodeDetailData copyWith({NodeThermalState? thermalState}) {
    return _NodeDetailData(
      status: status,
      thermalState: thermalState ?? this.thermalState,
      rrdPoints: rrdPoints,
    );
  }
}

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard({
    required this.status,
    required this.thermalState,
    required this.isDiskDetailsLoading,
  });

  final NodeStatus status;
  final NodeThermalState thermalState;
  final bool isDiskDetailsLoading;

  @override
  Widget build(BuildContext context) {
    final cpuInfo = status.cpuInfo;
    final l10n = context.l10n;
    final cpuModel = cpuInfo?.model;
    final loadAverage = status.loadAverage.isEmpty
        ? '-'
        : status.loadAverage
              .take(3)
              .map((value) => value.toStringAsFixed(2))
              .join('  ');
    final diskTemperatures = thermalState.diskTemperatures;

    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title: l10n.systemInfo),
          const SizedBox(height: 20),
          if (cpuModel != null)
            _InfoRow(label: l10n.processor, value: cpuModel),
          _InfoRow(
            label: l10n.cpuCores,
            value: l10n.cpuCoresValue(
              cpuInfo?.cores ?? 0,
              cpuInfo?.cpus ?? 0,
              cpuInfo?.sockets ?? 0,
            ),
          ),
          _InfoRow(label: l10n.pveVersion, value: status.pveVersion ?? '-'),
          _InfoRow(
            label: l10n.kernelVersion,
            value: status.kernelVersion ?? '-',
          ),
          _InfoRow(label: l10n.uptime, value: uptime(l10n, status.uptime)),
          _InfoRow(label: l10n.loadAverage, value: loadAverage),
          _InfoRow(
            label: l10n.cpuFrequencyGhz,
            value: _formatCpuFrequency(l10n, cpuInfo),
          ),
          _InfoRow(
            label: l10n.cpuTemperature,
            value: _formatCpuTemperature(l10n, thermalState),
          ),
          _DiskTemperatureRows(
            diskTemperatures: diskTemperatures,
            isLoading: isDiskDetailsLoading,
          ),
        ],
      ),
    );
  }
}

class _DiskTemperatureRows extends StatelessWidget {
  const _DiskTemperatureRows({
    required this.diskTemperatures,
    required this.isLoading,
  });

  final List<NodeDiskTemperature> diskTemperatures;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visibleDiskTemperatures = isLoading
        ? const <NodeDiskTemperature>[]
        : diskTemperatures;
    final rows = <Widget>[
      ...visibleDiskTemperatures.map(
        (disk) => _DiskTemperatureRow(
          label: _diskTemperatureLabel(l10n, disk),
          value: l10n.temperatureValue(disk.formatTemperature()),
        ),
      ),
      if (isLoading) _DiskDetailsLoadingRow(label: l10n.disk),
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey<String>(_diskRowsKey(visibleDiskTemperatures, isLoading)),
        children: rows,
      ),
    );
  }
}

String _diskRowsKey(
  List<NodeDiskTemperature> diskTemperatures,
  bool isLoading,
) {
  final rowsKey = diskTemperatures
      .map((disk) => '${disk.type.name}:${disk.index}:${disk.model ?? ''}')
      .join('|');
  return '$isLoading:$rowsKey';
}

String _formatCpuFrequency(AppLocalizations l10n, CpuInfo? cpuInfo) {
  final mhz = cpuInfo?.mhz;
  if (mhz == null || mhz <= 0) {
    return '-';
  }

  final ghz = (mhz / 1000).toStringAsFixed(2);
  final cores = cpuInfo?.cores ?? 0;
  if (cores > 0) {
    return l10n.cpuFrequencyValue(cores, ghz);
  }
  return l10n.cpuFrequencyCurrentValue(ghz);
}

String _formatCpuTemperature(
  AppLocalizations l10n,
  NodeThermalState thermalState,
) {
  final values = <String>[];
  final packageSensor = thermalState.cpuPackageSensor;
  if (packageSensor != null) {
    values.add(l10n.cpuPackageTemperature(packageSensor.formatTemperature()));
  }

  final coreSensors = thermalState.cpuCoreSensors;
  if (coreSensors.isNotEmpty) {
    final coreTemperatures = coreSensors.map((sensor) => sensor.celsius);
    final average =
        coreTemperatures.reduce((sum, value) => sum + value) /
        coreSensors.length;
    final min = coreTemperatures.reduce((a, b) => a < b ? a : b);
    final max = coreTemperatures.reduce((a, b) => a > b ? a : b);
    values.add(
      l10n.cpuCoreTemperature(
        NodeTemperatureSensor(
          label: 'Temperature',
          celsius: average,
        ).formatTemperature(),
        '${NodeTemperatureSensor(label: 'Temperature', celsius: min).formatTemperature()}~'
        '${NodeTemperatureSensor(label: 'Temperature', celsius: max).formatTemperature()}',
      ),
    );
  }

  if (values.isEmpty) {
    final primarySensor = thermalState.primaryCpuSensor;
    if (primarySensor == null) {
      return '-';
    }
    return l10n.temperatureValue(primarySensor.formatTemperature());
  }

  return values.join(' | ');
}

String _diskTemperatureLabel(AppLocalizations l10n, NodeDiskTemperature disk) {
  final model = disk.model?.trim();
  if (model != null && model.isNotEmpty) {
    return model;
  }

  return switch (disk.type) {
    NodeDiskTemperatureType.nvme => l10n.nvmeDiskLabel(disk.index),
    NodeDiskTemperatureType.sata => l10n.sataDiskLabel(disk.index),
    NodeDiskTemperatureType.ssd => l10n.solidStateDiskLabel(disk.index),
  };
}

class _ResourceUsageCard extends StatelessWidget {
  const _ResourceUsageCard({required this.status});

  final NodeStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(title: l10n.resourceUsage),
          const SizedBox(height: 20),
          UsageLine(label: 'CPU', value: status.cpu, text: percent(status.cpu)),
          const SizedBox(height: 18),
          UsageLine(
            label: l10n.memory,
            value: status.memoryRatio,
            text: '${bytes(status.memoryUsed)} / ${bytes(status.memoryTotal)}',
          ),
          const SizedBox(height: 18),
          UsageLine(
            label: l10n.swap,
            value: status.swapRatio,
            text: '${bytes(status.swapUsed)} / ${bytes(status.swapTotal)}',
          ),
          const SizedBox(height: 18),
          UsageLine(
            label: l10n.rootPartition,
            value: status.rootRatio,
            text: '${bytes(status.rootUsed)} / ${bytes(status.rootTotal)}',
          ),
        ],
      ),
    );
  }
}

class _TimeframeSelector extends StatelessWidget {
  const _TimeframeSelector({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
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

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiskTemperatureRow extends StatelessWidget {
  const _DiskTemperatureRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: labelStyle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.right,
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}

class _DiskDetailsLoadingRow extends StatelessWidget {
  const _DiskDetailsLoadingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
