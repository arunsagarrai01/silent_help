import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/storage_service.dart';
import '../services/emergency_service.dart';
import '../services/foreground_sos_service.dart';
import '../services/permission_service.dart';
import '../services/voice_sos_controller.dart';
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
  bool _voiceSosEnabled = false;
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
      final voiceSos = await ForegroundSosService.isVoiceSosEnabled();

      setState(() {
        _secretPattern = pattern;
        _shakeCount = shakeCount;
        _alertMessage = message;
        _monitoringEnabled = monitoring;
        _voiceSosEnabled = voiceSos;
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
      builder: (dialogContext) => _themedDialog(
        title: 'Secret Calculator Pattern',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themedTextField(controller, 'Pattern (e.g., 123==)'),
            const SizedBox(height: 12),
            const Text(
              'Enter a sequence that triggers an emergency alert when typed in the calculator.',
              style: TextStyle(fontSize: 12, color: AppTheme.grey),
            ),
          ],
        ),
        onSave: () async {
          final pattern = controller.text.trim();
          if (pattern.isNotEmpty) {
            await _storageService.setSecretPattern(pattern);
            setState(() => _secretPattern = pattern);
            if (mounted) Navigator.pop(dialogContext);
            _showSuccessSnackBar('Secret pattern updated');
          }
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }

  void _showShakeCountDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => ShakeCountDialog(
        initialCount: _shakeCount,
        onSave: (value) {
          _storageService.setShakeCount(value);
          ForegroundSosService.setShakeCount(value);
          setState(() => _shakeCount = value);
          _showSuccessSnackBar('Shake count updated');
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }

  void _showAlertMessageDialog() {
    final controller = TextEditingController(text: _alertMessage);

    showDialog(
      context: context,
      builder: (dialogContext) => _themedDialog(
        title: 'Emergency Alert Message',
        content: _themedTextField(
          controller,
          'Enter the message to send in emergencies...',
          maxLines: 4,
        ),
        onSave: () async {
          final message = controller.text.trim();
          if (message.isNotEmpty) {
            await _storageService.setAlertMessage(message);
            setState(() => _alertMessage = message);
            if (mounted) Navigator.pop(dialogContext);
            _showSuccessSnackBar('Alert message updated');
          }
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }

  Future<void> _toggleMonitoring(bool enable) async {
    if (enable) {
      final perms = await PermissionService.requestCorePermissions();
      if (perms['sms'] != true) {
        _showErrorSnackBar(
          'SMS permission is required to send emergency alerts.',
        );
        return;
      }
      if (perms['location'] != true) {
        _showErrorSnackBar(
          'Location permission recommended for location in alerts.',
        );
      }
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

  Future<void> _toggleVoiceSos(bool enable) async {
    await ForegroundSosService.setVoiceSosEnabled(enable);
    setState(() => _voiceSosEnabled = enable);

    if (enable) {
      final granted = await PermissionService.requestMicrophone();
      if (!granted) {
        setState(() => _voiceSosEnabled = false);
        await ForegroundSosService.setVoiceSosEnabled(false);
        _showErrorSnackBar('Microphone permission is required for Voice SOS');
        return;
      }
      final started = await VoiceSosController.instance.start();
      if (started) {
        _showSuccessSnackBar('Voice SOS active. Say "SilentHelp Emergency"');
      } else {
        _showErrorSnackBar('Voice recognition unavailable on this device');
      }
    } else {
      await VoiceSosController.instance.stop();
      _showSuccessSnackBar('Voice SOS disabled');
    }
  }

  void _testEmergencySystem() {
    showDialog(
      context: context,
      builder: (dialogContext) => _themedDialog(
        title: 'Test Emergency System',
        saveLabel: 'Send Test',
        saveColor: AppTheme.warning,
        content: const Text(
          'This will trigger a test emergency alert to all your trusted contacts. '
          'Are you sure you want to continue?',
          style: TextStyle(color: AppTheme.charcoalSoft),
        ),
        onSave: () async {
          Navigator.pop(dialogContext);
          await PermissionService.requestCorePermissions();
          final result = await EmergencyService.testEmergencySystem();
          switch (result) {
            case EmergencyResult.sent:
              _showSuccessSnackBar('Test alert sent to contacts');
              break;
            case EmergencyResult.cooldown:
              _showErrorSnackBar('Still in cooldown. Try again shortly.');
              break;
            case EmergencyResult.noContacts:
              _showErrorSnackBar('Add a trusted contact first');
              break;
            case EmergencyResult.smsUnavailable:
              _showErrorSnackBar('SMS unavailable (check SIM / permission)');
              break;
          }
        },
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
  }

  // ---- themed helpers ----

  Widget _themedDialog({
    required String title,
    required Widget content,
    required VoidCallback onSave,
    required VoidCallback onCancel,
    String saveLabel = 'Save',
    Color saveColor = AppTheme.lime,
  }) {
    return AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: content,
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel', style: TextStyle(color: AppTheme.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: saveColor,
            foregroundColor: AppTheme.charcoal,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
          onPressed: onSave,
          child: Text(saveLabel),
        ),
      ],
    );
  }

  Widget _themedTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
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
        title: const Text('Emergency Settings'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.charcoal,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.lime))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeroCard(),
                const SizedBox(height: 24),
                _buildSectionHeader('Emergency Triggers'),
                _buildTile(
                  icon: Icons.calculate,
                  title: 'Secret Calculator Pattern',
                  subtitle: 'Current: $_secretPattern',
                  onTap: _showSecretPatternDialog,
                ),
                _buildTile(
                  icon: Icons.vibration,
                  title: 'Shake Detection',
                  subtitle: 'Trigger after $_shakeCount shakes',
                  onTap: _showShakeCountDialog,
                ),
                _buildSwitchTile(
                  icon: _monitoringEnabled
                      ? Icons.shield
                      : Icons.shield_outlined,
                  title: 'Monitor when minimized / locked',
                  subtitle: _monitoringEnabled
                      ? 'Active. Shake detection runs in the background.'
                      : 'Off. Detection only works while app is open.',
                  value: _monitoringEnabled,
                  onChanged: _toggleMonitoring,
                ),
                _buildSwitchTile(
                  icon: _voiceSosEnabled ? Icons.mic : Icons.mic_off,
                  title: 'Voice SOS',
                  subtitle: _voiceSosEnabled
                      ? 'Say "SilentHelp Emergency" while app is open'
                      : 'Tap to enable hands-free voice trigger',
                  value: _voiceSosEnabled,
                  onChanged: _toggleVoiceSos,
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Alert Configuration'),
                _buildTile(
                  icon: Icons.message,
                  title: 'Emergency Message',
                  subtitle: _alertMessage.length > 50
                      ? '${_alertMessage.substring(0, 50)}...'
                      : _alertMessage,
                  onTap: _showAlertMessageDialog,
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Testing & History'),
                _buildTile(
                  icon: Icons.bug_report,
                  title: 'Test Emergency System',
                  subtitle: 'Send a test alert to all contacts',
                  onTap: _testEmergencySystem,
                  accent: AppTheme.warning,
                ),
                _buildTile(
                  icon: Icons.history,
                  title: 'Emergency History',
                  subtitle: 'View past alerts sent from this device',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildInfoCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildHeroCard() {
    final activeCount = [
      _monitoringEnabled,
      _voiceSosEnabled,
    ].where((e) => e).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.charcoalGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: AppTheme.limeGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.limeShadow,
            ),
            child: const Icon(
              Icons.health_and_safety,
              color: AppTheme.charcoal,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Protection Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activeCount > 0
                      ? '$activeCount trigger(s) armed and ready'
                      : 'No background triggers active',
                  style: TextStyle(
                    color: activeCount > 0 ? AppTheme.lime : AppTheme.greyLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.charcoal,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color accent = AppTheme.charcoal,
  }) {
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.grey, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow,
        border: value ? Border.all(color: AppTheme.lime, width: 1.5) : null,
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: value
                ? AppTheme.lime.withValues(alpha: 0.25)
                : AppTheme.greyLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: value ? AppTheme.limeDark : AppTheme.grey,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.grey, fontSize: 12),
        ),
        activeThumbColor: AppTheme.charcoal,
        activeTrackColor: AppTheme.lime,
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.limeSoft,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline, color: AppTheme.limeDark),
              SizedBox(width: 8),
              Text(
                'How It Works',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.charcoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '• Calculator Pattern: Enter the secret sequence to trigger emergency\n'
            '• Shake Detection: Shake your phone the set number of times\n'
            '• Background Monitoring: Keep listening when app is minimized\n'
            '• Voice SOS: Say "SilentHelp Emergency" while the app is open\n'
            '• All triggers work silently and send your location + timestamp',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.charcoalSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog widget for shake count selection
class ShakeCountDialog extends StatefulWidget {
  final int initialCount;
  final VoidCallback onCancel;
  final ValueChanged<int> onSave;

  const ShakeCountDialog({
    super.key,
    required this.initialCount,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<ShakeCountDialog> createState() => _ShakeCountDialogState();
}

class _ShakeCountDialogState extends State<ShakeCountDialog> {
  late int tempShakeCount;

  @override
  void initState() {
    super.initState();
    tempShakeCount = widget.initialCount;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      title: const Text(
        'Shake Detection',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Number of shakes required to trigger emergency:',
            style: TextStyle(color: AppTheme.charcoalSoft),
          ),
          const SizedBox(height: 16),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppTheme.limeGradient,
              shape: BoxShape.circle,
              boxShadow: AppTheme.limeShadow,
            ),
            child: Text(
              '$tempShakeCount',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.charcoal,
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.lime,
              thumbColor: AppTheme.charcoal,
              inactiveTrackColor: AppTheme.greyLight,
              overlayColor: AppTheme.lime.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: tempShakeCount.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              label: tempShakeCount.toString(),
              onChanged: (value) {
                setState(() => tempShakeCount = value.round());
              },
            ),
          ),
          Text(
            '$tempShakeCount shakes',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoal,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
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
            widget.onSave(tempShakeCount);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
