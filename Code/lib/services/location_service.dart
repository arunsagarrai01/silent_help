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
