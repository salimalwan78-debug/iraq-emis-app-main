import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';

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

  bool loading = true, saving = false;
  String? error;

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
    'jobDesignation': '/SelectOption/نوع الوظيفة',
    'employmentType': '/SelectOption/نوع الوظيفة',
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
    'employmentGrade': 'الدرجة الوظيفية',
    'dateOfStartWorking': 'تاريخ أول تعيين',
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
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة إن وجدت',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال',
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
    c['motherTongue']!.text = 'العربية';
    c['bloodGroup']!.text = 'غير معروف';
    c['religion']!.text = 'الإسلام';
    _load();
  }

  @override
  void dispose() {
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
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
        options[e.key] = await _list(e.value);
      }
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  List<Map<String, dynamic>> _values(String key) {
    final result = <Map<String, dynamic>>[
      ...(options[key] ?? []),
    ];
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
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText: '${labels[key] ?? key}${required ? ' *' : ''}',
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
        validator: required
            ? (v) =>
                v == null || v.trim().isEmpty ? 'هذا الحقل مطلوب' : null
            : null,
      );

  Widget _select(
    String key, {
    bool required = false,
    List<String> fallback = const [],
  }) {
    final values = _values(key);
    for (final x in fallback) {
      if (!values.any((v) => _value(v) == x)) {
        values.add({'value': x, 'displayName': x});
      }
    }

    final current = c[key]!.text.trim();
    return DropdownButtonFormField<String>(
      value: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '${labels[key] ?? key}${required ? ' *' : ''}',
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
              child: Text(_text(x), overflow: TextOverflow.ellipsis),
            ),
          )
          .where((x) => x.value != null && x.value!.isNotEmpty)
          .toList(),
      onChanged: (v) => setState(() => c[key]!.text = v ?? ''),
      validator: required
          ? (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null
          : null,
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
          'countryStructureId': null,
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
              'StatusType': 'مستمر',
              'DisEngagementDate': null,
              'MinistryOfficialDocumentNumber': null,
              'Reason': null,
              'CurrentBelongToEntityId': int.tryParse(widget.schoolId),
            }
          ],
          'EmploymentPositions': [],
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
      body: loading
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
                          Expanded(
                            child: _select(
                              'employmentType',
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: _select('jobDesignation')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('employeeCategory')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('classification')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField('employmentGrade')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField('dateOfStartWorking')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('educationLevel'),
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
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                  ],
                ),
              ),
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
                    style: TextStyle(color: Colors.white70, fontSize: 13),
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
        child: Text(text, style: const TextStyle(color: Colors.red)),
      );
}
