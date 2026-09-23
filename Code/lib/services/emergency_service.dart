import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/contact.dart';
import '../models/emergency_record.dart';
import 'location_service.dart';
import 'sms_service.dart';
import 'storage_service.dart';

/// Outcome of an SOS trigger attempt.
enum EmergencyResult {
  /// SMS was dispatched to at least one contact.
  sent,

  /// Suppressed because we are still inside the cooldown window.
  cooldown,

  /// No trusted contacts are configured.
  noContacts,

  /// The message could not be sent (no SIM / SMS capability).
  smsUnavailable,
}

/// Core, offline-first emergency handler.
///
/// This is deliberately self-contained and dependency-light so it can run
/// from BOTH the UI isolate and the background foreground-service isolate.
/// It never touches the internet or Firebase: location comes from GPS and the
/// alert is delivered over cellular SMS via [SmsService].
class EmergencyService {
  static final StorageService _storage = StorageService();

  /// Minimum time between two SOS incidents. Repeated shakes inside this window
  /// are ignored so a single incident does not fire multiple SMS bursts.
  static const Duration cooldown = Duration(seconds: 60);

  /// Trigger an emergency alert. Silent, automatic, no user interaction.
  ///
  /// Steps:
  ///   1. Debounce against the shared cooldown.
  ///   2. Load trusted contacts (local storage).
  ///   3. Get the best available GPS fix (best-effort, may be null).
  ///   4. Build the message.
  ///   5. Send SMS automatically to every contact via SmsManager.
  ///   6. Persist a local history record.
  static Future<EmergencyResult> triggerEmergencyAlert(
    String triggerType,
  ) async {
    try {
      // 1. Cooldown / debounce.
      final last = await _storage.getLastTriggerTime();
      if (last != null && DateTime.now().difference(last) < cooldown) {
        return EmergencyResult.cooldown;
      }
      // Claim the cooldown slot up-front so concurrent triggers (e.g. shake +
      // secret pattern firing together) cannot double-send.
      await _storage.setLastTriggerTime(DateTime.now());

      // 2. Contacts.
      final List<Contact> contacts = await _storage.getContacts();
      if (contacts.isEmpty) {
        await _saveHistory(
          triggerType: triggerType,
          message: '',
          position: null,
          contactCount: 0,
          deliveredCount: 0,
          status: 'No trusted contacts configured',
        );
        return EmergencyResult.noContacts;
      }

      // 3. Best available location (best-effort; never blocks the send).
      final Position? position = await LocationService.getBestLocation();

      // 4. Message.
      final baseMessage = await _storage.getAlertMessage();
      final fullMessage = _composeMessage(
        baseMessage: baseMessage,
        triggerType: triggerType,
        position: position,
        timestamp: DateTime.now(),
      );

      // 5. Guard against a device that cannot send SMS at all.
      final capable = await SmsService.isSmsCapable();
      final hasSim = await SmsService.hasReadySim();
      if (!capable || !hasSim) {
        await _saveHistory(
          triggerType: triggerType,
          message: fullMessage,
          position: position,
          contactCount: contacts.length,
          deliveredCount: 0,
          status: !hasSim
              ? 'No SIM / SMS unavailable'
              : 'Device not SMS capable',
        );
        return EmergencyResult.smsUnavailable;
      }

      // 6. Auto-send to everyone.
      final results = await SmsService.sendToAll(
        phoneNumbers: contacts.map((c) => c.phoneNumber).toList(),
        message: fullMessage,
      );
      final delivered = results.where((r) => r.success).length;

      await _saveHistory(
        triggerType: triggerType,
        message: fullMessage,
        position: position,
        contactCount: contacts.length,
        deliveredCount: delivered,
        status:
            'Sent to $delivered/${contacts.length} contacts'
            '${position == null ? ' (no location)' : ''}',
      );

      return EmergencyResult.sent;
    } catch (e) {
      // Never let the emergency path throw. Record what we can.
      await _saveHistory(
        triggerType: triggerType,
        message: '',
        position: null,
        contactCount: 0,
        deliveredCount: 0,
        status: 'Error: $e',
      );
      return EmergencyResult.smsUnavailable;
    }
  }

  static String _composeMessage({
    required String baseMessage,
    required String triggerType,
    required Position? position,
    required DateTime timestamp,
  }) {
    final buffer = StringBuffer(baseMessage);
    buffer.write('\nTime: ${_formatDateTime(timestamp)}');
    if (position != null) {
      buffer.write('\nLocation: ${LocationService.getGoogleMapsUrl(position)}');
    } else {
      buffer.write('\nLocation: unavailable');
    }
    return buffer.toString();
  }

  static Future<void> _saveHistory({
    required String triggerType,
    required String message,
    required Position? position,
    required int contactCount,
    required int deliveredCount,
    required String status,
  }) async {
    try {
      await _storage.addHistoryRecord(
        EmergencyRecord(
          id: _generateId(),
          timestamp: DateTime.now(),
          triggerType: triggerType,
          latitude: position?.latitude,
          longitude: position?.longitude,
          message: message,
          contactCount: contactCount,
          deliveredCount: deliveredCount,
          status: status,
        ),
      );
    } catch (_) {
      // History is best-effort; swallow persistence failures.
    }
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(1000)}';
  }

  /// Test the full emergency system (used by the Settings screen).
  static Future<EmergencyResult> testEmergencySystem() async {
    return triggerEmergencyAlert('Test Trigger');
  }
}
