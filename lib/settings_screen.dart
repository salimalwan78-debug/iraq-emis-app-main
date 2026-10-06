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

  Future<void> _setVoiceSetting({
    bool? autoRestart,
    int? possibleSilenceMs,
    int? completeSilenceMs,
    int? minimumSpeechMs,
    int? restartDelayMs,
    int? finalizationTimeoutMs,
    double? arrowOpacity,
  }) async {
    await AppCore.saveVoiceSettings(
      autoRestart: autoRestart,
      possibleSilenceMs: possibleSilenceMs,
      completeSilenceMs: completeSilenceMs,
      minimumSpeechMs: minimumSpeechMs,
      restartDelayMs: restartDelayMs,
      finalizationTimeoutMs: finalizationTimeoutMs,
      arrowOpacity: arrowOpacity,
    );
    if (mounted) setState(() {});
  }

  Future<void> _resetVoiceSettings() async {
    await AppCore.resetVoiceSettings();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إعادة جميع إعدادات الميكروفون إلى القيم الافتراضية.')),
    );
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

  Widget _voiceSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) formatter,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(formatter(value), style: TextStyle(color: isDark ? Colors.lightGreenAccent : Colors.green.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: formatter(value),
          onChanged: onChanged,
        ),
      ],
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
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: Colors.green, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ضبط الميكروفون والتعرف الصوتي',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _resetVoiceSettings,
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('الافتراضي'),
                          ),
                        ],
                      ),
                      const Divider(),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إعادة الاستماع تلقائياً'),
                        subtitle: const Text('إذا أنهت خدمة Google جلسة بسبب الصمت أو النتيجة، يعيد التطبيق الاستماع تلقائياً ما دام المستخدم لم يضغط لإيقاف الميكروفون.'),
                        value: AppCore.voiceAutoRestart,
                        onChanged: (v) => _setVoiceSetting(autoRestart: v),
                      ),
                      const SizedBox(height: 8),
                      _voiceSlider(
                        context,
                        label: 'الصمت المحتمل قبل إنهاء الجملة',
                        value: AppCore.voicePossibleSilenceMs.toDouble(),
                        min: 1000,
                        max: 30000,
                        divisions: 58,
                        formatter: (v) => '${(v / 1000).toStringAsFixed(1)} ث',
                        onChanged: (v) => _setVoiceSetting(possibleSilenceMs: v.round()),
                      ),
                      _voiceSlider(
                        context,
                        label: 'الصمت المؤكد قبل إنهاء الجلسة',
                        value: AppCore.voiceCompleteSilenceMs.toDouble(),
                        min: 1000,
                        max: 30000,
                        divisions: 58,
                        formatter: (v) => '${(v / 1000).toStringAsFixed(1)} ث',
                        onChanged: (v) => _setVoiceSetting(completeSilenceMs: v.round()),
                      ),
                      _voiceSlider(
                        context,
                        label: 'الحد الأدنى لبدء التقاط الكلام',
                        value: AppCore.voiceMinimumSpeechMs.toDouble(),
                        min: 100,
                        max: 3000,
                        divisions: 29,
                        formatter: (v) => '${v.round()} مللي ثانية',
                        onChanged: (v) => _setVoiceSetting(minimumSpeechMs: v.round()),
                      ),
                      _voiceSlider(
                        context,
                        label: 'الفاصل بين جلسات التعرف',
                        value: AppCore.voiceRestartDelayMs.toDouble(),
                        min: 0,
                        max: 5000,
                        divisions: 50,
                        formatter: (v) => '${v.round()} مللي ثانية',
                        onChanged: (v) => _setVoiceSetting(restartDelayMs: v.round()),
                      ),
                      _voiceSlider(
                        context,
                        label: 'مهلة إنهاء الجلسة عند الضغط على الإيقاف',
                        value: AppCore.voiceFinalizationTimeoutMs.toDouble(),
                        min: 500,
                        max: 3000,
                        divisions: 25,
                        formatter: (v) => '${v.round()} مللي ثانية',
                        onChanged: (v) => _setVoiceSetting(finalizationTimeoutMs: v.round()),
                      ),
                      _voiceSlider(
                        context,
                        label: 'شفافية الأسهم الثابتة',
                        value: ((1.0 - AppCore.voiceArrowOpacity) * 100).clamp(10.0, 80.0),
                        min: 10,
                        max: 80,
                        divisions: 14,
                        formatter: (v) => '${v.round()}%',
                        onChanged: (v) => _setVoiceSetting(arrowOpacity: 1.0 - v / 100.0),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'زيادة الشفافية تجعل الأسهم أقل تغطية للحقول الموجودة خلفها. الإعدادات الزمنية تؤثر على مسار Google/Android ولا تُجبر خدمة Google إذا كانت تفرض حدوداً داخلية خاصة بها.',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], height: 1.45, fontSize: 12),
                      ),
                    ],
                  ),
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
