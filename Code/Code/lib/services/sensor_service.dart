import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Sensor service for detecting shake gestures
class SensorService {
  /// Threshold for shake detection. Must exceed normal walking/carrying.
  /// Typical values: walking ~6-8, running ~10-12, shake ~15-20.
  static const double _shakeThreshold = 17.0;

  /// Minimum individual shake magnitude to avoid false positives from jitter.
  static const double _minShakeMagnitude = 14.0;

  /// Time window for shake detection (ms)
  static const int _shakeTimeWindow = 2000;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  final List<DateTime> _shakeTimestamps = [];
  Function(int)? _onShakeDetected;
  int _requiredShakeCount = 3;
  DateTime? _lastTriggerTime;

  void startShakeDetection({
    required Function(int) onShakeDetected,
    int requiredShakeCount = 3,
  }) {
    _onShakeDetected = onShakeDetected;
    _requiredShakeCount = requiredShakeCount;

    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      _handleAccelerometerEvent(event);
    });
  }

  void stopShakeDetection() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _shakeTimestamps.clear();
    _lastTriggerTime = null;
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    // Calculate the magnitude of acceleration
    double magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    // Require minimum magnitude per shake to avoid jitter
    if (magnitude < _minShakeMagnitude) return;

    // Check if magnitude exceeds shake threshold
    if (magnitude > _shakeThreshold) {
      DateTime now = DateTime.now();
      _shakeTimestamps.add(now);

      // Remove old shake timestamps outside the time window
      _shakeTimestamps.removeWhere(
        (timestamp) =>
            now.difference(timestamp).inMilliseconds > _shakeTimeWindow,
      );

      // Check if we have enough shakes within the time window
      if (_shakeTimestamps.length >= _requiredShakeCount &&
          (_lastTriggerTime == null ||
              now.difference(_lastTriggerTime!).inSeconds > 60)) {
        _lastTriggerTime = now;
        _shakeTimestamps.clear();
        _onShakeDetected?.call(_requiredShakeCount);
      }
    }
  }

  bool get isListening => _accelerometerSubscription != null;
}
