import 'package:flutter/material.dart';
import 'grade_smart_tools_card.dart';

class GradeSmartToolsScreen extends StatelessWidget {
  final String token;
  final String schoolId;

  const GradeSmartToolsScreen({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الأدوات الذكية للدرجات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          padding: const EdgeInsets.all(16),
          children: [
            GradeSmartToolsCard(
              token: token,
              schoolId: schoolId,
            ),
          ],
        ),
      ),
    );
  }
}
