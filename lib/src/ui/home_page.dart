import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import 'library_forms.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = false;
  Object? _error;
  List<Album> _newest = const [];
  List<Album> _recent = const [];
  List<Album> _random = const [];
  int _epoch = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (widget.controller.libraryEpoch != _epoch) _load();
  }

  Future<void> _load() async {
    final controller = widget.controller;
    _epoch = controller.libraryEpoch;
    if (!controller.hasLibrary) {
      setState(() {
        _loading = false;
        _error = null;
        _newest = const [];
        _recent = const [];
        _random = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        controller.albums(type: 'newest'),
        controller.albums(type: 'recent'),
        controller.albums(type: 'random'),
      ]);
      try {
        await controller.refreshFolders();
      } catch (_) {}
      if (!mounted || controller.libraryEpoch != _epoch) return;
      setState(() {
        _newest = results[0];
        _recent = results[1];
        _random = results[2];
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
    final controller = widget.controller;
    if (!controller.ready) return const LoadingPane();
    if (!controller.hasLibrary) {
      return MessagePane(
        icon: Icons.library_add_outlined,
        title: Zh.noLibraryTitle,
        body: Zh.noLibraryBody,
        actionLabel: Zh.addLibrary,
        onAction: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => LibraryFormPage(controller: controller)),
          );
        },
      );
    }
    if (controller.needsPassword) {
      return MessagePane(
        icon: Icons.key_outlined,
        title: Zh.needPassword,
        actionLabel: Zh.editLibrary,
        onAction: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => LibraryFormPage(controller: controller, existing: controller.current),
            ),
          );
        },
      );
    }
    final empty = !_loading && _error == null && _newest.isEmpty && _recent.isEmpty && _random.isEmpty;
    return StatusPane(
      loading: _loading && _newest.isEmpty && _recent.isEmpty && _random.isEmpty,
      error: _newest.isEmpty && _recent.isEmpty && _random.isEmpty ? _error : null,
      empty: empty,
      emptyTitle: Zh.emptyCatalogTitle,
      emptyBody: Zh.emptyCatalogBody,
      onRetry: _load,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (controller.current?.unrecognized == true) const WarningBanner(text: Zh.unrecognizedServer),
            if (controller.current?.hasTranscoding == false) const WarningBanner(text: Zh.noTranscoding),
            _shelf(Zh.recentlyAdded, _newest),
            _shelf(Zh.recentlyPlayed, _recent),
            _shelf(Zh.randomAlbums, _random),
          ],
        ),
      ),
    );
  }

  Widget _shelf(String title, List<Album> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = _homeColumns(width);
            const gap = 16.0;
            final tile = columns <= 1 ? width : (width - gap * (columns - 1)) / columns;
            return GridView.builder(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 18,
                crossAxisSpacing: gap,
                mainAxisExtent: tile + 72,
              ),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
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
      ],
    );
  }
}

int _homeColumns(double width) {
  if (width >= 1500) return 5;
  if (width >= 1100) return 4;
  if (width >= 760) return 3;
  if (width >= 480) return 2;
  return 2;
}
