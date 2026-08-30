import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/node_status.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/models/pve_snapshot.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/view/guest/guest_config_screen.dart';
import 'package:pve_manager/view/guest/guest_detail_screen.dart';
import 'package:pve_manager/view/dashboard/widgets/guest_panel.dart';
import 'package:pve_manager/view/node/node_detail_screen.dart';
import 'package:pve_manager/view/storage/storage_detail_screen.dart';
import 'package:pve_manager/view/dashboard/widgets/node_grid.dart';
import 'package:pve_manager/view/dashboard/widgets/section_header.dart';
import 'package:pve_manager/view/dashboard/widgets/storage_list.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.client,
    required this.serverName,
    required this.autoRefreshIntervalListenable,
    super.key,
  });

  final ProxmoxClient client;
  final String serverName;
  final ValueListenable<Duration> autoRefreshIntervalListenable;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const double _splitLayoutWidth = 840;

  late Future<PveSnapshot> _snapshotFuture;
  Timer? _refreshTimer;
  bool _isSnapshotLoading = false;
  PveSnapshot? _lastSnapshot;
  _DashboardSelection? _selection;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshotTracked();
    widget.autoRefreshIntervalListenable.addListener(_startRefreshTimer);
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoRefreshIntervalListenable !=
        widget.autoRefreshIntervalListenable) {
      oldWidget.autoRefreshIntervalListenable.removeListener(
        _startRefreshTimer,
      );
      widget.autoRefreshIntervalListenable.addListener(_startRefreshTimer);
      _startRefreshTimer();
    }
  }

  @override
  void dispose() {
    widget.autoRefreshIntervalListenable.removeListener(_startRefreshTimer);
    _refreshTimer?.cancel();
    widget.client.close();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.autoRefreshIntervalListenable.value, (
      _,
    ) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _refreshSnapshot();
      }
    });
  }

  Future<PveSnapshot> _loadSnapshot() async {
    final initialResults = await Future.wait<Object>([
      _loadResources(),
      _loadNodes(),
      _loadClusterStatus(),
    ]);
    final resourcesResult = initialResults[0] as _ResourcesLoadResult;
    final nodesResult = initialResults[1] as _NodesLoadResult;
    final clusterStatus = initialResults[2] as Map<String, dynamic>;
    final resources = resourcesResult.resources
        .map(widget.client.applyCachedGuestDiskUsage)
        .toList();
    unawaited(widget.client.preloadGuestDiskUsage(resources));
    final baseNodes = nodesResult.nodes;
    widget.client.preloadNodeThermalStates(baseNodes.map((node) => node.name));
    final storagePermissionFuture = resourcesResult.fullResourceAccessDenied
        ? _isStoragePermissionDenied()
        : Future.value(false);
    final loadedNodesFuture = _loadNodeUsage(
      baseNodes,
      skipStatusRequests: nodesResult.permissionDenied,
    );
    final postLoadResults = await Future.wait<Object>([
      storagePermissionFuture,
      loadedNodesFuture,
    ]);
    final storagePermissionDenied = postLoadResults[0] as bool;
    final loadedNodes = postLoadResults[1] as List<PveNode>;

    final snapshot = PveSnapshot(
      nodes: baseNodes,
      resources: resources,
      clusterStatus: clusterStatus,
      nodePermissionDenied: nodesResult.permissionDenied,
      storagePermissionDenied: storagePermissionDenied,
    );
    final snapshotWithNodeUsage = PveSnapshot(
      nodes: loadedNodes,
      resources: snapshot.resources,
      clusterStatus: snapshot.clusterStatus,
      nodePermissionDenied: snapshot.nodePermissionDenied,
      storagePermissionDenied: snapshot.storagePermissionDenied,
    );
    _lastSnapshot = snapshotWithNodeUsage;
    return snapshotWithNodeUsage;
  }

  Future<_ResourcesLoadResult> _loadResources() async {
    try {
      return _ResourcesLoadResult(
        resources: await widget.client.getResources(),
        fullResourceAccessDenied: false,
      );
    } on ProxmoxApiException catch (error) {
      if (!_isPermissionError(error)) {
        rethrow;
      }
      return _ResourcesLoadResult(
        resources: await widget.client.getResources(type: 'vm'),
        fullResourceAccessDenied: true,
      );
    }
  }

  Future<_NodesLoadResult> _loadNodes() async {
    try {
      return _NodesLoadResult(
        nodes: await widget.client.getNodes(),
        permissionDenied: false,
      );
    } on ProxmoxApiException catch (error) {
      if (!_isPermissionError(error)) {
        rethrow;
      }
      return const _NodesLoadResult(nodes: <PveNode>[], permissionDenied: true);
    }
  }

  Future<Map<String, dynamic>> _loadClusterStatus() async {
    try {
      return await widget.client.getClusterStatus();
    } on ProxmoxApiException catch (error) {
      if (!_isPermissionError(error)) {
        rethrow;
      }
      return <String, dynamic>{};
    }
  }

  bool _isPermissionError(ProxmoxApiException error) {
    final statusCode = error.values['statusCode'];
    if (statusCode is num && statusCode == 403) {
      return true;
    }
    return error.message?.toLowerCase().contains('permission check failed') ??
        false;
  }

  Future<bool> _isStoragePermissionDenied() async {
    try {
      await widget.client.canReadStorageConfig();
      return false;
    } on ProxmoxApiException catch (error) {
      if (!_isPermissionError(error)) {
        return false;
      }
      return true;
    }
  }

  Future<List<PveNode>> _loadNodeUsage(
    List<PveNode> nodes, {
    required bool skipStatusRequests,
  }) async {
    if (nodes.isEmpty) {
      return nodes;
    }

    if (skipStatusRequests) {
      return [
        for (final node in nodes) node.copyWith(hasDetailPermission: false),
      ];
    }

    final results = await Future.wait<_NodeStatusLoadResult>(
      nodes.map((node) async {
        try {
          return _NodeStatusLoadResult.success(
            await widget.client.getNodeStatus(node.name),
          );
        } on ProxmoxApiException catch (error) {
          return _isPermissionError(error)
              ? const _NodeStatusLoadResult.permissionDenied()
              : const _NodeStatusLoadResult.failed();
        } on Object {
          return const _NodeStatusLoadResult.failed();
        }
      }),
    );

    return [
      for (var index = 0; index < nodes.length; index++)
        if (results[index].status case final status?)
          nodes[index].copyWith(
            cpu: status.cpu,
            memoryUsed: status.memoryUsed,
            memoryTotal: status.memoryTotal,
            hasDetailPermission: true,
          )
        else if (results[index].permissionDenied)
          nodes[index].copyWith(hasDetailPermission: false)
        else
          nodes[index],
    ];
  }

  Future<PveSnapshot> _loadSnapshotTracked() async {
    _isSnapshotLoading = true;
    try {
      return await _loadSnapshot();
    } finally {
      _isSnapshotLoading = false;
    }
  }

  Future<void> _refreshSnapshot() async {
    if (_isSnapshotLoading) {
      return;
    }

    final future = _loadSnapshotTracked();
    setState(() {
      _snapshotFuture = future;
    });

    try {
      await future;
    } on Object {
      // FutureBuilder renders the error state when there is no cached snapshot.
    }
  }

  void _selectGuest(PveResource guest) {
    setState(() {
      _selection = _DashboardSelection.guest(guest.id);
    });
  }

  void _selectGuestConfig(PveResource guest) {
    setState(() {
      _selection = _DashboardSelection.guestConfig(guest.id);
    });
  }

  void _selectGuestDetail(PveResource guest) {
    setState(() {
      _selection = _DashboardSelection.guest(guest.id);
    });
  }

  Future<void> _openGuestRoute(PveResource guest) async {
    final shouldRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => GuestDetailScreen(
          client: widget.client,
          guest: guest,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
        ),
      ),
    );

    if (shouldRefresh == true && mounted) {
      await _refreshSnapshot();
    }
  }

  void _selectNode(PveNode node) {
    if (!node.hasDetailPermission) {
      return;
    }
    setState(() {
      _selection = _DashboardSelection.node(node.name);
    });
  }

  Future<void> _openNodeRoute(PveNode node) async {
    if (!node.hasDetailPermission) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NodeDetailScreen(
          client: widget.client,
          node: node,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
        ),
      ),
    );
    if (mounted) {
      await _refreshSnapshot();
    }
  }

  void _selectStorage(PveResource storage) {
    setState(() {
      _selection = _DashboardSelection.storage(storage.id);
    });
  }

  Future<void> _openStorageRoute(PveResource storage) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StorageDetailScreen(
          client: widget.client,
          storage: storage,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
        ),
      ),
    );
    if (mounted) {
      await _refreshSnapshot();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(widget.serverName)),
      body: FutureBuilder<PveSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? _lastSnapshot;
          if (snapshot.connectionState == ConnectionState.waiting &&
              data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError && data == null) {
            return ErrorState(
              message: localizedError(l10n, snapshot.error!),
              onRetry: _refreshSnapshot,
            );
          }

          final snapshotData = data!;
          final guests = snapshotData.resources
              .where((item) => item.isGuest)
              .toList();
          final storages = snapshotData.resources
              .where((item) => item.type == 'storage')
              .toList();
          final useSplitLayout =
              MediaQuery.sizeOf(context).width >= _splitLayoutWidth;

          if (useSplitLayout) {
            return _DashboardSplitLayout(
              snapshot: snapshotData,
              guests: guests,
              storages: storages,
              selection: _effectiveSelection(
                snapshotData.nodes,
                guests,
                storages,
              ),
              onRefresh: _refreshSnapshot,
              onNodeTap: _selectNode,
              onGuestTap: _selectGuest,
              onStorageTap: _selectStorage,
              detailBuilder: _buildSplitDetail,
            );
          }

          return _DashboardList(
            snapshot: snapshotData,
            guests: guests,
            storages: storages,
            onRefresh: _refreshSnapshot,
            onNodeTap: _openNodeRoute,
            onGuestTap: _openGuestRoute,
            onStorageTap: _openStorageRoute,
          );
        },
      ),
    );
  }

  _DashboardSelection? _effectiveSelection(
    List<PveNode> nodes,
    List<PveResource> guests,
    List<PveResource> storages,
  ) {
    final selection = _selection;
    if (selection != null) {
      switch (selection.type) {
        case _DashboardSelectionType.node:
          if (nodes.any(
            (node) => node.name == selection.id && node.hasDetailPermission,
          )) {
            return selection;
          }
        case _DashboardSelectionType.guest:
        case _DashboardSelectionType.guestConfig:
          if (guests.any((guest) => guest.id == selection.id)) {
            return selection;
          }
        case _DashboardSelectionType.storage:
          if (storages.any((storage) => storage.id == selection.id)) {
            return selection;
          }
      }
    }

    final accessibleNodes = nodes.where((node) => node.hasDetailPermission);
    if (accessibleNodes.isNotEmpty) {
      return _DashboardSelection.node(accessibleNodes.first.name);
    }
    if (guests.isNotEmpty) {
      return _DashboardSelection.guest(guests.first.id);
    }
    if (storages.isNotEmpty) {
      return _DashboardSelection.storage(storages.first.id);
    }
    return null;
  }

  Widget _buildSplitDetail(
    BuildContext context,
    _DashboardSelection? selection,
    List<PveNode> nodes,
    List<PveResource> guests,
    List<PveResource> storages,
  ) {
    if (selection == null) {
      return const SizedBox.shrink();
    }

    switch (selection.type) {
      case _DashboardSelectionType.node:
        final node = _findNode(nodes, selection.id);
        if (node == null || !node.hasDetailPermission) {
          return const SizedBox.shrink();
        }
        return NodeDetailScreen(
          key: ValueKey('node-detail-${node.name}'),
          client: widget.client,
          node: node,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
          embedded: true,
        );
      case _DashboardSelectionType.guest:
        final guest = _findGuest(guests, selection.id);
        if (guest == null) {
          return const SizedBox.shrink();
        }
        return GuestDetailScreen(
          key: ValueKey('guest-detail-${guest.id}'),
          client: widget.client,
          guest: guest,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
          embedded: true,
          onActionCompleted: _refreshSnapshot,
          onOpenConfig: () => _selectGuestConfig(guest),
        );
      case _DashboardSelectionType.guestConfig:
        final guest = _findGuest(guests, selection.id);
        if (guest == null) {
          return const SizedBox.shrink();
        }
        return GuestConfigScreen(
          key: ValueKey('guest-config-${guest.id}'),
          client: widget.client,
          guest: guest,
          embedded: true,
          onBack: () => _selectGuestDetail(guest),
        );
      case _DashboardSelectionType.storage:
        final storage = _findStorage(storages, selection.id);
        if (storage == null) {
          return const SizedBox.shrink();
        }
        return StorageDetailScreen(
          key: ValueKey('storage-detail-${storage.id}'),
          client: widget.client,
          storage: storage,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
          embedded: true,
        );
    }
  }

  PveNode? _findNode(List<PveNode> nodes, String name) {
    for (final node in nodes) {
      if (node.name == name) {
        return node;
      }
    }
    return null;
  }

  PveResource? _findGuest(List<PveResource> guests, String id) {
    for (final guest in guests) {
      if (guest.id == id) {
        return guest;
      }
    }
    return null;
  }

  PveResource? _findStorage(List<PveResource> storages, String id) {
    for (final storage in storages) {
      if (storage.id == id) {
        return storage;
      }
    }
    return null;
  }
}

enum _DashboardSelectionType { node, guest, guestConfig, storage }

class _DashboardSelection {
  const _DashboardSelection._(this.type, this.id);

  const _DashboardSelection.node(String name)
    : this._(_DashboardSelectionType.node, name);

  const _DashboardSelection.guest(String id)
    : this._(_DashboardSelectionType.guest, id);

  const _DashboardSelection.guestConfig(String id)
    : this._(_DashboardSelectionType.guestConfig, id);

  const _DashboardSelection.storage(String id)
    : this._(_DashboardSelectionType.storage, id);

  final _DashboardSelectionType type;
  final String id;
}

class _DashboardList extends StatelessWidget {
  const _DashboardList({
    required this.snapshot,
    required this.guests,
    required this.storages,
    required this.onRefresh,
    required this.onNodeTap,
    required this.onGuestTap,
    required this.onStorageTap,
    this.selection,
  });

  final PveSnapshot snapshot;
  final List<PveResource> guests;
  final List<PveResource> storages;
  final RefreshCallback onRefresh;
  final ValueChanged<PveNode> onNodeTap;
  final ValueChanged<PveResource> onGuestTap;
  final ValueChanged<PveResource> onStorageTap;
  final _DashboardSelection? selection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: l10n.nodes,
            trailing: l10n.nodesCount(snapshot.nodes.length),
          ),
          const SizedBox(height: 8),
          NodeGrid(
            nodes: snapshot.nodes,
            permissionDenied: snapshot.nodePermissionDenied,
            onNodeTap: onNodeTap,
            selectedNodeName: selection?.type == _DashboardSelectionType.node
                ? selection?.id
                : null,
          ),
          const SizedBox(height: 16),
          SectionHeader(
            title: l10n.guests,
            trailing: l10n.itemsCount(guests.length),
          ),
          const SizedBox(height: 8),
          GuestPanel(
            guests: guests,
            onSelect: onGuestTap,
            selectedGuestId:
                selection?.type == _DashboardSelectionType.guest ||
                    selection?.type == _DashboardSelectionType.guestConfig
                ? selection?.id
                : null,
          ),
          const SizedBox(height: 16),
          SectionHeader(
            title: l10n.storage,
            trailing: l10n.itemsCount(storages.length),
          ),
          const SizedBox(height: 8),
          StorageList(
            storages: storages,
            permissionDenied: snapshot.storagePermissionDenied,
            onStorageTap: onStorageTap,
            selectedStorageId:
                selection?.type == _DashboardSelectionType.storage
                ? selection?.id
                : null,
          ),
        ],
      ),
    );
  }
}

class _ResourcesLoadResult {
  const _ResourcesLoadResult({
    required this.resources,
    required this.fullResourceAccessDenied,
  });

  final List<PveResource> resources;
  final bool fullResourceAccessDenied;
}

class _NodesLoadResult {
  const _NodesLoadResult({required this.nodes, required this.permissionDenied});

  final List<PveNode> nodes;
  final bool permissionDenied;
}

class _NodeStatusLoadResult {
  const _NodeStatusLoadResult._({this.status, this.permissionDenied = false});

  const _NodeStatusLoadResult.success(NodeStatus status)
    : this._(status: status);

  const _NodeStatusLoadResult.permissionDenied()
    : this._(permissionDenied: true);

  const _NodeStatusLoadResult.failed() : this._();

  final NodeStatus? status;
  final bool permissionDenied;
}

class _DashboardSplitLayout extends StatelessWidget {
  const _DashboardSplitLayout({
    required this.snapshot,
    required this.guests,
    required this.storages,
    required this.selection,
    required this.onRefresh,
    required this.onNodeTap,
    required this.onGuestTap,
    required this.onStorageTap,
    required this.detailBuilder,
  });

  final PveSnapshot snapshot;
  final List<PveResource> guests;
  final List<PveResource> storages;
  final _DashboardSelection? selection;
  final RefreshCallback onRefresh;
  final ValueChanged<PveNode> onNodeTap;
  final ValueChanged<PveResource> onGuestTap;
  final ValueChanged<PveResource> onStorageTap;
  final Widget Function(
    BuildContext context,
    _DashboardSelection? selection,
    List<PveNode> nodes,
    List<PveResource> guests,
    List<PveResource> storages,
  )
  detailBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final masterWidth = (constraints.maxWidth * 0.38)
            .clamp(360.0, 520.0)
            .toDouble();

        return Row(
          children: [
            SizedBox(
              width: masterWidth,
              child: _DashboardList(
                snapshot: snapshot,
                guests: guests,
                storages: storages,
                onRefresh: onRefresh,
                onNodeTap: onNodeTap,
                onGuestTap: onGuestTap,
                onStorageTap: onStorageTap,
                selection: selection,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                child: detailBuilder(
                  context,
                  selection,
                  snapshot.nodes,
                  guests,
                  storages,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
