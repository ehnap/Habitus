import 'dart:async';

import 'package:flutter/material.dart';

import '../copy/zh.dart';
import '../model/models.dart';
import '../state/app_controller.dart';
import '../theme/habitus_theme.dart';
import 'browse_pages.dart';
import 'home_page.dart';
import 'library_forms.dart';
import 'player_page.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _tab = ValueNotifier<int>(0);
  StreamSubscription<String>? _messages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab.addListener(() {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      setState(() {});
    });
    _messages = widget.controller.messages.stream.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.persistQueue();
    }
  }

  void _openPlayer() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => PlayerPage(controller: widget.controller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = desktopLayout(constraints.maxWidth);
            final body = Column(
              children: [
                _LibraryBar(controller: controller),
                Expanded(child: _stackNavigator()),
                _Transport(controller: controller, desktop: desktop, onOpen: _openPlayer),
              ],
            );
            if (!desktop) {
              return Scaffold(
                body: SafeArea(bottom: false, child: body),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _tab.value,
                  onDestinationSelected: (index) => _tab.value = index,
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Zh.home),
                    NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: Zh.library),
                    NavigationDestination(icon: Icon(Icons.search), label: Zh.search),
                    NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Zh.me),
                  ],
                ),
              );
            }
            return Scaffold(
              body: Row(
                children: [
                  _Sidebar(tab: _tab.value, onSelect: (index) => _tab.value = index),
                  Expanded(child: body),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _stackNavigator() {
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (context) {
            return ValueListenableBuilder<int>(
              valueListenable: _tab,
              builder: (context, tab, _) {
                return IndexedStack(
                  index: tab,
                  children: [
                    HomePage(controller: widget.controller),
                    LibraryHubPage(controller: widget.controller),
                    SearchPage(controller: widget.controller),
                    MePage(controller: widget.controller),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.tab, required this.onSelect});

  final int tab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (Icons.home_outlined, Zh.home),
      (Icons.library_music_outlined, Zh.library),
      (Icons.search, Zh.search),
      (Icons.person_outline, Zh.me),
    ];
    return Container(
      width: 220,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Text(Zh.appName, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: ListTile(
                  selected: tab == i,
                  selectedTileColor: scheme.primary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(items[i].$1),
                  title: Text(items[i].$2),
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryBar extends StatelessWidget {
  const _LibraryBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final library = controller.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: library == null ? null : () => showLibrarySwitcher(context, controller),
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  library?.name ?? Zh.noLibraryTitle,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
          if (controller.folders.length > 1)
            DropdownButton<String>(
              value: controller.folderId ?? '',
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: '', child: Text(Zh.allFolders)),
                for (final folder in controller.folders)
                  DropdownMenuItem(value: folder.id, child: Text(folder.name)),
              ],
              onChanged: (value) => controller.selectFolder(value == null || value.isEmpty ? null : value),
            ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, required this.desktop, required this.onOpen});

  final AppController controller;
  final bool desktop;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.player.views,
      builder: (context, _) {
        final view = controller.player.views.view;
        if (!view.hasSong) return const SizedBox.shrink();
        final song = view.song!;
        final progress = view.duration.inMilliseconds == 0
            ? 0.0
            : (view.position.inMilliseconds / view.duration.inMilliseconds).clamp(0.0, 1.0);
        return Material(
          color: Theme.of(context).cardColor,
          child: InkWell(
            onTap: onOpen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: view.buffering && progress == 0 ? null : progress, minHeight: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: CoverArt(
                          cache: controller.covers,
                          libraryId: controller.current?.id,
                          coverArt: song.coverArt,
                          size: 128,
                          radius: 8,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song.artistLabel,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (desktop) ...[
                        IconButton(tooltip: Zh.previous, onPressed: controller.player.skipToPrevious, icon: const Icon(Icons.skip_previous)),
                      ],
                      IconButton(
                        tooltip: view.playing ? Zh.pause : Zh.play,
                        onPressed: view.playing ? controller.player.pause : controller.player.play,
                        icon: Icon(view.playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36),
                      ),
                      IconButton(tooltip: Zh.next, onPressed: controller.player.skipToNext, icon: const Icon(Icons.skip_next)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void showLibrarySwitcher(BuildContext context, AppController controller) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text(Zh.switchLibrary)),
                for (final library in controller.libraries)
                  ListTile(
                    leading: Icon(controller.current?.id == library.id ? Icons.check_circle : Icons.circle_outlined),
                    title: Text(library.name),
                    subtitle: Text(_librarySubtitle(library)),
                    onTap: () async {
                      Navigator.pop(context);
                      await controller.switchTo(library.id);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text(Zh.addLibrary),
                  onTap: () {
                    final navigator = Navigator.of(context, rootNavigator: true);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute(builder: (_) => LibraryFormPage(controller: controller)),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _librarySubtitle(LibraryRecord library) {
  final notes = <String>[library.baseUrl];
  if (library.unrecognized) notes.add(Zh.unrecognizedServer);
  if (!library.hasTranscoding) notes.add(Zh.noTranscoding);
  return notes.join(' · ');
}
