import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/emergency_service.dart';
import '../services/foreground_sos_service.dart';
import '../services/permission_service.dart';
import 'history_screen.dart';

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
  bool _monitoringEnabled = false;
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
      final monitoring = await ForegroundSosService.isRunning();

      setState(() {
        _secretPattern = pattern;
        _shakeCount = shakeCount;
        _alertMessage = message;
        _monitoringEnabled = monitoring;
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
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
              await ForegroundSosService.setShakeCount(tempShakeCount);
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

  Future<void> _toggleMonitoring(bool enable) async {
    if (enable) {
      // Ensure the critical permissions are granted before arming.
      final perms = await PermissionService.requestCorePermissions();
      if (perms['sms'] != true) {
        _showErrorSnackBar(
          'SMS permission is required to send emergency alerts.',
        );
        return;
      }
      if (perms['location'] != true) {
        _showErrorSnackBar(
          'Location permission recommended so alerts can include your position.',
        );
      }
      // Background location gives the best result while the screen is locked.
      await PermissionService.requestBackgroundLocation();

      final started = await ForegroundSosService.start();
      await _storageService.setMonitoringEnabled(started);
      setState(() => _monitoringEnabled = started);
      if (started) {
        _showSuccessSnackBar('Background monitoring enabled');
      } else {
        _showErrorSnackBar('Could not start background monitoring');
      }
    } else {
      await ForegroundSosService.stop();
      await _storageService.setMonitoringEnabled(false);
      setState(() => _monitoringEnabled = false);
      _showSuccessSnackBar('Background monitoring disabled');
    }
  }

  void _testEmergencySystem() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Emergency System'),
        content: const Text(
          'This will trigger a test emergency alert to all your trusted contacts. '
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await PermissionService.requestCorePermissions();
              final result = await EmergencyService.testEmergencySystem();
              switch (result) {
                case EmergencyResult.sent:
                  _showSuccessSnackBar('Test alert sent to contacts');
                  break;
                case EmergencyResult.cooldown:
                  _showErrorSnackBar(
                    'Still in cooldown from a recent alert. Try again shortly.',
                  );
                  break;
                case EmergencyResult.noContacts:
                  _showErrorSnackBar('Add a trusted contact first');
                  break;
                case EmergencyResult.smsUnavailable:
                  _showErrorSnackBar(
                    'SMS unavailable (check SIM / permission)',
                  );
                  break;
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Send Test'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: SwitchListTile(
                    secondary: Icon(
                      _monitoringEnabled ? Icons.shield : Icons.shield_outlined,
                      color: _monitoringEnabled ? Colors.green : Colors.blue,
                      size: 28,
                    ),
                    title: const Text(
                      'Monitor when minimized / locked',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _monitoringEnabled
                          ? 'Active. Shake detection runs in the background.'
                          : 'Off. Detection only works while app is open.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    value: _monitoringEnabled,
                    onChanged: (v) => _toggleMonitoring(v),
                  ),
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
                _buildSettingCard(
                  icon: Icons.history,
                  title: 'Emergency History',
                  subtitle: 'View past alerts sent from this device',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoryScreen(),
                      ),
                    );
                  },
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
        leading: Icon(icon, color: iconColor ?? Colors.blue, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
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
