import 'package:flutter/foundation.dart';

import 'emergency_service.dart';
import 'foreground_sos_service.dart';
import 'permission_service.dart';
import 'speech_service.dart';

/// Drives Voice SOS from the UI isolate.
///
/// Android's `SpeechRecognizer` needs an Activity + platform channel, which are
/// only available in the main (UI) isolate — not the background foreground
/// service isolate. So we run continuous voice listening here, while the app is
/// open, and trigger the shared [EmergencyService] on the wake phrase.
class VoiceSosController {
  VoiceSosController._();
  static final VoiceSosController instance = VoiceSosController._();

  SpeechService? _speech;
  bool _active = false;

  /// Notifies listeners (e.g. UI) when a voice SOS fires.
  final ValueNotifier<bool> lastTriggered = ValueNotifier(false);

  bool get isActive => _active;

  /// Start listening if the user has enabled Voice SOS.
  Future<bool> startIfEnabled() async {
    final enabled = await ForegroundSosService.isVoiceSosEnabled();
    if (!enabled) return false;
    return start();
  }

  /// Start continuous voice listening. Requests mic permission if needed.
  Future<bool> start() async {
    if (_active) return true;

    final micGranted = await PermissionService.requestMicrophone();
    if (!micGranted) {
      debugPrint('VoiceSos: microphone permission denied');
      return false;
    }

    _speech = SpeechService(onWakeWordDetected: _onWakeWord);
    final available = await _speech!.isAvailable();
    if (!available) {
      debugPrint('VoiceSos: speech recognition unavailable');
      return false;
    }

    final started = await _speech!.startListening();
    _active = started;
    return started;
  }

  Future<void> stop() async {
    _active = false;
    await _speech?.stopListening();
    await _speech?.dispose();
    _speech = null;
  }

  Future<void> _onWakeWord() async {
    final result = await EmergencyService.triggerEmergencyAlert(
      'Voice SOS (SilentHelp Emergency)',
    );
    if (result == EmergencyResult.sent) {
      lastTriggered.value = true;
      // reset flag shortly after so UI can re-listen for future events
      Future.delayed(const Duration(seconds: 2), () {
        lastTriggered.value = false;
      });
    }
  }
}
