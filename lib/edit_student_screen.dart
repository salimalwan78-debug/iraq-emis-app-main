import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'emis_live_sync.dart';

import 'app_core.dart';
import 'google_speech_service.dart';
import 'package:permission_handler/permission_handler.dart';

class EditStudentScreen extends StatefulWidget {
  final String token;
  final String studentId;

  const EditStudentScreen({
    super.key,
    required this.token,
    required this.studentId,
  });

  @override
  State<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _studentData;
  File? _pickedImage;
  StreamSubscription<Map<String, dynamic>>? _speechSubscription;
  int _speechSessionCounter = 0;
  int? _activeSpeechSession;
  Map<String, dynamic>? _activeSpeechOwner;
  String? _activeSpeechKey;
  bool _speechListening = false;
  String? _speechError;
  final Map<String, TextEditingController> _dateControllers = {};
  final Set<String> _speechEnabledFields = {'name','fatherName','grandFatherName','fathersGrandFatherName','surName','motherName','mothersFatherName','mothersGrandFatherName','homeTown','notes','issuer','nameOfDocument','town','area','quarter','street','address1','address2','closestLocation','homePhoneNumber','censusNumber','dateOfBirth','idNumber','jinsiyaIdNumber','recordNumber','pageNumber','birthCertificateNumber','otherIdNumber'};

  final Map<String, List<Map<String, dynamic>>> _options = {};
  final Set<String> _loadingOptions = <String>{};

  List<Map<String, dynamic>> _addressCountries = [];
  List<Map<String, dynamic>> _addressGovernorates = [];
  List<Map<String, dynamic>> _addressDistricts = [];
  String? _addressCountryId;
  String? _addressGovernorateId;
  String? _addressDistrictId;

  static const Map<String, String> _optionEndpoints = {
    'countryOfBirth': '/selectoption/بلد الولادة',
    'nationality': '/selectoption/بلد الولادة',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'gender': '/selectoption/Gender',
    'motherTongue': '/selectoption/لغة',
    'studyLanguage': '/selectoption/لغة',
    'maritalStatus': '/selectoption/الحالة الاجتماعية',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'specialNeeds': '/selectoption/ذوي الإحتياجات الخاصة',
    'economicLevel': '/selectoption/حالة الاقتصادية',
    'academicYearId': '/selectoption/getActiveAcademicYear',
  };

  final Map<String, String> _officialArabicNames = {
    'name': 'الإسم', 'fatherName': 'إسم الأب',
    'grandFatherName': 'اسم والد الأب',
    'fathersGrandFatherName': 'اسم جد الأب', 'surName': 'اللقب',
    'motherName': 'إسم الأم', 'mothersFatherName': 'اسم والد الأم',
    'mothersGrandFatherName': 'اسم جد الأم',
    'dateOfBirth': 'تاريخ التولّد', 'gender': 'الجنس',
    'nationality': 'الجنسية', 'countryOfBirth': 'محل الولادة',
    'homeTown': 'مسقط الرأس', 'motherTongue': 'اللغة الأم',
    'maritalStatus': 'الحالة الاجتماعية', 'bloodGroup': 'فئة الدم',
    'religion': 'الديانة', 'homePhoneNumber': 'رقم الهاتف',
    'notes': 'ملاحظات', 'censusNumber': 'رقم الإحصاء',
    'identification': 'وثيقة التعريف', 'idNumber': 'رقم الهوية',
    'issuingCountry': 'بلد الإصدار', 'idType': 'نوع الهوية',
    'jinsiyaIdNumber': 'رقم شهادة الجنسية', 'issuer': 'جهة الإصدار',
    'recordNumber': 'رقم السجل', 'pageNumber': 'رقم الصحيفة',
    'issuingDate': 'تاريخ الإصدار', 'nameOfDocument': 'نوع الوثيقة',
    'birthCertificateNumber': 'رقم شهادة الولادة',
    'otherIdNumber': 'رقم الهوية الأخرى',
    'fatherIdentification': 'هوية الأب',
    'motherIdentification': 'هوية الأم', 'specialNeeds': 'الاحتياجات الخاصة، إن وجدت',
    'studyLanguage': 'لغة الدراسة', 'economicLevel': 'المستوى المعيشي',
    'isCoveredBySocialWelfare': 'مشمول بمنحة الرعاية الاجتماعية؟',
    'isDroppedOutFromSchool': 'متسرّب من المدرسة؟',
    'lastYearResult': 'نتيجة العام الدراسي السابق',
    'lastAcademicYearId': 'العام الدراسي السابق',
    'lastCompletedStageId': 'المرحلة الدراسية السابقة',
    'lastSchoolId': 'المدرسة السابقة', 'academicYearId': 'العام الدراسي',
    'stageId': 'الصف الدراسي', 'schoolId': 'المدرسة',
    'classRoomId': 'الشعبة', 'studentStatus': 'حالة الطالب',
    'studentStatusName': 'حالة الطالب', 'address': 'العنوان',
    'addressType': 'نوع العنوان', 'countryStructureId': 'الموقع الجغرافي',
    'town': 'المدينة/القرية', 'area': 'الحي', 'quarter': 'المحلة',
    'street': 'زقاق', 'apartmentNumber': 'رقم الشقة',
    'buildingNumber': 'رقم البناية', 'address1': 'عنوان 1',
    'address2': 'عنوان 2', 'closestLocation': 'أقرب نقطة دالة',
    'schoolPhoneNumber': 'رقم هاتف مدير المدرسة',
    'mobilePhoneNumber': 'رقم هاتف المعلم',
    'employeePhoneNumber': 'رقم هاتف الموظف', 'email': 'البريد الإلكتروني',
    'website': 'الموقع الإلكتروني', 'latitude': 'خط العرض',
    'longitude': 'خط الطول', 'imageUrl': 'الصورة',
    'ageExceptionReason': 'سبب استثناء العمر',
    'genderExceptionReason': 'سبب استثناء الجنس',
    'classificationName': 'التصنيف', 'classification': 'التصنيف',
    'schoolName': 'المدرسة', 'stageName': 'الصف الدراسي',
    'classRoomName': 'الشعبة', 'academicYearName': 'العام الدراسي',
  };

  @override
  void initState() {
    super.initState();
    _speechSubscription = GoogleSpeechService.events.listen(_onSpeechEvent);
    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _fetchStudentData();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in _officialArabicNames.entries)
          entry.key: <String>[entry.key, entry.value],
      };

  Map<String, String> _liveValues() {
    final result = <String, String>{};
    final data = _studentData;
    if (data == null) return result;
    final identification = data['identification'] is Map ? Map<String, dynamic>.from(data['identification']) : <String, dynamic>{};
    final address = data['address'] is Map ? Map<String, dynamic>.from(data['address']) : <String, dynamic>{};
    for (final key in _officialArabicNames.keys) {
      dynamic value;
      if (data.containsKey(key)) value = data[key];
      else if (identification.containsKey(key)) value = identification[key];
      else if (address.containsKey(key)) value = address[key];
      if (value is List) value = value.isEmpty ? '' : value.first;
      if (value is bool) value = value ? 'true' : 'false';
      if (value != null) result[key] = '$value';
    }
    return result;
  }

  void _pushLive() => _liveSyncKey.currentState?.pushValues(_liveValues());

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  dynamic _liveCoerce(dynamic old, String value) {
    if (old is bool) return value.toLowerCase() == 'true' || value == '1';
    if (old is int) return int.tryParse(value) ?? old;
    if (old is double) return double.tryParse(value) ?? old;
    if (old is List) return value.isEmpty ? <String>[] : <String>[value];
    return value;
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    final data = _studentData;
    if (data == null) return;
    final identification = data['identification'] is Map ? Map<String, dynamic>.from(data['identification']) : <String, dynamic>{};
    final address = data['address'] is Map ? Map<String, dynamic>.from(data['address']) : <String, dynamic>{};
    bool changed = false;
    for (final entry in values.entries) {
      final key = entry.key;
      if (data.containsKey(key)) {
        final next = _liveCoerce(data[key], entry.value);
        if ('${data[key]}' != '$next') { data[key] = next; changed = true; }
      } else if (identification.containsKey(key)) {
        final next = _liveCoerce(identification[key], entry.value);
        if ('${identification[key]}' != '$next') { identification[key] = next; changed = true; }
      } else if (address.containsKey(key)) {
        final next = _liveCoerce(address[key], entry.value);
        if ('${address[key]}' != '$next') { address[key] = next; changed = true; }
      }
    }
    if (changed) {
      data['identification'] = identification;
      data['address'] = address;
      if (mounted) setState(() {});
    }
  }

  Map<String, dynamic> _unwrap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return decoded;
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('استجابة بيانات الطالب غير صالحة');
  }

  Future<void> _fetchStudentData() async {
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/student/getstudent/${widget.studentId}'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final student = _unwrap(jsonDecode(utf8.decode(response.bodyBytes)));

      for (final key in _optionEndpoints.keys) {
        await _loadOptions(key);
      }
      await _loadStageOptions(student['schoolId']?.toString());
      await _loadClassroomOptions(
        student['schoolId']?.toString(),
        student['stageId']?.toString(),
      );
      _studentData = student;
      await _loadCountryStructure();
      if (student['identification'] is Map) {
        final identification = Map<String, dynamic>.from(student['identification']);
        identification['idType'] ??= 12;
        student['identification'] = identification;
      }

      if (!mounted) return;
      setState(() {
        _studentData = student;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في جلب بيانات الطالب: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _getOptions(String path) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api$path'),
      headers: {'Authorization': widget.token, 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    dynamic value = decoded;
    if (value is Map) value = value['data'] ?? value['items'] ?? value['results'] ?? value;
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadOptions(String key) async {
    if (_options.containsKey(key) || _loadingOptions.contains(key)) return;
    final endpoint = _optionEndpoints[key];
    if (endpoint == null) return;
    _loadingOptions.add(key);
    try {
      final list = await _getOptions(endpoint);
      if (list.isNotEmpty) _options[key] = list;
    } catch (e) {
      debugPrint('تعذر تحميل خيارات $key: $e');
    } finally {
      _loadingOptions.remove(key);
    }
  }

  Future<void> _loadStageOptions(String? schoolId) async {
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      final list = await _getOptions('/selectoption/getAvailableStagesForStudent?schoolId=$schoolId');
      if (list.isNotEmpty) _options['stageId'] = list;
    } catch (e) { debugPrint('تعذر تحميل الصفوف: $e'); }
  }

  Future<void> _loadClassroomOptions(String? schoolId, String? stageId) async {
    if (schoolId == null || stageId == null || schoolId.isEmpty || stageId.isEmpty) return;
    try {
      final list = await _getOptions('/selectoption/getClassRooms?schoolId=$schoolId&stageId=$stageId');
      _options['classRoomId'] = list;
    } catch (e) { debugPrint('تعذر تحميل الشعب: $e'); }
  }

  Future<void> _loadStageDetails(String? stageId) async {
    if (stageId == null || stageId.isEmpty) return;
    try {
      final list = await _getOptions('/selectoption/getstagedetails/$stageId');
      if (list.isNotEmpty) _options['stageDetails'] = list;
    } catch (e) { debugPrint('تعذر تحميل تفاصيل الصف: $e'); }
  }

  Future<void> _loadCountryStructure() async {
    try {
      final list = await _getOptions('/CountryStructure/getcountrystructure');
      if (list.isEmpty) return;
      _addressCountries = list;

      final address = _studentData?['address'] is Map
          ? Map<String, dynamic>.from(_studentData!['address'])
          : <String, dynamic>{};
      final stored = address['countryStructureId']?.toString();

      Map<String, dynamic>? iraq;
      for (final item in _addressCountries) {
        final text = _optionText(item);
        if (text.contains('العراق') || text.toLowerCase() == 'iraq') {
          iraq = item;
          break;
        }
      }
      iraq ??= _addressCountries.first;
      _addressCountryId = _optionValue(iraq)?.toString();
      _addressGovernorates = _childrenOf(iraq);

      Map<String, dynamic>? selectedNode;
      void walk(Map<String, dynamic> node, String? countryId, String? governorateId) {
        final id = _optionValue(node)?.toString();
        if (stored != null && id == stored) {
          selectedNode = node;
          _addressCountryId = countryId ?? id;
          _addressGovernorateId = governorateId;
        }
        for (final child in _childrenOf(node)) {
          walk(child, countryId ?? id, governorateId ?? id);
        }
      }
      for (final country in _addressCountries) {
        walk(country, _optionValue(country)?.toString(), null);
      }

      if (selectedNode != null) {
        final selectedId = _optionValue(selectedNode!)?.toString();
        for (final country in _addressCountries) {
          for (final gov in _childrenOf(country)) {
            final districts = _childrenOf(gov);
            if (districts.any((d) => _optionValue(d)?.toString() == selectedId)) {
              _addressCountryId = _optionValue(country)?.toString();
              _addressGovernorateId = _optionValue(gov)?.toString();
              _addressDistrictId = selectedId;
              _addressGovernorates = _childrenOf(country);
              _addressDistricts = districts;
            }
          }
        }
      }
      if (_addressGovernorateId == null && _addressGovernorates.isNotEmpty) {
        _addressGovernorateId = null;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('تعذر تحميل هيكل العناوين: $e');
    }
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
    final raw = node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _onSpeechEvent(Map<String, dynamic> event) {
    if (!mounted || event['sessionId'] != _activeSpeechSession) return;
    final type = event['type']?.toString();
    if (type == 'partial' || type == 'result') {
      final raw = (event['text'] ?? event['result'] ?? event['transcript'] ?? '').toString();
      if (raw.isEmpty || _activeSpeechOwner == null || _activeSpeechKey == null) return;

      final key = _activeSpeechKey!;
      if (_isDateField(key)) {
        final normalized = _normalizeRecognizedDate(raw);
        if (normalized == null) return;
        final controller = _dateControllers[key];
        if (controller != null) {
          controller.value = TextEditingValue(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
        setState(() {
          _activeSpeechOwner![key] = normalized;
          _speechError = null;
        });
      } else {
        final recognizedText = <String>{'homePhoneNumber', 'idNumber'}
                .contains(key)
            ? _normalizeDigits(raw).replaceAll(RegExp(r'[^0-9]'), '')
            : raw;
        setState(() {
          _activeSpeechOwner![key] = recognizedText;
          _speechError = null;
        });
      }
    } else if (type == 'error') {
      setState(() { _speechError = (event['message'] ?? 'تعذر التعرف على الكلام').toString(); _speechListening = false; });
      _activeSpeechSession = null;
    } else if (type == 'stopped' || type == 'end') {
      setState(() => _speechListening = false);
      _activeSpeechSession = null;
    } else if (type == 'listening' || type == 'begin') {
      setState(() { _speechListening = true; _speechError = null; });
    }
  }

  Future<void> _toggleFieldMic(Map<String, dynamic> owner, String key) async {
    if (!AppCore.voiceInputEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الميكروفون مغلق من الإعدادات.')));
      return;
    }
    if (_activeSpeechSession != null) {
      await GoogleSpeechService.stopListening();
      setState(() => _speechListening = false);
      _activeSpeechSession = null;
      if (_activeSpeechKey == key) return;
    }
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى السماح للتطبيق باستخدام الميكروفون.')));
      return;
    }
    try {
      final info = await GoogleSpeechService.getInfo();
      if (info['available'] == false) throw Exception('خدمة التعرف الصوتي غير متاحة على الجهاز.');
      final id = ++_speechSessionCounter;
      _activeSpeechSession = id;
      _activeSpeechOwner = owner;
      _activeSpeechKey = key;
      final started = await GoogleSpeechService.startListening(sessionId: id, locale: 'ar-IQ');
      if (!started) {
        _activeSpeechSession = null;
        throw Exception('تعذر بدء الاستماع.');
      }
      if (mounted) setState(() { _speechListening = true; _speechError = null; });
    } catch (e) {
      if (mounted) {
        setState(() { _speechListening = false; _speechError = e.toString(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل الميكروفون: $e')));
      }
    }
  }

  String _normalizeDigits(String value) {
    const arabicIndic = '٠١٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final ch in value.runes) {
      final c = String.fromCharCode(ch);
      final a = arabicIndic.indexOf(c);
      if (a >= 0) { out.write(a); continue; }
      final e = easternArabicIndic.indexOf(c);
      if (e >= 0) { out.write(e); continue; }
      out.write(c);
    }
    return out.toString();
  }

  DateTime? _parseSpokenDate(String raw, String key) {
    final normalizedDigits = _normalizeDigits(raw);
    final digitGroups = RegExp(r'\d+').allMatches(normalizedDigits)
        .map((m) => int.tryParse(m.group(0)!)).whereType<int>().toList();
    int? day, month, year;
    if (digitGroups.length >= 3) {
      if (digitGroups[0] >= 1900) {
        year = digitGroups[0]; month = digitGroups[1]; day = digitGroups[2];
      } else {
        day = digitGroups[0]; month = digitGroups[1]; year = digitGroups[2];
      }
    } else {
      return null;
    }
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += year >= 50 ? 1900 : 2000;
    if (year < 1900 || year > DateTime.now().year || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    if (key == 'dateOfBirth' && date.isAfter(DateTime.now())) return null;
    return date;
  }

  String? _normalizeRecognizedDate(String raw) {
    final spokenDate = _parseSpokenDate(raw, 'dateOfBirth');
    if (spokenDate != null) {
      return '${spokenDate.year.toString().padLeft(4, '0')}-'
          '${spokenDate.month.toString().padLeft(2, '0')}-'
          '${spokenDate.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  String _formatDateValue(String value) {
    final v = value.trim();
    final iso = RegExp(r'^(\d{4})[-/]?(\d{2})[-/]?(\d{2})$').firstMatch(v);
    if (iso != null) return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    return v.replaceAll('/', '-');
  }

  String _formatTypedDate(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    var out = limited.substring(0, limited.length >= 4 ? 4 : limited.length);
    if (limited.length > 4) out += '-${limited.substring(4, limited.length >= 6 ? 6 : limited.length)}';
    if (limited.length > 6) out += '-${limited.substring(6)}';
    return out;
  }

  String _label(String key) => _officialArabicNames[key] ?? key;

  bool _isDateField(String key) => <String>{
    'dateOfBirth', 'issuingDate', 'effectiveDate', 'startDate', 'endDate',
  }.contains(key);

  bool _isRequired(String key, [Map<String, dynamic>? parent]) => false;

  dynamic _optionValue(Map<String, dynamic> option) => option['value'] ?? option['id'];
  String _optionText(Map<String, dynamic> option) => (option['displayName'] ?? option['name'] ?? option['label'] ?? option['text'] ?? _optionValue(option)?.toString() ?? '').toString();

  bool _sameValue(dynamic a, dynamic b) => a?.toString() == b?.toString();

  Widget _dropdownField({
    required String key,
    required Map<String, dynamic> owner,
    required bool isDark,
    required Color textColor,
  }) {
    final items = _options[key] ?? const <Map<String, dynamic>>[];
    final value = owner[key];
    Map<String, dynamic>? selected;
    for (final item in items) {
      if (_sameValue(_optionValue(item), value)) { selected = item; break; }
    }
    final safeValue = selected == null ? null : _optionValue(selected);
    final requiredField = _isRequired(key, owner);

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<dynamic>(
        value: safeValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: requiredField ? '${_label(key)} *' : _label(key),
          labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        style: TextStyle(color: isDark ? Colors.white : textColor, fontSize: 16, fontWeight: FontWeight.bold),
        items: items.map((item) => DropdownMenuItem<dynamic>(
          value: _optionValue(item), child: Text(_optionText(item), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor)),
        )).toList(),
        validator: null,
        onTap: () => _focusLive(key),
        onChanged: (newValue) async {
          setState(() {
            owner[key] = newValue;
            if (key == 'stageId') owner['classRoomId'] = null;
          });
          if (key == 'stageId') {
            await _loadStageDetails(newValue?.toString());
            await _loadClassroomOptions(_studentData?['schoolId']?.toString(), newValue?.toString());
            if (mounted) setState(() {});
          }
        },
      ),
    );
  }

  Future<void> _pickDate(Map<String, dynamic> owner, String key) async {
    DateTime initial = DateTime.now();
    final raw = owner[key]?.toString();
    if (raw != null && raw.isNotEmpty) initial = DateTime.tryParse(raw) ?? initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null && mounted) {
      final formatted = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _dateControllers.putIfAbsent(key, () => TextEditingController()).value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      setState(() => owner[key] = formatted);
    }
  }

  Widget _fieldFor(String key, dynamic value, Map<String, dynamic> owner, bool isDark, Color textColor) {
    if (_hiddenStudentResponseFields.contains(key) ||
        _hiddenAddressResponseFields.contains(key)) {
      return const SizedBox.shrink();
    }

    if (_optionEndpoints.containsKey(key) || key == 'stageId' || key == 'classRoomId') {
      return _dropdownField(key: key, owner: owner, isDark: isDark, textColor: textColor);
    }

    if (_isDateField(key)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextFormField(
          key: ValueKey('date-$key'),
          controller: _dateControllers.putIfAbsent(
            key,
            () => TextEditingController(text: _formatDateValue(value?.toString() ?? '')),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [TextInputFormatter.withFunction((oldValue, newValue) { final formatted = _formatTypedDate(newValue.text); return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length)); })],
          onChanged: (v) => owner[key] = v,
          onTap: () => _focusLive(key),
          style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: _isRequired(key, owner) ? '${_label(key)} *' : _label(key),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'الإدخال الصوتي', onPressed: () => _toggleFieldMic(owner, key), icon: Icon(_speechListening && _activeSpeechKey == key ? Icons.mic : Icons.mic_none, color: _speechListening && _activeSpeechKey == key ? Colors.red : null)),
              IconButton(tooltip: 'اختيار التاريخ', onPressed: () => _pickDate(owner, key), icon: const Icon(Icons.calendar_month)),
            ]),
            filled: true, fillColor: isDark ? Colors.black12 : Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(key), style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        value: value,
        onChanged: (v) => setState(() => owner[key] = v),
      );
    }

    if (value is List) {
      if (key == 'specialNeeds') {
        return Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: DropdownButtonFormField<String>(
            value: value.isNotEmpty && value.first.toString().isNotEmpty ? value.first.toString() : null,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : textColor, fontWeight: FontWeight.bold),
            decoration: InputDecoration(labelText: _label(key), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: (_options[key] ?? const []).map((o) => DropdownMenuItem<String>(value: _optionValue(o)?.toString(), child: Text(_optionText(o), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor)))).toList(),
            onChanged: (v) => setState(() => owner[key] = v == null ? <String>[] : <String>[v]),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return PlainTextField(
      label: _isRequired(key, owner) ? '${_label(key)} *' : _label(key),
      initialValue: value,
      isDark: isDark,
      textColor: textColor,
      textDirection: <String>{'homePhoneNumber', 'idNumber'}.contains(key)
          ? TextDirection.ltr
          : null,
      readOnly: false,
      requiredField: _isRequired(key, owner),
      onChanged: (v) => owner[key] = v,
      onMic: _speechEnabledFields.contains(key) ? () => _toggleFieldMic(owner, key) : null,
      micActive: _speechListening && _activeSpeechKey == key,
    );
  }

  static const Set<String> _visibleStudentFields = {
    'name', 'fatherName', 'grandFatherName', 'fathersGrandFatherName', 'surName', 'motherName', 'mothersFatherName', 'mothersGrandFatherName', 'dateOfBirth', 'gender', 'nationality', 'countryOfBirth', 'homeTown', 'motherTongue', 'maritalStatus', 'bloodGroup', 'religion', 'homePhoneNumber', 'notes', 'specialNeeds', 'studyLanguage', 'economicLevel', 'isCoveredBySocialWelfare', 'isDroppedOutFromSchool', 'academicYearId', 'stageId', 'classRoomId', 'identification', 'address', 'ageExceptionReason', 'genderExceptionReason',
  };

  static const Set<String> _visibleAddressFields = {
    'countryStructureId', 'town', 'area', 'quarter', 'street', 'address1', 'address2', 'closestLocation',
  };

  static const Set<String> _hiddenStudentResponseFields = {
    'id', 'createdAt', 'updatedAt', 'imageUrl', 'schoolId', 'schoolName', 'schoolCensusNumber', 'stageName', 'classRoomName', 'academicYearName', 'studentStatusName', 'studentStatus', 'classificationName', 'classification', 'classifications', 'lastSchoolClassifications', 'lastSchoolClassification', 'lastSchoolName', 'lastCompletedStageName', 'lastAcademicYearName', 'lastYearResult', 'lastAcademicYearId', 'lastCompletedStageId', 'lastSchoolId', 'censusNumber',
  };

  static const Set<String> _hiddenAddressResponseFields = {
    'apartmentNumber', 'buildingNumber', 'latitude', 'longitude', 'schoolPhoneNumber', 'mobilePhoneNumber', 'employeePhoneNumber', 'email', 'website',
  };

  bool _identityFieldVisible(String key, dynamic idType) {
    final t = int.tryParse(idType?.toString() ?? '');
    if (t == 3) return {'idNumber','jinsiyaIdNumber','issuer','recordNumber','pageNumber','issuingCountry','issuingDate','nameOfDocument'}.contains(key);
    if (t == 12) return {'idNumber'}.contains(key);
    if (t == 22) return {'birthCertificateNumber','issuer','issuingDate','issuingCountry','nameOfDocument'}.contains(key);
    if (t == 16) return {'otherIdNumber','nameOfDocument','issuer','issuingDate','issuingCountry'}.contains(key);
    return true;
  }

  Widget _addressDropdown(String label, String? value, List<Map<String, dynamic>> items, ValueChanged<String?> onChanged, bool isDark, Color textColor) {
    final safe = items.any((x) => _optionValue(x)?.toString() == value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        value: safe,
        isExpanded: true,
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
        ),
        items: items.map((item) => DropdownMenuItem<String>(
          value: _optionValue(item)?.toString(),
          child: Text(_optionText(item), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor)),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _studentSection(String title, List<Widget> children, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.indigo.shade400)),
            const SizedBox(height: 13),
            ..._studentGrid(children),
          ],
        ),
      ),
    );
  }

  List<Widget> _studentGrid(List<Widget> children) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length;) {
      final current = children[i];
      final isDate = current is TextFormField && current.key is ValueKey &&
          (current.key as ValueKey).value.toString().startsWith('date-');
      if (isDate) {
        rows.add(SizedBox(width: double.infinity, child: current));
        i++;
      } else {
        final next = i + 1 < children.length ? children[i + 1] : const SizedBox();
        final nextIsDate = next is TextFormField && next.key is ValueKey &&
            (next.key as ValueKey).value.toString().startsWith('date-');
        if (nextIsDate) {
          rows.add(SizedBox(width: double.infinity, child: current));
          i++;
        } else {
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: current), const SizedBox(width: 10), Expanded(child: next),
          ]));
          i += 2;
        }
      }
      if (i < children.length) rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  List<Widget> _buildStudentFormSections(bool isDark, Color textColor) {
    final student = _studentData!;
    final identification = student['identification'] is Map<String, dynamic>
        ? student['identification'] as Map<String, dynamic>
        : student['identification'] is Map
            ? Map<String, dynamic>.from(student['identification'] as Map)
            : <String, dynamic>{};
    final address = student['address'] is Map<String, dynamic>
        ? student['address'] as Map<String, dynamic>
        : student['address'] is Map
            ? Map<String, dynamic>.from(student['address'] as Map)
            : <String, dynamic>{};
    student['identification'] = identification;
    student['address'] = address;

    Widget field(String key, [Map<String, dynamic>? owner]) {
      final target = owner ?? student;
      if (!target.containsKey(key)) return const SizedBox.shrink();
      return _fieldFor(key, target[key], target, isDark, textColor);
    }

    final result = <Widget>[
      _studentSection('الاسم الكامل', [
        field('name'), field('fatherName'), field('grandFatherName'), field('fathersGrandFatherName'),
        field('surName'), field('motherName'), field('mothersFatherName'), field('mothersGrandFatherName'),
      ], isDark),
      _studentSection('البيانات الشخصية', [field('dateOfBirth')], isDark),
      _studentSection('الجنس', [field('gender')], isDark),
      _studentSection('البيانات الشخصية', [
        field('nationality'), field('countryOfBirth'), field('homeTown'), field('motherTongue'),
        field('maritalStatus'), field('bloodGroup'), field('religion'), field('homePhoneNumber'),
        field('notes'), field('specialNeeds'), field('studyLanguage'), field('economicLevel'),
        field('isCoveredBySocialWelfare'), field('isDroppedOutFromSchool'),
      ], isDark),
      _studentSection('وثيقة التعريف', [
        if (identification.isNotEmpty) ...[
          if (identification.containsKey('idType'))
            _dropdownField(key: 'idType', owner: identification, isDark: isDark, textColor: textColor),
          ...identification.entries
              .where((entry) => entry.key != 'idType' && _identityFieldVisible(entry.key, identification['idType']))
              .map((entry) => _fieldFor(entry.key, entry.value, identification, isDark, textColor)),
        ],
      ], isDark),
      _studentSection('البيانات الدراسية', [
        field('academicYearId'), field('stageId'), field('classRoomId'),
      ], isDark),
      _studentSection('العنوان', [
        _addressDropdown('الدولة', _addressCountryId, _addressCountries, (v) {
          final country = _addressCountries.where((x) => _optionValue(x)?.toString() == v).toList();
          if (country.isEmpty) return;
          setState(() {
            _addressCountryId = v;
            _addressGovernorates = _childrenOf(country.first);
            _addressGovernorateId = null;
            _addressDistricts = [];
            _addressDistrictId = null;
            address['countryStructureId'] = null;
          });
          _focusLive('countryStructureId');
        }, isDark, textColor),
        _addressDropdown('المحافظة', _addressGovernorateId, _addressGovernorates, (v) {
          final gov = _addressGovernorates.where((x) => _optionValue(x)?.toString() == v).toList();
          if (gov.isEmpty) return;
          setState(() {
            _addressGovernorateId = v;
            _addressDistricts = _childrenOf(gov.first);
            _addressDistrictId = null;
            address['countryStructureId'] = null;
          });
          _focusLive('countryStructureId');
        }, isDark, textColor),
        _addressDropdown('القضاء', _addressDistrictId, _addressDistricts, (v) {
          setState(() {
            _addressDistrictId = v;
            address['countryStructureId'] = v == null ? null : int.tryParse(v);
          });
          _focusLive('countryStructureId');
        }, isDark, textColor),
        field('town', address), field('area', address), field('quarter', address),
        field('street', address), field('address1', address), field('address2', address),
        field('closestLocation', address),
      ], isDark),
    ];
    return result;
  }

  SelfieSegmenter? _selfieSegmenter;

  Future<void> _initializeSelfieSegmenter() async {
    _selfieSegmenter ??= SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: false);
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
        source = img.copyResize(source, width: source.width >= source.height ? maxDimension : null, height: source.height > source.width ? maxDimension : null);
      }
      normalizedFile = File('${imageFile.path}_seg_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await normalizedFile.writeAsBytes(img.encodeJpg(source, quality: 90), flush: true);
      final mask = await segmenter.processImage(InputImage.fromFilePath(normalizedFile.path));
      if (mask == null) throw Exception('لم يتم الحصول على قناع الشخص');
      final result = img.Image(width: source.width, height: source.height, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final index = y * source.width + x;
          final confidence = mask.confidences[index].clamp(0.0, 1.0);
          final alpha = ((confidence - 0.35) / 0.40 * 255.0).round().clamp(0, 255);
          final p = source.getPixel(x, y);
          result.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
        }
      }
      final out = File('${imageFile.path}_nobg_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(img.encodePng(result, level: 6), flush: true);
      return out;
    } finally {
      if (normalizedFile != null) { try { if (await normalizedFile.exists()) await normalizedFile.delete(); } catch (_) {} }
    }
  }

  Future<void> _showImagePreviewDialog(File imageFile) async {
    File currentImage = imageFile;
    bool isProcessing = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('معاينة الصورة الشخصية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 220, width: double.infinity,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(currentImage, fit: BoxFit.contain)),
              ),
              const SizedBox(height: 15),
              isProcessing
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      onPressed: () async {
                        setDialogState(() => isProcessing = true);
                        try {
                          final processed = await _removeBackgroundUsingSelfieSegmentation(currentImage);
                          if (processed != null && mounted) {
                            setDialogState(() { currentImage = processed; isProcessing = false; });
                          }
                        } catch (e) {
                          if (mounted) setDialogState(() => isProcessing = false);
                        }
                      },
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('حذف الخلفية'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent),
                    ),
            ],
          ),
          actions: [
            TextButton(onPressed: isProcessing ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: isProcessing ? null : () { setState(() => _pickedImage = currentImage); Navigator.pop(dialogContext); },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('اعتماد', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2000, maxHeight: 2000);
    if (picked != null && mounted) await _showImagePreviewDialog(File(picked.path));
  }

  void _deleteCurrentPhoto() {
    setState(() { _pickedImage = null; if (_studentData != null) _studentData!['imageUrl'] = null; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف صورة الطالب')));
  }

  Future<String?> _uploadImageToEmisServer(File imageFile) async {
    final request = http.MultipartRequest('POST', Uri.parse('https://emis.moedu.gov.iq/api/student/uploadimage'));
    request.headers['Authorization'] = widget.token;
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path, filename: 'avatar.png'));
    try {
      final res = await request.send();
      final body = await res.stream.bytesToString();
      if (res.statusCode == 200) {
        final j = jsonDecode(body);
        if (j is Map) return j['imageUrl']?.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveStudentData() async {
    if (_studentData == null) return;
    setState(() => _isSaving = true);
    try {
      if (_pickedImage != null) {
        final url = await _uploadImageToEmisServer(_pickedImage!);
        if (url != null && url.isNotEmpty) _studentData!['imageUrl'] = url;
      }
      final payload = Map<String, dynamic>.from(_studentData!);
      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api/student/updatestudent'),
        headers: {'Authorization': widget.token, 'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ بنجاح!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: ${response.body}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        final isDark = currentMode == ThemeMode.dark;
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        String imgUrl = _studentData?['imageUrl']?.toString() ?? '';
        if (imgUrl.isNotEmpty && !imgUrl.startsWith('http')) imgUrl = 'https://emis.moedu.gov.iq$imgUrl';

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('تعديل بيانات الطالب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]))),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Stack(
            children: [
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _studentData == null
                      ? const Center(child: Text('فشل جلب البيانات'))
                      : Column(
                          children: [
                            Expanded(
                              child: Form(
                                key: _formKey,
                                child: ListView(
                                  padding: const EdgeInsets.all(15),
                                  children: [
                                    Center(
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: 140, height: 140,
                                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.blueAccent, width: 3)),
                                            child: ClipOval(
                                              child: _pickedImage != null
                                                  ? Image.file(_pickedImage!, fit: BoxFit.cover)
                                                  : imgUrl.isNotEmpty
                                                      ? Image.network(imgUrl, headers: {'Authorization': widget.token}, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 80, color: Colors.grey))
                                                      : const Icon(Icons.person, size: 80, color: Colors.grey),
                                            ),
                                          ),
                                          Positioned(bottom: 0, right: 0, child: CircleAvatar(backgroundColor: Colors.blue, radius: 20, child: IconButton(icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18), onPressed: () => _pickImage(ImageSource.camera)))),
                                          Positioned(bottom: 0, left: 0, child: CircleAvatar(backgroundColor: Colors.green, radius: 20, child: IconButton(icon: const Icon(Icons.photo_library, color: Colors.white, size: 18), onPressed: () => _pickImage(ImageSource.gallery)))),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Center(child: TextButton.icon(onPressed: _deleteCurrentPhoto, icon: const Icon(Icons.delete_forever, color: Colors.red), label: const Text('حذف الصورة الحالية', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))),
                                    const SizedBox(height: 15),
                                    ..._buildStudentFormSections(isDark, textColor),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(15),
                              color: cardColor,
                              child: SizedBox(
                                width: double.infinity, height: 55,
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveStudentData,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('حفظ', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                          ],
                        ),
              Positioned(
                left: 0, bottom: 0,
                child: EmisLiveSync(
                  key: _liveSyncKey,
                  url: 'https://emis.moedu.gov.iq/centers/schools/${_studentData?['schoolId'] ?? ''}/individuals/students/management',
                  mode: 'edit', entity: 'student', token: widget.token, recordId: widget.studentId,
                  aliases: _liveAliases(), onSnapshot: _applyLiveSnapshot, onStatus: (v) {},
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PlainTextField extends StatefulWidget {
  final String label;
  final dynamic initialValue;
  final bool isDark;
  final Color textColor;
  final TextDirection? textDirection;
  final Function(String) onChanged;
  final bool readOnly;
  final bool requiredField;
  final VoidCallback? onTap;
  final VoidCallback? onMic;
  final bool micActive;

  const PlainTextField({
    super.key, required this.label, required this.initialValue, required this.isDark,
    required this.textColor, this.textDirection, required this.onChanged,
    this.readOnly = false, this.requiredField = false, this.onTap, this.onMic, this.micActive = false,
  });

  @override
  State<PlainTextField> createState() => _PlainTextFieldState();
}

class _PlainTextFieldState extends State<PlainTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant PlainTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialValue?.toString() ?? '';
    if (next != _controller.text) {
      _controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: _controller,
        readOnly: widget.readOnly,
        onChanged: widget.onChanged,
        onTap: widget.onTap,
        validator: null,
        textDirection: widget.textDirection,
        style: TextStyle(fontWeight: FontWeight.bold, color: widget.textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          filled: true, fillColor: widget.isDark ? Colors.black12 : Colors.grey[50],
          suffixIcon: widget.onMic == null ? null : IconButton(tooltip: 'الإدخال الصوتي', onPressed: widget.onMic, icon: Icon(widget.micActive ? Icons.mic_rounded : Icons.mic_none_rounded, color: widget.micActive ? Colors.red : null)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        ),
      ),
    );
  }
}
