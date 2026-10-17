import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCore {
  static ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
  static final AudioPlayer audioPlayer = AudioPlayer();
  static bool isAudioMuted = true; // القيمة الافتراضية صامت لحين قراءة التفضيلات
  static double currentVolume = 0.5;
  static bool voiceInputEnabled = true;
  // التشغيل التلقائي للتنقل الصوتي بين الحقول في نموذج إضافة الطالب.
  static bool voiceSequentialAutoStart = false;
  /// google = Android SpeechRecognizer (يفضل خدمة Google/الخدمة الافتراضية)،
  /// legacy = مسار speech_to_text القديم الذي كان يعمل سابقاً.
  static String voiceRecognitionEngine = 'google';

  // إعدادات التعرف الصوتي في Android/Google.
  static bool voiceAutoRestart = false;
  static int voicePossibleSilenceMs = 23000;
  static int voiceCompleteSilenceMs = 23000;
  static int voiceMinimumSpeechMs = 2500;
  static int voiceRestartDelayMs = 4100;
  static int voiceFinalizationTimeoutMs = 2400;
  static double voiceArrowOpacity = 0.25;

  // متغيرات داخلية لمنع تضارب تشغيل الصوت وإدارة دورة حياة التطبيق
  static bool _isPlayingRequest = false;
  static bool _lifecycleObserverAdded = false;
  static final _AppLifecycleObserver _lifecycleObserver = _AppLifecycleObserver();

  static Future<void> initPreferences() async {
    _ensureLifecycleObserver();

    final prefs = await SharedPreferences.getInstance();
    bool isDark = prefs.getBool('isDark') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

    // قراءة الحالة المحفوظة بدقة (افتراضياً صامت إلى أن يفعله المستخدم)
    isAudioMuted = prefs.getBool('isAudioMuted') ?? true;
    currentVolume = (prefs.getDouble('currentVolume') ?? 0.5).clamp(0.0, 1.0);
    voiceInputEnabled = prefs.getBool('voiceInputEnabled') ?? true;
    voiceSequentialAutoStart = prefs.getBool('voiceSequentialAutoStart') ?? false;
    voiceRecognitionEngine = prefs.getString('voiceRecognitionEngine') ?? 'google';
    voiceAutoRestart = prefs.getBool('voiceAutoRestart') ?? false;
    voicePossibleSilenceMs = prefs.getInt('voicePossibleSilenceMs') ?? 23000;
    voiceCompleteSilenceMs = prefs.getInt('voiceCompleteSilenceMs') ?? 23000;
    voiceMinimumSpeechMs = prefs.getInt('voiceMinimumSpeechMs') ?? 2500;
    voiceRestartDelayMs = prefs.getInt('voiceRestartDelayMs') ?? 4100;
    voiceFinalizationTimeoutMs = prefs.getInt('voiceFinalizationTimeoutMs') ?? 2400;
    voiceArrowOpacity = (prefs.getDouble('voiceArrowOpacity') ?? 0.25).clamp(0.20, 0.90);

    await audioPlayer.setReleaseMode(ReleaseMode.loop);
    await audioPlayer.setVolume(currentVolume);

    if (!isAudioMuted) {
      await playRelaxMusic();
    } else {
      await audioPlayer.stop();
    }
  }

  static void _ensureLifecycleObserver() {
    if (_lifecycleObserverAdded) return;
    try {
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      _lifecycleObserverAdded = true;
    } catch (_) {}
  }

  static Future<void> saveThemePreference(bool isDark) async {
    // تحديث الواجهة فوراً دون انتظار الكتابة في الذاكرة لمنع أي تأخير بصري
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', isDark);
  }

  static Future<void> playRelaxMusic() async {
    if (isAudioMuted || _isPlayingRequest) return;
    _isPlayingRequest = true;
    try {
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.setVolume(currentVolume);
      if (audioPlayer.state != PlayerState.playing) {
        await audioPlayer.play(AssetSource('relax.mp3'));
      }
    } catch (e) {
      debugPrint('خطأ أثناء تشغيل الصوت: $e');
    } finally {
      _isPlayingRequest = false;
    }
  }

  static Future<void> pauseMusicForBackground() async {
    try {
      if (audioPlayer.state == PlayerState.playing) {
        await audioPlayer.pause();
      }
    } catch (_) {}
  }

  static Future<void> resumeMusicFromBackground() async {
    if (isAudioMuted) return;
    try {
      if (audioPlayer.state == PlayerState.paused) {
        await audioPlayer.resume();
      } else if (audioPlayer.state != PlayerState.playing) {
        await playRelaxMusic();
      }
    } catch (_) {}
  }

  static Future<void> toggleAudio() async {
    isAudioMuted = !isAudioMuted;
    if (isAudioMuted) {
      await audioPlayer.stop();
    } else {
      await playRelaxMusic();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAudioMuted', isAudioMuted);
  }

  static Future<void> setVolume(double vol) async {
    currentVolume = vol.clamp(0.0, 1.0);
    await audioPlayer.setVolume(currentVolume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('currentVolume', currentVolume);
  }

  static Future<void> setVoiceInputEnabled(bool enabled) async {
    voiceInputEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voiceInputEnabled', enabled);
  }

  static Future<void> setVoiceSequentialAutoStart(bool enabled) async {
    voiceSequentialAutoStart = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voiceSequentialAutoStart', enabled);
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
    voiceAutoRestart = false;
    voicePossibleSilenceMs = 23000;
    voiceCompleteSilenceMs = 23000;
    voiceMinimumSpeechMs = 2500;
    voiceRestartDelayMs = 4100;
    voiceFinalizationTimeoutMs = 2400;
    voiceArrowOpacity = 0.25;
    for (final key in [
      'voiceAutoRestart',
      'voicePossibleSilenceMs',
      'voiceCompleteSilenceMs',
      'voiceMinimumSpeechMs',
      'voiceRestartDelayMs',
      'voiceFinalizationTimeoutMs',
      'voiceArrowOpacity',
    ]) {
      await prefs.remove(key);
    }
  }

  static Future<void> toggleTheme() async {
    bool isDark = themeNotifier.value == ThemeMode.dark;
    await saveThemePreference(!isDark);
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      AppCore.pauseMusicForBackground();
    } else if (state == AppLifecycleState.resumed) {
      AppCore.resumeMusicFromBackground();
    }
  }
}
