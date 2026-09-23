import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'emergency_service.dart';

/// Entry point for the foreground-service isolate.
///
/// MUST be a top-level function annotated with `@pragma('vm:entry-point')` so
/// it survives tree-shaking and can be resolved by the platform side.
@pragma('vm:entry-point')
void startSosCallback() {
  FlutterForegroundTask.setTaskHandler(SosTaskHandler());
}

/// Runs inside the Android foreground service isolate.
///
/// Keeps the accelerometer alive while the app is minimized or the screen is
/// locked, detects strong shakes, and triggers the offline emergency flow.
class SosTaskHandler extends TaskHandler {
  // Shake detection tuning (mirrors the original SensorService).
  static const double _shakeThreshold = 12.0;
  static const int _shakeWindowMs = 1500;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<DateTime> _shakeTimestamps = [];

  // Number of strong shakes required. Defaults to 3, overridable via data.
  int _requiredShakeCount = 3;

  // Guards against re-entrancy while an alert is being processed.
  bool _handling = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _requiredShakeCount = await _loadShakeCount();
    _startListening();
  }

  void _startListening() {
    _accelSub?.cancel();
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(
      _onAccelerometer,
      onError: (_) {
        // Sensor errors are non-fatal; keep the service alive.
      },
      cancelOnError: false,
    );
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final magnitude =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

    if (magnitude <= _shakeThreshold) return;

    final now = DateTime.now();
    _shakeTimestamps.add(now);
    _shakeTimestamps.removeWhere(
      (t) => now.difference(t).inMilliseconds > _shakeWindowMs,
    );

    if (_shakeTimestamps.length >= _requiredShakeCount && !_handling) {
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
      // Notify the UI isolate (if it is listening) about the outcome.
      FlutterForegroundTask.sendDataToMain(result.name);

      // Reflect state in the ongoing notification.
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
      // Never crash the service.
    } finally {
      _handling = false;
    }
  }

  Future<int> _loadShakeCount() async {
    try {
      final value =
          await FlutterForegroundTask.getData<int>(key: _kShakeCountKey);
      if (value != null && value >= 2) return value;
    } catch (_) {}
    return 3;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Watchdog: if the sensor subscription somehow died, restart it.
    if (_accelSub == null) {
      _startListening();
    }
  }

  @override
  void onReceiveData(Object data) {
    // Allow the UI isolate to push a new shake count at runtime.
    if (data is int && data >= 2) {
      _requiredShakeCount = data;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _accelSub?.cancel();
    _accelSub = null;
    _shakeTimestamps.clear();
  }
}

/// Key used to share the configured shake count into the service isolate via
/// [FlutterForegroundTask]'s own prefs store.
const String _kShakeCountKey = 'fg_shake_count';

/// UI-side controller for the background SOS foreground service.
class ForegroundSosService {
  ForegroundSosService._();

  static bool _initialized = false;

  /// Initialise notification channel + task options. Safe to call repeatedly.
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
        // A light heartbeat used only as a sensor watchdog.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// Push the configured shake count so the service isolate can read it.
  static Future<void> setShakeCount(int count) async {
    await FlutterForegroundTask.saveData(key: _kShakeCountKey, value: count);
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(count);
    }
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  /// Start (or no-op if already running) the monitoring service.
  static Future<bool> start() async {
    init();
    if (await isRunning()) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: 8421,
      serviceTypes: const [
        ForegroundServiceTypes.location,
        ForegroundServiceTypes.dataSync,
      ],
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
