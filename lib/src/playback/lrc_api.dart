import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/models.dart';
import 'lyrics.dart';

/// Builds the LrcApi lyrics request.
///
/// HisAtri/LrcApi serves `GET /lyrics` (the same handler is also mounted at
/// `/api/v1/lyrics/single`). It reads `title`, `artist`, and `album`, and
/// returns raw LRC text, or the body `Lyrics not found.` with HTTP 404.
/// `duration` is included because the player knows it; the current service
/// does not read that argument.
///
/// An empty base returns null and must not be requested. A base that already
/// ends at `/lyrics` or `/lyrics/single` is used as-is.
Uri? lrcApiUri({
  required String base,
  required String title,
  required String artist,
  required String album,
  required int durationSeconds,
}) {
  final trimmed = base.trim();
  if (trimmed.isEmpty) return null;
  var text = trimmed;
  final scheme = text.indexOf('://');
  if (scheme <= 0) text = 'http://$text';
  final parsed = Uri.tryParse(text);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;

  var path = parsed.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final lower = path.toLowerCase();
  final ready = lower == '/lyrics' || lower.endsWith('/lyrics') || lower.endsWith('/lyrics/single');
  if (!ready) {
    path = path.isEmpty || path == '/' ? '/lyrics' : '$path/lyrics';
  }
  if (!path.startsWith('/')) path = '/$path';

  return parsed.replace(
    path: path,
    queryParameters: {
      'title': title,
      'artist': artist,
      'album': album,
      'duration': '$durationSeconds',
    },
  );
}

/// Fetches LRC from [base]. Returns null when the service has nothing.
/// Failures are swallowed so a down lyrics server does not surface as an error,
/// and the address itself is never written to a log or an exception message.
Future<LyricTrack?> fetchLrcApiLyrics({
  required String base,
  required String title,
  required String artist,
  required String album,
  required int durationSeconds,
  HttpClient? http,
}) async {
  final uri = lrcApiUri(
    base: base,
    title: title,
    artist: artist,
    album: album,
    durationSeconds: durationSeconds,
  );
  if (uri == null) return null;
  final client = http ?? HttpClient();
  final ownsClient = http == null;
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 12))) {
      builder.add(chunk);
      if (builder.length > 512 * 1024) return null;
    }
    if (response.statusCode == 404) return null;
    final body = utf8.decode(builder.takeBytes(), allowMalformed: true).trim();
    if (body.isEmpty || body == 'Lyrics not found.') return null;
    if (response.statusCode != 200) return null;
    return lyricsFromPlainText(body);
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) client.close(force: true);
  }
}
