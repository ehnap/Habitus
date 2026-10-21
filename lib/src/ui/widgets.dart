import 'dart:io';

import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../format.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import '../storage/cover_cache.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.cache,
    required this.libraryId,
    required this.coverArt,
    this.size = 300,
    this.radius = 12,
  });

  final CoverCache cache;
  final String? libraryId;
  final String coverArt;
  final int size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _PlaceholderCover(radius: radius);
    if (libraryId == null || coverArt.isEmpty) return placeholder;
    return FutureBuilder<File?>(
      future: cache.fileFor(libraryId: libraryId!, coverArt: coverArt, size: size),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      },
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: scheme.primary.withValues(alpha: 0.12),
      ),
      child: Icon(Icons.album_outlined, color: scheme.primary, size: 28),
    );
  }
}

class StatusPane extends StatelessWidget {
  const StatusPane({
    super.key,
    required this.loading,
    this.error,
    this.empty = false,
    this.emptyTitle = Zh.nothingHere,
    this.emptyBody = '',
    this.onRetry,
    required this.child,
  });

  final bool loading;
  final Object? error;
  final bool empty;
  final String emptyTitle;
  final String emptyBody;
  final VoidCallback? onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) return const LoadingPane();
    if (error != null) {
      return MessagePane(
        icon: Icons.cloud_off_outlined,
        title: describeError(error!),
        actionLabel: onRetry == null ? null : Zh.retry,
        onAction: onRetry,
      );
    }
    if (empty) {
      return MessagePane(icon: Icons.library_music_outlined, title: emptyTitle, body: emptyBody);
    }
    return child;
  }
}

class LoadingPane extends StatelessWidget {
  const LoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _Skeleton(height: 22, width: 140),
        SizedBox(height: 16),
        _Skeleton(height: 120),
        SizedBox(height: 12),
        _Skeleton(height: 64),
        SizedBox(height: 8),
        _Skeleton(height: 64),
        SizedBox(height: 8),
        _Skeleton(height: 64),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class MessagePane extends StatelessWidget {
  const MessagePane({
    super.key,
    required this.icon,
    required this.title,
    this.body = '',
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, required this.cache, required this.libraryId, required this.onTap});

  final Album album;
  final CoverCache cache;
  final String? libraryId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: CoverArt(cache: cache, libraryId: libraryId, coverArt: album.coverArt, radius: 16),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            album.artistLabel,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SongHeart extends StatelessWidget {
  const SongHeart({
    super.key,
    required this.controller,
    required this.song,
    this.fallback = false,
    this.size = 22,
    this.showTooltip = true,
  });

  final AppController controller;
  final Song song;
  final bool fallback;
  final double size;

  /// Song lists keep the label. The mini bar and player sit on the window edge,
  /// where the same label is clipped, so those callers turn it off.
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final on = controller.isStarred(song, fallback: fallback);
        final color = on ? Theme.of(context).colorScheme.primary : Theme.of(context).iconTheme.color;
        return IconButton(
          tooltip: showTooltip ? (on ? Zh.unstar : Zh.star) : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => controller.toggleSongStar(song, fallback: fallback),
          icon: Icon(on ? Icons.favorite : Icons.favorite_border, size: size, color: color),
        );
      },
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.controller,
    this.number,
    this.active = false,
    this.starred = false,
    this.onMore,
    this.showTooltips = true,
  });

  final Song song;
  final VoidCallback onTap;
  final AppController? controller;
  final int? number;
  final bool active;
  final bool starred;
  final VoidCallback? onMore;

  /// The player queue sits against the window edge, so it turns these off.
  final bool showTooltips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: SizedBox(
        width: 28,
        child: Center(
          child: active
              ? Icon(Icons.graphic_eq, color: scheme.primary, size: 18)
              : Text(
                  number == null || number == 0 ? '·' : '$number',
                  style: TextStyle(color: muted),
                ),
        ),
      ),
      title: Text(
        song.title.isEmpty ? Zh.songs : song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? scheme.primary : null),
      ),
      subtitle: Text(
        song.artistLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller != null)
            SongHeart(
              controller: controller!,
              song: song,
              fallback: starred,
              size: 18,
              showTooltip: showTooltips,
            )
          else if (starred || song.starred)
            Icon(Icons.favorite, size: 16, color: scheme.primary),
          const SizedBox(width: 4),
          Text(formatClock(song.durationValue), style: TextStyle(color: muted, fontSize: 12)),
          if (onMore != null)
            IconButton(
              tooltip: showTooltips ? Zh.more : null,
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class WarningBanner extends StatelessWidget {
  const WarningBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

Future<void> showSongMenu(
  BuildContext context,
  AppController controller,
  Song song, {
  bool starredFallback = false,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(song.title), subtitle: Text(song.artistLabel)),
            ListTile(leading: const Icon(Icons.skip_next_outlined), title: const Text(Zh.playNext), onTap: () => Navigator.pop(context, 'next')),
            ListTile(leading: const Icon(Icons.playlist_add), title: const Text(Zh.addToEnd), onTap: () => Navigator.pop(context, 'end')),
            ListTile(leading: const Icon(Icons.queue_music), title: const Text(Zh.addToPlaylist), onTap: () => Navigator.pop(context, 'playlist')),
            ListTile(
              leading: Icon(
                controller.isStarred(song, fallback: starredFallback) ? Icons.favorite : Icons.favorite_border,
              ),
              title: Text(controller.isStarred(song, fallback: starredFallback) ? Zh.unstar : Zh.star),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            if (song.albumId.isNotEmpty)
              ListTile(leading: const Icon(Icons.album_outlined), title: const Text(Zh.viewAlbum), onTap: () => Navigator.pop(context, 'album')),
            if (song.artistId.isNotEmpty)
              ListTile(leading: const Icon(Icons.person_outline), title: const Text(Zh.viewArtist), onTap: () => Navigator.pop(context, 'artist')),
          ],
        ),
      );
    },
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'next':
      await controller.player.addNext(song);
      await controller.persistQueue();
    case 'end':
      await controller.player.addToEnd(song);
      await controller.persistQueue();
    case 'playlist':
      if (context.mounted) await pickPlaylist(context, controller, [song.id]);
    case 'star':
      await controller.toggleSongStar(song, fallback: starredFallback);
    case 'album':
      if (context.mounted) openAlbum(context, controller, song.albumId);
    case 'artist':
      if (context.mounted) openArtist(context, controller, song.artistId);
  }
}

Future<void> pickPlaylist(BuildContext context, AppController controller, List<String> songIds) async {
  List<Playlist> playlists;
  try {
    playlists = await controller.playlists();
  } catch (error) {
    controller.toast(describeError(error));
    return;
  }
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text(Zh.pickPlaylist)),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text(Zh.newPlaylist),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            for (final playlist in playlists)
              ListTile(
                title: Text(playlist.name),
                subtitle: Text('${playlist.songCount}'),
                onTap: () => Navigator.pop(context, playlist.id),
              ),
          ],
        ),
      );
    },
  );
  if (!context.mounted || choice == null) return;
  try {
    if (choice == 'new') {
      final name = await askText(context, title: Zh.newPlaylist, label: Zh.playlistName);
      if (name == null || name.trim().isEmpty) return;
      await controller.createPlaylist(name.trim(), songIds: songIds);
      controller.toast(Zh.playlistCreated);
      return;
    }
    await controller.addSongsToPlaylist(choice, songIds);
    controller.toast(Zh.addedToPlaylist);
  } catch (error) {
    controller.toast(describeError(error));
  }
}

Future<String?> askText(BuildContext context, {required String title, required String label, String initial = ''}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: field, decoration: InputDecoration(labelText: label), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(Zh.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text(Zh.create)),
        ],
      );
    },
  );
}

void openAlbum(BuildContext context, AppController controller, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AlbumRoute(controller: controller, albumId: id)));
}

void openArtist(BuildContext context, AppController controller, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ArtistRoute(controller: controller, artistId: id)));
}

void openPlaylist(BuildContext context, AppController controller, String id) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PlaylistRoute(controller: controller, playlistId: id)));
}

// Routes are implemented in detail_pages.dart. These typedef-like wrappers
// avoid an import cycle by living next to the navigation helpers. The real
// pages are assigned from detail_pages.dart via the setters below.
Widget Function(AppController controller, String id) buildAlbumPage = (controller, id) => const SizedBox.shrink();
Widget Function(AppController controller, String id) buildArtistPage = (controller, id) => const SizedBox.shrink();
Widget Function(AppController controller, String id) buildPlaylistPage = (controller, id) => const SizedBox.shrink();

class _AlbumRoute extends StatelessWidget {
  const _AlbumRoute({required this.controller, required this.albumId});
  final AppController controller;
  final String albumId;
  @override
  Widget build(BuildContext context) => buildAlbumPage(controller, albumId);
}

class _ArtistRoute extends StatelessWidget {
  const _ArtistRoute({required this.controller, required this.artistId});
  final AppController controller;
  final String artistId;
  @override
  Widget build(BuildContext context) => buildArtistPage(controller, artistId);
}

class _PlaylistRoute extends StatelessWidget {
  const _PlaylistRoute({required this.controller, required this.playlistId});
  final AppController controller;
  final String playlistId;
  @override
  Widget build(BuildContext context) => buildPlaylistPage(controller, playlistId);
}

int gridCount(double width) {
  if (width >= 1400) return 6;
  if (width >= 1100) return 5;
  if (width >= 800) return 4;
  if (width >= 520) return 3;
  return 2;
}
