import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';
import '../models/emergency_record.dart';

/// Local storage service for app data.
///
/// All state here is persisted with [SharedPreferences], which is backed by a
/// single file shared across isolates on Android. That lets the background
/// foreground-service isolate read contacts / the alert message and share the
/// SOS cooldown timestamp with the UI isolate.
class StorageService {
  static const String _contactsKey = 'trusted_contacts';
  static const String _secretPatternKey = 'secret_pattern';
  static const String _shakeCountKey = 'shake_count';
  static const String _alertMessageKey = 'alert_message';
  static const String _historyKey = 'emergency_history';
  static const String _lastTriggerKey = 'last_sos_trigger_ms';
  static const String _monitoringEnabledKey = 'monitoring_enabled';

  /// Max history entries to retain locally.
  static const int _maxHistory = 50;

  // Contacts management
  Future<List<Contact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getString(_contactsKey);

    if (contactsJson == null) return [];

    final List<dynamic> contactsList = json.decode(contactsJson);
    return contactsList.map((json) => Contact.fromJson(json)).toList();
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = json.encode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_contactsKey, contactsJson);
  }

  Future<void> addContact(Contact contact) async {
    final contacts = await getContacts();
    contacts.add(contact);
    await saveContacts(contacts);
  }

  Future<void> updateContact(Contact updatedContact) async {
    final contacts = await getContacts();
    final index = contacts.indexWhere((c) => c.id == updatedContact.id);
    if (index != -1) {
      contacts[index] = updatedContact;
      await saveContacts(contacts);
    }
  }

  Future<void> deleteContact(String contactId) async {
    final contacts = await getContacts();
    contacts.removeWhere((c) => c.id == contactId);
    await saveContacts(contacts);
  }

  // Settings management
  Future<String> getSecretPattern() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_secretPatternKey) ?? '123==';
  }

  Future<void> setSecretPattern(String pattern) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_secretPatternKey, pattern);
  }

  Future<int> getShakeCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_shakeCountKey) ?? 3;
  }

  Future<void> setShakeCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shakeCountKey, count);
  }

  Future<String> getAlertMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_alertMessageKey) ??
        'Emergency! I need help. This is an automated message from SilentHelp.';
  }

  Future<void> setAlertMessage(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alertMessageKey, message);
  }

  // Background monitoring toggle
  Future<bool> isMonitoringEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_monitoringEnabledKey) ?? false;
  }

  Future<void> setMonitoringEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monitoringEnabledKey, enabled);
  }

  // SOS cooldown / debounce
  //
  // Stored as epoch-millis of the last successful trigger so both the UI and
  // background isolates agree on whether we are still inside the cooldown.
  Future<DateTime?> getLastTriggerTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastTriggerKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastTriggerTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    // Ensure the write is visible to the other isolate immediately.
    await prefs.reload();
    await prefs.setInt(_lastTriggerKey, time.millisecondsSinceEpoch);
  }

  // Emergency history (local only)
  Future<List<EmergencyRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final List<dynamic> list = json.decode(raw);
      return list
          .map((e) => EmergencyRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistoryRecord(EmergencyRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final history = await getHistory();
    history.insert(0, record); // newest first
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }
    final encoded = json.encode(history.map((r) => r.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
