import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'constants/app_theme.dart';
import 'screens/calculator_screen.dart';
import 'services/app_bootstrap.dart';
import 'services/foreground_sos_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Required so the UI isolate can receive messages from the background
  // foreground-service isolate.
  FlutterForegroundTask.initCommunicationPort();

  // Prepare the notification channel / task options up-front (cheap, no start).
  ForegroundSosService.init();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Show UI immediately, then bring up the optional Firebase cloud layer in the
  // background. The app is fully usable (local SOS) whether or not this
  // succeeds — Firebase is never on the critical path.
  runApp(const SilentHelpApp());
  AppBootstrap.initCloud();
}

class SilentHelpApp extends StatelessWidget {
  // Srateless Widget
  const SilentHelpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator', //app title
      debugShowCheckedModeBanner: false, // Removes the banner
      // Emergency screens use the lime/charcoal AppTheme. The calculator
      // disguise keeps its own dark styling inside its widget.
      theme: AppTheme.themeData(),
      // WithForegroundTask keeps the task alive and lets the plugin manage the
      // service lifecycle correctly while the disguised UI is shown.
      home: const WithForegroundTask(child: CalculatorScreen()),
    );
  }
}
