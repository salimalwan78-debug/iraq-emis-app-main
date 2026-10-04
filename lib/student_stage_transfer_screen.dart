import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';

class StudentStageTransferScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;

  const StudentStageTransferScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allStudents,
  });

  @override
  State<StudentStageTransferScreen> createState() =>
      _StudentStageTransferScreenState();
}

class _StudentStageTransferScreenState
    extends State<StudentStageTransferScreen> {
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> stages = [];

  String? fromStage, toStage;
  final Set<int> selected = {};
  bool loading = true, loadingStudents = false, saving = false;
  String? error;

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  dynamic _unwrap(dynamic d) =>
      d is Map && d['data'] != null ? d['data'] : d;

  List<Map<String, dynamic>> _maps(dynamic value) {
    final raw = _unwrap(value);
    if (raw is! List) return [];
    return [
      for (final x in raw)
        if (x is Map) Map<String, dynamic>.from(x),
    ];
  }

  Future<dynamic> _get(String endpoint) async {
    final r = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
      headers: h,
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(
        'HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}',
      );
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<List<Map<String, dynamic>>> _list(String endpoint) async =>
      _maps(await _get(endpoint));

  String _id(Map<String, dynamic> x) =>
      '${x['id'] ?? x['value'] ?? x['stageId'] ?? ''}';

  String _label(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['name'] ?? x['label'] ?? x['text'] ?? x['value'] ?? ''}';

  String _studentName(Map<String, dynamic> s) {
    final direct = s['fullName'] ?? s['studentName'];
    if ('$direct'.trim().isNotEmpty) return '$direct';
    return [
      s['name'],
      s['fatherName'],
      s['grandFatherName'],
      s['surName'],
    ].where((x) => x != null && '$x'.trim().isNotEmpty).join(' ');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _list(
        '/selectoption/getAvailableStagesForStudent?schoolId=${widget.schoolId}',
      );
      if (!mounted) return;
      setState(() {
        stages = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> _fromChanged(String? value) async {
    if (value == null) return;
    setState(() {
      fromStage = value;
      selected.clear();
      loadingStudents = true;
      error = null;
    });

    try {
      Map<String, dynamic>? stage;
      for (final item in stages) {
        if (_id(item) == value) {
          stage = item;
          break;
        }
      }
      final stageName = stage == null ? '' : _label(stage);

      final result = await _list(
        '/student/getstudents?page=1&rowsPerPage=3000&sortBy=id'
        '&sortOrder=desc&entityId=${widget.schoolId}',
      );

      final filtered = result.where((student) {
        final sid =
            '${student['stageId'] ?? student['studentStageId'] ?? ''}';
        final name =
            '${student['studentStage'] ?? student['stageName'] ?? student['stage'] ?? ''}';
        return sid == value ||
            (stageName.isNotEmpty && name.trim() == stageName.trim());
      }).toList();

      if (!mounted) return;
      setState(() {
        students = filtered;
        loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingStudents = false;
        error = '$e';
      });
    }
  }

  Future<Map<String, dynamic>> _fullStudent(dynamic id) async {
    final raw = await _get('/student/getstudent/$id');
    final data = _unwrap(raw);
    if (data is! Map) {
      throw Exception('بيانات الطالب $id غير صالحة');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> _run() async {
    if (fromStage == null ||
        toStage == null ||
        fromStage == toStage ||
        selected.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ترحيل الطلاب', textDirection: TextDirection.rtl),
        content: Text(
          'سيتم ترحيل ${selected.length} طالب إلى الصف المحدد. متابعة؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      saving = true;
      error = null;
    });

    int ok = 0, failed = 0;
    String? lastError;

    try {
      for (final id in selected.toList()) {
        try {
          final dto = await _fullStudent(id);

          // نحافظ على كامل سجل EMIS ثم نغيّر حقلي المرحلة والشعبة فقط.
          dto['stageId'] = int.tryParse(toStage!);
          dto['classRoomId'] = null;

          final response = await http.post(
            Uri.parse('https://emis.moedu.gov.iq/api/student/updatestudent'),
            headers: h,
            body: jsonEncode(dto),
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            ok++;
          } else {
            failed++;
            lastError =
                'الطالب $id: HTTP ${response.statusCode}: '
                '${utf8.decode(response.bodyBytes)}';
          }
        } catch (e) {
          failed++;
          lastError = '$e';
        }
      }

      if (!mounted) return;
      selected.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم ترحيل $ok من ${ok + failed} طالب'
            '${lastError == null ? '' : '\nآخر خطأ: $lastError'}',
          ),
          backgroundColor: failed == 0 ? Colors.green : Colors.orange,
        ),
      );
      await _fromChanged(fromStage);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

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
              'ترحيل الطلاب بين الصفوف',
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
                    padding: const EdgeInsets.all(18),
                    children: [
                      _hero(),
                      const SizedBox(height: 16),
                      _drop('الصف الحالي', fromStage, stages, _fromChanged, dark),
                      const SizedBox(height: 12),
                      _drop(
                        'الصف الدراسي المستهدف',
                        toStage,
                        stages.where((x) => _id(x) != fromStage).toList(),
                        (v) => setState(() => toStage = v),
                        dark,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                      if (loadingStudents) ...[
                        const SizedBox(height: 22),
                        const Center(child: CircularProgressIndicator()),
                      ] else if (fromStage != null) ...[
                        const SizedBox(height: 14),
                        _header(dark),
                        const SizedBox(height: 8),
                        ...students.map((s) => _studentTile(s, dark)),
                        if (students.isEmpty)
                          _empty(dark),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: saving ||
                                    selected.isEmpty ||
                                    toStage == null ||
                                    toStage == fromStage
                                ? null
                                : _run,
                            icon: saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.move_up_rounded),
                            label: Text('تنفيذ الترحيل (${selected.length})'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _hero() => Container(
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
              child: Icon(Icons.move_up_rounded, color: Colors.white, size: 30),
            ),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ترحيل الطلاب',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('قراءة مباشرة من EMIS ثم تحديث المرحلة للطلاب المحددين.',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
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
    bool dark,
  ) =>
      DropdownButtonFormField<String>(
        value: data.any((x) => _id(x) == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
          ),
        ),
        items: data
            .map((x) => DropdownMenuItem(
                  value: _id(x),
                  child: Text(_label(x), overflow: TextOverflow.ellipsis),
                ))
            .where((x) => x.value != null && x.value!.isNotEmpty)
            .toList(),
        onChanged: data.isEmpty ? null : onChanged,
      );

  Widget _header(bool dark) => Card(
        elevation: 0,
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE8EAF6),
            child: Icon(Icons.people_alt_rounded, color: Color(0xFF3949AB)),
          ),
          title: Text('طلاب الصف الحالي: ${students.length}'),
          subtitle: const Text('يمكن اختيار مجموعة من الطلاب أو اختيارهم جميعاً.'),
          trailing: TextButton(
            onPressed: students.isEmpty
                ? null
                : () => setState(() {
                      if (selected.length == students.length) {
                        selected.clear();
                      } else {
                        selected
                          ..clear()
                          ..addAll(students
                              .map((s) => int.tryParse('${s['id']}') ?? -1)
                              .where((id) => id > 0));
                      }
                    }),
            child: Text(
              selected.length == students.length ? 'إلغاء الكل' : 'اختيار الكل',
            ),
          ),
        ),
      );

  Widget _studentTile(Map<String, dynamic> s, bool dark) {
    final id = int.tryParse('${s['id']}') ?? -1;
    final checked = selected.contains(id);
    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: CheckboxListTile(
        value: checked,
        onChanged: id < 0
            ? null
            : (_) => setState(
                  () => checked ? selected.remove(id) : selected.add(id),
                ),
        title: Text(_studentName(s)),
        subtitle: Text('رقم الطالب: ${s['id'] ?? ''}'),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _empty(bool dark) => Card(
        elevation: 0,
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Text('لا يوجد طلاب في الصف المحدد.'),
        ),
      );
}
