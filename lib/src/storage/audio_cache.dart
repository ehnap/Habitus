import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class AudioCacheEntry {
  AudioCacheEntry({
    required this.key,
    required this.libraryId,
    required this.path,
    required this.bytes,
    required this.createdAt,
    required this.complete,
  });

  final String key;
  final String libraryId;
  String path;
  int bytes;
  int createdAt;
  bool complete;

  Map<String, dynamic> toJson() => {
    'key': key,
    'libraryId': libraryId,
    'path': path,
    'bytes': bytes,
    'createdAt': createdAt,
    'complete': complete,
  };

  static AudioCacheEntry fromJson(Map<String, dynamic> json) {
    return AudioCacheEntry(
      key: json['key'] as String? ?? '',
      libraryId: json['libraryId'] as String? ?? '',
      path: json['path'] as String? ?? '',
      bytes: json['bytes'] is int ? json['bytes'] as int : 0,
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : 0,
      complete: json['complete'] == true,
    );
  }
}

class AudioCache {
  AudioCache(this.directory, {this.limitBytes = 512 * 1024 * 1024});

  final Directory directory;
  int limitBytes;
  final Map<String, AudioCacheEntry> _entries = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    await directory.create(recursive: true);
    final index = File('${directory.path}/index.json');
    if (await index.exists()) {
      try {
        final decoded = jsonDecode(await index.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final entry = AudioCacheEntry.fromJson(Map<String, dynamic>.from(item));
              if (entry.key.isNotEmpty) _entries[entry.key] = entry;
            }
          }
        }
      } catch (_) {
        _entries.clear();
      }
    }
    _loaded = true;
  }

  Future<File?> completeFile(String key) async {
    await load();
    final entry = _entries[key];
    if (entry == null || !entry.complete) return null;
    final file = File(entry.path);
    if (!await file.exists() || await file.length() <= 0) {
      _entries.remove(key);
      await _persist();
      return null;
    }
    return file;
  }

  Future<File> begin(String key, {required String libraryId}) async {
    await load();
    final name = sha1.convert(utf8.encode(key)).toString();
    final file = File('${directory.path}/$name.part');
    await directory.create(recursive: true);
    if (await file.exists()) await file.delete();
    _entries[key] = AudioCacheEntry(
      key: key,
      libraryId: libraryId,
      path: file.path,
      bytes: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      complete: false,
    );
    await _persist();
    return file;
  }

  Future<File> commit(String key, int bytes) async {
    await load();
    final entry = _entries[key];
    if (entry == null) {
      throw StateError('missing cache entry');
    }
    final part = File(entry.path);
    final finished = File(part.path.replaceFirst(RegExp(r'\.part$'), '.bin'));
    if (await finished.exists()) await finished.delete();
    if (await part.exists()) {
      await part.rename(finished.path);
    }
    entry
      ..path = finished.path
      ..bytes = bytes
      ..complete = true;
    await evict(protect: {key});
    await _persist();
    return finished;
  }

  Future<void> abort(String key) async {
    await load();
    final entry = _entries.remove(key);
    if (entry != null) {
      final file = File(entry.path);
      if (await file.exists()) await file.delete();
    }
    await _persist();
  }

  Future<void> evict({Set<String> protect = const {}}) async {
    await load();
    var total = _entries.values.where((entry) => entry.complete).fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (total <= limitBytes) return;
    final victims = _entries.values.where((entry) => entry.complete && !protect.contains(entry.key)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final entry in victims) {
      if (total <= limitBytes) break;
      final file = File(entry.path);
      if (await file.exists()) await file.delete();
      total -= entry.bytes;
      _entries.remove(entry.key);
    }
    await _persist();
  }

  Future<void> deleteLibrary(String libraryId) async {
    await load();
    final keys = _entries.entries.where((entry) => entry.value.libraryId == libraryId).map((entry) => entry.key).toList();
    for (final key in keys) {
      await abort(key);
    }
  }

  Future<void> clear() async {
    await load();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File && !entity.path.endsWith('index.json')) {
          await entity.delete();
        }
      }
    }
    _entries.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final index = File('${directory.path}/index.json');
    await directory.create(recursive: true);
    final payload = _entries.values.map((entry) => entry.toJson()).toList();
    await index.writeAsString(jsonEncode(payload));
  }
}

String audioCacheKey({
  required String libraryId,
  required String songId,
  required bool direct,
}) {
  return '$libraryId|$songId|${direct ? 'raw' : 'aac'}';
}
