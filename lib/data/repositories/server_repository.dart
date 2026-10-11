import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:pve_manager/data/models/pve_server_config.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class ServerRepository {
  ServerRepository._({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    String? databasePath,
  }) : _secureStorage = secureStorage,
       _databasePath = databasePath;

  @visibleForTesting
  ServerRepository.forTesting({
    required String databasePath,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : this._(secureStorage: secureStorage, databasePath: databasePath);

  static final ServerRepository instance = ServerRepository._();

  final FlutterSecureStorage _secureStorage;
  final String? _databasePath;
  sqflite.Database? _database;
  Future<sqflite.Database>? _openingDatabase;
  Future<void> _pendingOperation = Future<void>.value();

  Future<List<PveServerConfig>> getServers() => _runExclusive(_getServers);

  Future<List<PveServerConfig>> _getServers() async {
    final db = await _openDatabase();
    final rows = await db.query('servers', orderBy: 'updated_at DESC, id DESC');
    final servers = <PveServerConfig>[];
    for (final row in rows) {
      final server = PveServerConfig.fromMap(row);
      final id = server.id;
      if (id == null) {
        servers.add(server);
        continue;
      }

      final credentials = await _readCredentials(id);
      servers.add(
        server.copyWith(
          password: credentials.password ?? server.password,
          apiTokenSecret: credentials.apiTokenSecret ?? server.apiTokenSecret,
        ),
      );
    }
    return servers;
  }

  Future<PveServerConfig> saveServer(PveServerConfig server) =>
      _runExclusive(() => _saveServer(server));

  Future<PveServerConfig> _saveServer(PveServerConfig server) async {
    final db = await _openDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      ...server.toDatabaseMap()..remove('id'),
      'updated_at': now,
    };

    if (server.id == null) {
      final id = await db.insert('servers', {
        ...values,
        'created_at': now,
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      try {
        await _writeCredentials(id, server);
      } on Object catch (error, stackTrace) {
        await _restoreCredentialsBestEffort(id, const _StoredCredentials());
        try {
          await db.delete('servers', where: 'id = ?', whereArgs: [id]);
        } on Object {
          // Preserve the secure-storage failure that caused the rollback.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return server.copyWith(id: id);
    }

    final id = server.id!;
    final previousCredentials = await _readCredentials(id);
    try {
      await _writeCredentials(id, server);
      final updated = await db.update(
        'servers',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated != 1) {
        throw StateError('Server $id no longer exists.');
      }
    } on Object catch (error, stackTrace) {
      await _restoreCredentialsBestEffort(id, previousCredentials);
      Error.throwWithStackTrace(error, stackTrace);
    }
    return server;
  }

  Future<PveServerConfig> markConnected(PveServerConfig server) =>
      _runExclusive(() => _markConnected(server));

  Future<PveServerConfig> _markConnected(PveServerConfig server) async {
    final db = await _openDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (server.id != null) {
      await db.update(
        'servers',
        {'last_connected_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [server.id],
      );
    }

    return server.copyWith(lastConnectedAt: now);
  }

  Future<void> deleteServer(int id) => _runExclusive(() => _deleteServer(id));

  Future<void> _deleteServer(int id) async {
    final db = await _openDatabase();
    final previousCredentials = await _readCredentials(id);
    try {
      await _clearCredentials(id);
      final deleted = await db.delete(
        'servers',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted != 1) {
        throw StateError('Server $id no longer exists.');
      }
    } on Object catch (error, stackTrace) {
      await _restoreCredentialsBestEffort(id, previousCredentials);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @visibleForTesting
  Future<void> close() => _runExclusive(_close);

  Future<void> _close() async {
    final database = _database;
    _database = null;
    _openingDatabase = null;
    await database?.close();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    // SQLite and secure storage cannot share a transaction. Keep reads, writes,
    // and rollback together so callers never observe or overwrite partial data.
    final result = _pendingOperation.then((_) => operation());
    _pendingOperation = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<sqflite.Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final opening = _openingDatabase;
    if (opening != null) {
      return opening;
    }

    final future = _createDatabase();
    _openingDatabase = future;
    try {
      final database = await future;
      _database = database;
      return database;
    } finally {
      if (identical(_openingDatabase, future)) {
        _openingDatabase = null;
      }
    }
  }

  Future<sqflite.Database> _createDatabase() async {
    final databaseFactory = _getDatabaseFactory();
    final path =
        _databasePath ??
        p.join(await databaseFactory.getDatabasesPath(), 'pve_manager.db');
    final database = await databaseFactory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE servers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            origin TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL DEFAULT '',
            realm TEXT NOT NULL,
            ignore_certificate_errors INTEGER NOT NULL DEFAULT 0,
            auth_type TEXT NOT NULL DEFAULT 'password',
            api_token_id TEXT NOT NULL DEFAULT '',
            api_token_secret TEXT NOT NULL DEFAULT '',
            last_connected_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE servers ADD COLUMN last_connected_at INTEGER',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE servers ADD COLUMN auth_type TEXT NOT NULL DEFAULT 'password'",
            );
            await db.execute(
              "ALTER TABLE servers ADD COLUMN api_token_id TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE servers ADD COLUMN api_token_secret TEXT NOT NULL DEFAULT ''",
            );
          }
        },
      ),
    );
    try {
      await _migrateLegacyCredentials(database);
      return database;
    } on Object {
      await database.close();
      rethrow;
    }
  }

  Future<void> _migrateLegacyCredentials(sqflite.Database database) async {
    final rows = await database.query(
      'servers',
      columns: ['id', 'password', 'api_token_secret'],
      where: "password <> '' OR api_token_secret <> ''",
    );

    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) {
        continue;
      }

      final password = row['password']?.toString() ?? '';
      final apiTokenSecret = row['api_token_secret']?.toString() ?? '';
      if (password.isNotEmpty) {
        await _migrateCredential(_passwordKey(id), password);
      }
      if (apiTokenSecret.isNotEmpty) {
        await _migrateCredential(_apiTokenSecretKey(id), apiTokenSecret);
      }

      await database.update(
        'servers',
        {'password': '', 'api_token_secret': ''},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _migrateCredential(String key, String legacyValue) async {
    final existing = await _secureStorage.read(key: key);
    if (existing == null || existing.isEmpty) {
      await _secureStorage.write(key: key, value: legacyValue);
    }
  }

  Future<_StoredCredentials> _readCredentials(int id) async {
    return _StoredCredentials(
      password: await _secureStorage.read(key: _passwordKey(id)),
      apiTokenSecret: await _secureStorage.read(key: _apiTokenSecretKey(id)),
    );
  }

  Future<void> _writeCredentials(int id, PveServerConfig server) async {
    await _secureStorage.write(
      key: _passwordKey(id),
      value: server.password.isEmpty ? null : server.password,
    );
    await _secureStorage.write(
      key: _apiTokenSecretKey(id),
      value: server.apiTokenSecret.isEmpty ? null : server.apiTokenSecret,
    );
  }

  Future<void> _clearCredentials(int id) async {
    await _secureStorage.write(key: _passwordKey(id), value: null);
    await _secureStorage.write(key: _apiTokenSecretKey(id), value: null);
  }

  Future<void> _restoreCredentialsBestEffort(
    int id,
    _StoredCredentials credentials,
  ) async {
    try {
      await _secureStorage.write(
        key: _passwordKey(id),
        value: credentials.password,
      );
    } on Object {
      // The original operation error is more useful to the caller.
    }
    try {
      await _secureStorage.write(
        key: _apiTokenSecretKey(id),
        value: credentials.apiTokenSecret,
      );
    } on Object {
      // The original operation error is more useful to the caller.
    }
  }

  sqflite.DatabaseFactory _getDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }
}

String _passwordKey(int serverId) => 'pve_server_${serverId}_password';

String _apiTokenSecretKey(int serverId) =>
    'pve_server_${serverId}_api_token_secret';

class _StoredCredentials {
  const _StoredCredentials({this.password, this.apiTokenSecret});

  final String? password;
  final String? apiTokenSecret;
}
