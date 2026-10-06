import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCore {
  static ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final AudioPlayer audioPlayer = AudioPlayer();
  static bool isAudioMuted = true;
  static double currentVolume = 0.5;

  // إعدادات التعرف الصوتي المحفوظة محلياً.
  static String? voiceLocale;
  static bool voiceEnhancementEnabled = true;
  static double voiceCalibrationScore = 0.0;
  static bool voiceCalibrationCompleted = false;

  static const MethodChannel _voiceChannel = MethodChannel('emis.voice/audio');

  static Future<void> initPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDark') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    isAudioMuted = prefs.getBool('isAudioMuted') ?? true;
    currentVolume = prefs.getDouble('currentVolume') ?? 0.5;
    voiceLocale = prefs.getString('voiceLocale');
    voiceEnhancementEnabled = prefs.getBool('voiceEnhancementEnabled') ?? true;
    voiceCalibrationScore = prefs.getDouble('voiceCalibrationScore') ?? 0.0;
    voiceCalibrationCompleted = prefs.getBool('voiceCalibrationCompleted') ?? false;

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

  static Future<void> saveVoiceLocale(String locale) async {
    voiceLocale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voiceLocale', locale);
  }

  static Future<void> saveVoiceEnhancement(bool enabled) async {
    voiceEnhancementEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voiceEnhancementEnabled', enabled);
  }

  static Future<void> saveVoiceCalibration(double score) async {
    voiceCalibrationScore = score.clamp(0.0, 1.0).toDouble();
    voiceCalibrationCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voiceCalibrationScore', voiceCalibrationScore);
    await prefs.setBool('voiceCalibrationCompleted', true);
  }

  static Future<bool> setVoiceEnhancement(bool enabled) async {
    try {
      final result = await _voiceChannel.invokeMethod<bool>(
        enabled ? 'enableVoiceEnhancement' : 'disableVoiceEnhancement',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getVoiceProcessingCapabilities() async {
    try {
      final result = await _voiceChannel.invokeMethod<dynamic>(
        'getVoiceProcessingCapabilities',
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return <String, dynamic>{
      'noiseSuppressorAvailable': false,
      'acousticEchoCancelerAvailable': false,
      'modeApplied': false,
    };
  }

  static void toggleTheme() {
    final isDark = themeNotifier.value == ThemeMode.dark;
    saveThemePreference(!isDark);
  }
}
