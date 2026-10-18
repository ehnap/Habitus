import 'dart:async';
import 'dart:io';

import '../subsonic/auth.dart';
import '../subsonic/client.dart';
import '../storage/audio_cache.dart';

class _Ticket {
  _Ticket({
    required this.endpoint,
    required this.query,
    required this.libraryId,
    this.cacheKey,
    this.cacheEnabled = false,
  });

  final String endpoint;
  final Map<String, String> query;
  final String libraryId;
  final String? cacheKey;
  final bool cacheEnabled;
}

class LocalAudioProxy {
  LocalAudioProxy(this.client, this.cache);

  final SubsonicClient client;
  final AudioCache cache;
  HttpServer? _server;
  final Map<String, _Ticket> _tickets = {};

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
  }

  Uri register({
    required String endpoint,
    required Map<String, String> query,
    required String libraryId,
    String? cacheKey,
    bool cacheEnabled = false,
  }) {
    final server = _server;
    if (server == null) {
      throw StateError('audio proxy is not running');
    }
    final id = newSalt();
    _tickets[id] = _Ticket(
      endpoint: endpoint,
      query: query,
      libraryId: libraryId,
      cacheKey: cacheKey,
      cacheEnabled: cacheEnabled,
    );
    return Uri.parse('http://127.0.0.1:${server.port}/a/$id');
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final ticket = segments.length == 2 ? _tickets[segments[1]] : null;
    if (ticket == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    IOSink? sink;
    var caching = false;
    try {
      final upstream = await client.openAudio(
        endpoint: ticket.endpoint,
        query: ticket.query,
        rangeHeader: range,
      );
      request.response.statusCode = upstream.statusCode;
      for (final name in const ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
        final value = upstream.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      final fromStart = range == null || range == 'bytes=0-';
      if (ticket.cacheEnabled &&
          ticket.cacheKey != null &&
          upstream.statusCode == HttpStatus.ok &&
          fromStart) {
        final file = await cache.begin(ticket.cacheKey!, libraryId: ticket.libraryId);
        sink = file.openWrite();
        caching = true;
      }
      var total = 0;
      await for (final chunk in upstream) {
        request.response.add(chunk);
        sink?.add(chunk);
        total += chunk.length;
      }
      await sink?.flush();
      await sink?.close();
      sink = null;
      if (caching && ticket.cacheKey != null) {
        await cache.commit(ticket.cacheKey!, total);
      }
      await request.response.close();
    } catch (_) {
      await sink?.close();
      if (caching && ticket.cacheKey != null) {
        await cache.abort(ticket.cacheKey!);
      }
      try {
        if (!request.response.headers.chunkedTransferEncoding) {
          request.response.statusCode = HttpStatus.badGateway;
        }
        await request.response.close();
      } catch (_) {}
    }
  }
}
