import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/node_log_entry.dart';
import 'package:pve_manager/data/models/node_task.dart';
import 'package:pve_manager/data/models/paged_result.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/node/node_tasks_logs_screen.dart';

void main() {
  late _Requests requests;

  setUp(() {
    requests = _Requests();
  });

  Future<void> openScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NodeTasksLogsScreen(
          client: _Client(requests),
          node: PveNode.fromJson({'node': 'pve'}),
        ),
      ),
    );
  }

  Future<void> openLogs(WidgetTester tester) async {
    await openScreen(tester);
    requests.tasks.single.result.complete(
      const PagedResult(items: <NodeTask>[], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(requests.logs, isEmpty);
    await tester.tap(find.text('Logs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('log pagination keeps readable rows and their scroll position', (
    tester,
  ) async {
    await openLogs(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(requests.logs.single.beforeCursor, isNull);
    requests.logs.single.result.complete(
      _logs(100, count: 30, cursor: 'older'),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const PageStorageKey<String>('node-logs'));
    await tester.drag(list, const Offset(0, -250));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    final offset = scrollable.position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(requests.logs.last.beforeCursor, 'older');
    expect(list, findsOneWidget);
    expect(scrollable.position.pixels, offset);
    expect(find.text('Cancel'), findsOneWidget);

    requests.logs.last.result.complete(_logs(70, count: 10));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, offset);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed log refresh keeps rows and retries the latest page', (
    tester,
  ) async {
    await openLogs(tester);
    requests.logs.single.result.complete(_logs(100, cursor: 'older'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.text('log-100'), findsOneWidget);
    expect(requests.logs.last.beforeCursor, isNull);
    requests.logs.last.result.completeError(StateError('temporarily offline'));
    await tester.pumpAndSettle();
    expect(find.text('log-100'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(requests.logs.last.beforeCursor, isNull);
    expect(requests.logs.last.start, isNull);
    requests.logs.last.result.complete(_logs(200));
    await tester.pumpAndSettle();
    expect(find.text('log-200'), findsOneWidget);
    expect(find.text('log-100'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelled pagination cannot replace a later result', (
    tester,
  ) async {
    await openLogs(tester);
    requests.logs.single.result.complete(_logs(100, cursor: 'older'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pump();
    final cancelled = requests.logs.last;
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled.client.closed, isTrue);
    expect(find.text('log-100'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(requests.logs.last.beforeCursor, 'older');
    requests.logs.last.result.complete(_logs(90));
    await tester.pumpAndSettle();
    cancelled.result.complete(_logs(80, cursor: 'stale'));
    await tester.pumpAndSettle();
    expect(find.text('log-100'), findsOneWidget);
    expect(find.text('log-90'), findsOneWidget);
    expect(find.text('log-80'), findsNothing);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed legacy log pagination retries the same offset', (
    tester,
  ) async {
    await openLogs(tester);
    requests.logs.single.result.complete(
      PagedResult(items: _logs(100).items, hasMore: true, nextStart: 70),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(requests.logs.last.start, 70);
    requests.logs.last.result.completeError(StateError('temporarily offline'));
    await tester.pumpAndSettle();
    expect(find.text('log-100'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(requests.logs.last.start, 70);
    expect(requests.logs.last.beforeCursor, isNull);
    requests.logs.last.result.complete(_logs(70));
    await tester.pumpAndSettle();
    expect(find.text('log-70'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('task refresh retains rows and retries from the first page', (
    tester,
  ) async {
    await openScreen(tester);
    requests.tasks.single.result.complete(_tasks('original', hasMore: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.text('original'), findsOneWidget);
    requests.tasks.last.result.completeError(StateError('temporarily offline'));
    await tester.pumpAndSettle();
    expect(find.text('original'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(requests.tasks.last.start, 0);
    requests.tasks.last.result.complete(_tasks('refreshed'));
    await tester.pumpAndSettle();
    expect(find.text('refreshed'), findsOneWidget);
    expect(find.text('original'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

PagedResult<NodeLogEntry> _logs(int newest, {int count = 1, String? cursor}) =>
    PagedResult(
      items: [
        for (var i = 0; i < count; i++)
          NodeLogEntry(lineNumber: newest - i, text: 'log-${newest - i}'),
      ],
      hasMore: cursor != null,
      nextCursor: cursor,
    );

PagedResult<NodeTask> _tasks(String type, {bool hasMore = false}) =>
    PagedResult(
      items: [
        NodeTask.fromJson({
          'upid': 'UPID:pve:$type',
          'type': type,
          'user': 'root@pam',
          'status': 'OK',
          'starttime': 1,
          'endtime': 2,
        }),
      ],
      hasMore: hasMore,
    );

class _Requests {
  final logs = <_LogRequest>[];
  final tasks = <_TaskRequest>[];
}

class _LogRequest {
  _LogRequest(this.client, this.start, this.beforeCursor);

  final _Client client;
  final int? start;
  final String? beforeCursor;
  final result = Completer<PagedResult<NodeLogEntry>>();
}

class _TaskRequest {
  _TaskRequest(this.start);

  final int start;
  final result = Completer<PagedResult<NodeTask>>();
}

class _Client extends Fake implements ProxmoxClient {
  _Client(this.requests);

  final _Requests requests;
  bool closed = false;

  @override
  ProxmoxClient forkSession() => _Client(requests);

  @override
  Future<PagedResult<NodeTask>> getNodeTasks(
    String node, {
    int start = 0,
    int limit = 20,
  }) {
    final request = _TaskRequest(start);
    requests.tasks.add(request);
    return request.result.future;
  }

  @override
  Future<PagedResult<NodeLogEntry>> getNodeSyslog(
    String node, {
    int? start,
    String? beforeCursor,
    int limit = 30,
  }) {
    final request = _LogRequest(this, start, beforeCursor);
    requests.logs.add(request);
    return request.result.future;
  }

  @override
  void close() {
    closed = true;
  }
}
