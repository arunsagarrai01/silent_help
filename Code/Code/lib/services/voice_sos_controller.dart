import 'package:flutter/foundation.dart';

import 'foreground_sos_service.dart';
import 'permission_service.dart';
import 'speech_service.dart';
import 'storage_service.dart';

/// Controls the NATIVE background voice-trigger service.
///
/// The heavy lifting (continuous recognition + SMS) runs in VoiceSosService.kt
/// so it works in the background / screen off, like shake detection. This
/// controller:
///   - ensures the trigger phrase, contacts and message are persisted to the
///     shared prefs the native service reads,
///   - requests microphone permission,
///   - starts / stops the native service.
class VoiceSosController {
  VoiceSosController._();
  static final VoiceSosController instance = VoiceSosController._();

  final StorageService _storage = StorageService();
  SpeechService? _speech;
  bool _active = false;

  final ValueNotifier<bool> lastTriggered = ValueNotifier(false);

  bool get isActive => _active;

  /// Start the native voice service if the user enabled Voice SOS.
  Future<bool> startIfEnabled() async {
    final enabled = await ForegroundSosService.isVoiceSosEnabled();
    if (!enabled) return false;
    return start();
  }

  /// Start the native background voice service.
  Future<bool> start() async {
    if (_active) return true;

    final micGranted = await PermissionService.requestMicrophone();
    if (!micGranted) {
      debugPrint('VoiceSos: microphone permission denied');
      return false;
    }

    _speech ??= SpeechService(
      onPermissionGranted: () => _active = true,
      onPermissionDenied: () => _active = false,
    );

    final available = await _speech!.isAvailable();
    if (!available) {
      debugPrint('VoiceSos: speech recognition unavailable on this device');
      return false;
    }

    // Hand the current config to the native service.
    final phrase = await _storage.getVoicePhrase();
    final contactsJson = await _storage.getContactsJson();
    final message = await _storage.getAlertMessage();

    final started = await _speech!.start(
      phrase: phrase,
      contactsJson: contactsJson,
      message: message,
    );
    _active = started;
    return started;
  }

  Future<void> stop() async {
    _active = false;
    await _speech?.stop();
  }

  /// Persist a new phrase and push it to the running native service.
  Future<void> updatePhrase(String phrase) async {
    await _storage.setVoicePhrase(phrase);
    if (_active) {
      await _speech?.updateConfig(phrase: phrase.toLowerCase());
    }
  }

  /// Call after contacts or the alert message change so the background service
  /// always has the latest config.
  Future<void> refreshConfig() async {
    if (!_active) return;
    final contactsJson = await _storage.getContactsJson();
    final message = await _storage.getAlertMessage();
    await _speech?.updateConfig(contactsJson: contactsJson, message: message);
  }
}
