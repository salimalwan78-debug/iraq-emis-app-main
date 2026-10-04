import 'package:flutter/material.dart';
import 'select_student_screen.dart';
import 'app_core.dart';
import 'smart_tools_screen.dart';
import 'add_student_screen.dart';
import 'deactivated_students_screen.dart';

class StudentManagementScreen extends StatelessWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;
  const StudentManagementScreen({super.key, required this.token, required this.schoolId, required this.allStudents});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        final dark = currentMode == ThemeMode.dark;
        return Scaffold(
          backgroundColor: dark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text('إدارة الطلاب', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF1A237E),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'إضافة طالب جديد',
                icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => AddStudentScreen(token: token, schoolId: schoolId)));
                },
              ),
              IconButton(
                tooltip: 'الطلبة غير المفعلين',
                icon: const Icon(Icons.person_off_outlined, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeactivatedStudentsScreen(token: token, schoolId: schoolId))),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(children: [
              _buildCard(context, 'تعديل بيانات الطلاب', 'عرض جميع طلاب المدرسة ثم تصفيتهم حسب الصف والشعبة', Icons.edit_document, Colors.indigo, dark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => SelectStudentScreen(token: token, schoolId: schoolId, preLoadedStudents: allStudents)))),
              const SizedBox(height: 15),
              _buildCard(context, 'الأدوات الذكية', 'حذف AA وإضافة صور الطلاب وتوزيعهم وترحيلهم', Icons.auto_awesome, Colors.teal, dark, () => Navigator.push(context, MaterialPageRoute(builder: (_) => SmartToolsScreen(token: token, schoolId: schoolId, allStudents: allStudents)))),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, String title, String sub, IconData icon, Color color, bool dark, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Card(
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(.10), shape: BoxShape.circle), child: Icon(icon, color: color, size: 30)),
        title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.grey)),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: dark ? Colors.white54 : Colors.black54),
      ),
    ),
  );
}
