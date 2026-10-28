import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'constants/app_theme.dart';
import 'screens/calculator_screen.dart';
import 'services/app_bootstrap.dart';
import 'services/foreground_sos_service.dart';
import 'services/theme_controller.dart';

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

  // Load the saved theme preference before first frame.
  await ThemeController.instance.load();

  // Initialise Firebase core BEFORE runApp (guarded — if not configured yet,
  // the app simply runs in local-only mode without crashing).
  await AppBootstrap.initCore();

  runApp(const SilentHelpApp());

  // Bring up the secondary cloud services (auth, FCM, sync, Crashlytics) after
  // the first frame so they never delay startup. Never on the critical path.
  AppBootstrap.initServices();
}

class SilentHelpApp extends StatelessWidget {
  const SilentHelpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) {
        // Resolve the effective brightness up-front so AppTheme's static
        // getters are correct before any screen builds.
        final platformDark =
            MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
        final effectiveDark = switch (mode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        AppTheme.applyBrightness(
          effectiveDark ? Brightness.dark : Brightness.light,
        );

        return MaterialApp(
          title: 'Calculator', //app title
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: mode,
          // Re-sync inside the tree too (covers system brightness changes).
          builder: (context, child) {
            AppTheme.applyBrightness(Theme.of(context).brightness);
            return child ?? const SizedBox.shrink();
          },
          home: const WithForegroundTask(child: CalculatorScreen()),
        );
      },
    );
  }
}
