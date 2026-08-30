import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:pve_manager/l10n/generated/app_localizations.dart';
import 'package:pve_manager/data/models/guest_action.dart';
import 'package:pve_manager/data/models/node_power_action.dart';
import 'package:pve_manager/data/services/app_update_service.dart';
import 'package:pve_manager/data/services/proxmox_api_exception.dart';

extension BuildContextLocalizations on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension GuestActionLocalizations on GuestAction {
  String localizedLabel(AppLocalizations l10n) {
    return switch (this) {
      GuestAction.start => l10n.start,
      GuestAction.shutdown => l10n.shutdown,
      GuestAction.reboot => l10n.reboot,
      GuestAction.stop => l10n.stop,
    };
  }
}

extension NodePowerActionLocalizations on NodePowerAction {
  String localizedLabel(AppLocalizations l10n) {
    return switch (this) {
      NodePowerAction.reboot => l10n.rebootNode,
      NodePowerAction.shutdown => l10n.shutdownNode,
    };
  }
}

String localizedResourceType(AppLocalizations l10n, String type) {
  return switch (type) {
    'qemu' => 'VM',
    'lxc' => 'CT',
    'node' => l10n.node,
    'storage' => l10n.storageType,
    _ => type.toUpperCase(),
  };
}

String localizedStatus(AppLocalizations l10n, String status) {
  return switch (status) {
    'online' => l10n.online,
    'running' => l10n.running,
    'stopped' => l10n.stopped,
    'permissionDenied' => l10n.noPermission,
    _ => status,
  };
}

String localizedError(AppLocalizations l10n, Object error) {
  if (error is AppUpdateException) {
    return l10n.updateCheckFailed;
  }
  if (error is ProxmoxApiException) {
    return error.localizedMessage(l10n);
  }
  if (error is SocketException) {
    return l10n.socketError;
  }
  if (error is HandshakeException) {
    return l10n.handshakeError;
  }
  if (error is TimeoutException) {
    return l10n.timeoutError;
  }
  if (error is FormatException) {
    return l10n.formatError;
  }
  return error.toString();
}
