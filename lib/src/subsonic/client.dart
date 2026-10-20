import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../model/models.dart';
import '../playback/lyrics.dart';
import '../playback/stream_choice.dart';
import 'auth.dart';
import 'parsers.dart';

const int librarySongPageSize = 100;

class QueryParams {
  final List<MapEntry<String, String>> entries = [];

  void add(String key, Object? value, {bool allowEmpty = false}) {
    if (value == null) return;
    final text = value.toString();
    if (text.isEmpty && !allowEmpty) return;
    entries.add(MapEntry(key, text));
  }

  void addAll(QueryParams other) {
    entries.addAll(other.entries);
  }

  QueryParams clone() {
    final copy = QueryParams();
    copy.entries.addAll(entries);
    return copy;
  }
}

String encodeQuery(QueryParams params) {
  return params.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}

class SubsonicClient {
  SubsonicClient({HttpClient? http}) : _http = http ?? _buildClient();

  final HttpClient _http;
  String? baseUrl;
  String? username;
  String? password;
  bool formPost = false;
  String? pinnedFingerprint;
  bool trustNewCertificate = false;
  String? observedFingerprint;
  String? acceptedFingerprint;
  bool ignoreFolderFilter = false;
  bool folderFilterDropped = false;

  static HttpClient _buildClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.userAgent = subsonicClient;
    return client;
  }

  void bind(LibraryRecord library, String password) {
    baseUrl = library.baseUrl;
    username = library.username;
    this.password = password;
    formPost = library.hasFormPost;
    pinnedFingerprint = library.certFingerprint;
    trustNewCertificate = false;
    acceptedFingerprint = library.certFingerprint;
    ignoreFolderFilter = false;
    folderFilterDropped = false;
  }

  void close() {
    _http.close(force: true);
  }

  bool _onCertificate(X509Certificate certificate, String host, int port) {
    final fingerprint = sha256.convert(certificate.der).toString();
    observedFingerprint = fingerprint;
    final pinned = pinnedFingerprint?.toLowerCase();
    if (pinned != null && pinned.isNotEmpty && pinned != fingerprint) {
      return false;
    }
    if (pinned != null && pinned.isNotEmpty && pinned == fingerprint) return true;
    if (trustNewCertificate) {
      acceptedFingerprint = fingerprint;
      pinnedFingerprint = fingerprint;
      return true;
    }
    return false;
  }

  void _installCallback() {
    _http.badCertificateCallback = (certificate, host, port) {
      final fingerprint = sha256.convert(certificate.der).toString();
      observedFingerprint = fingerprint;
      final pinned = pinnedFingerprint?.toLowerCase();
      final mismatch = pinned != null && pinned.isNotEmpty && pinned != fingerprint;
      _certificateMismatch = mismatch;
      if (mismatch) return false;
      return _onCertificate(certificate, host, port);
    };
  }

  bool _certificateMismatch = false;

  Future<ServerInfo> openExtensions() async {
    try {
      final response = await call('getOpenSubsonicExtensions', QueryParams(), authenticate: false);
      return parseServerInfo(response);
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.server && (error.code == null || error.message.contains('404'))) {
        return ServerInfo.empty;
      }
      rethrow;
    }
  }

  Future<void> ping() async {
    await call('ping', QueryParams());
  }

  Future<List<MusicFolder>> musicFolders() async {
    final response = await call('getMusicFolders', QueryParams());
    return parseMusicFolders(response);
  }

  Future<List<Album>> albumList({
    required String type,
    int size = 20,
    int offset = 0,
    String? musicFolderId,
  }) async {
    final params = QueryParams()
      ..add('type', type)
      ..add('size', size)
      ..add('offset', offset);
    final response = await _withFolder('getAlbumList2', params, musicFolderId);
    return parseAlbumList(response);
  }

  Future<Album> album(String id) async {
    final response = await call('getAlbum', QueryParams()..add('id', id));
    return parseAlbumResponse(response);
  }

  Future<List<ArtistIndex>> artists({String? musicFolderId}) async {
    final response = await _withFolder('getArtists', QueryParams(), musicFolderId);
    return parseArtistIndexes(response);
  }

  Future<Artist> artist(String id) async {
    final response = await call('getArtist', QueryParams()..add('id', id));
    return parseArtistResponse(response);
  }

  Future<SearchPageResult> search({
    required String query,
    int artistCount = 20,
    int albumCount = 20,
    int songCount = 30,
    int artistOffset = 0,
    int albumOffset = 0,
    int songOffset = 0,
    String? musicFolderId,
  }) async {
    final params = QueryParams()
      ..add('query', query, allowEmpty: true)
      ..add('artistCount', artistCount)
      ..add('albumCount', albumCount)
      ..add('songCount', songCount)
      ..add('artistOffset', artistOffset)
      ..add('albumOffset', albumOffset)
      ..add('songOffset', songOffset);
    final response = await _withFolder('search3', params, musicFolderId);
    return parseSearch(response);
  }

  Future<List<Song>> librarySongs({int offset = 0, String? musicFolderId}) async {
    final result = await search(
      query: '',
      songCount: librarySongPageSize,
      songOffset: offset,
      artistCount: 0,
      albumCount: 0,
      musicFolderId: musicFolderId,
    );
    return result.songs;
  }

  Future<List<Playlist>> playlists() async {
    final response = await call('getPlaylists', QueryParams());
    return parsePlaylists(response);
  }

  Future<Playlist> playlist(String id) async {
    final response = await call('getPlaylist', QueryParams()..add('id', id));
    return parsePlaylistResponse(response);
  }

  Future<Playlist?> createPlaylist({required String name, List<String> songIds = const []}) async {
    final params = QueryParams()..add('name', name);
    for (final id in songIds) {
      params.add('songId', id);
    }
    final response = await call('createPlaylist', params);
    final raw = response['playlist'];
    if (raw is Map) return parsePlaylist(Map<String, dynamic>.from(raw));
    return null;
  }

  Future<void> addToPlaylist({required String playlistId, required List<String> songIds}) async {
    final params = QueryParams()..add('playlistId', playlistId);
    for (final id in songIds) {
      params.add('songIdToAdd', id);
    }
    await call('updatePlaylist', params);
  }

  Future<void> deletePlaylist(String id) async {
    await call('deletePlaylist', QueryParams()..add('id', id));
  }

  Future<StarredCollection> starred({String? musicFolderId}) async {
    final response = await _withFolder('getStarred2', QueryParams(), musicFolderId);
    return parseStarred(response);
  }

  Future<void> star({String? id, String? albumId, String? artistId}) async {
    final params = QueryParams()
      ..add('id', id)
      ..add('albumId', albumId)
      ..add('artistId', artistId);
    await call('star', params);
  }

  Future<void> unstar({String? id, String? albumId, String? artistId}) async {
    final params = QueryParams()
      ..add('id', id)
      ..add('albumId', albumId)
      ..add('artistId', artistId);
    await call('unstar', params);
  }

  Future<List<Genre>> genres() async {
    final response = await call('getGenres', QueryParams());
    return parseGenres(response);
  }

  Future<List<Song>> songsByGenre({
    required String genre,
    int count = 50,
    int offset = 0,
    String? musicFolderId,
  }) async {
    final params = QueryParams()
      ..add('genre', genre)
      ..add('count', count)
      ..add('offset', offset);
    final response = await _withFolder('getSongsByGenre', params, musicFolderId);
    return parseSongsByGenre(response);
  }

  Future<List<Song>> randomSongs({int size = 100, String? musicFolderId}) async {
    final params = QueryParams()..add('size', size);
    final response = await _withFolder('getRandomSongs', params, musicFolderId);
    return parseRandomSongs(response);
  }

  Future<List<ArtistIndex>> indexes({String? musicFolderId}) async {
    final response = await _withFolder('getIndexes', QueryParams(), musicFolderId);
    return parseIndexes(response);
  }

  Future<List<FolderEntry>> directory(String id) async {
    final response = await call('getMusicDirectory', QueryParams()..add('id', id));
    return parseDirectory(response);
  }

  Future<void> scrobble({
    required String id,
    required bool submission,
    int? timeMs,
  }) async {
    final params = QueryParams()
      ..add('id', id)
      ..add('submission', submission ? 'true' : 'false');
    if (submission && timeMs != null) params.add('time', timeMs);
    await call('scrobble', params);
  }

  Future<LyricTrack?> lyricsFor({
    required bool hasSongLyrics,
    required Song song,
  }) async {
    if (hasSongLyrics) {
      final response = await call('getLyricsBySongId', QueryParams()..add('id', song.id));
      final structured = lyricsFromStructured(response['lyricsList']);
      if (structured != null && !structured.isEmpty) return structured;
    }
    final plain = await call(
      'getLyrics',
      QueryParams()
        ..add('artist', song.artistLabel)
        ..add('title', song.title),
    );
    final lyrics = plain['lyrics'];
    if (lyrics is Map) {
      return lyricsFromPlainText(asString(lyrics['value']));
    }
    return null;
  }

  Future<TranscodeDecision> transcodeDecision({
    required String mediaId,
    required Map<String, dynamic> body,
  }) async {
    final params = QueryParams()
      ..add('mediaId', mediaId)
      ..add('mediaType', 'song');
    try {
      final response = await _send(
        endpoint: 'getTranscodeDecision',
        params: params,
        authenticate: true,
        jsonBody: body,
        forceGet: false,
      );
      return parseDecision(response);
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.notFound) {
        return const TranscodeDecision(canDirectPlay: false, canTranscode: false, notFound: true);
      }
      rethrow;
    }
  }

  Future<List<int>> coverBytes(String coverArt, int size) async {
    final response = await _open(
      endpoint: 'getCoverArt',
      params: QueryParams()
        ..add('id', coverArt)
        ..add('size', size),
      authenticate: true,
    );
    if (response.statusCode >= 400) {
      await response.drain<void>().catchError((_) {});
      throw AppFailure(FailureKind.server, Zh.serverError, code: response.statusCode);
    }
    return response.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
  }

  Future<HttpClientResponse> openAudio({
    required String endpoint,
    required Map<String, String> query,
    String? rangeHeader,
  }) async {
    final params = QueryParams();
    query.forEach(params.add);
    final response = await _open(
      endpoint: endpoint,
      params: params,
      authenticate: true,
      rangeHeader: rangeHeader,
      forceGet: true,
    );
    return response;
  }

  Future<Map<String, dynamic>> call(
    String endpoint,
    QueryParams params, {
    bool authenticate = true,
  }) {
    return _send(endpoint: endpoint, params: params, authenticate: authenticate);
  }

  Future<Map<String, dynamic>> _withFolder(
    String endpoint,
    QueryParams params,
    String? musicFolderId,
  ) async {
    final folder = ignoreFolderFilter ? null : musicFolderId;
    if (folder == null || folder.isEmpty) return call(endpoint, params);
    final withFolder = params.clone()..add('musicFolderId', folder);
    try {
      return await call(endpoint, withFolder);
    } on AppFailure catch (error) {
      final retry =
          error.kind == FailureKind.server &&
          (error.code == null || error.code == 0 || error.code == 10 || error.code == 30);
      if (!retry) rethrow;
      ignoreFolderFilter = true;
      folderFilterDropped = true;
      return call(endpoint, params);
    }
  }

  Future<Map<String, dynamic>> _send({
    required String endpoint,
    required QueryParams params,
    required bool authenticate,
    Map<String, dynamic>? jsonBody,
    bool forceGet = false,
  }) async {
    final response = await _open(
      endpoint: endpoint,
      params: params,
      authenticate: authenticate,
      jsonBody: jsonBody,
      forceGet: forceGet,
    );
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
    if (response.statusCode == 404 && !text.contains('subsonic-response')) {
      throw const AppFailure(FailureKind.server, 'HTTP 404');
    }
    if (response.statusCode >= 400 && !text.contains('subsonic-response')) {
      throw AppFailure(FailureKind.server, '服务器返回了错误（HTTP ${response.statusCode}）');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const AppFailure(FailureKind.server, Zh.serverError);
    }
    final body = unwrapSubsonic(decoded);
    final failure = failureFromResponse(body);
    if (failure != null) throw failure;
    return body;
  }

  Future<HttpClientResponse> _open({
    required String endpoint,
    required QueryParams params,
    required bool authenticate,
    Map<String, dynamic>? jsonBody,
    bool forceGet = false,
    String? rangeHeader,
  }) async {
    final root = baseUrl;
    if (root == null || root.isEmpty) {
      throw const AppFailure(FailureKind.invalidInput, Zh.invalidUrl);
    }
    _certificateMismatch = false;
    _installCallback();
    final query = params.clone();
    query.add('v', subsonicVersion);
    query.add('c', subsonicClient);
    query.add('f', 'json');
    if (authenticate) {
      final user = username;
      final secret = password;
      if (user == null || user.isEmpty || secret == null) {
        throw const AppFailure(FailureKind.wrongCredentials, Zh.wrongCredentials);
      }
      final salt = newSalt();
      query.add('u', user);
      query.add('s', salt);
      query.add('t', subsonicToken(secret, salt));
    }

    final decision = endpoint == 'getTranscodeDecision';
    final useForm = formPost && jsonBody == null && !forceGet && !decision;
    final uri = useForm
        ? Uri.parse('$root/rest/$endpoint.view')
        : Uri.parse('$root/rest/$endpoint.view?${encodeQuery(query)}');
    try {
      final request = useForm
          ? await _http.postUrl(uri).timeout(const Duration(seconds: 20))
          : jsonBody != null
          ? await _http.postUrl(uri).timeout(const Duration(seconds: 20))
          : await _http.getUrl(uri).timeout(const Duration(seconds: 20));
      if (rangeHeader != null && rangeHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }
      if (useForm) {
        final body = encodeQuery(query);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
        request.contentLength = utf8.encode(body).length;
        request.write(body);
      } else if (jsonBody != null) {
        final body = jsonEncode(jsonBody);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
        request.contentLength = utf8.encode(body).length;
        request.write(body);
      }
      return await request.close().timeout(const Duration(seconds: 45));
    } on HandshakeException {
      throw _certificateFailure();
    } on TlsException {
      throw _certificateFailure();
    } on SocketException {
      throw const AppFailure(FailureKind.network, Zh.networkUnreachable);
    } on HttpException {
      throw const AppFailure(FailureKind.network, Zh.networkUnreachable);
    } on AppFailure {
      rethrow;
    } catch (error) {
      if (error is HandshakeException || error is TlsException) {
        throw _certificateFailure();
      }
      throw const AppFailure(FailureKind.network, Zh.networkUnreachable);
    }
  }

  AppFailure _certificateFailure() {
    if (_certificateMismatch) {
      return AppFailure(
        FailureKind.certificateChanged,
        Zh.certChanged,
        fingerprint: observedFingerprint,
      );
    }
    return AppFailure(
      FailureKind.certificateUntrusted,
      Zh.certUntrusted,
      fingerprint: observedFingerprint,
    );
  }
}
