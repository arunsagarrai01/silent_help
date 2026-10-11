import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../models/contact.dart';
import '../services/storage_service.dart';
import '../services/voice_sos_controller.dart';
import '../services/firestore_sync_service.dart';

/// Screen for managing trusted emergency contacts.
///
/// Performance notes:
///  - Contacts are the single source of truth in memory (`_contacts`). CRUD
///    updates the list optimistically and persists in the background, so the
///    UI never shows a full-screen spinner after the first load.
///  - List items are `const`-friendly and keyed so Flutter can reuse elements.
///  - Cloud backup (Firestore) and the native voice-service config are refreshed
///    in the background — never blocking the UI.
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
      _showSnack('Error loading contacts: $e', AppTheme.danger);
    }
  }

  /// Persist current list + propagate to voice service and cloud in background.
  void _persistAndSync() {
    // Fire-and-forget; UI already updated optimistically.
    _storageService.saveContacts(_contacts);
    VoiceSosController.instance.refreshConfig();
    FirestoreSyncService.instance.pushContacts();
  }

  Future<void> _saveContact({
    Contact? existing,
    required String name,
    required String phone,
  }) async {
    setState(() {
      if (existing != null) {
        final i = _contacts.indexWhere((c) => c.id == existing.id);
        if (i != -1) {
          _contacts[i] = existing.copyWith(name: name, phoneNumber: phone);
        }
      } else {
        _contacts = [
          ..._contacts,
          Contact(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            phoneNumber: phone,
            createdAt: DateTime.now(),
          ),
        ];
      }
    });
    _persistAndSync();
    _showSnack(
      existing != null ? 'Contact updated' : 'Contact added',
      AppTheme.success,
    );
  }

  void _removeContact(Contact contact) {
    setState(
      () => _contacts = _contacts.where((c) => c.id != contact.id).toList(),
    );
    _persistAndSync();
    _showSnack('Contact deleted', AppTheme.success);
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
            onPressed: () {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                _showSnack('Please fill in all fields', AppTheme.danger);
                return;
              }
              Navigator.pop(dialogContext);
              _saveContact(existing: existingContact, name: name, phone: phone);
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

  void _confirmDelete(Contact contact) {
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
            onPressed: () {
              Navigator.pop(dialogContext);
              _removeContact(contact);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
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
          ? const _EmptyState()
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

  Widget _buildContactsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _contacts.length,
      // Reuse elements efficiently; items are keyed by contact id.
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return _ContactCard(
          key: ValueKey(contact.id),
          contact: contact,
          onEdit: () => _showAddContactDialog(contact),
          onDelete: () => _confirmDelete(contact),
        );
      },
    );
  }
}

/// Extracted const-friendly empty state so it is not rebuilt with the list.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
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
}

/// A single contact row. Stateless + keyed so the list rebuilds cheaply.
class _ContactCard extends StatelessWidget {
  final Contact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactCard({
    super.key,
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
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
              onEdit();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20, color: AppTheme.charcoal),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
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
  }
}
