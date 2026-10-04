import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'app_core.dart';

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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _studentData;
  File? _pickedImage;

  // ============================================================
  // EMIS LIVE REFERENCE DATA
  // ============================================================

  final Map<String, List<Map<String, dynamic>>> _options = {};
  final Set<String> _loadingOptions = <String>{};

  static const Map<String, String> _optionEndpoints = {
    'countryOfBirth': '/selectoption/بلد الولادة',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'gender': '/selectoption/Gender',
    'motherTongue': '/selectoption/لغة',
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
    _fetchStudentData();
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

      // These are the real option APIs observed in the supplied EMIS HAR.
      for (final key in _optionEndpoints.keys) {
        await _loadOptions(key);
      }
      await _loadStageOptions(student['schoolId']?.toString());
      await _loadClassroomOptions(
        student['schoolId']?.toString(),
        student['stageId']?.toString(),
      );
      await _loadCountryStructure();

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
      final flattened = <Map<String, dynamic>>[];
      void walk(List<dynamic> nodes, String prefix) {
        for (final node in nodes) {
          if (node is! Map) continue;
          final id = node['id'];
          final name = node['name']?.toString() ?? '';
          if (id != null) flattened.add({'value': id, 'displayName': prefix.isEmpty ? name : '$prefix / $name'});
          final children = node['children'];
          if (children is List) walk(children, prefix.isEmpty ? name : '$prefix / $name');
        }
      }
      walk(list, '');
      if (flattened.isNotEmpty) _options['countryStructureId'] = flattened;
    } catch (e) { debugPrint('تعذر تحميل هيكل العناوين: $e'); }
  }

  String _label(String key) => _officialArabicNames[key] ?? key;

  bool _isDateField(String key) => <String>{
    'dateOfBirth', 'issuingDate', 'effectiveDate', 'startDate', 'endDate',
  }.contains(key);

  bool _isRequired(String key, [Map<String, dynamic>? parent]) {
    // Required markers mirror the fields currently treated as mandatory by
    // the EMIS student form.  The complete API object is still retained;
    // this only controls the UI/validation projection.
    const core = <String>{
      'name',
      'fatherName',
      'grandFatherName',
      'motherName',
      'dateOfBirth',
      'gender',
      'nationality',
      'countryOfBirth',
      'motherTongue',
      'maritalStatus',
      'bloodGroup',
      'religion',
      'stageId',
      'classRoomId',
    };
    if (core.contains(key)) return true;

    final idType = parent?['idType'] ?? _studentData?['identification']?['idType'];
    if (key == 'idType') return true;
    if (key == 'idNumber' && (idType == 12 || idType == 3)) return true;
    if (key == 'jinsiyaIdNumber' && idType == 3) return true;
    if (key == 'issuingCountry' && (idType == 3 || idType == 12 || idType == 22)) return true;
    return false;
  }

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
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        style: TextStyle(color: textColor, fontSize: 16),
        items: items.map((item) => DropdownMenuItem<dynamic>(
          value: _optionValue(item), child: Text(_optionText(item)),
        )).toList(),
        validator: requiredField ? (v) => v == null || v.toString().isEmpty ? 'هذا الحقل مطلوب' : null : null,
        onChanged: (newValue) async {
          setState(() {
            owner[key] = newValue;
            if (key == 'stageId') owner['classRoomId'] = null;
            if (key == 'idType' && owner.containsKey('idNumber')) {
              // Do not erase the stored identity object; only conditional UI changes.
            }
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
      setState(() {
        owner[key] = '${picked.year.toString().padLeft(4,'0')}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
      });
    }
  }

  Widget _fieldFor(String key, dynamic value, Map<String, dynamic> owner, bool isDark, Color textColor) {
    // IMPORTANT: never use key.endsWith('Name') here.  Names such as
    // fatherName/motherName are real EMIS form fields.  Visibility is
    // controlled explicitly by the EMIS UI projection below.
    if (_hiddenStudentResponseFields.contains(key) ||
        _hiddenAddressResponseFields.contains(key)) {
      return const SizedBox.shrink();
    }

    if (_optionEndpoints.containsKey(key) || key == 'stageId' || key == 'classRoomId' || key == 'countryStructureId') {
      return _dropdownField(key: key, owner: owner, isDark: isDark, textColor: textColor);
    }

    if (_isDateField(key)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextFormField(
          controller: TextEditingController(text: value?.toString() ?? ''),
          readOnly: true,
          onTap: () => _pickDate(owner, key),
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            labelText: _isRequired(key, owner) ? '${_label(key)} *' : _label(key),
            suffixIcon: const Icon(Icons.calendar_month),
            filled: true, fillColor: isDark ? Colors.black12 : Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(key), style: TextStyle(color: textColor)),
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
            decoration: InputDecoration(labelText: _label(key), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: (_options[key] ?? const []).map((o) => DropdownMenuItem<String>(value: _optionValue(o)?.toString(), child: Text(_optionText(o)))).toList(),
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
      readOnly: false,
      requiredField: _isRequired(key, owner),
      onChanged: (v) => owner[key] = v,
    );
  }

  // ------------------------------------------------------------------------
  // EMIS UI projection
  // ------------------------------------------------------------------------
  // These sets do NOT delete anything from _studentData.  They only decide
  // which parts of the complete getstudent response are rendered as editable
  // controls.  This keeps the data model future-proof while preventing
  // calculated/history/system fields from leaking into the form.
  static const Set<String> _visibleStudentFields = {
    'name',
    'fatherName',
    'grandFatherName',
    'fathersGrandFatherName',
    'surName',
    'motherName',
    'mothersFatherName',
    'mothersGrandFatherName',
    'dateOfBirth',
    'gender',
    'nationality',
    'countryOfBirth',
    'homeTown',
    'motherTongue',
    'maritalStatus',
    'bloodGroup',
    'religion',
    'homePhoneNumber',
    'notes',
    'specialNeeds',
    'studyLanguage',
    'economicLevel',
    'isCoveredBySocialWelfare',
    'isDroppedOutFromSchool',
    'academicYearId',
    'stageId',
    'classRoomId',
    'identification',
    'address',
    'ageExceptionReason',
    'genderExceptionReason',
  };

  static const Set<String> _visibleAddressFields = {
    'countryStructureId',
    'town',
    'area',
    'quarter',
    'street',
    'address1',
    'address2',
    'closestLocation',
  };

  static const Set<String> _hiddenStudentResponseFields = {
    'id',
    'createdAt',
    'updatedAt',
    'imageUrl',
    'schoolId',
    'schoolName',
    'schoolCensusNumber',
    'stageName',
    'classRoomName',
    'academicYearName',
    'studentStatusName',
    'studentStatus',
    'classificationName',
    'classification',
    'classifications',
    'lastSchoolClassifications',
    'lastSchoolClassification',
    'lastSchoolName',
    'lastCompletedStageName',
    'lastAcademicYearName',
    'lastYearResult',
    'lastAcademicYearId',
    'lastCompletedStageId',
    'lastSchoolId',
    'censusNumber',
  };

  static const Set<String> _hiddenAddressResponseFields = {
    'apartmentNumber',
    'buildingNumber',
    'latitude',
    'longitude',
    'schoolPhoneNumber',
    'mobilePhoneNumber',
    'employeePhoneNumber',
    'email',
    'website',
  };

  List<Widget> _buildDynamicFields(Map<String, dynamic> dataMap, bool isDark, Color textColor, {String prefix = ''}) {
    final widgets = <Widget>[];

    dataMap.forEach((key, value) {
      // Top-level projection: preserve every response field in memory, but
      // render only fields that belong to the current EMIS edit form.
      if (prefix.isEmpty && !_visibleStudentFields.contains(key)) return;

      // Nested address projection: EMIS currently does not render the system
      // metadata fields shown in the raw API response (coordinates, school
      // phone/email/website, apartment/building metadata, ...).
      if (prefix == 'address.' && !_visibleAddressFields.contains(key)) return;
      if (_hiddenStudentResponseFields.contains(key) ||
          _hiddenAddressResponseFields.contains(key)) return;

      if (value is Map) {
        if (key == 'identification') {
          final m = value is Map<String, dynamic>
              ? value
              : Map<String, dynamic>.from(value);
          widgets.add(Card(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            margin: const EdgeInsets.only(bottom: 15, top: 10),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'وثيقة التعريف',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.indigo.shade400),
                  ),
                  const SizedBox(height: 12),
                  if (m.containsKey('idType'))
                    _dropdownField(key: 'idType', owner: m, isDark: isDark, textColor: textColor),
                  ...m.entries
                      .where((e) => e.key != 'idType' && _identityFieldVisible(e.key, m['idType']))
                      .map((e) => _fieldFor(e.key, e.value, m, isDark, textColor)),
                ],
              ),
            ),
          ));
          return;
        }

        widgets.add(Card(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          margin: const EdgeInsets.only(bottom: 15, top: 10),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(key),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade400),
                ),
                const SizedBox(height: 12),
                ..._buildDynamicFields(
                  Map<String, dynamic>.from(value),
                  isDark,
                  textColor,
                  prefix: '$prefix$key.',
                ),
              ],
            ),
          ),
        ));
      } else {
        widgets.add(_fieldFor(key, value, dataMap, isDark, textColor));
      }
    });

    return widgets;
  }

  Widget _studentSection(
    String title,
    List<Widget> children,
    bool isDark,
  ) {
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
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.indigo.shade400,
              ),
            ),
            const SizedBox(height: 13),
            ..._studentGrid(children),
          ],
        ),
      ),
    );
  }

  List<Widget> _studentGrid(List<Widget> children) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final first = children[i];
      final second = i + 1 < children.length ? children[i + 1] : const SizedBox();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        ),
      );
      if (i + 2 < children.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return rows;
  }

  List<Widget> _buildStudentFormSections(bool isDark, Color textColor) {
    final student = _studentData!;
    final identification = student['identification'] is Map
        ? Map<String, dynamic>.from(student['identification'])
        : <String, dynamic>{};
    final address = student['address'] is Map
        ? Map<String, dynamic>.from(student['address'])
        : <String, dynamic>{};

    Widget field(String key, [Map<String, dynamic>? owner]) {
      final target = owner ?? student;
      if (!target.containsKey(key)) return const SizedBox.shrink();
      return _fieldFor(key, target[key], target, isDark, textColor);
    }

    final result = <Widget>[
      _studentSection('الاسم الكامل', [
        field('name'),
        field('fatherName'),
        field('grandFatherName'),
        field('fathersGrandFatherName'),
        field('surName'),
        field('motherName'),
        field('mothersFatherName'),
        field('mothersGrandFatherName'),
      ], isDark),
      _studentSection('البيانات الشخصية', [
        field('dateOfBirth'),
        field('gender'),
        field('nationality'),
        field('countryOfBirth'),
        field('homeTown'),
        field('motherTongue'),
        field('maritalStatus'),
        field('bloodGroup'),
        field('religion'),
        field('homePhoneNumber'),
        field('notes'),
        field('specialNeeds'),
        field('studyLanguage'),
        field('economicLevel'),
        field('isCoveredBySocialWelfare'),
        field('isDroppedOutFromSchool'),
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
        field('academicYearId'),
        field('stageId'),
        field('classRoomId'),
      ], isDark),
      _studentSection('العنوان', [
        field('countryStructureId', address),
        field('town', address),
        field('area', address),
        field('quarter', address),
        field('street', address),
        field('address1', address),
        field('address2', address),
        field('closestLocation', address),
      ], isDark),
    ];

    final ageReason = student['ageExceptionReason']?.toString() ?? '';
    final genderReason = student['genderExceptionReason']?.toString() ?? '';
    if (ageReason.trim().isNotEmpty || genderReason.trim().isNotEmpty) {
      result.add(
        _studentSection('الاستثناءات', [
          if (ageReason.trim().isNotEmpty) field('ageExceptionReason'),
          if (genderReason.trim().isNotEmpty) field('genderExceptionReason'),
        ], isDark),
      );
    }

    return result;
  }

  bool _identityFieldVisible(String key, dynamic idType) {
    final t = int.tryParse(idType?.toString() ?? '');
    if (t == 3) return {'idNumber','jinsiyaIdNumber','issuer','recordNumber','pageNumber','issuingCountry','issuingDate','nameOfDocument'}.contains(key);
    if (t == 12) return {'idNumber','issuingCountry','issuingDate','nameOfDocument'}.contains(key);
    if (t == 22) return {'birthCertificateNumber','issuer','issuingDate','issuingCountry','nameOfDocument'}.contains(key);
    if (t == 16) return {'otherIdNumber','nameOfDocument','issuer','issuingDate','issuingCountry'}.contains(key);
    return true;
  }

  // ============================================================
  // LOCAL BACKGROUND REMOVAL - Google ML Kit Selfie Segmentation
  // ============================================================
  //
  // The segmentation is performed locally on the phone.
  // No image is uploaded to a background-removal website or API.
  //
  // We intentionally reduce the working image to a maximum of 512 px
  // because this application only needs a student ID/avatar image.
  // This keeps processing fast and the resulting file small.

  SelfieSegmenter? _selfieSegmenter;

  Future<void> _initializeSelfieSegmenter() async {
    _selfieSegmenter ??= SelfieSegmenter(
      mode: SegmenterMode.single,
      enableRawSizeMask: false,
    );
  }

  Future<File?> _removeBackgroundUsingSelfieSegmentation(
    File imageFile,
  ) async {
    final stopwatch = Stopwatch()..start();
    File? normalizedFile;

    try {
      await _initializeSelfieSegmenter();

      final segmenter = _selfieSegmenter;
      if (segmenter == null) {
        throw Exception('تعذر تهيئة أداة إزالة الخلفية');
      }

      final sourceBytes = await imageFile.readAsBytes();
      var sourceImage = img.decodeImage(sourceBytes);

      if (sourceImage == null) {
        throw Exception('تعذر قراءة الصورة');
      }

      // Apply EXIF orientation before sending the image to ML Kit so that
      // the image and segmentation mask always have the same orientation.
      sourceImage = img.bakeOrientation(sourceImage);

      // Keep the processing image small. The longest side will be <= 512 px.
      const maxDimension = 512;
      if (sourceImage.width > maxDimension ||
          sourceImage.height > maxDimension) {
        sourceImage = img.copyResize(
          sourceImage,
          width: sourceImage.width >= sourceImage.height
              ? maxDimension
              : null,
          height: sourceImage.height > sourceImage.width
              ? maxDimension
              : null,
          interpolation: img.Interpolation.linear,
        );
      }

      // Convert to a simple JPEG for ML Kit input. This avoids depending on
      // EXIF metadata after the orientation has already been baked in.
      normalizedFile = File(
        '${imageFile.path}_segmentation_input_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await normalizedFile.writeAsBytes(
        img.encodeJpg(sourceImage, quality: 90),
        flush: true,
      );

      final inputImage = InputImage.fromFilePath(normalizedFile.path);
      final mask = await segmenter.processImage(inputImage);

      if (mask == null) {
        throw Exception('لم يتم الحصول على قناع الشخص من ML Kit');
      }

      if (mask.width <= 0 || mask.height <= 0 || mask.confidences.isEmpty) {
        throw Exception('قناع إزالة الخلفية غير صالح');
      }

      if (mask.width != sourceImage.width ||
          mask.height != sourceImage.height) {
        throw Exception(
          'أبعاد قناع إزالة الخلفية لا تطابق الصورة: '
          '${mask.width}x${mask.height} مقابل '
          '${sourceImage.width}x${sourceImage.height}',
        );
      }

      // ML Kit returns a foreground confidence in the range 0..1 for each
      // pixel. Keep a small soft edge rather than using a hard binary cut.
      final result = img.Image(
        width: sourceImage.width,
        height: sourceImage.height,
        numChannels: 4,
      );

      final pixelCount = sourceImage.width * sourceImage.height;
      if (mask.confidences.length < pixelCount) {
        throw Exception(
          'عدد قيم القناع غير كافٍ: ${mask.confidences.length}',
        );
      }

      for (var y = 0; y < sourceImage.height; y++) {
        for (var x = 0; x < sourceImage.width; x++) {
          final index = y * sourceImage.width + x;
          final confidence = mask.confidences[index].clamp(0.0, 1.0);

          // Remove low-confidence background while keeping a smooth edge.
          // 0.35 -> transparent, 0.75 -> fully opaque.
          final alpha = ((confidence - 0.35) / 0.40 * 255.0)
              .round()
              .clamp(0, 255);

          final sourcePixel = sourceImage.getPixel(x, y);
          result.setPixelRgba(
            x,
            y,
            sourcePixel.r,
            sourcePixel.g,
            sourcePixel.b,
            alpha,
          );
        }
      }

      final outputPath =
          '${imageFile.path}_nobg_${DateTime.now().millisecondsSinceEpoch}.png';
      final outputFile = File(outputPath);

      await outputFile.writeAsBytes(
        img.encodePng(result, level: 6),
        flush: true,
      );

      debugPrint(
        'ML Kit background removal completed in '
        '${stopwatch.elapsedMilliseconds} ms: $outputPath',
      );

      return outputFile;
    } catch (e, stackTrace) {
      debugPrint('ML Kit background removal error: $e');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      if (normalizedFile != null) {
        try {
          if (await normalizedFile.exists()) {
            await normalizedFile.delete();
          }
        } catch (e) {
          debugPrint('تعذر حذف ملف المعالجة المؤقت: $e');
        }
      }
      stopwatch.stop();
    }
  }

  @override
  void dispose() {
    final segmenter = _selfieSegmenter;
    _selfieSegmenter = null;
    if (segmenter != null) {
      segmenter.close();
    }
    super.dispose();
  }

  // ============================================================
  // IMAGE PREVIEW
  // ============================================================

  Future<void> _showImagePreviewDialog(File imageFile) async {
    File currentImage = imageFile;
    bool isProcessing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'معاينة الصورة الشخصية',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: InteractiveViewer(
                          panEnabled: true,
                          boundaryMargin: const EdgeInsets.all(20),
                          minScale: 0.5,
                          maxScale: 4,
                          child: Image.file(
                            currentImage,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'يمكنك تقريب الصورة لمراجعتها قبل اعتمادها',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 15),
                    if (isProcessing)
                      const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'جاري إزالة الخلفية محليًا...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'يرجى الانتظار',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            setDialogState(() => isProcessing = true);
                            try {
                              final processed =
                                  await _removeBackgroundUsingSelfieSegmentation(
                                currentImage,
                              );

                              if (processed == null) {
                                throw Exception(
                                  'لم يتم الحصول على الصورة المعالجة',
                                );
                              }

                              if (!mounted) return;

                              setDialogState(() {
                                currentImage = processed;
                                isProcessing = false;
                              });

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تمت إزالة الخلفية بنجاح'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              debugPrint('ML Kit background removal error: $e');
                              if (!mounted) return;

                              setDialogState(() => isProcessing = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تعذر إزالة الخلفية: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.auto_fix_high,
                            color: Colors.black87,
                          ),
                          label: const Text(
                            'حذف الخلفية',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () {
                          setState(() => _pickedImage = currentImage);
                          Navigator.pop(dialogContext);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'اعتماد',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2500,
        maxHeight: 2500,
      );

      if (picked != null && mounted) {
        await _showImagePreviewDialog(File(picked.path));
      }
    } catch (e) {
      debugPrint('خطأ في اختيار الصورة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح الكاميرا أو معرض الصور'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _deleteCurrentPhoto() {
    setState(() {
      _pickedImage = null;
      if (_studentData != null) _studentData!['imageUrl'] = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف صورة الطالب')),
    );
  }

  // ============================================================
  // UPLOAD IMAGE TO EMIS
  // ============================================================

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
        filename: 'avatar.png',
      ),
    );

    try {
      final streamedResponse = await request.send();
      final responseData =
          await streamedResponse.stream.bytesToString();

      debugPrint('رفع صورة EMIS: ${streamedResponse.statusCode}');

      if (streamedResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(responseData);
        if (jsonResponse is Map) {
          return jsonResponse['imageUrl']?.toString();
        }
      }

      debugPrint('استجابة رفع الصورة: $responseData');
    } catch (e) {
      debugPrint('خطأ في رفع الصورة إلى EMIS: $e');
    }

    return null;
  }

  // ============================================================
  // SAVE STUDENT
  // ============================================================

  Future<void> _saveStudentData() async {
    if (_studentData == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى ملء الحقول الإلزامية المشار إليها بعلامة *'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_pickedImage != null) {
        final newImageUrl =
            await _uploadImageToEmisServer(_pickedImage!);

        if (newImageUrl != null && newImageUrl.isNotEmpty) {
          _studentData!['imageUrl'] = newImageUrl;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تعذر رفع صورة الطالب'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      final response = await http.post(
        Uri.parse(
          'https://emis.moedu.gov.iq/api/student/updatestudent',
        ),
        headers: {
          'Authorization': widget.token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(_studentData),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الحفظ بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        debugPrint('Update student status: ${response.statusCode}');
        debugPrint('Update student response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل الحفظ! تأكد من المدخلات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات الطالب: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطأ في الاتصال'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppCore.themeNotifier,
      builder: (context, currentMode, child) {
        final isDark = currentMode == ThemeMode.dark;
        final bgColor =
            isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
        final cardColor =
            isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;

        String imgUrl = _studentData?['imageUrl']?.toString() ?? '';
        if (imgUrl.isNotEmpty && !imgUrl.startsWith('http')) {
          imgUrl = 'https://emis.moedu.gov.iq$imgUrl';
        }

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text(
              'تعديل بيانات الطالب',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1A237E),
                    Color(0xFF4A90E2),
                  ],
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: _isLoading
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
                                      width: 140,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.blueAccent,
                                          width: 3,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: _pickedImage != null
                                            ? Image.file(
                                                _pickedImage!,
                                                fit: BoxFit.cover,
                                              )
                                            : imgUrl.isNotEmpty
                                                ? Image.network(
                                                    imgUrl,
                                                    headers: {
                                                      'Authorization':
                                                          widget.token,
                                                    },
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Icon(
                                                        Icons.person,
                                                        size: 80,
                                                        color: Colors.grey[400],
                                                      );
                                                    },
                                                  )
                                                : Icon(
                                                    Icons.person,
                                                    size: 80,
                                                    color: Colors.grey[400],
                                                  ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: CircleAvatar(
                                        backgroundColor: Colors.blue,
                                        radius: 20,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.camera_alt,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          onPressed: () => _pickImage(
                                            ImageSource.camera,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      child: CircleAvatar(
                                        backgroundColor: Colors.green,
                                        radius: 20,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.photo_library,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          onPressed: () => _pickImage(
                                            ImageSource.gallery,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: TextButton.icon(
                                  onPressed: _deleteCurrentPhoto,
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'حذف الصورة الحالية',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              ..._buildStudentFormSections(
                                isDark,
                                textColor,
                              ),
                            ],
                          ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(15),
                          color: cardColor,
                          child: SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed:
                                  _isSaving ? null : _saveStudentData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isSaving
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'حفظ',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
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
}

// ================================================================
// NORMAL TEXT FIELD
// لا يوجد ميكروفون هنا.
// ================================================================

class PlainTextField extends StatefulWidget {
  final String label;
  final dynamic initialValue;
  final bool isDark;
  final Color textColor;
  final Function(String) onChanged;
  final bool readOnly;
  final bool requiredField;

  const PlainTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.isDark,
    required this.textColor,
    required this.onChanged,
    this.readOnly = false,
    this.requiredField = false,
  });

  @override
  State<PlainTextField> createState() => _PlainTextFieldState();
}

class _PlainTextFieldState extends State<PlainTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: _controller,
        readOnly: widget.readOnly,
        onChanged: widget.onChanged,
        validator: widget.requiredField
            ? (value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
        style: TextStyle(
          color: widget.textColor,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: widget.isDark ? Colors.black12 : Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }
}
