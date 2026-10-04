import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GradeSmartToolsCard extends StatefulWidget {
  final String token;
  final String schoolId;

  const GradeSmartToolsCard({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  State<GradeSmartToolsCard> createState() => _GradeSmartToolsCardState();
}

class _GradeSmartToolsCardState extends State<GradeSmartToolsCard> {
  List<Map<String, dynamic>> stages = [];
  final Map<String, List<Map<String, dynamic>>> subjectsByStage = {};
  final Map<String, List<Map<String, dynamic>>> examsBySubject = {};

  final Set<String> selectedTerms = {};
  final Set<String> selectedStages = {};
  final Set<String> selectedSubjects = {};

  bool loadingCatalog = true;
  bool allStagesAndSubjects = false;
  bool running = false;
  String? error;
  String status = 'جاري قراءة الفصول والمواد من EMIS...';

  Map<String, String> get _headers => {
        'Authorization': widget.token.toLowerCase().startsWith('bearer ')
            ? widget.token
            : 'Bearer ${widget.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  dynamic _unwrap(dynamic value) =>
      value is Map && value['data'] != null ? value['data'] : value;

  List<Map<String, dynamic>> _maps(dynamic value) {
    final raw = _unwrap(value);
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  Future<dynamic> _get(String endpoint) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  String _id(Map<String, dynamic> x) =>
      '${x['value'] ?? x['id'] ?? x['stageId'] ?? ''}';

  String _label(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? x['labelAr'] ?? _id(x)}';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final rawStages = await _get(
        '/selectoption/getschoolstages/${widget.schoolId}',
      );
      stages = _maps(rawStages);

      int subjectCount = 0;
      int examCount = 0;
      for (final stage in stages) {
        final stageId = _id(stage);
        if (stageId.isEmpty) continue;
        status = 'جاري قراءة مواد ${_label(stage)}...';
        if (mounted) setState(() {});

        final rawSubjects = await _get(
          '/subject/getsubjectsselect?stageId=$stageId&schoolId=${widget.schoolId}',
        );
        final subjects = _maps(rawSubjects);
        subjectsByStage[stageId] = subjects;
        subjectCount += subjects.length;

        for (final subject in subjects) {
          final subjectId = _id(subject);
          if (subjectId.isEmpty) continue;
          final rawExams = await _get(
            '/examscore/getexamsformarks?schoolId=${widget.schoolId}'
            '&stageId=$stageId&subjectId=$subjectId',
          );
          final raw = rawExams is Map ? rawExams['exams'] : null;
          final exams = _maps(raw);
          examsBySubject['$stageId:$subjectId'] = exams;
          examCount += exams.length;
        }
      }

      if (!mounted) return;
      setState(() {
        loadingCatalog = false;
        status = 'تمت قراءة $subjectCount مادة و$examCount فصلاً من EMIS.';
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingCatalog = false;
        error = '$e';
        status = 'تعذر قراءة بيانات الفصول والمواد من EMIS.';
      });
    }
  }

  List<Map<String, dynamic>> get _selectedStageSubjects {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final stageId in selectedStages) {
      for (final subject in subjectsByStage[stageId] ?? const []) {
        final id = _id(subject);
        if (id.isNotEmpty && seen.add('$stageId:$id')) {
          result.add({...subject, '_stageId': stageId});
        }
      }
    }
    return result;
  }

  List<String> get _termLabels {
    final result = <String>[];
    final seen = <String>{};
    for (final exams in examsBySubject.values) {
      for (final exam in exams) {
        final label = _label(exam).trim();
        if (label.isNotEmpty && seen.add(label)) result.add(label);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> get _filteredSubjects {
    final allowed = selectedStages.isEmpty
        ? const <Map<String, dynamic>>[]
        : _selectedStageSubjects;
    final result = <Map<String, dynamic>>[];
    for (final subject in allowed) {
      final stageId = '${subject['_stageId']}';
      final id = _id(subject);
      if (selectedSubjects.contains('$stageId:$id')) {
        result.add(subject);
      }
    }
    return result;
  }

  void _setAllStagesAndSubjects(bool enabled) {
    setState(() {
      allStagesAndSubjects = enabled;
      if (enabled) {
        selectedStages
          ..clear()
          ..addAll(stages.map(_id).where((x) => x.isNotEmpty));
        selectedSubjects
          ..clear()
          ..addAll([
            for (final entry in subjectsByStage.entries)
              for (final subject in entry.value)
                if (_id(subject).isNotEmpty) '${entry.key}:${_id(subject)}',
          ]);
      } else {
        selectedStages.clear();
        selectedSubjects.clear();
      }
    });
  }

  Future<void> _chooseTerms() async {
    await _multiChoice(
      title: 'اختيار فصل أو عدة فصول من EMIS',
      items: _termLabels,
      selected: selectedTerms,
      allLabel: 'اختيار كل الفصول',
      onApply: (values) => setState(() => selectedTerms
        ..clear()
        ..addAll(values)),
    );
  }

  Future<void> _chooseStages() async {
    final items = [
      for (final stage in stages) _label(stage),
    ];
    final idsByLabel = <String, String>{
      for (final stage in stages) _label(stage): _id(stage),
    };
    final selectedLabels = <String>{
      for (final stage in stages)
        if (selectedStages.contains(_id(stage))) _label(stage),
    };

    await _multiChoice(
      title: 'اختيار الصف الدراسي',
      items: items,
      selected: selectedLabels,
      allLabel: 'اختيار كل الصفوف',
      onApply: (values) {
        final ids = values.map((x) => idsByLabel[x]).whereType<String>().toSet();
        setState(() {
          selectedStages
            ..clear()
            ..addAll(ids);
          selectedSubjects.removeWhere((key) => !ids.contains(key.split(':').first));
        });
      },
    );
  }

  Future<void> _chooseSubjects() async {
    final entries = _selectedStageSubjects;
    final labels = <String>[];
    final idsByLabel = <String, String>{};
    for (final subject in entries) {
      final stageId = '${subject['_stageId']}';
      final id = _id(subject);
      final label = '${_label(subject)} — ${_stageLabel(stageId)}';
      labels.add(label);
      idsByLabel[label] = '$stageId:$id';
    }
    final selectedLabels = <String>{
      for (final entry in idsByLabel.entries)
        if (selectedSubjects.contains(entry.value)) entry.key,
    };

    await _multiChoice(
      title: 'اختيار مادة دراسية أو عدة مواد',
      items: labels,
      selected: selectedLabels,
      allLabel: 'اختيار كل المواد',
      onApply: (values) => setState(() {
        selectedSubjects
          ..clear()
          ..addAll(values.map((x) => idsByLabel[x]).whereType<String>());
      }),
    );
  }

  String _stageLabel(String id) {
    for (final stage in stages) {
      if (_id(stage) == id) return _label(stage);
    }
    return id;
  }

  Future<void> _multiChoice({
    required String title,
    required List<String> items,
    required Set<String> selected,
    required String allLabel,
    required ValueChanged<Set<String>> onApply,
  }) async {
    final temp = {...selected};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            final all = items.isNotEmpty && temp.length == items.length;
            return AlertDialog(
              title: Text(title, textDirection: TextDirection.rtl),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: all,
                        title: Text(allLabel),
                        onChanged: items.isEmpty
                            ? null
                            : (v) => setDialog(() {
                                  temp.clear();
                                  if (v == true) temp.addAll(items);
                                }),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, index) {
                            final item = items[index];
                            return CheckboxListTile(
                              dense: true,
                              value: temp.contains(item),
                              title: Text(item, style: const TextStyle(fontWeight: FontWeight.bold)),
                              onChanged: (v) => setDialog(() {
                                if (v == true) {
                                  temp.add(item);
                                } else {
                                  temp.remove(item);
                                }
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, temp),
                  child: const Text('اعتماد الاختيار'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) onApply(result);
  }

  Future<void> _run(bool ignore) async {
    if (selectedTerms.isEmpty || selectedStages.isEmpty || selectedSubjects.isEmpty) {
      _show('اختر الفصول والصفوف والمواد أولاً.', Colors.orange);
      return;
    }

    final selectedSubjectsData = <Map<String, dynamic>>[];
    for (final subject in _selectedStageSubjects) {
      final stageId = '${subject['_stageId']}';
      final subjectId = _id(subject);
      if (selectedSubjects.contains('$stageId:$subjectId')) {
        selectedSubjectsData.add(subject);
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ignore ? 'إهمال الامتحان' : 'إلغاء إهمال الامتحان'),
        content: Text(
          'سيتم ${ignore ? 'إهمال' : 'إلغاء إهمال'} الفصول المحددة '
          'لـ ${selectedSubjectsData.length} اختيار مادة/صف. '
          'سيتم تنفيذ العملية على طلاب الصف للمادة كما يفعل EMIS.',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنفيذ')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      running = true;
      error = null;
      status = 'جاري تنفيذ العملية على EMIS...';
    });

    int ok = 0;
    int failed = 0;
    final failures = <String>[];

    try {
      for (final subject in selectedSubjectsData) {
        final stageId = '${subject['_stageId']}';
        final subjectId = _id(subject);
        final exams = examsBySubject['$stageId:$subjectId'] ?? [];

        final wantedExams = exams.where((exam) => selectedTerms.contains(_label(exam))).toList();
        if (wantedExams.isEmpty) continue;

        final studentsRaw = await _get(
          '/examscore/getstudentswithgrades?schoolId=${widget.schoolId}'
          '&stageId=$stageId&subjectId=$subjectId',
        );
        final students = _maps(studentsRaw);
        final ids = students
            .map((s) => int.tryParse('${s['id']}'))
            .whereType<int>()
            .toSet()
            .toList();
        if (ids.isEmpty) {
          failures.add('${_stageLabel(stageId)} / ${_label(subject)}: لا يوجد طلاب');
          continue;
        }

        for (final exam in wantedExams) {
          if (ignore && exam['isIgnorable'] == false) {
            failures.add('${_label(exam)}: EMIS يعتبره غير قابل للإهمال');
            continue;
          }
          final endpoint = ignore
              ? '/examscore/ignoreexamgrade'
              : '/examScore/unignoreexamgrade';
          final response = await http.post(
            Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
            headers: _headers,
            body: jsonEncode({
              'examId': int.tryParse(_id(exam)),
              'studentIds': ids,
            }),
          );
          if (response.statusCode >= 200 && response.statusCode < 300) {
            ok++;
          } else {
            failed++;
            failures.add(
              '${_stageLabel(stageId)} / ${_label(subject)} / ${_label(exam)}: '
              'HTTP ${response.statusCode} ${utf8.decode(response.bodyBytes)}',
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        status = 'اكتملت العملية: نجاح $ok — فشل $failed';
      });
      final details = failures.isEmpty ? '' : '\n${failures.first}';
      _show(
        'تم ${ignore ? 'إهمال' : 'إلغاء إهمال'} $ok عملية${failed == 0 ? '' : ' — فشل $failed'}$details',
        failed == 0 ? Colors.green : Colors.orange,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      _show('فشلت العملية: $e', Colors.red);
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  void _show(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFE8EAF6),
                    child: Icon(Icons.auto_awesome, color: Color(0xFF3949AB)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الأدوات الذكية للدرجات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('إهمال أو إلغاء إهمال الامتحانات مباشرة وفق بيانات EMIS.'),
                      ],
                    ),
                  ),
                  if (loadingCatalog)
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 10),
              Text(status, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              _choiceButton(
                label: 'الفصول',
                value: selectedTerms.isEmpty ? 'اختر فصلاً أو عدة فصول' : selectedTerms.join('، '),
                icon: Icons.event_note_rounded,
                enabled: !loadingCatalog && _termLabels.isNotEmpty,
                onTap: _chooseTerms,
              ),
              const SizedBox(height: 2),
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE1E6EF)),
                ),
                child: CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: allStagesAndSubjects,
                  onChanged: loadingCatalog
                      ? null
                      : (v) => _setAllStagesAndSubjects(v == true),
                  title: const Text(
                    'تطبيق العملية على جميع الصفوف والمواد الدراسية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'عند التفعيل لن تحتاج لاختيار الصفوف والمواد يدوياً.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _choiceButton(
                label: 'الصف الدراسي',
                value: selectedStages.isEmpty ? 'اختر صفاً أو عدة صفوف' : selectedStages.map(_stageLabel).join('، '),
                icon: Icons.school_rounded,
                enabled: !loadingCatalog && stages.isNotEmpty,
                onTap: _chooseStages,
              ),
              const SizedBox(height: 10),
              _choiceButton(
                label: 'المادة الدراسية',
                value: selectedSubjects.isEmpty ? 'اختر مادة أو عدة مواد' : '${selectedSubjects.length} مادة/صف',
                icon: Icons.menu_book_rounded,
                enabled: selectedStages.isNotEmpty,
                onTap: _chooseSubjects,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: running ? null : () => _run(true),
                      icon: const Icon(Icons.visibility_off_rounded),
                      label: const Text('إهمال الامتحان'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: running ? null : () => _run(false),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('إلغاء الإهمال'),
                    ),
                  ),
                ],
              ),
              if (running) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceButton({
    required String label,
    required String value,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF7F8FB) : Colors.grey.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE1E6EF)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF3949AB)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 3),
                  Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}
