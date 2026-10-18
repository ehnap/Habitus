import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../model/models.dart';
import '../storage/audio_cache.dart';
import '../storage/cover_cache.dart';
import 'audio_proxy.dart';
import 'format_policy.dart';
import 'gain.dart';
import 'queue_logic.dart' as queue_logic;
import 'scrobble.dart';
import 'stream_choice.dart';
import '../subsonic/client.dart';

class PlaybackView {
  const PlaybackView({
    this.items = const [],
    this.index = 0,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.routeLabel = '',
    this.buffering = false,
  });

  final List<QueueItem> items;
  final int index;
  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool shuffle;
  final RepeatMode repeat;
  final String routeLabel;
  final bool buffering;

  bool get hasSong => items.isNotEmpty;

  Song? get song {
    if (items.isEmpty) return null;
    final safe = index < 0 ? 0 : (index >= items.length ? items.length - 1 : index);
    return items[safe].song;
  }
}

class PlaybackViewModel extends ChangeNotifier {
  PlaybackView view = const PlaybackView();

  void set(PlaybackView next) {
    view = next;
    notifyListeners();
  }
}

typedef ScrobbleCallback =
    Future<void> Function(String id, {required bool submission, int? timeMs});

class HabitusAudioHandler extends BaseAudioHandler with SeekHandler {
  HabitusAudioHandler({
    required this.client,
    required this.cache,
    required this.covers,
    required this.proxy,
    AudioPlayer? player,
  }) : _player = player ??
           AudioPlayer(
             handleInterruptions: false,
             useLazyPreparation: false,
             useProxyForRequestHeaders: false,
           ) {
    _player.playerStateStream.listen((_) {
      _publish(force: true);
      _broadcast();
    });
    _player.positionStream.listen(_onPosition);
    _player.currentIndexStream.listen(_onPlayerIndex);
    _player.processingStateStream.listen(_onProcessing);
    _player.errorStream.listen(_onError);
    _wireSession();
    supportsReplayGain =
        Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;
  }

  final SubsonicClient client;
  final AudioCache cache;
  final CoverCache covers;
  final LocalAudioProxy proxy;
  final AudioPlayer _player;
  Future<bool> Function() preferDirect = () async => true;
  ScrobbleCallback onScrobble = (String id, {required bool submission, int? timeMs}) async {};
  void Function(String message) onNotice = (_) {};
  final PlaybackViewModel views = PlaybackViewModel();

  LibraryRecord? library;
  bool replayGain = true;
  bool cacheEnabled = true;
  PlatformGroup platform = PlatformGroup.other;
  String platformLabel = 'Linux';
  bool supportsReplayGain = true;

  final List<QueueItem> _items = [];
  final Map<int, PlaybackRoute> _routes = {};
  final ListenClock _clock = ListenClock();
  int _index = 0;
  int _windowStart = 0;
  int _generation = 0;
  int _prefetchGeneration = 0;
  int _failures = 0;
  Duration _origin = Duration.zero;
  Duration? _pendingPosition;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  String _routeLabel = '';
  bool _handlingError = false;
  bool _missingPlayer = false;
  DateTime _lastPublish = DateTime.fromMillisecondsSinceEpoch(0);

  QueueSnapshot snapshot() {
    return QueueSnapshot(
      items: List<QueueItem>.of(_items),
      index: _index,
      positionMs: _reported().inMilliseconds,
      shuffle: _shuffle,
      repeat: _repeat,
    );
  }

  void configure({
    required LibraryRecord? library,
    required String? password,
    required bool replayGain,
    required bool cacheEnabled,
    required int cacheLimitBytes,
    required PlatformGroup platform,
    required String platformLabel,
  }) {
    this.library = library;
    this.replayGain = replayGain;
    this.cacheEnabled = cacheEnabled;
    cache.limitBytes = cacheLimitBytes;
    this.platform = platform;
    this.platformLabel = platformLabel;
    client.password = password;
    client.formPost = library?.hasFormPost ?? false;
    client.trustNewCertificate = false;
    if (library != null) {
      client.baseUrl = library.baseUrl;
      client.username = library.username;
      client.pinnedFingerprint = library.certFingerprint;
    } else {
      client.baseUrl = null;
      client.username = null;
      client.pinnedFingerprint = null;
    }
  }

  Future<void> restore(QueueSnapshot snapshot) async {
    _generation++;
    _items
      ..clear()
      ..addAll(snapshot.items);
    _index = _items.isEmpty ? 0 : snapshot.index.clamp(0, _items.length - 1);
    _shuffle = snapshot.shuffle;
    _repeat = snapshot.repeat;
    _pendingPosition = Duration(milliseconds: snapshot.positionMs < 0 ? 0 : snapshot.positionMs);
    _origin = Duration.zero;
    _routes.clear();
    _routeLabel = '';
    await _safe(() => _player.stop());
    await _syncQueue();
    _publish(force: true);
    _broadcast();
  }

  Future<void> playItems(List<QueueItem> items, {int index = 0}) async {
    _items
      ..clear()
      ..addAll(items);
    _index = items.isEmpty ? 0 : index.clamp(0, items.length - 1);
    _pendingPosition = Duration.zero;
    _failures = 0;
    await _syncQueue();
    if (_items.isEmpty) {
      _publish(force: true);
      return;
    }
    await _load(index: _index, play: true);
  }

  Future<void> addNext(Song song) async {
    final item = QueueItem(song: song);
    final at = _items.isEmpty ? 0 : _index + 1;
    _items.insert(at, item);
    await _syncQueue();
    _publish(force: true);
  }

  Future<void> addToEnd(Song song) async {
    _items.add(QueueItem(song: song));
    await _syncQueue();
    _publish(force: true);
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    final wasPlaying = _player.playing;
    final current = _index;
    _items.removeAt(index);
    _index = queue_logic.indexAfterRemoval(current, index, _items.length);
    await _syncQueue();
    if (_items.isEmpty) {
      _generation++;
      await _player.stop();
      _publish(force: true);
      _broadcast();
      return;
    }
    if (index == current) {
      await _load(index: _index, play: wasPlaying);
    } else {
      _publish(force: true);
    }
  }

  Future<void> moveToNext(int index) async {
    final moved = queue_logic.moveItemToNext(List<QueueItem>.of(_items), _index, index);
    _items
      ..clear()
      ..addAll(moved);
    await _syncQueue();
    _publish(force: true);
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffle = enabled;
    if (enabled && _index + 1 < _items.length) {
      final head = _items.sublist(0, _index + 1);
      final tail = _items.sublist(_index + 1)..shuffle();
      _items
        ..clear()
        ..addAll(head)
        ..addAll(tail);
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: _shuffleMode));
    await _syncQueue();
    _publish(force: true);
  }

  Future<void> setRepeat(RepeatMode mode) async {
    _repeat = mode;
    if (_player.processingState != ProcessingState.idle) {
      await _player.setLoopMode(mode == RepeatMode.one ? LoopMode.one : LoopMode.off);
    }
    _publish(force: true);
    _broadcast();
  }

  @override
  Future<void> play() async {
    if (_items.isEmpty) return;
    final ready = _player.processingState == ProcessingState.ready ||
        _player.processingState == ProcessingState.buffering ||
        _player.processingState == ProcessingState.completed;
    if (!ready || _routes[_index] == null) {
      await _load(index: _index, play: true, position: _pendingPosition ?? Duration.zero);
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _load(index: _index, play: true, position: Duration.zero);
      return;
    }
    await _player.play();
    _armListen();
  }

  @override
  Future<void> pause() async {
    await _safe(() => _player.pause());
    _publish(force: true);
    _broadcast();
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _safe(() => _player.stop());
    _publish(force: true);
    _broadcast();
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (error is MissingPluginException || error is UnimplementedError || error is UnsupportedError) {
        supportsReplayGain = false;
        if (!_missingPlayer) {
          _missingPlayer = true;
          onNotice(Zh.playerMissing);
        }
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final route = _routes[_index];
    final song = _currentSong;
    if (route == null || song == null) {
      _pendingPosition = position;
      _publish(force: true);
      return;
    }
    if (route.direct) {
      _origin = Duration.zero;
      await _player.seek(position);
      _pendingPosition = null;
      _broadcast();
      _publish(force: true);
      return;
    }
    if (route.seekWithOffset || route.seekWithTimeOffset) {
      await _load(
        index: _index,
        play: _player.playing || _player.processingState == ProcessingState.idle,
        position: position,
        reuseRoute: route,
      );
      return;
    }
    try {
      await _player.seek(position);
    } catch (_) {
      onNotice(Zh.seekUnavailable);
    }
  }

  @override
  Future<void> skipToNext() => _skip(1);

  @override
  Future<void> skipToPrevious() async {
    if (_reported() > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    await _skip(-1);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _items.length) return;
    await _load(index: index, play: true);
  }

  Future<void> _skip(int delta) async {
    if (_items.isEmpty) return;
    var next = _index + delta;
    if (next < 0) next = 0;
    if (next >= _items.length) {
      if (_repeat == RepeatMode.all) {
        next = 0;
      } else {
        await pause();
        return;
      }
    }
    await _load(index: next, play: true);
  }

  Future<void> _load({
    required int index,
    required bool play,
    Duration position = Duration.zero,
    bool forceTranscode = false,
    PlaybackRoute? reuseRoute,
  }) async {
    if (index < 0 || index >= _items.length) return;
    final generation = ++_generation;
    _prefetchGeneration++;
    _index = index;
    _windowStart = index;
    _routes.clear();
    _publish(force: true);

    try {
      final route = reuseRoute ??
          await _resolve(index, forceTranscode: forceTranscode);
      if (generation != _generation) return;
      if (route == null) {
        await _fail(play: play);
        return;
      }
      _routes[index] = route;
      _routeLabel = route.label;
      final opening = route.direct ? position : Duration.zero;
      if (!route.direct && position > Duration.zero) {
        _origin = Duration(seconds: position.inSeconds);
      } else {
        _origin = Duration.zero;
      }
      final sources = <AudioSource>[await _sourceFor(index, route, openingOffset: position)];
      if (index + 1 < _items.length) {
        try {
          final next = await _resolve(index + 1, forceTranscode: false);
          if (generation != _generation) return;
          if (next != null && route.direct && sameDirectDecoder(route, next)) {
            _routes[index + 1] = next;
            sources.add(await _sourceFor(index + 1, next, openingOffset: Duration.zero));
          } else if (next != null && cacheEnabled) {
            unawaited(_prefetch(index + 1, next));
          }
        } catch (_) {
          // The current song can still play if the next one cannot be prepared.
        }
      }
      await _player.setLoopMode(_repeat == RepeatMode.one ? LoopMode.one : LoopMode.off);
      await _player.setAudioSources(sources, initialPosition: opening);
      if (generation != _generation) return;
      await _applyGain(index, route);
      await _updateMediaItem(index);
      _pendingPosition = null;
      _failures = 0;
      if (play) {
        await _player.play();
        _armListen();
      }
      _publish(force: true);
      _broadcast();
    } on AppFailure catch (error) {
      if (generation != _generation) return;
      if (error.kind == FailureKind.network) {
        onNotice(Zh.networkNextFailed);
        await _player.pause();
        _publish(force: true);
        return;
      }
      if (error.kind == FailureKind.notFound) {
        onNotice(Zh.notFound);
        await _fail(play: play);
        return;
      }
      if (!forceTranscode && reuseRoute == null) {
        await _load(index: index, play: play, position: position, forceTranscode: true);
        return;
      }
      await _fail(play: play);
    } catch (error) {
      if (generation != _generation) return;
      if (error is PlayerInterruptedException) return;
      if (error is MissingPluginException) {
        onNotice(Zh.playerMissing);
        supportsReplayGain = false;
        _publish(force: true);
        return;
      }
      if (!forceTranscode && reuseRoute == null) {
        await _load(index: index, play: play, position: position, forceTranscode: true);
        return;
      }
      await _fail(play: play);
    }
  }

  Future<PlaybackRoute?> _resolve(int index, {required bool forceTranscode}) async {
    final song = _items[index].song;
    final current = library;
    if (current == null) {
      throw const AppFailure(FailureKind.invalidInput, Zh.needPassword);
    }
    final wantDirect = forceTranscode ? false : await preferDirect();
    final local = suffixCanDirect(platform, song.suffix);
    TranscodeDecision? decision;
    if (current.hasTranscoding && !forceTranscode) {
      decision = await client.transcodeDecision(
        mediaId: song.id,
        body: clientInfoBody(
          platformLabel: platformLabel,
          platform: platform,
          allowDirect: wantDirect && local,
        ),
      );
    }
    final choice = chooseRoute(
      hasTranscoding: current.hasTranscoding && !forceTranscode,
      hasTranscodeOffset: current.hasTranscodeOffset,
      wantDirect: wantDirect,
      localCanDirect: local,
      suffix: song.suffix,
      forceTranscode: forceTranscode,
      decision: decision,
    );
    if (choice.notFound) {
      throw const AppFailure(FailureKind.notFound, Zh.notFound);
    }
    return choice.route;
  }

  Future<AudioSource> _sourceFor(
    int index,
    PlaybackRoute route, {
    required Duration openingOffset,
  }) async {
    final song = _items[index].song;
    final libraryId = library?.id ?? '';
    final key = audioCacheKey(libraryId: libraryId, songId: song.id, direct: route.direct);
    if (cacheEnabled) {
      final cached = await cache.completeFile(key);
      if (cached != null && openingOffset == Duration.zero) {
        return AudioSource.file(cached.path);
      }
    }
    final offset = route.direct ? 0 : openingOffset.inSeconds;
    final uri = proxy.register(
      endpoint: route.endpoint,
      query: route.query(mediaId: song.id, offsetSeconds: offset),
      libraryId: libraryId,
      cacheKey: cacheEnabled && offset == 0 ? key : null,
      cacheEnabled: cacheEnabled && offset == 0,
    );
    return AudioSource.uri(uri);
  }

  Future<void> _prefetch(int index, PlaybackRoute route) async {
    if (!cacheEnabled || library == null || index < 0 || index >= _items.length) return;
    final generation = _prefetchGeneration;
    final song = _items[index].song;
    final key = audioCacheKey(libraryId: library!.id, songId: song.id, direct: route.direct);
    if (await cache.completeFile(key) != null) return;
    if (generation != _prefetchGeneration) return;
    final file = await cache.begin(key, libraryId: library!.id);
    final sink = file.openWrite();
    try {
      final response = await client.openAudio(
        endpoint: route.endpoint,
        query: route.query(mediaId: song.id),
      );
      if (response.statusCode >= 400) {
        await response.drain<void>().catchError((_) {});
        await sink.close();
        await cache.abort(key);
        return;
      }
      var total = 0;
      await for (final chunk in response) {
        if (generation != _prefetchGeneration) {
          await sink.close();
          await cache.abort(key);
          return;
        }
        sink.add(chunk);
        total += chunk.length;
      }
      await sink.close();
      if (generation != _prefetchGeneration) {
        await cache.abort(key);
        return;
      }
      await cache.commit(key, total);
    } catch (_) {
      await sink.close();
      await cache.abort(key);
    }
  }

  Future<void> _fail({required bool play}) async {
    _failures += 1;
    onNotice(Zh.cannotPlay);
    if (_failures >= 3) {
      onNotice(Zh.stoppedAfterFailures);
      await _player.pause();
      _publish(force: true);
      _broadcast();
      return;
    }
    if (_index + 1 < _items.length) {
      await _load(index: _index + 1, play: play);
    } else {
      await _player.pause();
      _publish(force: true);
    }
  }

  Future<void> _applyGain(int index, PlaybackRoute route) async {
    if (!supportsReplayGain || index < 0 || index >= _items.length) return;
    final item = _items[index];
    final gain = item.song.replayGain;
    final volume = gainForTrack(
      enabled: replayGain,
      direct: route.direct,
      albumContext: item.albumGain,
      trackGain: gain?.trackGain,
      albumGain: gain?.albumGain,
      trackPeak: gain?.trackPeak,
      albumPeak: gain?.albumPeak,
    );
    try {
      await _player.setVolume((volume ?? 1).clamp(0, 1));
    } catch (_) {
      supportsReplayGain = false;
    }
  }

  void _armListen() {
    final song = _currentSong;
    if (song == null) return;
    _clock.start(DateTime.now().millisecondsSinceEpoch);
    onScrobble(song.id, submission: false);
  }

  void _onPosition(Duration position) {
    final song = _currentSong;
    final reported = _reported(playerPosition: position);
    if (song != null) {
      final duration = _bestDuration(song);
      final submit = _clock.onPosition(
        position: reported,
        duration: duration,
        playing: _player.playing,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (_clock.restarted) onScrobble(song.id, submission: false);
      if (submit) {
        onScrobble(song.id, submission: true, timeMs: _clock.startedAtMs);
      }
    }
    _publish();
  }

  void _onPlayerIndex(int? playerIndex) {
    if (playerIndex == null) return;
    final logical = _windowStart + playerIndex;
    if (logical == _index || logical < 0 || logical >= _items.length) return;
    _index = logical;
    _origin = Duration.zero;
    final route = _routes[logical];
    if (route != null) {
      _routeLabel = route.label;
      unawaited(_applyGain(logical, route));
    }
    unawaited(_updateMediaItem(logical));
    if (_player.playing) _armListen();
    _publish(force: true);
    _broadcast();
  }

  void _onProcessing(ProcessingState state) {
    if (state != ProcessingState.completed || _handlingError) return;
    if (_repeat == RepeatMode.one) return;
    if (_index + 1 < _items.length) {
      unawaited(_load(index: _index + 1, play: true));
      return;
    }
    if (_repeat == RepeatMode.all && _items.isNotEmpty) {
      unawaited(_load(index: 0, play: true));
      return;
    }
    unawaited(pause());
  }

  void _onError(PlayerException exception) {
    if (_handlingError) return;
    _handlingError = true;
    final route = _routes[_index];
    final direct = route?.direct ?? true;
    unawaited(() async {
      try {
        if (direct) {
          await _load(
            index: _index,
            play: true,
            position: _reported(),
            forceTranscode: true,
          );
        } else {
          await _fail(play: true);
        }
      } finally {
        _handlingError = false;
      }
    }());
  }

  Future<void> _updateMediaItem(int index) async {
    if (index < 0 || index >= _items.length) return;
    final song = _items[index].song;
    Uri? art;
    final libraryId = library?.id;
    if (libraryId != null && song.coverArt.isNotEmpty) {
      final file = await covers.fileFor(libraryId: libraryId, coverArt: song.coverArt, size: 300);
      if (file != null) art = Uri.file(file.path);
    }
    final item = MediaItem(
      id: song.id,
      title: song.title.isEmpty ? Zh.appName : song.title,
      artist: song.artistLabel,
      album: song.album,
      duration: song.durationValue,
      artUri: art,
    );
    mediaItem.add(item);
  }

  Future<void> _syncQueue() async {
    queue.add([
      for (final item in _items)
        MediaItem(
          id: item.song.id,
          title: item.song.title.isEmpty ? Zh.appName : item.song.title,
          artist: item.song.artistLabel,
          album: item.song.album,
          duration: item.song.durationValue,
        ),
    ]);
  }

  Duration _reported({Duration? playerPosition}) {
    if (_pendingPosition != null && _player.processingState == ProcessingState.idle) {
      return _pendingPosition!;
    }
    return _origin + (playerPosition ?? _player.position);
  }

  Duration _bestDuration(Song song) {
    final playerDuration = _player.duration;
    if (playerDuration != null && playerDuration > Duration.zero) return playerDuration;
    return song.durationValue;
  }

  Song? get _currentSong {
    if (_items.isEmpty) return null;
    final safe = _index.clamp(0, _items.length - 1);
    return _items[safe].song;
  }

  void _publish({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPublish) < const Duration(milliseconds: 200)) return;
    _lastPublish = now;
    final song = _currentSong;
    views.set(
      PlaybackView(
        items: List<QueueItem>.of(_items),
        index: _index,
        playing: _player.playing,
        position: _reported(),
        duration: song == null ? Duration.zero : _bestDuration(song),
        buffered: _origin + _player.bufferedPosition,
        shuffle: _shuffle,
        repeat: _repeat,
        routeLabel: _routeLabel,
        buffering: _player.processingState == ProcessingState.buffering ||
            _player.processingState == ProcessingState.loading,
      ),
    );
  }

  void _broadcast() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapState(_player.processingState),
        playing: _player.playing,
        updatePosition: _reported(),
        bufferedPosition: _origin + _player.bufferedPosition,
        speed: _player.playing ? 1 : 0,
        queueIndex: _items.isEmpty ? null : _index,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
      ),
    );
  }

  AudioServiceRepeatMode get _repeatMode {
    switch (_repeat) {
      case RepeatMode.one:
        return AudioServiceRepeatMode.one;
      case RepeatMode.all:
        return AudioServiceRepeatMode.all;
      case RepeatMode.off:
        return AudioServiceRepeatMode.none;
    }
  }

  AudioServiceShuffleMode get _shuffleMode =>
      _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none;

  AudioProcessingState _mapState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void _wireSession() {
    AudioSession.instance.then((session) async {
      try {
        await session.configure(const AudioSessionConfiguration.music());
      } catch (_) {}
      session.becomingNoisyEventStream.listen((_) {
        unawaited(pause());
        onNotice(Zh.headphonesPaused);
      });
      session.interruptionEventStream.listen((event) {
        if (event.begin && event.type != AudioInterruptionType.duck) {
          unawaited(pause());
        }
      });
    }).catchError((_) {});
  }

  Future<void> setReplayGain(bool enabled) async {
    replayGain = enabled;
    final route = _routes[_index];
    if (route != null) await _applyGain(_index, route);
  }
}
