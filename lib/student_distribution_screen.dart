import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';

class StudentDistributionScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;

  const StudentDistributionScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allStudents,
  });

  @override
  State<StudentDistributionScreen> createState() =>
      _StudentDistributionScreenState();
}

class _StudentDistributionScreenState
    extends State<StudentDistributionScreen> {
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> stages = [];
  List<Map<String, dynamic>> rooms = [];

  String? stageId;
  String? targetRoomId;
  String? _activeRoomId;

  final Set<int> selected = {};
  final Map<String, Set<int>> assignments = {};

  bool loading = true;
  bool saving = false;
  bool loadingStudents = false;
  String? error;

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  dynamic _unwrap(dynamic value) {
    if (value is Map && value['data'] != null) return value['data'];
    return value;
  }

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

  String _name(Map<String, dynamic> s) {
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

  Future<void> _stageChanged(String? value) async {
    if (value == null) return;

    setState(() {
      stageId = value;
      targetRoomId = null;
      _activeRoomId = null;
      rooms = [];
      students = [];
      selected.clear();
      assignments.clear();
      loadingStudents = true;
      error = null;
    });

    try {
      final stageRooms = await _list(
        '/selectoption/getClassRooms?schoolId=${widget.schoolId}&stageId=$value',
      );

      Map<String, dynamic>? stage;
      for (final item in stages) {
        if (_id(item) == value) {
          stage = item;
          break;
        }
      }
      final stageName = stage == null ? '' : _label(stage);

      final rawStudents = await _list(
        '/student/getstudents?page=1&rowsPerPage=3000&sortBy=id'
        '&sortOrder=desc&entityId=${widget.schoolId}',
      );

      final filtered = rawStudents.where((s) {
        final sid = '${s['stageId'] ?? s['studentStageId'] ?? ''}';
        final sname =
            '${s['studentStage'] ?? s['stageName'] ?? s['stage'] ?? ''}';
        return sid == value ||
            (stageName.isNotEmpty && sname.trim() == stageName.trim());
      }).map((student) {
        final id = _studentId(student);
        if (student['classRoomName'] != null || student['classRoom'] != null || student['classRoomId'] != null) {
          return student;
        }
        for (final cached in widget.allStudents) {
          if (cached is Map && int.tryParse('${cached['id']}') == id) {
            final merged = Map<String, dynamic>.from(student);
            for (final key in ['classRoomName', 'classRoom', 'classroom', 'classRoomId', 'classroomId']) {
              if (cached[key] != null) merged[key] = cached[key];
            }
            return merged;
          }
        }
        return student;
      }).toList();

      if (!mounted) return;
      setState(() {
        rooms = stageRooms;
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

  List<Map<String, dynamic>> get availableStudents {
    final assigned = assignments.values.expand((x) => x).toSet();
    return students
        .where((s) => !assigned.contains(_studentId(s)))
        .toList();
  }

  int _studentId(Map<String, dynamic> s) =>
      int.tryParse('${s['id']}') ?? -1;

  void _commitActiveSelection() {
    if (_activeRoomId == null) return;
    if (selected.isEmpty) return;
    assignments.putIfAbsent(_activeRoomId!, () => <int>{}).addAll(selected);
  }

  void _roomChanged(String? value) {
    if (value == null) return;

    setState(() {
      _commitActiveSelection();
      targetRoomId = value;
      _activeRoomId = value;
      selected.clear();
    });
  }

  String _roomName(String? id) {
    for (final room in rooms) {
      if (_id(room) == id) return _label(room);
    }
    return '';
  }

  Future<Map<String, dynamic>> _fullStudent(dynamic id) async {
    final raw = await _get('/student/getstudent/$id');
    final data = _unwrap(raw);
    if (data is! Map) {
      throw Exception('بيانات الطالب $id غير صالحة');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> _execute() async {
    _commitActiveSelection();

    final jobs = <MapEntry<String, Set<int>>>[
      for (final e in assignments.entries)
        if (e.value.isNotEmpty) MapEntry(e.key, {...e.value}),
    ];

    if (jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر طلاباً ثم شعبة مستهدفة أولاً')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنفيذ توزيع الطلاب', textDirection: TextDirection.rtl),
        content: Text(
          'سيتم توزيع ${jobs.fold<int>(0, (n, e) => n + e.value.length)} طالب '
          'على ${jobs.length} شعبة. متابعة؟',
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
      for (final job in jobs) {
        final roomId = job.key;
        for (final id in job.value) {
          try {
            final dto = await _fullStudent(id);
            dto['stageId'] = int.tryParse(stageId!);
            dto['classRoomId'] = int.tryParse(roomId);

            final response = await http.post(
              Uri.parse(
                'https://emis.moedu.gov.iq/api/student/updatestudent',
              ),
              headers: h,
              body: jsonEncode(dto),
            );

            if (response.statusCode >= 200 &&
                response.statusCode < 300) {
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
      }

      if (!mounted) return;
      assignments.clear();
      selected.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم توزيع $ok طالب'
            '${failed == 0 ? '' : ' — فشل $failed'}'
            '${lastError == null ? '' : '\nآخر خطأ: $lastError'}',
          ),
          backgroundColor: failed == 0 ? Colors.green : Colors.orange,
        ),
      );
      setState(() {});
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = availableStudents;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, mode, _) {
        final dark = mode == ThemeMode.dark;
        return Scaffold(
          backgroundColor:
              dark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: const Text(
              'توزيع الطلاب على الشُعَب',
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
                      _hero(dark),
                      const SizedBox(height: 16),
                      _drop(
                        'الصف الدراسي',
                        stageId,
                        stages,
                        (v) => _stageChanged(v),
                        dark,
                      ),
                      const SizedBox(height: 12),
                      _drop(
                        'الشعبة المستهدفة',
                        targetRoomId,
                        rooms,
                        (v) => _roomChanged(v),
                        dark,
                      ),
                      if (loadingStudents) ...[
                        const SizedBox(height: 20),
                        const Center(child: CircularProgressIndicator()),
                      ] else if (stageId != null) ...[
                        const SizedBox(height: 14),
                        _selectionHeader(list.length, dark),
                        const SizedBox(height: 8),
                        ...list.map((s) => _studentTile(s, dark)),
                        if (list.isEmpty)
                          _emptyCard(
                            'تم توزيع جميع الطلاب الذين تم اختيارهم في الشعب السابقة.',
                            dark,
                          ),
                      ],
                    ],
                  ),
                ),
          bottomNavigationBar: _pendingCount == 0
              ? null
              : SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                      boxShadow: const [
                        BoxShadow(blurRadius: 12, offset: Offset(0, -3), color: Colors.black12),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الطلاب المحددون للتوزيع: $_pendingCount',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: saving ? null : _execute,
                          icon: saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.done_all_rounded),
                          label: const Text('تنفيذ التوزيع'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  int get _pendingCount => assignments.values.expand((x) => x).length + selected.length;

  Widget _hero(bool dark) => Container(
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
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white24,
              child: Icon(Icons.groups_2_rounded, color: Colors.white, size: 30),
            ),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('توزيع الطلاب',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text(
                    'اختر مجموعة من الطلاب لكل شعبة ثم نفّذ العملية مرة واحدة.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
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
    bool dark,
  ) {
    return DropdownButtonFormField<String>(
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
  }

  Widget _selectionHeader(int count, bool dark) {
    final room = _roomName(targetRoomId);
    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE8EAF6),
          child: Icon(Icons.checklist_rounded, color: Color(0xFF3949AB)),
        ),
        title: Text('الطلاب المتاحون: $count'),
        subtitle: Text(
          room.isEmpty
              ? 'اختر الشعبة المستهدفة'
              : 'الشعبة الحالية: $room — المحددون: ${selected.length}',
        ),
        trailing: TextButton(
          onPressed: listIsEmpty(count)
              ? null
              : () => setState(() {
                    if (selected.length == count) {
                      selected.clear();
                    } else {
                      selected
                        ..clear()
                        ..addAll(availableStudents.map(_studentId).where((x) => x > 0));
                    }
                  }),
          child: Text(selected.length == count ? 'إلغاء الكل' : 'اختيار الكل'),
        ),
      ),
    );
  }

  bool listIsEmpty(int count) => count == 0 || targetRoomId == null;

  String _currentRoomName(Map<String, dynamic> s) {
    final direct = s['classRoomName'] ?? s['classRoom'] ?? s['classroom'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct';
    final roomId = '${s['classRoomId'] ?? s['classroomId'] ?? ''}';
    if (roomId.isNotEmpty) {
      final name = _roomName(roomId);
      if (name.isNotEmpty) return name;
    }
    return 'غير محددة';
  }

  Widget _studentTile(Map<String, dynamic> student, bool dark) {
    final id = _studentId(student);
    final checked = selected.contains(id);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: CheckboxListTile(
        value: checked,
        onChanged: targetRoomId == null || id < 0
            ? null
            : (_) => setState(
                  () => checked ? selected.remove(id) : selected.add(id),
                ),
        title: Text(_name(student)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('رقم الطالب: ${student['id'] ?? ''}'),
            const SizedBox(height: 3),
            Text(
              'الشعبة الحالية: ${_currentRoomName(student)}',
              style: TextStyle(
                color: _currentRoomName(student) == 'غير محددة' ? Colors.orange : Colors.blueGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _emptyCard(String text, bool dark) => Card(
        elevation: 0,
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
