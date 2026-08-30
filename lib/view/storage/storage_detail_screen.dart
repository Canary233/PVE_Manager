import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/core/utils/formatters.dart';
import 'package:pve_manager/core/widgets/empty_state.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/models/pve_storage.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';

class StorageDetailScreen extends StatefulWidget {
  const StorageDetailScreen({
    required this.client,
    required this.storage,
    required this.autoRefreshIntervalListenable,
    this.embedded = false,
    super.key,
  });

  final ProxmoxClient client;
  final PveResource storage;
  final ValueListenable<Duration> autoRefreshIntervalListenable;
  final bool embedded;

  @override
  State<StorageDetailScreen> createState() => _StorageDetailScreenState();
}

class _StorageDetailScreenState extends State<StorageDetailScreen> {
  late Future<PveStorageDetail> _detailFuture;
  final Map<_StorageSection, Future<List<PveStorageContent>>> _contentFutures =
      {};
  Timer? _refreshTimer;
  PveStorageDetail? _lastDetail;
  _StorageSection _section = _StorageSection.overview;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
    widget.autoRefreshIntervalListenable.addListener(_startRefreshTimer);
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(StorageDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storage.id != widget.storage.id ||
        oldWidget.storage.node != widget.storage.node ||
        oldWidget.client != widget.client) {
      _contentFutures.clear();
      _section = _StorageSection.overview;
      _detailFuture = _loadDetail();
    }
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
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.autoRefreshIntervalListenable.value, (
      _,
    ) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(_refresh());
      }
    });
  }

  Future<PveStorageDetail> _loadDetail() async {
    final detail = await widget.client.getNodeStorageDetail(
      widget.storage.node,
      widget.storage.name,
    );
    _lastDetail = detail;
    return detail;
  }

  Future<List<PveStorageContent>> _loadContent(_StorageSection section) {
    final contentType = section.contentType;
    if (contentType == null) {
      return Future<List<PveStorageContent>>.value(const []);
    }

    final cached = _contentFutures[section];
    if (cached != null) {
      return cached;
    }

    final future = widget.client.getNodeStorageContent(
      widget.storage.node,
      widget.storage.name,
      content: contentType,
    );
    _contentFutures[section] = future;
    return future;
  }

  Future<void> _refresh() async {
    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    final detailFuture = _loadDetail();
    final section = _section;
    if (section.contentType != null) {
      _contentFutures.remove(section);
    }
    if (mounted) {
      setState(() {
        _detailFuture = detailFuture;
        if (section.contentType != null) {
          _loadContent(section);
        }
      });
    }

    try {
      await detailFuture;
      if (section.contentType != null) {
        await _loadContent(section);
      }
    } on Object {
      // FutureBuilder shows the error while keeping the last detail visible.
    } finally {
      _isRefreshing = false;
    }
  }

  void _selectSection(_StorageSection section) {
    if (_section == section) {
      return;
    }
    setState(() {
      _section = section;
      if (section.contentType != null) {
        _loadContent(section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(widget.storage.name),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _isRefreshing ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<PveStorageDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          final detail = snapshot.data ?? _lastDetail;
          if (snapshot.connectionState == ConnectionState.waiting &&
              detail == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && detail == null) {
            return ErrorState(
              message: localizedError(l10n, snapshot.error!),
              onRetry: _refresh,
            );
          }
          if (detail == null) {
            return ErrorState(message: l10n.noData, onRetry: _refresh);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 196,
                      child: _buildSectionNavigation(context),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildSectionContent(context, detail)),
                  ],
                );
              }

              return Column(
                children: [
                  _buildMobileSectionPicker(context),
                  Expanded(child: _buildSectionContent(context, detail)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionNavigation(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
            child: Text(
              widget.storage.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final section in _StorageSection.values)
            _buildSectionTile(context, section),
        ],
      ),
    );
  }

  Widget _buildSectionTile(BuildContext context, _StorageSection section) {
    final selected = section == _section;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.55),
      leading: Icon(section.icon),
      title: Text(_sectionLabel(context, section)),
      dense: true,
      onTap: () => _selectSection(section),
    );
  }

  Widget _buildMobileSectionPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: context.l10n.storageContent,
          filled: true,
          fillColor: colorScheme.surfaceContainer,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_StorageSection>(
            value: _section,
            isExpanded: true,
            items: [
              for (final section in _StorageSection.values)
                DropdownMenuItem(
                  value: section,
                  child: Text(_sectionLabel(context, section)),
                ),
            ],
            onChanged: (section) {
              if (section != null) {
                _selectSection(section);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(BuildContext context, PveStorageDetail detail) {
    final section = _section;
    if (section == _StorageSection.overview) {
      return _buildOverview(context, detail);
    }
    if (section.contentType == null) {
      return EmptyState(text: context.l10n.storageSectionUnsupported);
    }

    return FutureBuilder<List<PveStorageContent>>(
      future: _loadContent(section),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorState(
            message: localizedError(context.l10n, snapshot.error!),
            onRetry: () {
              setState(() {
                _contentFutures.remove(section);
              });
            },
          );
        }

        final content = snapshot.data ?? const <PveStorageContent>[];
        if (content.isEmpty) {
          return EmptyState(text: context.l10n.storageNoContent);
        }
        return _buildContentList(context, content);
      },
    );
  }

  Widget _buildOverview(BuildContext context, PveStorageDetail detail) {
    final l10n = context.l10n;
    final status = detail.status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StorageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.storageOverview,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              UsageLine(
                label: l10n.storageCapacity,
                value: status.usedFraction,
                text: '${bytes(status.used)} / ${bytes(status.total)}',
              ),
              const SizedBox(height: 18),
              _StorageInfoRow(
                label: l10n.storageAvailable,
                value: bytes(status.available),
              ),
              _StorageInfoRow(
                label: l10n.storageBackendType,
                value: detail.type,
              ),
              _StorageInfoRow(
                label: l10n.storageStatus,
                value: status.active ? l10n.online : l10n.disconnected,
              ),
              _StorageInfoRow(
                label: l10n.storageEnabled,
                value: status.enabled ? l10n.yes : l10n.no,
              ),
              _StorageInfoRow(
                label: l10n.storageShared,
                value: status.shared ? l10n.yes : l10n.no,
              ),
              if (detail.config?.path != null)
                _StorageInfoRow(
                  label: l10n.storagePath,
                  value: detail.config!.path!,
                ),
              if (detail.config?.nodes.isNotEmpty == true)
                _StorageInfoRow(
                  label: l10n.nodes,
                  value: detail.config!.nodes.join(', '),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StorageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.storageContent,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (detail.contentTypes.isEmpty)
                Text(l10n.noData)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in detail.contentTypes)
                      Chip(label: Text(_contentTypeLabel(context, type))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentList(
    BuildContext context,
    List<PveStorageContent> content,
  ) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _sectionLabel(context, _section),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.surface,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: content.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = content[index];
              final details = <String>[
                if (item.format != '-') item.format,
                bytes(item.size),
                if (item.vmid != null) '${l10n.storageVmid}: ${item.vmid}',
                if (item.createdAt != null) timestamp(item.createdAt!),
              ];
              return ListTile(
                leading: Icon(_contentTypeIcon(item.contentType)),
                title: Text(
                  item.volumeId,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                trailing: item.used > 0 ? Text(bytes(item.used)) : null,
              );
            },
          ),
        ),
      ],
    );
  }

  String _sectionLabel(BuildContext context, _StorageSection section) {
    final l10n = context.l10n;
    return switch (section) {
      _StorageSection.overview => l10n.storageOverview,
      _StorageSection.backups => l10n.storageBackups,
      _StorageSection.vmDisks => l10n.storageVmDisks,
      _StorageSection.ctVolumes => l10n.storageCtVolumes,
      _StorageSection.isoImages => l10n.storageIsoImages,
      _StorageSection.ctTemplates => l10n.storageCtTemplates,
      _StorageSection.snippets => l10n.storageSnippets,
      _StorageSection.import => l10n.storageImport,
      _StorageSection.permissions => l10n.storagePermissions,
    };
  }

  String _contentTypeLabel(BuildContext context, String type) {
    return switch (type) {
      'backup' => context.l10n.storageBackups,
      'images' => context.l10n.storageVmDisks,
      'rootdir' => context.l10n.storageCtVolumes,
      'iso' => context.l10n.storageIsoImages,
      'vztmpl' => context.l10n.storageCtTemplates,
      'snippets' => context.l10n.storageSnippets,
      'import' => context.l10n.storageImport,
      _ => type,
    };
  }

  IconData _contentTypeIcon(String type) {
    return switch (type) {
      'backup' => Icons.backup_rounded,
      'images' => Icons.storage_rounded,
      'rootdir' => Icons.inventory_2_rounded,
      'iso' => Icons.album_rounded,
      'vztmpl' => Icons.description_rounded,
      'snippets' => Icons.code_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }
}

enum _StorageSection {
  overview(null, Icons.dashboard_rounded),
  backups('backup', Icons.backup_rounded),
  vmDisks('images', Icons.storage_rounded),
  ctVolumes('rootdir', Icons.inventory_2_rounded),
  isoImages('iso', Icons.album_rounded),
  ctTemplates('vztmpl', Icons.description_rounded),
  snippets('snippets', Icons.code_rounded),
  import('import', Icons.file_download_rounded),
  permissions(null, Icons.lock_outline_rounded);

  const _StorageSection(this.contentType, this.icon);

  final String? contentType;
  final IconData icon;
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _StorageInfoRow extends StatelessWidget {
  const _StorageInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
