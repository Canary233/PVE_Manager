import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/node_terminal_session.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/view/terminal_visuals.dart';

class LocalTerminalScreen extends StatefulWidget {
  const LocalTerminalScreen.node({
    required this.title,
    required this.client,
    required String node,
    super.key,
  }) : _node = node,
       _guest = null;

  const LocalTerminalScreen.guest({
    required this.title,
    required this.client,
    required PveResource guest,
    super.key,
  }) : _node = null,
       _guest = guest;

  final String title;
  final ProxmoxClient client;
  final String? _node;
  final PveResource? _guest;

  @override
  State<LocalTerminalScreen> createState() => _LocalTerminalScreenState();
}

class _LocalTerminalScreenState extends State<LocalTerminalScreen> {
  late final Terminal _terminal;
  late final GlobalKey<TerminalViewState> _terminalViewKey;
  late final TerminalController _controller;
  late final FocusNode _focusNode;
  late final StreamController<List<int>> _outputBytesController;
  late final StreamSubscription<String> _outputTextSubscription;

  ProxmoxTerminalConnection? _connection;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _pingTimer;
  _TerminalConnectionState _connectionState =
      _TerminalConnectionState.connecting;
  String? _statusMessage;
  bool _disposed = false;
  bool _reconnectInFlight = false;
  bool _ctrlLatch = false;
  bool _altLatch = false;
  int _toastRequestId = 0;

  @override
  void initState() {
    super.initState();
    _terminalViewKey = GlobalKey<TerminalViewState>();
    _controller = TerminalController(
      pointerInputs: const PointerInputs({
        PointerInput.tap,
        PointerInput.scroll,
        PointerInput.drag,
        PointerInput.move,
      }),
    );
    _focusNode = FocusNode(skipTraversal: true, canRequestFocus: false);
    _terminal = Terminal(
      maxLines: 10000,
      platform: _terminalPlatform(),
      onOutput: _sendInput,
      onResize: _sendResize,
    );
    _outputBytesController = StreamController<List<int>>();
    _outputTextSubscription = _outputBytesController.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_terminal.write);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        unawaited(_connect());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _hideKeyboard();
    _focusNode
      ..canRequestFocus = false
      ..unfocus();
    _pingTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_connection?.close());
    unawaited(_outputTextSubscription.cancel());
    _outputBytesController.close();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final l10n = context.l10n;
    _setConnectionState(
      _TerminalConnectionState.connecting,
      l10n.terminalConnecting,
    );
    try {
      final apiPath = _terminalApiPath();
      final session = await _createSession();
      final connection = await widget.client.connectTerminalWebSocket(
        apiPath: apiPath,
        session: session,
      );

      if (_disposed) {
        await connection.close();
        return;
      }

      _connection = connection;
      _socketSubscription = connection.socket.listen(
        _handleSocketMessage,
        onDone: () {
          if (!_disposed) {
            _setConnectionState(
              _TerminalConnectionState.disconnected,
              l10n.terminalDisconnected,
            );
          }
        },
        onError: (Object error) {
          if (!_disposed) {
            _setConnectionState(
              _TerminalConnectionState.disconnected,
              localizedError(l10n, error),
            );
          }
        },
      );

      connection.socket.add('${session.user}:${session.ticket}\n');
      _startPing();
    } on Object catch (error) {
      if (!_disposed) {
        _setConnectionState(
          _TerminalConnectionState.disconnected,
          localizedError(l10n, error),
        );
      }
    }
  }

  String _terminalApiPath() {
    final guest = widget._guest;
    if (guest != null) {
      return widget.client.guestTerminalApiPath(guest);
    }
    return widget.client.nodeTerminalApiPath(widget._node!);
  }

  Future<NodeTerminalSession> _createSession() {
    final guest = widget._guest;
    if (guest != null) {
      return widget.client.createGuestTerminalSession(guest);
    }
    return widget.client.createNodeTerminalSession(widget._node!);
  }

  void _handleSocketMessage(dynamic message) {
    if (_disposed) {
      return;
    }

    if (message is String) {
      _handleSocketText(message);
      return;
    }

    if (message is Uint8List) {
      _handleSocketBytes(message);
      return;
    }

    if (message is List<int>) {
      _handleSocketBytes(Uint8List.fromList(message));
    }
  }

  void _handleSocketText(String data) {
    if (_connectionState == _TerminalConnectionState.connecting) {
      if (!data.startsWith('OK')) {
        unawaited(_connection?.close());
        _setConnectionState(
          _TerminalConnectionState.disconnected,
          context.l10n.terminalAuthenticationFailed,
        );
        return;
      }

      _setConnectionState(_TerminalConnectionState.connected, null);
      _sendCurrentSize();
      _requestKeyboardAfterFrame(clearSelection: false);
      final remaining = data.substring(2);
      if (remaining.isNotEmpty) {
        _terminal.write(remaining);
      }
      return;
    }

    if (_connectionState == _TerminalConnectionState.connected) {
      _terminal.write(data);
    }
  }

  void _handleSocketBytes(Uint8List bytes) {
    if (_connectionState == _TerminalConnectionState.connecting) {
      if (bytes.length < 2 || bytes[0] != 0x4f || bytes[1] != 0x4b) {
        unawaited(_connection?.close());
        _setConnectionState(
          _TerminalConnectionState.disconnected,
          context.l10n.terminalAuthenticationFailed,
        );
        return;
      }

      _setConnectionState(_TerminalConnectionState.connected, null);
      _sendCurrentSize();
      _requestKeyboardAfterFrame(clearSelection: false);
      if (bytes.length > 2) {
        _outputBytesController.add(bytes.sublist(2));
      }
      return;
    }

    if (_connectionState == _TerminalConnectionState.connected) {
      _outputBytesController.add(bytes);
    }
  }

  void _sendInput(String data) {
    if (_connectionState != _TerminalConnectionState.connected) {
      return;
    }

    final byteLength = utf8.encode(data).length;
    _connection?.socket.add('0:$byteLength:$data');
  }

  void _sendResize(int columns, int rows, int pixelWidth, int pixelHeight) {
    if (_connectionState != _TerminalConnectionState.connected) {
      return;
    }
    _connection?.socket.add('1:$columns:$rows:');
  }

  void _sendCurrentSize() {
    _sendResize(_terminal.viewWidth, _terminal.viewHeight, 0, 0);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectionState == _TerminalConnectionState.connected) {
        _connection?.socket.add('2');
      }
    });
  }

  Future<void> _reconnect() async {
    if (_reconnectInFlight || _disposed) {
      return;
    }

    _reconnectInFlight = true;
    _setConnectionState(
      _TerminalConnectionState.connecting,
      context.l10n.terminalReconnecting,
    );
    _pingTimer?.cancel();
    try {
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      final connection = _connection;
      _connection = null;
      if (connection != null) {
        await connection.close();
      }
      _terminal.write('\r\n');
      await _connect();
    } finally {
      _reconnectInFlight = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _copySelection() async {
    final selection = _controller.selection;
    if (selection == null) {
      return;
    }

    final text = _terminal.buffer.getText(selection);
    if (text.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    await _showNativeToast(context.l10n.terminalCopied);
  }

  Future<void> _showNativeToast(
    String message, {
    Duration delay = Duration.zero,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final requestId = ++_toastRequestId;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
      if (!mounted || requestId != _toastRequestId) {
        return;
      }
    }
    const channel = MethodChannel('pve_manager/toast');
    await channel.invokeMethod<void>('show', <String, String>{
      'message': message,
    });
  }

  Future<void> _pasteClipboard() async {
    if (!_isInputEnabled) {
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    _terminal.paste(text);
    _controller.clearSelection();
    _focusKeyboard(clearSelection: false);
    if (!mounted) {
      return;
    }
    // Android 13+ shows its own clipboard access overlay first. Delay the
    // requested native toast so it is not hidden behind that system overlay.
    await _showNativeToast(
      context.l10n.terminalPasted,
      delay: const Duration(seconds: 6),
    );
  }

  void _sendShortcut(_TerminalShortcut shortcut) {
    if (!_isInputEnabled) {
      return;
    }

    final ctrl = _ctrlLatch;
    final alt = _altLatch;
    setState(() {
      _ctrlLatch = false;
      _altLatch = false;
    });

    if (shortcut.text != null) {
      final text = shortcut.text!;
      if (text.length == 1) {
        final handled = _terminal.charInput(
          text.codeUnitAt(0),
          ctrl: ctrl,
          alt: alt,
        );
        if (!handled) {
          _terminal.textInput(text);
        }
      } else {
        _terminal.textInput(text);
      }
      _focusKeyboard(clearSelection: false);
      return;
    }
    final key = shortcut.key;
    if (key != null) {
      _terminal.keyInput(key, ctrl: ctrl, alt: alt);
    }
    _focusKeyboard(clearSelection: false);
  }

  void _toggleCtrlLatch() {
    if (!_isInputEnabled) {
      return;
    }

    setState(() {
      _ctrlLatch = !_ctrlLatch;
    });
    _focusKeyboard(clearSelection: false);
  }

  void _toggleAltLatch() {
    if (!_isInputEnabled) {
      return;
    }

    setState(() {
      _altLatch = !_altLatch;
    });
    _focusKeyboard(clearSelection: false);
  }

  void _focusKeyboard({bool clearSelection = true}) {
    if (!_isInputEnabled) {
      return;
    }

    if (clearSelection) {
      _controller.clearSelection();
    }
    _terminalViewKey.currentState?.requestKeyboard();
  }

  void _hideKeyboard() {
    _terminalViewKey.currentState?.closeKeyboard();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _toggleKeyboard() {
    if (!_isInputEnabled) {
      _hideKeyboard();
      return;
    }

    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _hideKeyboard();
      return;
    }
    _focusKeyboard(clearSelection: false);
  }

  void _requestKeyboardAfterFrame({bool clearSelection = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted && _isInputEnabled) {
        _focusKeyboard(clearSelection: clearSelection);
      }
    });
  }

  KeyEventResult _handleTerminalKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyC && _hasSelection) {
      final isCopyShortcut =
          (keyboard.isControlPressed && keyboard.isShiftPressed) ||
          keyboard.isMetaPressed;
      if (isCopyShortcut) {
        unawaited(_copySelection());
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setConnectionState(_TerminalConnectionState state, String? message) {
    if (!mounted) {
      return;
    }
    _syncFocusAvailability(state);
    setState(() {
      _connectionState = state;
      _statusMessage = message;
    });
  }

  bool get _hasSelection => _controller.selection != null;
  bool get _isInputEnabled =>
      _connectionState == _TerminalConnectionState.connected && !_disposed;

  void _syncFocusAvailability(_TerminalConnectionState state) {
    final canRequestFocus = state == _TerminalConnectionState.connected;
    _focusNode.canRequestFocus = canRequestFocus;
    if (!canRequestFocus) {
      _focusNode.unfocus();
      _hideKeyboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = terminalScreenBackgroundColor(colorScheme);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        title: Text(widget.title),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return IconButton(
                tooltip: MaterialLocalizations.of(context).copyButtonLabel,
                onPressed: _hasSelection ? _copySelection : null,
                icon: const Icon(Icons.copy_rounded),
              );
            },
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).pasteButtonLabel,
            onPressed: _pasteClipboard,
            icon: const Icon(Icons.content_paste_rounded),
          ),
          IconButton(
            tooltip: context.l10n.reconnect,
            onPressed:
                _connectionState == _TerminalConnectionState.connecting ||
                    _reconnectInFlight
                ? null
                : () => unawaited(_reconnect()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  IgnorePointer(
                    ignoring:
                        _connectionState == _TerminalConnectionState.connecting,
                    child: TerminalView(
                      _terminal,
                      key: _terminalViewKey,
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: _isInputEnabled,
                      theme: buildTerminalTheme(colorScheme),
                      textStyle: const TerminalStyle(
                        fontSize: 13,
                        height: 1.18,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      keyboardType: TextInputType.visiblePassword,
                      cursorType: TerminalCursorType.block,
                      alwaysShowCursor: true,
                      deleteDetection: true,
                      onKeyEvent: _handleTerminalKeyEvent,
                    ),
                  ),
                  if (_connectionState == _TerminalConnectionState.connecting)
                    Positioned.fill(
                      child: _TerminalLoadingView(
                        label: context.l10n.terminalConnecting,
                      ),
                    )
                  else if (_statusMessage != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: _TerminalStatusBanner(
                        state: _connectionState,
                        message: _statusMessage!,
                      ),
                    ),
                ],
              ),
            ),
            if (_connectionState != _TerminalConnectionState.connecting)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return _TerminalShortcutBar(
                    ctrlActive: _ctrlLatch,
                    altActive: _altLatch,
                    onShortcut: _sendShortcut,
                    onToggleCtrl: _toggleCtrlLatch,
                    onToggleAlt: _toggleAltLatch,
                    onFocusKeyboard: _focusKeyboard,
                    onToggleKeyboard: _toggleKeyboard,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  static TerminalTargetPlatform _terminalPlatform() {
    if (kIsWeb) {
      return TerminalTargetPlatform.web;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => TerminalTargetPlatform.android,
      TargetPlatform.iOS => TerminalTargetPlatform.ios,
      TargetPlatform.macOS => TerminalTargetPlatform.macos,
      TargetPlatform.windows => TerminalTargetPlatform.windows,
      TargetPlatform.linux => TerminalTargetPlatform.linux,
      TargetPlatform.fuchsia => TerminalTargetPlatform.fuchsia,
    };
  }
}

enum _TerminalConnectionState { connecting, connected, disconnected }

class _TerminalLoadingView extends StatelessWidget {
  const _TerminalLoadingView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: terminalScreenBackgroundColor(colorScheme),
      child: Center(
        child: Semantics(
          label: label,
          child: SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalStatusBanner extends StatelessWidget {
  const _TerminalStatusBanner({required this.state, required this.message});

  final _TerminalConnectionState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = switch (state) {
      _TerminalConnectionState.connecting => colorScheme.tertiary,
      _TerminalConnectionState.connected => colorScheme.primary,
      _TerminalConnectionState.disconnected => colorScheme.error,
    };
    final foreground = switch (state) {
      _TerminalConnectionState.connecting => colorScheme.onTertiaryContainer,
      _TerminalConnectionState.connected => colorScheme.onPrimaryContainer,
      _TerminalConnectionState.disconnected => colorScheme.onErrorContainer,
    };
    final container = switch (state) {
      _TerminalConnectionState.connecting => colorScheme.tertiaryContainer,
      _TerminalConnectionState.connected => colorScheme.primaryContainer,
      _TerminalConnectionState.disconnected => colorScheme.errorContainer,
    };
    final background = Color.alphaBlend(
      container.withValues(alpha: 0.72),
      colorScheme.surfaceContainerHighest,
    );

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 14, 10),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 32,
                      child: Center(
                        child: state == _TerminalConnectionState.connecting
                            ? SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  strokeCap: StrokeCap.round,
                                  color: accent,
                                ),
                              )
                            : Icon(
                                state == _TerminalConnectionState.connected
                                    ? Icons.check_rounded
                                    : Icons.priority_high_rounded,
                                size: 19,
                                color: accent,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (state == _TerminalConnectionState.connecting)
              LinearProgressIndicator(
                minHeight: 3,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TerminalShortcut {
  const _TerminalShortcut({required this.label, this.key, this.text});

  final String label;
  final TerminalKey? key;
  final String? text;
}

const _terminalShortcutRows = <List<_TerminalShortcut>>[
  <_TerminalShortcut>[
    _TerminalShortcut(label: 'ESC', key: TerminalKey.escape),
    _TerminalShortcut(label: '/', text: '/'),
    _TerminalShortcut(label: '|', text: '|'),
    _TerminalShortcut(label: 'HOME', key: TerminalKey.home),
    _TerminalShortcut(label: '↑', key: TerminalKey.arrowUp),
    _TerminalShortcut(label: 'END', key: TerminalKey.end),
    _TerminalShortcut(label: 'PGUP', key: TerminalKey.pageUp),
  ],
  <_TerminalShortcut>[
    _TerminalShortcut(label: 'TAB', key: TerminalKey.tab),
    _TerminalShortcut(label: '←', key: TerminalKey.arrowLeft),
    _TerminalShortcut(label: '↓', key: TerminalKey.arrowDown),
    _TerminalShortcut(label: '→', key: TerminalKey.arrowRight),
    _TerminalShortcut(label: 'PGDN', key: TerminalKey.pageDown),
  ],
];

class _TerminalShortcutBar extends StatelessWidget {
  const _TerminalShortcutBar({
    required this.ctrlActive,
    required this.altActive,
    required this.onShortcut,
    required this.onToggleCtrl,
    required this.onToggleAlt,
    required this.onFocusKeyboard,
    required this.onToggleKeyboard,
  });

  final bool ctrlActive;
  final bool altActive;
  final ValueChanged<_TerminalShortcut> onShortcut;
  final VoidCallback onToggleCtrl;
  final VoidCallback onToggleAlt;
  final VoidCallback onFocusKeyboard;
  final VoidCallback onToggleKeyboard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: terminalShortcutBarBackgroundColor(colorScheme),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TerminalShortcutRow(
              children: [
                for (final shortcut in _terminalShortcutRows[0])
                  TerminalShortcutTile.button(
                    label: shortcut.label,
                    onPressed: () => onShortcut(shortcut),
                  ),
                TerminalShortcutTile.button(
                  label: 'FN',
                  onPressed: onFocusKeyboard,
                ),
              ],
            ),
            _TerminalShortcutRow(
              children: [
                TerminalShortcutTile.button(
                  label: 'TAB',
                  onPressed: () => onShortcut(_terminalShortcutRows[1][0]),
                ),
                TerminalShortcutTile.button(
                  label: 'CTRL',
                  active: ctrlActive,
                  onPressed: onToggleCtrl,
                ),
                TerminalShortcutTile.button(
                  label: 'ALT',
                  active: altActive,
                  onPressed: onToggleAlt,
                ),
                for (final shortcut in _terminalShortcutRows[1].skip(1))
                  TerminalShortcutTile.button(
                    label: shortcut.label,
                    onPressed: () => onShortcut(shortcut),
                  ),
                TerminalShortcutTile.icon(
                  icon: Icons.keyboard_alt_rounded,
                  onPressed: onToggleKeyboard,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalShortcutRow extends StatelessWidget {
  const _TerminalShortcutRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: terminalShortcutCellExtent,
      child: Row(
        children: [for (final child in children) Expanded(child: child)],
      ),
    );
  }
}
