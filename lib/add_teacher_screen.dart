import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';
import 'emis_live_sync.dart';

class AddTeacherScreen extends StatefulWidget {
  final String token;
  final String schoolId;

  const AddTeacherScreen({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  State<AddTeacherScreen> createState() => _AddTeacherScreenState();
}

class _AddTeacherScreenState extends State<AddTeacherScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  final Map<String, List<Map<String, dynamic>>> options = {};

  List<Map<String, dynamic>> _addressCountries = [];
  List<Map<String, dynamic>> _addressGovernorates = [];
  List<Map<String, dynamic>> _addressDistricts = [];
  String? _addressCountryId;
  String? _addressGovernorateId;
  String? _addressDistrictId;

  bool loading = true, saving = false;
  String? error;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';

  final endpoints = const <String, String>{
    'gender': '/selectoption/Gender',
    'countryOfBirth': '/selectoption/بلد الولادة',
    'nationality': '/selectoption/بلد الولادة',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'idType': '/selectoption/IdentificationType',
    'motherTongue': '/selectoption/لغة',
    'maritalStatus': '/selectoption/الحالة الاجتماعية',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'positionType': '/SelectOption/نوع الوظيفة',
    'employmentType': '/selectoption/نوع التوظيف',
    'employeeCategory': '/selectoption/فئة الموظف',
    'classification': '/selectoption/التصنيف',
    'status': '/selectoption/الحالة الوظيفية',
    'currentPosition': '/selectoption/المنصب الحالي',
    'educationLevel': '/selectoption/التحصيل الدراسي',
  };

  final labels = const <String, String>{
    'name': 'الإسم',
    'fatherName': 'إسم الأب',
    'grandFatherName': 'اسم والد الأب',
    'fathersGrandFatherName': 'اسم جد الأب',
    'surName': 'اللقب',
    'motherName': 'إسم الأم',
    'mothersFatherName': 'اسم والد الأم',
    'mothersGrandFatherName': 'اسم جد الأم',
    'nationalId': 'رقم البطاقة الوطنية الموحدة',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'idType': 'نوع الهوية',
    'issuingCountry': 'بلد الإصدار',
    'dateOfBirth': 'تاريخ التولد',
    'gender': 'الجنس',
    'nationality': 'الجنسية',
    'countryOfBirth': 'محل الولادة',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة',
    'employmentType': 'نوع التوظيف',
    'employeeCategory': 'فئة الموظف',
    'classification': 'التصنيف',
    'jobDesignation': 'المسمى الوظيفي',
    'positionType': 'نوع الوظيفة',
    'employmentGrade': 'الدرجة الوظيفية',
    'dateOfStartWorking': 'تاريخ أول تعيين',
    'currentPosition': 'المنصب الحالي',
    'status': 'الحالة الوظيفية',
    'statusDate': 'تاريخ سريان الحالة الوظيفية',
    'statusReason': 'سبب تغيير الحالة الوظيفية',
    'educationLevel': 'التحصيل الدراسي',
    'universityName': 'إسم الكلية / المعهد',
    'graduationYear': 'سنة التخرج',
    'specialization': 'الإختصاص',
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال',
    'town': 'المدينة / القرية',
    'area': 'الحي',
    'quarter': 'المحلة',
    'street': 'الزقاق',
    'address1': 'عنوان 1',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة',
    'mobilePhoneNumber': 'رقم هاتف المعلم',
    'email': 'البريد الإلكتروني',
    'notes': 'ملاحظات',
    'addressCountry': 'الدولة',
    'addressGovernorate': 'المحافظة',
    'addressDistrict': 'القضاء',
  };

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    for (final key in labels.keys) {
      c[key] = TextEditingController();
    }
    c['nationality']!.text = 'العراق';
    c['issuingCountry']!.text = 'العراق';
    c['countryOfBirth']!.text = 'العراق';
    c['idType']!.text = '12';
    c['motherTongue']!.text = 'العربية';
    c['bloodGroup']!.text = 'غير معروف';
    c['religion']!.text = 'الإسلام';
    c['status']!.text = 'مستمر';
    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _load();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in labels.entries)
          entry.key: <String>[entry.key, entry.value],
        'addressCountry': ['addressCountry', 'الدولة', 'country'],
        'addressGovernorate': ['addressGovernorate', 'المحافظة', 'governorate'],
        'addressDistrict': ['addressDistrict', 'القضاء', 'district'],
        'countryStructureId': ['countryStructureId', 'الموقع الجغرافي'],
      };

  Map<String, String> _liveValues() => {
        for (final entry in c.entries) entry.key: entry.value.text,
        'addressCountry': _addressCountryId ?? '',
        'addressGovernorate': _addressGovernorateId ?? '',
        'addressDistrict': _addressDistrictId ?? '',
        'countryStructureId': _addressDistrictId ?? '',
      };

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _pushLive() {
    _liveSyncKey.currentState?.pushValues({
      for (final entry in c.entries) entry.key: entry.value.text,
    });
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    bool changed = false;
    for (final entry in values.entries) {
      final controller = c[entry.key];
      if (controller != null && controller.text != entry.value) {
        controller.value = TextEditingValue(
          text: entry.value,
          selection: TextSelection.collapsed(offset: entry.value.length),
        );
        changed = true;
        if (entry.key == 'employmentType') {
          _liveSyncKey.currentState?.refreshOptions(['classification']);
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _applyLiveOptions(Map<String, List<Map<String, dynamic>>> incoming) {
    bool changed = false;
    incoming.forEach((key, values) {
      if (values.isEmpty) return;
      final existing = options[key] ?? <Map<String, dynamic>>[];
      final merged = <Map<String, dynamic>>[...existing.where((o) => o['_liveOnly'] != true)];
      for (final option in values) {
        final value = option['value'] ?? option['id'] ?? option['displayName'] ?? option['label'];
        final label = option['displayName'] ?? option['label'] ?? option['text'] ?? value;
        if ('$value'.trim().isEmpty) continue;
        if (!merged.any((o) => '${o['value'] ?? o['id'] ?? ''}' == '$value' || '${o['displayName'] ?? o['label'] ?? ''}' == '$label')) {
          merged.add({'value': value, 'displayName': label, '_liveOnly': true});
        }
      }
      options[key] = merged;
      changed = true;
    });
    if (changed && mounted) setState(() {});
  }

  List<String> _classificationFallback() {
    final type = c['employmentType']?.text.trim();
    if (type == 'ملاك') return const ['موظف', 'معلم'];
    if (type == 'عقد') return const ['موظف بعقد', 'محاضر بعقد'];
    return const [];
  }

  dynamic _unwrap(dynamic d) =>
      d is Map && d['data'] != null ? d['data'] : d;

  Future<dynamic> _get(String endpoint) async {
    final response = await http.get(
      Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
      headers: h,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Map<String, dynamic>>> _list(String endpoint) async {
    final raw = _unwrap(await _get(endpoint));
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  String _value(Map<String, dynamic> x) =>
      '${x['value'] ?? x['id'] ?? x['code'] ?? ''}';

  String _text(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? _value(x)}';

  Future<void> _load() async {
    try {
      for (final e in endpoints.entries) {
        options[e.key] = await _loadOptionCandidates(e.key);
      }
      await _loadCountryStructure();
      if (c['status']!.text.trim().isEmpty && (options['status'] ?? const []).isNotEmpty) {
        c['status']!.text = _value(options['status']!.first);
      }
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = '$e'; });
    }
  }

  List<String> _optionEndpointCandidates(String key) {
    if (key == 'positionType') return const ['/SelectOption/نوع الوظيفة'];
    return endpoints.containsKey(key) ? <String>[endpoints[key]!] : const [];
  }

  Future<List<Map<String, dynamic>>> _loadOptionCandidates(String key) async {
    for (final endpoint in _optionEndpointCandidates(key)) {
      try {
        final list = await _list(endpoint);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [];
  }

  Future<void> _loadCountryStructure() async {
    try {
      final list = await _list('/CountryStructure/getcountrystructure');
      if (list.isEmpty) return;
      _addressCountries = list;
      Map<String, dynamic>? iraq;
      for (final item in list) {
        if (_text(item).contains('العراق') || _text(item).toLowerCase() == 'iraq') { iraq = item; break; }
      }
      iraq ??= list.first;
      _addressCountryId = _value(iraq);
      _addressGovernorates = _childrenOf(iraq);
      _addressGovernorateId = null;
      _addressDistrictId = null;
      _addressDistricts = [];
    } catch (_) {}
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
    final raw = node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _setAddressGovernorates(Map<String, dynamic> country) {
    _addressGovernorates = _childrenOf(country);
    _addressGovernorateId = null;
    _addressDistricts = [];
    _addressDistrictId = null;
  }

  void _setAddressDistricts(Map<String, dynamic> governorate) {
    _addressDistricts = _childrenOf(governorate);
    _addressDistrictId = null;
  }

  Widget _addressDropdown({required String label, required String? value, required List<Map<String, dynamic>> items, required ValueChanged<String?> onChanged}) {
    final safe = items.any((x) => _value(x) == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safe,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      items: items.map((x) => DropdownMenuItem<String>(value: _value(x), child: Text(_text(x), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
      onChanged: onChanged,
    );
  }

  List<Map<String, dynamic>> _values(String key) {
    final result = <Map<String, dynamic>>[
      ...(options[key] ?? []),
    ];
    if (key == 'classification') {
      for (final value in _classificationFallback()) {
        if (!result.any((x) => _value(x) == value)) result.add({'value': value, 'displayName': value});
      }
    }
    final current = c[key]!.text.trim();
    if (current.isNotEmpty && !result.any((x) => _value(x) == current)) {
      result.insert(0, {'value': current, 'displayName': current});
    }
    return result;
  }

  Widget _textField(
    String key, {
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: c[key],
        keyboardType: keyboard,
        maxLines: maxLines,
        readOnly: key == 'dateOfBirth' || key == 'dateOfStartWorking' || key == 'statusDate',
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText: labels[key] ?? key,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
          ),
        ),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        validator: null,
        onChanged: (_) => _liveSyncKey.currentState?.pushValues(_liveValues()),
        onTap: () { if (key == 'dateOfBirth' || key == 'dateOfStartWorking' || key == 'statusDate') { _pickDate(key); } else { _focusLive(key); } },
      );

  Future<void> _pickDate(String key) async {
    final initial = DateTime.tryParse(c[key]?.text ?? '') ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: DateTime.now(), helpText: labels[key], locale: const Locale('ar'));
    if (picked == null || !mounted) return;
    c[key]!.text = '${picked.year.toString().padLeft(4,'0')}-${picked.month.toString().padLeft(2,'0')}-${picked.day.toString().padLeft(2,'0')}';
    _focusLive(key);
    setState(() {});
  }

  Widget _select(
    String key, {
    bool required = false,
    List<String> fallback = const [],
  }) {
    final values = key == 'idType'
        ? <Map<String, dynamic>>[{'value': '12', 'displayName': 'البطاقة الوطنية الموحدة'}]
        : _values(key);
    for (final x in fallback) {
      if (!values.any((v) => _value(v) == x)) {
        values.add({'value': x, 'displayName': x});
      }
    }

    final current = c[key]!.text.trim();
    return DropdownButtonFormField<String>(
      value: current.isEmpty ? null : current,
      isExpanded: true,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
        ),
      ),
      items: values
          .map(
            (x) => DropdownMenuItem<String>(
              value: _value(x),
              child: Text(_text(x), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
          .where((x) => x.value != null && x.value!.isNotEmpty)
          .toList(),
      onTap: () => _focusLive(key),
      onChanged: (v) { setState(() => c[key]!.text = v ?? ''); _focusLive(key); if (key == 'employmentType') _liveSyncKey.currentState?.refreshOptions(['classification']); },
      validator: null,
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.045),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4527A0),
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      saving = true;
      error = null;
    });

    try {
      final nationalId = c['nationalId']!.text.trim();
      if (nationalId.isNotEmpty) {
        final check = await _get(
          '/employee/checknationalidnumber?value=${Uri.encodeQueryComponent(nationalId)}',
        );
        if (check is Map && check['isUnique'] == false) {
          throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً');
        }
      }

      final payload = <String, dynamic>{
        'Id': 0,
        'EmployeeIdNumber': _n('employeeIdNumber'),
        'FamilyNumber': _n('familyNumber'),
        'IsTeacher': true,
        'EmploymentType': _n('employmentType') ?? '',
        'EmployeeCategory': _n('employeeCategory') ?? '',
        'Classification': _n('classification') ?? '',
        'JobDesignation': _n('jobDesignation'),
        'EmploymentGrade': _n('employmentGrade'),
        'DateOfStartWorking': _n('dateOfStartWorking'),
        'EducationLevel': _n('educationLevel'),
        'GraduationYear': _n('graduationYear'),
        'UniversityName': _n('universityName'),
        'Specialization': _n('specialization'),
        'Name': _n('name') ?? '',
        'FatherName': _n('fatherName') ?? '',
        'GrandFatherName': _n('grandFatherName') ?? '',
        'FathersGrandFatherName': _n('fathersGrandFatherName') ?? '',
        'SurName': _n('surName'),
        'MotherName': _n('motherName'),
        'MothersFatherName': _n('mothersFatherName'),
        'MothersGrandFatherName': _n('mothersGrandFatherName'),
        'DateOfBirth': _n('dateOfBirth'),
        'Gender': int.tryParse(c['gender']!.text),
        'Nationality': _n('nationality') ?? 'العراق',
        'CountryOfBirth': _n('countryOfBirth') ?? 'العراق',
        'HomeTown': _n('homeTown'),
        'IdentificationId': 0,
        'Identification': {
          'IdNumber': nationalId,
          'IssuingCountry': _n('issuingCountry') ?? 'العراق',
          'IdType': int.tryParse(c['idType']!.text),
        },
        'ImageUrl': '',
        'MotherTongue': _n('motherTongue') ?? 'العربية',
        'MaritalStatus': _n('maritalStatus') ?? 'أعزب',
        'BloodGroup': _n('bloodGroup') ?? 'غير معروف',
        'Religion': _n('religion') ?? 'الإسلام',
        'HomePhoneNumber': '',
        'Notes': _n('notes') ?? '',
        'SpecialNeedsInformation': _n('specialNeedsInformation'),
        'EmergencyContactName': _n('emergencyContactName'),
        'EmergencyContactRelationship': _n('emergencyContactRelationship'),
        'EmergencyContactPhoneNumber': _n('emergencyContactPhoneNumber'),
        'Address': {
          'AddressType': 1,
          'Town': _n('town') ?? '',
          'Area': _n('area') ?? '',
          'Quarter': _n('quarter') ?? '',
          'Street': _n('street') ?? '',
          'ClosestLocation': _n('closestLocation') ?? '',
          'countryStructureId': _addressDistrictId == null ? null : int.tryParse(_addressDistrictId!),
          'Latitude': '0',
          'Longitude': '0',
          'ApartmentNumber': '',
          'BuildingNumber': '',
          'Address1': _n('address1') ?? '',
          'Address2': _n('address2') ?? '',
          'SchoolPhoneNumber': '',
          'MobilePhoneNumber': _n('mobilePhoneNumber') ?? '',
          'Email': _n('email') ?? '',
          'Fax': '',
          'Website': '',
        },
        'EmploymentRecord': {
          'EmploymentStatuses': [
            {
              'StatusType': _n('status'),
              'DisEngagementDate': null,
              'MinistryOfficialDocumentNumber': null,
              'Reason': _n('statusReason'),
              'StatusDate': _n('statusDate'),
              'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
            }
          ],
          'EmploymentPositions': [
            {
              'Position': _n('currentPosition'),
              'InitiateDate': _n('dateOfStartWorking'),
            }
          ],
          'IsCurrentlyActive': (_n('status') ?? 'مستمر') == 'مستمر',
          'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
          'CurrentEmploymentPosition': _n('positionType'),
        },
      };

      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/addemployee'),
        headers: h,
        body: jsonEncode(payload),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة المعلم بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String? _n(String key) {
    final value = c[key]?.text.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'إضافة معلم جديد',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4527A0), Color(0xFF7E57C2)],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          loading
              ? const Center(child: CircularProgressIndicator())
              : Directionality(
              textDirection: TextDirection.rtl,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(17),
                  children: [
                    _hero(),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      _error(error!),
                    ],
                    const SizedBox(height: 14),
                    _section('البيانات الشخصية', [
                      _textField('name', required: true),
                      const SizedBox(height: 10),
                      _textField('fatherName', required: true),
                      const SizedBox(height: 10),
                      _textField('grandFatherName', required: true),
                      const SizedBox(height: 10),
                      _textField('fathersGrandFatherName'),
                      const SizedBox(height: 10),
                      _textField('surName'),
                      const SizedBox(height: 10),
                      _textField('motherName'),
                      const SizedBox(height: 10),
                      _textField('mothersFatherName'),
                      const SizedBox(height: 10),
                      _textField('mothersGrandFatherName'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('gender', required: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('dateOfBirth')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('countryOfBirth')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('nationality')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('homeTown'),
                    ]),
                    _section('الهوية والوثائق', [
                      Row(
                        children: [
                          Expanded(
                            child: _select('idType', required: true),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _select(
                              'issuingCountry',
                              fallback: const ['العراق'],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              'nationalId',
                              required: true,
                              keyboard: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('employeeIdNumber')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('familyNumber'),
                    ]),
                    _section('البيانات الوظيفية', [
                      Row(
                        children: [
                          Expanded(child: _select('employmentType', required: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('jobDesignation')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('employeeCategory', required: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _select('classification', required: true)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('currentPosition')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('positionType', required: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('employmentGrade')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('dateOfStartWorking'),
                      const SizedBox(height: 10),
                      _section('الحالة الوظيفية', [
                        _select('status', required: true),
                        const SizedBox(height: 10),
                        _textField('statusDate'),
                        const SizedBox(height: 10),
                        _textField('statusReason', maxLines: 2),
                      ]),
                      const SizedBox(height: 10),
                      _select('educationLevel', fallback: const ['ابتدائية','متوسطة','إعدادية','دبلوم','بكالوريوس','دبلوم عالي','ماجستير','دكتوراه']),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('universityName')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('graduationYear')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('specialization'),
                    ]),
                    _section('البيانات الاجتماعية', [
                      Row(
                        children: [
                          Expanded(child: _select('motherTongue')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('maritalStatus')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('bloodGroup')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('religion')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('specialNeedsInformation', maxLines: 2),
                      const SizedBox(height: 10),
                      _textField('notes', maxLines: 3),
                    ]),
                    _section('بيانات الاتصال والطوارئ', [
                      _textField('emergencyContactName'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('emergencyContactRelationship')),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              'emergencyContactPhoneNumber',
                              keyboard: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    _section('العنوان', [
                      _addressDropdown(
                        label: 'الدولة',
                        value: _addressCountryId,
                        items: _addressCountries,
                        onChanged: (v) {
                          final item = _addressCountries.where((x) => _value(x) == v).toList();
                          if (item.isEmpty) return;
                          setState(() {
                            _addressCountryId = v;
                            _setAddressGovernorates(item.first);
                          });
                          _focusLive('addressCountry');
                        },
                      ),
                      const SizedBox(height: 10),
                      _addressDropdown(
                        label: 'المحافظة',
                        value: _addressGovernorateId,
                        items: _addressGovernorates,
                        onChanged: (v) {
                          final item = _addressGovernorates.where((x) => _value(x) == v).toList();
                          if (item.isEmpty) return;
                          setState(() {
                            _addressGovernorateId = v;
                            _setAddressDistricts(item.first);
                          });
                          _focusLive('addressGovernorate');
                        },
                      ),
                      const SizedBox(height: 10),
                      _addressDropdown(
                        label: 'القضاء',
                        value: _addressDistrictId,
                        items: _addressDistricts,
                        onChanged: (v) {
                          setState(() => _addressDistrictId = v);
                          _focusLive('addressDistrict');
                        },
                      ),
                      const SizedBox(height: 10),
                      _textField('town'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('area')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('quarter')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('street'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('address1')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('address2')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('closestLocation'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('mobilePhoneNumber', keyboard: TextInputType.phone)),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('email', keyboard: TextInputType.emailAddress)),
                        ],
                      ),
                    ]),
                    SizedBox(
                      height: 55,
                      child: FilledButton.icon(
                        onPressed: saving ? null : _save,
                        icon: saving
                            ? const SizedBox(
                                width: 21,
                                height: 21,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text(
                          'حفظ المعلم',
                          style: TextStyle(fontWeight: FontWeight.bold,fontSize: 17),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                  ],
                ),
              ),
            ),
          if (!loading)
            Positioned(
              left: 0,
              bottom: 0,
              child: EmisLiveSync(
                key: _liveSyncKey,
                url: 'https://emis.moedu.gov.iq/centers/schools/${widget.schoolId}/individuals/teachers/management',
                mode: 'add',
                entity: 'teacher',
                token: widget.token,
                aliases: _liveAliases(),
                onSnapshot: _applyLiveSnapshot,
                onOptions: _applyLiveOptions,
                onStatus: (v) { if (mounted) setState(() => _liveStatus = v); },
              ),
            ),
        ],
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4527A0), Color(0xFF7E57C2)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person_add_alt_1_rounded,
                  color: Colors.white, size: 30),
            ),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إضافة معلم جديد',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text(
                    'الحقول والقوائم تُقرأ مباشرة من EMIS.',
                    style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _error(String text) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold,color: Colors.red)),
      );
}
