import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dashboard_screen.dart';
import 'app_core.dart';

class LoadingDataScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  const LoadingDataScreen({super.key, required this.token, required this.schoolId});

  @override
  State<LoadingDataScreen> createState() => _LoadingDataScreenState();
}

class _LoadingDataScreenState extends State<LoadingDataScreen>
    with SingleTickerProviderStateMixin {
  String _statusText = 'جاري الاتصال بخوادم EMIS...';
  double _progressValue = .08;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    AppCore.playRelaxMusic();
    _startFetchingData();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _startFetchingData() async {
    final authHeader = widget.token.toLowerCase().startsWith('bearer ')
        ? widget.token
        : 'Bearer ${widget.token}';
    final headers = {
      'Authorization': authHeader,
      'Accept': 'application/json, text/plain, */*',
    };

    try {
      setState(() {
        _statusText = 'جاري جلب بيانات المستخدم...';
        _progressValue = .20;
      });
      String realUserName = 'مستخدم النظام';
      final userRes = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/account/getloggedinuser'),
        headers: headers,
      );
      if (userRes.statusCode == 200) {
        final data = jsonDecode(utf8.decode(userRes.bodyBytes));
        if (data is Map) {
          realUserName =
              '${data['employeeName'] ?? data['fullName'] ?? realUserName}';
        }
      }

      setState(() {
        _statusText = 'جاري جلب بيانات المدرسة...';
        _progressValue = .38;
      });
      final schoolRes = await http.get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/school/getschoolinformation/${widget.schoolId}',
        ),
        headers: headers,
      );
      final schoolData = schoolRes.statusCode == 200
          ? jsonDecode(utf8.decode(schoolRes.bodyBytes))
          : <String, dynamic>{};

      setState(() {
        _statusText = 'جاري تحميل سجلات الطلاب...';
        _progressValue = .63;
      });
      final studentsRes = await http.get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/student/getstudents?page=1&rowsPerPage=3000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}',
        ),
        headers: headers,
      );
      final decodedStudents = studentsRes.statusCode == 200
          ? jsonDecode(utf8.decode(studentsRes.bodyBytes))
          : <String, dynamic>{};
      final studentsData = decodedStudents is Map && decodedStudents['data'] is List
          ? decodedStudents['data']
          : <dynamic>[];

      setState(() {
        _statusText = 'جاري تحميل سجلات المعلمين...';
        _progressValue = .82;
      });
      final teachersRes = await http.get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/employee/getemployeesbyentities?page=1&rowsPerPage=1000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}&isTeacher=true',
        ),
        headers: headers,
      );
      final decodedTeachers = teachersRes.statusCode == 200
          ? jsonDecode(utf8.decode(teachersRes.bodyBytes))
          : <String, dynamic>{};
      final teachersData = decodedTeachers is Map && decodedTeachers['data'] is List
          ? decodedTeachers['data']
          : <dynamic>[];

      setState(() {
        _statusText = 'اكتملت المزامنة — تجهيز التطبيق...';
        _progressValue = 1;
      });
      await Future.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            token: authHeader,
            schoolId: widget.schoolId,
            schoolName: schoolData is Map
                ? '${schoolData['schoolName'] ?? 'المدرسة'}'
                : 'المدرسة',
            userName: realUserName,
            allStudents: studentsData,
            allTeachers: teachersData,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'تعذر تحميل البيانات. تحقق من الاتصال ثم أعد المحاولة.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF172A88), Color(0xFF2F78D0), Color(0xFFF4F7FC)],
            stops: [0, .55, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Transform.scale(
                      scale: 1 + (_pulse.value * .035),
                      child: Container(
                        width: 175,
                        height: 175,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.96),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.18),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/avatar.jpg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'مساعد EMIS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'مساعد الإدارة المدرسية',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.14),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sync_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _statusText,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progressValue,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${(_progressValue * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
