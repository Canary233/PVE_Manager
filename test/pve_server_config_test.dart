import 'package:flutter_test/flutter_test.dart';
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/models/pve_server_config.dart';

void main() {
  test('api token server config round trips through database map', () {
    const config = PveServerConfig(
      id: 7,
      name: 'Token server',
      origin: 'https://pve.example:8006',
      username: 'alice',
      password: '',
      realm: 'pve',
      authMode: ProxmoxAuthMode.apiToken,
      apiTokenId: 'mobile',
      apiTokenSecret: 'secret-uuid',
      ignoreCertificateErrors: true,
      lastConnectedAt: 123,
    );

    final restored = PveServerConfig.fromMap(config.toMap());

    expect(restored.authMode, ProxmoxAuthMode.apiToken);
    expect(restored.apiTokenId, 'mobile');
    expect(restored.apiTokenSecret, 'secret-uuid');
    expect(restored.accountLabel, 'alice@pve!mobile');

    final databaseMap = config.toDatabaseMap();
    expect(databaseMap['password'], isEmpty);
    expect(databaseMap['api_token_secret'], isEmpty);
  });

  test('legacy server config defaults to password authentication', () {
    final restored = PveServerConfig.fromMap({
      'name': 'Legacy',
      'origin': 'https://pve.example:8006',
      'username': 'root',
      'password': 'secret',
      'realm': 'pam',
      'ignore_certificate_errors': 1,
    });

    expect(restored.authMode, ProxmoxAuthMode.password);
    expect(restored.accountLabel, 'root@pam');
  });

  test('missing certificate preference defaults to verification enabled', () {
    final restored = PveServerConfig.fromMap({
      'name': 'Secure default',
      'origin': 'https://pve.example:8006',
      'username': 'root',
      'password': '',
      'realm': 'pam',
    });

    expect(restored.ignoreCertificateErrors, isFalse);
  });

  test('normalizes a full api token identity without duplicating user id', () {
    const config = PveServerConfig(
      name: 'Token server',
      origin: 'https://pve.example:8006',
      username: 'root',
      password: '',
      realm: 'pam',
      authMode: ProxmoxAuthMode.apiToken,
      apiTokenId: 'root@pam!ca',
      apiTokenSecret: 'secret-uuid',
      ignoreCertificateErrors: true,
    );

    expect(config.accountLabel, 'root@pam!ca');
    expect(config.apiTokenCredentials.tokenId, 'ca');
    expect(
      config.apiTokenCredentials.authorizationValue,
      'PVEAPIToken=root@pam!ca=secret-uuid',
    );
  });

  test('parses a complete api token copied into the secret field', () {
    final credentials = ProxmoxApiTokenCredentials.fromInput(
      username: 'ignored',
      realm: 'pam',
      tokenId: '',
      tokenSecret: 'PVEAPIToken=alice@pve!mobile=secret-uuid',
    );

    expect(credentials.userId, 'alice@pve');
    expect(credentials.tokenId, 'mobile');
    expect(credentials.secret, 'secret-uuid');
  });

  test('parses token credentials without separate username or realm', () {
    final credentials = ProxmoxApiTokenCredentials.fromTokenInput(
      tokenId: 'alice@pve!mobile',
      tokenSecret: 'secret-uuid',
    );

    expect(credentials.username, 'alice');
    expect(credentials.realm, 'pve');
    expect(credentials.tokenId, 'mobile');
    expect(
      credentials.authorizationValue,
      'PVEAPIToken=alice@pve!mobile=secret-uuid',
    );
  });

  test('rejects a token id without an account identity', () {
    final credentials = ProxmoxApiTokenCredentials.fromTokenInput(
      tokenId: 'mobile',
      tokenSecret: 'secret-uuid',
    );

    expect(credentials.userId, isEmpty);
    expect(credentials.tokenId, 'mobile');
  });
}
