import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/calculator_screen.dart';
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

  runApp(const SilentHelpApp());
}

class SilentHelpApp extends StatelessWidget {
  const SilentHelpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      debugShowCheckedModeBanner: false, // Removes the banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      ),
      // WithForegroundTask keeps the task alive and lets the plugin manage the
      // service lifecycle correctly while the disguised UI is shown.
      home: const WithForegroundTask(child: CalculatorScreen()),
    );
  }
}
