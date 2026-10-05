import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dashboard_screen.dart';
import 'app_core.dart';
import 'emis_webview_screen.dart';

class LoadingDataScreen extends StatefulWidget {
  final String token;
  final String? refreshToken;
  final String schoolId;

  const LoadingDataScreen({
    super.key,
    required this.token,
    this.refreshToken,
    required this.schoolId,
  });

  @override
  State<LoadingDataScreen> createState() => _LoadingDataScreenState();
}

class _SessionExpired implements Exception {}

class _LoadingDataScreenState extends State<LoadingDataScreen>
    with SingleTickerProviderStateMixin {
  String _statusText = 'جاري الاتصال بخوادم EMIS...';
  double _progressValue = .08;
  late String _activeToken;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _activeToken = widget.token;
    AppCore.playRelaxMusic();
    _startFetchingData();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Authorization': _activeToken.toLowerCase().startsWith('bearer ')
            ? _activeToken
            : 'Bearer $_activeToken',
        'Accept': 'application/json, text/plain, */*',
      };

  Future<bool> _refreshAccessToken() async {
    final refresh = widget.refreshToken?.trim();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final current = _activeToken.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
      final response = await http
          .post(
            Uri.parse('https://emis.moedu.gov.iq/api/account/refresh'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'accessToken': current,
              'refreshToken': refresh,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final decoded = _decode(response);
      final next = decoded is Map ? decoded['accessToken']?.toString() : null;
      if (next == null || next.trim().isEmpty) return false;
      _activeToken = next.trim();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _get(Uri uri) async {
    http.Response? last;
    bool refreshed = false;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 15));
        last = response;
        if (response.statusCode == 401) {
          if (!refreshed && await _refreshAccessToken()) {
            refreshed = true;
            continue;
          }
          throw _SessionExpired();
        }
        if (response.statusCode == 200) return response;
      } on _SessionExpired {
        rethrow;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw Exception('EMIS HTTP ${last?.statusCode ?? 0}');
  }

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (text.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(text);
  }

  List<dynamic> _extractList(dynamic decoded, String label) {
    if (decoded is Map && decoded['data'] is List) return decoded['data'] as List;
    if (decoded is List) return decoded;
    throw Exception('استجابة $label من EMIS غير متوقعة');
  }

  Future<void> _startFetchingData() async {
    try {
      setState(() {
        _statusText = 'جاري جلب بيانات المستخدم...';
        _progressValue = .20;
      });
      String realUserName = 'مستخدم النظام';
      final userRes = await _get(
        Uri.parse('https://emis.moedu.gov.iq/api/account/getloggedinuser'),
      );
      final userData = _decode(userRes);
      if (userData is Map) {
        realUserName =
            '${userData['employeeName'] ?? userData['fullName'] ?? realUserName}';
      }

      setState(() {
        _statusText = 'جاري جلب بيانات المدرسة...';
        _progressValue = .38;
      });
      final schoolRes = await _get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/school/getschoolinformation/${widget.schoolId}',
        ),
      );
      final schoolData = _decode(schoolRes);
      if (schoolData is! Map ||
          (schoolData['schoolName'] ?? schoolData['name'] ?? '')
              .toString()
              .trim()
              .isEmpty) {
        throw Exception('تعذر قراءة بيانات المدرسة من EMIS');
      }

      setState(() {
        _statusText = 'جاري تحميل سجلات الطلاب...';
        _progressValue = .63;
      });
      final studentsRes = await _get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/student/getstudents?page=1&rowsPerPage=3000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}',
        ),
      );
      final studentsData = _extractList(_decode(studentsRes), 'الطلاب');

      setState(() {
        _statusText = 'جاري تحميل سجلات المعلمين...';
        _progressValue = .82;
      });
      final teachersRes = await _get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/employee/getemployeesbyentities?page=1&rowsPerPage=1000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}&isTeacher=true',
        ),
      );
      final teachersData = _extractList(_decode(teachersRes), 'المعلمين');

      setState(() {
        _statusText = 'اكتملت المزامنة — تجهيز التطبيق...';
        _progressValue = 1;
      });
      await Future<void>.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            token: _headers['Authorization']!,
            schoolId: widget.schoolId,
            schoolName:
                '${schoolData['schoolName'] ?? schoolData['name'] ?? 'المدرسة'}',
            userName: realUserName,
            allStudents: studentsData,
            allTeachers: teachersData,
          ),
        ),
      );
    } on _SessionExpired {
      if (!mounted) return;
      setState(() {
        _statusText = 'انتهت جلسة EMIS. إعادة فتح جلسة الدخول...';
        _progressValue = .12;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmisWebviewScreen()),
      );
    } catch (e) {
      debugPrint('EMIS data loading error: $e');
      if (!mounted) return;
      setState(() {
        _statusText = 'تعذر تحميل بيانات المدرسة. أعد المحاولة.';
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعذر تحميل البيانات'),
          content: Text('$e', textDirection: TextDirection.rtl),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _startFetchingData();
              },
              child: const Text('إعادة المحاولة'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const EmisWebviewScreen()),
                );
              },
              child: const Text('تسجيل الدخول من جديد'),
            ),
          ],
        ),
      );
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
                      child: SizedBox(
                        width: 250,
                        height: 310,
                        child: Image.asset(
                          'assets/avatar.png',
                          fit: BoxFit.contain,
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
                            minHeight: 9,
                            backgroundColor: Colors.white24,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${(_progressValue * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold),
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
