/// Cloud (Firestore) data models for SilentHelp.
///
/// These mirror the minimal fields synced to Firestore. Sensitive data is kept
/// minimal: we store only coarse fields required for the emergency history and
/// contact notification. No continuous location history is stored.
library;

/// User roles. Privileged roles are assigned ONLY server-side (custom claims);
/// clients can never write these to their own profile.
enum UserRole { user, trustedContact, admin }

extension UserRoleName on UserRole {
  String get value => switch (this) {
    UserRole.user => 'user',
    UserRole.trustedContact => 'trusted_contact',
    UserRole.admin => 'admin',
  };

  static UserRole fromString(String? s) => switch (s) {
    'trusted_contact' => UserRole.trustedContact,
    'admin' => UserRole.admin,
    _ => UserRole.user,
  };
}

/// users/{uid}
class UserProfile {
  final String uid;
  final String? displayName;
  final String role; // read-only for clients; set via custom claims/functions

  UserProfile({required this.uid, this.displayName, this.role = 'user'});

  /// Fields a client is allowed to write. Note: `role` is NOT here.
  Map<String, dynamic> toClientMap() => {
    'displayName': displayName,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfile(
      uid: uid,
      displayName: map['displayName'] as String?,
      role: map['role'] as String? ?? 'user',
    );
  }
}

/// emergencyEvents/{eventId}
///
/// [id] is the idempotent local event id (also used as the Firestore doc id)
/// so re-syncing the same local record never creates duplicates.
class CloudEmergencyEvent {
  final String id;
  final String ownerUid;
  final String triggerType;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final int contactCount;
  final int deliveredCount;
  final String status;

  CloudEmergencyEvent({
    required this.id,
    required this.ownerUid,
    required this.triggerType,
    required this.timestamp,
    required this.contactCount,
    required this.deliveredCount,
    required this.status,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'ownerUid': ownerUid,
    'triggerType': triggerType,
    'timestamp': timestamp.toUtc().toIso8601String(),
    // Coarsen location to ~100m to minimise stored precision.
    if (latitude != null) 'lat': _coarsen(latitude!),
    if (longitude != null) 'lng': _coarsen(longitude!),
    'contactCount': contactCount,
    'deliveredCount': deliveredCount,
    'status': status,
    'source': 'mobile',
  };

  static double _coarsen(double v) => (v * 1000).roundToDouble() / 1000;
}

/// trustedContacts/{contactId}
///
/// Cloud backup of a trusted contact so the list survives reinstall / is
/// available across the owner's devices. The LOCAL copy remains authoritative
/// for the critical SOS path; this is a secondary mirror only.
///
/// [id] is the local contact id, reused as the Firestore doc id for idempotent
/// upserts (no duplicates on re-sync).
class CloudContact {
  final String id;
  final String ownerUid;
  final String name;
  final String phone;
  final DateTime updatedAt;

  CloudContact({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.phone,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'ownerUid': ownerUid,
    'name': name,
    'phone': phone,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory CloudContact.fromMap(Map<String, dynamic> map) {
    return CloudContact(
      id: map['id'] as String,
      ownerUid: map['ownerUid'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// notificationTokens/{tokenId}
class DeviceToken {
  final String token;
  final String platform;

  DeviceToken({required this.token, required this.platform});

  Map<String, dynamic> toMap() => {
    'token': token,
    'platform': platform,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
}
