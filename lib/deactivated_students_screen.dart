import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DeactivatedStudentsScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  const DeactivatedStudentsScreen({super.key, required this.token, required this.schoolId});
  @override State<DeactivatedStudentsScreen> createState() => _DeactivatedStudentsScreenState();
}

class _DeactivatedStudentsScreenState extends State<DeactivatedStudentsScreen> {
  List<Map<String, dynamic>> students = [];
  bool loading = true;
  String q = '';
  String? error;
  Map<String, String> get h => {'Authorization': widget.token, 'Accept': 'application/json'};

  @override void initState() { super.initState(); load(); }

  dynamic _unwrap(dynamic d) => d is Map && d['data'] != null ? d['data'] : d;

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    String? e;
    for (final p in [
      '/student/getdeactivatedstudents?schoolId=${widget.schoolId}',
      '/student/getdeactivatedstudents?entityId=${widget.schoolId}',
      '/student/getstudents?schoolId=${widget.schoolId}&entityId=${widget.schoolId}&isActive=false',
    ]) {
      try {
        final r = await http.get(Uri.parse('https://emis.moedu.gov.iq/api$p'), headers: h);
        if (r.statusCode == 200) {
          final x = _unwrap(jsonDecode(utf8.decode(r.bodyBytes)));
          if (x is List) students = x.whereType<Map>().map((z) => Map<String, dynamic>.from(z)).toList();
          if (mounted) setState(() => loading = false);
          return;
        }
        e = 'HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}';
        if (r.statusCode != 404) break;
      } catch (ex) { e = '$ex'; }
    }
    if (mounted) setState(() { loading = false; error = e ?? 'تعذر تحميل الطلبة غير المفعلين'; });
  }

  String name(Map<String, dynamic> s) {
    final f = s['fullName'] ?? s['studentName'];
    if ('$f'.trim().isNotEmpty) return '$f';
    return [s['name'], s['fatherName'], s['grandFatherName'], s['surName']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' ');
  }

  Future<void> _activateStudent(Map<String, dynamic> s) async {
    final id = s['id'];
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تفعيل الطالب', textDirection: TextDirection.rtl),
        content: Text('هل تريد تفعيل الطالب ${name(s)}؟', textDirection: TextDirection.rtl),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تفعيل'))],
      ),
    );
    if (ok != true) return;
    String? e;
    for (final path in ['/student/activate/$id', '/student/activatestudent/$id']) {
      for (final method in ['POST', 'PUT', 'DELETE']) {
        try {
          final uri = Uri.parse('https://emis.moedu.gov.iq/api$path');
          final r = method == 'POST' ? await http.post(uri, headers: h) : method == 'PUT' ? await http.put(uri, headers: h) : await http.delete(uri, headers: h);
          if (r.statusCode >= 200 && r.statusCode < 300) {
            await load();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تفعيل الطالب بنجاح'), backgroundColor: Colors.green));
            return;
          }
          e = 'HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}';
        } catch (ex) { e = '$ex'; }
      }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تفعيل الطالب: ${e ?? 'استجابة غير معروفة'}'), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = students.where((s) => name(s).toLowerCase().contains(q.trim().toLowerCase()) || '${s['id'] ?? ''}'.contains(q.trim())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الطلبة غير المفعلين', style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFFB71C1C), iconTheme: const IconThemeData(color: Colors.white), actions: [IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh, color: Colors.white))]),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(textDirection: TextDirection.rtl, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(labelText: 'بحث باسم الطالب أو الرقم', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
          const SizedBox(height: 12),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red), textDirection: TextDirection.rtl),
          if (loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا يوجد طلبة غير مفعلين')))
          else ...filtered.map((s) => Card(margin: const EdgeInsets.only(bottom: 9), child: Directionality(textDirection: TextDirection.rtl, child: ListTile(title: Text(name(s)), subtitle: Text('رقم الطالب: ${s['id'] ?? ''}'), leading: const Icon(Icons.person_off, color: Colors.redAccent), trailing: IconButton(onPressed: () => _activateStudent(s), icon: const Icon(Icons.person_add_alt_1, color: Colors.green), tooltip: 'تفعيل الطالب'))))),
        ]),
      ),
    );
  }
}
