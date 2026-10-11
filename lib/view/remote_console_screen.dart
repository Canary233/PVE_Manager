import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/view/terminal_visuals.dart';

class RemoteConsoleScreen extends StatefulWidget {
  const RemoteConsoleScreen({
    required this.title,
    required this.uri,
    required this.authCookie,
    this.authCookieName = 'PVEAuthCookie',
    this.terminalMode = false,
    required this.ignoreCertificateErrors,
    required this.loadFailedTemplate,
    required this.unknownErrorMessage,
    required this.certificateErrorMessage,
    required this.errorHint,
    super.key,
  });

  final String title;
  final Uri uri;
  final String authCookie;
  final String authCookieName;
  final bool terminalMode;
  final bool ignoreCertificateErrors;
  final String loadFailedTemplate;
  final String unknownErrorMessage;
  final String certificateErrorMessage;
  final String errorHint;

  @override
  State<RemoteConsoleScreen> createState() => _RemoteConsoleScreenState();
}

class _RemoteConsoleScreenState extends State<RemoteConsoleScreen> {
  WebviewController _controller = WebviewController();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  bool _controllerInitializeStarted = false;
  bool _initializeInFlight = false;
  Future<void>? _controllerDisposal;
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _ctrlLatch = false;
  bool _altLatch = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializeInFlight || !mounted) {
      return;
    }
    _initializeInFlight = true;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // A failed setup may already have a native view and single-listener
      // streams. Release that instance before attempting a fresh setup.
      if (_controllerInitializeStarted) {
        for (final subscription in _subscriptions) {
          await subscription.cancel();
        }
        _subscriptions.clear();
        await _disposeController();
        if (!mounted) {
          return;
        }
        _controller = WebviewController();
        _controllerDisposal = null;
        _controllerInitializeStarted = false;
      }
      await _initializeCertificatePolicy();
      if (!mounted) {
        return;
      }

      _controllerInitializeStarted = true;
      await _controller.initialize();
      if (!mounted) {
        return;
      }

      _subscriptions.add(
        _controller.loadingState.listen((state) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isLoading = state == LoadingState.loading;
            if (_isLoading) {
              _errorMessage = null;
            }
          });
          if (widget.terminalMode &&
              state == LoadingState.navigationCompleted) {
            unawaited(_focusTerminal());
          }
        }),
      );
      _subscriptions.add(_controller.onLoadError.listen(_handleLoadError));

      final webviewBackgroundColor = widget.terminalMode
          ? terminalConsoleBackgroundColor(Theme.of(context).colorScheme)
          : Colors.black;
      await _controller.setBackgroundColor(webviewBackgroundColor);
      if (!mounted) {
        return;
      }
      await _controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      await _controller.addScriptToExecuteOnDocumentCreated(
        _buildAuthenticationBootstrapScript(),
      );
      if (!mounted) {
        return;
      }
      if (widget.terminalMode) {
        await _controller.addScriptToExecuteOnDocumentCreated(
          _buildTerminalBootstrapScript(),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isInitialized = true;
      });
      await _loadConsole();
    } on PlatformException catch (error) {
      _showLoadFailure(error.message ?? error.code);
    } on Object catch (error) {
      _showLoadFailure(error.toString());
    } finally {
      _initializeInFlight = false;
    }
  }

  Future<void> _initializeCertificatePolicy() async {
    if (!widget.ignoreCertificateErrors) {
      return;
    }

    try {
      await WebviewController.initializeEnvironment(
        additionalArguments: '--ignore-certificate-errors',
      );
    } on PlatformException catch (error) {
      if (error.code != 'environment_already_initialized') {
        rethrow;
      }
    }
  }

  Future<void> _loadConsole() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _controller.loadUrl(widget.uri.toString());
    } on PlatformException catch (error) {
      _showLoadFailure(error.message ?? error.code);
    } on Object catch (error) {
      _showLoadFailure(error.toString());
    }
  }

  String _buildAuthenticationBootstrapScript() {
    final cookie = [
      '${widget.authCookieName}=${widget.authCookie}',
      'Path=/',
      'SameSite=Strict',
      if (widget.uri.scheme == 'https') 'Secure',
    ].join('; ');
    final origin = widget.uri.origin.toLowerCase();
    final marker =
        '${widget.uri.toString().hashCode}:${widget.authCookie.hashCode}';

    return '''
(() => {
  if (window.top !== window.self) {
    return;
  }
  if (location.origin.toLowerCase() !== ${jsonEncode(origin)}) {
    return;
  }

  document.cookie = ${jsonEncode(cookie)};

  const key = '__pve_manager_console_cookie_loaded';
  const marker = ${jsonEncode(marker)};
  if (sessionStorage.getItem(key) !== marker) {
    sessionStorage.setItem(key, marker);
    location.replace(${jsonEncode(widget.uri.toString())});
  }
})();
''';
  }

  String _buildTerminalBootstrapScript() {
    return '''
(() => {
  const terminalColor = ${jsonEncode(terminalBackgroundCssColor(Theme.of(context).colorScheme))};
  const apply = () => {
    if (document.documentElement) {
      document.documentElement.style.background = terminalColor;
    }
    if (document.body) {
      document.body.style.background = terminalColor;
    }
    const focusTarget =
      document.querySelector('.xterm-helper-textarea, textarea, input, canvas') ||
      document.body;
    if (focusTarget && typeof focusTarget.focus === 'function') {
      focusTarget.focus();
    }
  };
  apply();
  window.addEventListener('load', apply, { once: true });
})();
''';
  }

  void _handleLoadError(WebErrorStatus status) {
    if (status == WebErrorStatus.WebErrorStatusOperationCanceled) {
      return;
    }

    if (_isCertificateError(status)) {
      _setError(widget.certificateErrorMessage);
      return;
    }

    _showLoadFailure(_describeWebError(status));
  }

  bool _isCertificateError(WebErrorStatus status) {
    return switch (status) {
      WebErrorStatus.WebErrorStatusCertificateCommonNameIsIncorrect ||
      WebErrorStatus.WebErrorStatusCertificateExpired ||
      WebErrorStatus.WebErrorStatusClientCertificateContainsErrors ||
      WebErrorStatus.WebErrorStatusCertificateRevoked ||
      WebErrorStatus.WebErrorStatusCertificateIsInvalid => true,
      _ => false,
    };
  }

  String _describeWebError(WebErrorStatus status) {
    if (status == WebErrorStatus.WebErrorStatusUnknown ||
        status == WebErrorStatus.WebErrorStatusUnexpectedError) {
      return widget.unknownErrorMessage;
    }

    final raw = status.name.replaceFirst('WebErrorStatus', '');
    return raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll('HTTP', 'HTTP ');
  }

  void _showLoadFailure(String description) {
    _setError(
      widget.loadFailedTemplate.replaceAll('{description}', description),
    );
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  Future<WebviewPermissionDecision> _handlePermissionRequest(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async {
    final requestUri = Uri.tryParse(url);
    final isConsoleOrigin =
        requestUri != null &&
        requestUri.scheme == widget.uri.scheme &&
        requestUri.host == widget.uri.host &&
        requestUri.port == widget.uri.port;
    if (mounted &&
        kind == WebviewPermissionKind.clipboardRead &&
        isUserInitiated &&
        isConsoleOrigin) {
      return WebviewPermissionDecision.allow;
    }
    return WebviewPermissionDecision.deny;
  }

  Future<void> _focusTerminal() async {
    if (!mounted || !_isInitialized) {
      return;
    }

    try {
      await _controller.executeScript('''
(() => {
  const focusIn = (win) => {
    try {
      const doc = win.document;
      const target =
        doc.querySelector('.xterm-helper-textarea, textarea, input, canvas') ||
        doc.body;
      if (target && typeof target.focus === 'function') {
        target.focus();
        return true;
      }
    } catch (_) {}
    return false;
  };
  if (focusIn(window)) {
    return true;
  }
  for (const frame of document.querySelectorAll('iframe')) {
    if (frame.contentWindow && focusIn(frame.contentWindow)) {
      return true;
    }
  }
  return false;
})();
''');
    } on Object {
      // The WebView can be navigating while the shortcut bar asks for focus.
    }
  }

  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _toggleKeyboard() {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _hideKeyboard();
      return;
    }
    unawaited(_focusTerminal());
  }

  Future<void> _sendTerminalShortcut(_TerminalShortcut shortcut) async {
    if (!mounted || !_isInitialized) {
      return;
    }

    final ctrlKey = _ctrlLatch;
    final altKey = _altLatch;
    setState(() {
      _ctrlLatch = false;
      _altLatch = false;
    });

    try {
      await _controller.executeScript(
        _terminalKeyScript(shortcut, ctrlKey: ctrlKey, altKey: altKey),
      );
    } on Object {
      // Keep the terminal UI responsive if the page is mid-navigation.
    }
  }

  String _terminalKeyScript(
    _TerminalShortcut shortcut, {
    required bool ctrlKey,
    required bool altKey,
  }) {
    final key = jsonEncode(shortcut.key);
    final code = jsonEncode(shortcut.code);
    final keyCode = shortcut.keyCode;
    final shiftKey = shortcut.shiftKey;
    final emitKeyPress = shortcut.key.length == 1;

    return '''
(() => {
  const init = {
    key: $key,
    code: $code,
    keyCode: $keyCode,
    which: $keyCode,
    bubbles: true,
    cancelable: true,
    composed: true,
    ctrlKey: $ctrlKey,
    altKey: $altKey,
    shiftKey: $shiftKey,
    metaKey: false
  };
  const dispatchIn = (win) => {
    try {
      const doc = win.document;
      const target =
        doc.activeElement ||
        doc.querySelector('.xterm-helper-textarea, textarea, input, canvas') ||
        doc.body;
      if (!target) {
        return false;
      }
      if (typeof target.focus === 'function') {
        target.focus();
      }
      target.dispatchEvent(new KeyboardEvent('keydown', init));
      if ($emitKeyPress) {
        target.dispatchEvent(new KeyboardEvent('keypress', init));
      }
      target.dispatchEvent(new KeyboardEvent('keyup', init));
      return true;
    } catch (_) {
      return false;
    }
  };
  if (dispatchIn(window)) {
    return true;
  }
  for (const frame of document.querySelectorAll('iframe')) {
    if (frame.contentWindow && dispatchIn(frame.contentWindow)) {
      return true;
    }
  }
  return false;
})();
''';
  }

  void _toggleCtrl() {
    setState(() {
      _ctrlLatch = !_ctrlLatch;
    });
  }

  void _toggleAlt() {
    setState(() {
      _altLatch = !_altLatch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = widget.terminalMode
        ? terminalScreenBackgroundColor(colorScheme)
        : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: widget.terminalMode
          ? AppBar(
              toolbarHeight: 44,
              backgroundColor: backgroundColor,
              surfaceTintColor: Colors.transparent,
              foregroundColor: colorScheme.onSurface,
              title: Text(widget.title),
              actions: [
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: _isInitialized ? _loadConsole : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : AppBar(
              backgroundColor: colorScheme.surfaceContainerLow,
              surfaceTintColor: Colors.transparent,
              title: Text(widget.title),
              actions: [
                IconButton(
                  tooltip: l10n.refresh,
                  onPressed: _isInitialized ? _loadConsole : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      body: ColoredBox(
        color: backgroundColor,
        child: Column(
          children: [
            SizedBox(
              height: widget.terminalMode ? 2 : 3,
              child: _isLoading ? const LinearProgressIndicator() : null,
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_isInitialized)
                    Positioned.fill(
                      child: Webview(
                        _controller,
                        permissionRequested: _handlePermissionRequest,
                      ),
                    )
                  else if (_errorMessage == null)
                    const Center(child: CircularProgressIndicator()),
                  if (_errorMessage != null)
                    Positioned.fill(
                      child: _ConsoleErrorOverlay(
                        message: _errorMessage!,
                        hint: widget.errorHint,
                        onRetry: _isInitialized ? _loadConsole : _initialize,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.terminalMode)
              _TerminalShortcutBar(
                ctrlActive: _ctrlLatch,
                altActive: _altLatch,
                onShortcut: (shortcut) {
                  unawaited(_sendTerminalShortcut(shortcut));
                },
                onToggleCtrl: _toggleCtrl,
                onToggleAlt: _toggleAlt,
                onFocusKeyboard: () {
                  unawaited(_focusTerminal());
                },
                onToggleKeyboard: _toggleKeyboard,
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_controllerInitializeStarted) {
      unawaited(_disposeController());
    }
    super.dispose();
  }

  Future<void> _disposeController() =>
      _controllerDisposal ??= _disposeControllerInstance(_controller);

  Future<void> _disposeControllerInstance(WebviewController controller) async {
    try {
      await controller.dispose();
    } on Object {
      // The controller may be mid-initialization when the route is closed.
    }
  }
}

class _ConsoleErrorOverlay extends StatelessWidget {
  const _ConsoleErrorOverlay({
    required this.message,
    required this.hint,
    required this.onRetry,
  });

  final String message;
  final String hint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.desktop_access_disabled_rounded,
                  color: colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalShortcut {
  const _TerminalShortcut({
    required this.label,
    required this.key,
    required this.code,
    required this.keyCode,
    this.shiftKey = false,
  });

  final String label;
  final String key;
  final String code;
  final int keyCode;
  final bool shiftKey;
}

const _terminalShortcutRows = <List<_TerminalShortcut>>[
  <_TerminalShortcut>[
    _TerminalShortcut(label: 'ESC', key: 'Escape', code: 'Escape', keyCode: 27),
    _TerminalShortcut(label: '/', key: '/', code: 'Slash', keyCode: 191),
    _TerminalShortcut(
      label: '|',
      key: '|',
      code: 'Backslash',
      keyCode: 220,
      shiftKey: true,
    ),
    _TerminalShortcut(label: 'HOME', key: 'Home', code: 'Home', keyCode: 36),
    _TerminalShortcut(label: '↑', key: 'ArrowUp', code: 'ArrowUp', keyCode: 38),
    _TerminalShortcut(label: 'END', key: 'End', code: 'End', keyCode: 35),
    _TerminalShortcut(
      label: 'PGUP',
      key: 'PageUp',
      code: 'PageUp',
      keyCode: 33,
    ),
  ],
  <_TerminalShortcut>[
    _TerminalShortcut(label: 'TAB', key: 'Tab', code: 'Tab', keyCode: 9),
    _TerminalShortcut(
      label: '←',
      key: 'ArrowLeft',
      code: 'ArrowLeft',
      keyCode: 37,
    ),
    _TerminalShortcut(
      label: '↓',
      key: 'ArrowDown',
      code: 'ArrowDown',
      keyCode: 40,
    ),
    _TerminalShortcut(
      label: '→',
      key: 'ArrowRight',
      code: 'ArrowRight',
      keyCode: 39,
    ),
    _TerminalShortcut(
      label: 'PGDN',
      key: 'PageDown',
      code: 'PageDown',
      keyCode: 34,
    ),
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
