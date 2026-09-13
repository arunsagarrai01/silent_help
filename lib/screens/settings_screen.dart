import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/emergency_service.dart';

/// Settings screen for emergency triggers and app configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storageService = StorageService();
  
  String _secretPattern = '123==';
  int _shakeCount = 3;
  String _alertMessage = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final pattern = await _storageService.getSecretPattern();
      final shakeCount = await _storageService.getShakeCount();
      final message = await _storageService.getAlertMessage();
      
      setState(() {
        _secretPattern = pattern;
        _shakeCount = shakeCount;
        _alertMessage = message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error loading settings: $e');
    }
  }

  void _showSecretPatternDialog() {
    final controller = TextEditingController(text: _secretPattern);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Secret Calculator Pattern'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Pattern (e.g., 123==)',
                border: OutlineInputBorder(),
                hintText: 'Enter sequence of numbers and operators',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Enter a sequence that will trigger emergency alert when typed in calculator. Use numbers, +, -, ×, ÷, and = symbols.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final pattern = controller.text.trim();
              if (pattern.isNotEmpty) {
                await _storageService.setSecretPattern(pattern);
                setState(() {
                  _secretPattern = pattern;
                });
                Navigator.pop(context);
                _showSuccessSnackBar('Secret pattern updated');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showShakeCountDialog() {
    int tempShakeCount = _shakeCount;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Shake Detection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Number of shakes required to trigger emergency:'),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setDialogState) => Column(
                children: [
                  Slider(
                    value: tempShakeCount.toDouble(),
                    min: 2,
                    max: 10,
                    divisions: 8,
                    label: tempShakeCount.toString(),
                    onChanged: (value) {
                      setDialogState(() {
                        tempShakeCount = value.round();
                      });
                    },
                  ),
                  Text(
                    '$tempShakeCount shakes',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _storageService.setShakeCount(tempShakeCount);
              setState(() {
                _shakeCount = tempShakeCount;
              });
              Navigator.pop(context);
              _showSuccessSnackBar('Shake count updated');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAlertMessageDialog() {
    final controller = TextEditingController(text: _alertMessage);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Alert Message'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
            hintText: 'Enter the message to send in emergencies...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final message = controller.text.trim();
              if (message.isNotEmpty) {
                await _storageService.setAlertMessage(message);
                setState(() {
                  _alertMessage = message;
                });
                Navigator.pop(context);
                _showSuccessSnackBar('Alert message updated');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _testEmergencySystem() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Emergency System'),
        content: const Text(
          'This will trigger a test emergency alert to all your trusted contacts. '
          'Are you sure you want to continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await EmergencyService.testEmergencySystem();
              _showSuccessSnackBar('Test alert sent');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Send Test'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Emergency Triggers'),
                _buildSettingCard(
                  icon: Icons.calculate,
                  title: 'Secret Calculator Pattern',
                  subtitle: 'Current: $_secretPattern',
                  onTap: _showSecretPatternDialog,
                ),
                _buildSettingCard(
                  icon: Icons.vibration,
                  title: 'Shake Detection',
                  subtitle: 'Trigger after $_shakeCount shakes',
                  onTap: _showShakeCountDialog,
                ),
                
                const SizedBox(height: 24),
                _buildSectionHeader('Alert Configuration'),
                _buildSettingCard(
                  icon: Icons.message,
                  title: 'Emergency Message',
                  subtitle: _alertMessage.length > 50 
                      ? '${_alertMessage.substring(0, 50)}...'
                      : _alertMessage,
                  onTap: _showAlertMessageDialog,
                ),
                
                const SizedBox(height: 24),
                _buildSectionHeader('Testing'),
                _buildSettingCard(
                  icon: Icons.bug_report,
                  title: 'Test Emergency System',
                  subtitle: 'Send a test alert to all contacts',
                  onTap: _testEmergencySystem,
                  iconColor: Colors.orange,
                ),
                
                const SizedBox(height: 24),
                _buildInfoCard(),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? Colors.blue,
          size: 28,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'How It Works',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '• Calculator Pattern: Enter the secret sequence in the calculator to trigger emergency\n'
              '• Shake Detection: Shake your phone the specified number of times\n'
              '• All triggers work silently without changing the calculator display\n'
              '• Emergency alerts include your location and timestamp',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}