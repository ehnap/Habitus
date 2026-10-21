import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/desktop/desktop_args.dart';
import 'src/desktop/desktop_chrome.dart';
import 'src/desktop/desktop_lyrics_window.dart';
import 'src/playback/audio_proxy.dart';
import 'src/playback/habitus_player.dart';
import 'src/state/app_controller.dart';
import 'src/storage/app_database.dart';
import 'src/storage/audio_cache.dart';
import 'src/storage/cover_cache.dart';
import 'src/storage/secure_store.dart';
import 'src/subsonic/client.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // macOS and Linux start a Flutter lyrics engine. Windows never does: the
  // runner paints those lines in a native layered window.
  if (isDesktopLyricsLaunch(args)) {
    await runDesktopLyricsWindow();
    return;
  }
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final support = await getApplicationSupportDirectory();
  final database = AppDatabase();
  await database.open(p.join(support.path, 'habitus.db'));
  final client = SubsonicClient();
  final covers = CoverCache(Directory(p.join(support.path, 'covers')), client);
  final audioCache = AudioCache(Directory(p.join(support.path, 'audio')));
  await audioCache.load();
  final proxy = LocalAudioProxy(client, audioCache);
  await proxy.start();

  HabitusAudioHandler? created;
  late final HabitusAudioHandler player;
  HabitusAudioHandler buildPlayer() {
    return created ??= HabitusAudioHandler(
      client: client,
      cache: audioCache,
      covers: covers,
      proxy: proxy,
    );
  }

  try {
    player = await AudioService.init(
      builder: buildPlayer,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'app.habitus.playback',
        androidNotificationChannelName: 'Habitus',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    );
  } on MissingPluginException {
    player = buildPlayer();
  } on PlatformException {
    player = buildPlayer();
  } catch (_) {
    player = buildPlayer();
  }

  final controller = AppController(
    database: database,
    credentials: SecureCredentialStore(),
    client: client,
    player: player,
    covers: covers,
    audioCache: audioCache,
  );
  try {
    await controller.boot();
  } catch (error) {
    runApp(HabitusBootFailure(error: error));
    return;
  }
  DesktopChrome? desktop;
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      final chrome = DesktopChrome(controller);
      await chrome.start();
      desktop = chrome;
    } catch (_) {
      desktop = null;
    }
  }
  runApp(HabitusApp(controller: controller, desktop: desktop));
}
