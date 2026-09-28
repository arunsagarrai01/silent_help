import 'dart:async';
import 'package:flutter/services.dart';

/// Voice SOS service using platform channel to native speech recognition.
///
/// Android: SpeechRecognizer API
/// iOS: SFSpeechRecognizer (to be implemented)
class SpeechService {
  static const MethodChannel _channel = MethodChannel('silent_help/speech');

  final void Function() _onWakeWordDetected;

  bool _isListening = false;

  SpeechService({required void Function() onWakeWordDetected})
    : _onWakeWordDetected = onWakeWordDetected;

  /// Start listening for the wake word.
  Future<bool> startListening() async {
    if (_isListening) return true;

    try {
      final result = await _channel.invokeMethod('startListening');
      if (result == 'SOS_TRIGGERED') {
        _onWakeWordDetected();
      }
      _isListening = result == 'LISTENING_STARTED';
      return _isListening;
    } on PlatformException catch (e) {
      print('SpeechService error: ${e.code} - ${e.message}');
      _isListening = false;
      return false;
    }
  }

  /// Stop listening for the wake word.
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _channel.invokeMethod('stopListening');
      _isListening = false;
    } on PlatformException catch (e) {
      print('SpeechService stop error: ${e.code} - ${e.message}');
    }
  }

  /// Whether the service is currently listening.
  bool get isListening => _isListening;

  /// Cleanup resources.
  Future<void> dispose() async {
    await stopListening();
  }
}

/// Simple intent detection helper for confirming SOS intent.
class IntentDetector {
  /// Check if the detected phrase indicates an emergency intent.
  static bool hasEmergencyIntent(String phrase) {
    final lower = phrase.toLowerCase();
    return lower.contains('silenthelp') &&
        (lower.contains('emergency') ||
            lower.contains('sos') ||
            lower.contains('help'));
  }
}
