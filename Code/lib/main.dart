import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'constants/app_theme.dart';
import 'screens/calculator_screen.dart';
import 'services/app_bootstrap.dart';
import 'services/foreground_sos_service.dart';

Future<void> main() async {
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

  // Initialise Firebase core BEFORE runApp (guarded — if not configured yet,
  // the app simply runs in local-only mode without crashing).
  await AppBootstrap.initCore();

  runApp(const SilentHelpApp());

  // Bring up the secondary cloud services (auth, FCM, sync, Crashlytics) after
  // the first frame so they never delay startup. Never on the critical path.
  AppBootstrap.initServices();
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
