import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DeactivatedStudentsScreen extends StatefulWidget {
  final String token;
  final String schoolId;

  const DeactivatedStudentsScreen({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  State<DeactivatedStudentsScreen> createState() =>
      _DeactivatedStudentsScreenState();
}

class _DeactivatedStudentsScreenState extends State<DeactivatedStudentsScreen> {
  List<Map<String, dynamic>> students = [];
  bool loading = true;
  String q = '';
  String? error;

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  dynamic _unwrap(dynamic d) =>
      d is Map && d['data'] != null ? d['data'] : d;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final uri = Uri.parse(
        'https://emis.moedu.gov.iq/api/student/getstudents'
        '?page=1&rowsPerPage=20&sortBy=id&sortOrder=desc'
        '&entityId=${Uri.encodeQueryComponent(widget.schoolId)}'
        '&onlyDeactivated=true',
      );
      final response = await http.get(uri, headers: h);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
        );
      }
      final decoded = _unwrap(jsonDecode(utf8.decode(response.bodyBytes)));
      final data = decoded is List ? decoded : const <dynamic>[];
      final list = data
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      if (!mounted) return;
      setState(() {
        students = list;
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

  String name(Map<String, dynamic> s) {
    final direct = s['fullName'] ?? s['studentName'];
    if ('$direct'.trim().isNotEmpty) return '$direct';
    return [s['name'], s['fatherName'], s['grandFatherName'], s['surName']]
        .where((x) => x != null && '$x'.trim().isNotEmpty)
        .join(' ');
  }

  Future<void> _activateStudent(Map<String, dynamic> student) async {
    final id = student['id'];
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفعيل الطالب', textDirection: TextDirection.rtl),
        content: Text(
          'هل تريد تفعيل الطالب ${name(student)}؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final uri = Uri.parse(
        'https://emis.moedu.gov.iq/api/student/activatestudent'
        '?id=${Uri.encodeQueryComponent('$id')}'
        '&schoolId=${Uri.encodeQueryComponent(widget.schoolId)}',
      );
      final response = await http.post(uri, headers: h);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
        );
      }
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل الطالب بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تفعيل الطالب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final filtered = students.where((student) {
      return name(student).toLowerCase().contains(query) ||
          '${student['id'] ?? ''}'.contains(q.trim());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الطلبة غير المفعلين',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFFB71C1C),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'تحديث القائمة',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(
                  labelText: 'بحث باسم الطالب أو الرقم',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: Text('لا يوجد طلبة غير مفعلين')),
                )
              else
                ...filtered.map(
                  (student) => Card(
                    margin: const EdgeInsets.only(bottom: 9),
                    child: ListTile(
                      title: Text(name(student)),
                      subtitle: Text('رقم الطالب: ${student['id'] ?? ''}'),
                      leading: const Icon(Icons.person_off, color: Colors.redAccent),
                      trailing: IconButton(
                        onPressed: () => _activateStudent(student),
                        icon: const Icon(Icons.person_add_alt_1, color: Colors.green),
                        tooltip: 'تفعيل الطالب',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
