import 'package:pve_manager/l10n/generated/app_localizations.dart';

String normalizeOrigin(String value) {
  final uri = _parseOrigin(value);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw const FormatException('Invalid Proxmox address');
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : 8006,
  ).toString();
}

String? validateOrigin(AppLocalizations l10n, String? value) {
  if (value == null || value.trim().isEmpty) {
    return l10n.enterProxmoxAddress;
  }

  final uri = _parseOrigin(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return l10n.invalidAddress;
  }

  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return l10n.unsupportedScheme;
  }

  return null;
}

Uri? _parseOrigin(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  // Preserve an explicitly supplied scheme so unsupported schemes are not
  // accidentally treated as part of a hostname (for example, ftp://host).
  final hasScheme = RegExp(
    r'^[a-z][a-z0-9+.-]*://',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final candidate = hasScheme ? trimmed : 'https://$trimmed';
  return Uri.tryParse(candidate);
}

String? requiredField(String? value, String message) {
  return value == null || value.trim().isEmpty ? message : null;
}
