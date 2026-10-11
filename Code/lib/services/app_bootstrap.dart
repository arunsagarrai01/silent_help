import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';
import 'firestore_sync_service.dart';
import 'messaging_service.dart';

/// Initialises the optional Firebase cloud layer AFTER the app is running.
///
/// This is deliberately best-effort and non-blocking: if Firebase is not
/// configured or the device is offline, the app still runs with full local SOS
/// capability. Nothing here touches the critical SMS path.
class AppBootstrap {
  AppBootstrap._();

  /// Core Firebase init. Awaited in main() BEFORE runApp so Firebase is ready
  /// when the first screen builds. Never throws; returns whether Firebase came
  /// up. If false, the app runs fully in local-only mode.
  static Future<bool> initCore() async {
    try {
      return await FirebaseService.instance.init();
    } catch (e) {
      debugPrint('AppBootstrap.initCore failed (local-only): $e');
      return false;
    }
  }

  /// Secondary services (auth, Crashlytics, FCM, sync). Fire-and-forget AFTER
  /// runApp so they never delay first frame. Safe no-op if Firebase isn't up.
  static Future<void> initServices() async {
    if (!FirebaseService.instance.ready) return; // local-only
    try {
      // Crashlytics — capture Flutter + platform errors (no sensitive data).
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseService.instance.ensureSignedIn();

      unawaited(MessagingService.instance.start());
      unawaited(FirestoreSyncService.instance.start());
    } catch (e) {
      debugPrint('AppBootstrap.initServices failed (local-only): $e');
    }
  }
}
