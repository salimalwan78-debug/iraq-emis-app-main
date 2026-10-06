import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_core.dart';
import 'google_speech_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingGoogleSpeech = true;
  bool _googleSpeechAvailable = false;
  String _googleSpeechMessage = 'جاري فحص خدمة Google...';

  @override
  void initState() {
    super.initState();
    _checkGoogleSpeech();
  }

  Future<void> _checkGoogleSpeech() async {
    try {
      final info = await GoogleSpeechService.getInfo();
      final available = info['available'] == true;
      final googleAvailable = info['googleAvailable'] == true;
      final provider = '${info['provider'] ?? ''}'.trim();
      final defaultPackage = '${info['defaultPackage'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        _googleSpeechAvailable = available;
        _checkingGoogleSpeech = false;
        if (!available) {
          _googleSpeechMessage =
              'لا توجد خدمة تعرف صوتي افتراضية متاحة في Android. افتح إعدادات إدخال الصوت وتأكد من تفعيل خدمة التعرف.';
        } else if (googleAvailable) {
          _googleSpeechMessage =
              'Google متاحة مباشرة. مزود التعرف الحالي: ${provider.isEmpty ? 'Google' : provider}.';
        } else {
          _googleSpeechMessage =
              'تطبيق Google مثبت، لكن Android لا يعرضه كخدمة مستقلة. سيتم استخدام خدمة التعرف الافتراضية${defaultPackage.isEmpty ? '' : ' ($defaultPackage)'}، وقد تكون Google.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingGoogleSpeech = false;
        _googleSpeechAvailable = false;
        _googleSpeechMessage = 'تعذر فحص خدمات التعرف الصوتي في Android.';
      });
    }
  }

  Future<void> _setVoiceEngine(String? engine) async {
    if (engine == null) return;
    await AppCore.setVoiceRecognitionEngine(engine);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setVoiceEnabled(bool enabled) async {
    if (enabled) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب منح التطبيق صلاحية الميكروفون من إعدادات Android أولاً.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    await AppCore.setVoiceInputEnabled(enabled);
    if (mounted) setState(() {});
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
            title: const Text(
              'الإعدادات',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    color: Colors.amber,
                    size: 30,
                  ),
                  title: Text(
                    'الوضع الداكن (Dark Mode)',
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  trailing: Switch(
                    value: isDark,
                    activeColor: Colors.amber,
                    onChanged: (val) async {
                      await AppCore.saveThemePreference(val);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Card(
                color: cardColor,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        AppCore.isAudioMuted ? Icons.volume_off : Icons.music_note,
                        color: Colors.blue,
                        size: 30,
                      ),
                      title: Text(
                        'الموسيقى الهادئة',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      trailing: Switch(
                        value: !AppCore.isAudioMuted,
                        activeColor: Colors.blue,
                        onChanged: (val) async {
                          await AppCore.toggleAudio();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    if (!AppCore.isAudioMuted)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.volume_down, color: Colors.grey),
                            Expanded(
                              child: Slider(
                                value: AppCore.currentVolume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label: '${(AppCore.currentVolume * 100).round()}%',
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
              Card(
                color: cardColor,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        AppCore.voiceInputEnabled ? Icons.mic : Icons.mic_off,
                        color: AppCore.voiceInputEnabled ? Colors.green : Colors.red,
                        size: 30,
                      ),
                      title: Text(
                        'الميكروفون والتعرف الصوتي',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Text(
                        'اختيار محرك التعرف الصوتي المستخدم في حقول إضافة الطالب',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], height: 1.35),
                      ),
                      value: AppCore.voiceInputEnabled,
                      activeColor: Colors.green,
                      onChanged: _setVoiceEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: DropdownButtonFormField<String>(
                        value: AppCore.voiceRecognitionEngine,
                        decoration: InputDecoration(
                          labelText: 'محرك التعرف الصوتي',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: isDark ? Colors.black26 : const Color(0xFFF7F8FA),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'google',
                            child: Text('Google / خدمة Android الافتراضية'),
                          ),
                          DropdownMenuItem(
                            value: 'legacy',
                            child: Text('التعرف السابق (speech_to_text)'),
                          ),
                        ],
                        onChanged: _setVoiceEngine,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.green.withOpacity(.10) : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.green.shade800 : Colors.green.shade200,
                          ),
                        ),
                        child: const Text(
                          'خدمة Google هنا ليست Google Cloud المدفوعة: التطبيق يستخدم SpeechRecognizer الموجود في Android مع مزود التعرف الموجود على الجهاز. لا يحتاج هذا المسار إلى مفتاح API أو اشتراك Google Cloud، لكن قد يستخدم اتصال الإنترنت وبيانات الهاتف عند اعتماد الخدمة على التعرف الشبكي.',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontWeight: FontWeight.w600, height: 1.45, fontSize: 12),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _checkingGoogleSpeech
                                ? Icons.sync
                                : (_googleSpeechAvailable ? Icons.cloud_done : Icons.warning_amber_rounded),
                            color: _checkingGoogleSpeech
                                ? Colors.blue
                                : (_googleSpeechAvailable ? Colors.green : Colors.orange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _googleSpeechMessage,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'إعادة الفحص',
                            onPressed: _checkingGoogleSpeech ? null : _checkGoogleSpeech,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Card(
                color: cardColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'الخيار الأول يستخدم Android SpeechRecognizer مع خدمة Google عندما تكون متاحة مباشرة، وإذا لم تكن ظاهرة كخدمة مستقلة يستخدم مزود التعرف الافتراضي في Android. إذا بقي التعرف غير مناسب، اختر «التعرف السابق (speech_to_text)» للعودة إلى الطريقة التي كانت تعمل سابقاً. عند إيقاف الميكروفون لن تعمل أزراره في صفحة إضافة الطالب حتى تعيد تفعيله من هنا.',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w600, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Center(
                child: Text(
                  'نسخة غير رسمية',
                  style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 5),
              const Center(
                child: Text(
                  'تصميم/ علي الفتلاوي / ثانوية الديوانية للمتميزين',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14),
                  textAlign: TextAlign.center,
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
