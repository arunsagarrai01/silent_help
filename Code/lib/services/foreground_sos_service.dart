import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'emergency_service.dart';
import 'permission_service.dart';
import 'speech_service.dart';

/// Entry point for the foreground-service isolate.
@pragma('vm:entry-point')
void startSosCallback() {
  FlutterForegroundTask.setTaskHandler(SosTaskHandler());
}

/// Runs inside the Android foreground service isolate.
class SosTaskHandler extends TaskHandler {
  static const double _shakeThreshold = 17.0;
  static const double _minShakeMagnitude = 14.0;
  static const int _shakeWindowMs = 2000;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<DateTime> _shakeTimestamps = [];
  DateTime? _lastTriggerTime;

  SpeechService? _speechService;
  bool _voiceSosEnabled = false;

  int _requiredShakeCount = 3;
  bool _handling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _requiredShakeCount = await _loadShakeCount();
    _voiceSosEnabled = await _loadVoiceSosEnabled();
    _startListening();

    if (_voiceSosEnabled) {
      _speechService = SpeechService(onWakeWordDetected: _onVoiceSosDetected);
      await _speechService?.startListening();
    }
  }

  Future<void> _onVoiceSosDetected() async {
    if (_handling) return;

    final result = await EmergencyService.triggerEmergencyAlert(
      'Voice SOS (SilentHelp Emergency)',
    );

    if (result == EmergencyResult.sent) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Calculator',
        notificationText: 'SOS sent. Monitoring resumed.',
      );
    }
  }

  void _startListening() {
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(_onAccelerometer, onError: (_) {}, cancelOnError: false);
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    if (magnitude < _minShakeMagnitude) return;
    if (magnitude <= _shakeThreshold) return;

    final now = DateTime.now();
    _shakeTimestamps.add(now);
    _shakeTimestamps.removeWhere(
      (t) => now.difference(t).inMilliseconds > _shakeWindowMs,
    );

    if (_shakeTimestamps.length >= _requiredShakeCount &&
        (_lastTriggerTime == null ||
            now.difference(_lastTriggerTime!).inSeconds > 60) &&
        !_handling) {
      _lastTriggerTime = now;
      _shakeTimestamps.clear();
      _triggerEmergency();
    }
  }

  Future<void> _triggerEmergency() async {
    _handling = true;
    try {
      final result = await EmergencyService.triggerEmergencyAlert(
        'Background Shake ($_requiredShakeCount shakes)',
      );
      FlutterForegroundTask.sendDataToMain(result.name);

      final text = switch (result) {
        EmergencyResult.sent => 'SOS sent. Monitoring resumed.',
        EmergencyResult.cooldown => 'Recent SOS active. Monitoring.',
        EmergencyResult.noContacts => 'No contacts set. Monitoring.',
        EmergencyResult.smsUnavailable => 'SMS unavailable. Monitoring.',
      };
      FlutterForegroundTask.updateService(
        notificationTitle: 'Calculator',
        notificationText: text,
      );
    } catch (_) {
    } finally {
      _handling = false;
    }
  }

  Future<int> _loadShakeCount() async {
    try {
      final value = await FlutterForegroundTask.getData<int>(
        key: _kShakeCountKey,
      );
      if (value != null && value >= 2) return value;
    } catch (_) {}
    return 3;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_accelSub == null) {
      _startListening();
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is int && data >= 2) {
      _requiredShakeCount = data;
    }
    if (data is bool) {
      if (data && _speechService == null) {
        _voiceSosEnabled = true;
        _speechService = SpeechService(onWakeWordDetected: _onVoiceSosDetected);
        _speechService?.startListening();
      } else if (!data && _speechService != null) {
        _speechService?.stopListening();
        _speechService?.dispose();
        _speechService = null;
        _voiceSosEnabled = false;
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _accelSub?.cancel();
    _accelSub = null;
    _shakeTimestamps.clear();
    await _speechService?.stopListening();
    await _speechService?.dispose();
    _speechService = null;
  }

  Future<bool> _loadVoiceSosEnabled() async {
    try {
      final value = await FlutterForegroundTask.getData<bool>(
        key: _kVoiceSosEnabledKey,
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }
}

const String _kShakeCountKey = 'fg_shake_count';
const String _kVoiceSosEnabledKey = 'fg_voice_sos_enabled';

/// UI-side controller for the background SOS foreground service.
class ForegroundSosService {
  ForegroundSosService._();

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'silent_help_monitor',
        channelName: 'Background service',
        channelDescription: 'Keeps the calculator running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  static Future<void> setShakeCount(int count) async {
    await FlutterForegroundTask.saveData(key: _kShakeCountKey, value: count);
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(count);
    }
  }

  static Future<void> setVoiceSosEnabled(bool enabled) async {
    await FlutterForegroundTask.saveData(
      key: _kVoiceSosEnabledKey,
      value: enabled,
    );
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(enabled);
    }
  }

  static Future<bool> isVoiceSosEnabled() async {
    try {
      final value = await FlutterForegroundTask.getData<bool>(
        key: _kVoiceSosEnabledKey,
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start() async {
    init();
    if (await isRunning()) return true;

    await PermissionService.requestBackgroundLocation();

    final serviceTypes = <ForegroundServiceTypes>[
      ForegroundServiceTypes.location,
      ForegroundServiceTypes.dataSync,
    ];
    final voiceEnabled = await isVoiceSosEnabled();
    if (voiceEnabled) {
      serviceTypes.add(ForegroundServiceTypes.microphone);
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 8421,
      serviceTypes: serviceTypes,
      notificationTitle: 'Calculator',
      notificationText: 'Running',
      callback: startSosCallback,
    );

    if (result is ServiceRequestFailure) {
      debugPrint('Foreground service failed to start: ${result.error}');
      return false;
    }
    return true;
  }

  static Future<bool> stop() async {
    if (!await isRunning()) return true;
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }
}
