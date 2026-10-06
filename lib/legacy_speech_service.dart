import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// واجهة لمسار التعرف الصوتي السابق الذي كان يعمل في النسخ السابقة.
/// يحتفظ التطبيق بمثيل SpeechToText واحد، مع تحديث مستمعي الحالة الحاليين
/// عند فتح صفحة إضافة طالب جديدة حتى لا تبقى callbacks مرتبطة بصفحة قديمة.
class LegacySpeechService {
  LegacySpeechService._();

  static final SpeechToText _speech = SpeechToText();
  static bool _initialized = false;
  static bool _available = false;
  static String? _localeId;
  static void Function(String status)? _onStatus;
  static void Function(SpeechRecognitionError error)? _onError;

  static SpeechToText get speech => _speech;
  static bool get available => _available;
  static String? get localeId => _localeId;

  static Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;

    if (_initialized) return _available;

    _available = await _speech.initialize(
      finalTimeout: const Duration(milliseconds: 350),
      onStatus: (status) => _onStatus?.call(status),
      onError: (error) => _onError?.call(error),
      debugLogging: false,
    );
    _initialized = true;

    if (_available) {
      final locales = await _speech.locales();
      LocaleName? arabic;
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id == 'ar-iq') {
          arabic = locale;
          break;
        }
        if (arabic == null && id.startsWith('ar')) arabic = locale;
      }
      _localeId = arabic?.localeId ?? 'ar-IQ';
    }
    return _available;
  }

  static Future<void> listen({required void Function(dynamic result) onResult}) async {
    await _speech.listen(
      onResult: onResult,
      localeId: _localeId ?? 'ar-IQ',
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(milliseconds: 1200),
      partialResults: true,
      onDevice: false,
      cancelOnError: true,
    );
  }

  static Future<void> stop() => _speech.stop();
  static Future<void> cancel() => _speech.cancel();
}
