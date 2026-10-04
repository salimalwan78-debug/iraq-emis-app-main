import 'package:flutter/material.dart';

import 'app_core.dart';
import 'batch_teacher_photos_screen.dart';

class TeacherSmartToolsScreen extends StatelessWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allTeachers;

  const TeacherSmartToolsScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allTeachers,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, mode, child) {
        final isDark = mode == ThemeMode.dark;
        final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final text = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('الأدوات الذكية للمعلمين', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            centerTitle: true,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF4527A0), Color(0xFF7E57C2)]),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4527A0), Color(0xFF7E57C2)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('أدوات ذكية لإدارة المعلمين', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('تنفيذ المهام الجماعية مباشرة على بيانات المعلمين المحملة في التطبيق.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _toolCard(
                context,
                title: 'إضافة صور المعلمين جماعيًا',
                subtitle: 'التقاط صور المعلمين أو اختيارها من الجهاز وحفظها بالتتابع مع الاحتفاظ بسجل الجلسة.',
                icon: Icons.camera_front_rounded,
                color: Colors.deepPurple,
                card: card,
                text: text,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchTeacherPhotosScreen(
                      token: token,
                      schoolId: schoolId,
                      allTeachers: allTeachers,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color card,
    required Color text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: color.withOpacity(0.10), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: text)),
                  const SizedBox(height: 7),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 17, color: color),
          ],
        ),
      ),
    );
  }
}
