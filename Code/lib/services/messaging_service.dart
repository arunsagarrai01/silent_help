import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/cloud_models.dart';
import 'firebase_service.dart';

/// Background FCM handler. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep minimal: do NOT process sensitive data here. Non-critical only.
  debugPrint('FCM background message: ${message.messageId}');
}

/// Firebase Cloud Messaging wrapper.
///
/// FCM is used ONLY for non-critical notifications (alerting a logged-in
/// trusted device, status updates, account notices). It is NEVER a replacement
/// for the native SMS emergency path.
class MessagingService {
  MessagingService._();
  static final MessagingService instance = MessagingService._();

  /// Register token + handlers. Never throws.
  Future<void> start() async {
    final fb = FirebaseService.instance;
    if (!fb.ready) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permission (Android 13+, iOS).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Foreground messages.
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('FCM foreground: ${message.notification?.title}');
      });

      await _registerToken(messaging);
      messaging.onTokenRefresh.listen((token) => _saveToken(token));
    } catch (e) {
      debugPrint('MessagingService start failed: $e');
    }
  }

  Future<void> _registerToken(FirebaseMessaging messaging) async {
    try {
      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('getToken failed: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final fb = FirebaseService.instance;
    if (!fb.ready || fb.db == null) return;
    final user = await fb.ensureSignedIn();
    if (user == null) return;
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final dt = DeviceToken(token: token, platform: platform);
      // notificationTokens/{uid_token} keeps it owned + de-duplicated.
      await fb.db!
          .collection('notificationTokens')
          .doc('${user.uid}_$token')
          .set({'ownerUid': user.uid, ...dt.toMap()});
    } catch (e) {
      debugPrint('saveToken failed: $e');
    }
  }
}
