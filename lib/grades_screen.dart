import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GradesScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  const GradesScreen({super.key, required this.token, required this.schoolId});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<Map<String, dynamic>> stages = [];
  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> exams = [];
  List<Map<String, dynamic>> students = [];

  String? stageId, subjectId, roomId, examId;
  final Map<int, TextEditingController> grades = {};
  bool loading = true, saving = false;
  bool? examIgnored;
  String? error;

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  dynamic _unwrap(dynamic d) {
    if (d is Map && d.containsKey('data') && d['data'] != null) {
      return d['data'];
    }
    return d;
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    final raw = _unwrap(value);
    if (raw is! List) return <Map<String, dynamic>>[];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) result.add(Map<String, dynamic>.from(item));
    }
    return result;
  }

  Future<dynamic> _getJson(String endpoint) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
      headers: h,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async {
    return _maps(await _getJson(endpoint));
  }

  String _id(Map<String, dynamic> x) =>
      '${x['id'] ?? x['value'] ?? x['stageId'] ?? ''}';

  String _label(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? x['value'] ?? x['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _loadStages();
  }

  @override
  void dispose() {
    for (final c in grades.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStages() async {
    try {
      final result =
          await _getList('/selectoption/getschoolstages/${widget.schoolId}');
      if (!mounted) return;
      setState(() {
        stages = result;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> _stageChanged(String? value) async {
    if (value == null) return;
    setState(() {
      stageId = value;
      subjectId = null;
      roomId = null;
      examId = null;
      subjects = [];
      rooms = [];
      exams = [];
      students = [];
      examIgnored = null;
      error = null;
    });
    try {
      final result = await _getList(
        '/subject/getsubjectsselect?stageId=$value&schoolId=${widget.schoolId}',
      );
      if (mounted) setState(() => subjects = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _subjectChanged(String? value) async {
    if (value == null || stageId == null) return;
    setState(() {
      subjectId = value;
      roomId = null;
      examId = null;
      rooms = [];
      exams = [];
      students = [];
      examIgnored = null;
      error = null;
    });
    try {
      final roomResult = await _getList(
        '/selectoption/getClassRooms?stageId=$stageId'
        '&schoolId=${widget.schoolId}&subjectId=$value',
      );

      final raw = await _getJson(
        '/examscore/getexamsformarks?schoolId=${widget.schoolId}'
        '&stageId=$stageId&subjectId=$value',
      );

      final examRaw = raw is Map ? raw['exams'] : null;
      final examResult = _maps(examRaw);

      if (!mounted) return;
      setState(() {
        rooms = roomResult;
        exams = examResult;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _roomChanged(String? value) async {
    setState(() {
      roomId = value;
      examId = null;
      students = [];
      examIgnored = null;
      error = null;
    });
  }

  Future<void> _examChanged(String? value) async {
    setState(() {
      examId = value;
      examIgnored = _readExamIgnored();
      students = [];
      error = null;
    });
    await _loadStudents();
  }

  bool? _readExamIgnored() {
    final exam = _currentExam;
    if (exam == null) return null;
    for (final key in const [
      'isIgnored',
      'ignored',
      'isIgnore',
      'isExamIgnored',
    ]) {
      final v = exam[key];
      if (v is bool) return v;
    }
    return null;
  }

  Map<String, dynamic>? get _currentExam {
    for (final exam in exams) {
      if (_id(exam) == examId) return exam;
    }
    return null;
  }

  Future<void> _loadStudents() async {
    if (stageId == null || subjectId == null || examId == null) return;
    try {
      var endpoint =
          '/examscore/getstudentswithgrades?schoolId=${widget.schoolId}'
          '&stageId=$stageId&subjectId=$subjectId';
      if (roomId != null && roomId!.isNotEmpty) {
        endpoint += '&classroomId=$roomId';
      }

      final result = await _getList(endpoint);
      for (final c in grades.values) {
        c.dispose();
      }
      grades.clear();

      for (final student in result) {
        final id = int.tryParse('${student['id']}');
        if (id == null) continue;

        dynamic gradeValue;
        final rawGrades = student['grades'];
        if (rawGrades is List) {
          for (final raw in rawGrades) {
            if (raw is Map &&
                '${raw['examId'] ?? raw['exam']?['id'] ?? raw['id']}' ==
                    examId) {
              gradeValue = raw['grade'] ?? raw['score'] ?? raw['value'];
              if (raw['isIgnored'] is bool) {
                examIgnored ??= raw['isIgnored'] as bool;
              }
              break;
            }
          }
        }
        grades[id] = TextEditingController(
          text: gradeValue == null ? '' : '$gradeValue',
        );
      }

      if (mounted) setState(() => students = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _saveGrades() async {
    final exam = _currentExam;
    if (exam == null) return;

    setState(() => saving = true);
    int ok = 0, failed = 0;

    try {
      for (final student in students) {
        final studentId = int.tryParse('${student['id']}');
        if (studentId == null) continue;

        final value = grades[studentId]?.text.trim() ?? '';
        if (value.isEmpty) continue;

        final grade = double.tryParse(value);
        if (grade == null) {
          failed++;
          continue;
        }

        try {
          final response = await http.post(
            Uri.parse(
              'https://emis.moedu.gov.iq/api/examscore/updateexamgrade',
            ),
            headers: h,
            body: jsonEncode({
              'studentId': studentId,
              'examId': int.tryParse(_id(exam)),
              'grade': grade,
            }),
          );
          if (response.statusCode >= 200 && response.statusCode < 300) {
            ok++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ $ok درجة${failed == 0 ? '' : ' — فشل $failed'}',
          ),
          backgroundColor: failed == 0 ? Colors.green : Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _changeIgnore(bool ignore) async {
    final exam = _currentExam;
    if (exam == null || students.isEmpty) return;

    final allowed = exam['isIgnorable'];
    if (allowed is bool && !allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا الفصل غير قابل للإهمال حسب EMIS'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final title = ignore ? 'إهمال الفصل الدراسي' : 'إلغاء إهمال الفصل الدراسي';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: Text(
          ignore
              ? 'سيتم إهمال هذا الفصل لجميع الطلاب الظاهرين في الشعبة المحددة. متابعة؟'
              : 'سيتم إلغاء إهمال هذا الفصل لجميع الطلاب الظاهرين. متابعة؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => saving = true);
    final ids = students
        .map((s) => int.tryParse('${s['id']}'))
        .whereType<int>()
        .toList();

    try {
      final endpoint = ignore
          ? '/examscore/ignoreexamgrade'
          : '/examScore/unignoreexamgrade';

      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
        headers: h,
        body: jsonEncode({
          'examId': int.tryParse(_id(exam)),
          'studentIds': ids,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
        );
      }

      if (!mounted) return;
      setState(() {
        saving = false;
        examIgnored = ignore;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ignore
                ? 'تم إهمال الفصل الدراسي بنجاح'
                : 'تم إلغاء إهمال الفصل الدراسي بنجاح',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadStudents();
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت العملية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exam = _currentExam;
    final max =
        double.tryParse('${exam?['maxAllowedGrade'] ?? exam?['max'] ?? 100}') ??
            100;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'الدرجات',
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
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  _headerCard(),
                  const SizedBox(height: 16),
                  _drop('الصف الدراسي', stageId, stages, _stageChanged),
                  const SizedBox(height: 12),
                  _drop('المادة', subjectId, subjects, _subjectChanged),
                  const SizedBox(height: 12),
                  _drop('الشعبة', roomId, rooms, _roomChanged),
                  const SizedBox(height: 12),
                  _drop('فصل الدرجات / الامتحان', examId, exams, _examChanged),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(error!, Colors.red),
                  ],
                  if (exam != null) ...[
                    const SizedBox(height: 16),
                    _examCard(exam, max),
                  ],
                  if (students.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...students.map((student) => _studentCard(student, max)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: saving ? null : _saveGrades,
                        icon: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text(
                          'حفظ الدرجات',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white24,
            child: Icon(Icons.bar_chart_rounded, color: Colors.white, size: 30),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إدارة الدرجات',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('قراءة مباشرة من EMIS وحفظ الدرجات والإهمال',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drop(
    String label,
    String? value,
    List<Map<String, dynamic>> data,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: data.any((x) => _id(x) == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: data
          .map(
            (x) => DropdownMenuItem<String>(
              value: _id(x),
              child: Text(
                _label(x),
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
              ),
            ),
          )
          .where((x) => x.value != null && x.value!.isNotEmpty)
          .toList(),
      onChanged: data.isEmpty ? null : onChanged,
    );
  }

  Widget _examCard(Map<String, dynamic> exam, double max) {
    final ignored = examIgnored ??
        (exam['isIgnored'] is bool ? exam['isIgnored'] as bool : false);
    final ignorable = exam['isIgnorable'] != false;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      (ignored ? Colors.red : Colors.orange).withOpacity(.10),
                  child: Icon(
                    ignored
                        ? Icons.visibility_off_rounded
                        : Icons.assignment_rounded,
                    color: ignored ? Colors.red : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${exam['label'] ?? _label(exam)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الدرجة القصوى: $max  •  الطلاب: ${students.length}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving || !ignorable || ignored
                        ? null
                        : () => _changeIgnore(true),
                    icon: const Icon(Icons.visibility_off_rounded),
                    label: const Text('إهمال'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving || !ignorable || !ignored
                        ? null
                        : () => _changeIgnore(false),
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('إلغاء الإهمال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> student, double max) {
    final id = int.tryParse('${student['id']}') ?? -1;
    final name =
        '${student['name'] ?? student['fullName'] ?? student['studentName'] ?? ''}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF1A237E).withOpacity(.08),
              child: const Icon(Icons.person, color: Color(0xFF3949AB)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('رقم الطالب: ${student['id'] ?? ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              width: 86,
              child: TextField(
                controller: grades[id],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0-$max',
                  filled: true,
                  fillColor: const Color(0xFFF7F8FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
