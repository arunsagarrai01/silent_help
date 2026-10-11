import 'package:geolocator/geolocator.dart';

/// Location service for getting current GPS coordinates
class LocationService {
  /// Best-effort location for the emergency path.
  ///
  /// Tries a fresh high-accuracy fix, but falls back to the last known
  /// position if GPS is slow or unavailable. Returns `null` only when nothing
  /// is obtainable. Never throws.
  static Future<Position?> getBestLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return await _lastKnown();
      }

      final hasAlways =
          await Geolocator.checkPermission() == LocationPermission.always;

      final accuracy = hasAlways
          ? LocationAccuracy.high
          : LocationAccuracy.medium;
      final timeLimit = hasAlways
          ? const Duration(seconds: 8)
          : const Duration(seconds: 5);

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
          timeLimit: timeLimit,
        );
      } catch (_) {
        final cached = await _lastKnown();
        if (cached != null) return cached;
        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 3),
          );
        } catch (_) {
          return null;
        }
      }
    } catch (_) {
      return await _lastKnown();
    }
  }

  static Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// FAST location for the emergency path: returns the last-known fix
  /// immediately (no GPS wait), and only attempts a fresh fix with a hard 2s
  /// cap. This guarantees SMS is never delayed more than ~2 seconds by GPS.
  static Future<Position?> getFastLocation() async {
    // 1. Instant cached fix (returns right away on virtually all devices).
    final cached = await _lastKnown();

    // 2. Try a very short fresh fix, but never block beyond 2 seconds.
    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 2),
      ).timeout(const Duration(seconds: 2));
      return fresh;
    } catch (_) {
      // Fall back to whatever we had instantly.
      return cached;
    }
  }

  static Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> requestLocationPermission() async {
    return true;
  }

  static String formatLocation(Position position) {
    return 'Lat: ${position.latitude.toStringAsFixed(6)}, '
        'Lng: ${position.longitude.toStringAsFixed(6)}';
  }

  static String getGoogleMapsUrl(Position position) {
    return 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
  }
}
