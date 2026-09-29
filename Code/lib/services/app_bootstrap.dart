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

  /// Call once, after runApp. Never throws.
  static Future<void> initCloud() async {
    try {
      final ok = await FirebaseService.instance.init();
      if (!ok) return; // running local-only

      // Crashlytics — capture Flutter + platform errors (no sensitive data).
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await FirebaseService.instance.ensureSignedIn();

      // Secondary services (safe to run in background).
      unawaited(MessagingService.instance.start());
      unawaited(FirestoreSyncService.instance.start());
    } catch (e) {
      debugPrint('AppBootstrap.initCloud failed (local-only): $e');
    }
  }
}
