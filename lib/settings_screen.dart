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

class _SettingsScreenState extends State<SettingsScreen> {
  final SpeechToText _speech = SpeechToText();

  bool _speechInitialized = false;
  bool _speechAvailable = false;
  bool _speechTesting = false;
  bool _speechListening = false;
  bool _speechHasArabic = false;
  String? _selectedLocale;
  String? _speechError;
  String _recognizedText = '';
  List<LocaleName> _arabicLocales = const [];

  static const List<String> _arabicCandidates = [
    'ar-IQ',
    'ar-SA',
    'ar-AE',
    'ar-EG',
    'ar-JO',
    'ar-KW',
    'ar-BH',
    'ar-QA',
    'ar-OM',
    'ar-YE',
    'ar-LB',
    'ar-SY',
    'ar-PS',
    'ar-MA',
    'ar-DZ',
    'ar-TN',
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

  @override
  void initState() {
    super.initState();
    _scanSpeechSupport();
  }

  Future<void> _scanSpeechSupport() async {
    if (_speechTesting) return;

    setState(() {
      _speechError = null;
    });

    try {
      if (!_speechInitialized) {
        final available = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            final listening = status == 'listening';
            setState(() {
              _speechListening = listening;
              if (!listening && _speechTesting) {
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
        if (!mounted) return;
        setState(() {
          _speechHasArabic = false;
          _arabicLocales = const [];
          _speechError = 'خدمة التعرف الصوتي نفسها غير متاحة على هذا الجهاز.';
        });
        return;
      }

      final locales = await _speech.locales();
      final arabic = locales
          .where((x) => x.localeId.toLowerCase().startsWith('ar'))
          .toList();

      final saved = AppCore.voiceLocale;
      String? selected;

      if (saved != null && saved.isNotEmpty) {
        selected = saved;
      } else if (arabic.any((x) => x.localeId.toLowerCase() == 'ar-iq')) {
        selected = arabic
            .firstWhere(
              (x) => x.localeId.toLowerCase() == 'ar-iq',
            )
            .localeId;
      } else if (arabic.isNotEmpty) {
        selected = arabic.first.localeId;
      } else {
        // عدم ظهور العربية في locales() لا يعني بالضرورة أن Google
        // لا يستطيع التعرف عليها؛ لذلك نضع ar-IQ للاختبار الفعلي.
        selected = 'ar-IQ';
      }

      if (!mounted) return;
      setState(() {
        _arabicLocales = arabic;
        _speechHasArabic = arabic.isNotEmpty;
        _selectedLocale = selected;
        _speechError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechError = 'تعذر فحص خدمة التعرف الصوتي: $e';
      });
    }
  }

  Future<void> _startArabicTest() async {
    if (_speechTesting || _speechListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _speechTesting = false;
          _speechListening = false;
        });
      }
      return;
    }

    if (!_speechInitialized || !_speechAvailable) {
      await _scanSpeechSupport();
    }

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
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        onDevice: false,
        cancelOnError: true,
        onResult: (SpeechRecognitionResult result) async {
          if (!mounted) return;

          final text = result.recognizedWords.trim();
          if (text.isNotEmpty) {
            setState(() {
              _recognizedText = text;
            });

            // نجاح التعرف الفعلي أهم من مجرد ظهور اللغة في locales().
            await AppCore.saveVoiceLocale(locale);

            if (result.finalResult && mounted) {
              setState(() {
                _speechTesting = false;
                _speechListening = false;
                _speechError = null;
              });
            }
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

  Future<void> _stopArabicTest() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _speechTesting = false;
      _speechListening = false;
    });
  }

  Future<void> _saveLocale(String? value) async {
    if (value == null || value.isEmpty) return;
    await AppCore.saveVoiceLocale(value);
    if (!mounted) return;
    setState(() {
      _selectedLocale = value;
    });
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Widget _voiceSettingsCard({
    required bool isDark,
    required Color cardColor,
    required Color textColor,
  }) {
    final selected = _selectedLocale ?? 'ar-IQ';

    return Card(
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    color: Colors.blue, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'التعرف الصوتي',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إعادة فحص الخدمة',
                  onPressed: _speechTesting ? null : _scanSpeechSupport,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _speechAvailable
                    ? Colors.green.withOpacity(.08)
                    : Colors.orange.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _speechAvailable
                      ? Colors.green.withOpacity(.25)
                      : Colors.orange.withOpacity(.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _speechAvailable
                        ? 'خدمة التعرف الصوتي: متاحة ✅'
                        : 'خدمة التعرف الصوتي: غير متاحة ⚠️',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _speechHasArabic
                        ? 'العربية ظاهرة ضمن لغات Android المتاحة.'
                        : 'العربية لا تظهر في قائمة Android، لكن هذا لا يعني أن Google لا يستطيع التعرف عليها. سيتم اختبارها فعلياً.',
                    style: TextStyle(
                      color: textColor.withOpacity(.75),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(
                labelText: 'لغة التعرف الصوتي',
                border: OutlineInputBorder(),
              ),
              items: _arabicCandidates.map((id) {
                final detected =
                    _arabicLocales.any((x) => x.localeId == id);
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(
                    detected
                        ? '${_localeLabel(id)}  ✓'
                        : _localeLabel(id),
                  ),
                );
              }).toList(),
              onChanged: _speechTesting ? null : _saveLocale,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _speechAvailable ? (_speechTesting ? _stopArabicTest : _startArabicTest) : null,
              icon: Icon(
                _speechTesting
                    ? Icons.stop_circle_outlined
                    : Icons.mic_rounded,
              ),
              label: Text(
                _speechTesting
                    ? 'إيقاف اختبار العربية'
                    : 'اختبار التعرف على العربية',
              ),
            ),
            if (_speechListening) ...[
              const SizedBox(height: 10),
              const Text(
                '🎙️ استمع الآن... تحدث بالعربية.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'الناتج: $_recognizedText',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'التعرف على العربية يعمل فعلياً ✅ وسيُستخدم هذا الإعداد في صفحة إضافة الطالب.',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_speechError != null) ...[
              const SizedBox(height: 8),
              Text(
                _speechError!,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_arabicLocales.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'لغات عربية اكتشفها Android: ${_arabicLocales.map((x) => x.localeId).join(', ')}',
                style: TextStyle(
                  color: textColor.withOpacity(.65),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        final isDark = currentMode == ThemeMode.dark;
        final bgColor =
            isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              'الإعدادات',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: cardColor,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  leading: Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    color: Colors.amber,
                    size: 30,
                  ),
                  title: Text(
                    'الوضع الداكن (Dark Mode)',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: Switch(
                    value: isDark,
                    activeColor: Colors.amber,
                    onChanged: (val) async {
                      await AppCore.saveThemePreference(val);
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Card(
                color: cardColor,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        AppCore.isAudioMuted
                            ? Icons.volume_off
                            : Icons.music_note,
                        color: Colors.blue,
                        size: 30,
                      ),
                      title: Text(
                        'الموسيقى الهادئة',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      trailing: Switch(
                        value: !AppCore.isAudioMuted,
                        activeColor: Colors.blue,
                        onChanged: (val) async {
                          await AppCore.toggleAudio();
                          setState(() {});
                        },
                      ),
                    ),
                    if (!AppCore.isAudioMuted)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.volume_down, color: Colors.grey),
                            Expanded(
                              child: Slider(
                                value: AppCore.currentVolume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label:
                                    '${(AppCore.currentVolume * 100).round()}%',
                                onChanged: (val) async {
                                  setState(() => AppCore.currentVolume = val);
                                  await AppCore.setVolume(val);
                                },
                              ),
                            ),
                            const Icon(Icons.volume_up, color: Colors.grey),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              _voiceSettingsCard(
                isDark: isDark,
                cardColor: cardColor,
                textColor: textColor,
              ),
              const SizedBox(height: 30),
              const Text(
                'نسخة غير رسمية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'تصميم/ علي الفتلاوي / ثانوية الديوانية للمتميزين',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
