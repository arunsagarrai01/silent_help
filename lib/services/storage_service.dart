import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';

/// Local storage service for app data
class StorageService {
  static const String _contactsKey = 'trusted_contacts';
  static const String _secretPatternKey = 'secret_pattern';
  static const String _shakeCountKey = 'shake_count';
  static const String _alertMessageKey = 'alert_message';

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
}