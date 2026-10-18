import 'package:sqflite/sqflite.dart';

import '../model/models.dart';

class AppDatabase {
  Database? _db;

  Database get db {
    final current = _db;
    if (current == null) throw StateError('database is not open');
    return current;
  }

  Future<void> open(String path) async {
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE libraries (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            username TEXT NOT NULL,
            music_folder_id TEXT,
            cert_fingerprint TEXT,
            unrecognized INTEGER NOT NULL,
            has_transcoding INTEGER NOT NULL,
            has_song_lyrics INTEGER NOT NULL,
            has_form_post INTEGER NOT NULL,
            has_transcode_offset INTEGER NOT NULL,
            server_version TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await database.execute('''
          CREATE TABLE queues (
            library_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<LibraryRecord>> libraries() async {
    final rows = await db.query('libraries', orderBy: 'created_at ASC');
    return rows.map(_library).toList();
  }

  Future<void> upsertLibrary(LibraryRecord library) async {
    await db.insert('libraries', {
      'id': library.id,
      'name': library.name,
      'base_url': library.baseUrl,
      'username': library.username,
      'music_folder_id': library.musicFolderId,
      'cert_fingerprint': library.certFingerprint,
      'unrecognized': library.unrecognized ? 1 : 0,
      'has_transcoding': library.hasTranscoding ? 1 : 0,
      'has_song_lyrics': library.hasSongLyrics ? 1 : 0,
      'has_form_post': library.hasFormPost ? 1 : 0,
      'has_transcode_offset': library.hasTranscodeOffset ? 1 : 0,
      'server_version': library.serverVersion,
      'created_at': library.createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : library.createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteLibrary(String id) async {
    await db.delete('libraries', where: 'id = ?', whereArgs: [id]);
    await db.delete('queues', where: 'library_id = ?', whereArgs: [id]);
    final current = await currentLibraryId();
    if (current == id) await setCurrentLibraryId(null);
  }

  Future<String?> currentLibraryId() async {
    final rows = await db.query('app_state', where: 'key = ?', whereArgs: ['current_library']);
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    if (value is! String || value.isEmpty) return null;
    return value;
  }

  Future<void> setCurrentLibraryId(String? id) async {
    await db.insert('app_state', {
      'key': 'current_library',
      'value': id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveQueue(String libraryId, QueueSnapshot snapshot) async {
    await db.insert('queues', {
      'library_id': libraryId,
      'payload': snapshot.toJsonString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<QueueSnapshot> loadQueue(String libraryId) async {
    final rows = await db.query('queues', where: 'library_id = ?', whereArgs: [libraryId]);
    if (rows.isEmpty) return const QueueSnapshot();
    final payload = rows.first['payload'];
    return QueueSnapshot.parse(payload is String ? payload : null);
  }

  Future<AppSettings> loadSettings() async {
    final rows = await db.query('settings');
    final values = <String, String>{};
    for (final row in rows) {
      final key = row['key'];
      final value = row['value'];
      if (key is String && value is String) values[key] = value;
    }
    return AppSettings(
      quality: AppSettings.qualityFromName(values['quality']),
      replayGain: values['replay_gain'] != '0',
      cacheEnabled: values['cache_enabled'] != '0',
      cacheLimitBytes: int.tryParse(values['cache_limit'] ?? '') ?? AppSettings.defaultCacheLimit,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    Future<void> put(String key, String value) {
      return db.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await put('quality', settings.quality.name);
    await put('replay_gain', settings.replayGain ? '1' : '0');
    await put('cache_enabled', settings.cacheEnabled ? '1' : '0');
    await put('cache_limit', '${settings.cacheLimitBytes}');
  }

  LibraryRecord _library(Map<String, Object?> row) {
    return LibraryRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      baseUrl: row['base_url'] as String,
      username: row['username'] as String,
      musicFolderId: row['music_folder_id'] as String?,
      certFingerprint: row['cert_fingerprint'] as String?,
      unrecognized: row['unrecognized'] == 1,
      hasTranscoding: row['has_transcoding'] == 1,
      hasSongLyrics: row['has_song_lyrics'] == 1,
      hasFormPost: row['has_form_post'] == 1,
      hasTranscodeOffset: row['has_transcode_offset'] == 1,
      serverVersion: row['server_version'] as String?,
      createdAt: (row['created_at'] as int?) ?? 0,
    );
  }
}
