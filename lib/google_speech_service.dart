import 'package:flutter/services.dart';

/// واجهة Flutter لمسار Android SpeechRecognizer.
/// في وضع Google يستخدم التطبيق خدمة Google إن كانت ظاهرة للنظام،
/// وإلا يستخدم خدمة التعرف الافتراضية التي يحددها Android (والتي قد تكون Google).
class GoogleSpeechService {
  static const MethodChannel _method = MethodChannel('emis.google_speech');
  static const EventChannel _events = EventChannel('emis.google_speech/events');

  static Stream<Map<String, dynamic>> get events =>
      _events.receiveBroadcastStream().map((event) {
        if (event is Map) return Map<String, dynamic>.from(event);
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
      'engine': 'google',
    });
    return result == true;
  }

  static Future<void> stopListening() => _method.invokeMethod('stop');
  static Future<void> cancelListening() => _method.invokeMethod('cancel');
}
