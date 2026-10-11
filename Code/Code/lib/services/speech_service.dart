import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin bridge to the NATIVE background voice service (VoiceSosService.kt).
///
/// Voice recognition + SMS sending run entirely in a native Android foreground
/// service, so they keep working in the background and when the screen is off —
/// exactly like shake detection. This Dart class only starts/stops that service
/// and relays permission callbacks.
class SpeechService {
  static const MethodChannel _channel = MethodChannel('silent_help/speech');

  /// Optional: notified when native reports permission results.
  final void Function()? onPermissionGranted;
  final void Function()? onPermissionDenied;

  bool _started = false;

  SpeechService({this.onPermissionGranted, this.onPermissionDenied}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPermissionGranted':
        _started = true;
        onPermissionGranted?.call();
        break;
      case 'onPermissionDenied':
        _started = false;
        onPermissionDenied?.call();
        break;
    }
    return null;
  }

  /// Whether the device supports speech recognition.
  Future<bool> isAvailable() async {
    try {
      return (await _channel.invokeMethod('isVoiceServiceAvailable')) == true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> hasMicPermission() async {
    try {
      return (await _channel.invokeMethod('hasMicPermission')) == true;
    } on PlatformException {
      return false;
    }
  }

  /// Start the native background voice service with the given config.
  Future<bool> start({
    required String phrase,
    required String contactsJson,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod('startVoiceService', {
        'phrase': phrase,
        'contactsJson': contactsJson,
        'message': message,
      });
      _started = result == 'STARTED' || result == 'PERMISSION_REQUESTED';
      return _started;
    } on PlatformException catch (e) {
      debugPrint('SpeechService start error: ${e.code} - ${e.message}');
      return false;
    }
  }

  /// Update native config while the service is running.
  Future<void> updateConfig({
    String? phrase,
    String? contactsJson,
    String? message,
  }) async {
    try {
      await _channel.invokeMethod('updateVoiceConfig', {
        if (phrase != null) 'phrase': phrase,
        if (contactsJson != null) 'contactsJson': contactsJson,
        if (message != null) 'message': message,
      });
    } on PlatformException catch (e) {
      debugPrint('SpeechService updateConfig error: ${e.message}');
    }
  }

  /// Stop the native background voice service.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopVoiceService');
      _started = false;
    } on PlatformException catch (e) {
      debugPrint('SpeechService stop error: ${e.message}');
    }
  }

  bool get isListening => _started;

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
  }
}
