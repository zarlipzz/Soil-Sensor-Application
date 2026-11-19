import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/map_screen.dart';
import 'utils/app_constants.dart';
import 'utils/app_fonts.dart';
import 'utils/app_language.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SoilSensorApp());
}

class SoilSensorApp extends StatefulWidget {
  const SoilSensorApp({super.key});

  @override
  State<SoilSensorApp> createState() => _SoilSensorAppState();
}

class _SoilSensorAppState extends State<SoilSensorApp> {
  static const _languageKey = 'soil_app_language';
  bool _isThai = true;
  bool _isChangingLanguage = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && !_isChangingLanguage) {
        setState(() => _isThai = prefs.getString(_languageKey) != 'en');
      }
    } catch (error) {
      debugPrint('Could not load the app language: $error');
    }
  }

  Future<void> _toggleLanguage(BuildContext context) async {
    if (_isChangingLanguage) return;
    _isChangingLanguage = true;
    final nextIsThai = !_isThai;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  nextIsThai ? 'Changing Language' : 'กำลังเปลี่ยนภาษา',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    navigator.push(route);
    try {
      await Future.wait([
        Future<void>.delayed(const Duration(milliseconds: 700)),
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString(_languageKey, nextIsThai ? 'th' : 'en'),
        ),
      ]);
    } catch (error) {
      debugPrint('Could not save the app language: $error');
    } finally {
      if (route.isActive) navigator.removeRoute(route);
      if (mounted) {
        setState(() {
          _isThai = nextIsThai;
          _isChangingLanguage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLanguage(
      isThai: _isThai,
      onToggle: _toggleLanguage,
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: AppFonts.primary,
          fontFamilyFallback: AppFonts.fallback,
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
            elevation: 1.0,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const DashboardScreen(),
          '/map': (context) => const MapScreen(),
          '/history': (context) =>
              HistoryScreen(logs: const [], onClearLogs: () {}),
        },
      ),
    );
  }
}
