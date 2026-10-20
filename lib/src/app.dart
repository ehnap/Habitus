import 'package:flutter/material.dart';

import 'copy/zh.dart';
import 'desktop/desktop_chrome.dart';
import 'failure.dart';
import 'state/app_controller.dart';
import 'theme/habitus_theme.dart';
import 'ui/detail_pages.dart';
import 'ui/shell.dart';
import 'ui/widgets.dart';

class HabitusApp extends StatefulWidget {
  const HabitusApp({super.key, required this.controller, this.desktop});

  final AppController controller;
  final DesktopChrome? desktop;

  @override
  State<HabitusApp> createState() => _HabitusAppState();
}

class _HabitusAppState extends State<HabitusApp> {
  @override
  void initState() {
    super.initState();
    registerDetailPages();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: Zh.appName,
      theme: habitusLight(),
      darkTheme: habitusDark(),
      themeMode: ThemeMode.system,
      home: AppShell(controller: widget.controller),
    );
    final desktop = widget.desktop;
    if (desktop == null) return app;
    return DesktopChromeScope(chrome: desktop, child: app);
  }
}

class HabitusBootFailure extends StatelessWidget {
  const HabitusBootFailure({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Zh.appName,
      theme: habitusLight(),
      darkTheme: habitusDark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: MessagePane(
          icon: Icons.error_outline,
          title: describeError(error),
          body: Zh.genericError,
        ),
      ),
    );
  }
}
