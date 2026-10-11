import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/node_terminal_session.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/view/local_terminal_screen.dart';
import 'package:xterm/xterm.dart';

const _session = NodeTerminalSession(
  user: 'test',
  ticket: 'ticket',
  port: 5900,
);

void main() {
  testWidgets('closing during session creation does not open a socket', (
    tester,
  ) async {
    final session = Completer<NodeTerminalSession>();
    final client = _TerminalClient(session: session.future);
    await tester.pumpWidget(_screen(client));
    await tester.pumpWidget(const SizedBox.shrink());

    session.complete(_session);
    await tester.pump();

    expect(client.connectCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a socket established after route disposal is released', (
    tester,
  ) async {
    final pending = Completer<ProxmoxTerminalConnection>();
    final client = _TerminalClient(connection: pending.future);
    final connection = _TerminalConnection();
    await tester.pumpWidget(_screen(client));
    await tester.pump();
    expect(client.connectCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());

    pending.complete(connection);
    await tester.pump();

    expect(connection.closeCalls, 1);
    expect(connection.socket.sent, isEmpty);
    expect(tester.takeException(), isNull);
    await connection.socket.events.close();
  });

  testWidgets('mixed socket message types preserve output order', (
    tester,
  ) async {
    final connection = _TerminalConnection();
    final client = _TerminalClient(connection: Future.value(connection));
    await tester.pumpWidget(_screen(client));
    await tester.pump();
    connection.socket.events.add('OK');
    await tester.pump();
    final terminal = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .terminal;

    connection.socket.events
      ..add(Uint8List.fromList('first'.codeUnits))
      ..add('second')
      ..add(Uint8List.fromList([0xe4, 0xb8]))
      ..add(Uint8List.fromList([0xad]));
    await tester.pump();

    expect(terminal.buffer.getText(), startsWith('firstsecond中'));
    await tester.pumpWidget(const SizedBox.shrink());
    await connection.socket.events.close();
  });

  testWidgets(
    'reconnecting does not carry incomplete UTF-8 into the new socket',
    (tester) async {
      final first = _TerminalConnection();
      final second = _TerminalConnection();
      final client = _TerminalClient(connection: Future.value(first));
      await tester.pumpWidget(_screen(client));
      await tester.pump();
      expect(first.socket.events.hasListener, isTrue);
      first.socket.events.add('OK');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.refresh_rounded),
            )
            .onPressed,
        isNotNull,
      );
      first.socket.events.add(Uint8List.fromList([0xe4]));
      client.connection = Future.value(second);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      expect(client.connectCalls, 2);
      expect(second.socket.events.hasListener, isTrue);
      second.socket.events
        ..add('OK')
        ..add(Uint8List.fromList('clean'.codeUnits));
      await tester.pump();

      final terminal = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal;
      expect(terminal.buffer.getText(), contains('clean'));
      expect(terminal.buffer.getText(), isNot(contains('\uFFFD')));
      expect(first.closeCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await first.socket.events.close();
      await second.socket.events.close();
    },
  );

  testWidgets(
    'closing while a reconnect releases the old socket stops retries',
    (tester) async {
      final closing = Completer<void>();
      final connection = _TerminalConnection(closeResult: closing.future);
      final client = _TerminalClient(connection: Future.value(connection));
      await tester.pumpWidget(_screen(client));
      await tester.pump();
      connection.socket.events.add('OK');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(connection.closeCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      closing.complete();
      await tester.pump();

      expect(client.connectCalls, 1);
      expect(tester.takeException(), isNull);
      await connection.socket.events.close();
    },
  );

  testWidgets(
    'clipboard completion after route disposal does not write input',
    (tester) async {
      final clipboard = Completer<Map<String, Object?>>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? clipboard.future : null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final connection = _TerminalConnection();
      final client = _TerminalClient(connection: Future.value(connection));
      await tester.pumpWidget(_screen(client));
      await tester.pump();
      connection.socket.events.add('OK');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.content_paste_rounded));
      await tester.pumpWidget(const SizedBox.shrink());
      final sent = List<String>.of(connection.socket.sent);
      clipboard.complete({'text': 'should not be sent'});
      await tester.pump();

      expect(connection.socket.sent, sent);
      expect(tester.takeException(), isNull);
      await connection.socket.events.close();
    },
  );
}

Widget _screen(ProxmoxClient client) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: LocalTerminalScreen.node(
    title: 'Terminal',
    client: client,
    node: 'node',
  ),
);

class _TerminalClient extends Fake implements ProxmoxClient {
  _TerminalClient({Future<NodeTerminalSession>? session, this.connection})
    : session = session ?? Future.value(_session);

  final Future<NodeTerminalSession> session;
  Future<ProxmoxTerminalConnection>? connection;
  int connectCalls = 0;

  @override
  String nodeTerminalApiPath(String node) => '/nodes/$node';

  @override
  Future<NodeTerminalSession> createNodeTerminalSession(String node) => session;

  @override
  Future<ProxmoxTerminalConnection> connectTerminalWebSocket({
    required String apiPath,
    required NodeTerminalSession session,
  }) {
    connectCalls++;
    return connection!;
  }
}

class _TerminalConnection extends Fake implements ProxmoxTerminalConnection {
  _TerminalConnection({this.closeResult});

  @override
  final _TerminalSocket socket = _TerminalSocket();
  final Future<void>? closeResult;
  int closeCalls = 0;

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCalls++;
    await closeResult;
  }
}

class _TerminalSocket extends Fake implements WebSocket {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final sent = <String>[];

  @override
  void add(dynamic data) => sent.add(data as String);

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
