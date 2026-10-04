import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'intro_screen.dart';
import 'app_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة وحفظ قراءة الإعدادات المحلية (الوضع الداكن والصوت) قبل بدء التطبيق
  await AppCore.initPreferences();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'مساعد EMIS',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar', 'IQ')],
          locale: const Locale('ar', 'IQ'),
          themeMode: currentMode,
          theme: ThemeData(
            fontFamily: 'Tajawal',
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            textTheme: const TextTheme(
              displayLarge: TextStyle(fontWeight: FontWeight.bold),
              displayMedium: TextStyle(fontWeight: FontWeight.bold),
              displaySmall: TextStyle(fontWeight: FontWeight.bold),
              headlineLarge: TextStyle(fontWeight: FontWeight.bold),
              headlineMedium: TextStyle(fontWeight: FontWeight.bold),
              headlineSmall: TextStyle(fontWeight: FontWeight.bold),
              titleLarge: TextStyle(fontWeight: FontWeight.bold),
              titleMedium: TextStyle(fontWeight: FontWeight.bold),
              titleSmall: TextStyle(fontWeight: FontWeight.bold),
              bodyLarge: TextStyle(fontWeight: FontWeight.bold),
              bodyMedium: TextStyle(fontWeight: FontWeight.bold),
              bodySmall: TextStyle(fontWeight: FontWeight.bold),
              labelLarge: TextStyle(fontWeight: FontWeight.bold),
              labelMedium: TextStyle(fontWeight: FontWeight.bold),
              labelSmall: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          darkTheme: ThemeData(
            fontFamily: 'Tajawal',
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            textTheme: const TextTheme(
              displayLarge: TextStyle(fontWeight: FontWeight.bold),
              displayMedium: TextStyle(fontWeight: FontWeight.bold),
              displaySmall: TextStyle(fontWeight: FontWeight.bold),
              headlineLarge: TextStyle(fontWeight: FontWeight.bold),
              headlineMedium: TextStyle(fontWeight: FontWeight.bold),
              headlineSmall: TextStyle(fontWeight: FontWeight.bold),
              titleLarge: TextStyle(fontWeight: FontWeight.bold),
              titleMedium: TextStyle(fontWeight: FontWeight.bold),
              titleSmall: TextStyle(fontWeight: FontWeight.bold),
              bodyLarge: TextStyle(fontWeight: FontWeight.bold),
              bodyMedium: TextStyle(fontWeight: FontWeight.bold),
              bodySmall: TextStyle(fontWeight: FontWeight.bold),
              labelLarge: TextStyle(fontWeight: FontWeight.bold),
              labelMedium: TextStyle(fontWeight: FontWeight.bold),
              labelSmall: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          home: const IntroScreen(),
        );
      },
    );
  }
}
