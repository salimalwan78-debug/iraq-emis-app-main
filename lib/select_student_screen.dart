import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';
import 'edit_student_screen.dart';
import 'add_student_screen.dart';

class SelectStudentScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> preLoadedStudents;
  const SelectStudentScreen({super.key, required this.token, required this.schoolId, required this.preLoadedStudents});
  @override State<SelectStudentScreen> createState() => _SelectStudentScreenState();
}

class _SelectStudentScreenState extends State<SelectStudentScreen> {
  late List<Map<String, dynamic>> _allStudents;
  String _query = '';
  String? _selectedStage;
  String? _selectedClassRoom;
  bool _loading = false;
  String? _error;

  Map<String, String> get _headers => {'Authorization': widget.token, 'Accept': 'application/json'};

  @override
  void initState() {
    super.initState();
    _allStudents = widget.preLoadedStudents.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    _loadStudents();
  }

  dynamic _unwrap(dynamic d) => d is Map && d['data'] != null ? d['data'] : d;

  Future<void> _loadStudents() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final r = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/student/getstudents?page=1&rowsPerPage=3000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}'),
        headers: _headers,
      );
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
      final data = _unwrap(jsonDecode(utf8.decode(r.bodyBytes)));
      if (data is List) {
        _allStudents = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  List<String> get _stages => _allStudents.map((s) => (s['studentStage'] ?? s['stageName'] ?? s['stage'] ?? '').toString()).where((s) => s.trim().isNotEmpty).toSet().toList();

  List<String> get _classRooms {
    if (_selectedStage == null) return [];
    return _allStudents.where((s) => (s['studentStage'] ?? s['stageName'] ?? s['stage'])?.toString() == _selectedStage)
        .map((s) => (s['classRoomName'] ?? s['classRoom'] ?? s['classroom'] ?? '').toString())
        .where((s) => s.isNotEmpty).toSet().toList();
  }

  String _studentName(Map<String, dynamic> s) {
    final direct = s['fullName'] ?? s['studentName'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct'.trim();
    return [s['name'], s['fatherName'], s['grandFatherName'], s['surName']].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join(' ').trim().isEmpty
        ? 'بدون اسم' : [s['name'], s['fatherName'], s['grandFatherName'], s['surName']].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join(' ');
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final q = _query.trim().toLowerCase();
    return _allStudents.where((s) {
      final stage = (s['studentStage'] ?? s['stageName'] ?? s['stage'])?.toString();
      final room = (s['classRoomName'] ?? s['classRoom'] ?? s['classroom'])?.toString();
      if (_selectedStage != null && stage != _selectedStage) return false;
      if (_selectedClassRoom != null && room != _selectedClassRoom) return false;
      if (q.isEmpty) return true;
      return [_studentName(s), s['id'], s['nationalIdNumber'], s['idNumber']].any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final id = '${student['id'] ?? ''}';
    if (id.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditStudentScreen(token: widget.token, studentId: id)));
    await _loadStudents();
  }

  Future<void> _addStudent() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddStudentScreen(token: widget.token, schoolId: widget.schoolId)));
    if (changed == true) await _loadStudents();
  }

  Future<void> _deactivateStudent(Map<String, dynamic> student) async {
    final id = student['id'];
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعطيل الطالب', textDirection: TextDirection.rtl),
        content: Text(
          'هل أنت متأكد من تعطيل الطالب ${_studentName(student)}؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      // هذا هو endpoint الفعلي المستخدم في EMIS حسب تسجيل الشبكة المرفق.
      final uri = Uri.parse(
        'https://emis.moedu.gov.iq/api/student/removestudent'
        '?id=${Uri.encodeQueryComponent('$id')}'
        '&schoolId=${Uri.encodeQueryComponent(widget.schoolId)}',
      );
      final response = await http.post(uri, headers: _headers);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(response.bodyBytes);
        throw Exception(
          'HTTP ${response.statusCode}${body.isEmpty ? '' : ': $body'}',
        );
      }

      await _loadStudents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعطيل الطالب بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تعطيل الطالب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, mode, child) {
        final dark = mode == ThemeMode.dark;
        final bg = dark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final card = dark ? const Color(0xFF1E1E1E) : Colors.white;
        final text = dark ? Colors.white : Colors.black87;
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('تعديل الطلاب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            centerTitle: true,
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]))),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(tooltip: 'إضافة طالب جديد', onPressed: _addStudent, icon: const Icon(Icons.person_add_alt_1, color: Colors.white)),
              IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _loadStudents, icon: const Icon(Icons.refresh, color: Colors.white)),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadStudents,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Colors.red), textDirection: TextDirection.rtl)),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _selectedStage, isExpanded: true,
                    decoration: InputDecoration(labelText: 'اختر الصف', filled: true, fillColor: card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                    dropdownColor: card, style: TextStyle(color: text),
                    items: _stages.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() { _selectedStage = v; _selectedClassRoom = null; }),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<String>(
                    value: _selectedClassRoom, isExpanded: true,
                    decoration: InputDecoration(labelText: 'اختر الشعبة', filled: true, fillColor: card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                    dropdownColor: card, style: TextStyle(color: text),
                    items: _classRooms.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: _selectedStage == null ? null : (v) => setState(() => _selectedClassRoom = v),
                  )),
                ]),
                const SizedBox(height: 14),
                TextField(textDirection: TextDirection.rtl, onChanged: (v) => setState(() => _query = v), decoration: InputDecoration(filled: true, fillColor: card, hintText: 'ابحث باسم الطالب أو الرقم', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none))),
                const SizedBox(height: 14),
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)), child: Row(children: [const Icon(Icons.people_alt_outlined, color: Colors.indigo), const SizedBox(width: 10), Text('${_filteredStudents.length} طالب', style: TextStyle(fontWeight: FontWeight.bold, color: text)), const Spacer(), if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))])),
                const SizedBox(height: 12),
                if (_filteredStudents.isEmpty) Container(padding: const EdgeInsets.all(35), decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)), child: Column(children: [const Icon(Icons.person_search_outlined, size: 55, color: Colors.grey), const SizedBox(height: 12), Text('لا توجد نتائج مطابقة للبحث', textAlign: TextAlign.center, style: TextStyle(color: text, fontWeight: FontWeight.bold))]))
                else ..._filteredStudents.map((s) => _studentCard(s, card, text)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _studentCard(Map<String, dynamic> s, Color card, Color text) {
    final stage = '${s['studentStage'] ?? s['stageName'] ?? ''}';
    final room = '${s['classRoomName'] ?? s['classRoom'] ?? ''}';
    return Card(
      color: card, elevation: 1.5, margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(textDirection: TextDirection.rtl, children: [
          CircleAvatar(radius: 27, backgroundColor: Colors.indigo.withOpacity(.12), child: const Icon(Icons.person, color: Colors.indigo, size: 30)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_studentName(s), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: text), textAlign: TextAlign.right),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.end, spacing: 6, children: [if (stage.isNotEmpty) _chip(stage, Colors.indigo), if (room.isNotEmpty) _chip('شعبة $room', Colors.blue)]),
            const SizedBox(height: 5), Text('رقم الطالب: ${s['id'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          IconButton(tooltip: 'تعطيل الطالب', onPressed: () => _deactivateStudent(s), icon: const Icon(Icons.person_off_outlined, color: Colors.redAccent)),
          IconButton(tooltip: 'تعديل بيانات الطالب', onPressed: () => _openStudent(s), icon: const Icon(Icons.edit_outlined, color: Colors.indigo)),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)));
}
