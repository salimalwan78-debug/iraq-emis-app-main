import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_core.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _CalibrationItem {
  final String text;
  final bool numeric;
  const _CalibrationItem(this.text, {this.numeric = false});
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SpeechToText _speech = SpeechToText();

  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _speechTesting = false;
  bool _speechListening = false;
  bool _speechHasArabic = false;
  bool _calibrating = false;
  bool _noiseChecking = false;
  String? _selectedLocale;
  String? _speechError;
  String _recognizedText = '';
  String _calibrationMessage = '';
  int _calibrationIndex = 0;
  int _calibrationPassed = 0;
  List<LocaleName> _arabicLocales = const [];
  Map<String, dynamic> _voiceCapabilities = const {};

  static const List<String> _arabicCandidates = [
    'ar-IQ', 'ar-SA', 'ar-AE', 'ar-EG', 'ar-JO', 'ar-KW', 'ar-BH',
    'ar-QA', 'ar-OM', 'ar-YE', 'ar-LB', 'ar-SY', 'ar-PS', 'ar-MA',
    'ar-DZ', 'ar-TN',
  ];

  static const List<_CalibrationItem> _calibrationItems = [
    _CalibrationItem('محمد'),
    _CalibrationItem('أحمد'),
    _CalibrationItem('علي'),
    _CalibrationItem('صفر', numeric: true),
    _CalibrationItem('سبعة', numeric: true),
    _CalibrationItem('ثمانية', numeric: true),
  ];

  String _localeLabel(String id) {
    const names = <String, String>{
      'ar-IQ': 'العربية - العراق',
      'ar-SA': 'العربية - السعودية',
      'ar-AE': 'العربية - الإمارات',
      'ar-EG': 'العربية - مصر',
      'ar-JO': 'العربية - الأردن',
      'ar-KW': 'العربية - الكويت',
      'ar-BH': 'العربية - البحرين',
      'ar-QA': 'العربية - قطر',
      'ar-OM': 'العربية - عُمان',
      'ar-YE': 'العربية - اليمن',
      'ar-LB': 'العربية - لبنان',
      'ar-SY': 'العربية - سوريا',
      'ar-PS': 'العربية - فلسطين',
      'ar-MA': 'العربية - المغرب',
      'ar-DZ': 'العربية - الجزائر',
      'ar-TN': 'العربية - تونس',
    };
    return names[id] ?? 'العربية ($id)';
  }

  String _normalizeArabic(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  String _normalizeNumeric(String value) {
    const words = <String, String>{
      'صفر': '0', 'واحد': '1', 'واحدة': '1', 'اثنان': '2', 'اثنين': '2',
      'اثنتان': '2', 'اثنتين': '2', 'ثلاثة': '3', 'ثلاث': '3',
      'أربعة': '4', 'اربعة': '4', 'خمسة': '5', 'خمس': '5',
      'ستة': '6', 'ست': '6', 'سبعة': '7', 'سبع': '7',
      'ثمانية': '8', 'ثماني': '8', 'تسعة': '9', 'تسع': '9',
    };
    final out = StringBuffer();
    final normalized = _normalizeArabic(value);
    const ai = '٠١٢٣٤٥٦٧٨٩';
    const ei = '۰۱۲۳۴۵۶۷۸۹';
    for (final rune in normalized.runes) {
      final c = String.fromCharCode(rune);
      final a = ai.indexOf(c);
      if (a >= 0) {
        out.write(a);
      } else {
        final e = ei.indexOf(c);
        if (e >= 0) {
          out.write(e);
        } else if (RegExp(r'[0-9]').hasMatch(c)) {
          out.write(c);
        }
      }
    }
    final direct = out.toString();
    if (direct.isNotEmpty) return direct;
    return normalized
        .split(RegExp(r'[\s,،.\-_/]+'))
        .map((x) => words[x] ?? '')
        .join();
  }

  String _recognizedForItem(_CalibrationItem item, String value) =>
      item.numeric ? _normalizeNumeric(value) : _normalizeArabic(value);

  String _expectedForItem(_CalibrationItem item) =>
      item.numeric ? _normalizeNumeric(item.text) : _normalizeArabic(item.text);

  @override
  void initState() {
    super.initState();
    _selectedLocale = AppCore.voiceLocale ?? 'ar-IQ';
    _loadVoiceSettings();
  }

  Future<void> _loadVoiceSettings() async {
    _voiceCapabilities = await AppCore.getVoiceProcessingCapabilities();
    await _scanSpeechSupport();
    if (mounted) setState(() {});
  }

  Future<void> _scanSpeechSupport() async {
    if (_speechTesting || _calibrating) return;
    if (mounted) setState(() => _speechError = null);

    try {
      if (!_speechInitialized) {
        final available = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            setState(() {
              _speechListening = status == 'listening';
              if (status != 'listening' && _speechTesting) {
                _speechTesting = false;
              }
            });
          },
          onError: (SpeechRecognitionError error) {
            if (!mounted) return;
            setState(() {
              _speechListening = false;
              _speechTesting = false;
              _speechError = error.errorMsg;
            });
          },
          debugLogging: false,
        );
        _speechInitialized = true;
        _speechAvailable = available;
      }

      if (!_speechAvailable) {
        if (mounted) {
          setState(() {
            _speechHasArabic = false;
            _arabicLocales = const [];
            _speechError = 'خدمة التعرف الصوتي نفسها غير متاحة على هذا الجهاز.';
          });
        }
        return;
      }

      final locales = await _speech.locales();
      final arabic = locales
          .where((x) => x.localeId.toLowerCase().startsWith('ar'))
          .toList();

      final saved = AppCore.voiceLocale;
      String selected = saved?.isNotEmpty == true ? saved! : 'ar-IQ';
      if (saved == null || saved!.isEmpty) {
        final iq = arabic.where((x) => x.localeId.toLowerCase() == 'ar-iq');
        if (iq.isNotEmpty) selected = iq.first.localeId;
        else if (arabic.isNotEmpty) selected = arabic.first.localeId;
      }

      if (!mounted) return;
      setState(() {
        _arabicLocales = arabic;
        _speechHasArabic = arabic.isNotEmpty;
        _selectedLocale = selected;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _speechError = 'تعذر فحص خدمة التعرف الصوتي: $e');
    }
  }

  Future<void> _startArabicTest() async {
    if (_speechTesting || _speechListening) {
      await _speech.stop();
      if (mounted) setState(() {
        _speechTesting = false;
        _speechListening = false;
      });
      return;
    }
    if (!_speechInitialized || !_speechAvailable) await _scanSpeechSupport();
    if (!_speechAvailable) return;

    final locale = _selectedLocale ?? 'ar-IQ';
    setState(() {
      _speechTesting = true;
      _speechListening = true;
      _recognizedText = '';
      _speechError = null;
    });

    try {
      await _speech.listen(
        localeId: locale,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(milliseconds: 1200),
        partialResults: true,
        onDevice: false,
        cancelOnError: true,
        onResult: (SpeechRecognitionResult result) async {
          if (!mounted) return;
          if (result.recognizedWords.trim().isNotEmpty) {
            setState(() => _recognizedText = result.recognizedWords.trim());
            await AppCore.saveVoiceLocale(locale);
          }
          if (result.finalResult && mounted) {
            setState(() {
              _speechTesting = false;
              _speechListening = false;
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechTesting = false;
        _speechListening = false;
        _speechError = 'فشل بدء اختبار العربية: $e';
      });
    }
  }

  Future<void> _saveLocale(String? value) async {
    if (value == null || value.isEmpty) return;
    await AppCore.saveVoiceLocale(value);
    if (!mounted) return;
    setState(() => _selectedLocale = value);
  }

  Future<String?> _recognizeOneCalibrationItem(_CalibrationItem item) async {
    final completer = Completer<String?>();
    Timer? timeout;
    void finish(String? value) {
      timeout?.cancel();
      if (!completer.isCompleted) completer.complete(value);
    }

    try {
      await _speech.listen(
        localeId: _selectedLocale ?? 'ar-IQ',
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(milliseconds: 1200),
        partialResults: true,
        onDevice: false,
        cancelOnError: true,
        onResult: (SpeechRecognitionResult result) {
          final text = result.recognizedWords.trim();
          if (text.isNotEmpty && result.finalResult) finish(text);
        },
      );
      timeout = Timer(const Duration(seconds: 6), () => finish(null));
      final value = await completer.future;
      await _speech.stop();
      return value;
    } catch (_) {
      finish(null);
      await _speech.stop();
      return completer.future;
    } finally {
      timeout?.cancel();
    }
  }

  Future<void> _runCalibration() async {
    if (_calibrating || !_speechAvailable) return;
    await _speech.stop();
    setState(() {
      _calibrating = true;
      _speechError = null;
      _calibrationIndex = 0;
      _calibrationPassed = 0;
      _calibrationMessage = '';
    });

    for (var i = 0; i < _calibrationItems.length; i++) {
      if (!mounted || !_calibrating) break;
      final item = _calibrationItems[i];
      setState(() {
        _calibrationIndex = i;
        _calibrationMessage = 'قل بوضوح: «${item.text}»';
        _speechListening = true;
      });

      final recognized = await _recognizeOneCalibrationItem(item);
      if (!mounted || !_calibrating) break;
      setState(() => _speechListening = false);

      if (recognized != null &&
          _recognizedForItem(item, recognized) == _expectedForItem(item)) {
        _calibrationPassed++;
      }
      setState(() {
        _calibrationMessage = recognized == null
            ? 'لم تصل نتيجة واضحة، سننتقل للعينة التالية.'
            : 'سمعت: «$recognized»';
      });
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }

    if (!mounted) return;
    final score = _calibrationPassed / _calibrationItems.length;
    await AppCore.saveVoiceCalibration(score);
    setState(() {
      _calibrating = false;
      _speechListening = false;
      _calibrationMessage = 'اكتملت المعايرة: $_calibrationPassed من ${_calibrationItems.length} عينات صحيحة.';
    });
  }

  Future<void> _stopCalibration() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _calibrating = false;
      _speechListening = false;
      _calibrationMessage = 'تم إيقاف المعايرة.';
    });
  }

  Future<void> _refreshNoiseInfo() async {
    setState(() => _noiseChecking = true);
    final info = await AppCore.getVoiceProcessingCapabilities();
    if (!mounted) return;
    setState(() {
      _voiceCapabilities = info;
      _noiseChecking = false;
    });
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Widget _card({required Color color, required Widget child}) => Card(
        color: color,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: child,
      );

  Widget _voiceSettingsCard({required Color cardColor, required Color textColor}) {
    final selected = _selectedLocale ?? 'ar-IQ';
    final calibrationPercent = (AppCore.voiceCalibrationScore * 100).round();
    return _card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.record_voice_over_rounded, color: Colors.blue, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Text('التعرف الصوتي', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17))),
              IconButton(
                tooltip: 'إعادة فحص الخدمة',
                onPressed: (_speechTesting || _calibrating) ? null : _scanSpeechSupport,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ]),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _speechAvailable ? Colors.green.withOpacity(.08) : Colors.orange.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _speechAvailable ? Colors.green.withOpacity(.25) : Colors.orange.withOpacity(.25)),
              ),
              child: Text(
                _speechAvailable
                    ? 'خدمة التعرف الصوتي: متاحة ✅\n${_speechHasArabic ? 'العربية ظاهرة في قائمة Android.' : 'العربية لا تظهر في قائمة Android، لذلك نعتمد على الاختبار الفعلي.'}'
                    : 'خدمة التعرف الصوتي غير متاحة ⚠️',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, height: 1.45),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _arabicCandidates.contains(selected) ? selected : 'ar-IQ',
              decoration: const InputDecoration(labelText: 'لغة التعرف الصوتي', border: OutlineInputBorder()),
              items: _arabicCandidates.map((id) {
                final detected = _arabicLocales.any((x) => x.localeId.toLowerCase() == id.toLowerCase());
                return DropdownMenuItem(value: id, child: Text(detected ? '${_localeLabel(id)} ✓' : _localeLabel(id)));
              }).toList(),
              onChanged: (_speechTesting || _calibrating) ? null : _saveLocale,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _speechAvailable ? (_speechTesting ? () => _speech.stop() : _startArabicTest) : null,
              icon: Icon(_speechTesting ? Icons.stop_circle_outlined : Icons.mic_rounded),
              label: Text(_speechTesting ? 'إيقاف الاختبار' : 'اختبار التعرف على العربية'),
            ),
            if (_speechListening && !_calibrating) ...[
              const SizedBox(height: 10),
              const Text('🎙️ استمع الآن... تحدث بالعربية.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            ],
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(.06), borderRadius: BorderRadius.circular(10)),
                child: Text('الناتج: $_recognizedText', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              ),
            ],
            if (_speechError != null) ...[
              const SizedBox(height: 8),
              Text(_speechError!, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
            ],
            if (_arabicLocales.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('لغات عربية اكتشفها Android: ${_arabicLocales.map((x) => x.localeId).join(', ')}', style: TextStyle(color: textColor.withOpacity(.65), fontSize: 11)),
            ],
            const Divider(height: 28),
            Row(children: [
              const Icon(Icons.tune_rounded, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(child: Text('معايرة التعرف لصوت المستخدم', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 6),
            Text(
              'سيطلب التطبيق نطق 3 كلمات و3 أرقام ويقارن النتائج. هذه معايرة واختبار لجودة التعرف على صوتك، وليست تدريباً داخلياً لنموذج Google؛ خدمة Android/Google هي التي تقوم بالتعرف الفعلي.',
              style: TextStyle(color: textColor.withOpacity(.7), fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 10),
            if (_calibrating) ...[
              LinearProgressIndicator(value: (_calibrationIndex + 1) / _calibrationItems.length),
              const SizedBox(height: 10),
              Text(_calibrationMessage, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _stopCalibration, icon: const Icon(Icons.stop), label: const Text('إيقاف المعايرة')),
            ] else ...[
              FilledButton.icon(onPressed: _speechAvailable ? _runCalibration : null, icon: const Icon(Icons.graphic_eq), label: const Text('ابدأ معايرة صوتي')),
              if (_calibrationMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_calibrationMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
              if (AppCore.voiceCalibrationCompleted)
                Text('نتيجة آخر معايرة: $calibrationPercent%', textAlign: TextAlign.center, style: TextStyle(color: textColor.withOpacity(.7), fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noiseCard({required Color cardColor, required Color textColor}) {
    final ns = _voiceCapabilities['noiseSuppressorAvailable'] == true;
    final aec = _voiceCapabilities['acousticEchoCancelerAvailable'] == true;
    return _card(
      color: cardColor,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.noise_aware_rounded, color: Colors.teal, size: 30),
          title: Text('تحسين الميكروفون وتقليل التشويش', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text('يحاول تفعيل معالجة الصوت الخاصة بالنظام أثناء التعرف الصوتي.', style: TextStyle(color: textColor.withOpacity(.65), height: 1.3)),
          trailing: Switch(
            value: AppCore.voiceEnhancementEnabled,
            activeColor: Colors.teal,
            onChanged: (value) async {
              await AppCore.saveVoiceEnhancement(value);
              if (value) await AppCore.setVoiceEnhancement(true);
              else await AppCore.setVoiceEnhancement(false);
              if (mounted) setState(() {});
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(children: [
            Expanded(child: Text(
              'مانع التشويش في الجهاز: ${ns ? 'متاح ✓' : 'غير ظاهر'}\nإلغاء الصدى AEC: ${aec ? 'متاح ✓' : 'غير ظاهر'}',
              style: TextStyle(color: textColor.withOpacity(.72), fontSize: 12, height: 1.5),
            )),
            IconButton(onPressed: _noiseChecking ? null : _refreshNoiseInfo, icon: const Icon(Icons.refresh_rounded)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        final isDark = currentMode == ThemeMode.dark;
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('الإعدادات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]))),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _card(
                color: cardColor,
                child: ListTile(
                  leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.amber, size: 30),
                  title: Text('الوضع الداكن (Dark Mode)', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: Switch(value: isDark, activeColor: Colors.amber, onChanged: (val) async { await AppCore.saveThemePreference(val); if (mounted) setState(() {}); }),
                ),
              ),
              const SizedBox(height: 15),
              _card(
                color: cardColor,
                child: Column(children: [
                  ListTile(
                    leading: Icon(AppCore.isAudioMuted ? Icons.volume_off : Icons.music_note, color: Colors.blue, size: 30),
                    title: Text('الموسيقى الهادئة', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    trailing: Switch(value: !AppCore.isAudioMuted, activeColor: Colors.blue, onChanged: (val) async { await AppCore.toggleAudio(); if (mounted) setState(() {}); }),
                  ),
                  if (!AppCore.isAudioMuted)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.volume_down, color: Colors.grey),
                        Expanded(child: Slider(value: AppCore.currentVolume, min: 0, max: 1, divisions: 10, label: '${(AppCore.currentVolume * 100).round()}%', onChanged: (val) async { setState(() => AppCore.currentVolume = val); await AppCore.setVolume(val); })),
                        const Icon(Icons.volume_up, color: Colors.grey),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 15),
              _voiceSettingsCard(cardColor: cardColor, textColor: textColor),
              const SizedBox(height: 15),
              _noiseCard(cardColor: cardColor, textColor: textColor),
              const SizedBox(height: 28),
              const Text('نسخة غير رسمية', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              const Text('تصميم/ علي الفتلاوي / ثانوية الديوانية للمتميزين', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
