import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
      final permission = await Geolocator.checkPermission();
      final permitted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (!serviceEnabled || !permitted) {
        // Even without a live service we may have a cached fix.
        return await _lastKnown();
      }

      // Kick off a fresh fix but cap the wait so the SOS never stalls.
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {
        // Timeout or transient error: fall back to the last known position.
        final cached = await _lastKnown();
        if (cached != null) return cached;
        // Last resort: a quick, lower-accuracy attempt.
        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          return null;
        }
      }
    } catch (e) {
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
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      return null;
    }
  }

  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status == PermissionStatus.granted;
  }

  static String formatLocation(Position position) {
    return 'Lat: ${position.latitude.toStringAsFixed(6)}, '
        'Lng: ${position.longitude.toStringAsFixed(6)}';
  }

  static String getGoogleMapsUrl(Position position) {
    return 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
  }
}
