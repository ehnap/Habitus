import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../subsonic/client.dart';

String coverFileName(String libraryId, String coverArt, int size) {
  final digest = sha1.convert(utf8.encode('$libraryId|$coverArt|$size')).toString();
  return '${libraryId}_$digest.img';
}

class CoverCache {
  CoverCache(this.directory, this.client);

  final Directory directory;
  final SubsonicClient client;
  final Map<String, Future<File?>> _inflight = {};

  Future<File?> fileFor({
    required String libraryId,
    required String coverArt,
    required int size,
  }) {
    if (coverArt.isEmpty) return Future.value();
    final name = coverFileName(libraryId, coverArt, size);
    return _inflight.putIfAbsent(name, () async {
      try {
        final file = File('${directory.path}/$name');
        if (await file.exists() && await file.length() > 32) return file;
        await directory.create(recursive: true);
        final bytes = await client.coverBytes(coverArt, size);
        if (bytes.isEmpty) return null;
        await file.writeAsBytes(bytes, flush: true);
        return file;
      } catch (_) {
        return null;
      } finally {
        _inflight.remove(name);
      }
    });
  }

  Future<void> deleteLibrary(String libraryId) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith('${libraryId}_')) {
        await entity.delete();
      }
    }
  }
}
