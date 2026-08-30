import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/services/proxmox_client.dart';

class PveServerConfig {
  const PveServerConfig({
    this.id,
    required this.name,
    required this.origin,
    required this.username,
    required this.password,
    required this.realm,
    required this.ignoreCertificateErrors,
    this.authMode = ProxmoxAuthMode.password,
    this.apiTokenId = '',
    this.apiTokenSecret = '',
    this.lastConnectedAt,
  });

  final int? id;
  final String name;
  final String origin;
  final String username;
  final String password;
  final String realm;
  final bool ignoreCertificateErrors;
  final ProxmoxAuthMode authMode;
  final String apiTokenId;
  final String apiTokenSecret;
  final int? lastConnectedAt;

  String get host => Uri.parse(origin).host;
  String get userId => username.contains('@') ? username : '$username@$realm';
  ProxmoxApiTokenCredentials get apiTokenCredentials =>
      ProxmoxApiTokenCredentials.fromInput(
        username: username,
        realm: realm,
        tokenId: apiTokenId,
        tokenSecret: apiTokenSecret,
      );
  String get accountLabel => authMode == ProxmoxAuthMode.apiToken
      ? apiTokenCredentials.accountLabel
      : userId;

  PveServerConfig copyWith({
    int? id,
    String? name,
    String? origin,
    String? username,
    String? password,
    String? realm,
    bool? ignoreCertificateErrors,
    ProxmoxAuthMode? authMode,
    String? apiTokenId,
    String? apiTokenSecret,
    int? lastConnectedAt,
  }) {
    return PveServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      origin: origin ?? this.origin,
      username: username ?? this.username,
      password: password ?? this.password,
      realm: realm ?? this.realm,
      ignoreCertificateErrors:
          ignoreCertificateErrors ?? this.ignoreCertificateErrors,
      authMode: authMode ?? this.authMode,
      apiTokenId: apiTokenId ?? this.apiTokenId,
      apiTokenSecret: apiTokenSecret ?? this.apiTokenSecret,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  factory PveServerConfig.fromMap(Map<String, Object?> map) {
    return PveServerConfig(
      id: map['id'] as int?,
      name: map['name']?.toString() ?? '',
      origin: map['origin']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      realm: map['realm']?.toString() ?? 'pam',
      ignoreCertificateErrors:
          (map['ignore_certificate_errors'] as int? ?? 0) == 1,
      authMode: ProxmoxAuthMode.fromStorage(map['auth_type']),
      apiTokenId: map['api_token_id']?.toString() ?? '',
      apiTokenSecret: map['api_token_secret']?.toString() ?? '',
      lastConnectedAt: map['last_connected_at'] as int?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'origin': origin,
      'username': username,
      'password': password,
      'realm': realm,
      'ignore_certificate_errors': ignoreCertificateErrors ? 1 : 0,
      'auth_type': authMode.storageValue,
      'api_token_id': apiTokenId,
      'api_token_secret': apiTokenSecret,
      'last_connected_at': lastConnectedAt,
    };
  }

  /// Returns the SQLite representation without secrets.
  Map<String, Object?> toDatabaseMap() {
    final map = toMap();
    map['password'] = '';
    map['api_token_secret'] = '';
    return map;
  }

  ProxmoxClient createClient() {
    final tokenCredentials = apiTokenCredentials;
    return ProxmoxClient(
      origin: origin,
      username: authMode == ProxmoxAuthMode.apiToken
          ? tokenCredentials.username
          : username,
      password: password,
      realm: authMode == ProxmoxAuthMode.apiToken
          ? tokenCredentials.realm
          : realm,
      authMode: authMode,
      apiTokenId: authMode == ProxmoxAuthMode.apiToken
          ? tokenCredentials.tokenId
          : apiTokenId,
      apiTokenSecret: authMode == ProxmoxAuthMode.apiToken
          ? tokenCredentials.secret
          : apiTokenSecret,
      ignoreCertificateErrors: ignoreCertificateErrors,
    );
  }
}
