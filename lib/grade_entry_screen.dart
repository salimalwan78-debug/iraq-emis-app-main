import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class GradeEntryScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  const GradeEntryScreen({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  State<GradeEntryScreen> createState() => _GradeEntryScreenState();
}

class _GradeEntryScreenState extends State<GradeEntryScreen> {
  List<Map<String, dynamic>> stages = [];
  List<Map<String, dynamic>> subjects = [];
  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> exams = [];
  List<Map<String, dynamic>> students = [];

  String? stageId, subjectId, roomId, examId;
  final Map<int, TextEditingController> grades = {};
  bool loading = true;
  bool loadingStudents = false;
  bool saving = false;
  bool togglingIgnore = false;
  bool? examIgnored;
  String? error;

  Map<String, String> get h => {
        'Authorization': widget.token.toLowerCase().startsWith('bearer ')
            ? widget.token
            : 'Bearer ${widget.token}',
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
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item)
    ];
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

  Future<List<Map<String, dynamic>>> _getList(String endpoint) async =>
      _maps(await _getJson(endpoint));

  String _id(Map<String, dynamic> x) =>
      '${x['id'] ?? x['examId'] ?? x['value'] ?? x['stageId'] ?? ''}';

  String _label(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? x['value'] ?? x['id'] ?? ''}';

  bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    return '$v'.toLowerCase() == 'true' || '$v' == '1';
  }

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
    _clearStudents();
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
    _clearStudents();
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
        '/selectoption/getClassRooms?stageId=$stageId&schoolId=${widget.schoolId}&subjectId=$value',
      );
      final raw = await _getJson(
        '/examscore/getexamsformarks?schoolId=${widget.schoolId}&stageId=$stageId&subjectId=$value',
      );
      final rawExams = raw is Map ? raw['exams'] : raw;
      final examResult = _maps(rawExams);
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
    _clearStudents();
    setState(() {
      roomId = value;
      students = [];
      error = null;
    });
    if (examId != null) {
      await _loadStudents();
    }
  }

  Future<void> _examChanged(String? value) async {
    _clearStudents();
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
    return _readIgnoredFlagFromMap(exam);
  }

  bool? _readIgnoredFlagFromMap(Map<dynamic, dynamic> value) {
    for (final key in const [
      'isIgnored',
      'ignored',
      'isIgnore',
      'isExamIgnored',
      'isIgnoredExam',
      'ignore',
    ]) {
      if (value.containsKey(key) && value[key] != null) {
        return _bool(value[key]);
      }
    }
    final exam = value['exam'];
    if (exam is Map) return _readIgnoredFlagFromMap(exam);
    final examInfo = value['examInfo'];
    if (examInfo is Map) return _readIgnoredFlagFromMap(examInfo);
    return null;
  }

  Set<String> _examIdCandidates(String selectedExamId) {
    final candidates = <String>{selectedExamId.trim()};
    final selected = _currentExam;
    if (selected != null) {
      for (final key in const ['id', 'examId', 'exam_id', 'value']) {
        final value = selected[key];
        if (value != null && '$value'.trim().isNotEmpty) {
          candidates.add('$value'.trim());
        }
      }
    }
    return candidates;
  }

  Map<dynamic, dynamic>? _findStudentGradeForExam(
    Map<String, dynamic> student,
    Set<String> selectedExamIds,
  ) {
    final rawGrades =
        student['grades'] ?? student['examScores'] ?? student['scores'] ?? student['marks'];

    if (rawGrades is List) {
      for (final item in rawGrades) {
        if (item is! Map) continue;
        final gradeMap = Map<dynamic, dynamic>.from(item);
        final rawExamId =
            gradeMap['examId'] ?? gradeMap['exam_id'] ?? gradeMap['id'];
        if (rawExamId != null && selectedExamIds.contains('$rawExamId'.trim())) {
          return gradeMap;
        }
      }
    } else if (rawGrades is Map) {
      for (final id in selectedExamIds) {
        if (rawGrades.containsKey(id)) {
          final val = rawGrades[id];
          if (val is Map) return Map<dynamic, dynamic>.from(val);
          return {'grade': val};
        }
      }
    }
    return null;
  }

  /// في نظام EMIS:
  /// - يُعتبر الامتحان مُهمَلاً (true) إذا كانت الدرجات المسجلة لهذا الامتحان تساوي -3.
  /// - أما إذا لم تكن هناك درجات مسجلة بعد (null أو فارغة) أو وُجدت أي درجة غير -3،
  ///   فإن الامتحان فعال وغير مُهمَل (false).
  bool _detectIgnoredStateFromStudents(
    List<Map<String, dynamic>> rows,
    String selectedExamId,
  ) {
    final explicitFlag = _readExamIgnored();
    if (explicitFlag != null) return explicitFlag;
    if (rows.isEmpty) return false;

    final selectedExamIds = _examIdCandidates(selectedExamId);
    int matchedGradesCount = 0;
    int ignoredGradesCount = 0;

    for (final student in rows) {
      final selectedGrade = _findStudentGradeForExam(student, selectedExamIds);
      if (selectedGrade == null) continue;

      final rawGrade = selectedGrade['grade'] ??
          selectedGrade['score'] ??
          selectedGrade['mark'] ??
          selectedGrade['value'];

      if (rawGrade == null || '$rawGrade'.trim().isEmpty) continue;

      final numericGrade =
          rawGrade is num ? rawGrade : num.tryParse('$rawGrade'.trim());
      if (numericGrade == null) continue;

      matchedGradesCount++;
      if (numericGrade == -3) {
        ignoredGradesCount++;
      } else {
        // وجود أي درجة فعلية غير -3 يعني أن الامتحان غير مُهمَل قطعاً
        return false;
      }
    }

    // إذا وُجدت سجلات درجات لهذا الامتحان وكانت جميعها -3، فهو مُهمَل
    if (matchedGradesCount > 0 && ignoredGradesCount == matchedGradesCount) {
      return true;
    }

    // إذا لم تُدخل أي درجة بعد (جميعها null أو غير موجودة)، فالامتحان فعال وجاهز للإدخال
    return false;
  }

  Map<String, dynamic>? get _currentExam {
    for (final exam in exams) {
      if (_id(exam) == examId) return exam;
    }
    return null;
  }

  void _clearStudents() {
    for (final c in grades.values) {
      c.dispose();
    }
    grades.clear();
  }

  Future<void> _loadStudents() async {
    if (stageId == null || subjectId == null || examId == null) return;
    setState(() {
      loadingStudents = true;
      error = null;
    });
    try {
      var endpoint =
          '/examscore/getstudentswithgrades?schoolId=${widget.schoolId}&stageId=$stageId&subjectId=$subjectId';
      if (roomId != null && roomId!.isNotEmpty) {
        endpoint += '&classroomId=$roomId';
      }
      final result = await _getList(endpoint);
      _clearStudents();

      final detectedIgnored = examId == null
          ? false
          : _detectIgnoredStateFromStudents(result, examId!);

      for (final student in result) {
        final id = int.tryParse('${student['id']}');
        if (id != null) grades[id] = TextEditingController();
      }

      if (mounted) {
        setState(() {
          students = result;
          examIgnored = detectedIgnored;
          loadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadingStudents = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> _toggleIgnoreCurrentExam(bool ignore) async {
    final exam = _currentExam;
    if (exam == null || students.isEmpty || togglingIgnore) return;

    if (ignore && exam['isIgnorable'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا الفصل غير قابل للإهمال حسب إعدادات EMIS.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final examNumber = int.tryParse(_id(exam));
    if (examNumber == null) return;

    final ids = students
        .map((s) => int.tryParse('${s['id']}'))
        .whereType<int>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    setState(() => togglingIgnore = true);
    try {
      final endpoint = ignore
          ? '/examscore/ignoreexamgrade'
          : '/examScore/unignoreexamgrade';
      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
        headers: h,
        body: jsonEncode({
          'examId': examNumber,
          'studentIds': ids,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ignore
                ? 'تم إهمال الفصل الدراسي بنجاح.'
                : 'تم إلغاء إهمال الفصل وتفعيله لإدخال الدرجات.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadStudents();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث حالة الفصل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => togglingIgnore = false);
    }
  }

  String _normalizeNumber(String value) => value
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll(' ', '')
      .replaceAll('،', '.')
      .replaceAll(',', '.')
      .replaceAll('٫', '.');

  Future<http.Response> _postGrade(
    int studentId,
    int examNumber,
    int grade,
  ) async {
    return http.post(
      Uri.parse('https://emis.moedu.gov.iq/api/examscore/updateexamgrade'),
      headers: h,
      body: jsonEncode({
        'studentId': studentId,
        'examId': examNumber,
        'grade': grade,
      }),
    );
  }

  Future<void> _saveGrades() async {
    final exam = _currentExam;
    if (exam == null) return;
    if (examIgnored == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا الفصل غير مفعل لأنه مُهمَل ولا يمكن إدخال درجات فيه. اضغط على "إلغاء الإهمال" أولاً.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final examNumber = int.tryParse(_id(exam));
    if (examNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('معرف الامتحان غير صالح في بيانات EMIS'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => saving = true);
    int ok = 0, failed = 0;
    final failures = <String>[];
    try {
      for (final student in students) {
        final studentId = int.tryParse('${student['id']}');
        if (studentId == null) continue;
        final raw = grades[studentId]?.text.trim() ?? '';
        if (raw.isEmpty) continue;
        final parsed = int.tryParse(_normalizeNumber(raw));
        final max =
            int.tryParse('${exam['maxAllowedGrade'] ?? exam['max'] ?? 100}') ??
                100;
        if (parsed == null || parsed < 0 || parsed > max) {
          failed++;
          failures.add(
            'الطالب $studentId: الدرجة "$raw" غير صالحة؛ المجال 0-$max',
          );
          continue;
        }
        try {
          var response = await _postGrade(studentId, examNumber, parsed);
          var body = utf8.decode(response.bodyBytes).trim();

          if (response.statusCode == 400 &&
              body.toLowerCase().contains('exam not found')) {
            final alternatives = <int>{};
            for (final k in const ['examId', 'id', 'value']) {
              final n = int.tryParse('${exam[k] ?? ''}');
              if (n != null) alternatives.add(n);
            }
            for (final alt in alternatives) {
              if (alt == examNumber) continue;
              response = await _postGrade(studentId, alt, parsed);
              body = utf8.decode(response.bodyBytes).trim();
              if (response.statusCode >= 200 && response.statusCode < 300) {
                break;
              }
            }
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            ok++;
          } else {
            failed++;
            failures.add(
              'الطالب $studentId: HTTP ${response.statusCode}${body.isEmpty ? '' : ' — $body'}',
            );
          }
        } catch (e) {
          failed++;
          failures.add('الطالب $studentId: $e');
        }
      }
      if (!mounted) return;
      for (final controller in grades.values) {
        controller.clear();
      }
      setState(() => saving = false);
      final details =
          failures.isEmpty ? '' : '\n${failures.take(2).join('\n')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حفظ $ok درجة${failed == 0 ? '' : ' — فشل $failed'}$details',
          ),
          backgroundColor: failed == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exam = _currentExam;
    final max =
        int.tryParse('${exam?['maxAllowedGrade'] ?? exam?['max'] ?? 100}') ??
            100;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'إدخال الدرجات',
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
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _drop('الصف الدراسي', stageId, stages, _stageChanged),
                          const SizedBox(height: 12),
                          _drop('المادة', subjectId, subjects, _subjectChanged),
                          const SizedBox(height: 12),
                          _drop('الشعبة', roomId, rooms, _roomChanged),
                          const SizedBox(height: 12),
                          _drop(
                            'فصل الدرجات / الامتحان',
                            examId,
                            exams,
                            _examChanged,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    _messageCard(error!, Colors.red),
                  ],
                  if (exam != null) ...[
                    const SizedBox(height: 16),
                    _examCard(exam, max),
                  ],
                  if (loadingStudents) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (students.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...students.map((student) => _studentCard(student, max)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed:
                            (saving || examIgnored == true) ? null : _saveGrades,
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _headerCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white24,
              child: Icon(
                Icons.edit_note_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إدخال الدرجات',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'قراءة مباشرة من EMIS وحفظ الدرجات',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _drop(
    String label,
    String? value,
    List<Map<String, dynamic>> data,
    ValueChanged<String?> onChanged,
  ) =>
      DropdownButtonFormField<String>(
        value: data.any((x) => _id(x) == value) ? value : null,
        isExpanded: true,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        items: data
            .map(
              (x) => DropdownMenuItem<String>(
                value: _id(x),
                child: Text(
                  _label(x),
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
            .where((x) => x.value != null && x.value!.isNotEmpty)
            .toList(),
        onChanged: data.isEmpty ? null : onChanged,
      );

  Widget _examCard(Map<String, dynamic> exam, int max) {
    final ignored = examIgnored == true;
    final statusText = loadingStudents
        ? 'جارٍ التحقق من حالة الإهمال...'
        : (ignored ? 'غير مفعل — مُهمَل' : 'فعال — غير مُهمَل');
    final statusColor = loadingStudents
        ? Colors.orange
        : (ignored ? Colors.red : Colors.green);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withOpacity(.1),
                  child: Icon(
                    ignored ? Icons.visibility_off : Icons.assignment,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(exam),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الدرجة القصوى: $max  •  الطلاب: ${students.length}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  backgroundColor: statusColor.withOpacity(.10),
                  label: Text(
                    statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!loadingStudents && students.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: togglingIgnore
                      ? null
                      : () => _toggleIgnoreCurrentExam(!ignored),
                  icon: togglingIgnore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          ignored
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 18,
                        ),
                  label: Text(
                    ignored
                        ? 'إلغاء إهمال الفصل لتفعيل الرصد'
                        : 'إهمال هذا الفصل',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> student, int max) {
    final id = int.tryParse('${student['id']}') ?? -1;
    final ignored = examIgnored == true;
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
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'رقم الطالب: ${student['id'] ?? ''}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 86,
              child: TextField(
                enabled: !ignored && !loadingStudents,
                controller: grades[id],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '',
                  filled: true,
                  fillColor: Color(0xFFF7F8FB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(String text, Color color) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      );
}
