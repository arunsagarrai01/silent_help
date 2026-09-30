import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/cloud_models.dart';

/// Central Firebase bootstrap + auth for SilentHelp.
///
/// IMPORTANT: Firebase is a SECONDARY layer. Initialization is fully guarded —
/// if Firebase is not configured (placeholder keys / missing google-services),
/// [ready] stays false and the whole app keeps working with local-only SOS.
/// Nothing here is ever on the critical SMS path.
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  bool _ready = false;
  bool get ready => _ready;

  FirebaseFirestore? _db;
  FirebaseFirestore? get db => _db;

  User? get currentUser => _ready ? FirebaseAuth.instance.currentUser : null;
  String? get uid => currentUser?.uid;

  /// Initialise Firebase. Never throws; returns whether it succeeded.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      final options = DefaultFirebaseOptions.currentPlatform;
      // Guard: refuse to init with the placeholder keys.
      if (options.apiKey == 'REPLACE_ME') {
        debugPrint(
          'FirebaseService: not configured (placeholder keys). '
          'Run `flutterfire configure`. Running local-only.',
        );
        return false;
      }

      await Firebase.initializeApp(options: options); //Firebase Initialize

      // App Check — reduces unauthorised backend access.
      await FirebaseAppCheck.instance.activate(
        androidProvider: kReleaseMode
            ? AndroidProvider.playIntegrity
            : AndroidProvider.debug,
        appleProvider: kReleaseMode
            ? AppleProvider.appAttest
            : AppleProvider.debug,
      );

      // Firestore offline persistence (default on mobile, set explicitly).
      _db = FirebaseFirestore.instance;
      _db!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      _ready = true;
      return true;
    } catch (e) {
      debugPrint('FirebaseService init failed (local-only mode): $e');
      _ready = false;
      return false;
    }
  }

  /// Ensure we have a signed-in user. Uses anonymous auth so the emergency
  /// features work without forcing account creation. Never throws.
  Future<User?> ensureSignedIn() async {
    if (!_ready) return null;
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) return auth.currentUser;
      final cred = await auth.signInAnonymously();
      return cred.user;
    } catch (e) {
      debugPrint('ensureSignedIn failed: $e');
      return null;
    }
  }

  /// Upgrade an anonymous account to email/password (optional flow).
  Future<User?> linkEmail(String email, String password) async {
    if (!_ready) return null;
    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final user = await FirebaseAuth.instance.currentUser?.linkWithCredential(
        cred,
      );
      return user?.user;
    } catch (e) {
      debugPrint('linkEmail failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    if (!_ready) return;
    await FirebaseAuth.instance.signOut();
  }

  /// Read the current user's role from custom claims (server-controlled).
  /// Clients cannot elevate this; it is only set by a Cloud Function/admin.
  Future<UserRole> currentRole() async {
    if (!_ready) return UserRole.user;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      final role = token?.claims?['role'] as String?;
      return UserRoleName.fromString(role);
    } catch (_) {
      return UserRole.user;
    }
  }
}
