import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_models.dart';
import '../models/emergency_record.dart';
import 'firebase_service.dart';
import 'storage_service.dart';

/// Offline-first synchronisation of local emergency history to Firestore.
///
/// Flow (secondary to the local SMS path):
///   Local SOS -> local history saved (already done by EmergencyService)
///   -> if internet + Firebase ready -> sync pending records
///   -> if offline -> keep locally, sync when connectivity returns.
///
/// Idempotency: the local record id is used as the Firestore document id, and
/// we track synced ids locally, so re-running sync never creates duplicates.
class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  static const String _syncedIdsKey = 'synced_event_ids';

  final StorageService _storage = StorageService();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _syncing = false;

  /// Start watching connectivity and sync opportunistically.
  Future<void> start() async {
    if (!FirebaseService.instance.ready) return;
    await FirebaseService.instance.ensureSignedIn();
    // Initial attempt.
    unawaited(syncPending());
    // React to connectivity changes.
    _sub ??= _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(syncPending());
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Push any local records not yet synced. Safe to call repeatedly.
  Future<void> syncPending() async {
    if (_syncing) return;
    final fb = FirebaseService.instance;
    if (!fb.ready || fb.db == null) return;

    // Require connectivity.
    final conn = await _connectivity.checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) return;

    final user = await fb.ensureSignedIn();
    if (user == null) return;

    _syncing = true;
    try {
      final history = await _storage.getHistory();
      final synced = await _loadSyncedIds();
      final pending = history.where((r) => !synced.contains(r.id)).toList();
      if (pending.isEmpty) return;

      final col = fb.db!.collection('emergencyEvents');
      for (final EmergencyRecord r in pending) {
        final event = CloudEmergencyEvent(
          id: r.id,
          ownerUid: user.uid,
          triggerType: r.triggerType,
          timestamp: r.timestamp,
          latitude: r.latitude,
          longitude: r.longitude,
          contactCount: r.contactCount,
          deliveredCount: r.deliveredCount,
          status: r.status,
        );
        // Doc id == local id => idempotent. merge:false is fine because the id
        // is unique per incident; re-writes are harmless and rare.
        await col.doc(r.id).set(event.toMap());
        synced.add(r.id);
      }
      await _saveSyncedIds(synced);
      debugPrint('FirestoreSync: synced ${pending.length} event(s).');
    } catch (e) {
      // Offline writes are queued by Firestore's own cache; our id-tracking
      // prevents duplicates on retry. Swallow errors — never break the app.
      debugPrint('FirestoreSync error: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<Set<String>> _loadSyncedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_syncedIdsKey) ?? const []).toSet();
  }

  Future<void> _saveSyncedIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    // Cap to avoid unbounded growth.
    final list = ids.toList();
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }
    await prefs.setStringList(_syncedIdsKey, list);
  }
}
