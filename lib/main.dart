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
              titleMedium: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          darkTheme: ThemeData(
            fontFamily: 'Tajawal',
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            textTheme: const TextTheme(
              titleMedium: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          home: const IntroScreen(),
        );
      },
    );
  }
}
