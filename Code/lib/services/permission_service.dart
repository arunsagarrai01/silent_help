import 'package:permission_handler/permission_handler.dart';

/// Centralised runtime-permission handling for the emergency features.
///
/// The critical SOS path needs SMS + location. Background monitoring
/// additionally benefits from notification and background-location grants.
class PermissionService {
  PermissionService._();

  /// Request the permissions required to arm the emergency system.
  ///
  /// Returns a map so the UI can explain exactly what is missing. Nothing here
  /// throws; a denied permission simply reports `false`.
  static Future<Map<String, bool>> requestCorePermissions() async {
    final results = <String, bool>{};

    // SMS - mandatory for the automatic alert.
    results['sms'] = await _request(Permission.sms);

    // Location - "while in use" first (required before background can be asked
    // on Android 10+).
    results['location'] = await _request(Permission.locationWhenInUse);

    // Notifications - needed on Android 13+ for the foreground-service
    // notification. Absent on older SDKs, where it resolves as granted.
    results['notification'] = await _request(Permission.notification);

    return results;
  }

  /// Request background location. Must be called AFTER foreground location is
  /// already granted, otherwise Android silently denies it.
  static Future<bool> requestBackgroundLocation() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) return false;
    return _request(Permission.locationAlways);
  }

  static Future<bool> hasSms() => Permission.sms.isGranted;

  static Future<bool> hasLocation() => Permission.locationWhenInUse.isGranted;

  static Future<bool> hasNotification() => Permission.notification.isGranted;

  /// True when the minimum needed to send an SOS is in place.
  static Future<bool> canRunEmergency() async {
    final sms = await Permission.sms.isGranted;
    final loc = await Permission.locationWhenInUse.isGranted;
    // Location is best-effort in the SOS flow, so SMS is the hard requirement.
    // We still report location so the UI can nudge the user.
    return sms && loc;
  }

  static Future<bool> _request(Permission permission) async {
    try {
      final status = await permission.status;
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return false;
      final result = await permission.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Open the OS app-settings page (for permanently denied permissions).
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
