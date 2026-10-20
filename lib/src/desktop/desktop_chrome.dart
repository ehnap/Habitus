import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../copy/zh.dart';
import '../playback/lyrics.dart';
import '../state/app_controller.dart';
import 'desktop_args.dart';

/// Main-window mini mode and the desktop lyrics window.
///
/// [windowManager.destroy] posts a quit to the process, so this class only
/// calls [windowManager.close] on the lyrics window.
class DesktopChrome extends ChangeNotifier {
  DesktopChrome(this.controller);

  final AppController controller;

  static const miniSize = Size(560, 76);

  bool mini = false;
  bool lyricsOpen = false;

  final WindowMethodChannel _channel = const WindowMethodChannel(
    desktopLyricsChannel,
    mode: ChannelMode.bidirectional,
  );

  Rect? _restore;
  bool _busy = false;
  bool _pushing = false;
  bool _pushAgain = false;
  String? _linesKey;

  Future<void> start() async {
    await _channel.setMethodCallHandler(_onChild);
    controller.player.views.addListener(_onPlayback);
    onWindowsChanged.listen((_) {
      _syncLyricsWindow();
    });
  }

  Future<void> _syncLyricsWindow() async {
    if (!lyricsOpen) return;
    try {
      final windows = await WindowController.getAll();
      final alive = windows.any((window) => window.arguments == desktopLyricsArgument);
      if (!alive && lyricsOpen) {
        lyricsOpen = false;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<dynamic> _onChild(MethodCall call) async {
    if (call.method == 'ready') {
      _linesKey = null;
      await _pushLines();
    } else if (call.method == 'closed') {
      if (lyricsOpen) {
        lyricsOpen = false;
        notifyListeners();
      }
    }
    return null;
  }

  void _onPlayback() {
    if (!lyricsOpen) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    _pushLines().whenComplete(() {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        _onPlayback();
      }
    });
  }

  Future<void> _pushLines() async {
    if (!lyricsOpen) return;
    final view = controller.player.views.view;
    final song = view.song;
    LyricWindowLines lines;
    if (song == null) {
      lines = const LyricWindowLines(current: '', next: '');
    } else {
      try {
        final track = await controller.lyrics(song);
        if (!lyricsOpen) return;
        final latest = controller.player.views.view;
        if (latest.song?.id != song.id) return;
        lines = lyricWindowLines(track, latest.position);
      } catch (_) {
        lines = const LyricWindowLines(current: '', next: '');
      }
    }
    final key = '${song?.id ?? ''}|${lines.current}|${lines.next}';
    if (key == _linesKey) return;
    try {
      await _channel.invokeMethod<void>('lines', {
        'current': lines.current,
        'next': lines.next,
      });
      _linesKey = key;
    } catch (_) {}
  }

  Future<void> toggleLyrics() async {
    if (_busy) return;
    _busy = true;
    try {
      if (lyricsOpen) {
        lyricsOpen = false;
        notifyListeners();
        try {
          await _channel.invokeMethod<void>('close');
        } catch (_) {}
        return;
      }
      await WindowController.create(
        const WindowConfiguration(hiddenAtLaunch: true, arguments: desktopLyricsArgument),
      );
      lyricsOpen = true;
      _linesKey = null;
      notifyListeners();
    } catch (_) {
      lyricsOpen = false;
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> enterMini() async {
    if (mini || _busy) return;
    _busy = true;
    try {
      final bounds = await windowManager.getBounds();
      _restore = bounds;
      mini = true;
      notifyListeners();
      await windowManager.setFullScreen(false);
      await windowManager.setMinimumSize(const Size(420, 68));
      await windowManager.setMaximumSize(const Size(680, 92));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAsFrameless();
      await windowManager.setBounds(Rect.fromLTWH(bounds.left, bounds.top, miniSize.width, miniSize.height));
    } catch (_) {
      if (mini) {
        try {
          await _restoreMainFrame();
        } catch (_) {}
        mini = false;
        _restore = null;
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> exitMini() async {
    if (!mini || _busy) return;
    _busy = true;
    try {
      await _restoreMainFrame();
      mini = false;
      _restore = null;
      notifyListeners();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> _restoreMainFrame() async {
    final restore = _restore;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMaximumSize(const Size(16384, 16384));
    await windowManager.setMinimumSize(const Size(640, 480));
    await windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);
    if (restore != null) {
      await windowManager.setBounds(restore);
    }
  }

  static DesktopChrome? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_DesktopChromeData>()?.chrome;
  }
}

class DesktopChromeScope extends StatelessWidget {
  const DesktopChromeScope({super.key, required this.chrome, required this.child});

  final DesktopChrome chrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chrome,
      builder: (context, _) => _DesktopChromeData(chrome: chrome, child: child),
    );
  }
}

class _DesktopChromeData extends InheritedWidget {
  const _DesktopChromeData({required this.chrome, required super.child});

  final DesktopChrome chrome;

  @override
  bool updateShouldNotify(_DesktopChromeData oldWidget) => true;
}

class DesktopWindowButtons extends StatelessWidget {
  const DesktopWindowButtons({super.key, required this.chrome});

  final DesktopChrome chrome;

  @override
  Widget build(BuildContext context) {
    final tint = chrome.lyricsOpen ? Theme.of(context).colorScheme.primary : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: chrome.lyricsOpen ? Zh.desktopLyricsOff : Zh.desktopLyrics,
          onPressed: chrome.toggleLyrics,
          icon: Icon(Icons.subtitles_outlined, color: tint),
        ),
        IconButton(
          tooltip: Zh.miniMode,
          onPressed: chrome.enterMini,
          icon: const Icon(Icons.picture_in_picture_alt_outlined),
        ),
      ],
    );
  }
}
