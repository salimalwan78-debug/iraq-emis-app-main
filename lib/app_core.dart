import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCore {
  static ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final AudioPlayer audioPlayer = AudioPlayer();
  static bool isAudioMuted = true; // اجعل القيمة الافتراضية صحيحة (موقف لحين قراءة التفضيلات)
  static double currentVolume = 0.5;
  static bool voiceInputEnabled = true;
  /// google = Android SpeechRecognizer (يفضل خدمة Google/الخدمة الافتراضية)،
  /// legacy = مسار speech_to_text القديم الذي كان يعمل سابقاً.
  static String voiceRecognitionEngine = 'google';

  // إعدادات التعرف الصوتي في Android/Google.
  static bool voiceAutoRestart = true;
  static int voicePossibleSilenceMs = 12000;
  static int voiceCompleteSilenceMs = 15000;
  static int voiceMinimumSpeechMs = 250;
  static int voiceRestartDelayMs = 700;
  static int voiceFinalizationTimeoutMs = 1500;
  static double voiceArrowOpacity = 0.65;

  static Future<void> initPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    bool isDark = prefs.getBool('isDark') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    // قراءة الحالة المحفوظة بدقة (افتراضياً صامت إلى أن يفعله المستخدم)
    isAudioMuted = prefs.getBool('isAudioMuted') ?? true;
    currentVolume = prefs.getDouble('currentVolume') ?? 0.5;
    voiceInputEnabled = prefs.getBool('voiceInputEnabled') ?? true;
    voiceRecognitionEngine = prefs.getString('voiceRecognitionEngine') ?? 'google';
    voiceAutoRestart = prefs.getBool('voiceAutoRestart') ?? true;
    voicePossibleSilenceMs = prefs.getInt('voicePossibleSilenceMs') ?? 12000;
    voiceCompleteSilenceMs = prefs.getInt('voiceCompleteSilenceMs') ?? 15000;
    voiceMinimumSpeechMs = prefs.getInt('voiceMinimumSpeechMs') ?? 250;
    voiceRestartDelayMs = prefs.getInt('voiceRestartDelayMs') ?? 700;
    voiceFinalizationTimeoutMs = prefs.getInt('voiceFinalizationTimeoutMs') ?? 1500;
    voiceArrowOpacity = prefs.getDouble('voiceArrowOpacity') ?? 0.65;
    voiceArrowOpacity = voiceArrowOpacity.clamp(0.20, 0.90);
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


  static Future<void> setVoiceInputEnabled(bool enabled) async {
    voiceInputEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voiceInputEnabled', enabled);
  }

  static Future<void> setVoiceRecognitionEngine(String engine) async {
    final value = engine == 'legacy' ? 'legacy' : 'google';
    voiceRecognitionEngine = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voiceRecognitionEngine', value);
  }

  static Future<void> saveVoiceSettings({
    bool? autoRestart,
    int? possibleSilenceMs,
    int? completeSilenceMs,
    int? minimumSpeechMs,
    int? restartDelayMs,
    int? finalizationTimeoutMs,
    double? arrowOpacity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (autoRestart != null) {
      voiceAutoRestart = autoRestart;
      await prefs.setBool('voiceAutoRestart', autoRestart);
    }
    if (possibleSilenceMs != null) {
      voicePossibleSilenceMs = possibleSilenceMs;
      await prefs.setInt('voicePossibleSilenceMs', possibleSilenceMs);
    }
    if (completeSilenceMs != null) {
      voiceCompleteSilenceMs = completeSilenceMs;
      await prefs.setInt('voiceCompleteSilenceMs', completeSilenceMs);
    }
    if (minimumSpeechMs != null) {
      voiceMinimumSpeechMs = minimumSpeechMs;
      await prefs.setInt('voiceMinimumSpeechMs', minimumSpeechMs);
    }
    if (restartDelayMs != null) {
      voiceRestartDelayMs = restartDelayMs;
      await prefs.setInt('voiceRestartDelayMs', restartDelayMs);
    }
    if (finalizationTimeoutMs != null) {
      voiceFinalizationTimeoutMs = finalizationTimeoutMs;
      await prefs.setInt('voiceFinalizationTimeoutMs', finalizationTimeoutMs);
    }
    if (arrowOpacity != null) {
      voiceArrowOpacity = arrowOpacity.clamp(0.20, 0.90);
      await prefs.setDouble('voiceArrowOpacity', voiceArrowOpacity);
    }
  }

  static Future<void> resetVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    voiceAutoRestart = true;
    voicePossibleSilenceMs = 12000;
    voiceCompleteSilenceMs = 15000;
    voiceMinimumSpeechMs = 250;
    voiceRestartDelayMs = 700;
    voiceFinalizationTimeoutMs = 1500;
    voiceArrowOpacity = 0.65;
    for (final key in [
      'voiceAutoRestart', 'voicePossibleSilenceMs', 'voiceCompleteSilenceMs',
      'voiceMinimumSpeechMs', 'voiceRestartDelayMs', 'voiceFinalizationTimeoutMs',
      'voiceArrowOpacity',
    ]) {
      await prefs.remove(key);
    }
  }
  static void toggleTheme() {
    bool isDark = themeNotifier.value == ThemeMode.dark;
    saveThemePreference(!isDark);
  }
}
