import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../copy/zh.dart';
import '../theme/habitus_theme.dart';
import 'desktop_args.dart';
import 'desktop_drag.dart';

/// Small always-on-top lyrics window. Closing it closes only this window.
Future<void> runDesktopLyricsWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow();
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
  }
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setAsFrameless();
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(const Size(320, 96));
  await windowManager.setMaximumSize(const Size(720, 160));
  await windowManager.setBounds(const Rect.fromLTWH(120, 96, 560, 112));
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setTitle(Zh.appName);
  const channel = WindowMethodChannel(desktopLyricsChannel, mode: ChannelMode.bidirectional);
  final bridge = _LyricBridge();
  await channel.setMethodCallHandler((call) async {
    if (call.method == 'lines') {
      final args = call.arguments;
      final map = args is Map ? args : const <Object?, Object?>{};
      bridge.show(map['current']?.toString() ?? '', map['next']?.toString() ?? '');
    } else if (call.method == 'close') {
      await _closeLyricsWindow(channel);
    }
    return null;
  });
  await windowManager.show();
  runApp(_DesktopLyricsApp(channel: channel, bridge: bridge));
}

class _LyricBridge {
  void Function(String current, String next)? onLines;

  void show(String current, String next) => onLines?.call(current, next);
}

Future<void> _closeLyricsWindow(WindowMethodChannel channel) async {
  try {
    await channel.invokeMethod('closed');
  } catch (_) {}
  try {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  } catch (_) {}
}

class _DesktopLyricsApp extends StatelessWidget {
  const _DesktopLyricsApp({required this.channel, required this.bridge});

  final WindowMethodChannel channel;
  final _LyricBridge bridge;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Zh.appName,
      debugShowCheckedModeBanner: false,
      theme: habitusDark(),
      home: _DesktopLyricsPage(channel: channel, bridge: bridge),
    );
  }
}

class _DesktopLyricsPage extends StatefulWidget {
  const _DesktopLyricsPage({required this.channel, required this.bridge});

  final WindowMethodChannel channel;
  final _LyricBridge bridge;

  @override
  State<_DesktopLyricsPage> createState() => _DesktopLyricsPageState();
}

class _DesktopLyricsPageState extends State<_DesktopLyricsPage> with WindowListener {
  String _current = '';
  String _next = '';
  bool _known = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.bridge.onLines = (current, next) {
      if (!mounted) return;
      setState(() {
        _current = current;
        _next = next;
        _known = true;
      });
    };
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    widget.channel.invokeMethod<void>('ready');
  }

  @override
  void dispose() {
    widget.bridge.onLines = null;
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    _close();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _closeLyricsWindow(widget.channel);
  }

  @override
  Widget build(BuildContext context) {
    final ink = HabitusColors.nightInk;
    final current = _current.trim();
    final next = _next.trim();
    final waiting = !_known;
    final missing = _known && current.isEmpty && next.isEmpty;
    return Scaffold(
      backgroundColor: HabitusColors.night,
      body: Row(
        children: [
          Expanded(
            child: DesktopDragArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waiting
                          ? Zh.lyricsLoading
                          : missing
                          ? Zh.noLyrics
                          : (current.isEmpty ? '…' : current),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: missing || waiting ? ink.withValues(alpha: 0.55) : ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      next,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.withValues(alpha: 0.42), fontSize: 13, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: Zh.close,
            onPressed: _close,
            icon: Icon(Icons.close, color: ink.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
