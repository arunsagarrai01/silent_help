import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_theme.dart';
import '../services/sensor_service.dart';
import '../services/emergency_service.dart';
import '../services/storage_service.dart';
import '../services/foreground_sos_service.dart';
import '../services/voice_sos_controller.dart';
import '../widgets/calculator_button.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart'; //imports

/// Main calculator screen that disguises the emergency app
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with WidgetsBindingObserver {
  String _display = '0';
  String _previousValue = '';
  String _operation = '';
  bool _waitingForOperand = false;
  String _inputSequence = '';

  final SensorService _sensorService = SensorService();
  final StorageService _storageService = StorageService();
  String _secretPattern = '123==';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sensorService.stopShakeDetection();
    VoiceSosController.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voice SOS uses the mic which only works while the app is foregrounded.
    // Pause it when backgrounded to be a good citizen and avoid false hits.
    if (state == AppLifecycleState.resumed) {
      VoiceSosController.instance.startIfEnabled();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      VoiceSosController.instance.stop();
    }
  }

  Future<void> _initializeApp() async {
    // Load secret pattern
    _secretPattern = await _storageService.getSecretPattern();

    // Start in-foreground shake detection (works while the screen is open).
    final shakeCount = await _storageService.getShakeCount();
    _sensorService.startShakeDetection(
      onShakeDetected: _onShakeDetected,
      requiredShakeCount: shakeCount,
    );

    // Keep the background service's shake count in sync.
    await ForegroundSosService.setShakeCount(shakeCount);

    // Resume background monitoring if the user had it enabled previously.
    final monitoringEnabled = await _storageService.isMonitoringEnabled();
    if (monitoringEnabled && !await ForegroundSosService.isRunning()) {
      await ForegroundSosService.start();
    }
    // Start Voice SOS (UI isolate) if the user enabled it.
    await VoiceSosController.instance.startIfEnabled();
  }

  void _onShakeDetected(int shakeCount) {
    // Trigger emergency silently (auto-sends SMS; cooldown handled internally).
    EmergencyService.triggerEmergencyAlert(
      'Shake Detection ($shakeCount shakes)',
    );

    // Provide subtle haptic feedback
    HapticFeedback.lightImpact();
  }

  void _inputDigit(String digit) {
    setState(() {
      if (_waitingForOperand) {
        _display = digit;
        _waitingForOperand = false;
      } else {
        _display = _display == '0' ? digit : _display + digit;
      }

      // Track input sequence for secret pattern
      _inputSequence += digit;
      _checkSecretPattern();
    });
  }

  void _inputOperation(String nextOperation) {
    double inputValue = double.parse(_display);

    if (_previousValue.isEmpty) {
      _previousValue = _display;
    } else if (!_waitingForOperand) {
      double previousValue = double.parse(_previousValue);
      double result = _calculate(previousValue, inputValue, _operation);

      setState(() {
        _display = result.toString();
        _previousValue = _display;
      });
    }

    setState(() {
      _waitingForOperand = true;
      _operation = nextOperation;
    });

    // Track operation in sequence
    _inputSequence += nextOperation;
    _checkSecretPattern();
  }

  double _calculate(
    double firstOperand,
    double secondOperand,
    String operation,
  ) {
    switch (operation) {
      case '+':
        return firstOperand + secondOperand;
      case '-':
        return firstOperand - secondOperand;
      case '×':
        return firstOperand * secondOperand;
      case '÷':
        return secondOperand != 0 ? firstOperand / secondOperand : 0;
      default:
        return secondOperand;
    }
  }

  void _performCalculation() {
    double inputValue = double.parse(_display);

    if (_previousValue.isNotEmpty && !_waitingForOperand) {
      double previousValue = double.parse(_previousValue);
      double result = _calculate(previousValue, inputValue, _operation);

      setState(() {
        _display = result.toString();
        _previousValue = '';
        _operation = '';
        _waitingForOperand = true;
      });
    }

    // Track equals in sequence
    _inputSequence += '=';
    _checkSecretPattern();
  }

  void _checkSecretPattern() {
    if (_inputSequence.contains(_secretPattern)) {
      // Secret pattern detected - trigger emergency silently
      EmergencyService.triggerEmergencyAlert('Secret Calculator Pattern');

      // Provide subtle haptic feedback
      HapticFeedback.lightImpact();

      // Reset sequence
      _inputSequence = '';
    }

    // Keep sequence length manageable
    if (_inputSequence.length > 20) {
      _inputSequence = _inputSequence.substring(_inputSequence.length - 10);
    }
  }

  void _clear() {
    setState(() {
      _display = '0';
      _previousValue = '';
      _operation = '';
      _waitingForOperand = false;
      _inputSequence = '';
    });
  }

  void _showHiddenMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.greyLight,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.limeGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shield, color: AppTheme.charcoal),
                ),
                const SizedBox(width: 12),
                const Text(
                  'SilentHelp',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.charcoal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMenuOption(
              icon: Icons.contacts,
              title: 'Trusted Contacts',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ContactsScreen(),
                  ),
                );
              },
            ),
            _buildMenuOption(
              icon: Icons.notifications_active,
              title: 'Emergency Triggers',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
            _buildMenuOption(
              icon: Icons.message,
              title: 'Alert Message',
              onTap: () {
                Navigator.pop(context);
                _showAlertMessageDialog();
              },
            ),
            _buildMenuOption(
              icon: Icons.settings_applications,
              title: 'App Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
            _buildMenuOption(
              icon: Icons.exit_to_app,
              title: 'Exit',
              iconColor: AppTheme.danger,
              onTap: () {
                Navigator.pop(context);
                SystemNavigator.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? AppTheme.charcoal).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor ?? AppTheme.charcoal, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    );
  }

  void _showAlertMessageDialog() {
    TextEditingController controller = TextEditingController();

    // Load current message
    _storageService.getAlertMessage().then((message) {
      controller.text = message;
    });

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        title: const Text(
          'Emergency Alert Message',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter your emergency message...',
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
          ),
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
              _storageService.setAlertMessage(controller.text);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Alert message updated')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: _showHiddenMenu,
        ),
        title: const Text('Calculator', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Display
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _display,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ),

          // Buttons
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Row 1: C, ±, %, ÷
                  Expanded(
                    child: Row(
                      children: [
                        CalculatorButton(
                          text: 'C',
                          onPressed: _clear,
                          backgroundColor: Colors.grey[400]!,
                          textColor: Colors.black,
                        ),
                        CalculatorButton(
                          text: '±',
                          onPressed: () {},
                          backgroundColor: Colors.grey[400]!,
                          textColor: Colors.black,
                        ),
                        CalculatorButton(
                          text: '%',
                          onPressed: () {},
                          backgroundColor: Colors.grey[400]!,
                          textColor: Colors.black,
                        ),
                        CalculatorButton(
                          text: '÷',
                          onPressed: () => _inputOperation('÷'),
                          backgroundColor: Colors.orange,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  // Row 2: 7, 8, 9, ×
                  Expanded(
                    child: Row(
                      children: [
                        CalculatorButton(
                          text: '7',
                          onPressed: () => _inputDigit('7'),
                        ),
                        CalculatorButton(
                          text: '8',
                          onPressed: () => _inputDigit('8'),
                        ),
                        CalculatorButton(
                          text: '9',
                          onPressed: () => _inputDigit('9'),
                        ),
                        CalculatorButton(
                          text: '×',
                          onPressed: () => _inputOperation('×'),
                          backgroundColor: Colors.orange,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  // Row 3: 4, 5, 6, -
                  Expanded(
                    child: Row(
                      children: [
                        CalculatorButton(
                          text: '4',
                          onPressed: () => _inputDigit('4'),
                        ),
                        CalculatorButton(
                          text: '5',
                          onPressed: () => _inputDigit('5'),
                        ),
                        CalculatorButton(
                          text: '6',
                          onPressed: () => _inputDigit('6'),
                        ),
                        CalculatorButton(
                          text: '-',
                          onPressed: () => _inputOperation('-'),
                          backgroundColor: Colors.orange,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  // Row 4: 1, 2, 3, +
                  Expanded(
                    child: Row(
                      children: [
                        CalculatorButton(
                          text: '1',
                          onPressed: () => _inputDigit('1'),
                        ),
                        CalculatorButton(
                          text: '2',
                          onPressed: () => _inputDigit('2'),
                        ),
                        CalculatorButton(
                          text: '3',
                          onPressed: () => _inputDigit('3'),
                        ),
                        CalculatorButton(
                          text: '+',
                          onPressed: () => _inputOperation('+'),
                          backgroundColor: Colors.orange,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  // Row 5: 0, ., =
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: CalculatorButton(
                            text: '0',
                            onPressed: () => _inputDigit('0'),
                          ),
                        ),
                        Expanded(
                          child: CalculatorButton(
                            text: '.',
                            onPressed: () => _inputDigit('.'),
                          ),
                        ),
                        Expanded(
                          child: CalculatorButton(
                            text: '=',
                            onPressed: _performCalculation,
                            backgroundColor: Colors.orange,
                            textColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
