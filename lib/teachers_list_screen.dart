import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'edit_teacher_screen.dart';
import 'teacher_smart_tools_screen.dart';
import 'add_teacher_screen.dart';

class TeachersListScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> initialTeachers;

  const TeachersListScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.initialTeachers,
  });

  @override
  State<TeachersListScreen> createState() => _TeachersListScreenState();
}

class _TeachersListScreenState extends State<TeachersListScreen> {
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  bool _loading = true;
  String _query = '';
  int _totalActive = 0;
  int _permanent = 0;
  int _contract = 0;
  String? _error;

  Map<String, String> get _headers => {
        'Authorization': widget.token,
        'Accept': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _teachers = widget.initialTeachers
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final uri = Uri.parse(
        'https://emis.moedu.gov.iq/api/employee/getemployeesbyentities'
        '?page=1&rowsPerPage=1000&sortBy=id&sortOrder=desc'
        '&entityId=${Uri.encodeQueryComponent(widget.schoolId)}&isTeacher=true',
      );
      final summaryUri = Uri.parse(
        'https://emis.moedu.gov.iq/api/employee/getemployeessummary'
        '?entityId=${Uri.encodeQueryComponent(widget.schoolId)}&isTeacher=true',
      );

      final results = await Future.wait([
        http.get(uri, headers: _headers),
        http.get(summaryUri, headers: _headers),
      ]);

      final listResponse = results[0];
      final summaryResponse = results[1];

      if (listResponse.statusCode != 200) {
        throw Exception('HTTP ${listResponse.statusCode}');
      }

      final decoded = jsonDecode(utf8.decode(listResponse.bodyBytes));
      final data = decoded is Map ? decoded['data'] : null;
      final teachers = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      if (summaryResponse.statusCode == 200) {
        final summary = jsonDecode(utf8.decode(summaryResponse.bodyBytes));
        _totalActive = _asInt(summary['totalActive']);
        _permanent = _asInt(summary['permanent']);
        _contract = _asInt(summary['contract']);
      }

      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل بيانات المعلمين: $e';
      });
    }
  }

  int _asInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  List<Map<String, dynamic>> get _filteredTeachers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _teachers;
    return _teachers.where((teacher) {
      final values = [
        teacher['employeeFullName'],
        teacher['nationalIdNumber'],
        teacher['employeeIdNumber'],
        teacher['classification'],
        teacher['employmentType'],
        teacher['currentEmploymentStatus'],
      ];
      return values.any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
  }

  static const List<String> _employmentStatusOptions = [
    'مستمر',
    'متقاعد',
    'مفصول',
    'متوفى',
    'في إجازة دراسية',
    'في إجازة أمومة',
    'أخرى',
  ];

  Future<void> _updateTeacherStatus(Map<String, dynamic> teacher) async {
    final employeeId = teacher['id'];
    if (employeeId == null || '$employeeId'.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديد رقم المعلم.')),
      );
      return;
    }

    String selectedStatus =
        '${teacher['currentEmploymentStatus'] ?? 'مستمر'}'.trim();
    if (!_employmentStatusOptions.contains(selectedStatus)) {
      selectedStatus = 'مستمر';
    }
    final documentController = TextEditingController();
    final reasonController = TextEditingController();
    bool saving = false;
    String? dialogError;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: !saving,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> save() async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(() {
                    dialogError = 'سبب تغيير الحالة الوظيفية مطلوب.';
                  });
                  return;
                }

                setDialogState(() {
                  saving = true;
                  dialogError = null;
                });

                try {
                  final uri = Uri.parse(
                    'https://emis.moedu.gov.iq/api/employee/updateemploymentstatus',
                  );
                  final body = <String, dynamic>{
                    'employeeId': employeeId is num
                        ? employeeId
                        : int.tryParse('$employeeId') ?? employeeId,
                    'statusType': selectedStatus,
                    'ministryOfficialDocumentNumber':
                        documentController.text.trim().isEmpty
                            ? null
                            : documentController.text.trim(),
                    'reason': reason,
                  };

                  final response = await http.post(
                    uri,
                    headers: {
                      ..._headers,
                      'Content-Type': 'application/json',
                    },
                    body: jsonEncode(body),
                  );

                  if (response.statusCode < 200 ||
                      response.statusCode >= 300) {
                    String details = utf8.decode(response.bodyBytes).trim();
                    if (details.isEmpty) {
                      details = 'HTTP ${response.statusCode}';
                    }
                    throw Exception(details);
                  }

                  if (!mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  setDialogState(() {
                    saving = false;
                    dialogError = 'فشل تحديث حالة المعلم: $e';
                  });
                }
              }

              return AlertDialog(
                title: const Text(
                  'تحديث حالة المعلم',
                  textDirection: TextDirection.rtl,
                ),
                content: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedStatus,
                          decoration: const InputDecoration(
                            labelText: 'الحالة الوظيفية *',
                            border: OutlineInputBorder(),
                          ),
                          items: _employmentStatusOptions
                              .map(
                                (status) => DropdownMenuItem<String>(
                                  value: status,
                                  child: Text(status),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    selectedStatus = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: documentController,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'رقم الأمر الإداري / الوثيقة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: reasonController,
                          enabled: !saving,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'سبب تغيير الحالة الوظيفية *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (dialogError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed: saving ? null : save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('حفظ'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث حالة المعلم بنجاح.'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadTeachers();
      }
    } finally {
      documentController.dispose();
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('إدارة المعلمين', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF4527A0),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'إضافة معلم جديد',
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AddTeacherScreen(token: widget.token, schoolId: widget.schoolId),
                ),
              );
              if (changed == true) await _loadTeachers();
            },
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadTeachers,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTeachers,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _buildSummary(card, text),
            const SizedBox(height: 14),
            Card(
              color: card,
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.10), shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                ),
                title: Text('الأدوات الذكية للمعلمين', style: TextStyle(fontWeight: FontWeight.bold, color: text)),
                subtitle: const Text('إضافة صور المعلمين جماعيًا مع حفظ سجل الجلسة'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 17, color: Colors.deepPurple),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherSmartToolsScreen(
                      token: widget.token,
                      schoolId: widget.schoolId,
                      allTeachers: _teachers,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              textDirection: TextDirection.rtl,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                filled: true,
                fillColor: card,
                hintText: 'ابحث باسم المعلم أو رقم الهوية أو الرقم الوظيفي',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              _buildError(card, text)
            else if (_loading && _teachers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(50),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredTeachers.isEmpty)
              _buildEmpty(card, text)
            else
              ..._filteredTeachers.map((teacher) => _buildTeacherCard(teacher, card, text)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(Color card, Color text) {
    return Row(
      children: [
        Expanded(child: _summaryCard('المعلمون', '${_totalActive == 0 ? _teachers.length : _totalActive}', Icons.people, Colors.deepPurple, card, text)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('ملاك', '$_permanent', Icons.badge, Colors.blue, card, text)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('عقد', '$_contract', Icons.assignment_ind, Colors.orange, card, text)),
      ],
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, Color card, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text)),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> teacher, Color card, Color text) {
    final name = '${teacher['employeeFullName'] ?? 'بدون اسم'}';
    final id = '${teacher['id'] ?? ''}';
    final national = '${teacher['nationalIdNumber'] ?? ''}';
    final employeeNo = '${teacher['employeeIdNumber'] ?? ''}';
    final type = '${teacher['employmentType'] ?? ''}';
    final classification = '${teacher['classification'] ?? ''}';
    final status = '${teacher['currentEmploymentStatus'] ?? 'غير محدد'}';

    return Card(
      color: card,
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Colors.deepPurple.withOpacity(0.12),
                child: const Icon(Icons.person, color: Colors.deepPurple, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: text), textAlign: TextAlign.right),
                    const SizedBox(height: 7),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (classification.isNotEmpty) _chip(classification, Colors.deepPurple),
                        if (type.isNotEmpty) _chip(type, Colors.blue),
                        _chip(status, status == 'مستمر' ? Colors.green : Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (national.isNotEmpty)
                      Text('الهوية الوطنية: $national', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.right),
                    if (employeeNo.isNotEmpty)
                      Text('الرقم الوظيفي: $employeeNo', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.right),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'تحديث حالة المعلم',
                onPressed: () => _updateTeacherStatus(teacher),
                icon: const Icon(
                  Icons.manage_history_outlined,
                  color: Colors.orange,
                ),
              ),
              IconButton(
                tooltip: 'تعديل بيانات المعلم',
                onPressed: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditTeacherScreen(
                        token: widget.token,
                        schoolId: widget.schoolId,
                        teacherId: id,
                      ),
                    ),
                  );
                  if (changed == true) await _loadTeachers();
                },
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildError(Color card, Color text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 42),
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: text), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          ElevatedButton.icon(onPressed: _loadTeachers, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  Widget _buildEmpty(Color card, Color text) {
    return Container(
      padding: const EdgeInsets.all(35),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Icon(Icons.people_outline, size: 55, color: Colors.grey),
          const SizedBox(height: 12),
          Text(_query.isEmpty ? 'لا توجد بيانات للمعلمين' : 'لا توجد نتائج مطابقة للبحث', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
