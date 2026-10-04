import 'package:flutter/material.dart';
import 'student_management_screen.dart';
import 'teachers_list_screen.dart';
import 'settings_screen.dart';
import 'app_core.dart';
import 'grades_screen.dart';

class DashboardScreen extends StatelessWidget {
  final String token;
  final String schoolId;
  final String schoolName;
  final String userName;
  final List<dynamic> allStudents;
  final List<dynamic> allTeachers;

  const DashboardScreen({
    super.key, required this.token, required this.schoolId,
    required this.schoolName, required this.userName,
    required this.allStudents, required this.allTeachers,
  });

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
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // إزالة صورة التلميذ واستبدالها بأيقونة مستخدم احترافية
                    Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 40),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('مرحباً أستاذ،', style: TextStyle(color: Colors.white70, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text(userName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.school, color: Colors.amber, size: 18),
                                const SizedBox(width: 5),
                                Flexible(child: Text(schoolName, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white, size: 30),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatCard('إجمالي المعلمين', allTeachers.length.toString(), Icons.work, Colors.orange, cardColor, textColor),
                    const SizedBox(width: 15),
                    _buildStatCard('إجمالي الطلاب', allStudents.length.toString(), Icons.people, Colors.blue, cardColor, textColor),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.95,
                  children: [
                    _buildMenuCard(title: 'إدارة الطلاب', icon: Icons.people_alt_rounded, color: Colors.blueAccent, cardColor: cardColor, textColor: textColor, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => StudentManagementScreen(token: token, schoolId: schoolId, allStudents: allStudents)));
                    }),
                    _buildMenuCard(title: 'إدارة المعلمين', icon: Icons.work_rounded, color: Colors.deepPurple, cardColor: cardColor, textColor: textColor, onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => TeachersListScreen(token: token, schoolId: schoolId, initialTeachers: allTeachers)));
                    }),
                    _buildMenuCard(title: 'الدرجات', icon: Icons.bar_chart_rounded, color: Colors.orange, cardColor: cardColor, textColor: textColor, onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => GradesScreen(token: token, schoolId: schoolId))); }),
                    _buildMenuCard(title: 'إرسال البيانات', icon: Icons.cloud_upload_rounded, color: Colors.green, cardColor: cardColor, textColor: textColor, onTap: () {}),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon, Color color, Color cardColor, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
        child: Column(
          children: [
            Icon(icon, color: color, size: 35),
            const SizedBox(height: 10),
            Text(count, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 5),
            Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({required String title, required IconData icon, required Color color, required Color cardColor, required Color textColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(25),
      child: Container(
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 45, color: color)),
            const SizedBox(height: 15),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }
}
