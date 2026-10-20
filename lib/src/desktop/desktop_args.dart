/// Argument string desktop_multi_window passes to the lyrics engine.
const desktopLyricsArgument = 'habitus.lyrics';

/// Channel shared by the main window and the desktop lyrics window.
const desktopLyricsChannel = 'habitus.lyrics';

/// The child engine is started with `multi_window`, its window id, then [desktopLyricsArgument].
bool isDesktopLyricsLaunch(List<String> args) {
  return args.length >= 3 && args[0] == 'multi_window' && args[2] == desktopLyricsArgument;
}
