import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_core.dart';
import 'edit_student_screen.dart';
import 'add_student_screen.dart';

class SelectStudentScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> preLoadedStudents;

  const SelectStudentScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.preLoadedStudents,
  });

  @override
  State<SelectStudentScreen> createState() => _SelectStudentScreenState();
}

class _SelectStudentScreenState extends State<SelectStudentScreen> {
  late List<Map<String, dynamic>> _allStudents;
  final Map<String, String> _phoneCache = <String, String>{};
  final Set<String> _fetchingIds = <String>{};

  String _query = '';
  String? _selectedStage;
  String? _selectedClassRoom;
  bool _loading = false;
  bool _loadingPhones = false;
  int _phonesLoadedCount = 0;
  int _phonesTotalToLoad = 0;
  bool _disposed = false;
  int _scanGeneration = 0;
  String? _error;

  String get _cacheStorageKey => 'emis_student_phones_cache_${widget.schoolId}';

  Map<String, String> get _headers => {
        'Authorization': widget.token,
        'Accept': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _allStudents = widget.preLoadedStudents
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _initAndLoad();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanGeneration++;
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    await _restorePhoneCache();
    await _loadStudents();
  }

  Future<void> _restorePhoneCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final key = k.toString().trim();
            final val = v?.toString().trim() ?? '';
            if (key.isNotEmpty && val.isNotEmpty) {
              _phoneCache[key] = val;
            }
          });
        }
      }
      _applyCachedPhonesToStudents();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _persistPhoneCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheStorageKey, jsonEncode(_phoneCache));
    } catch (_) {}
  }

  void _applyCachedPhonesToStudents() {
    for (final s in _allStudents) {
      final id = '${s['id'] ?? ''}'.trim();
      if (id.isNotEmpty && _phoneCache.containsKey(id)) {
        final cached = _phoneCache[id]!;
        if (cached.isNotEmpty && cached != '-') {
          s['homePhoneNumber'] = cached;
        }
      }
    }
  }

  dynamic _unwrap(dynamic d) => d is Map && d['data'] != null ? d['data'] : d;

  String _extractPhoneFromMap(Map<String, dynamic> s) {
    final address = s['address'];
    final candidates = <dynamic>[
      if (address is Map) address['mobilePhoneNumber'],
      s['mobilePhoneNumber'],
      s['homePhoneNumber'],
      if (address is Map) address['homePhoneNumber'],
      if (address is Map) address['schoolPhoneNumber'],
      if (address is Map) address['phoneNumber'],
      s['phoneNumber'],
      s['phone'],
    ];
    for (final value in candidates) {
      final phone = value?.toString().trim() ?? '';
      if (phone.isNotEmpty && phone != 'null') return phone;
    }
    return '';
  }

  Future<void> _loadStudents() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await http.get(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/student/getstudents?page=1&rowsPerPage=3000&sortBy=id&sortOrder=desc&entityId=${widget.schoolId}',
        ),
        headers: _headers,
      );
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception('HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
      }
      final data = _unwrap(jsonDecode(utf8.decode(r.bodyBytes)));
      if (data is List) {
        _allStudents = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      _applyCachedPhonesToStudents();
      if (mounted) setState(() => _loading = false);

      // بدء جلب أرقام الهواتف للطلاب الذين لم تُجلب أرقامهم بعد
      unawaited(_fetchMissingPhonesConcurrently());
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<String?> _fetchSingleStudentPhone(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('https://emis.moedu.gov.iq/api/student/getstudent/$id'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;
      final decoded = _unwrap(jsonDecode(utf8.decode(response.bodyBytes)));
      if (decoded is Map) {
        final fullMap = decoded.map((k, v) => MapEntry(k.toString(), v));
        final phone = _extractPhoneFromMap(fullMap);
        // نخزن '-' إذا لم يكن لدى الطالب رقم فعلي في السيرفر لكي لا نعيد طلبه في كل مرة
        return phone.isEmpty ? '-' : phone;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchMissingPhonesConcurrently({bool forceRefreshAll = false}) async {
    final currentGen = ++_scanGeneration;

    if (forceRefreshAll) {
      _phoneCache.clear();
    }

    // تحديد الطلاب الذين لم يُجلب لهم رقم هاتف بعد (مع إعطاء الأولوية للطلاب المعروضين حالياً)
    final filteredIds = _filteredStudents
        .map((s) => '${s['id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final pendingStudents = <Map<String, dynamic>>[];
    for (final s in _allStudents) {
      final id = '${s['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final directPhone = _extractPhoneFromMap(s);
      if (directPhone.isNotEmpty) {
        _phoneCache[id] = directPhone;
        continue;
      }
      if (!_phoneCache.containsKey(id)) {
        pendingStudents.add(s);
      }
    }

    // ترتيب الأولوية للطلاب المطابقين للفلتر الحالي في أعلى الشاشة
    pendingStudents.sort((a, b) {
      final aInView = filteredIds.contains('${a['id'] ?? ''}') ? 0 : 1;
      final bInView = filteredIds.contains('${b['id'] ?? ''}') ? 0 : 1;
      return aInView.compareTo(bInView);
    });

    if (pendingStudents.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingPhones = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingPhones = true;
        _phonesLoadedCount = 0;
        _phonesTotalToLoad = pendingStudents.length;
      });
    }

    const int concurrency = 8;
    int nextIndex = 0;
    int completed = 0;

    Future<void> worker() async {
      while (!_disposed && currentGen == _scanGeneration) {
        final idx = nextIndex++;
        if (idx >= pendingStudents.length) return;

        final student = pendingStudents[idx];
        final id = '${student['id'] ?? ''}'.trim();
        if (id.isEmpty || _fetchingIds.contains(id)) continue;

        _fetchingIds.add(id);
        try {
          final phoneResult = await _fetchSingleStudentPhone(id);
          if (_disposed || currentGen != _scanGeneration) return;

          if (phoneResult != null) {
            _phoneCache[id] = phoneResult;
            if (phoneResult != '-') {
              student['homePhoneNumber'] = phoneResult;
            }
          }
        } finally {
          _fetchingIds.remove(id);
          completed++;
          if (!_disposed &&
              currentGen == _scanGeneration &&
              mounted &&
              (completed % 6 == 0 || completed == pendingStudents.length)) {
            setState(() {
              _phonesLoadedCount = completed;
            });
            unawaited(_persistPhoneCache());
          }
        }
      }
    }

    final workersCount = pendingStudents.length < concurrency
        ? pendingStudents.length
        : concurrency;
    await Future.wait(List.generate(workersCount, (_) => worker()));

    if (!_disposed && currentGen == _scanGeneration) {
      await _persistPhoneCache();
      if (mounted) {
        setState(() {
          _loadingPhones = false;
        });
      }
    }
  }

  List<String> get _stages => _allStudents
      .map((s) =>
          (s['studentStage'] ?? s['stageName'] ?? s['stage'] ?? '').toString())
      .where((s) => s.trim().isNotEmpty)
      .toSet()
      .toList();

  List<String> get _classRooms {
    if (_selectedStage == null) return [];
    return _allStudents
        .where((s) =>
            (s['studentStage'] ?? s['stageName'] ?? s['stage'])?.toString() ==
            _selectedStage)
        .map((s) =>
            (s['classRoomName'] ?? s['classRoom'] ?? s['classroom'] ?? '')
                .toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  String _studentName(Map<String, dynamic> s) {
    final direct = s['fullName'] ?? s['studentName'];
    if (direct != null && '$direct'.trim().isNotEmpty) return '$direct'.trim();
    final combined = [
      s['name'],
      s['fatherName'],
      s['grandFatherName'],
      s['surName']
    ].map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join(' ');
    return combined.trim().isEmpty ? 'بدون اسم' : combined;
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final q = _query.trim().toLowerCase();
    return _allStudents.where((s) {
      final stage =
          (s['studentStage'] ?? s['stageName'] ?? s['stage'])?.toString();
      final room =
          (s['classRoomName'] ?? s['classRoom'] ?? s['classroom'])?.toString();
      if (_selectedStage != null && stage != _selectedStage) return false;
      if (_selectedClassRoom != null && room != _selectedClassRoom) return false;
      if (q.isEmpty) return true;
      return [
        _studentName(s),
        s['id'],
        s['nationalIdNumber'],
        s['idNumber'],
        _studentPhone(s),
      ].any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
  }

  String _studentPhone(Map<String, dynamic> s) {
    final direct = _extractPhoneFromMap(s);
    if (direct.isNotEmpty) return direct;

    final id = '${s['id'] ?? ''}'.trim();
    if (id.isNotEmpty && _phoneCache.containsKey(id)) {
      final cached = _phoneCache[id]!;
      if (cached.isNotEmpty && cached != '-') return cached;
      if (cached == '-') return 'غير مسجل';
    }

    if (_loadingPhones) return 'جاري القراءة...';
    return 'غير مسجل';
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final id = '${student['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditStudentScreen(token: widget.token, studentId: id),
      ),
    );
    // حذف رقم الطالب المعدل من الذاكرة المؤقتة ليتم جلبه مجدداً بأحدث قيمة
    _phoneCache.remove(id);
    await _loadStudents();
  }

  Future<void> _addStudent() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddStudentScreen(token: widget.token, schoolId: widget.schoolId),
      ),
    );
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

      _phoneCache.remove('$id');
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
            title: const Text(
              'تعديل الطلاب',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'إضافة طالب جديد',
                onPressed: _addStudent,
                icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
              ),
              IconButton(
                tooltip: 'تحديث القائمة وأرقام الهواتف',
                onPressed: _loading
                    ? null
                    : () async {
                        await _loadStudents();
                        unawaited(_fetchMissingPhonesConcurrently(
                            forceRefreshAll: true));
                      },
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadStudents,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStage,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'اختر الصف',
                          filled: true,
                          fillColor: card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        dropdownColor: card,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                        items: _stages
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedStage = v;
                            _selectedClassRoom = null;
                          });
                          unawaited(_fetchMissingPhonesConcurrently());
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedClassRoom,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'اختر الشعبة',
                          filled: true,
                          fillColor: card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        dropdownColor: card,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                        items: _classRooms
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                ))
                            .toList(),
                        onChanged: _selectedStage == null
                            ? null
                            : (v) {
                                setState(() => _selectedClassRoom = v);
                                unawaited(_fetchMissingPhonesConcurrently());
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  textDirection: TextDirection.rtl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: card,
                    hintText: 'ابحث باسم الطالب أو الرقم أو الهاتف',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people_alt_outlined, color: Colors.indigo),
                      const SizedBox(width: 10),
                      Text(
                        '${_filteredStudents.length} طالب',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingPhones) ...[
                        Text(
                          'جلب الهواتف: $_phonesLoadedCount / $_phonesTotalToLoad',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_loading || _loadingPhones)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_filteredStudents.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(35),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.person_search_outlined,
                          size: 55,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد نتائج مطابقة للبحث',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._filteredStudents.map((s) => _studentCard(s, card, text)),
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
    final phoneText = _studentPhone(s);
    final hasValidPhone =
        phoneText != 'غير مسجل' && phoneText != 'جاري القراءة...';

    return Card(
      color: card,
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: Colors.indigo.withOpacity(.12),
              child: const Icon(Icons.person, color: Colors.indigo, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _studentName(s),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: text,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    children: [
                      if (stage.isNotEmpty) _chip(stage, Colors.indigo),
                      if (room.isNotEmpty) _chip('شعبة $room', Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'رقم الطالب: ${s['id'] ?? 'غير متوفر'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'رقم الهاتف: $phoneText',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: hasValidPhone ? Colors.green.shade600 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تعطيل الطالب',
              onPressed: () => _deactivateStudent(s),
              icon: const Icon(
                Icons.person_off_outlined,
                color: Colors.redAccent,
              ),
            ),
            IconButton(
              tooltip: 'تعديل بيانات الطالب',
              onPressed: () => _openStudent(s),
              icon: const Icon(Icons.edit_outlined, color: Colors.indigo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
