import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/map_screen.dart';
import 'utils/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization warning: $e');
  }

  runApp(const SoilSensorApp());
}

class SoilSensorApp extends StatelessWidget {
  const SoilSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.softGreyBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.softBlue,
          primary: AppColors.softBlue,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.appbarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const DashboardScreen(),
        '/map': (context) => const MapScreen(),
        '/history': (context) => HistoryScreen(
              logs: const [],
              onClearLogs: () {},
            ),
      },
    );
  }
}
