import 'package:flutter/material.dart';

abstract final class HabitusColors {
  static const pine = Color(0xFF0F6E56);
  static const pineSoft = Color(0xFFE5F2ED);
  static const paper = Color(0xFFF3F0E8);
  static const paperCard = Color(0xFFFFFCF7);
  static const ink = Color(0xFF1C1915);
  static const muted = Color(0xFF6E675E);
  static const line = Color(0xFFE4DDD2);
  static const night = Color(0xFF121411);
  static const nightCard = Color(0xFF1C1F1A);
  static const nightInk = Color(0xFFF3F0E8);
  static const nightMuted = Color(0xFFA8A196);
  static const danger = Color(0xFF9C3B2E);
}

ThemeData habitusLight() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HabitusColors.pine,
    brightness: Brightness.light,
    surface: HabitusColors.paper,
  );
  return _base(scheme, HabitusColors.ink, HabitusColors.muted, HabitusColors.paperCard);
}

ThemeData habitusDark() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HabitusColors.pine,
    brightness: Brightness.dark,
    surface: HabitusColors.night,
  );
  return _base(scheme, HabitusColors.nightInk, HabitusColors.nightMuted, HabitusColors.nightCard);
}

ThemeData _base(ColorScheme scheme, Color ink, Color muted, Color card) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'Source Han Sans SC',
      'PingFang SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: ink)),
    ),
    dividerColor: scheme.brightness == Brightness.dark ? const Color(0xFF2A2E28) : HabitusColors.line,
    textTheme: TextTheme(
      titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 22),
      titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 16),
      bodyMedium: TextStyle(color: ink, fontSize: 14),
      bodySmall: TextStyle(color: muted, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

bool desktopLayout(double width) => width >= 1100;
