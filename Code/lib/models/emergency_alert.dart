/// Emergency alert data model
class EmergencyAlert {
  final String id;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String triggerType;
  final String message;
  final bool sent;

  EmergencyAlert({
    required this.id,
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.triggerType,
    required this.message,
    this.sent = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'triggerType': triggerType,
      'message': message,
      'sent': sent,
    };
  }

  factory EmergencyAlert.fromJson(Map<String, dynamic> json) {
    return EmergencyAlert(
      id: json['id'],
      timestamp: DateTime.parse(json['timestamp']),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      triggerType: json['triggerType'],
      message: json['message'],
      sent: json['sent'] ?? false,
    );
  }
}