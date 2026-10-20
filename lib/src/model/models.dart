import 'dart:convert';

enum QualityMode { auto, original, saver }

enum RepeatMode { off, all, one }

class AppSettings {
  const AppSettings({
    this.quality = QualityMode.auto,
    this.replayGain = true,
    this.cacheEnabled = true,
    this.cacheLimitBytes = defaultCacheLimit,
    this.lrcApiBase = '',
  });

  static const defaultCacheLimit = 512 * 1024 * 1024;

  final QualityMode quality;
  final bool replayGain;
  final bool cacheEnabled;
  final int cacheLimitBytes;

  /// Base address of an LrcApi server. Empty means do not call it.
  final String lrcApiBase;

  AppSettings copyWith({
    QualityMode? quality,
    bool? replayGain,
    bool? cacheEnabled,
    int? cacheLimitBytes,
    String? lrcApiBase,
  }) {
    return AppSettings(
      quality: quality ?? this.quality,
      replayGain: replayGain ?? this.replayGain,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      cacheLimitBytes: cacheLimitBytes ?? this.cacheLimitBytes,
      lrcApiBase: lrcApiBase ?? this.lrcApiBase,
    );
  }

  static QualityMode qualityFromName(String? name) {
    return QualityMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => QualityMode.auto,
    );
  }
}

class ReplayGain {
  const ReplayGain({this.trackGain, this.albumGain, this.trackPeak, this.albumPeak});

  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;

  bool get isEmpty =>
      trackGain == null && albumGain == null && trackPeak == null && albumPeak == null;

  Map<String, dynamic> toJson() => {
    'trackGain': trackGain,
    'albumGain': albumGain,
    'trackPeak': trackPeak,
    'albumPeak': albumPeak,
  };

  static ReplayGain? fromJson(Object? json) {
    if (json is! Map) return null;
    final gain = ReplayGain(
      trackGain: _asDouble(json['trackGain']),
      albumGain: _asDouble(json['albumGain']),
      trackPeak: _asDouble(json['trackPeak']),
      albumPeak: _asDouble(json['albumPeak']),
    );
    return gain.isEmpty ? null : gain;
  }
}

class Song {
  const Song({
    required this.id,
    required this.title,
    this.artist = '',
    this.displayArtist = '',
    this.album = '',
    this.albumId = '',
    this.artistId = '',
    this.coverArt = '',
    this.duration = 0,
    this.track = 0,
    this.discNumber = 1,
    this.year = 0,
    this.bitRate = 0,
    this.suffix = '',
    this.contentType = '',
    this.genre = '',
    this.starred = false,
    this.replayGain,
  });

  final String id;
  final String title;
  final String artist;
  final String displayArtist;
  final String album;
  final String albumId;
  final String artistId;
  final String coverArt;
  final int duration;
  final int track;
  final int discNumber;
  final int year;
  final int bitRate;
  final String suffix;
  final String contentType;
  final String genre;
  final bool starred;
  final ReplayGain? replayGain;

  String get artistLabel => displayArtist.isNotEmpty ? displayArtist : artist;

  Duration get durationValue => Duration(seconds: duration < 0 ? 0 : duration);

  Song copyWith({bool? starred}) => Song(
    id: id,
    title: title,
    artist: artist,
    displayArtist: displayArtist,
    album: album,
    albumId: albumId,
    artistId: artistId,
    coverArt: coverArt,
    duration: duration,
    track: track,
    discNumber: discNumber,
    year: year,
    bitRate: bitRate,
    suffix: suffix,
    contentType: contentType,
    genre: genre,
    starred: starred ?? this.starred,
    replayGain: replayGain,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'displayArtist': displayArtist,
    'album': album,
    'albumId': albumId,
    'artistId': artistId,
    'coverArt': coverArt,
    'duration': duration,
    'track': track,
    'discNumber': discNumber,
    'year': year,
    'bitRate': bitRate,
    'suffix': suffix,
    'contentType': contentType,
    'genre': genre,
    'starred': starred,
    'replayGain': replayGain?.toJson(),
  };

  static Song fromJson(Map<String, dynamic> json) {
    return Song(
      id: _asId(json['id']),
      title: _asString(json['title']),
      artist: _asString(json['artist']),
      displayArtist: _asString(json['displayArtist']),
      album: _asString(json['album']),
      albumId: _asId(json['albumId']),
      artistId: _asId(json['artistId']),
      coverArt: _asString(json['coverArt']),
      duration: _asInt(json['duration']),
      track: _asInt(json['track']),
      discNumber: _asInt(json['discNumber'], fallback: 1),
      year: _asInt(json['year']),
      bitRate: _asInt(json['bitRate']),
      suffix: _asString(json['suffix']),
      contentType: _asString(json['contentType']),
      genre: _asString(json['genre']),
      starred: json['starred'] == true,
      replayGain: ReplayGain.fromJson(json['replayGain']),
    );
  }
}

class Album {
  const Album({
    required this.id,
    required this.name,
    this.artist = '',
    this.displayArtist = '',
    this.artistId = '',
    this.coverArt = '',
    this.songCount = 0,
    this.duration = 0,
    this.year = 0,
    this.genre = '',
    this.starred = false,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String artist;
  final String displayArtist;
  final String artistId;
  final String coverArt;
  final int songCount;
  final int duration;
  final int year;
  final String genre;
  final bool starred;
  final List<Song> songs;

  String get artistLabel => displayArtist.isNotEmpty ? displayArtist : artist;

  Album copyWith({bool? starred, List<Song>? songs}) => Album(
    id: id,
    name: name,
    artist: artist,
    displayArtist: displayArtist,
    artistId: artistId,
    coverArt: coverArt,
    songCount: songCount,
    duration: duration,
    year: year,
    genre: genre,
    starred: starred ?? this.starred,
    songs: songs ?? this.songs,
  );
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.coverArt = '',
    this.albumCount = 0,
    this.starred = false,
    this.albums = const [],
  });

  final String id;
  final String name;
  final String coverArt;
  final int albumCount;
  final bool starred;
  final List<Album> albums;

  Artist copyWith({bool? starred, List<Album>? albums}) => Artist(
    id: id,
    name: name,
    coverArt: coverArt,
    albumCount: albumCount,
    starred: starred ?? this.starred,
    albums: albums ?? this.albums,
  );
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.comment = '',
    this.songCount = 0,
    this.duration = 0,
    this.coverArt = '',
    this.songs = const [],
  });

  final String id;
  final String name;
  final String comment;
  final int songCount;
  final int duration;
  final String coverArt;
  final List<Song> songs;
}

class Genre {
  const Genre({required this.name, this.songCount = 0, this.albumCount = 0});

  final String name;
  final int songCount;
  final int albumCount;
}

class MusicFolder {
  const MusicFolder({required this.id, required this.name});

  final String id;
  final String name;
}

class FolderEntry {
  const FolderEntry({
    required this.id,
    required this.name,
    required this.isDir,
    this.song,
    this.coverArt = '',
  });

  final String id;
  final String name;
  final bool isDir;
  final Song? song;
  final String coverArt;
}

class ArtistIndex {
  const ArtistIndex({required this.name, required this.artists});

  final String name;
  final List<Artist> artists;
}

class ServerInfo {
  const ServerInfo({
    required this.unrecognized,
    required this.hasTranscoding,
    required this.hasSongLyrics,
    required this.hasFormPost,
    required this.hasTranscodeOffset,
    this.serverVersion,
    this.type,
    this.extensions = const [],
  });

  final bool unrecognized;
  final bool hasTranscoding;
  final bool hasSongLyrics;
  final bool hasFormPost;
  final bool hasTranscodeOffset;
  final String? serverVersion;
  final String? type;
  final List<String> extensions;

  static const empty = ServerInfo(
    unrecognized: true,
    hasTranscoding: false,
    hasSongLyrics: false,
    hasFormPost: false,
    hasTranscodeOffset: false,
  );
}

class LibraryRecord {
  const LibraryRecord({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    this.musicFolderId,
    this.certFingerprint,
    this.unrecognized = false,
    this.hasTranscoding = false,
    this.hasSongLyrics = false,
    this.hasFormPost = false,
    this.hasTranscodeOffset = false,
    this.serverVersion,
    this.createdAt = 0,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String? musicFolderId;
  final String? certFingerprint;
  final bool unrecognized;
  final bool hasTranscoding;
  final bool hasSongLyrics;
  final bool hasFormPost;
  final bool hasTranscodeOffset;
  final String? serverVersion;
  final int createdAt;

  bool get http => baseUrl.startsWith('http://');

  LibraryRecord copyWith({
    String? name,
    String? baseUrl,
    String? username,
    String? musicFolderId,
    bool clearFolder = false,
    String? certFingerprint,
    bool clearCert = false,
    bool? unrecognized,
    bool? hasTranscoding,
    bool? hasSongLyrics,
    bool? hasFormPost,
    bool? hasTranscodeOffset,
    String? serverVersion,
  }) {
    return LibraryRecord(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      musicFolderId: clearFolder ? null : musicFolderId ?? this.musicFolderId,
      certFingerprint: clearCert ? null : certFingerprint ?? this.certFingerprint,
      unrecognized: unrecognized ?? this.unrecognized,
      hasTranscoding: hasTranscoding ?? this.hasTranscoding,
      hasSongLyrics: hasSongLyrics ?? this.hasSongLyrics,
      hasFormPost: hasFormPost ?? this.hasFormPost,
      hasTranscodeOffset: hasTranscodeOffset ?? this.hasTranscodeOffset,
      serverVersion: serverVersion ?? this.serverVersion,
      createdAt: createdAt,
    );
  }
}

class QueueItem {
  const QueueItem({required this.song, this.albumGain = false});

  final Song song;
  final bool albumGain;

  Map<String, dynamic> toJson() => {'albumGain': albumGain, 'song': song.toJson()};

  static QueueItem fromJson(Map<String, dynamic> json) {
    final songJson = json['song'];
    return QueueItem(
      song: Song.fromJson(
        songJson is Map ? Map<String, dynamic>.from(songJson) : const {},
      ),
      albumGain: json['albumGain'] == true,
    );
  }
}

class QueueSnapshot {
  const QueueSnapshot({
    this.items = const [],
    this.index = 0,
    this.positionMs = 0,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
  });

  final List<QueueItem> items;
  final int index;
  final int positionMs;
  final bool shuffle;
  final RepeatMode repeat;

  bool get isEmpty => items.isEmpty;

  String toJsonString() => jsonEncode({
    'index': index,
    'positionMs': positionMs,
    'shuffle': shuffle,
    'repeat': repeat.name,
    'items': items.map((item) => item.toJson()).toList(),
  });

  static QueueSnapshot parse(String? raw) {
    if (raw == null || raw.isEmpty) return const QueueSnapshot();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const QueueSnapshot();
    final itemsRaw = decoded['items'];
    final items = <QueueItem>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map) items.add(QueueItem.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return QueueSnapshot(
      items: items,
      index: _asInt(decoded['index']),
      positionMs: _asInt(decoded['positionMs']),
      shuffle: decoded['shuffle'] == true,
      repeat: RepeatMode.values.firstWhere(
        (mode) => mode.name == decoded['repeat'],
        orElse: () => RepeatMode.off,
      ),
    );
  }
}

class SearchPageResult {
  const SearchPageResult({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

class StarredCollection {
  const StarredCollection({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

class LyricLine {
  const LyricLine({this.start, required this.text});

  final Duration? start;
  final String text;
}

class LyricTrack {
  const LyricTrack({required this.synced, required this.lines, this.offset = Duration.zero});

  final bool synced;
  final List<LyricLine> lines;
  final Duration offset;

  bool get isEmpty => lines.isEmpty || lines.every((line) => line.text.trim().isEmpty);
}

String _asString(Object? value) => value == null ? '' : value.toString();

String _asId(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
  return value.toString();
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<Song> sortAlbumSongs(List<Song> songs) {
  final indexed = songs.asMap().entries.toList();
  indexed.sort((a, b) {
    final disc = a.value.discNumber.compareTo(b.value.discNumber);
    if (disc != 0) return disc;
    final track = a.value.track.compareTo(b.value.track);
    if (track != 0) return track;
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList();
}
