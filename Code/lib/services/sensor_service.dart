import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Sensor service for detecting shake gestures (in-app / foreground).
///
/// Uses GRAVITY-COMPENSATED acceleration: a phone at rest reads ~0 (not ~9.8),
/// so a deliberate shake is detected accurately and quickly, while walking /
/// carrying stays well below the threshold.
class SensorService {
  static const double _gravity = 9.81;

  /// Net acceleration (above gravity) that counts as one shake "jolt".
  static const double _shakeDelta = 12.0;

  /// Window within which the required jolts must occur.
  static const int _shakeTimeWindow = 1500;

  /// Ignore sensor transients right after start (prevents accidental trigger).
  static const int _armingDelayMs = 1500;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  final List<DateTime> _shakeTimestamps = [];
  Function(int)? _onShakeDetected;
  int _requiredShakeCount = 3;
  DateTime? _lastTriggerTime;
  DateTime? _armedAt;

  void startShakeDetection({
    required Function(int) onShakeDetected,
    int requiredShakeCount = 3,
  }) {
    _onShakeDetected = onShakeDetected;
    _requiredShakeCount = requiredShakeCount;
    _shakeTimestamps.clear();
    _armedAt = DateTime.now().add(const Duration(milliseconds: _armingDelayMs));

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval, // ~20ms, fast + responsive
    ).listen(_handleAccelerometerEvent, onError: (_) {}, cancelOnError: false);
  }

  void stopShakeDetection() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _shakeTimestamps.clear();
    _lastTriggerTime = null;
    _armedAt = null;
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    final now = DateTime.now();

    // Not armed yet → ignore startup transients.
    if (_armedAt == null || now.isBefore(_armedAt!)) return;

    final magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final net = (magnitude - _gravity).abs();

    if (net <= _shakeDelta) return;

    _shakeTimestamps.add(now);
    _shakeTimestamps.removeWhere(
      (t) => now.difference(t).inMilliseconds > _shakeTimeWindow,
    );

    final inCooldown =
        _lastTriggerTime != null &&
        now.difference(_lastTriggerTime!).inSeconds < 60;

    if (_shakeTimestamps.length >= _requiredShakeCount && !inCooldown) {
      _lastTriggerTime = now;
      _shakeTimestamps.clear();
      _onShakeDetected?.call(_requiredShakeCount);
    }
  }

  bool get isListening => _accelerometerSubscription != null;
}
