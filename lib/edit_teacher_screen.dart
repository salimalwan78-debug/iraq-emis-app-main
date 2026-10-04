import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EditTeacherScreen extends StatefulWidget {
  final String token;
  final String schoolId;
  final String teacherId;

  const EditTeacherScreen({
    super.key,
    required this.token,
    required this.schoolId,
    required this.teacherId,
  });

  @override
  State<EditTeacherScreen> createState() => _EditTeacherScreenState();
}

class _EditTeacherScreenState extends State<EditTeacherScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _employee;
  File? _pickedImage;
  bool _removeExistingPhoto = false;
  SelfieSegmenter? _selfieSegmenter;

  final Map<String, TextEditingController> _c = {};
  final Map<String, List<Map<String, dynamic>>> _options = {};

  static const _commonOptionEndpoints = <String, String>{
    'countryOfBirth': '/selectoption/بلد الولادة',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'gender': '/selectoption/Gender',
    'nationality': '/selectoption/بلد الولادة',
    'motherTongue': '/selectoption/لغة',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'jobDesignation': '/SelectOption/نوع الوظيفة',
  };

  static const _labels = <String, String>{
    'name': 'الإسم',
    'fatherName': 'إسم الأب',
    'grandFatherName': 'اسم والد الأب',
    'fathersGrandFatherName': 'اسم جد الأب',
    'surName': 'اللقب',
    'motherName': 'إسم الأم',
    'mothersFatherName': 'اسم والد الأم',
    'mothersGrandFatherName': 'اسم جد الأم',
    'dateOfBirth': 'تاريخ التولّد',
    'countryOfBirth': 'محل الولادة',
    'idType': 'نوع الهوية',
    'issuingCountry': 'بلد الإصدار',
    'nationalId': 'رقم البطاقة الوطنية الموحدة',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'gender': 'الجنس',
    'nationality': 'الجنسية',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة',
    'notes': 'ملاحظات',
    'employmentType': 'نوع التوظيف',
    'employeeCategory': 'نوع الموظف',
    'status': 'الحالة الوظيفية',
    'jobDesignation': 'المسمى الوظيفي',
    'employmentGrade': 'الدرجة الوظيفية',
    'classification': 'التصنيف',
    'currentPosition': 'المنصب الحالي',
    'dateOfStartWorking': 'تاريخ اول تعيين للموظف',
    'educationLevel': 'التحصيل الدراسي',
    'universityName': 'إسم الكلية / المعهد',
    'graduationYear': 'سنة التخرج',
    'specialization': 'الإختصاص',
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة إن وجدت',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال في الحالات الطارئة',
    'town': 'المدينة/القرية',
    'area': 'الحي',
    'quarter': 'المحلة',
    'street': 'زقاق',
    'address1': 'عنوان 1',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة',
    'email': 'البريد الإلكتروني',
    'mobilePhoneNumber': 'رقم هاتف المعلم',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _selfieSegmenter?.close();
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<void> _load() async {
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/getemployee/${widget.teacherId}'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final employee = decoded is Map && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'])
          : Map<String, dynamic>.from(decoded as Map);

      _employee = employee;
      _initControllers(employee);
      await Future.wait([
        for (final key in _commonOptionEndpoints.keys) _loadOption(key),
        _loadCountryStructure(),
      ]);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل بيانات المعلم: $e';
      });
    }
  }

  void _initControllers(Map<String, dynamic> e) {
    final identification = e['identification'] is Map ? Map<String, dynamic>.from(e['identification']) : <String, dynamic>{};
    final address = e['address'] is Map ? Map<String, dynamic>.from(e['address']) : <String, dynamic>{};
    final employment = e['employmentRecord'] is Map ? Map<String, dynamic>.from(e['employmentRecord']) : <String, dynamic>{};
    final positions = employment['employmentPositions'];
    final currentPosition = e['currentEmploymentPosition'] ??
        (positions is List && positions.isNotEmpty && positions.first is Map ? positions.first['position'] : null);

    final values = <String, dynamic>{
      'name': e['name'],
      'fatherName': e['fatherName'],
      'grandFatherName': e['grandFatherName'],
      'fathersGrandFatherName': e['fathersGrandFatherName'],
      'surName': e['surName'],
      'motherName': e['motherName'],
      'mothersFatherName': e['mothersFatherName'],
      'mothersGrandFatherName': e['mothersGrandFatherName'],
      'dateOfBirth': _dateOnly(e['dateOfBirth']),
      'countryOfBirth': e['countryOfBirth'],
      'idType': identification['idType'],
      'issuingCountry': identification['issuingCountry'],
      'nationalId': identification['idNumber'],
      'employeeIdNumber': e['employeeIdNumber'],
      'familyNumber': e['familyNumber'],
      'gender': e['gender'],
      'nationality': e['nationality'],
      'homeTown': e['homeTown'],
      'motherTongue': e['motherTongue'],
      'maritalStatus': e['maritalStatus'],
      'bloodGroup': e['bloodGroup'],
      'religion': e['religion'],
      'notes': e['notes'],
      'employmentType': e['employmentType'],
      'employeeCategory': e['employeeCategory'],
      'status': e['status'],
      'jobDesignation': e['jobDesignation'],
      'employmentGrade': e['employmentGrade'],
      'classification': e['classification'],
      'currentPosition': currentPosition,
      'dateOfStartWorking': _dateOnly(e['dateOfStartWorking']),
      'educationLevel': e['educationLevel'],
      'universityName': e['universityName'],
      'graduationYear': _dateOnly(e['graduationYear']),
      'specialization': e['specialization'],
      'specialNeedsInformation': e['specialNeedsInformation'],
      'emergencyContactName': e['emergencyContactName'],
      'emergencyContactRelationship': e['emergencyContactRelationship'],
      'emergencyContactPhoneNumber': e['emergencyContactPhoneNumber'],
      'town': address['town'],
      'area': address['area'],
      'quarter': address['quarter'],
      'street': address['street'],
      'address1': address['address1'],
      'address2': address['address2'],
      'closestLocation': address['closestLocation'],
      'email': address['email'],
      'mobilePhoneNumber': address['mobilePhoneNumber'],
    };

    for (final entry in values.entries) {
      _c[entry.key] = TextEditingController(text: entry.value == null ? '' : '${entry.value}');
    }
  }

  String _dateOnly(dynamic value) {
    if (value == null) return '';
    final s = '$value';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _loadOption(String key) async {
    final endpoint = _commonOptionEndpoints[key];
    if (endpoint == null) return;
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final raw = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['results']) : decoded;
      if (raw is List) {
        _options[key] = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
  }

  Future<void> _loadCountryStructure() async {
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/CountryStructure/getcountrystructure'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final raw = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['results']) : decoded;
      if (raw is List) {
        _options['countryStructure'] = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
  }

  List<String> _stringOptions(String key, {List<String> fallback = const []}) {
    final result = <String>[];
    for (final item in _options[key] ?? const <Map<String, dynamic>>[]) {
      final value = item['value'] ?? item['displayName'] ?? item['name'];
      if (value != null && '$value'.trim().isNotEmpty) result.add('$value');
    }
    for (final item in fallback) {
      if (!result.contains(item)) result.add(item);
    }
    final current = _c[key]?.text.trim() ?? '';
    if (current.isNotEmpty && !result.contains(current)) result.insert(0, current);
    return result;
  }

  String? _selected(String key) => _c[key]?.text.trim().isEmpty == true ? null : _c[key]?.text.trim();

  Widget _textField(String key, {bool required = false, int maxLines = 1, TextInputType? keyboardType, bool readOnly = false}) {
    final controller = _c[key]!;
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: _labels[key],
        labelStyle: const TextStyle(fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.03) : Colors.white,
      ),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null : null,
      onTap: readOnly && (key == 'dateOfBirth' || key == 'dateOfStartWorking' || key == 'graduationYear')
          ? () => _pickDate(key)
          : null,
    );
  }

  Widget _selectField(String key, {bool required = false, List<String> fallback = const []}) {
    final values = _stringOptions(key, fallback: fallback);
    return DropdownButtonFormField<String>(
      value: _selected(key),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _labels[key],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.03) : Colors.white,
      ),
      items: values.map((v) => DropdownMenuItem<String>(value: v, child: Text(v, textDirection: TextDirection.rtl, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (value) => setState(() => _c[key]!.text = value ?? ''),
      validator: required ? (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null : null,
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 14),
          ..._grid(children),
        ],
      ),
    );
  }

  List<Widget> _grid(List<Widget> children) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i += 2) {
      result.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: children[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ],
      ));
      result.add(const SizedBox(height: 12));
    }
    return result;
  }

  Future<void> _initializeSelfieSegmenter() async {
    _selfieSegmenter ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: false,
    );
  }

  Future<File?> _removeBackgroundUsingSelfieSegmentation(File imageFile) async {
    File? normalizedFile;
    try {
      await _initializeSelfieSegmenter();
      final segmenter = _selfieSegmenter;
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

      normalizedFile = File(
        '${imageFile.path}_teacher_seg_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await normalizedFile.writeAsBytes(
        img.encodeJpg(source, quality: 90),
        flush: true,
      );

      final mask = await segmenter.processImage(
        InputImage.fromFilePath(normalizedFile.path),
      );
      if (mask == null || mask.width <= 0 || mask.height <= 0 || mask.confidences.isEmpty) {
        throw Exception('لم يتم الحصول على قناع صالح للشخص');
      }
      if (mask.width != source.width || mask.height != source.height) {
        throw Exception('أبعاد قناع إزالة الخلفية غير متطابقة');
      }

      final result = img.Image(
        width: source.width,
        height: source.height,
        numChannels: 4,
      );
      final pixelCount = source.width * source.height;
      if (mask.confidences.length < pixelCount) {
        throw Exception('بيانات القناع غير مكتملة');
      }

      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final index = y * source.width + x;
          final confidence = mask.confidences[index].clamp(0.0, 1.0);
          final alpha = ((confidence - 0.35) / 0.40 * 255.0)
              .round()
              .clamp(0, 255);
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
      if (normalizedFile != null) {
        try {
          if (await normalizedFile.exists()) await normalizedFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _showImagePreviewDialog(File imageFile) async {
    File currentImage = imageFile;
    bool processing = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'معاينة صورة المعلم',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 280,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: InteractiveViewer(
                        panEnabled: true,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.all(30),
                        minScale: 0.5,
                        maxScale: 5,
                        child: Image.file(currentImage, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'يمكنك تقريب الصورة وتحريكها لمراجعتها قبل اعتمادها',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: processing
                          ? null
                          : () async {
                              setDialogState(() => processing = true);
                              try {
                                final processed = await _removeBackgroundUsingSelfieSegmentation(currentImage);
                                if (!mounted) return;
                                if (processed == null) throw Exception('لم يتم الحصول على الصورة المعالجة');
                                setDialogState(() {
                                  currentImage = processed;
                                  processing = false;
                                });
                              } catch (e) {
                                if (!mounted) return;
                                setDialogState(() => processing = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('تعذر إزالة الخلفية: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      icon: processing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_fix_high),
                      label: Text(processing ? 'جاري إزالة الخلفية...' : 'إزالة الخلفية'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: processing ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: processing
                      ? null
                      : () {
                          setState(() {
                            _pickedImage = currentImage;
                            _removeExistingPhoto = false;
                          });
                          Navigator.pop(dialogContext);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('اعتماد', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2500,
        maxHeight: 2500,
      );
      if (picked == null || !mounted) return;
      await _showImagePreviewDialog(File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار صورة المعلم: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _deleteCurrentPhoto() {
    setState(() {
      _pickedImage = null;
      _removeExistingPhoto = true;
    });
  }

  Future<String?> _uploadImageToEmisServer(File imageFile) async {
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
        filename: imageFile.path.toLowerCase().endsWith('.png') ? 'teacher.png' : 'teacher.jpg',
      ),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('فشل رفع صورة المعلم (${response.statusCode})${body.isEmpty ? '' : ': $body'}');
    }
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['imageUrl'] != null) {
      return decoded['imageUrl'].toString();
    }
    throw Exception('لم يرجع خادم EMIS رابط الصورة');
  }

  Future<void> _pickDate(String key) async {
    final initial = DateTime.tryParse(_c[key]!.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: _labels[key],
      locale: const Locale('ar'),
    );
    if (picked != null) {
      _c[key]!.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employee == null) return;
    setState(() => _saving = true);

    try {
      final old = _employee!;
      final nationalId = _c['nationalId']!.text.trim();
      if (nationalId.isNotEmpty) {
        final check = await http.get(
          Uri.parse('https://emis.moedu.gov.iq/api/employee/checknationalidnumber?value=${Uri.encodeQueryComponent(nationalId)}&excludeId=${Uri.encodeQueryComponent(widget.teacherId)}'),
          headers: {'Authorization': widget.token, 'Accept': 'application/json'},
        );
        if (check.statusCode == 200) {
          final result = jsonDecode(utf8.decode(check.bodyBytes));
          if (result is Map && result['isUnique'] == false) {
            throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً');
          }
        }
      }
      final identification = old['identification'] is Map ? Map<String, dynamic>.from(old['identification']) : <String, dynamic>{};
      final oldAddress = old['address'] is Map ? Map<String, dynamic>.from(old['address']) : <String, dynamic>{};
      final oldEmployment = old['employmentRecord'] is Map ? Map<String, dynamic>.from(old['employmentRecord']) : <String, dynamic>{};

      String imageUrl = old['imageUrl']?.toString() ?? '';
      if (_pickedImage != null) {
        final uploaded = await _uploadImageToEmisServer(_pickedImage!);
        if (uploaded == null || uploaded.isEmpty) {
          throw Exception('تعذر رفع صورة المعلم');
        }
        imageUrl = uploaded;
      } else if (_removeExistingPhoto) {
        imageUrl = '';
      }

      final payload = <String, dynamic>{
        'Id': old['id'],
        'EmployeeIdNumber': _c['employeeIdNumber']!.text.trim(),
        'FamilyNumber': _nullable(_c['familyNumber']!.text),
        'IsTeacher': true,
        'EmploymentType': _c['employmentType']!.text.trim(),
        'EmployeeCategory': _c['employeeCategory']!.text.trim(),
        'Classification': _c['classification']!.text.trim(),
        'JobDesignation': _nullable(_c['jobDesignation']!.text),
        'EmploymentGrade': _nullable(_c['employmentGrade']!.text),
        'DateOfStartWorking': _nullable(_c['dateOfStartWorking']!.text),
        'EducationLevel': _nullable(_c['educationLevel']!.text),
        'GraduationYear': _nullable(_c['graduationYear']!.text),
        'UniversityName': _nullable(_c['universityName']!.text),
        'Specialization': _nullable(_c['specialization']!.text),
        'Name': _c['name']!.text.trim(),
        'FatherName': _c['fatherName']!.text.trim(),
        'GrandFatherName': _c['grandFatherName']!.text.trim(),
        'FathersGrandFatherName': _c['fathersGrandFatherName']!.text.trim(),
        'SurName': _c['surName']!.text.trim(),
        'MotherName': _c['motherName']!.text.trim(),
        'MothersFatherName': _c['mothersFatherName']!.text.trim(),
        'MothersGrandFatherName': _c['mothersGrandFatherName']!.text.trim(),
        'ImageUrl': imageUrl,
        'DateOfBirth': _nullable(_c['dateOfBirth']!.text),
        'Gender': _intOrNull(_c['gender']!.text),
        'Nationality': _c['nationality']!.text.trim(),
        'CountryOfBirth': _c['countryOfBirth']!.text.trim(),
        'HomeTown': _c['homeTown']!.text.trim(),
        'IdentificationId': 0,
        'Identification': {
          'IdNumber': nationalId,
          'IssuingCountry': _c['issuingCountry']!.text.trim(),
          'IdType': _intOrNull(_c['idType']!.text),
          'issuingDate': identification['issuingDate'],
        },
        'FatherIdentificationId': old['fatherIdentificationId'],
        'FatherIdentification': {
          'IdNumber': '',
          'IssuingCountry': 'العراق',
          'IdType': 0,
          'issuingDate': null,
        },
        'MotherTongue': _c['motherTongue']!.text.trim(),
        'MaritalStatus': _c['maritalStatus']!.text.trim(),
        'BloodGroup': _c['bloodGroup']!.text.trim(),
        'Religion': _c['religion']!.text.trim(),
        'HomePhoneNumber': _nullable(old['homePhoneNumber']),
        'Status': _intOrNull(_c['status']!.text),
        'Notes': _c['notes']!.text,
        'SpecialNeedsInformation': _nullable(_c['specialNeedsInformation']!.text),
        'EmergencyContactName': _nullable(_c['emergencyContactName']!.text),
        'EmergencyContactRelationship': _nullable(_c['emergencyContactRelationship']!.text),
        'EmergencyContactPhoneNumber': _nullable(_c['emergencyContactPhoneNumber']!.text),
        'Address': {
          'AddressType': 1,
          'Town': _c['town']!.text.trim(),
          'Area': _c['area']!.text.trim(),
          'Quarter': _c['quarter']!.text.trim(),
          'Street': _c['street']!.text.trim(),
          'ClosestLocation': _c['closestLocation']!.text.trim(),
          'countryStructureId': oldAddress['countryStructureId'],
          'Latitude': '${oldAddress['latitude'] ?? 0}',
          'Longitude': '${oldAddress['longitude'] ?? 0}',
          'ApartmentNumber': oldAddress['apartmentNumber'] ?? '',
          'BuildingNumber': oldAddress['buildingNumber'] ?? '',
          'Address1': _c['address1']!.text.trim(),
          'Address2': _c['address2']!.text.trim(),
          'SchoolPhoneNumber': oldAddress['schoolPhoneNumber'] ?? '',
          'MobilePhoneNumber': _c['mobilePhoneNumber']!.text.trim(),
          'Email': _c['email']!.text.trim(),
          'Fax': oldAddress['fax'] ?? '',
          'Website': oldAddress['website'] ?? '',
        },
        'AgeExceptionReason': old['ageExceptionReason'],
        'AgeExceptionAttachmentUrl': old['ageExceptionAttachmentUrl'],
        'ageExceptionAttachment': null,
        'EmploymentRecord': _buildEmploymentRecord(oldEmployment),
      };

      final response = await http.put(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/updateemployee'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(response.bodyBytes);
        throw Exception('HTTP ${response.statusCode}${body.isEmpty ? '' : ': $body'}');
      }

      if (!mounted) return;
      old['imageUrl'] = imageUrl;
      _pickedImage = null;
      _removeExistingPhoto = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث المعلم بنجاح')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحديث المعلم: $e'), backgroundColor: Colors.red));
    }
  }

  Map<String, dynamic> _buildEmploymentRecord(Map<String, dynamic> old) {
    final statuses = old['employmentStatuses'];
    final positions = old['employmentPositions'];
    final currentStatus = _c['status']!.text.trim();
    final currentPosition = _c['currentPosition']!.text.trim();

    return {
      'EmploymentStatuses': [
        {
          'StatusType': currentStatus,
          'DisEngagementDate': null,
          'MinistryOfficialDocumentNumber': null,
          'Reason': null,
          'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
        }
      ],
      'EmploymentPositions': [
        {
          'Position': currentPosition,
          'InitiateDate': _c['dateOfStartWorking']!.text.trim(),
        }
      ],
      'IsCurrentlyActive': true,
      'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
      'CurrentEmploymentPosition': currentPosition,
    };
  }

  dynamic _nullable(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : s;
  }

  int? _intOrNull(String value) => int.tryParse(value.trim());

  Widget _buildTeacherImageCard() {
    String imageUrl = _employee?['imageUrl']?.toString() ?? '';
    if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
      imageUrl = 'https://emis.moedu.gov.iq$imageUrl';
    }
    final hasImage = _pickedImage != null || (!_removeExistingPhoto && imageUrl.isNotEmpty);

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'الصورة الشخصية للمعلم',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.deepPurple, width: 3),
                  ),
                  child: ClipOval(
                    child: _pickedImage != null
                        ? Image.file(_pickedImage!, fit: BoxFit.cover)
                        : hasImage
                            ? Image.network(
                                imageUrl,
                                headers: {'Authorization': widget.token},
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 80, color: Colors.grey),
                              )
                            : const Icon(Icons.person, size: 80, color: Colors.grey),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: IconButton(
                      tooltip: 'الكاميرا',
                      onPressed: _saving ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, color: Colors.white, size: 19),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('من الجهاز'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasImage && !_saving
                        ? () {
                            final file = _pickedImage;
                            if (file != null) {
                              _showImagePreviewDialog(file);
                            } else if (imageUrl.isNotEmpty) {
                              showDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.black,
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 5,
                                    child: Image.network(
                                      imageUrl,
                                      headers: {'Authorization': widget.token},
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.zoom_in),
                    label: const Text('Preview'),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: hasImage && !_saving ? _deleteCurrentPhoto : null,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('إزالة الصورة الحالية', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل بيانات المعلم', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF4527A0),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        _buildTeacherImageCard(),
                        const SizedBox(height: 14),
                        _section('الاسم الكامل', [
                          _textField('name', required: true),
                          _textField('fatherName', required: true),
                          _textField('grandFatherName', required: true),
                          _textField('fathersGrandFatherName', required: true),
                          _textField('surName', required: true),
                          _textField('motherName'),
                          _textField('mothersFatherName'),
                          _textField('mothersGrandFatherName'),
                        ]),
                        _section('البيانات الشخصية', [
                          _textField('dateOfBirth', required: true, readOnly: true),
                          _selectField('countryOfBirth', required: true),
                          _selectField('gender', required: true),
                          _selectField('nationality', required: true),
                          _textField('homeTown'),
                          _selectField('motherTongue'),
                          _selectField('maritalStatus'),
                          _selectField('bloodGroup'),
                          _selectField('religion'),
                          _textField('notes', maxLines: 3),
                        ]),
                        _section('وثيقة التعريف', [
                          _selectField('idType', required: true),
                          _selectField('issuingCountry', required: true),
                          _textField('nationalId', required: true, keyboardType: TextInputType.number),
                          _textField('employeeIdNumber', keyboardType: TextInputType.number),
                          _textField('familyNumber', keyboardType: TextInputType.number),
                        ]),
                        _section('البيانات الوظيفية', [
                          _selectField('employmentType', required: true, fallback: const ['ملاك', 'عقد']),
                          _selectField('employeeCategory', required: true, fallback: const ['تدريسي']),
                          _selectField('status', required: true, fallback: const ['مستمر']),
                          _selectField('classification', required: true, fallback: const ['معلم']),
                          _selectField('jobDesignation'),
                          _textField('employmentGrade'),
                          _selectField('currentPosition', fallback: const ['مدرس', 'مدرس اول', 'مدرس ثاني', 'مدرس ثالث', 'مدرس اقدم']),
                          _textField('dateOfStartWorking', required: true, readOnly: true),
                        ]),
                        _section('التحصيل الدراسي', [
                          _selectField('educationLevel', fallback: const ['ابتدائية', 'متوسطة', 'إعدادية', 'دبلوم', 'بكالوريوس', 'دبلوم عالي', 'ماجستير', 'دكتوراه']),
                          _textField('universityName'),
                          _textField('graduationYear', readOnly: true),
                          _textField('specialization'),
                        ]),
                        _section('ذوو الاحتياجات الخاصة والاتصال الطارئ', [
                          _textField('specialNeedsInformation'),
                          _textField('emergencyContactName'),
                          _textField('emergencyContactRelationship'),
                          _textField('emergencyContactPhoneNumber', keyboardType: TextInputType.phone),
                        ]),
                        _section('العنوان ومعلومات الاتصال', [
                          _textField('town'),
                          _textField('area'),
                          _textField('quarter'),
                          _textField('street'),
                          _textField('address1'),
                          _textField('address2'),
                          _textField('closestLocation'),
                          _textField('email', keyboardType: TextInputType.emailAddress),
                          _textField('mobilePhoneNumber', keyboardType: TextInputType.phone),
                        ]),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                            label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ بيانات المعلم'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }
}
