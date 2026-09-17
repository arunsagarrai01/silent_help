import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact.dart';
import '../models/emergency_alert.dart';
import 'location_service.dart';
import 'storage_service.dart';

/// Emergency service for handling SOS alerts
class EmergencyService {
  static final StorageService _storage = StorageService();

  /// Trigger emergency alert silently
  static Future<void> triggerEmergencyAlert(String triggerType) async {
    try {
      // Get current location
      Position? position = await LocationService.getCurrentLocation();
      
      // Get alert message
      String message = await _storage.getAlertMessage();
      
      // Create emergency alert
      EmergencyAlert alert = EmergencyAlert(
        id: _generateId(),
        timestamp: DateTime.now(),
        latitude: position?.latitude,
        longitude: position?.longitude,
        triggerType: triggerType,
        message: message,
      );

      // Send alerts to all trusted contacts
      await _sendAlertsToContacts(alert);
      
      print('Emergency alert triggered: $triggerType');
    } catch (e) {
      print('Error triggering emergency alert: $e');
    }
  }

  static Future<void> _sendAlertsToContacts(EmergencyAlert alert) async {
    List<Contact> contacts = await _storage.getContacts();
    
    for (Contact contact in contacts) {
      await _sendSMSAlert(contact, alert);
    }
  }

  static Future<void> _sendSMSAlert(Contact contact, EmergencyAlert alert) async {
    try {
      String locationText = '';
      if (alert.latitude != null && alert.longitude != null) {
        locationText = '\nLocation: ${LocationService.getGoogleMapsUrl(
          Position(
            latitude: alert.latitude!,
            longitude: alert.longitude!,
            timestamp: alert.timestamp,
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          )
        )}';
      }

      String fullMessage = '${alert.message}'
          '\nTime: ${_formatDateTime(alert.timestamp)}'
          '$locationText'
          '\n\nTriggered by: ${alert.triggerType}';

      // Create SMS URL
      String smsUrl = 'sms:${contact.phoneNumber}?body=${Uri.encodeComponent(fullMessage)}';
      
      if (await canLaunchUrl(Uri.parse(smsUrl))) {
        await launchUrl(Uri.parse(smsUrl));
      }
    } catch (e) {
      print('Error sending SMS to ${contact.name}: $e');
    }
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
           '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() + 
           Random().nextInt(1000).toString();
  }

  /// Test emergency system (for development)
  static Future<void> testEmergencySystem() async {
    await triggerEmergencyAlert('Test Trigger');
  }
}