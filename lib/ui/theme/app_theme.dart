import 'package:flutter/material.dart';

class MolStrColors {
  static const purple = Color(0xFF7C3AED);
  static const deepPurple = Color(0xFF4C1D95);
  static const lightPurple = Color(0xFFA78BFA);
  static const ink = Color(0xFF0F0A1E);
  static const cardDark = Color(0xFF18112C);
}

class MolStrTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: MolStrColors.ink,
      primaryColor: MolStrColors.purple,
      colorScheme: const ColorScheme.dark(
        primary: MolStrColors.purple,
        secondary: Colors.white,
        surface: MolStrColors.cardDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MolStrColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: MolStrColors.purple,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: MolStrColors.ink,
        selectedItemColor: MolStrColors.lightPurple,
        unselectedItemColor: Colors.grey,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF8F7FC),
      primaryColor: MolStrColors.purple,
      colorScheme: const ColorScheme.light(
        primary: MolStrColors.deepPurple,
        secondary: MolStrColors.purple,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: MolStrColors.purple,
        foregroundColor: Colors.white,
      ),
    );
  }
}