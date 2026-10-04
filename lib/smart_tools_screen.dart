import 'package:flutter/material.dart';

import 'aa_removal_tool_screen.dart';
import 'batch_student_photos_screen.dart';
import 'app_core.dart';
import 'student_distribution_screen.dart';
import 'student_stage_transfer_screen.dart';

class SmartToolsScreen extends StatelessWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;

  const SmartToolsScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allStudents,
  });

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
              'الأدوات الذكية',
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أدوات ذكية لإدارة الطلاب',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'تنفيذ المهام مباشرة على البيانات المحملة في التطبيق دون إعادة تحميل القائمة.',
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildToolCard(
                context,
                title: 'حذف AA من أرقام الهوية',
                subtitle: 'إزالة AA والأصفار التي تليها من بداية رقم الهوية وتحديث الطالب مباشرة.',
                icon: Icons.badge_outlined,
                color: Colors.deepOrange,
                cardColor: cardColor,
                textColor: textColor,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AARemovalToolScreen(
                      token: token,
                      schoolId: schoolId,
                      allStudents: allStudents,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              _buildToolCard(
                context,
                title: 'توزيع الطلاب على الشُعَب',
                subtitle: 'اختر الصف ثم الشعبة المستهدفة وحدد مجموعة الطلاب لتنفيذ التوزيع.',
                icon: Icons.groups_2_outlined,
                color: Colors.green,
                cardColor: cardColor,
                textColor: textColor,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentDistributionScreen(token: token, schoolId: schoolId, allStudents: allStudents))),
              ),
              const SizedBox(height: 15),
              _buildToolCard(
                context,
                title: 'ترحيل الطلاب بين الصفوف',
                subtitle: 'اختر الصف الحالي والصف المستهدف ثم حدد الطلاب المراد ترحيلهم.',
                icon: Icons.move_up_outlined,
                color: Colors.deepOrange,
                cardColor: cardColor,
                textColor: textColor,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentStageTransferScreen(token: token, schoolId: schoolId, allStudents: allStudents))),
              ),
              const SizedBox(height: 15),
              _buildToolCard(
                context,
                title: 'إضافة صور الطلاب جماعيًا',
                subtitle: 'اختر الصف والشعبة من أعلى صفحة الأداة، ثم التقط الصورة أو اخترها من الجهاز واحفظ الطالب التالي.',
                icon: Icons.camera_front_rounded,
                color: Colors.blueAccent,
                cardColor: cardColor,
                textColor: textColor,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BatchStudentPhotosScreen(
                      token: token,
                      schoolId: schoolId,
                      allStudents: allStudents,
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

  Widget _buildToolCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor)),
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
