import 'package:flutter/material.dart';

import 'storage_service.dart';

/// Holds the current [ThemeMode] and persists the user's choice.
///
/// Exposes a [ValueNotifier] so [MaterialApp] rebuilds when the mode changes.
/// Modes: system (follow device), light, dark.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final StorageService _storage = StorageService();

  /// Current mode; listened to by the app root.
  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Load the saved preference at startup.
  Future<void> load() async {
    final saved = await _storage.getThemeMode();
    mode.value = _fromString(saved);
  }

  /// Change and persist the mode.
  Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    await _storage.setThemeMode(_toString(m));
  }

  static ThemeMode _fromString(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
