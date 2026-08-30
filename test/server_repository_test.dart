import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pve_manager/data/models/proxmox_auth_mode.dart';
import 'package:pve_manager/data/models/pve_server_config.dart';
import 'package:pve_manager/data/repositories/server_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late String databasePath;
  const secureStorage = FlutterSecureStorage();

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'pve_manager_repository_test_',
    );
    databasePath = p.join(tempDirectory.path, 'servers.db');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'stores new credentials outside SQLite and hydrates them on read',
    () async {
      final repository = ServerRepository.forTesting(
        databasePath: databasePath,
        secureStorage: secureStorage,
      );
      addTearDown(repository.close);

      final saved = await repository.saveServer(
        const PveServerConfig(
          name: 'Lab',
          origin: 'https://pve.example:8006',
          username: 'root',
          password: 'password-secret',
          realm: 'pam',
          authMode: ProxmoxAuthMode.apiToken,
          apiTokenId: 'mobile',
          apiTokenSecret: 'token-secret',
          ignoreCertificateErrors: false,
        ),
      );

      final loaded = await repository.getServers();
      expect(loaded, hasLength(1));
      expect(loaded.single.password, 'password-secret');
      expect(loaded.single.apiTokenSecret, 'token-secret');

      await repository.close();
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await database.query('servers');
      await database.close();

      expect(rows.single['password'], '');
      expect(rows.single['api_token_secret'], '');
      expect(
        await secureStorage.read(key: 'pve_server_${saved.id}_password'),
        'password-secret',
      );
      expect(
        await secureStorage.read(
          key: 'pve_server_${saved.id}_api_token_secret',
        ),
        'token-secret',
      );
    },
  );

  test(
    'migrates legacy SQLite credentials without overwriting newer secrets',
    () async {
      final database = await _createLegacyDatabase(databasePath);
      await database.insert('servers', {
        'id': 7,
        'name': 'Legacy',
        'origin': 'https://legacy.example:8006',
        'username': 'root',
        'password': 'old-password',
        'realm': 'pam',
        'ignore_certificate_errors': 1,
        'auth_type': 'apiToken',
        'api_token_id': 'mobile',
        'api_token_secret': 'legacy-token-secret',
        'created_at': 1,
        'updated_at': 1,
      });
      await database.close();
      FlutterSecureStorage.setMockInitialValues({
        'pve_server_7_password': 'newer-password',
      });

      final repository = ServerRepository.forTesting(
        databasePath: databasePath,
        secureStorage: secureStorage,
      );
      addTearDown(repository.close);
      final loaded = await repository.getServers();

      expect(loaded.single.password, 'newer-password');
      expect(loaded.single.apiTokenSecret, 'legacy-token-secret');
      expect(loaded.single.ignoreCertificateErrors, isTrue);

      await repository.close();
      final migratedDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
      );
      final rows = await migratedDatabase.query('servers');
      await migratedDatabase.close();

      expect(rows.single['password'], '');
      expect(rows.single['api_token_secret'], '');
    },
  );

  test(
    'does not report success when secure storage rejects a new secret',
    () async {
      final repository = ServerRepository.forTesting(
        databasePath: databasePath,
        secureStorage: const _FailingSecureStorage(),
      );
      addTearDown(repository.close);

      await expectLater(
        repository.saveServer(
          const PveServerConfig(
            name: 'Lab',
            origin: 'https://pve.example:8006',
            username: 'root',
            password: 'password-secret',
            realm: 'pam',
            ignoreCertificateErrors: false,
          ),
        ),
        throwsStateError,
      );

      await repository.close();
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await database.query('servers');
      await database.close();
      expect(rows, isEmpty);
    },
  );

  test('deleting a server also deletes its secure credentials', () async {
    final repository = ServerRepository.forTesting(
      databasePath: databasePath,
      secureStorage: secureStorage,
    );
    addTearDown(repository.close);
    final saved = await repository.saveServer(
      const PveServerConfig(
        name: 'Lab',
        origin: 'https://pve.example:8006',
        username: 'root',
        password: 'password-secret',
        realm: 'pam',
        ignoreCertificateErrors: false,
      ),
    );

    await repository.deleteServer(saved.id!);

    expect(
      await secureStorage.read(key: 'pve_server_${saved.id}_password'),
      isNull,
    );
    expect(await repository.getServers(), isEmpty);
  });
}

Future<Database> _createLegacyDatabase(String path) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            origin TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            realm TEXT NOT NULL,
            ignore_certificate_errors INTEGER NOT NULL DEFAULT 1,
            auth_type TEXT NOT NULL DEFAULT 'password',
            api_token_id TEXT NOT NULL DEFAULT '',
            api_token_secret TEXT NOT NULL DEFAULT '',
            last_connected_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    ),
  );
}

class _FailingSecureStorage extends FlutterSecureStorage {
  const _FailingSecureStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw StateError('Secure storage is unavailable.');
  }
}
