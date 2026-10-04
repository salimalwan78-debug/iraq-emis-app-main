import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_core.dart';

class BatchTeacherPhotosScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final List<dynamic> allTeachers;

  const BatchTeacherPhotosScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.allTeachers,
  });

  @override
  State<BatchTeacherPhotosScreen> createState() => _BatchTeacherPhotosScreenState();
}

class _BatchTeacherPhotosScreenState extends State<BatchTeacherPhotosScreen> {
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  int _currentIndex = 0;
  final Set<String> _photographed = <String>{};
  final Set<String> _skipped = <String>{};
  final Set<String> _notPhotographed = <String>{};
  File? _currentImage;
  bool _saving = false;
  bool _restoringSession = false;
  bool _processing = false;
  bool _backgroundRemovedForCurrentImage = false;
  SelfieSegmenter? _segmenter;

  String _teacherId(Map<String, dynamic> teacher) =>
      teacher['id']?.toString() ?? '';

  String _teacherName(Map<String, dynamic> teacher) {
    final direct = teacher['employeeFullName'] ?? teacher['fullName'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    final parts = [
      teacher['name'],
      teacher['fatherName'],
      teacher['grandFatherName'],
      teacher['surName'],
    ]
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'بدون اسم' : parts.join(' ');
  }

  String get _sessionKey =>
      'batch_teacher_photo_session_${widget.schoolId}';

  @override
  void initState() {
    super.initState();
    _teachers = widget.allTeachers
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => _teacherId(e).isNotEmpty)
        .toList();
    _restoreSession();
  }

  Future<void> _initializeSegmenter() async {
    _segmenter ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: false,
    );
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

    final inputFile = File(
      '${imageFile.path}_teacher_seg_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
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
          final index = y * source.width + x;
          final confidence = mask.confidences[index].clamp(0.0, 1.0);
          final alpha = ((confidence - 0.35) / 0.40 * 255.0).round().clamp(0, 255);
          final pixel = source.getPixel(x, y);
          result.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
        }
      }
      final output = File(
        '${imageFile.path}_teacher_nobg_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await output.writeAsBytes(img.encodePng(result, level: 6), flush: true);
      return output;
    } finally {
      try {
        if (await inputFile.exists()) await inputFile.delete();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _segmenter?.close();
    super.dispose();
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sessionKey,
        jsonEncode({
          'photographed': _photographed.toList(),
          'skipped': _skipped.toList(),
          'notPhotographed': _notPhotographed.toList(),
          'currentIndex': _currentIndex,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Persist teacher batch session error: $e');
    }
  }

  Future<void> _restoreSession() async {
    _restoringSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        final validIds = _teachers.map(_teacherId).toSet();
        if (data is Map) {
          _photographed.addAll(
            (data['photographed'] as List? ?? const [])
                .map((e) => '$e')
                .where(validIds.contains),
          );
          _skipped.addAll(
            (data['skipped'] as List? ?? const [])
                .map((e) => '$e')
                .where(validIds.contains),
          );
          _notPhotographed.addAll(
            (data['notPhotographed'] as List? ?? const [])
                .map((e) => '$e')
                .where(validIds.contains),
          );
          _notPhotographed.addAll(_skipped);
        }
      }
      _currentIndex = _firstPendingIndex();
    } catch (e) {
      debugPrint('Restore teacher batch session error: $e');
      _currentIndex = _firstPendingIndex();
    } finally {
      _restoringSession = false;
      if (mounted) setState(() {});
    }
  }

  int _firstPendingIndex() {
    for (var i = 0; i < _teachers.length; i++) {
      final id = _teacherId(_teachers[i]);
      if (!_photographed.contains(id) && !_skipped.contains(id)) return i;
    }
    return _teachers.length;
  }

  Map<String, dynamic>? get _currentTeacher =>
      _teachers.isNotEmpty && _currentIndex < _teachers.length
          ? _teachers[_currentIndex]
          : null;

  Future<void> _pickImage(ImageSource source) async {
    if (_currentTeacher == null || _saving) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2500,
        maxHeight: 2500,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _currentImage = File(picked.path);
        _backgroundRemovedForCurrentImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر اختيار صورة المعلم: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeBackgroundFromCurrentImage() async {
    final image = _currentImage;
    if (image == null || _processing || _saving || _backgroundRemovedForCurrentImage) return;
    setState(() => _processing = true);
    try {
      final processed = await _removeBackground(image);
      if (!mounted) return;
      setState(() {
        _currentImage = processed;
        _backgroundRemovedForCurrentImage = true;
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إزالة الخلفية من صورة المعلم')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إزالة الخلفية: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showPreview() async {
    final image = _currentImage;
    if (image == null) return;
    File currentImage = image;
    bool processing = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('معاينة صورة المعلم', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 280,
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    boundaryMargin: const EdgeInsets.all(30),
                    child: Image.file(currentImage, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('قرّب الصورة وحركها لمراجعتها قبل الحفظ', style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: processing || _backgroundRemovedForCurrentImage
                      ? null
                      : () async {
                          setDialogState(() => processing = true);
                          try {
                            final processed = await _removeBackground(currentImage);
                            if (!mounted) return;
                            currentImage = processed;
                            _backgroundRemovedForCurrentImage = true;
                            setDialogState(() => processing = false);
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => processing = false);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إزالة الخلفية: $e'), backgroundColor: Colors.red));
                          }
                        },
                  icon: processing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
                  label: Text(processing ? 'جاري إزالة الخلفية...' : 'إزالة الخلفية'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: processing ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: processing
                  ? null
                  : () {
                      setState(() => _currentImage = currentImage);
                      Navigator.pop(dialogContext);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('اعتماد', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }


  Future<Map<String, dynamic>> _fetchFullTeacher(String id) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api/employee/getemployee/$id'),
      headers: {'Authorization': widget.token, 'Accept': 'application/json'},
    );
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw Exception('تعذر جلب بيانات المعلم الكاملة (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(decoded);
    }
    throw Exception('استجابة بيانات المعلم غير صالحة');
  }

  Future<String?> _uploadImage(File imageFile) async {
    // EMIS uses the same image storage endpoint used by the student photo
    // workflow. The returned imageUrl is then attached to the employee DTO.
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://emis.moedu.gov.iq/api/student/uploadimage'),
    );
    request.headers['Authorization'] = widget.token;
    request.headers['Accept'] = 'application/json';
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
        filename: imageFile.path.toLowerCase().endsWith('.png')
            ? 'teacher.png'
            : 'teacher.jpg',
      ),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('فشل رفع الصورة (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['imageUrl'] != null) {
      return decoded['imageUrl'].toString();
    }
    throw Exception('لم يرجع خادم EMIS رابط الصورة');
  }

  Map<String, dynamic> _buildEmployeePayload(
    Map<String, dynamic> old,
    String imageUrl,
  ) {
    final identification = old['identification'] is Map
        ? Map<String, dynamic>.from(old['identification'])
        : <String, dynamic>{};
    final address = old['address'] is Map
        ? Map<String, dynamic>.from(old['address'])
        : <String, dynamic>{};
    final employment = old['employmentRecord'] is Map
        ? Map<String, dynamic>.from(old['employmentRecord'])
        : <String, dynamic>{};

    final positions = employment['employmentPositions'];
    final currentPosition = old['currentEmploymentPosition'] ??
        (positions is List &&
                positions.isNotEmpty &&
                positions.first is Map
            ? positions.first['position']
            : null);

    final status = old['status'];
    final statusString = status == null ? '' : '$status'.trim();
    final positionString = currentPosition == null
        ? ''
        : '$currentPosition'.trim();

    return <String, dynamic>{
      // This is intentionally the same payload shape used by the working
      // Edit Teacher screen. Do not send the raw getemployee DTO here.
      'Id': old['id'],
      'EmployeeIdNumber': old['employeeIdNumber'] ?? '',
      'FamilyNumber': _nullable(old['familyNumber']),
      'IsTeacher': old['isTeacher'] ?? true,
      'EmploymentType': old['employmentType'] ?? '',
      'EmployeeCategory': old['employeeCategory'] ?? '',
      'Classification': old['classification'] ?? '',
      'JobDesignation': _nullable(old['jobDesignation']),
      'EmploymentGrade': _nullable(old['employmentGrade']),
      'DateOfStartWorking': _dateOnlyOrNull(old['dateOfStartWorking']),
      'EducationLevel': _nullable(old['educationLevel']),
      'GraduationYear': _dateOnlyOrNull(old['graduationYear']),
      'UniversityName': _nullable(old['universityName']),
      'Specialization': _nullable(old['specialization']),
      'Name': old['name'] ?? '',
      'FatherName': old['fatherName'] ?? '',
      'GrandFatherName': old['grandFatherName'] ?? '',
      'FathersGrandFatherName': old['fathersGrandFatherName'] ?? '',
      'SurName': old['surName'] ?? '',
      'MotherName': old['motherName'] ?? '',
      'MothersFatherName': old['mothersFatherName'] ?? '',
      'MothersGrandFatherName': old['mothersGrandFatherName'] ?? '',
      'ImageUrl': imageUrl,
      'DateOfBirth': _dateOnlyOrNull(old['dateOfBirth']),
      'Gender': _intOrNull(old['gender']),
      'Nationality': old['nationality'] ?? '',
      'CountryOfBirth': old['countryOfBirth'] ?? '',
      'HomeTown': old['homeTown'] ?? '',
      'IdentificationId': old['identificationId'] ?? 0,
      'Identification': {
        'IdNumber': identification['idNumber'] ?? '',
        'IssuingCountry': identification['issuingCountry'] ?? '',
        'IdType': _intOrNull(identification['idType']),
        'issuingDate': identification['issuingDate'],
      },
      'FatherIdentificationId': old['fatherIdentificationId'],
      'FatherIdentification': old['fatherIdentification'] is Map
          ? old['fatherIdentification']
          : {
              'IdNumber': '',
              'IssuingCountry': 'العراق',
              'IdType': 0,
              'issuingDate': null,
            },
      'MotherTongue': old['motherTongue'] ?? '',
      'MaritalStatus': old['maritalStatus'] ?? '',
      'BloodGroup': old['bloodGroup'] ?? '',
      'Religion': old['religion'] ?? '',
      'HomePhoneNumber': _nullable(old['homePhoneNumber']),
      'Status': _intOrNull(old['status']),
      'Notes': old['notes'] ?? '',
      'SpecialNeedsInformation': _nullable(old['specialNeedsInformation']),
      'EmergencyContactName': _nullable(old['emergencyContactName']),
      'EmergencyContactRelationship':
          _nullable(old['emergencyContactRelationship']),
      'EmergencyContactPhoneNumber':
          _nullable(old['emergencyContactPhoneNumber']),
      'Address': {
        'AddressType': 1,
        'Town': address['town'] ?? '',
        'Area': address['area'] ?? '',
        'Quarter': address['quarter'] ?? '',
        'Street': address['street'] ?? '',
        'ClosestLocation': address['closestLocation'] ?? '',
        'countryStructureId': address['countryStructureId'],
        'Latitude': '${address['latitude'] ?? 0}',
        'Longitude': '${address['longitude'] ?? 0}',
        'ApartmentNumber': address['apartmentNumber'] ?? '',
        'BuildingNumber': address['buildingNumber'] ?? '',
        'Address1': address['address1'] ?? '',
        'Address2': address['address2'] ?? '',
        'SchoolPhoneNumber': address['schoolPhoneNumber'] ?? '',
        'MobilePhoneNumber': address['mobilePhoneNumber'] ?? '',
        'Email': address['email'] ?? '',
        'Fax': address['fax'] ?? '',
        'Website': address['website'] ?? '',
      },
      'AgeExceptionReason': old['ageExceptionReason'],
      'AgeExceptionAttachmentUrl': old['ageExceptionAttachmentUrl'],
      'ageExceptionAttachment': null,
      'EmploymentRecord': {
        'EmploymentStatuses': [
          {
            // EMIS updateemployee expects this to be a JSON string.
            'StatusType': statusString,
            'DisEngagementDate': null,
            'MinistryOfficialDocumentNumber': null,
            'Reason': null,
            'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
          }
        ],
        'EmploymentPositions': [
          {
            'Position': positionString,
            'InitiateDate': _dateOnlyOrNull(old['dateOfStartWorking']) ?? '',
          }
        ],
        'IsCurrentlyActive': true,
        'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
        'CurrentEmploymentPosition': positionString,
      },
    };
  }

  dynamic _nullable(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : value;
  }

  String? _dateOnlyOrNull(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    if (s.isEmpty) return null;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value'.trim());
  }

  Future<bool> _saveCurrentTeacher() async {
    final teacher = _currentTeacher;
    final image = _currentImage;
    if (teacher == null || image == null || _saving) return false;
    final id = _teacherId(teacher);
    if (id.isEmpty) return false;

    setState(() => _saving = true);
    try {
      // The raw getemployee response must NOT be sent directly to
      // updateemployee. The Edit Teacher screen that is already working
      // sends the normalized PascalCase DTO below. Batch saving follows
      // exactly the same API contract.
      final fullTeacher = await _fetchFullTeacher(id);
      final imageUrl = await _uploadImage(image);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('تعذر رفع صورة المعلم');
      }

      final payload = _buildEmployeePayload(fullTeacher, imageUrl);

      debugPrint('Batch update employee $id: normalized payload');
      debugPrint('Payload has Id: ${payload.containsKey('Id')}');
      debugPrint('Payload has EmploymentRecord: ${payload.containsKey('EmploymentRecord')}');

      final response = await http.put(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/updateemployee'),
        headers: {
          'Authorization': widget.token,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      final body = utf8.decode(response.bodyBytes);
      debugPrint('Batch update employee response ${response.statusCode}: $body');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        var details = body.trim();
        if (details.length > 1200) details = details.substring(0, 1200);
        throw Exception(
          details.isEmpty
              ? 'فشل حفظ بيانات المعلم (${response.statusCode})'
              : 'فشل حفظ بيانات المعلم (${response.statusCode}): $details',
        );
      }

      teacher['imageUrl'] = imageUrl;
      final originalIndex = widget.allTeachers.indexWhere(
        (e) => e is Map && e['id']?.toString() == id,
      );
      if (originalIndex >= 0 && widget.allTeachers[originalIndex] is Map) {
        widget.allTeachers[originalIndex]['imageUrl'] = imageUrl;
      }

      _photographed.add(id);
      _skipped.remove(id);
      _notPhotographed.remove(id);
      await _persistSession();
      return true;
    } catch (e) {
      _notPhotographed.add(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل حفظ صورة المعلم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      await _persistSession();
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _nextTeacher() async {
    if (_currentTeacher == null || _currentImage == null || _saving) return;
    final saved = await _saveCurrentTeacher();
    if (!saved || !mounted) return;
    final last = _currentIndex == _teachers.length - 1;
    setState(() {
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
      _currentIndex = last ? _teachers.length : _currentIndex + 1;
    });
  }

  Future<void> _skipCurrentTeacher() async {
    final teacher = _currentTeacher;
    if (teacher == null || _saving) return;
    final id = _teacherId(teacher);
    if (id.isEmpty) return;
    final last = _currentIndex == _teachers.length - 1;
    setState(() {
      _skipped.add(id);
      _notPhotographed.add(id);
      _currentImage = null;
      _backgroundRemovedForCurrentImage = false;
      _currentIndex = last ? _teachers.length : _currentIndex + 1;
    });
    await _persistSession();
  }

  Future<void> _restart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بدء جلسة جديدة'),
        content: const Text('سيتم مسح سجل تصوير المعلمين من الجهاز والبدء من أول معلم. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('بدء من جديد')),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    if (!mounted) return;
    setState(() {
      _photographed.clear();
      _skipped.clear();
      _notPhotographed.clear();
      _currentIndex = 0;
      _currentImage = null;
    });
  }

  Future<void> _showReport() async {
    final photographed = _teachers.where((t) => _photographed.contains(_teacherId(t))).toList();
    final skipped = _teachers.where((t) => _skipped.contains(_teacherId(t))).toList();
    final pending = _teachers.where((t) {
      final id = _teacherId(t);
      return !_photographed.contains(id) && !_skipped.contains(id);
    }).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تقرير جلسة تصوير المعلمين'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _reportRow('تم التصوير', photographed.length, Colors.green),
                _reportRow('متجاهل', skipped.length, Colors.orange),
                _reportRow('لم يُصوّر بعد', pending.length, Colors.red),
                const Divider(),
                if (skipped.isNotEmpty) ...[
                  const Text('المتجاهلون', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...skipped.map((t) => ListTile(dense: true, title: Text(_teacherName(t)))),
                ],
                if (pending.isNotEmpty) ...[
                  const Text('المتبقون', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...pending.map((t) => ListTile(dense: true, title: Text(_teacherName(t)))),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
      ),
    );
  }

  Widget _reportRow(String title, int count, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold))),
      title: Text(title),
    );
  }

  Widget _counter(String title, String value, Color color, Color card, Color text) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(title, style: TextStyle(fontSize: 11, color: text)),
      ],
    );
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
        final teacher = _currentTeacher;
        final photographedCount = _photographed.length;
        final skippedCount = _skipped.length;
        final remaining = _teachers.length - photographedCount - skippedCount;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: const Text('إضافة صور المعلمين جماعيًا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF4527A0), Color(0xFF7E57C2)]))),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(onPressed: _showReport, tooltip: 'تقرير', icon: const Icon(Icons.assessment_outlined)),
              IconButton(onPressed: _restart, tooltip: 'جلسة جديدة', icon: const Icon(Icons.restart_alt)),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_restoringSession) const LinearProgressIndicator(minHeight: 3),
                if (_teachers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        children: [
                          Expanded(child: _counter('المجموع', '${_teachers.length}', Colors.deepPurple, card, text)),
                          Expanded(child: _counter('تم التصوير', '$photographedCount', Colors.green, card, text)),
                          Expanded(child: _counter('متبقٍ', '$remaining', Colors.orange, card, text)),
                          Expanded(child: _counter('متجاهل', '$skippedCount', Colors.redAccent, card, text)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: teacher == null
                      ? Center(child: Text(_teachers.isEmpty ? 'لا توجد بيانات للمعلمين' : 'اكتملت جلسة التصوير', style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.bold)))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(15, 8, 15, 20),
                          children: [
                            Card(
                              color: card,
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text(_teacherName(teacher), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text), textAlign: TextAlign.center),
                                    const SizedBox(height: 5),
                                    Text('المعلم ${_currentIndex + 1} من ${_teachers.length}', style: const TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 15),
                                    Container(
                                      height: 310,
                                      width: double.infinity,
                                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(18)),
                                      child: _currentImage == null
                                          ? const Icon(Icons.person, size: 110, color: Colors.grey)
                                          : ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(_currentImage!, fit: BoxFit.contain)),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('من الجهاز'))),
                                        const SizedBox(width: 8),
                                        Expanded(child: ElevatedButton.icon(onPressed: _saving ? null : () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt, color: Colors.white), label: const Text('التقاط الصورة', style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (_currentImage != null) ...[
                                      OutlinedButton.icon(onPressed: _saving ? null : _showPreview, icon: const Icon(Icons.zoom_in), label: const Text('Preview / معاينة الصورة')),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: _saving || _processing || _backgroundRemovedForCurrentImage ? null : _removeBackgroundFromCurrentImage,
                                          icon: _processing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_fix_high, color: Colors.white),
                                          label: Text(_processing ? 'جاري إزالة الخلفية...' : (_backgroundRemovedForCurrentImage ? 'تمت إزالة الخلفية' : 'إزالة الخلفية'), style: const TextStyle(color: Colors.white)),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: OutlinedButton.icon(
                                        onPressed: _saving ? null : _skipCurrentTeacher,
                                        icon: const Icon(Icons.skip_next),
                                        label: const Text('تجاهل المعلم (غائب)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange, side: const BorderSide(color: Colors.deepOrange, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton.icon(
                                        onPressed: _currentImage == null || _saving ? null : _nextTeacher,
                                        icon: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_back, color: Colors.white),
                                        label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ المعلم والانتقال للالتالي', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
}
