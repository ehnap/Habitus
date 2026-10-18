import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../format.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import 'widgets.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.controller, required this.albumId});

  final AppController controller;
  final String albumId;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  bool _loading = true;
  Object? _error;
  Album? _album;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _album == null;
      _error = null;
    });
    try {
      final album = await widget.controller.album(widget.albumId);
      if (!mounted) return;
      setState(() {
        _album = album;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _toggleStar() async {
    final album = _album;
    if (album == null) return;
    final next = !album.starred;
    setState(() => _album = album.copyWith(starred: next));
    try {
      await widget.controller.setStar(albumId: album.id, starred: next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _album = album);
      widget.controller.toast(Zh.starFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;
    return Scaffold(
      appBar: AppBar(
        title: Text(album?.name ?? Zh.albums),
        actions: [
          if (album != null)
            IconButton(
              tooltip: album.starred ? Zh.unstar : Zh.star,
              onPressed: _toggleStar,
              icon: Icon(album.starred ? Icons.favorite : Icons.favorite_border),
            ),
        ],
      ),
      body: StatusPane(
        loading: _loading,
        error: album == null ? _error : null,
        empty: album != null && album.songs.isEmpty,
        emptyTitle: Zh.nothingHere,
        onRetry: _load,
        child: album == null
            ? const SizedBox.shrink()
            : _AlbumBody(
                controller: widget.controller,
                album: album,
                onMenu: _load,
              ),
      ),
    );
  }
}

class _AlbumBody extends StatelessWidget {
  const _AlbumBody({required this.controller, required this.album, required this.onMenu});

  final AppController controller;
  final Album album;
  final Future<void> Function() onMenu;

  @override
  Widget build(BuildContext context) {
    final songs = album.songs;
    final discs = songs.map((song) => song.discNumber).toSet();
    final multiDisc = discs.length > 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 148,
              height: 148,
              child: CoverArt(
                cache: controller.covers,
                libraryId: controller.current?.id,
                coverArt: album.coverArt,
                size: 300,
                radius: 16,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  if (album.artistId.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: () => openArtist(context, controller, album.artistId),
                      child: Text(album.artistLabel),
                    )
                  else
                    Text(album.artistLabel),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (album.year > 0) '${album.year}',
                      '${songs.length} ${Zh.songs}',
                      if (album.duration > 0) formatClock(Duration(seconds: album.duration)),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: songs.isEmpty ? null : () => controller.playAlbum(songs, shuffle: false),
              icon: const Icon(Icons.play_arrow),
              label: const Text(Zh.play),
            ),
            OutlinedButton.icon(
              onPressed: songs.isEmpty ? null : () => controller.playAlbum(songs, shuffle: true),
              icon: const Icon(Icons.shuffle),
              label: const Text(Zh.shufflePlay),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < songs.length; i++) ...[
          if (multiDisc && (i == 0 || songs[i].discNumber != songs[i - 1].discNumber))
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text('${Zh.disc} ${songs[i].discNumber}', style: Theme.of(context).textTheme.titleMedium),
            ),
          SongTile(
            song: songs[i],
            number: songs[i].track == 0 ? i + 1 : songs[i].track,
            starred: songs[i].starred,
            active: controller.player.views.view.song?.id == songs[i].id,
            onTap: () => controller.playSongs(songs, i, albumGain: true),
            onMore: () async {
              await showSongMenu(context, controller, songs[i]);
              await onMenu();
            },
          ),
        ],
      ],
    );
  }
}

class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.controller, required this.artistId});

  final AppController controller;
  final String artistId;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  bool _loading = true;
  Object? _error;
  Artist? _artist;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _artist == null;
      _error = null;
    });
    try {
      final artist = await widget.controller.artist(widget.artistId);
      if (!mounted) return;
      setState(() {
        _artist = artist;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _toggleStar() async {
    final artist = _artist;
    if (artist == null) return;
    final next = !artist.starred;
    setState(() => _artist = artist.copyWith(starred: next));
    try {
      await widget.controller.setStar(artistId: artist.id, starred: next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _artist = artist);
      widget.controller.toast(Zh.starFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = _artist;
    return Scaffold(
      appBar: AppBar(
        title: Text(artist?.name ?? Zh.artists),
        actions: [
          if (artist != null)
            IconButton(
              tooltip: artist.starred ? Zh.unstar : Zh.star,
              onPressed: _toggleStar,
              icon: Icon(artist.starred ? Icons.favorite : Icons.favorite_border),
            ),
        ],
      ),
      body: StatusPane(
        loading: _loading,
        error: artist == null ? _error : null,
        empty: artist != null && artist.albums.isEmpty,
        emptyTitle: Zh.nothingHere,
        onRetry: _load,
        child: artist == null
            ? const SizedBox.shrink()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final count = gridCount(constraints.maxWidth);
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: artist.albums.length,
                    itemBuilder: (context, index) {
                      final album = artist.albums[index];
                      return AlbumCard(
                        album: album,
                        cache: widget.controller.covers,
                        libraryId: widget.controller.current?.id,
                        onTap: () => openAlbum(context, widget.controller, album.id),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.controller, required this.playlistId});

  final AppController controller;
  final String playlistId;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool _loading = true;
  Object? _error;
  Playlist? _playlist;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _playlist == null;
      _error = null;
    });
    try {
      final playlist = await widget.controller.playlist(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _playlist = playlist;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _play({required bool shuffle}) async {
    final songs = _playlist?.songs ?? const <Song>[];
    if (songs.isEmpty) return;
    if (shuffle) {
      await widget.controller.playAlbum(songs, shuffle: true);
      return;
    }
    await widget.controller.player.playItems([for (final song in songs) QueueItem(song: song)]);
    await widget.controller.persistQueue();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Zh.deletePlaylist),
        content: const Text(Zh.deletePlaylistBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(Zh.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text(Zh.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.controller.removePlaylist(widget.playlistId);
      widget.controller.toast(Zh.playlistDeleted);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      widget.controller.toast(describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    final songs = playlist?.songs ?? const <Song>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? Zh.playlists),
        actions: [
          IconButton(tooltip: Zh.deletePlaylist, onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: StatusPane(
        loading: _loading,
        error: playlist == null ? _error : null,
        empty: playlist != null && songs.isEmpty,
        emptyTitle: Zh.emptyPlaylist,
        onRetry: _load,
        child: playlist == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CoverArt(
                          cache: widget.controller.covers,
                          libraryId: widget.controller.current?.id,
                          coverArt: playlist.coverArt,
                          radius: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${songs.length} ${Zh.songs}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _play(shuffle: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(Zh.play),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _play(shuffle: true),
                        icon: const Icon(Icons.shuffle),
                        label: const Text(Zh.shufflePlay),
                      ),
                    ],
                  ),
                  for (var i = 0; i < songs.length; i++)
                    SongTile(
                      song: songs[i],
                      number: i + 1,
                      starred: songs[i].starred,
                      active: widget.controller.player.views.view.song?.id == songs[i].id,
                      onTap: () => widget.controller.playSongs(songs, i, albumGain: false),
                      onMore: () async {
                        await showSongMenu(context, widget.controller, songs[i]);
                        await _load();
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

void registerDetailPages() {
  buildAlbumPage = (controller, id) => AlbumPage(controller: controller, albumId: id);
  buildArtistPage = (controller, id) => ArtistPage(controller: controller, artistId: id);
  buildPlaylistPage = (controller, id) => PlaylistPage(controller: controller, playlistId: id);
}
