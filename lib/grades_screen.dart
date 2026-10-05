import 'package:flutter/material.dart';
import 'grade_entry_screen.dart';
import 'grade_smart_tools_screen.dart';
import 'app_core.dart';

class GradesScreen extends StatelessWidget {
  final String token;
  final String schoolId;
  final List<Map<String, dynamic>> stages;
  final Map<String, List<Map<String, dynamic>>> subjectsByStage;
  final Map<String, List<Map<String, dynamic>>> examsBySubject;

  const GradesScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.stages,
    required this.subjectsByStage,
    required this.examsBySubject,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return Scaffold(
          backgroundColor:
              dark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text(
              'الدرجات',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 23,
              ),
            ),
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                ),
              ),
            ),
          ),
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _header(dark),
                const SizedBox(height: 18),
                _actionCard(
                  context,
                  dark: dark,
                  title: 'إدخال الدرجات',
                  subtitle:
                      'اختيار الصف والمادة والشعبة والفصل وإدخال درجات الطلاب وحفظها مباشرة في EMIS.',
                  icon: Icons.edit_note_rounded,
                  iconColor: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GradeEntryScreen(
                        token: token,
                        schoolId: schoolId,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                _actionCard(
                  context,
                  dark: dark,
                  title: 'الأدوات الذكية للدرجات',
                  subtitle:
                      'إهمال أو إلغاء إهمال فصل أو عدة فصول مع اختيار الصفوف والمواد من بيانات EMIS.',
                  icon: Icons.auto_awesome_rounded,
                  iconColor: const Color(0xFF3949AB),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GradeSmartToolsScreen(
                        token: token,
                        schoolId: schoolId,
                        stages: stages,
                        subjectsByStage: subjectsByStage,
                        examsBySubject: examsBySubject,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(bool dark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 6),
            color: Colors.black12,
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            child: Icon(
              Icons.bar_chart_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إدارة الدرجات',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'أدوات منفصلة لإدخال الدرجات وإدارة الإهمال',
                  style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required bool dark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: iconColor, size: 31),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(fontWeight: FontWeight.bold,
                        color: dark ? Colors.white60 : Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: dark ? Colors.white54 : Colors.black45,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
