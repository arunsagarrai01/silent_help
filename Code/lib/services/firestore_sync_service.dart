import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cloud_models.dart';
import '../models/contact.dart';
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
    // Restore contacts from cloud if this device has none locally.
    unawaited(restoreContactsIfEmpty());
    // Initial attempt (events + contacts).
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

    // Mirror the current contact list to the cloud (best-effort).
    unawaited(pushContacts());
  }

  // --------------------------------------------------------------------------
  // Trusted contacts cloud backup (local stays authoritative)
  // --------------------------------------------------------------------------

  /// Upsert all local contacts to Firestore and remove cloud docs that no
  /// longer exist locally. Idempotent (doc id == local contact id).
  Future<void> pushContacts() async {
    final fb = FirebaseService.instance;
    if (!fb.ready || fb.db == null) return;
    final conn = await _connectivity.checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) return;
    final user = await fb.ensureSignedIn();
    if (user == null) return;

    try {
      final local = await _storage.getContacts();
      final col = fb.db!.collection('trustedContacts');

      // Upsert local contacts owned by this user.
      final batch = fb.db!.batch();
      final localIds = <String>{};
      for (final c in local) {
        localIds.add(c.id);
        final cloud = CloudContact(
          id: c.id,
          ownerUid: user.uid,
          name: c.name,
          phone: c.phoneNumber,
          updatedAt: DateTime.now(),
        );
        batch.set(col.doc(c.id), cloud.toMap());
      }
      await batch.commit();

      // Delete cloud contacts that were removed locally.
      final remote = await col.where('ownerUid', isEqualTo: user.uid).get();
      final deletions = fb.db!.batch();
      var hasDeletions = false;
      for (final doc in remote.docs) {
        if (!localIds.contains(doc.id)) {
          deletions.delete(doc.reference);
          hasDeletions = true;
        }
      }
      if (hasDeletions) await deletions.commit();
    } catch (e) {
      debugPrint('pushContacts error: $e');
    }
  }

  /// If local storage has no contacts (e.g. fresh install) but the cloud has
  /// some for this user, restore them locally.
  Future<void> restoreContactsIfEmpty() async {
    final fb = FirebaseService.instance;
    if (!fb.ready || fb.db == null) return;
    final conn = await _connectivity.checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) return;
    final user = await fb.ensureSignedIn();
    if (user == null) return;

    try {
      final local = await _storage.getContacts();
      if (local.isNotEmpty) return; // local is authoritative; don't overwrite.

      final remote = await fb.db!
          .collection('trustedContacts')
          .where('ownerUid', isEqualTo: user.uid)
          .get();
      if (remote.docs.isEmpty) return;

      final restored = remote.docs.map((d) {
        final cc = CloudContact.fromMap(d.data());
        return Contact(
          id: cc.id,
          name: cc.name,
          phoneNumber: cc.phone,
          createdAt: cc.updatedAt,
        );
      }).toList();

      await _storage.saveContacts(restored);
      debugPrint('FirestoreSync: restored ${restored.length} contact(s).');
    } catch (e) {
      debugPrint('restoreContactsIfEmpty error: $e');
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
