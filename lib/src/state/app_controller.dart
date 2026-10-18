import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../copy/zh.dart';
import '../model/models.dart';
import '../playback/format_policy.dart';
import '../playback/habitus_player.dart';
import '../playback/queue_logic.dart';
import '../storage/app_database.dart';
import '../storage/audio_cache.dart';
import '../storage/cover_cache.dart';
import '../storage/secure_store.dart';
import '../subsonic/client.dart';
import '../subsonic/url_rules.dart';

class ProbeResult {
  const ProbeResult({
    required this.url,
    required this.info,
    required this.folders,
    this.fingerprint,
  });

  final NormalizedUrl url;
  final ServerInfo info;
  final List<MusicFolder> folders;
  final String? fingerprint;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.database,
    required this.credentials,
    required this.client,
    required this.player,
    required this.covers,
    required this.audioCache,
    this.network = const PluginNetworkStatus(),
  }) {
    player.onNotice = toast;
  }

  final AppDatabase database;
  final CredentialStore credentials;
  final SubsonicClient client;
  final HabitusAudioHandler player;
  final CoverCache covers;
  final AudioCache audioCache;
  final NetworkStatus network;

  final StreamController<String> messages = StreamController<String>.broadcast();
  final Uuid _uuid = const Uuid();

  AppSettings settings = const AppSettings();
  List<LibraryRecord> libraries = [];
  LibraryRecord? current;
  String? password;
  bool ready = false;
  int libraryEpoch = 0;
  List<MusicFolder> folders = [];
  bool _folderNotified = false;
  Timer? _positionTimer;

  bool get hasLibrary => current != null;
  bool get needsPassword => current != null && (password == null || password!.isEmpty);
  bool get phone => Platform.isAndroid || Platform.isIOS;

  PlatformGroup get platformGroup {
    if (Platform.isAndroid) return PlatformGroup.android;
    if (Platform.isIOS || Platform.isMacOS) return PlatformGroup.apple;
    if (Platform.isWindows) return PlatformGroup.windows;
    return PlatformGroup.other;
  }

  String get platformLabel {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    return 'Linux';
  }

  String? get folderId {
    if (client.ignoreFolderFilter) return null;
    final id = current?.musicFolderId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> boot() async {
    settings = await database.loadSettings();
    libraries = await database.libraries();
    final id = await database.currentLibraryId();
    current = _find(id);
    if (current != null) {
      password = await credentials.read(current!.id);
      _bind();
      await player.restore(await database.loadQueue(current!.id));
    } else {
      _bind();
    }
    _positionTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.views.view.playing) {
        unawaited(persistQueue());
      }
    });
    ready = true;
    notifyListeners();
  }

  Future<ProbeResult> probe({
    required String url,
    required String username,
    required String password,
    required bool trustCertificate,
    String? pinnedFingerprint,
  }) async {
    final previous = _clientSnapshot();
    final normalized = normalizeBaseUrl(url);
    client
      ..baseUrl = normalized.base
      ..username = username
      ..password = password
      ..pinnedFingerprint = trustCertificate ? null : pinnedFingerprint
      ..trustNewCertificate = trustCertificate
      ..formPost = false
      ..acceptedFingerprint = trustCertificate ? null : pinnedFingerprint;
    try {
      final info = await client.openExtensions();
      client.formPost = info.hasFormPost;
      await client.ping();
      final found = await client.musicFolders();
      return ProbeResult(
        url: normalized,
        info: info,
        folders: found,
        fingerprint: client.acceptedFingerprint ?? client.pinnedFingerprint,
      );
    } catch (error) {
      _restoreClient(previous);
      rethrow;
    }
  }

  void rebind() => _bind();

  Future<void> saveLibrary({
    String? id,
    required String name,
    required NormalizedUrl url,
    required String username,
    required String password,
    required ServerInfo info,
    String? musicFolderId,
    String? fingerprint,
    int? createdAt,
  }) async {
    final libraryId = id ?? _uuid.v4();
    final record = LibraryRecord(
      id: libraryId,
      name: name.trim().isEmpty ? hostLabel(url.base) : name.trim(),
      baseUrl: url.base,
      username: username.trim(),
      musicFolderId: musicFolderId,
      certFingerprint: fingerprint,
      unrecognized: info.unrecognized,
      hasTranscoding: info.hasTranscoding,
      hasSongLyrics: info.hasSongLyrics,
      hasFormPost: info.hasFormPost,
      hasTranscodeOffset: info.hasTranscodeOffset,
      serverVersion: info.serverVersion,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    await credentials.write(libraryId, password);
    try {
      await database.upsertLibrary(record);
    } catch (error) {
      if (id == null) await credentials.delete(libraryId);
      rethrow;
    }
    libraries = await database.libraries();
    if (current != null && current!.id != libraryId) {
      await player.pause();
      await persistQueue();
    }
    current = _find(libraryId);
    await database.setCurrentLibraryId(libraryId);
    this.password = password;
    _folderNotified = false;
    client.ignoreFolderFilter = false;
    _bind();
    await player.restore(
      id == null ? const QueueSnapshot() : await database.loadQueue(libraryId),
    );
    libraryEpoch++;
    notifyListeners();
  }

  Future<void> switchTo(String id) async {
    if (current?.id == id) return;
    await player.pause();
    await persistQueue();
    current = _find(id);
    await database.setCurrentLibraryId(id);
    password = current == null ? null : await credentials.read(current!.id);
    _folderNotified = false;
    client.ignoreFolderFilter = false;
    folders = [];
    _bind();
    await player.restore(
      current == null ? const QueueSnapshot() : await database.loadQueue(current!.id),
    );
    libraryEpoch++;
    notifyListeners();
  }

  Future<void> deleteLibrary(String id) async {
    final deletingCurrent = current?.id == id;
    if (deletingCurrent) {
      await player.pause();
      await player.restore(const QueueSnapshot());
    }
    await credentials.delete(id);
    await database.deleteLibrary(id);
    await covers.deleteLibrary(id);
    await audioCache.deleteLibrary(id);
    libraries = await database.libraries();
    if (deletingCurrent) {
      current = libraries.isEmpty ? null : libraries.first;
      await database.setCurrentLibraryId(current?.id);
      password = current == null ? null : await credentials.read(current!.id);
      _bind();
      if (current != null) {
        await player.restore(await database.loadQueue(current!.id));
      }
    }
    libraryEpoch++;
    notifyListeners();
  }

  Future<void> selectFolder(String? id) async {
    final library = current;
    if (library == null) return;
    final next = id == null || id.isEmpty
        ? library.copyWith(clearFolder: true)
        : library.copyWith(musicFolderId: id);
    await database.upsertLibrary(next);
    current = next;
    libraries = [for (final item in libraries) item.id == next.id ? next : item];
    client.ignoreFolderFilter = false;
    _folderNotified = false;
    notifyListeners();
  }

  Future<String?> passwordFor(String id) => credentials.read(id);

  Future<void> refreshFolders() async {
    if (current == null || needsPassword) {
      folders = [];
      notifyListeners();
      return;
    }
    folders = await client.musicFolders();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await database.saveSettings(next);
    _bind();
    await player.setReplayGain(next.replayGain);
    notifyListeners();
  }

  Future<void> clearPlaybackCache() async {
    await audioCache.clear();
    toast(Zh.cacheCleared);
  }

  Future<void> persistQueue() async {
    final library = current;
    if (library == null) return;
    await database.saveQueue(library.id, player.snapshot());
  }

  Future<List<Album>> albums({required String type, int size = 24, int offset = 0}) {
    return _guard(() => client.albumList(type: type, size: size, offset: offset, musicFolderId: folderId));
  }

  Future<Album> album(String id) => _guard(() => client.album(id));

  Future<List<ArtistIndex>> artists() => _guard(() => client.artists(musicFolderId: folderId));

  Future<Artist> artist(String id) => _guard(() => client.artist(id));

  Future<SearchPageResult> search(String query, {int songOffset = 0, int albumOffset = 0, int artistOffset = 0}) {
    return _guard(
      () => client.search(
        query: query,
        musicFolderId: folderId,
        songOffset: songOffset,
        albumOffset: albumOffset,
        artistOffset: artistOffset,
      ),
    );
  }

  Future<List<Playlist>> playlists() => _guard(client.playlists);

  Future<Playlist> playlist(String id) => _guard(() => client.playlist(id));

  Future<Playlist?> createPlaylist(String name, {List<String> songIds = const []}) {
    return _guard(() => client.createPlaylist(name: name, songIds: songIds));
  }

  Future<void> addSongsToPlaylist(String playlistId, List<String> songIds) {
    return _guard(() => client.addToPlaylist(playlistId: playlistId, songIds: songIds));
  }

  Future<void> removePlaylist(String id) => _guard(() => client.deletePlaylist(id));

  Future<StarredCollection> starred() => _guard(() => client.starred(musicFolderId: folderId));

  Future<List<Genre>> genres() => _guard(client.genres);

  Future<List<Song>> songsByGenre(String genre, {int offset = 0}) {
    return _guard(
      () => client.songsByGenre(genre: genre, offset: offset, musicFolderId: folderId),
    );
  }

  Future<List<Song>> randomSongs() {
    return _guard(() => client.randomSongs(musicFolderId: folderId));
  }

  Future<List<ArtistIndex>> folderIndexes() => _guard(() => client.indexes(musicFolderId: folderId));

  Future<List<FolderEntry>> folder(String id) => _guard(() => client.directory(id));

  Future<LyricTrack?> lyrics(Song song) {
    return _guard(
      () => client.lyricsFor(hasSongLyrics: current?.hasSongLyrics ?? false, song: song),
    );
  }

  Future<void> setStar({String? songId, String? albumId, String? artistId, required bool starred}) {
    return _guard(() {
      if (starred) return client.star(id: songId, albumId: albumId, artistId: artistId);
      return client.unstar(id: songId, albumId: albumId, artistId: artistId);
    });
  }

  Future<void> playSongs(List<Song> songs, int index, {required bool albumGain}) async {
    final items = queueFromTap(
      songs: songs,
      index: index,
      shuffle: player.views.view.shuffle,
      albumGain: albumGain,
    );
    await player.playItems(items);
    await persistQueue();
  }

  Future<void> playAlbum(List<Song> songs, {required bool shuffle}) async {
    final items = queueFromAlbum(songs: songs, shuffle: shuffle);
    await player.playItems(items);
    await persistQueue();
  }

  Future<void> playRandomBatch() async {
    final songs = await randomSongs();
    if (songs.isEmpty) {
      toast(Zh.emptyCatalogTitle);
      return;
    }
    await player.playItems([for (final song in songs) QueueItem(song: song)]);
    await persistQueue();
  }

  void toast(String message) {
    if (!messages.isClosed && message.isNotEmpty) messages.add(message);
  }

  Future<bool> _preferDirect() async {
    final cellular = await network.cellular;
    return preferDirectPlay(quality: settings.quality, cellular: cellular, phone: phone);
  }

  void _bind() {
    final library = current;
    client.ignoreFolderFilter = false;
    if (library != null && password != null) {
      client.bind(library, password!);
    } else if (library != null) {
      client.baseUrl = library.baseUrl;
      client.username = library.username;
      client.password = null;
      client.formPost = library.hasFormPost;
      client.pinnedFingerprint = library.certFingerprint;
    }
    player.configure(
      library: library,
      password: password,
      replayGain: settings.replayGain,
      cacheEnabled: settings.cacheEnabled,
      cacheLimitBytes: settings.cacheLimitBytes,
      platform: platformGroup,
      platformLabel: platformLabel,
    );
    player.preferDirect = _preferDirect;
    player.onScrobble = _scrobble;
    player.onNotice = toast;
  }

  Future<void> _scrobble(String id, {required bool submission, int? timeMs}) async {
    if (current == null || password == null) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await client.scrobble(id: id, submission: submission, timeMs: timeMs);
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (current == null) {
      throw const FormatException(Zh.noLibraryTitle);
    }
    if (needsPassword) {
      throw const FormatException(Zh.needPassword);
    }
    final value = await action();
    if (client.folderFilterDropped && !_folderNotified) {
      _folderNotified = true;
      toast(Zh.folderFilterUnavailable);
    }
    return value;
  }

  LibraryRecord? _find(String? id) {
    if (id == null) return null;
    for (final library in libraries) {
      if (library.id == id) return library;
    }
    return null;
  }

  _ClientSnapshot _clientSnapshot() {
    return _ClientSnapshot(
      baseUrl: client.baseUrl,
      username: client.username,
      password: client.password,
      pinned: client.pinnedFingerprint,
      formPost: client.formPost,
      trustNew: client.trustNewCertificate,
    );
  }

  void _restoreClient(_ClientSnapshot snapshot) {
    client
      ..baseUrl = snapshot.baseUrl
      ..username = snapshot.username
      ..password = snapshot.password
      ..pinnedFingerprint = snapshot.pinned
      ..formPost = snapshot.formPost
      ..trustNewCertificate = snapshot.trustNew;
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    unawaited(messages.close());
    super.dispose();
  }
}

class _ClientSnapshot {
  const _ClientSnapshot({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.pinned,
    required this.formPost,
    required this.trustNew,
  });

  final String? baseUrl;
  final String? username;
  final String? password;
  final String? pinned;
  final bool formPost;
  final bool trustNew;
}

abstract class NetworkStatus {
  const NetworkStatus();
  Future<bool> get cellular;
}

class PluginNetworkStatus implements NetworkStatus {
  const PluginNetworkStatus();

  @override
  Future<bool> get cellular async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final results = await Connectivity().checkConnectivity();
      final wifi =
          results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet);
      if (wifi) return false;
      return results.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }
}

class FixedNetworkStatus implements NetworkStatus {
  const FixedNetworkStatus(this.isCellular);
  final bool isCellular;

  @override
  Future<bool> get cellular async => isCellular;
}
