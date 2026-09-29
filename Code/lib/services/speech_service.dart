import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Voice SOS service using a platform channel to native speech recognition.
///
/// The native side (Android `SpeechRecognizer`) continuously listens and calls
/// back into Dart via `onWakeWord` when the phrase "SilentHelp Emergency" (or a
/// close variant) is heard. This runs in the UI isolate while the app is open.
///
/// iOS: continuous background microphone is restricted by Apple; voice SOS on
/// iOS works only while the app is in the foreground.
class SpeechService {
  static const MethodChannel _channel = MethodChannel('silent_help/speech');

  final void Function() _onWakeWordDetected;
  bool _isListening = false;

  SpeechService({required void Function() onWakeWordDetected})
    : _onWakeWordDetected = onWakeWordDetected {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onWakeWord':
        debugPrint('Voice wake word detected: ${call.arguments}');
        _onWakeWordDetected();
        break;
      case 'onPermissionGranted':
        _isListening = true;
        break;
      case 'onPermissionDenied':
        _isListening = false;
        break;
    }
    return null;
  }

  /// Whether device supports speech recognition.
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod('isAvailable');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  /// Start continuously listening for the wake word.
  Future<bool> startListening() async {
    if (_isListening) return true;
    try {
      final result = await _channel.invokeMethod('startListening');
      _isListening =
          result == 'LISTENING_STARTED' || result == 'PERMISSION_REQUESTED';
      return _isListening;
    } on PlatformException catch (e) {
      debugPrint('SpeechService start error: ${e.code} - ${e.message}');
      _isListening = false;
      return false;
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    if (!_isListening) return;
    try {
      await _channel.invokeMethod('stopListening');
      _isListening = false;
    } on PlatformException catch (e) {
      debugPrint('SpeechService stop error: ${e.code} - ${e.message}');
    }
  }

  bool get isListening => _isListening;

  Future<void> dispose() async {
    await stopListening();
    _channel.setMethodCallHandler(null);
  }
}

/// Local keyword/intent matcher (offline, no cloud).
class IntentDetector {
  static bool hasEmergencyIntent(String phrase) {
    final lower = phrase.toLowerCase();
    final hasName =
        lower.contains('silenthelp') ||
        (lower.contains('silent') && lower.contains('help'));
    final hasIntent =
        lower.contains('emergency') ||
        lower.contains('sos') ||
        lower.contains('help me');
    return hasName && hasIntent;
  }
}
