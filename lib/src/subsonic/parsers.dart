import '../copy/zh.dart';
import '../failure.dart';
import '../model/models.dart';
import '../playback/stream_choice.dart';

Map<String, dynamic> unwrapSubsonic(Object? decoded) {
  if (decoded is! Map) {
    throw const AppFailure(FailureKind.server, Zh.serverError);
  }
  final body = Map<String, dynamic>.from(decoded);
  final response = body['subsonic-response'];
  if (response is! Map) {
    throw const AppFailure(FailureKind.server, Zh.serverError);
  }
  return Map<String, dynamic>.from(response);
}

AppFailure? failureFromResponse(Map<String, dynamic> response) {
  if (response['status'] != 'failed') return null;
  final error = response['error'];
  var code = 0;
  if (error is Map && error['code'] is num) {
    code = (error['code'] as num).round();
  }
  return AppFailure(_kindForCode(code), messageForCode(code), code: code);
}

FailureKind _kindForCode(int code) {
  switch (code) {
    case 40:
    case 41:
      return FailureKind.wrongCredentials;
    case 50:
      return FailureKind.notAuthorized;
    case 70:
      return FailureKind.notFound;
    default:
      return FailureKind.server;
  }
}

String messageForCode(int code) {
  switch (code) {
    case 40:
    case 41:
      return Zh.wrongCredentials;
    case 50:
      return '没有权限访问';
    case 70:
      return Zh.notFound;
    case 10:
      return '请求缺少参数';
    case 20:
    case 30:
      return '客户端和服务器的协议版本不兼容';
    default:
      return Zh.genericError;
  }
}

List<Map<String, dynamic>> asMaps(Object? value) {
  if (value == null) return const [];
  if (value is List) {
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
  if (value is Map) return [Map<String, dynamic>.from(value)];
  return const [];
}

String asId(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
  return value.toString();
}

String asString(Object? value) => value == null ? '' : value.toString();

String firstText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final text = asString(json[key]).trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

int asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool asStarred(Object? value) => value != null && value.toString().isNotEmpty;

Song parseSong(Map<String, dynamic> json) {
  final replay = json['replayGain'];
  ReplayGain? gain;
  if (replay is Map) {
    final parsed = ReplayGain(
      trackGain: asDouble(replay['trackGain']),
      albumGain: asDouble(replay['albumGain']),
      trackPeak: asDouble(replay['trackPeak']),
      albumPeak: asDouble(replay['albumPeak']),
    );
    if (!parsed.isEmpty) gain = parsed;
  }
  return Song(
    id: asId(json['id']),
    title: firstText(json, const ['title', 'name']),
    artist: asString(json['artist']),
    displayArtist: asString(json['displayArtist']),
    album: asString(json['album']),
    albumId: asId(json['albumId']),
    artistId: asId(json['artistId']),
    coverArt: asString(json['coverArt']),
    duration: asInt(json['duration']),
    track: asInt(json['track']),
    discNumber: asInt(json['discNumber'], fallback: 1),
    year: asInt(json['year']),
    bitRate: asInt(json['bitRate']),
    suffix: asString(json['suffix']),
    contentType: asString(json['contentType']),
    genre: asString(json['genre']),
    starred: asStarred(json['starred']),
    replayGain: gain,
  );
}

Album parseAlbum(Map<String, dynamic> json) {
  final songs = sortAlbumSongs([for (final song in asMaps(json['song'])) parseSong(song)]);
  return Album(
    id: asId(json['id']),
    name: firstText(json, const ['name', 'title']),
    artist: asString(json['artist']),
    displayArtist: asString(json['displayArtist']),
    artistId: asId(json['artistId']),
    coverArt: asString(json['coverArt']),
    songCount: asInt(json['songCount'], fallback: songs.length),
    duration: asInt(json['duration']),
    year: asInt(json['year']),
    genre: asString(json['genre']),
    starred: asStarred(json['starred']),
    songs: songs,
  );
}

Artist parseArtist(Map<String, dynamic> json) {
  return Artist(
    id: asId(json['id']),
    name: asString(json['name']),
    coverArt: firstText(json, const ['coverArt', 'artistImageUrl']),
    albumCount: asInt(json['albumCount']),
    starred: asStarred(json['starred']),
    albums: [for (final album in asMaps(json['album'])) parseAlbum(album)],
  );
}

Playlist parsePlaylist(Map<String, dynamic> json) {
  final songs = [for (final song in asMaps(json['entry'])) parseSong(song)];
  return Playlist(
    id: asId(json['id']),
    name: asString(json['name']),
    comment: asString(json['comment']),
    songCount: asInt(json['songCount'], fallback: songs.length),
    duration: asInt(json['duration']),
    coverArt: asString(json['coverArt']),
    songs: songs,
  );
}

Genre parseGenre(Map<String, dynamic> json) {
  return Genre(
    name: asString(json['value'] ?? json['name']),
    songCount: asInt(json['songCount']),
    albumCount: asInt(json['albumCount']),
  );
}

List<Album> parseAlbumList(Map<String, dynamic> response) {
  final container = response['albumList2'];
  if (container is! Map) return const [];
  return [for (final album in asMaps(container['album'])) parseAlbum(album)];
}

List<ArtistIndex> parseArtistIndexes(Map<String, dynamic> response) {
  final container = response['artists'];
  if (container is! Map) return const [];
  final indexes = <ArtistIndex>[];
  for (final index in asMaps(container['index'])) {
    indexes.add(
      ArtistIndex(
        name: asString(index['name']),
        artists: [for (final artist in asMaps(index['artist'])) parseArtist(artist)],
      ),
    );
  }
  return indexes;
}

Album parseAlbumResponse(Map<String, dynamic> response) {
  final album = response['album'];
  if (album is! Map) {
    throw const AppFailure(FailureKind.notFound, Zh.notFound);
  }
  return parseAlbum(Map<String, dynamic>.from(album));
}

Artist parseArtistResponse(Map<String, dynamic> response) {
  final artist = response['artist'];
  if (artist is! Map) {
    throw const AppFailure(FailureKind.notFound, Zh.notFound);
  }
  return parseArtist(Map<String, dynamic>.from(artist));
}

List<Playlist> parsePlaylists(Map<String, dynamic> response) {
  final container = response['playlists'];
  if (container is! Map) return const [];
  return [for (final playlist in asMaps(container['playlist'])) parsePlaylist(playlist)];
}

Playlist parsePlaylistResponse(Map<String, dynamic> response) {
  final playlist = response['playlist'];
  if (playlist is! Map) {
    throw const AppFailure(FailureKind.notFound, Zh.notFound);
  }
  return parsePlaylist(Map<String, dynamic>.from(playlist));
}

SearchPageResult parseSearch(Map<String, dynamic> response) {
  final container = response['searchResult3'];
  if (container is! Map) return const SearchPageResult();
  final map = Map<String, dynamic>.from(container);
  return SearchPageResult(
    artists: [for (final artist in asMaps(map['artist'])) parseArtist(artist)],
    albums: [for (final album in asMaps(map['album'])) parseAlbum(album)],
    songs: [for (final song in asMaps(map['song'])) parseSong(song)],
  );
}

StarredCollection parseStarred(Map<String, dynamic> response) {
  final container = response['starred2'];
  if (container is! Map) return const StarredCollection();
  final map = Map<String, dynamic>.from(container);
  return StarredCollection(
    artists: [for (final artist in asMaps(map['artist'])) parseArtist(artist)],
    albums: [for (final album in asMaps(map['album'])) parseAlbum(album)],
    songs: [for (final song in asMaps(map['song'])) parseSong(song)],
  );
}

List<Genre> parseGenres(Map<String, dynamic> response) {
  final container = response['genres'];
  if (container is! Map) return const [];
  return [for (final genre in asMaps(container['genre'])) parseGenre(genre)];
}

List<Song> parseSongsByGenre(Map<String, dynamic> response) {
  final container = response['songsByGenre'];
  if (container is! Map) return const [];
  return [for (final song in asMaps(container['song'])) parseSong(song)];
}

List<Song> parseRandomSongs(Map<String, dynamic> response) {
  final container = response['randomSongs'];
  if (container is! Map) return const [];
  return [for (final song in asMaps(container['song'])) parseSong(song)];
}

List<MusicFolder> parseMusicFolders(Map<String, dynamic> response) {
  final container = response['musicFolders'];
  if (container is! Map) return const [];
  return [
    for (final folder in asMaps(container['musicFolder']))
      MusicFolder(id: asId(folder['id']), name: asString(folder['name'])),
  ];
}

List<ArtistIndex> parseIndexes(Map<String, dynamic> response) {
  final container = response['indexes'];
  if (container is! Map) return const [];
  return [
    for (final index in asMaps(container['index']))
      ArtistIndex(
        name: asString(index['name']),
        artists: [
          for (final artist in asMaps(index['artist']))
            Artist(
              id: asId(artist['id']),
              name: asString(artist['name']),
              coverArt: asString(artist['coverArt'] ?? artist['artistImageUrl']),
            ),
        ],
      ),
  ];
}

List<FolderEntry> parseDirectory(Map<String, dynamic> response) {
  final container = response['directory'];
  if (container is! Map) return const [];
  final entries = <FolderEntry>[];
  for (final child in asMaps(container['child'])) {
    final isDir = child['isDir'] == true;
    final song = isDir ? null : parseSong(child);
    entries.add(
      FolderEntry(
        id: asId(child['id']),
        name: asString(child['title'] ?? child['name']),
        isDir: isDir,
        song: song,
        coverArt: asString(child['coverArt']),
      ),
    );
  }
  return entries;
}

ServerInfo parseServerInfo(Map<String, dynamic> response) {
  final type = asString(response['type']).trim();
  if (type.isNotEmpty && type.toLowerCase() != 'navidrome') {
    throw const AppFailure(FailureKind.notNavidrome, Zh.notNavidrome);
  }
  final names = <String>[];
  for (final extension in asMaps(response['openSubsonicExtensions'])) {
    final name = asString(extension['name']);
    if (name.isNotEmpty) names.add(name);
  }
  bool has(String name) => names.any((item) => item.toLowerCase() == name.toLowerCase());
  return ServerInfo(
    unrecognized: type.isEmpty,
    hasTranscoding: has('transcoding'),
    hasSongLyrics: has('songLyrics'),
    hasFormPost: has('formPost'),
    hasTranscodeOffset: has('transcodeOffset'),
    serverVersion: asString(response['serverVersion']).isEmpty
        ? null
        : asString(response['serverVersion']),
    type: type.isEmpty ? null : type,
    extensions: names,
  );
}

TranscodeDecision parseDecision(Map<String, dynamic> response) {
  final raw = response['transcodeDecision'];
  if (raw is! Map) {
    return const TranscodeDecision(canDirectPlay: false, canTranscode: false);
  }
  final decision = Map<String, dynamic>.from(raw);
  final source = decision['sourceStream'];
  final transcode = decision['transcodeStream'];
  return TranscodeDecision(
    canDirectPlay: decision['canDirectPlay'] == true,
    canTranscode: decision['canTranscode'] == true,
    transcodeParams: asString(decision['transcodeParams']).isEmpty
        ? null
        : asString(decision['transcodeParams']),
    errorReason: asString(decision['errorReason']).isEmpty ? null : asString(decision['errorReason']),
    sourceCodec: source is Map ? asString(source['codec']) : null,
    sourceContainer: source is Map ? asString(source['container']) : null,
    transcodeProtocol: transcode is Map ? asString(transcode['protocol']) : null,
    transcodeCodec: transcode is Map ? asString(transcode['codec']) : null,
  );
}
