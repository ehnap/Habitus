import 'dart:async';

import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../failure.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import '../subsonic/client.dart';
import 'widgets.dart';

class LibraryHubPage extends StatelessWidget {
  const LibraryHubPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = [
      (Icons.album_outlined, Zh.albums, () => _push(context, AlbumIndexPage(controller: controller))),
      (Icons.people_outline, Zh.artists, () => _push(context, ArtistIndexPage(controller: controller))),
      (Icons.music_note_outlined, Zh.songs, () => _push(context, SongsPage(controller: controller))),
      (Icons.queue_music, Zh.playlists, () => _push(context, PlaylistIndexPage(controller: controller))),
      (Icons.favorite_border, Zh.favorites, () => _push(context, FavoritesPage(controller: controller))),
      (Icons.piano_outlined, Zh.genres, () => _push(context, GenreIndexPage(controller: controller))),
      (Icons.folder_outlined, Zh.folders, () => _push(context, FolderIndexPage(controller: controller))),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          child: ListTile(
            leading: Icon(entry.$1),
            title: Text(entry.$2),
            trailing: const Icon(Icons.chevron_right),
            onTap: entry.$3,
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class AlbumIndexPage extends StatefulWidget {
  const AlbumIndexPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AlbumIndexPage> createState() => _AlbumIndexPageState();
}

class _AlbumIndexPageState extends State<AlbumIndexPage> {
  final _albums = <Album>[];
  bool _loading = true;
  bool _more = false;
  Object? _error;
  int _epoch = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _load(reset: true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (widget.controller.libraryEpoch != _epoch) _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _more = true);
    }
    try {
      final page = await widget.controller.albums(
        type: 'alphabeticalByName',
        size: 40,
        offset: reset ? 0 : _albums.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _albums
            ..clear()
            ..addAll(page);
        } else {
          _albums.addAll(page);
        }
        _loading = false;
        _more = false;
        _error = null;
        _epoch = widget.controller.libraryEpoch;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _more = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Zh.albums)),
      body: StatusPane(
        loading: _loading,
        error: _albums.isEmpty ? _error : null,
        empty: _albums.isEmpty,
        emptyTitle: Zh.emptyCatalogTitle,
        emptyBody: Zh.emptyCatalogBody,
        onRetry: () => _load(reset: true),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = gridCount(constraints.maxWidth);
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 240 && !_more && !_loading) {
                  _load(reset: false);
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.72,
                ),
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  return AlbumCard(
                    album: album,
                    cache: widget.controller.covers,
                    libraryId: widget.controller.current?.id,
                    onTap: () => openAlbum(context, widget.controller, album.id),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class ArtistIndexPage extends StatefulWidget {
  const ArtistIndexPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ArtistIndexPage> createState() => _ArtistIndexPageState();
}

class _ArtistIndexPageState extends State<ArtistIndexPage> {
  List<ArtistIndex> _indexes = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final indexes = await widget.controller.artists();
      if (!mounted) return;
      setState(() {
        _indexes = indexes;
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

  @override
  Widget build(BuildContext context) {
    final empty = _indexes.every((index) => index.artists.isEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text(Zh.artists)),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: empty,
        emptyTitle: Zh.emptyCatalogTitle,
        emptyBody: Zh.emptyCatalogBody,
        onRetry: _load,
        child: ListView(
          children: [
            for (final index in _indexes) ...[
              if (index.artists.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(index.name, style: Theme.of(context).textTheme.titleMedium),
                ),
              for (final artist in index.artists)
                ListTile(
                  leading: SizedBox(
                    width: 44,
                    height: 44,
                    child: CoverArt(
                      cache: widget.controller.covers,
                      libraryId: widget.controller.current?.id,
                      coverArt: artist.coverArt,
                      size: 128,
                      radius: 22,
                    ),
                  ),
                  title: Text(artist.name),
                  subtitle: Text('${artist.albumCount}'),
                  onTap: () => openArtist(context, widget.controller, artist.id),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class SongsPage extends StatefulWidget {
  const SongsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  final _songs = <Song>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  bool _failedReset = false;
  int _epoch = -1;
  String? _folder;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _epoch = widget.controller.libraryEpoch;
    _folder = widget.controller.folderId;
    widget.controller.addListener(_onController);
    _load(reset: true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    final folder = widget.controller.folderId;
    if (widget.controller.libraryEpoch == _epoch && folder == _folder) return;
    _epoch = widget.controller.libraryEpoch;
    _folder = folder;
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    final token = ++_request;
    final offset = reset ? 0 : _songs.length;
    setState(() {
      _error = null;
      _failedReset = false;
      if (reset) {
        _loading = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await widget.controller.librarySongs(offset: offset);
      if (!mounted || token != _request) return;
      setState(() {
        if (reset) {
          _songs
            ..clear()
            ..addAll(page);
        } else {
          _songs.addAll(page);
        }
        _hasMore = page.length >= librarySongPageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _epoch = widget.controller.libraryEpoch;
        _folder = widget.controller.folderId;
      });
    } catch (error) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error;
        _failedReset = reset;
      });
    }
  }

  bool _nearEnd(ScrollNotification notification) {
    return notification.metrics.pixels > notification.metrics.maxScrollExtent - 240;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(Zh.songs),
        actions: [
          TextButton(
            onPressed: () => widget.controller.playRandomBatch(),
            child: const Text(Zh.randomBatch),
          ),
        ],
      ),
      body: StatusPane(
        loading: _loading && _songs.isEmpty,
        error: _songs.isEmpty ? _error : null,
        empty: !_loading && _error == null && _songs.isEmpty,
        emptyTitle: Zh.emptyCatalogTitle,
        emptyBody: Zh.emptyCatalogBody,
        onRetry: () => _load(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (_error == null && _nearEnd(notification)) _load(reset: false);
            return false;
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: _songs.length + (_loadingMore || (_error != null && _songs.isNotEmpty) ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _songs.length) {
                if (_error != null) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: TextButton(onPressed: () => _load(reset: _failedReset), child: const Text(Zh.retry)),
                    ),
                  );
                }
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final song = _songs[index];
              return SongTile(
                song: song,
                onTap: () => widget.controller.playSongs(_songs, index, albumGain: false),
                onMore: () => showSongMenu(context, widget.controller, song),
              );
            },
          ),
        ),
      ),
    );
  }
}

class PlaylistIndexPage extends StatefulWidget {
  const PlaylistIndexPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PlaylistIndexPage> createState() => _PlaylistIndexPageState();
}

class _PlaylistIndexPageState extends State<PlaylistIndexPage> {
  List<Playlist> _playlists = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final playlists = await widget.controller.playlists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
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

  Future<void> _create() async {
    final name = await askText(context, title: Zh.newPlaylist, label: Zh.playlistName);
    if (name == null || name.trim().isEmpty) return;
    try {
      await widget.controller.createPlaylist(name.trim());
      widget.controller.toast(Zh.playlistCreated);
      await _load();
    } catch (error) {
      widget.controller.toast(describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Zh.playlists)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text(Zh.newPlaylist),
      ),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: _playlists.isEmpty,
        emptyTitle: Zh.noPlaylists,
        onRetry: _load,
        child: ListView.builder(
          itemCount: _playlists.length,
          itemBuilder: (context, index) {
            final playlist = _playlists[index];
            return ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: CoverArt(
                  cache: widget.controller.covers,
                  libraryId: widget.controller.current?.id,
                  coverArt: playlist.coverArt,
                  radius: 8,
                ),
              ),
              title: Text(playlist.name),
              subtitle: Text('${playlist.songCount}'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => buildPlaylistPage(widget.controller, playlist.id),
                  ),
                );
                _load();
              },
            );
          },
        ),
      ),
    );
  }
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  StarredCollection _starred = const StarredCollection();
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final starred = await widget.controller.starred();
      if (!mounted) return;
      setState(() {
        _starred = starred;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(Zh.favorites),
        actions: [IconButton(tooltip: Zh.refresh, onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: _starred.isEmpty,
        emptyTitle: Zh.noFavorites,
        onRetry: _load,
        child: ListView(
          children: [
            if (_starred.artists.isNotEmpty) const SectionTitle(Zh.artists),
            for (final artist in _starred.artists)
              ListTile(title: Text(artist.name), onTap: () => openArtist(context, widget.controller, artist.id)),
            if (_starred.albums.isNotEmpty) const SectionTitle(Zh.albums),
            for (final album in _starred.albums)
              ListTile(
                title: Text(album.name),
                subtitle: Text(album.artistLabel),
                onTap: () => openAlbum(context, widget.controller, album.id),
              ),
            if (_starred.songs.isNotEmpty) const SectionTitle(Zh.songs),
            for (var i = 0; i < _starred.songs.length; i++)
              SongTile(
                song: _starred.songs[i],
                starred: true,
                onTap: () => widget.controller.playSongs(_starred.songs, i, albumGain: false),
                onMore: () => showSongMenu(context, widget.controller, _starred.songs[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class GenreIndexPage extends StatefulWidget {
  const GenreIndexPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GenreIndexPage> createState() => _GenreIndexPageState();
}

class _GenreIndexPageState extends State<GenreIndexPage> {
  List<Genre> _genres = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final genres = await widget.controller.genres();
      if (!mounted) return;
      setState(() {
        _genres = genres;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(Zh.genres)),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: _genres.isEmpty,
        emptyTitle: Zh.noGenres,
        onRetry: _load,
        child: ListView.builder(
          itemCount: _genres.length,
          itemBuilder: (context, index) {
            final genre = _genres[index];
            return ListTile(
              title: Text(genre.name),
              subtitle: Text('${genre.songCount}'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenreSongsPage(controller: widget.controller, genre: genre.name),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class GenreSongsPage extends StatefulWidget {
  const GenreSongsPage({super.key, required this.controller, required this.genre});

  final AppController controller;
  final String genre;

  @override
  State<GenreSongsPage> createState() => _GenreSongsPageState();
}

class _GenreSongsPageState extends State<GenreSongsPage> {
  final _songs = <Song>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await widget.controller.songsByGenre(widget.genre);
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(songs);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.genre)),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: _songs.isEmpty,
        emptyTitle: Zh.nothingHere,
        onRetry: _load,
        child: ListView.builder(
          itemCount: _songs.length,
          itemBuilder: (context, index) => SongTile(
            song: _songs[index],
            onTap: () => widget.controller.playSongs(_songs, index, albumGain: false),
            onMore: () => showSongMenu(context, widget.controller, _songs[index]),
          ),
        ),
      ),
    );
  }
}

class FolderIndexPage extends StatefulWidget {
  const FolderIndexPage({super.key, required this.controller, this.parentId, this.title = Zh.folders});

  final AppController controller;
  final String? parentId;
  final String title;

  @override
  State<FolderIndexPage> createState() => _FolderIndexPageState();
}

class _FolderIndexPageState extends State<FolderIndexPage> {
  List<ArtistIndex> _indexes = const [];
  List<FolderEntry> _entries = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.parentId == null) {
        _indexes = await widget.controller.folderIndexes();
      } else {
        _entries = await widget.controller.folder(widget.parentId!);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = [for (final entry in _entries) if (entry.song != null) entry.song!];
    final empty = widget.parentId == null
        ? _indexes.every((index) => index.artists.isEmpty)
        : _entries.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StatusPane(
        loading: _loading,
        error: _error,
        empty: empty,
        emptyTitle: Zh.noFolders,
        onRetry: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (widget.parentId == null)
              const Padding(padding: EdgeInsets.all(16), child: WarningBanner(text: Zh.folderNotice)),
            if (widget.parentId == null)
              for (final index in _indexes)
                for (final artist in index.artists)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(artist.name),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FolderIndexPage(
                            controller: widget.controller,
                            parentId: artist.id,
                            title: artist.name,
                          ),
                        ),
                      );
                    },
                  ),
            for (final entry in _entries)
              if (entry.isDir)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(entry.name),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FolderIndexPage(
                          controller: widget.controller,
                          parentId: entry.id,
                          title: entry.name,
                        ),
                      ),
                    );
                  },
                )
              else if (entry.song != null)
                SongTile(
                  song: entry.song!,
                  onTap: () {
                    final index = songs.indexWhere((song) => song.id == entry.song!.id);
                    widget.controller.playSongs(songs, index < 0 ? 0 : index, albumGain: false);
                  },
                  onMore: () => showSongMenu(context, widget.controller, entry.song!),
                ),
          ],
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Timer? _timer;
  SearchPageResult? _result;
  bool _loading = false;
  Object? _error;
  int _request = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _result = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    _timer = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String value) async {
    final token = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.search(value);
      if (!mounted || token != _request) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final result = _result;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: Zh.searchHint),
            onChanged: _schedule,
          ),
        ),
        Expanded(
          child: query.isEmpty
              ? const MessagePane(icon: Icons.search, title: Zh.searchEmpty)
              : StatusPane(
                  loading: _loading && result == null,
                  error: result == null ? _error : null,
                  empty: result != null && result.isEmpty,
                  emptyTitle: Zh.searchNoMatch,
                  onRetry: () => _search(query),
                  child: result == null
                      ? const SizedBox.shrink()
                      : ListView(
                          children: [
                            if (result.artists.isNotEmpty) const SectionTitle(Zh.artists),
                            for (final artist in result.artists)
                              ListTile(
                                title: Text(artist.name),
                                onTap: () => openArtist(context, widget.controller, artist.id),
                              ),
                            if (result.albums.isNotEmpty) const SectionTitle(Zh.albums),
                            for (final album in result.albums)
                              ListTile(
                                title: Text(album.name),
                                subtitle: Text(album.artistLabel),
                                onTap: () => openAlbum(context, widget.controller, album.id),
                              ),
                            if (result.songs.isNotEmpty) const SectionTitle(Zh.songs),
                            for (var i = 0; i < result.songs.length; i++)
                              SongTile(
                                song: result.songs[i],
                                onTap: () => widget.controller.playSongs(result.songs, i, albumGain: false),
                                onMore: () => showSongMenu(context, widget.controller, result.songs[i]),
                              ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}
