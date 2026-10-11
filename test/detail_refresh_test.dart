import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/core/widgets/error_state.dart';
import 'package:pve_manager/core/widgets/performance_history_card.dart';
import 'package:pve_manager/data/models/guest_config.dart';
import 'package:pve_manager/data/models/guest_rrd_point.dart';
import 'package:pve_manager/data/models/node_rrd_point.dart';
import 'package:pve_manager/data/models/node_status.dart';
import 'package:pve_manager/data/models/pve_node.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/models/pve_storage.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/guest/guest_config_screen.dart';
import 'package:pve_manager/view/guest/guest_detail_screen.dart';
import 'package:pve_manager/view/node/node_detail_screen.dart';
import 'package:pve_manager/view/storage/storage_detail_screen.dart';

void main() {
  late _ControlledClient client;
  late ValueNotifier<Duration> interval;

  setUp(() {
    client = _ControlledClient();
    interval = ValueNotifier(const Duration(minutes: 1));
  });
  tearDown(() {
    interval.dispose();
    client.close();
  });

  testWidgets('old node responses cannot populate a different node', (
    tester,
  ) async {
    Widget page(String name) => _app(
      NodeDetailScreen(
        client: client,
        node: PveNode.fromJson({'node': name}),
        autoRefreshIntervalListenable: interval,
      ),
    );
    await tester.pumpWidget(page('old'));
    await tester.pumpWidget(page('new'));
    client.nodes['new']!.completeError(StateError('new node unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    client.nodes['old']!.complete(NodeStatus.fromJson({'pveversion': 'old'}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('old guest history is not reused after switching guests', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget page(String name) => _app(
      GuestDetailScreen(
        client: client,
        guest: _resource(name),
        autoRefreshIntervalListenable: interval,
      ),
    );
    await tester.pumpWidget(page('old'));
    await tester.pumpWidget(page('new'));
    client.histories['new']!.completeError(StateError('new guest unavailable'));
    await tester.pumpAndSettle();
    client.histories['old']!.complete([
      GuestRrdPoint.fromJson({'time': 1}),
    ]);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PerformanceHistoryCard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'node refresh reloads expired temperatures with existing disk data',
    (tester) async {
      client.thermalState = const NodeThermalState(
        sensors: [
          NodeTemperatureSensor(
            label: 'Temperature',
            source: '/dev/sda',
            celsius: 42,
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          NodeDetailScreen(
            client: client,
            node: PveNode.fromJson({'node': 'pve'}),
            autoRefreshIntervalListenable: interval,
          ),
        ),
      );
      client.nodes['pve']!.complete(NodeStatus.fromJson({}));
      await tester.pumpAndSettle();
      expect(client.thermalRequests, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(client.thermalRequests, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('storage refresh recovers its button after a failed request', (
    tester,
  ) async {
    Widget page(String name) => _app(
      StorageDetailScreen(
        client: client,
        storage: _resource(name, type: 'storage'),
        autoRefreshIntervalListenable: interval,
      ),
    );
    await tester.pumpWidget(page('old'));
    await tester.pumpWidget(page('new'));
    client.storages['new']!.completeError(
      StateError('new storage unavailable'),
    );
    await tester.pumpAndSettle();
    client.storages['old']!.complete(
      PveStorageDetail(
        node: 'pve',
        status: PveStorageStatus.fromJson({
          'type': 'old-backend',
        }, fallbackStorage: 'old'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('old-backend'), findsNothing);
    final refresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh_rounded),
    );
    expect(refresh.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('configuration retry handles network failures', (tester) async {
    await tester.pumpWidget(
      _app(GuestConfigScreen(client: client, guest: _resource('guest'))),
    );
    client.configs.single.completeError(
      StateError('configuration unavailable'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    client.configs.last.completeError(StateError('retry unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving configuration refreshes even while an older read runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(GuestConfigScreen(client: client, guest: _resource('guest'))),
    );
    const original = GuestConfig(
      values: {'name': 'original-name'},
      editSchema: GuestConfigEditSchema(
        parameters: {'name'},
        isAvailable: true,
      ),
    );
    client.configs.single.complete(original);
    await tester.pumpAndSettle();
    unawaited(
      tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh(),
    );
    await tester.pump();
    expect(client.configs, hasLength(2));
    await tester.tap(find.text('original-name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'saved-name');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(client.configs, hasLength(3));
    const updated = GuestConfig(
      values: {'name': 'saved-name'},
      editSchema: GuestConfigEditSchema(
        parameters: {'name'},
        isAvailable: true,
      ),
    );
    client.configs.last.complete(updated);
    await tester.pumpAndSettle();
    client.configs[1].complete(original);
    await tester.pumpAndSettle();
    expect(find.text('saved-name'), findsOneWidget);
    expect(find.text('original-name'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

PveResource _resource(String name, {String type = 'qemu'}) =>
    PveResource.fromJson({
      'id': '$type/$name',
      'name': name,
      'node': 'pve',
      'type': type,
      'vmid': 100,
      'status': 'running',
    });

class _ControlledClient extends ProxmoxClient {
  _ControlledClient()
    : super(
        origin: 'https://pve.invalid',
        username: '',
        password: '',
        realm: 'pam',
      );

  final nodes = <String, Completer<NodeStatus>>{};
  final histories = <String, Completer<List<GuestRrdPoint>>>{};
  final storages = <String, Completer<PveStorageDetail>>{};
  final configs = <Completer<GuestConfig>>[];
  NodeThermalState thermalState = const NodeThermalState.empty();
  int thermalRequests = 0;

  @override
  Future<NodeStatus> getNodeStatus(String node) =>
      nodes.putIfAbsent(node, Completer<NodeStatus>.new).future;

  @override
  Future<List<NodeRrdPoint>> getNodeRrdData(
    String node, {
    String timeframe = 'hour',
  }) async => [];

  @override
  Future<NodeThermalState> getNodeThermalState(String node) async {
    thermalRequests++;
    return thermalState;
  }

  @override
  Future<PveResource> getGuestCurrentStatus(PveResource guest) async => guest;

  @override
  Future<List<GuestRrdPoint>> getGuestRrdData(
    PveResource guest, {
    String timeframe = 'hour',
  }) => histories
      .putIfAbsent(guest.name, Completer<List<GuestRrdPoint>>.new)
      .future;

  @override
  Future<PveStorageDetail> getNodeStorageDetail(String node, String storage) =>
      storages.putIfAbsent(storage, Completer<PveStorageDetail>.new).future;

  @override
  Future<GuestConfig> getGuestConfig(PveResource guest) {
    final result = Completer<GuestConfig>();
    configs.add(result);
    return result.future;
  }

  @override
  Future<void> updateGuestConfig(
    PveResource guest,
    String key,
    String value,
  ) async {}
}
