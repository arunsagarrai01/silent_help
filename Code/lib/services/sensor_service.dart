import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Sensor service for detecting shake gestures
class SensorService {
  static const double _shakeThreshold = 12.0;
  static const int _shakeTimeWindow = 1000; // milliseconds
  
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  final List<DateTime> _shakeTimestamps = [];
  Function(int)? _onShakeDetected;
  int _requiredShakeCount = 3;  

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
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    // Calculate the magnitude of acceleration
    double magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z
    );

    // Check if magnitude exceeds shake threshold
    if (magnitude > _shakeThreshold) {
      DateTime now = DateTime.now();
      _shakeTimestamps.add(now);

      // Remove old shake timestamps outside the time window
      _shakeTimestamps.removeWhere((timestamp) =>
          now.difference(timestamp).inMilliseconds > _shakeTimeWindow);

      // Check if we have enough shakes within the time window
      if (_shakeTimestamps.length >= _requiredShakeCount) {
        _onShakeDetected?.call(_shakeTimestamps.length);
        _shakeTimestamps.clear(); // Reset after detection
      }
    }
  }

  bool get isListening => _accelerometerSubscription != null;
}