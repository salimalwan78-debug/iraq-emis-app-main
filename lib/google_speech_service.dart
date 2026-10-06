import 'package:flutter/services.dart';

/// واجهة Flutter لخدمة Android SpeechRecognizer الموجهة إلى خدمة Google
/// الموجودة على الجهاز عند توفرها.
class GoogleSpeechService {
  static const MethodChannel _method = MethodChannel('emis.google_speech');
  static const EventChannel _events = EventChannel('emis.google_speech/events');

  static Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return Map<String, dynamic>.from(event);
        }
        return <String, dynamic>{};
      });

  static Future<Map<String, dynamic>> getInfo() async {
    final result = await _method.invokeMethod<dynamic>('getInfo');
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{'available': false};
  }

  static Future<bool> startListening({
    required int sessionId,
    String locale = 'ar-IQ',
  }) async {
    final result = await _method.invokeMethod<dynamic>('start', {
      'sessionId': sessionId,
      'locale': locale,
    });
    return result == true;
  }

  static Future<void> stopListening() async {
    await _method.invokeMethod('stop');
  }

  static Future<void> cancelListening() async {
    await _method.invokeMethod('cancel');
  }
}
