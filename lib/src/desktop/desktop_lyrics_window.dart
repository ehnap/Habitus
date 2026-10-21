import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../copy/zh.dart';
import '../theme/habitus_theme.dart';
import 'desktop_args.dart';
import 'desktop_drag.dart';

const _lyricShadows = <Shadow>[
  Shadow(color: Color(0xE6000000), blurRadius: 8, offset: Offset(0, 1)),
  Shadow(color: Color(0xFF000000), offset: Offset(1, 0)),
  Shadow(color: Color(0xFF000000), offset: Offset(-1, 0)),
  Shadow(color: Color(0xFF000000), offset: Offset(0, 1)),
  Shadow(color: Color(0xFF000000), offset: Offset(0, -1)),
  Shadow(color: Color(0xFF000000), offset: Offset(1, 1)),
  Shadow(color: Color(0xFF000000), offset: Offset(-1, -1)),
  Shadow(color: Color(0xFF000000), offset: Offset(1, -1)),
  Shadow(color: Color(0xFF000000), offset: Offset(-1, 1)),
];

/// Small always-on-top lyrics window. Hiding it leaves the main window running.
Future<void> runDesktopLyricsWindow() async {
  await windowManager.ensureInitialized();
  // backgroundColor has to be passed here. A bare waitUntilReadyToShow leaves
  // the Windows view on the default opaque white surface.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    ),
  );
  const channel = WindowMethodChannel(desktopLyricsChannel, mode: ChannelMode.bidirectional);
  final bridge = _LyricBridge();
  await channel.setMethodCallHandler((call) async {
    if (call.method == 'lines') {
      final args = call.arguments;
      final map = args is Map ? args : const <Object?, Object?>{};
      bridge.show(map['current']?.toString() ?? '', map['next']?.toString() ?? '');
    } else if (call.method == 'close') {
      await _hideLyricsWindow(channel);
    } else if (call.method == 'show') {
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
    }
    return null;
  });
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
  }
  // Swallow the native close so the engine is never destroyed. On Windows that
  // destruction quits the process.
  await windowManager.setPreventClose(true);
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setAsFrameless();
  if (Platform.isMacOS) {
    // setAsFrameless marks the window opaque. Hidden title-bar style clears that.
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  }
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(const Size(320, 96));
  await windowManager.setMaximumSize(const Size(720, 160));
  await windowManager.setBounds(const Rect.fromLTWH(120, 96, 560, 112));
  await windowManager.setAlwaysOnTop(true);
  // The window exists now. Set the color again so later frame changes do not
  // leave the default white client area in place. This includes Windows.
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setTitle(Zh.appName);
  await windowManager.show();
  runApp(_DesktopLyricsApp(channel: channel, bridge: bridge));
}

class _LyricBridge {
  void Function(String current, String next)? onLines;

  void show(String current, String next) => onLines?.call(current, next);
}

Future<void> _hideLyricsWindow(WindowMethodChannel channel) async {
  try {
    await channel.invokeMethod<void>('closed');
  } catch (_) {}
  try {
    await windowManager.hide();
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
      theme: habitusDark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        cardColor: Colors.transparent,
      ),
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
    _hide();
  }

  Future<void> _hide() async {
    if (_closing) return;
    _closing = true;
    try {
      await _hideLyricsWindow(widget.channel);
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = HabitusColors.nightInk;
    final current = _current.trim();
    final next = _next.trim();
    final waiting = !_known;
    final missing = _known && current.isEmpty && next.isEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _LyricsClearPainter()),
          Row(
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
                            color: missing || waiting ? ink.withValues(alpha: 0.72) : ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            shadows: _lyricShadows,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          next,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.2,
                            shadows: _lyricShadows,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _hide,
                icon: Icon(Icons.close, color: ink, shadows: _lyricShadows),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Writes ARGB 0 over the whole lyrics view. A transparent scaffold does not
/// replace an opaque white surface; source blend does.
class _LyricsClearPainter extends CustomPainter {
  const _LyricsClearPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.src
        ..color = const Color(0x00000000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
