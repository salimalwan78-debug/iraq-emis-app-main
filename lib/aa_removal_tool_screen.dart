import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_core.dart';

class AARemovalToolScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;

  const AARemovalToolScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allStudents,
  });

  @override
  State<AARemovalToolScreen> createState() => _AARemovalToolScreenState();
}

class _AARemovalToolScreenState extends State<AARemovalToolScreen> {
  bool _isWorking = false;
  final Set<String> _successfulIds = <String>{};
  final Set<String> _failedIds = <String>{};
  final Set<String> _skippedIds = <String>{};

  String _nameOf(dynamic student) {
    if (student is! Map) return 'بدون اسم';
    final direct = student['fullName'] ?? student['studentName'];
    if (direct != null && direct.toString().trim().isNotEmpty) return direct.toString().trim();
    final parts = [
      student['name'],
      student['firstName'],
      student['fatherName'],
      student['grandFatherName'],
      student['surName'],
    ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? 'بدون اسم' : parts.join(' ');
  }

  String? _nationalId(dynamic student) {
    if (student is! Map) return null;
    final candidates = [
      student['nationalIdNumber'],
      if (student['identification'] is Map) (student['identification'] as Map)['idNumber'],
      student['idNumber'],
    ];
    for (final value in candidates) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _newId(String oldId) {
    var result = oldId.replaceFirst(RegExp(r'^AA', caseSensitive: false), '');
    result = result.replaceFirst(RegExp(r'^0+'), '');
    return result;
  }

  String _studentKey(dynamic student) => (student is Map ? student['id'] : null)?.toString() ?? '';

  List<Map<String, dynamic>> get _targets {
    final result = <Map<String, dynamic>>[];
    for (final item in widget.allStudents) {
      if (item is! Map) continue;
      final oldId = _nationalId(item);
      if (oldId != null && RegExp(r'^AA', caseSensitive: false).hasMatch(oldId)) {
        result.add({
          'student': item,
          'oldId': oldId,
          'newId': _newId(oldId),
        });
      }
    }
    return result;
  }

  Future<bool> _updateStudent(Map<String, dynamic> student, String newId) async {
    final payload = jsonDecode(jsonEncode(student)) as Map<String, dynamic>;

    if (payload['nationalIdNumber'] != null) {
      payload['nationalIdNumber'] = newId;
    } else if (payload['identification'] is Map) {
      final identification = Map<String, dynamic>.from(payload['identification'] as Map);
      identification['idNumber'] = newId;
      payload['identification'] = identification;
    } else {
      payload['idNumber'] = newId;
    }

    final response = await http.post(
      Uri.parse('https://emis.moedu.gov.iq/api/student/updatestudent'),
      headers: {
        'Authorization': widget.token,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      debugPrint('AA update failed ${response.statusCode}: ${response.body}');
      return false;
    }

    if (student['nationalIdNumber'] != null) {
      student['nationalIdNumber'] = newId;
    } else if (student['identification'] is Map) {
      (student['identification'] as Map)['idNumber'] = newId;
    } else {
      student['idNumber'] = newId;
    }
    return true;
  }

  Future<void> _run() async {
    final targets = _targets;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طالب يبدأ رقم هويته بـ AA.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تعديل أرقام الهوية'),
        content: Text('سيتم تعديل ${targets.length} طالبًا من البيانات الموجودة في التطبيق.\n\nلن يتم إعادة تحميل قائمة الطلاب.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isWorking = true;
      _successfulIds.clear();
      _failedIds.clear();
      _skippedIds.clear();
    });

    for (final target in targets) {
      final student = target['student'] as Map<String, dynamic>;
      final id = _studentKey(student);
      final oldId = target['oldId'] as String;
      final newId = target['newId'] as String;

      if (newId.length != 12 || !RegExp(r'^\d{12}$').hasMatch(newId)) {
        _skippedIds.add(id);
        continue;
      }

      try {
        final ok = await _updateStudent(student, newId);
        if (ok) {
          _successfulIds.add(id);
        } else {
          _failedIds.add(id);
        }
      } catch (e) {
        debugPrint('AA update error for $oldId: $e');
        _failedIds.add(id);
      }

      if (mounted) setState(() {});
    }

    if (mounted) {
      setState(() => _isWorking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اكتمل التنفيذ: ${_successfulIds.length} نجاح، ${_failedIds.length} فشل، ${_skippedIds.length} تجاوز.'),
          backgroundColor: _failedIds.isEmpty ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, mode, child) {
        final isDark = mode == ThemeMode.dark;
        final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final text = isDark ? Colors.white : Colors.black87;
        final targets = _targets;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('حذف AA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]))),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10, offset: const Offset(0, 5))]),
                  child: Row(
                    children: [
                      Container(width: 58, height: 58, decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(.1), shape: BoxShape.circle), child: const Icon(Icons.badge_outlined, color: Colors.deepOrange, size: 32)),
                      const SizedBox(width: 15),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('طلاب يحتاجون التعديل', style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 5), Text('${targets.length}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 26))])),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(width: double.infinity, height: 54, child: ElevatedButton.icon(onPressed: _isWorking ? null : _run, icon: const Icon(Icons.auto_fix_high, color: Colors.white), label: Text(_isWorking ? 'جاري التعديل...' : 'حذف AA والأصفار', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: targets.isEmpty
                    ? Center(child: Text('لا توجد سجلات تبدأ بـ AA', style: TextStyle(color: text, fontSize: 16)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
                        itemCount: targets.length,
                        itemBuilder: (context, index) {
                          final target = targets[index];
                          final student = target['student'] as Map<String, dynamic>;
                          final id = _studentKey(student);
                          final ok = _successfulIds.contains(id);
                          final failed = _failedIds.contains(id);
                          final skipped = _skippedIds.contains(id);
                          final status = ok ? 'تم التحديث' : failed ? 'فشل التحديث' : skipped ? 'تم التجاوز' : 'بانتظار التنفيذ';
                          final statusColor = ok ? Colors.green : failed ? Colors.red : skipped ? Colors.orange : Colors.grey;
                          return Card(
                            color: card,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: statusColor.withOpacity(.12), child: Icon(ok ? Icons.check : failed ? Icons.error_outline : Icons.person, color: statusColor)),
                              title: Text(_nameOf(student), style: TextStyle(color: text, fontWeight: FontWeight.bold)),
                              subtitle: Text('${target['oldId']}  →  ${target['newId']}\n$status', style: TextStyle(color: statusColor, height: 1.4)),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
