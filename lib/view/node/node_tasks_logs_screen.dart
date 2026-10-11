import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/node_log_entry.dart';
import 'package:pve_manager/data/models/node_task.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/core/utils/formatters.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/core/widgets/status_pill.dart';

class NodeTasksLogsScreen extends StatefulWidget {
  const NodeTasksLogsScreen({
    required this.client,
    required this.node,
    super.key,
  });

  final ProxmoxClient client;
  final PveNode node;

  @override
  State<NodeTasksLogsScreen> createState() => _NodeTasksLogsScreenState();
}

class _NodeTasksLogsScreenState extends State<NodeTasksLogsScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _loadTimeout = Duration(seconds: 8);
  static const Duration _logLoadTimeout = Duration(seconds: 25);
  static const int _taskPageSize = 20;
  static const int _logPageSize = 30;

  late final TabController _tabController;
  int _tasksLoadId = 0;
  int _logsLoadId = 0;
  int _tasksStart = 0;
  int? _logsNextStart;
  String? _logsNextCursor;
  bool _tasksLoading = false;
  bool _logsLoading = false;
  bool _tasksLoadIsReset = true;
  bool _logsLoadIsReset = true;
  bool _tasksHasMore = false;
  bool _logsHasMore = false;
  Object? _tasksError;
  Object? _logsError;
  List<NodeTask>? _tasks;
  List<NodeLogEntry>? _logs;
  ProxmoxClient? _tasksClient;
  ProxmoxClient? _logsClient;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTasks(reset: true);
      }
    });
  }

  @override
  void dispose() {
    _tasksLoadId++;
    _logsLoadId++;
    _tasksClient?.close();
    _logsClient?.close();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.index == 1 && _logs == null && !_logsLoading) {
      _loadLogs(reset: true);
    }
  }

  Future<void> _loadTasks({bool reset = false}) async {
    if (_tasksLoading) {
      return;
    }

    final loadId = ++_tasksLoadId;
    final start = reset ? 0 : _tasksStart;
    _tasksClient?.close();

    setState(() {
      _tasksLoading = true;
      _tasksError = null;
      _tasksLoadIsReset = reset;
    });

    ProxmoxClient? client;
    try {
      client = widget.client.forkSession();
      _tasksClient = client;
      final result = await client
          .getNodeTasks(widget.node.name, start: start, limit: _taskPageSize)
          .timeout(_loadTimeout);
      if (!mounted || loadId != _tasksLoadId) {
        return;
      }
      setState(() {
        _tasks = <NodeTask>[if (!reset) ...?_tasks, ...result.items];
        _tasksStart = start + result.items.length;
        _tasksHasMore = result.hasMore;
        _tasksLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || loadId != _tasksLoadId) {
        return;
      }
      setState(() {
        _tasksError = error;
        _tasksLoading = false;
      });
    } finally {
      if (identical(_tasksClient, client)) {
        _tasksClient = null;
      }
      client?.close();
    }
  }

  Future<void> _loadLogs({bool reset = false}) async {
    if (_logsLoading) {
      return;
    }

    final loadId = ++_logsLoadId;
    final start = reset ? null : _logsNextStart;
    final beforeCursor = reset ? null : _logsNextCursor;
    if (!reset && start == null && beforeCursor == null) {
      return;
    }
    _logsClient?.close();

    setState(() {
      _logsLoading = true;
      _logsError = null;
      _logsLoadIsReset = reset;
    });

    ProxmoxClient? client;
    try {
      client = widget.client.forkSession();
      _logsClient = client;
      final result = await client
          .getNodeSyslog(
            widget.node.name,
            start: start,
            beforeCursor: beforeCursor,
            limit: _logPageSize,
          )
          .timeout(_logLoadTimeout);
      if (!mounted || loadId != _logsLoadId) {
        return;
      }
      setState(() {
        _logs = <NodeLogEntry>[if (!reset) ...?_logs, ...result.items];
        _logsNextStart = result.nextStart;
        _logsNextCursor = result.nextCursor;
        _logsHasMore = result.hasMore;
        _logsLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || loadId != _logsLoadId) {
        return;
      }
      setState(() {
        _logsError = error;
        _logsLoading = false;
      });
    } finally {
      if (identical(_logsClient, client)) {
        _logsClient = null;
      }
      client?.close();
    }
  }

  void _cancelTasks() {
    _tasksLoadId++;
    _tasksClient?.close();
    _tasksClient = null;
    if (_tasksLoading) {
      setState(() {
        _tasksLoading = false;
      });
    }
  }

  void _cancelLogs() {
    _logsLoadId++;
    _logsClient?.close();
    _logsClient = null;
    if (_logsLoading) {
      setState(() {
        _logsLoading = false;
      });
    }
  }

  void _refresh() {
    if (_tabController.index == 0) {
      _loadTasks(reset: true);
    } else {
      _loadLogs(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasksAndLogs),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.tasks),
            Tab(text: l10n.logs),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AsyncList<NodeTask>(
            isLoading: _tasksLoading,
            items: _tasks,
            error: _tasksError,
            hasMore: _tasksHasMore,
            onLoad: () => _loadTasks(reset: true),
            onLoadMore: _loadTasks,
            onRetry: () => _loadTasks(reset: _tasksLoadIsReset),
            onCancel: _cancelTasks,
            loadText: l10n.loadTasks,
            progressText: _tasksLoadIsReset ? l10n.refresh : l10n.loadMore,
            loadMoreText: l10n.loadMore,
            emptyText: l10n.noTasks,
            builder: (items) => _TaskList(tasks: items),
          ),
          _AsyncList<NodeLogEntry>(
            isLoading: _logsLoading,
            items: _logs,
            error: _logsError,
            hasMore: _logsHasMore,
            onLoad: () => _loadLogs(reset: true),
            onLoadMore: _loadLogs,
            onRetry: () => _loadLogs(reset: _logsLoadIsReset),
            onCancel: _cancelLogs,
            loadText: l10n.loadLogs,
            progressText: _logsLoadIsReset ? l10n.refresh : l10n.loadMore,
            loadMoreText: l10n.loadMore,
            emptyText: l10n.noLogs,
            builder: (items) => _LogList(logs: items),
          ),
        ],
      ),
    );
  }
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.isLoading,
    required this.items,
    required this.error,
    required this.hasMore,
    required this.onLoad,
    required this.onLoadMore,
    required this.onRetry,
    required this.onCancel,
    required this.loadText,
    required this.progressText,
    required this.loadMoreText,
    required this.emptyText,
    required this.builder,
  });

  final bool isLoading;
  final List<T>? items;
  final Object? error;
  final bool hasMore;
  final VoidCallback onLoad;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final String loadText;
  final String progressText;
  final String loadMoreText;
  final String emptyText;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final items = this.items;
    if (isLoading && items == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(loadText),
            const SizedBox(height: 12),
            TextButton(onPressed: onCancel, child: Text(context.l10n.cancel)),
          ],
        ),
      );
    }

    final error = this.error;
    if (error != null && items == null) {
      return ErrorState(
        message: localizedError(context.l10n, error),
        onRetry: onRetry,
      );
    }

    if (items == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: onLoad,
          icon: const Icon(Icons.article_rounded),
          label: Text(loadText),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(emptyText))
              : builder(items),
        ),
        _ListFooter(
          isLoading: isLoading,
          hasMore: hasMore,
          error: error,
          onLoadMore: onLoadMore,
          onRetry: onRetry,
          onCancel: onCancel,
          progressText: progressText,
          loadMoreText: loadMoreText,
        ),
      ],
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoading,
    required this.hasMore,
    required this.error,
    required this.onLoadMore,
    required this.onRetry,
    required this.onCancel,
    required this.progressText,
    required this.loadMoreText,
  });

  final bool isLoading;
  final bool hasMore;
  final Object? error;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final String progressText;
  final String loadMoreText;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(progressText),
              const SizedBox(width: 12),
              TextButton(onPressed: onCancel, child: Text(context.l10n.cancel)),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.retry),
          ),
        ),
      );
    }

    if (!hasMore) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more_rounded),
          label: Text(loadMoreText),
        ),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<NodeTask> tasks;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey<String>('node-tasks'),
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: ListTile(
            title: Text(task.type),
            subtitle: Text('${task.user} · ${timestamp(task.startTime)}'),
            trailing: StatusPill(
              status: task.isRunning ? 'running' : task.status,
            ),
          ),
        );
      },
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.logs});

  final List<NodeLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const PageStorageKey<String>('node-logs'),
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final log = logs[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            log.text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        );
      },
    );
  }
}
