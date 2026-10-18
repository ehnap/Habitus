import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitus/src/copy/zh.dart';
import 'package:habitus/src/failure.dart';
import 'package:habitus/src/format.dart';
import 'package:habitus/src/model/models.dart';
import 'package:habitus/src/playback/format_policy.dart';
import 'package:habitus/src/playback/gain.dart';
import 'package:habitus/src/playback/lyrics.dart';
import 'package:habitus/src/playback/queue_logic.dart';
import 'package:habitus/src/playback/scrobble.dart';
import 'package:habitus/src/playback/stream_choice.dart';
import 'package:habitus/src/storage/app_database.dart';
import 'package:habitus/src/subsonic/auth.dart';
import 'package:habitus/src/subsonic/parsers.dart';
import 'package:habitus/src/subsonic/redact.dart';
import 'package:habitus/src/subsonic/url_rules.dart';
import 'package:habitus/src/theme/habitus_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('normalizes server urls', () {
    expect(normalizeBaseUrl('music.example.com/rest/').base, 'http://music.example.com');
    expect(normalizeBaseUrl('https://music.example.com:4533/navidrome/').base, 'https://music.example.com:4533/navidrome');
    expect(normalizeBaseUrl('https://music.example.com/REST').http, isFalse);
    expect(() => normalizeBaseUrl('   '), throwsA(isA<AppFailure>()));
  });

  test('token is md5 of password plus salt and client name has no version', () {
    expect(subsonicToken('sesame', 'abc'), 'ab3c35d2e29e863dbdd0df5bf3ec081f');
    expect(subsonicToken('sesame', 'abc'), md5.convert('sesameabc'.codeUnits).toString());
    expect(subsonicClient, 'Habitus');
    expect(subsonicVersion, '1.16.1');
    expect(newSalt(StreamRandom()).length, 24);
  });

  test('redacts secrets', () {
    expect(
      redactSecrets('https://x/rest/ping.view?u=a&t=secret&s=salt&p=nope&apiKey=nds_1'),
      'https://x/rest/ping.view?u=a&t=***&s=***&p=***&apiKey=***',
    );
  });

  test('parses songs, rejects other servers, and reads decisions', () {
    final song = parseSong({
      'id': 12,
      'title': '海',
      'artist': '甲',
      'duration': '200',
      'starred': '2020-01-01T00:00:00Z',
      'replayGain': {'trackGain': -6.0, 'trackPeak': 1.2},
      'suffix': 'flac',
    });
    expect(song.id, '12');
    expect(song.starred, isTrue);
    expect(song.replayGain?.trackGain, -6);
    expect(
      parseServerInfo({
        'type': 'navidrome',
        'serverVersion': '0.64.2',
        'openSubsonicExtensions': [
          {'name': 'transcoding'},
          {'name': 'songLyrics'},
          {'name': 'formPost'},
        ],
      }).hasTranscoding,
      isTrue,
    );
    expect(
      () => parseServerInfo({'type': 'gonic', 'openSubsonicExtensions': []}),
      throwsA(isA<AppFailure>().having((error) => error.kind, 'kind', FailureKind.notNavidrome)),
    );
    expect(parseServerInfo({'serverVersion': '0.64.2'}).unrecognized, isTrue);
    final decision = parseDecision({
      'transcodeDecision': {
        'canDirectPlay': true,
        'canTranscode': false,
        'transcodeParams': 'keep-me',
        'sourceStream': {'codec': 'flac'},
      },
    });
    expect(decision.transcodeParams, 'keep-me');
    expect(
      failureFromResponse({
        'status': 'failed',
        'error': {'code': 40, 'message': 'Wrong username or password'},
      })?.message,
      Zh.wrongCredentials,
    );
  });

  test('replaygain caps positive gain and peak', () {
    expect(replayGainVolume(gainDb: 6), 1);
    expect(replayGainVolume(gainDb: -6), closeTo(0.501187, 0.001));
    expect(replayGainVolume(gainDb: 0, peak: 2), 0.5);
    expect(replayGainVolume(), 1);
    expect(
      gainForTrack(
        enabled: true,
        direct: true,
        albumContext: true,
        albumGain: -3,
        trackGain: -12,
      ),
      replayGainVolume(gainDb: -3),
    );
    expect(gainForTrack(enabled: true, direct: false, albumContext: true, trackGain: -12), 1);
  });

  test('scrobble counts only natural progress', () {
    expect(ScrobbleRules.reached(duration: const Duration(seconds: 20), listened: const Duration(seconds: 20)), isFalse);
    expect(ScrobbleRules.reached(duration: const Duration(minutes: 3), listened: const Duration(seconds: 90)), isTrue);
    expect(ScrobbleRules.reached(duration: const Duration(minutes: 10), listened: const Duration(minutes: 3)), isFalse);
    expect(ScrobbleRules.reached(duration: const Duration(minutes: 10), listened: const Duration(minutes: 4)), isTrue);
    final clock = ListenClock()..start(1000);
    expect(
      clock.onPosition(
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 3),
        playing: true,
        nowMs: 2000,
      ),
      isFalse,
    );
    expect(
      clock.onPosition(
        position: const Duration(seconds: 100),
        duration: const Duration(minutes: 3),
        playing: true,
        nowMs: 3000,
      ),
      isFalse,
    );
    expect(clock.listened, Duration.zero);
    final playing = ListenClock()..start(4000);
    var submitted = false;
    for (var second = 0; second <= 90; second++) {
      submitted = playing.onPosition(
        position: Duration(seconds: second),
        duration: const Duration(minutes: 3),
        playing: true,
        nowMs: 4000 + second,
      );
      if (submitted) break;
    }
    expect(submitted, isTrue);
    expect(
      playing.onPosition(
        position: const Duration(seconds: 91),
        duration: const Duration(minutes: 3),
        playing: true,
        nowMs: 9000,
      ),
      isFalse,
    );
    final restart = ListenClock()..start(1);
    restart.onPosition(position: const Duration(seconds: 20), duration: const Duration(minutes: 3), playing: true, nowMs: 2);
    restart.onPosition(position: const Duration(milliseconds: 200), duration: const Duration(minutes: 3), playing: true, nowMs: 3);
    expect(restart.restarted, isTrue);
    expect(restart.listened, Duration.zero);
  });

  test('queue tap, album gain, and direct preference', () {
    final songs = [
      for (var i = 0; i < 4; i++) Song(id: '$i', title: 't$i'),
    ];
    final tapped = queueFromTap(songs: songs, index: 1, shuffle: false, albumGain: true);
    expect(tapped.map((item) => item.song.id), ['1', '2', '3']);
    expect(tapped.every((item) => item.albumGain), isTrue);
    final shuffled = queueFromTap(songs: songs, index: 0, shuffle: true, albumGain: true, random: _FixedRandom());
    expect(shuffled.first.song.id, '0');
    expect(shuffled.first.albumGain, isFalse);
    expect(queueFromAlbum(songs: songs, shuffle: false).first.albumGain, isTrue);
    final moved = moveItemToNext(
      [QueueItem(song: songs[0]), QueueItem(song: songs[1]), QueueItem(song: songs[2])],
      0,
      2,
    );
    expect(moved.map((item) => item.song.id), ['0', '2', '1']);
    expect(indexAfterRemoval(2, 0, 2), 1);
    expect(preferDirectPlay(quality: QualityMode.auto, cellular: true, phone: true), isFalse);
    expect(preferDirectPlay(quality: QualityMode.auto, cellular: true, phone: false), isTrue);
    expect(preferDirectPlay(quality: QualityMode.saver, cellular: false, phone: false), isFalse);
    expect(preferDirectPlay(quality: QualityMode.original, cellular: true, phone: true), isTrue);
  });

  test('direct profiles never declare hls', () {
    for (final platform in PlatformGroup.values) {
      final body = clientInfoBody(platformLabel: 'test', platform: platform, allowDirect: true);
      expect(declaresHls(body), isFalse);
      expect(body['maxTranscodingAudioBitrate'], 256000);
      expect(body['transcodingProfiles'], [aacTranscodeProfile]);
      final profiles = body['directPlayProfiles'] as List;
      expect(profiles.every((profile) => (profile['protocols'] as List).contains('http')), isTrue);
    }
    expect(suffixCanDirect(PlatformGroup.apple, 'opus'), isFalse);
    expect(suffixCanDirect(PlatformGroup.android, 'opus'), isTrue);
    expect(suffixCanDirect(PlatformGroup.windows, 'wma'), isTrue);
  });

  test('route falls back when navidrome drops aac or returns hls', () {
    final direct = chooseRoute(
      hasTranscoding: true,
      hasTranscodeOffset: true,
      wantDirect: true,
      localCanDirect: true,
      suffix: 'flac',
      forceTranscode: false,
      decision: const TranscodeDecision(
        canDirectPlay: true,
        canTranscode: false,
        transcodeParams: 'abc',
        sourceCodec: 'flac',
      ),
    );
    expect(direct.route?.direct, isTrue);
    expect(direct.route?.transcodeParams, 'abc');
    expect(direct.route?.endpoint, 'getTranscodeStream');

    final stripped = chooseRoute(
      hasTranscoding: true,
      hasTranscodeOffset: false,
      wantDirect: false,
      localCanDirect: false,
      suffix: 'ape',
      forceTranscode: false,
      decision: const TranscodeDecision(canDirectPlay: false, canTranscode: false),
    );
    expect(stripped.route?.direct, isFalse);
    expect(stripped.route?.endpoint, 'stream');
    expect(stripped.route?.classicFormat, 'aac');
    expect(stripped.route?.maxBitRateKbps, 256);

    final hls = chooseRoute(
      hasTranscoding: true,
      hasTranscodeOffset: true,
      wantDirect: false,
      localCanDirect: false,
      suffix: 'ape',
      forceTranscode: false,
      decision: const TranscodeDecision(
        canDirectPlay: false,
        canTranscode: true,
        transcodeParams: 'hls-params',
        transcodeProtocol: 'hls',
      ),
    );
    expect(hls.route?.endpoint, 'stream');
    expect(hls.route?.seekWithTimeOffset, isTrue);
    expect(chooseRoute(
      hasTranscoding: true,
      hasTranscodeOffset: false,
      wantDirect: true,
      localCanDirect: true,
      suffix: 'mp3',
      forceTranscode: false,
      decision: const TranscodeDecision(canDirectPlay: false, canTranscode: false, notFound: true),
    ).notFound, isTrue);
    expect(sameDirectDecoder(direct.route, direct.route), isTrue);
    expect(sameDirectDecoder(direct.route, stripped.route), isFalse);
  });

  test('lyrics offset directions', () {
    final structured = lyricsFromStructured({
      'structuredLyrics': {
        'synced': true,
        'offset': 500,
        'line': [
          {'start': 1000, 'value': '一'},
          {'start': 2000, 'value': '二'},
        ],
      },
    });
    expect(lineStart(structured!.lines.first, structured.offset), const Duration(milliseconds: 500));
    expect(activeLyricIndex(structured, const Duration(milliseconds: 499)), -1);
    expect(activeLyricIndex(structured, const Duration(milliseconds: 500)), 0);
    final lrc = lyricsFromPlainText('[offset:-200]\n[00:01.00]一\nplain');
    expect(lrc!.lines.first.start, const Duration(milliseconds: 800));
    expect(lrc.synced, isFalse);
  });

  test('database keeps libraries, settings, and paused queues', () async {
    final dir = await Directory.systemTemp.createTemp('habitus-db');
    final database = AppDatabase();
    await database.open('${dir.path}/app.db');
    final library = LibraryRecord(
      id: 'lib-a',
      name: '家里',
      baseUrl: 'https://music.example.com',
      username: 'ada',
      hasTranscoding: true,
      hasSongLyrics: true,
      createdAt: 10,
    );
    await database.upsertLibrary(library);
    await database.setCurrentLibraryId(library.id);
    await database.saveSettings(const AppSettings(quality: QualityMode.saver, replayGain: false, cacheEnabled: false));
    final queue = QueueSnapshot(
      items: [QueueItem(song: const Song(id: 's', title: '歌'), albumGain: true)],
      index: 0,
      positionMs: 1500,
      repeat: RepeatMode.all,
    );
    await database.saveQueue(library.id, queue);
    expect((await database.libraries()).single.name, '家里');
    expect(await database.currentLibraryId(), 'lib-a');
    final settings = await database.loadSettings();
    expect(settings.quality, QualityMode.saver);
    expect(settings.replayGain, isFalse);
    final loaded = await database.loadQueue(library.id);
    expect(loaded.items.single.song.title, '歌');
    expect(loaded.positionMs, 1500);
    expect(loaded.repeat, RepeatMode.all);
    await database.deleteLibrary(library.id);
    expect(await database.libraries(), isEmpty);
    expect(await database.currentLibraryId(), isNull);
    await database.close();
    await dir.delete(recursive: true);
  });

  test('fingerprint and clock formatting', () {
    expect(formatFingerprint('ab12cd'), 'AB:12:CD');
    expect(formatClock(const Duration(seconds: 75)), '1:15');
    expect(desktopLayout(1099), isFalse);
    expect(desktopLayout(1100), isTrue);
  });
}

class StreamRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 1;
}

class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
