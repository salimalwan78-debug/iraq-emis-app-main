import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCore {
  static ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final AudioPlayer audioPlayer = AudioPlayer();
  static bool isAudioMuted = true; // اجعل القيمة الافتراضية صحيحة (موقف لحين قراءة التفضيلات)
  static double currentVolume = 0.5;

  static Future<void> initPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    bool isDark = prefs.getBool('isDark') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    // قراءة الحالة المحفوظة بدقة (افتراضياً صامت إلى أن يفعله المستخدم)
    isAudioMuted = prefs.getBool('isAudioMuted') ?? true;
    currentVolume = prefs.getDouble('currentVolume') ?? 0.5;
    await audioPlayer.setVolume(currentVolume);

    if (!isAudioMuted) {
      await playRelaxMusic();
    } else {
      await audioPlayer.stop();
    }
  }

  static Future<void> saveThemePreference(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> playRelaxMusic() async {
    if (isAudioMuted) return;
    audioPlayer.setReleaseMode(ReleaseMode.loop);
    if (audioPlayer.state != PlayerState.playing) {
      await audioPlayer.play(AssetSource('relax.mp3'));
      await audioPlayer.setVolume(currentVolume);
    }
  }

  static Future<void> toggleAudio() async {
    isAudioMuted = !isAudioMuted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAudioMuted', isAudioMuted);

    if (isAudioMuted) {
      await audioPlayer.stop();
    } else {
      await playRelaxMusic();
    }
  }

  static Future<void> setVolume(double vol) async {
    currentVolume = vol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('currentVolume', vol);
    await audioPlayer.setVolume(vol);
  }

  static void toggleTheme() {
    bool isDark = themeNotifier.value == ThemeMode.dark;
    saveThemePreference(!isDark);
  }
}
