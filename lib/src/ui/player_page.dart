import 'package:flutter/material.dart' hide RepeatMode;

import '../copy/zh.dart';
import '../failure.dart';
import '../format.dart';
import '../model/models.dart';
import '../playback/lyrics.dart';
import '../state/app_controller.dart';
import 'widgets.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _epoch;
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _epoch = widget.controller.libraryEpoch;
    widget.controller.addListener(_onLibrary);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (!mounted || widget.controller.libraryEpoch == _epoch) return;
    _epoch = widget.controller.libraryEpoch;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text(Zh.appName),
        actions: [
          IconButton(
            tooltip: Zh.queue,
            onPressed: () => _openQueue(context),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller.player.views,
        builder: (context, _) {
          final view = controller.player.views.view;
          final song = view.song;
          if (song == null) {
            return const MessagePane(icon: Icons.queue_music, title: Zh.noQueue);
          }
          final durationMs = view.duration.inMilliseconds <= 0 ? 1 : view.duration.inMilliseconds;
          final positionMs = (_dragMs ?? view.position.inMilliseconds.toDouble()).clamp(0, durationMs.toDouble());
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Expanded(
                    child: PageView(
                      children: [
                        _CoverPage(controller: controller, song: song, route: view.routeLabel),
                        _LyricPage(controller: controller, song: song, position: view.position),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      children: [
                        Slider(
                          value: positionMs.toDouble(),
                          max: durationMs.toDouble(),
                          onChanged: (value) => setState(() => _dragMs = value),
                          onChangeEnd: (value) {
                            setState(() => _dragMs = null);
                            controller.player.seek(Duration(milliseconds: value.round()));
                          },
                        ),
                        Row(
                          children: [
                            Text(formatClock(Duration(milliseconds: positionMs.round()))),
                            const Spacer(),
                            Text(formatClock(view.duration)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              tooltip: view.shuffle ? Zh.shuffleOn : Zh.shuffleOff,
                              onPressed: () => controller.player.setShuffleEnabled(!view.shuffle),
                              icon: Icon(Icons.shuffle, color: view.shuffle ? Theme.of(context).colorScheme.primary : null),
                            ),
                            IconButton(
                              tooltip: Zh.previous,
                              onPressed: controller.player.skipToPrevious,
                              icon: const Icon(Icons.skip_previous, size: 36),
                            ),
                            IconButton(
                              tooltip: view.playing ? Zh.pause : Zh.play,
                              onPressed: view.playing ? controller.player.pause : controller.player.play,
                              icon: Icon(
                                view.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                size: 64,
                              ),
                            ),
                            IconButton(
                              tooltip: Zh.next,
                              onPressed: controller.player.skipToNext,
                              icon: const Icon(Icons.skip_next, size: 36),
                            ),
                            IconButton(
                              tooltip: _repeatLabel(view.repeat),
                              onPressed: () => controller.player.setRepeat(_nextRepeat(view.repeat)),
                              icon: Icon(
                                view.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                                color: view.repeat == RepeatMode.off ? null : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scroll) {
            return ListenableBuilder(
              listenable: widget.controller.player.views,
              builder: (context, _) {
                final view = widget.controller.player.views.view;
                if (view.items.isEmpty) {
                  return const MessagePane(icon: Icons.queue_music, title: Zh.noQueue);
                }
                return ListView.builder(
                  controller: scroll,
                  itemCount: view.items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return const ListTile(title: Text(Zh.queue));
                    final itemIndex = index - 1;
                    final song = view.items[itemIndex].song;
                    return SongTile(
                      song: song,
                      number: itemIndex + 1,
                      active: itemIndex == view.index,
                      starred: song.starred,
                      onTap: () {
                        Navigator.pop(context);
                        widget.controller.player.skipToQueueItem(itemIndex);
                      },
                      onMore: () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.skip_next_outlined),
                                  title: const Text(Zh.moveNext),
                                  onTap: () => Navigator.pop(context, 'next'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.remove_circle_outline),
                                  title: const Text(Zh.remove),
                                  onTap: () => Navigator.pop(context, 'remove'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (action == 'next') {
                          await widget.controller.player.moveToNext(itemIndex);
                        } else if (action == 'remove') {
                          await widget.controller.player.removeAt(itemIndex);
                        }
                        await widget.controller.persistQueue();
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CoverPage extends StatelessWidget {
  const _CoverPage({required this.controller, required this.song, required this.route});

  final AppController controller;
  final Song song;
  final String route;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: CoverArt(
                cache: controller.covers,
                libraryId: controller.current?.id,
                coverArt: song.coverArt,
                size: 600,
                radius: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(song.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(song.artistLabel, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          if (song.album.isNotEmpty)
            Text(song.album, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          if (route.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(route, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class _LyricPage extends StatefulWidget {
  const _LyricPage({required this.controller, required this.song, required this.position});

  final AppController controller;
  final Song song;
  final Duration position;

  @override
  State<_LyricPage> createState() => _LyricPageState();
}

class _LyricPageState extends State<_LyricPage> {
  late Future<LyricTrack?> _future;
  final ScrollController _scroll = ScrollController();
  int _active = -2;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _LyricPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _active = -2;
      _future = _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<LyricTrack?> _load() => widget.controller.lyrics(widget.song);

  void _follow(int index) {
    if (index == _active || !_scroll.hasClients) return;
    _active = index;
    final target = (index * 48.0 - 96).clamp(0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target.toDouble(), duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<LyricTrack?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const MessagePane(icon: Icons.lyrics_outlined, title: Zh.lyricsLoading);
              }
              if (snapshot.hasError) {
                return MessagePane(
                  icon: Icons.lyrics_outlined,
                  title: describeError(snapshot.error!),
                  body: Zh.lyricsFailed,
                  actionLabel: Zh.retry,
                  onAction: () => setState(() => _future = _load()),
                );
              }
              final track = snapshot.data;
              if (track == null || track.isEmpty) {
                return const MessagePane(icon: Icons.lyrics_outlined, title: Zh.noLyrics);
              }
              final active = activeLyricIndex(track, widget.position);
              WidgetsBinding.instance.addPostFrameCallback((_) => _follow(active));
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                itemCount: track.lines.length,
                itemBuilder: (context, index) {
                  final line = track.lines[index];
                  final on = index == active;
                  final start = lineStart(line, track.offset);
                  return InkWell(
                    onTap: start == null
                        ? null
                        : () => widget.controller.player.seek(start < Duration.zero ? Duration.zero : start),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        line.text.isEmpty ? '…' : line.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: on ? 18 : 15,
                          height: 1.35,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          color: on
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

String _repeatLabel(RepeatMode mode) {
  switch (mode) {
    case RepeatMode.off:
      return Zh.repeatOff;
    case RepeatMode.all:
      return Zh.repeatAll;
    case RepeatMode.one:
      return Zh.repeatOne;
  }
}

RepeatMode _nextRepeat(RepeatMode mode) {
  switch (mode) {
    case RepeatMode.off:
      return RepeatMode.all;
    case RepeatMode.all:
      return RepeatMode.one;
    case RepeatMode.one:
      return RepeatMode.off;
  }
}
