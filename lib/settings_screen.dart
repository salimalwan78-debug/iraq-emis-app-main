import 'package:flutter/material.dart';
import 'app_core.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        bool isDark = currentMode == ThemeMode.dark;
        Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        Color textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('الإعدادات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]))), 
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Card(
                  color: cardColor, elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: Colors.amber, size: 30),
                    title: Text('الوضع الداكن (Dark Mode)', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    trailing: Switch(
                      value: isDark, 
                      activeColor: Colors.amber, 
                      onChanged: (val) async {
                        await AppCore.saveThemePreference(val);
                        setState(() {});
                      }
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Card(
                  color: cardColor, elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(AppCore.isAudioMuted ? Icons.volume_off : Icons.music_note, color: Colors.blue, size: 30),
                        title: Text('الموسيقى الهادئة', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                        trailing: Switch(
                          value: !AppCore.isAudioMuted, activeColor: Colors.blue,
                          onChanged: (val) async { 
                            await AppCore.toggleAudio(); 
                            setState(() {}); 
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
                
                const Spacer(),
                const Text('نسخة غير رسمية', style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('تصميم/ علي الفتلاوي / ثانوية الديوانية للمتميزين', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      }
    );
  }
}
