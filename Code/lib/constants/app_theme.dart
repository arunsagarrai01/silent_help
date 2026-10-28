import 'package:flutter/material.dart';

/// Central theme for SilentHelp.
///
/// Supports LIGHT and DARK modes. Brand colours (lime, status colours) are the
/// same in both modes; the "semantic" neutrals (surface / card / text / grey)
/// flip based on [isDark]. Screens keep using `AppTheme.surface`,
/// `AppTheme.card`, `AppTheme.charcoal`, etc. unchanged — those are now dynamic
/// getters so the whole UI adapts automatically.
class AppTheme {
  AppTheme._();

  /// Set once per frame by [MaterialApp] (via [applyBrightness]) so the static
  /// getters below know which palette to return.
  static bool isDark = false;

  static void applyBrightness(Brightness b) {
    isDark = b == Brightness.dark;
  }

  // ---- Brand palette (same in both modes) ----
  static const Color lime = Color(0xFFC5E81C);
  static const Color limeDark = Color(0xFFAFCE12);

  static Color get limeSoft =>
      isDark ? const Color(0xFF3A4010) : const Color(0xFFEEF7C4);

  /// Status colours (kept on-brand).
  static const Color success = Color(0xFF7CB518);
  static const Color danger = Color(0xFFE84C3D);
  static const Color warning = Color(0xFFE8A31C);

  // ---- Semantic neutrals (flip by mode) ----
  /// App / scaffold background.
  static Color get surface =>
      isDark ? const Color(0xFF121212) : const Color(0xFFF4F5F0);

  /// Raised card / sheet background.
  static Color get card => isDark ? const Color(0xFF1E1E1E) : Colors.white;

  /// Primary text / strong foreground.
  static Color get charcoal =>
      isDark ? const Color(0xFFF2F2F2) : const Color(0xFF2E2E2E);

  /// Secondary text.
  static Color get charcoalSoft =>
      isDark ? const Color(0xFFCFCFCF) : const Color(0xFF4A4A4A);

  /// Muted text / icons.
  static Color get grey =>
      isDark ? const Color(0xFF9A9A9A) : const Color(0xFF9E9E9E);

  /// Subtle dividers / inactive track.
  static Color get greyLight =>
      isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

  // ---- Gradients ----
  static const LinearGradient limeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lime, limeDark],
  );

  /// Dark hero gradient — stays dark in both modes (lime pops on it).
  static const LinearGradient charcoalGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E2E2E), Color(0xFF4A4A4A)],
  );

  // ---- Shadows ----
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
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

  /// Light ThemeData.
  static ThemeData lightTheme() => _build(Brightness.light);

  /// Dark ThemeData.
  static ThemeData darkTheme() => _build(Brightness.dark);

  /// Backwards-compatible alias (was the only theme before).
  static ThemeData themeData() => lightTheme();

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surfaceC = dark ? const Color(0xFF121212) : const Color(0xFFF4F5F0);
    final cardC = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final textC = dark ? const Color(0xFFF2F2F2) : const Color(0xFF2E2E2E);
    final trackOff = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lime,
        primary: lime,
        onPrimary: const Color(0xFF2E2E2E),
        secondary: textC,
        surface: cardC,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: surfaceC,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceC,
        foregroundColor: textC,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textC,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardC,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF2E2E2E)
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? lime : trackOff,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: lime,
        foregroundColor: Color(0xFF2E2E2E),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
