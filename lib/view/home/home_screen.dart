import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/pve_server_config.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';
import 'package:pve_manager/view/dashboard/dashboard_screen.dart';
import 'package:pve_manager/data/repositories/server_repository.dart';
import 'package:pve_manager/core/widgets/inline_message.dart';
import 'package:pve_manager/view/home/widgets/empty_servers.dart';
import 'package:pve_manager/view/home/widgets/server_card.dart';
import 'package:pve_manager/view/home/widgets/server_form_dialog.dart';
import 'package:pve_manager/view/settings/settings_screen.dart';

enum _ServerAction { edit, delete }

const double _settingsSidebarWidth = 400;
const double _settingsSidebarBreakpoint = 840;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.autoRefreshIntervalListenable,
    required this.onAutoRefreshIntervalChanged,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final ValueListenable<Duration> autoRefreshIntervalListenable;
  final AsyncValueSetter<Duration> onAutoRefreshIntervalChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<PveServerConfig> _servers = <PveServerConfig>[];
  final ServerRepository _repository = ServerRepository.instance;
  Timer? _refreshTimer;
  bool _isInitializing = true;
  bool _isLoading = false;
  Object? _connectingServerKey;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.autoRefreshIntervalListenable.addListener(_startRefreshTimer);
    _startRefreshTimer();
    _loadServers();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
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
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.autoRefreshIntervalListenable.value, (
      _,
    ) {
      if (mounted &&
          !_isLoading &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        _loadServers();
      }
    });
  }

  Future<void> _loadServers() async {
    try {
      final servers = await _repository.getServers();
      if (!mounted) {
        return;
      }
      setState(() {
        _servers
          ..clear()
          ..addAll(servers);
        _isInitializing = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = localizedError(context.l10n, error);
        _isInitializing = false;
      });
    }
  }

  Future<void> _openServerForm({PveServerConfig? server, int? index}) async {
    final result = await showDialog<PveServerConfig>(
      context: context,
      builder: (context) => ServerFormDialog(server: server),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      final serverToSave = index == null
          ? result
          : result.copyWith(
              id: server?.id,
              lastConnectedAt: server?.lastConnectedAt,
            );
      final saved = await _repository.saveServer(serverToSave);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = null;
        if (index == null) {
          _servers.insert(0, saved);
        } else {
          final currentIndex = _servers.indexWhere(
            (item) => item.id == saved.id,
          );
          if (currentIndex != -1) {
            _servers[currentIndex] = saved;
          }
        }
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = localizedError(context.l10n, error);
      });
    }
  }

  Future<void> _showServerActions(int index) async {
    final server = _servers[index];
    final action = await showModalBottomSheet<_ServerAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(context.l10n.edit),
              subtitle: Text(server.name),
              onTap: () => Navigator.of(context).pop(_ServerAction.edit),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.l10n.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_ServerAction.delete),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ServerAction.edit:
        await _openServerForm(server: server, index: index);
      case _ServerAction.delete:
        try {
          final id = server.id;
          if (id != null) {
            await _repository.deleteServer(id);
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _servers.removeWhere(
              (item) => _serverKey(item) == _serverKey(server),
            );
            _error = null;
          });
        } on Object catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = localizedError(context.l10n, error);
          });
        }
    }
  }

  Future<void> _openSettings() async {
    if (MediaQuery.sizeOf(context).width >= _settingsSidebarBreakpoint) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.24),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: _settingsSidebarWidth,
              height: double.infinity,
              child: SettingsScreen(
                locale: widget.locale,
                onLocaleChanged: widget.onLocaleChanged,
                autoRefreshIntervalListenable:
                    widget.autoRefreshIntervalListenable,
                onAutoRefreshIntervalChanged:
                    widget.onAutoRefreshIntervalChanged,
                embedded: true,
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          locale: widget.locale,
          onLocaleChanged: widget.onLocaleChanged,
          autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
          onAutoRefreshIntervalChanged: widget.onAutoRefreshIntervalChanged,
        ),
      ),
    );
  }

  Future<void> _connect(PveServerConfig server) async {
    if (_isLoading) {
      return;
    }

    if (kIsWeb) {
      setState(() {
        _error = context.l10n.webConsoleUnsupported;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _connectingServerKey = _serverKey(server);
      _error = null;
    });

    final client = server.createClient();

    try {
      final loggedIn = await _loginWithOptionalTfa(client);
      if (!loggedIn) {
        client.close();
        return;
      }
      client.preloadClusterNodeThermalStates();
      unawaited(client.preloadClusterGuestDiskUsage());
      if (!mounted) {
        client.close();
        return;
      }
      final connectedServer = await _repository.markConnected(server);
      if (!mounted) {
        client.close();
        return;
      }
      setState(() {
        final index = _servers.indexWhere((item) => item.id == server.id);
        if (index != -1) {
          _servers[index] = connectedServer;
        }
        _isLoading = false;
        _connectingServerKey = null;
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DashboardScreen(
            client: client,
            serverName: server.name,
            autoRefreshIntervalListenable: widget.autoRefreshIntervalListenable,
          ),
        ),
      );
    } on Object catch (error) {
      client.close();
      if (!mounted) {
        return;
      }
      setState(() {
        _error = localizedError(context.l10n, error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _connectingServerKey = null;
        });
      }
    }
  }

  Future<bool> _loginWithOptionalTfa(ProxmoxClient client) async {
    try {
      await client.login();
      return true;
    } on ProxmoxTfaRequiredException catch (challenge) {
      if (!mounted) {
        return false;
      }

      return _showTwoFactorDialog(client: client, challenge: challenge);
    }
  }

  Future<bool> _showTwoFactorDialog({
    required ProxmoxClient client,
    required ProxmoxTfaRequiredException challenge,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _TwoFactorDialog(client: client, challenge: challenge),
    );
    return result ?? false;
  }

  Object _serverKey(PveServerConfig server) {
    return server.id ??
        Object.hash(
          server.origin,
          server.username,
          server.realm,
          server.authMode,
          server.apiTokenId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.appTitle),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: l10n.settings,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: _isInitializing || _servers.isEmpty
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isInitializing)
                    const Center(child: CircularProgressIndicator())
                  else if (_servers.isEmpty)
                    EmptyServers(onAdd: () => _openServerForm())
                  else
                    Flexible(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(top: 8),
                        shrinkWrap: true,
                        itemCount: _servers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final server = _servers[index];
                          return ServerCard(
                            server: server,
                            isConnecting:
                                _isLoading &&
                                _connectingServerKey == _serverKey(server),
                            onTap: () => _connect(server),
                            onLongPress: () => _showServerActions(index),
                          );
                        },
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    InlineMessage(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addServer,
        onPressed: () => _openServerForm(),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _TwoFactorDialog extends StatefulWidget {
  const _TwoFactorDialog({required this.client, required this.challenge});

  final ProxmoxClient client;
  final ProxmoxTfaRequiredException challenge;

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.client.completeTwoFactor(
        widget.challenge,
        _controller.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = localizedError(context.l10n, error);
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.twoFactorTitle),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_isSubmitting,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  labelText: l10n.twoFactorCode,
                  hintText: l10n.twoFactorCodeHint,
                  prefixIcon: const Icon(Icons.pin_rounded),
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => unawaited(_submit()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.enterTwoFactorCode;
                  }
                  return null;
                },
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _submitError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : () => unawaited(_submit()),
          child: _isSubmitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.verify),
                  ],
                )
              : Text(l10n.verify),
        ),
      ],
    );
  }
}
