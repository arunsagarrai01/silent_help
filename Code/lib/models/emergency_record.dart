/// A locally-stored record of a fired emergency incident.
///
/// This is the persisted history entry (distinct from the transient
/// [EmergencyAlert] used while composing a message).
class EmergencyRecord {
  final String id;
  final DateTime timestamp;
  final String triggerType;
  final double? latitude;
  final double? longitude;
  final String message;

  /// Contacts the alert was addressed to.
  final int contactCount;

  /// How many recipients the SMS was successfully handed to the radio for.
  final int deliveredCount;

  /// Human-readable outcome, e.g. "Sent to 2/3 contacts" or
  /// "No location available".
  final String status;

  EmergencyRecord({
    required this.id,
    required this.timestamp,
    required this.triggerType,
    required this.message,
    required this.contactCount,
    required this.deliveredCount,
    required this.status,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'triggerType': triggerType,
        'latitude': latitude,
        'longitude': longitude,
        'message': message,
        'contactCount': contactCount,
        'deliveredCount': deliveredCount,
        'status': status,
      };

  factory EmergencyRecord.fromJson(Map<String, dynamic> json) {
    return EmergencyRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      triggerType: json['triggerType'] as String? ?? 'Unknown',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      message: json['message'] as String? ?? '',
      contactCount: json['contactCount'] as int? ?? 0,
      deliveredCount: json['deliveredCount'] as int? ?? 0,
      status: json['status'] as String? ?? '',
    );
  }
}
