import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_core.dart';

class BatchStudentPhotosScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allStudents;

  const BatchStudentPhotosScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allStudents,
  });

  @override
  State<BatchStudentPhotosScreen> createState() => _BatchStudentPhotosScreenState();
}

class _BatchStudentPhotosScreenState extends State<BatchStudentPhotosScreen> {
  String? _selectedStage;
  String? _selectedClassRoom;
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  int _currentIndex = 0;
  final Set<String> _photographed = <String>{};
  final Set<String> _notPhotographed = <String>{};
  final Set<String> _skipped = <String>{};
  File? _currentImage;
  bool _processing = false;
  bool _saving = false;
  bool _backgroundRemovedForCurrentImage = false;
  SelfieSegmenter? _segmenter;
  bool _restoringSession = false;

  String _sessionKey(String? stage, String? classroom) {
    final a = Uri.encodeComponent(stage ?? '');
    final b = Uri.encodeComponent(classroom ?? '');
    return 'batch_student_photo_session_${widget.schoolId}_${a}_${b}';
  }

  Future<void> _persistSession() async {
    if (_selectedStage == null || _selectedClassRoom == null || _students.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _sessionKey(_selectedStage, _selectedClassRoom);
      final payload = {
        'stage': _selectedStage,
        'classRoom': _selectedClassRoom,
        'photographed': _photographed.toList(),
        'skipped': _skipped.toList(),
        'notPhotographed': _notPhotographed.toList(),
        'currentIndex': _currentIndex,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(payload));
      await prefs.setString('batch_student_last_session_${widget.schoolId}', key);
    } catch (e) {
      debugPrint('Persist student batch session error: $e');
    }
  }

  Future<void> _restoreSessionForCurrentSelection() async {
    if (_selectedStage == null || _selectedClassRoom == null || _students.isEmpty) return;
    _restoringSession = true;
    if (mounted) setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _sessionKey(_selectedStage, _selectedClassRoom);
      final raw = prefs.getString(key);
      _photographed.clear();
      _notPhotographed.clear();
      _skipped.clear();
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) {
          final validIds = _students.map(_studentId).toSet();
          _photographed.addAll((data['photographed'] as List? ?? const []).map((e) => '$e').where(validIds.contains));
          _skipped.addAll((data['skipped'] as List? ?? const []).map((e) => '$e').where(validIds.contains));
          _notPhotographed.addAll((data['notPhotographed'] as List? ?? const []).map((e) => '$e').where(validIds.contains));
          _notPhotographed.addAll(_skipped);
          _notPhotographed.removeAll(_photographed);
        }
      }
      _currentIndex = _firstPendingIndex(_students);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Restore student batch session error: $e');
      _currentIndex = _firstPendingIndex(_students);
    } finally {
      _restoringSession = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _clearPersistedCurrentSession() async {
    if (_selectedStage == null || _selectedClassRoom == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey(_selectedStage, _selectedClassRoom));
      final lastKey = 'batch_student_last_session_${widget.schoolId}';
      if (prefs.getString(lastKey) == _sessionKey(_selectedStage, _selectedClassRoom)) {
        await prefs.remove(lastKey);
      }
    } catch (e) {
      debugPrint('Clear student batch session error: $e');
    }
  }

  Future<void> _restoreLastSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('batch_student_last_session_${widget.schoolId}');
      if (key == null || key.isEmpty || !mounted) return;
      final raw = prefs.getString(key);
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final stage = data['stage']?.toString();
      final classroom = data['classRoom']?.toString();
      if (stage == null || classroom == null || !_stages.contains(stage)) return;
      final filtered = widget.allStudents.whereType<Map>().where((s) {
        return s['studentStage']?.toString() == stage &&
            (s['classRoomName'] ?? s['classRoom'])?.toString() == classroom;
      }).map((s) => Map<String, dynamic>.from(s)).toList();
      if (filtered.isEmpty || !mounted) return;
      setState(() {
        _selectedStage = stage;
        _selectedClassRoom = classroom;
        _students = filtered;
      });
      await _restoreSessionForCurrentSelection();
    } catch (e) {
      debugPrint('Restore last student session error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreLastSession();
  }

  List<String> get _stages => widget.allStudents
      .whereType<Map>()
      .map((s) => s['studentStage']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  List<String> get _classRooms {
    if (_selectedStage == null) return <String>[];
    return widget.allStudents
        .whereType<Map>()
        .where((s) => s['studentStage']?.toString() == _selectedStage)
        .map((s) => (s['classRoomName'] ?? s['classRoom'])?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  String _studentId(Map<String, dynamic> s) => s['id']?.toString() ?? '';

  String _studentName(Map<String, dynamic> s) {
    final direct = s['fullName'] ?? s['studentName'];
    if (direct != null && direct.toString().trim().isNotEmpty) return direct.toString().trim();
    final parts = [s['name'], s['firstName'], s['fatherName'], s['grandFatherName'], s['surName']]
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'بدون اسم' : parts.join(' ');
  }

  void _selectStage(String? value) {
    setState(() {
      _selectedStage = value;
      _selectedClassRoom = null;
      _students = <Map<String, dynamic>>[];
      _currentIndex = 0;
      _photographed.clear();
      _notPhotographed.clear();
      _skipped.clear();
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
    });
  }

  void _selectClassRoom(String? value) {
    final filtered = widget.allStudents.whereType<Map>().where((s) {
      return s['studentStage']?.toString() == _selectedStage &&
          (s['classRoomName'] ?? s['classRoom'])?.toString() == value;
    }).map((s) => Map<String, dynamic>.from(s)).toList();

    setState(() {
      _selectedClassRoom = value;
      _students = filtered;
      _currentIndex = _firstPendingIndex(filtered);
      _photographed.clear();
      _notPhotographed.clear();
      _skipped.clear();
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
    });
    _restoreSessionForCurrentSelection();
  }

  int _firstPendingIndex(List<Map<String, dynamic>> list) {
    for (var i = 0; i < list.length; i++) {
      final id = _studentId(list[i]);
      if (!_photographed.contains(id) && !_skipped.contains(id)) return i;
    }
    return list.length;
  }

  Future<void> _initializeSegmenter() async {
    _segmenter ??= SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: false);
  }

  Future<File> _removeBackground(File imageFile) async {
    await _initializeSegmenter();
    final segmenter = _segmenter;
    if (segmenter == null) throw Exception('تعذر تهيئة أداة إزالة الخلفية');

    final bytes = await imageFile.readAsBytes();
    var source = img.decodeImage(bytes);
    if (source == null) throw Exception('تعذر قراءة الصورة');
    source = img.bakeOrientation(source);

    const maxDimension = 512;
    if (source.width > maxDimension || source.height > maxDimension) {
      source = img.copyResize(
        source,
        width: source.width >= source.height ? maxDimension : null,
        height: source.height > source.width ? maxDimension : null,
        interpolation: img.Interpolation.linear,
      );
    }

    final inputPath = '${imageFile.path}_seg_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final inputFile = File(inputPath);
    await inputFile.writeAsBytes(img.encodeJpg(source, quality: 90), flush: true);

    try {
      final mask = await segmenter.processImage(InputImage.fromFilePath(inputFile.path));
      if (mask == null || mask.width <= 0 || mask.height <= 0 || mask.confidences.isEmpty) {
        throw Exception('لم يتم الحصول على قناع صالح للشخص');
      }
      if (mask.width != source.width || mask.height != source.height) {
        throw Exception('أبعاد قناع إزالة الخلفية غير متطابقة');
      }

      final result = img.Image(width: source.width, height: source.height, numChannels: 4);
      final count = source.width * source.height;
      if (mask.confidences.length < count) throw Exception('بيانات القناع غير مكتملة');

      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final i = y * source.width + x;
          final confidence = mask.confidences[i].clamp(0.0, 1.0);
          final alpha = ((confidence - 0.35) / 0.40 * 255.0).round().clamp(0, 255);
          final pixel = source.getPixel(x, y);
          result.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
        }
      }

      final output = File('${imageFile.path}_nobg_${DateTime.now().millisecondsSinceEpoch}.png');
      await output.writeAsBytes(img.encodePng(result, level: 6), flush: true);
      return output;
    } finally {
      try {
        if (await inputFile.exists()) await inputFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_students.isEmpty ||
        _currentIndex >= _students.length ||
        _processing ||
        _saving) {
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2500,
        maxHeight: 2500,
      );
      if (picked == null || !mounted) return;

      final originalFile = File(picked.path);

      setState(() {
        _currentImage = originalFile;
        _backgroundRemovedForCurrentImage = false;
      });
    } catch (e) {
      debugPrint('Batch photo processing error: $e');
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر معالجة الصورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeBackgroundFromCurrentImage() async {
    if (_currentImage == null ||
        _processing ||
        _saving ||
        _backgroundRemovedForCurrentImage) {
      return;
    }

    final currentImage = _currentImage!;
    setState(() => _processing = true);

    try {
      final processed = await _removeBackground(currentImage);
      if (!mounted) return;

      setState(() {
        _currentImage = processed;
        _backgroundRemovedForCurrentImage = true;
        _processing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إزالة الخلفية من صورة الطالب'),
        ),
      );
    } catch (e) {
      debugPrint('Manual background removal error: $e');
      if (!mounted) return;

      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إزالة الخلفية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _takePhoto() => _pickImage(ImageSource.camera);

  Future<void> _pickFromGallery() => _pickImage(ImageSource.gallery);

  Future<void> _showImagePreview() async {
    final image = _currentImage;
    if (image == null || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(10),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  boundaryMargin: const EdgeInsets.all(100),
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Center(
                    child: Image.file(
                      image,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'إغلاق',
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Text(
                          'قرّب أو أبعد بإصبعين واسحب الصورة للتحريك',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _skipCurrentStudent() {
    if (_students.isEmpty ||
        _currentIndex >= _students.length ||
        _processing ||
        _saving) {
      return;
    }

    final student = _students[_currentIndex];
    final id = _studentId(student);
    if (id.isEmpty) return;

    final isLast = _currentIndex == _students.length - 1;

    setState(() {
      _skipped.add(id);
      _notPhotographed.add(id);
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
      if (isLast) {
        _currentIndex = _students.length;
      } else {
        _currentIndex++;
      }
    });

    _persistSession();

    if (isLast && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تجاهل آخر طالب. يمكنك مراجعة التقرير.'),
        ),
      );
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://emis.moedu.gov.iq/api/student/uploadimage'),
    );
    request.headers['Authorization'] = widget.token;
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path, filename: 'avatar.png'));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      debugPrint('Image upload failed ${response.statusCode}: $body');
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return decoded['imageUrl']?.toString();
    } catch (_) {}
    return null;
  }

  /// The list returned by getstudents is a lightweight DTO intended for
  /// listing/filtering. EMIS updatestudent expects the complete student DTO
  /// returned by getstudent/{id}. Sending the lightweight list record causes
  /// HTTP 400. Always refresh the complete record immediately before saving.
  Future<Map<String, dynamic>> _fetchFullStudent(String id) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api/student/getstudent/$id'),
      headers: {
        'Authorization': widget.token,
        'Accept': 'application/json',
      },
    );

    final body = utf8.decode(response.bodyBytes);
    debugPrint('Get full student $id: ${response.statusCode}');

    if (response.statusCode != 200) {
      debugPrint('Get full student response: $body');
      throw Exception('تعذر جلب بيانات الطالب الكاملة (${response.statusCode})');
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(decoded);
    }

    throw Exception('استجابة بيانات الطالب غير صالحة');
  }

  Future<bool> _saveCurrentStudent() async {
    if (_students.isEmpty || _currentIndex >= _students.length || _currentImage == null) return false;
    final listedStudent = _students[_currentIndex];
    final id = _studentId(listedStudent);
    if (id.isEmpty) return false;

    setState(() => _saving = true);
    try {
      // IMPORTANT: getstudents returns a lightweight listing object. Do not
      // send it to updatestudent. Fetch the exact full EMIS record first.
      final fullStudent = await _fetchFullStudent(id);

      final imageUrl = await _uploadImage(_currentImage!);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('تعذر رفع الصورة إلى EMIS');
      }

      // Change only imageUrl in the complete server record. All other fields
      // remain exactly as EMIS returned them.
      fullStudent['imageUrl'] = imageUrl;

      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api/student/updatestudent'),
        headers: {
          'Authorization': widget.token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(fullStudent),
      );

      final responseBody = utf8.decode(response.bodyBytes);
      debugPrint('Update student $id: ${response.statusCode}');
      debugPrint('Update student response: $responseBody');

      if (response.statusCode != 200 && response.statusCode != 204) {
        String details = responseBody.trim();
        if (details.length > 500) details = details.substring(0, 500);
        throw Exception(
          details.isEmpty
              ? 'فشل حفظ بيانات الطالب (${response.statusCode})'
              : 'فشل حفظ بيانات الطالب (${response.statusCode}): $details',
        );
      }

      // Update local/list data only after EMIS confirms the save.
      listedStudent['imageUrl'] = imageUrl;
      final originalIndex = widget.allStudents.indexWhere(
        (s) => s is Map && s['id']?.toString() == id,
      );
      if (originalIndex >= 0 && widget.allStudents[originalIndex] is Map) {
        widget.allStudents[originalIndex]['imageUrl'] = imageUrl;
      }

      _photographed.add(id);
      _notPhotographed.remove(id);
      await _persistSession();
      return true;
    } catch (e) {
      debugPrint('Batch save error: $e');
      _notPhotographed.add(id);
      await _persistSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ الطالب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _nextStudent() async {
    if (_currentImage == null || _saving || _processing) return;
    final saved = await _saveCurrentStudent();
    if (!saved || !mounted) return;

    final isLast = _currentIndex == _students.length - 1;
    setState(() {
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
      _currentIndex = isLast ? _students.length : _currentIndex + 1;
    });
  }

  Future<void> _restart() async {
    if (_students.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بدء جلسة جديدة'),
        content: const Text('سيتم مسح سجل هذه الشعبة من الجهاز والبدء من أول طالب. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('بدء من جديد')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _clearPersistedCurrentSession();
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _photographed.clear();
      _notPhotographed.clear();
      _skipped.clear();
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
    });
  }

  void _resume() {
    setState(() {
      _currentIndex = _firstPendingIndex(_students);
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
    });
  }

  @override
  void dispose() {
    _segmenter?.close();
    super.dispose();
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
        final selectedStudent = _students.isNotEmpty && _currentIndex < _students.length
            ? _students[_currentIndex]
            : null;
        final photographedCount = _photographed.length;
        final skippedCount = _skipped.length;
        final remaining = _students.length - photographedCount - skippedCount;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text(
              'إضافة صور الطلاب جماعيًا',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (_students.isNotEmpty)
                IconButton(
                  onPressed: _showReport,
                  tooltip: 'تقرير التصوير',
                  icon: const Icon(Icons.assessment_outlined),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // اختيار الصف والشعبة أصبح جزءًا من صفحة الأداة نفسها.
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedStage,
                          decoration: _inputDecoration('اختر الصف', isDark),
                          dropdownColor: card,
                          style: TextStyle(color: text),
                          items: _stages
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: _processing || _saving ? null : _selectStage,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedClassRoom,
                          decoration: _inputDecoration('اختر الشعبة', isDark),
                          dropdownColor: card,
                          style: TextStyle(color: text),
                          items: _classRooms
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: _selectedStage == null || _processing || _saving
                              ? null
                              : _selectClassRoom,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_restoringSession)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_students.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _counter('المجموع', '${_students.length}', Colors.indigo)),
                          Expanded(child: _counter('تم التصوير', '$photographedCount', Colors.green)),
                          Expanded(child: _counter('متبقٍ', '$remaining', Colors.orange)),
                          Expanded(child: _counter('متجاهل', '$skippedCount', Colors.redAccent)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: selectedStudent == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _students.isEmpty
                                  ? 'اختر الصف والشعبة لبدء تصوير الطلاب'
                                  : 'اكتملت معالجة الطلاب المحددين. يمكنك مراجعة التقرير.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: text, fontSize: 16),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(15, 0, 15, 24),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: card,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'الطالب ${_currentIndex + 1} من ${_students.length}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _studentName(selectedStudent),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: text,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    height: 300,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.black26 : const Color(0xFFF1F3F6),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: _processing
                                        ? Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CircularProgressIndicator(),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'جاري إزالة الخلفية محليًا...',
                                                  style: TextStyle(color: text),
                                                ),
                                              ],
                                            ),
                                          )
                                        : _currentImage == null
                                            ? const Center(
                                                child: Icon(
                                                  Icons.person_outline,
                                                  size: 100,
                                                  color: Colors.grey,
                                                ),
                                              )
                                            : ClipRRect(
                                                borderRadius: BorderRadius.circular(18),
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onDoubleTap: _showImagePreview,
                                                  child: InteractiveViewer(
                                                    minScale: 1.0,
                                                    maxScale: 4.0,
                                                    panEnabled: true,
                                                    scaleEnabled: true,
                                                    boundaryMargin: const EdgeInsets.all(40),
                                                    child: Image.file(
                                                      _currentImage!,
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _processing || _saving ? null : _takePhoto,
                                          icon: const Icon(Icons.camera_alt, color: Colors.white),
                                          label: Text(
                                            _currentImage == null ? 'الكاميرا' : 'إعادة التصوير',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueAccent,
                                            minimumSize: const Size.fromHeight(52),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _processing || _saving ? null : _pickFromGallery,
                                          icon: const Icon(Icons.photo_library_outlined),
                                          label: const Text(
                                            'من الجهاز',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(52),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: ElevatedButton.icon(
                                      onPressed: _currentImage == null ||
                                              _processing ||
                                              _saving ||
                                              _backgroundRemovedForCurrentImage
                                          ? null
                                          : _removeBackgroundFromCurrentImage,
                                      icon: const Icon(
                                        Icons.auto_fix_high_rounded,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        _backgroundRemovedForCurrentImage
                                            ? 'تمت إزالة الخلفية'
                                            : 'إزالة الخلفية',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF7B61FF),
                                        disabledBackgroundColor: isDark
                                            ? Colors.white12
                                            : Colors.grey.shade300,
                                        disabledForegroundColor: Colors.grey,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _processing || _saving ? null : _skipCurrentStudent,
                                    icon: const Icon(
                                      Icons.skip_next_rounded,
                                      color: Colors.deepOrange,
                                    ),
                                    label: const Text(
                                      'تجاهل الطالب (غائب)',
                                      style: TextStyle(
                                        color: Colors.deepOrange,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      side: const BorderSide(color: Colors.deepOrange),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  if (_currentImage != null) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        onPressed: _saving || _processing ? null : _nextStudent,
                                        icon: _saving
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Colors.white,
                                              ),
                                        label: Text(
                                          _saving
                                              ? 'جاري الحفظ...'
                                              : (_currentIndex == _students.length - 1
                                                  ? 'حفظ الطالب وإنهاء'
                                                  : 'حفظ الطالب والانتقال للتالي'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: photographedCount == 0 && skippedCount == 0
                                        ? null
                                        : _resume,
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('استكمال'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: photographedCount == 0 && skippedCount == 0
                                        ? null
                                        : _restart,
                                    icon: const Icon(Icons.restart_alt),
                                    label: const Text('إعادة من جديد'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, bool isDark) => InputDecoration(labelText: label, filled: true, fillColor: isDark ? Colors.black12 : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));

  Widget _counter(String title, String value, Color color) => Column(children: [Text(value, style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 3), Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12))]);

  Future<void> _showReport() async {
    final photographed = _students
        .where((s) => _photographed.contains(_studentId(s)))
        .toList();
    final skipped = _students
        .where((s) => _skipped.contains(_studentId(s)))
        .toList();
    final notPhotographed = _students
        .where(
          (s) => !_photographed.contains(_studentId(s)) &&
              !_skipped.contains(_studentId(s)),
        )
        .toList();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تقرير التصوير'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم تصويرهم: ${photographed.length}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...photographed.map((s) => Text('✓ ${_studentName(s)}')),
                const Divider(height: 25),
                Text(
                  'تم تجاهلهم: ${skipped.length}',
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...skipped.map((s) => Text('⏭ ${_studentName(s)}')),
                const Divider(height: 25),
                Text(
                  'لم يتم تصويرهم: ${notPhotographed.length}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...notPhotographed.map((s) => Text('• ${_studentName(s)}')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

}
