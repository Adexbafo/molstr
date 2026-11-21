import 'package:flutter/material.dart';

class MolStrColors {
  static const purple = Color(0xFF7C3AED);
  static const deepPurple = Color(0xFF4C1D95);
  static const lightPurple = Color(0xFFA78BFA);
  static const ink = Color(0xFF0F0A1E);
  static const cardDark = Color(0xFF18112C);
}

enum MolStrPreset {
  nightInk,
  paper,
  highContrast,
  orchid;

  String get label => switch (this) {
        nightInk => 'Night Ink',
        paper => 'Paper',
        highContrast => 'High Contrast',
        orchid => 'Orchid',
      };
}

class MolStrTheme {
  static ThemeData forPreset(MolStrPreset preset) {
    final brightness = preset == MolStrPreset.paper
        ? Brightness.light
        : Brightness.dark;

    final background = switch (preset) {
      MolStrPreset.nightInk => MolStrColors.ink,
      MolStrPreset.paper => const Color(0xFFFAF7F2),
      MolStrPreset.highContrast => Colors.black,
      MolStrPreset.orchid => const Color(0xFF261033),
    };

    final surface = switch (preset) {
      MolStrPreset.nightInk => MolStrColors.cardDark,
      MolStrPreset.paper => Colors.white,
      MolStrPreset.highContrast => Colors.black,
      MolStrPreset.orchid => const Color(0xFF391B49),
    };

    final accent = switch (preset) {
      MolStrPreset.nightInk => MolStrColors.lightPurple,
      MolStrPreset.paper => MolStrColors.deepPurple,
      MolStrPreset.highContrast => Colors.white,
      MolStrPreset.orchid => const Color(0xFFF0ABFC),
    };

    final foreground =
        brightness == Brightness.dark ? Colors.white : const Color(0xFF21172E);

    final scheme = ColorScheme.fromSeed(
      seedColor: MolStrColors.purple,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: preset == MolStrPreset.highContrast
          ? Colors.white
          : null,
      outline: preset == MolStrPreset.highContrast ? Colors.white : null,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
      ),
    );
  }
}