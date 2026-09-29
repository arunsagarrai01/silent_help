import 'package:flutter/material.dart';

/// Central theme for SilentHelp emergency features.
///
/// Inspired by a modern fitness-app palette: a vivid lime accent on soft
/// light-grey surfaces with deep charcoal text. Used across every emergency
/// screen (Contacts, Triggers, Alert Message, Settings, History, etc.).
class AppTheme {
  AppTheme._();

  // ---- Core palette ----
  /// Vivid lime/chartreuse accent.
  static const Color lime = Color(0xFFC5E81C);
  static const Color limeDark = Color(0xFFAFCE12);
  static const Color limeSoft = Color(0xFFEEF7C4);

  /// Neutrals.
  static const Color charcoal = Color(0xFF2E2E2E);
  static const Color charcoalSoft = Color(0xFF4A4A4A);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFE0E0E0);
  static const Color surface = Color(0xFFF4F5F0);
  static const Color card = Colors.white;

  /// Status colours (kept on-brand).
  static const Color success = Color(0xFF7CB518);
  static const Color danger = Color(0xFFE84C3D);
  static const Color warning = Color(0xFFE8A31C);

  // ---- Gradients ----
  static const LinearGradient limeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lime, limeDark],
  );

  static const LinearGradient charcoalGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [charcoal, charcoalSoft],
  );

  // ---- Shadows ----
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get limeShadow => [
    BoxShadow(
      color: lime.withValues(alpha: 0.35),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  // ---- Radii ----
  static const double radius = 20.0;
  static const double radiusSmall = 14.0;

  /// The MaterialApp ThemeData for the emergency section.
  static ThemeData themeData() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lime,
        primary: lime,
        onPrimary: charcoal,
        secondary: charcoal,
        surface: card,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: surface,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: charcoal,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: charcoal,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? charcoal : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? lime : greyLight,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lime,
        foregroundColor: charcoal,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
