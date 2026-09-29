import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../models/contact.dart';
import '../services/storage_service.dart';

/// Screen for managing trusted emergency contacts
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final StorageService _storageService = StorageService();
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await _storageService.getContacts();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error loading contacts: $e');
    }
  }

  void _showAddContactDialog([Contact? existingContact]) {
    final nameController = TextEditingController(
      text: existingContact?.name ?? '',
    );
    final phoneController = TextEditingController(
      text: existingContact?.phoneNumber ?? '',
    );
    final isEditing = existingContact != null;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: Text(
          isEditing ? 'Edit Contact' : 'Add Trusted Contact',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameController, 'Name', Icons.person_outline),
            const SizedBox(height: 16),
            _field(
              phoneController,
              'Phone Number',
              Icons.phone_outlined,
              hint: '+1234567890',
              keyboard: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.lime,
              foregroundColor: AppTheme.charcoal,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();

              if (name.isEmpty || phone.isEmpty) {
                _showErrorSnackBar('Please fill in all fields');
                return;
              }

              try {
                if (isEditing) {
                  await _storageService.updateContact(
                    existingContact.copyWith(name: name, phoneNumber: phone),
                  );
                } else {
                  await _storageService.addContact(
                    Contact(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                      phoneNumber: phone,
                      createdAt: DateTime.now(),
                    ),
                  );
                }
                if (mounted) Navigator.pop(dialogContext);
                _loadContacts();
                _showSuccessSnackBar(
                  isEditing ? 'Contact updated' : 'Contact added',
                );
              } catch (e) {
                _showErrorSnackBar('Error saving contact: $e');
              }
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.grey),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: AppTheme.lime, width: 2),
        ),
      ),
    );
  }

  void _deleteContact(Contact contact) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: const Text(
          'Delete Contact',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text('Are you sure you want to delete ${contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
            ),
            onPressed: () async {
              try {
                await _storageService.deleteContact(contact.id);
                if (mounted) Navigator.pop(dialogContext);
                _loadContacts();
                _showSuccessSnackBar('Contact deleted');
              } catch (e) {
                _showErrorSnackBar('Error deleting contact: $e');
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.charcoal,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.lime))
          : _contacts.isEmpty
          ? _buildEmptyState()
          : _buildContactsList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddContactDialog(),
        backgroundColor: AppTheme.lime,
        foregroundColor: AppTheme.charcoal,
        icon: const Icon(Icons.add),
        label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.limeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.contacts_outlined,
              size: 64,
              color: AppTheme.limeDark,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No trusted contacts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add emergency contacts who will receive\nalerts when you need help',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            boxShadow: AppTheme.softShadow,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppTheme.limeGradient,
                shape: BoxShape.circle,
              ),
              child: Text(
                contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.charcoal,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            title: Text(
              contact.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoal,
              ),
            ),
            subtitle: Text(
              contact.phoneNumber,
              style: const TextStyle(color: AppTheme.grey),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.grey),
              onSelected: (value) {
                if (value == 'edit') {
                  _showAddContactDialog(contact);
                } else if (value == 'delete') {
                  _deleteContact(contact);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: AppTheme.charcoal),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: AppTheme.danger),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppTheme.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
