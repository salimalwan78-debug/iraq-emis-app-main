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

  File? _pickedImage;
  String _uploadedImageUrl = '';
  SelfieSegmenter? _selfieSegmenter;

  bool loading = true;
  bool saving = false;
  String? error;

  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';

  // المسارات الفعلية الموجودة في سيرفر EMIS
  static const Map<String, String> _optionEndpoints = {
    'countryOfBirth': '/selectoption/بلد الولادة',
    'nationality': '/selectoption/الجنسية',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'idType': '/selectoption/IdentificationType',
    'gender': '/selectoption/Gender',
    'motherTongue': '/selectoption/لغة',
    'maritalStatus': '/selectoption/الحالة الاجتماعية',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'educationLevel': '/selectoption/تحصیل الدراسي',
    'positionType': '/SelectOption/نوع الوظيفة',
    'specialization': '/selectoption/الإختصاص',
  };

  // القوائم الثابتة المعتمدة في ملفات النظام الأصلي (TeacherFormPage & constants)
  static final Map<String, List<Map<String, dynamic>>> _defaultStaticOptions = {
    'gender': [
      <String, dynamic>{'value': '1', 'displayName': 'ذكر'},
      <String, dynamic>{'value': '2', 'displayName': 'أنثى'},
    ],
    'idType': [
      <String, dynamic>{'value': '3', 'displayName': 'هوية الأحوال المدنية'},
      <String, dynamic>{'value': '12', 'displayName': 'البطاقة الوطنية الموحدة'},
      <String, dynamic>{'value': '22', 'displayName': 'شهادة الولادة'},
      <String, dynamic>{'value': '16', 'displayName': 'أخرى'},
    ],
    'employmentType': [
      <String, dynamic>{'value': 'ملاك', 'displayName': 'ملاك دائم'},
      <String, dynamic>{'value': 'عقد', 'displayName': 'عقد'},
      <String, dynamic>{'value': 'محاضر', 'displayName': 'محاضر'},
      <String, dynamic>{'value': 'أجر يومي', 'displayName': 'أجر يومي'},
    ],
    'employeeCategory': [
      <String, dynamic>{'value': 'تدريسي', 'displayName': 'تدريسي'},
      <String, dynamic>{'value': 'إداري', 'displayName': 'إداري'},
      <String, dynamic>{'value': 'خدمي', 'displayName': 'خدمي'},
    ],
    'status': [
      <String, dynamic>{'value': 'مستمر', 'displayName': 'مستمر'},
      <String, dynamic>{'value': 'مجاز', 'displayName': 'مجاز'},
      <String, dynamic>{'value': 'منسب', 'displayName': 'منسب'},
      <String, dynamic>{
        'value': 'مكلف او منسب من وزارة التربية الى جهات أخرى',
        'displayName': 'مكلف او منسب من وزارة التربية الى جهات أخرى'
      },
      <String, dynamic>{'value': 'سحب يد', 'displayName': 'سحب يد'},
      <String, dynamic>{'value': 'متقاعد', 'displayName': 'متقاعد'},
      <String, dynamic>{'value': 'مستقيل', 'displayName': 'مستقيل'},
    ],
    'employmentGrade': [
      <String, dynamic>{'value': 'الأولى', 'displayName': 'الأولى'},
      <String, dynamic>{'value': 'الثانية', 'displayName': 'الثانية'},
      <String, dynamic>{'value': 'الثالثة', 'displayName': 'الثالثة'},
      <String, dynamic>{'value': 'الرابعة', 'displayName': 'الرابعة'},
      <String, dynamic>{'value': 'الخامسة', 'displayName': 'الخامسة'},
      <String, dynamic>{'value': 'السادسة', 'displayName': 'السادسة'},
      <String, dynamic>{'value': 'السابعة', 'displayName': 'السابعة'},
      <String, dynamic>{'value': 'الثامنة', 'displayName': 'الثامنة'},
      <String, dynamic>{'value': 'التاسعة', 'displayName': 'التاسعة'},
      <String, dynamic>{'value': 'العاشرة', 'displayName': 'العاشرة'},
    ],
    'classification': [
      <String, dynamic>{'value': 'معلم', 'displayName': 'معلم'},
      <String, dynamic>{'value': 'معلم جامعي', 'displayName': 'معلم جامعي'},
      <String, dynamic>{'value': 'مدرس', 'displayName': 'مدرس'},
      <String, dynamic>{'value': 'مرشد تربوي', 'displayName': 'مرشد تربوي'},
      <String, dynamic>{'value': 'معلم مهني', 'displayName': 'معلم مهني'},
      <String, dynamic>{'value': 'مدرب مهني', 'displayName': 'مدرب مهني'},
      <String, dynamic>{'value': 'موظف بعقد', 'displayName': 'موظف بعقد'},
      <String, dynamic>{'value': 'محاضر بعقد', 'displayName': 'محاضر بعقد'},
      <String, dynamic>{'value': 'إداري', 'displayName': 'إداري'},
      <String, dynamic>{'value': 'موظف خدمة', 'displayName': 'موظف خدمة'},
      <String, dynamic>{'value': 'حارس', 'displayName': 'حارس'},
    ],
    'currentPosition': [
      <String, dynamic>{'value': 'مدير', 'displayName': 'مدير'},
      <String, dynamic>{'value': 'معاون', 'displayName': 'معاون'},
      <String, dynamic>{'value': 'معلم', 'displayName': 'معلم'},
      <String, dynamic>{'value': 'مدرس', 'displayName': 'مدرس'},
      <String, dynamic>{'value': 'مرشد تربوي', 'displayName': 'مرشد تربوي'},
      <String, dynamic>{'value': 'كاتب', 'displayName': 'كاتب'},
      <String, dynamic>{'value': 'أمين مكتبة', 'displayName': 'أمين مكتبة'},
      <String, dynamic>{'value': 'محاسب', 'displayName': 'محاسب'},
      <String, dynamic>{'value': 'موظف خدمة', 'displayName': 'موظف خدمة'},
      <String, dynamic>{'value': 'حارس ليلي', 'displayName': 'حارس ليلي'},
    ],
    'educationLevel': [
      <String, dynamic>{'value': 'ابتدائية', 'displayName': 'ابتدائية'},
      <String, dynamic>{'value': 'متوسطة', 'displayName': 'متوسطة'},
      <String, dynamic>{'value': 'إعدادية', 'displayName': 'إعدادية'},
      <String, dynamic>{'value': 'دبلوم', 'displayName': 'دبلوم'},
      <String, dynamic>{'value': 'بكالوريوس', 'displayName': 'بكالوريوس'},
      <String, dynamic>{'value': 'دبلوم عالي', 'displayName': 'دبلوم عالي'},
      <String, dynamic>{'value': 'ماجستير', 'displayName': 'ماجستير'},
      <String, dynamic>{'value': 'دكتوراه', 'displayName': 'دكتوراه'},
    ],
    'specialization': [
      <String, dynamic>{'value': 'التربية الإسلامية', 'displayName': 'التربية الإسلامية'},
      <String, dynamic>{'value': 'اللغة العربية', 'displayName': 'اللغة العربية'},
      <String, dynamic>{'value': 'اللغة الإنكليزية', 'displayName': 'اللغة الإنكليزية'},
      <String, dynamic>{'value': 'الرياضيات', 'displayName': 'الرياضيات'},
      <String, dynamic>{'value': 'العلوم', 'displayName': 'العلوم'},
      <String, dynamic>{'value': 'الفيزياء', 'displayName': 'الفيزياء'},
      <String, dynamic>{'value': 'الكيمياء', 'displayName': 'الكيمياء'},
      <String, dynamic>{'value': 'الأحياء', 'displayName': 'الأحياء'},
      <String, dynamic>{'value': 'التاريخ', 'displayName': 'التاريخ'},
      <String, dynamic>{'value': 'الجغرافية', 'displayName': 'الجغرافية'},
      <String, dynamic>{'value': 'الاجتماعيات', 'displayName': 'الاجتماعيات'},
      <String, dynamic>{'value': 'التربية الفنية', 'displayName': 'التربية الفنية'},
      <String, dynamic>{'value': 'التربية الرياضية', 'displayName': 'التربية الرياضية'},
      <String, dynamic>{'value': 'الحاسوب', 'displayName': 'الحاسوب'},
      <String, dynamic>{'value': 'الإرشاد التربوي', 'displayName': 'الإرشاد التربوي'},
      <String, dynamic>{'value': 'معلم صفوف أولية', 'displayName': 'معلم صفوف أولية'},
      <String, dynamic>{'value': 'اللغة الكردية', 'displayName': 'اللغة الكردية'},
      <String, dynamic>{'value': 'اللغة الفرنسية', 'displayName': 'اللغة الفرنسية'},
      <String, dynamic>{'value': 'التربية الخاصة', 'displayName': 'التربية الخاصة'},
      <String, dynamic>{'value': 'أخرى', 'displayName': 'أخرى'},
    ],
    'motherTongue': [
      <String, dynamic>{'value': 'العربية', 'displayName': 'العربية'},
      <String, dynamic>{'value': 'الكردية', 'displayName': 'الكردية'},
      <String, dynamic>{'value': 'التركمانية', 'displayName': 'التركمانية'},
      <String, dynamic>{'value': 'السريانية', 'displayName': 'السريانية'},
      <String, dynamic>{'value': 'أخرى', 'displayName': 'أخرى'},
    ],
    'maritalStatus': [
      <String, dynamic>{'value': 'أعزب', 'displayName': 'أعزب'},
      <String, dynamic>{'value': 'متزوج', 'displayName': 'متزوج'},
      <String, dynamic>{'value': 'مطلق', 'displayName': 'مطلق'},
      <String, dynamic>{'value': 'أرمل', 'displayName': 'أرمل'},
    ],
    'bloodGroup': [
      <String, dynamic>{'value': 'A+', 'displayName': 'A+'},
      <String, dynamic>{'value': 'A-', 'displayName': 'A-'},
      <String, dynamic>{'value': 'B+', 'displayName': 'B+'},
      <String, dynamic>{'value': 'B-', 'displayName': 'B-'},
      <String, dynamic>{'value': 'AB+', 'displayName': 'AB+'},
      <String, dynamic>{'value': 'AB-', 'displayName': 'AB-'},
      <String, dynamic>{'value': 'O+', 'displayName': 'O+'},
      <String, dynamic>{'value': 'O-', 'displayName': 'O-'},
    ],
    'religion': [
      <String, dynamic>{'value': 'الإسلام', 'displayName': 'الإسلام'},
      <String, dynamic>{'value': 'المسيحية', 'displayName': 'المسيحية'},
      <String, dynamic>{'value': 'الأزيدية', 'displayName': 'الأزيدية'},
      <String, dynamic>{'value': 'الصابئة المندائية', 'displayName': 'الصابئة المندائية'},
      <String, dynamic>{'value': 'أخرى', 'displayName': 'أخرى'},
    ],
    'countryOfBirth': [
      <String, dynamic>{'value': 'العراق', 'displayName': 'العراق'},
    ],
    'nationality': [
      <String, dynamic>{'value': 'العراق', 'displayName': 'العراق'},
    ],
    'issuingCountry': [
      <String, dynamic>{'value': 'العراق', 'displayName': 'العراق'},
    ],
  };

  final Map<String, String> labels = const <String, String>{
    'name': 'الإسم *',
    'fatherName': 'إسم الأب *',
    'grandFatherName': 'اسم والد الأب *',
    'fathersGrandFatherName': 'اسم جد الأب *',
    'surName': 'اللقب *',
    'motherName': 'إسم الأم *',
    'mothersFatherName': 'اسم والد الأم *',
    'mothersGrandFatherName': 'اسم جد الأم *',
    'nationalId': 'رقم الوثيقة / البطاقة الوطنية *',
    'nameOfDocument': 'نوع الوثيقة *',
    'recordNumber': 'رقم السجل *',
    'pageNumber': 'رقم الصحيفة *',
    'issuer': 'جهة الإصدار',
    'issuingDate': 'تاريخ الإصدار *',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'idType': 'نوع الهوية *',
    'issuingCountry': 'بلد الإصدار *',
    'dateOfBirth': 'تاريخ التولد *',
    'gender': 'الجنس *',
    'nationality': 'الجنسية *',
    'countryOfBirth': 'محل الولادة',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم *',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة *',
    'employmentType': 'نوع التوظيف *',
    'employeeCategory': 'نوع الموظف *',
    'classification': 'التصنيف *',
    'jobDesignation': 'المسمى الوظيفي',
    'positionType': 'العنوان الوظيفي *',
    'employmentGrade': 'الدرجة الوظيفية',
    'weeklyTeachingQuota': 'النصاب الأسبوعي للحصص',
    'dateOfStartWorking': 'تاريخ أول تعيين للموظف *',
    'currentPosition': 'المنصب الحالي *',
    'status': 'الحالة الوظيفية *',
    'statusDate': 'تاريخ سريان الحالة الوظيفية',
    'statusReason': 'سبب الحالة الوظيفية *',
    'assignedEntityName': 'الجهة المنسب أو المكلف إليها *',
    'educationLevel': 'التحصيل الدراسي *',
    'universityName': 'إسم الكلية / المعهد',
    'graduationYear': 'سنة التخرج',
    'specialization': 'الإختصاص *',
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة إن وجدت',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال في الحالات الطارئة',
    'town': 'المدينة / القرية *',
    'area': 'الحي *',
    'quarter': 'المحلة *',
    'street': 'الزقاق *',
    'address1': 'عنوان 1 *',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة *',
    'mobilePhoneNumber': 'رقم هاتف المعلم *',
    'email': 'البريد الإلكتروني',
    'notes': 'ملاحظات',
    'addressCountry': 'الدولة',
    'addressGovernorate': 'المحافظة',
    'addressDistrict': 'القضاء / الناحية *',
  };

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _initStaticOptions();
    for (final key in labels.keys) {
      c[key] = TextEditingController();
    }
    // القيم الافتراضية المعتمدة في نظام EMIS عند فتح نموذج إضافة معلم
    c['nationality']!.text = 'العراق';
    c['issuingCountry']!.text = 'العراق';
    c['countryOfBirth']!.text = 'العراق';
    c['idType']!.text = '12';
    c['gender']!.text = '1';
    c['motherTongue']!.text = 'العربية';
    c['religion']!.text = 'الإسلام';
    c['status']!.text = 'مستمر';
    c['employeeCategory']!.text = 'تدريسي';
    c['employmentType']!.text = 'ملاك';
    c['classification']!.text = 'معلم';
    c['currentPosition']!.text = 'مدرس';
    c['educationLevel']!.text = 'بكالوريوس';

    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _load();
  }

  void _initStaticOptions() {
    for (final entry in _defaultStaticOptions.entries) {
      options[entry.key] = entry.value
          .map((item) => <String, dynamic>{
                'value': item['value'],
                'displayName': item['displayName'],
              })
          .toList();
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    final segmenter = _selfieSegmenter;
    _selfieSegmenter = null;
    if (segmenter != null) segmenter.close();
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in labels.entries)
          entry.key: <String>[
            entry.key,
            entry.value.replaceAll(' *', '').trim(),
            entry.value,
          ],
        'idNumber': ['nationalId', 'رقم البطاقة الوطنية الموحدة', 'رقم الوثيقة'],
        'addressCountry': ['addressCountry', 'الدولة', 'country'],
        'addressGovernorate': ['addressGovernorate', 'المحافظة', 'governorate'],
        'addressDistrict': ['addressDistrict', 'القضاء', 'district'],
        'countryStructureId': ['countryStructureId', 'الموقع الجغرافي'],
      };

  Map<String, String> _liveValues() => {
        for (final entry in c.entries) entry.key: entry.value.text,
        'idNumber': c['nationalId']?.text ?? '',
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
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    bool changed = false;
    for (final entry in values.entries) {
      final targetKey = entry.key == 'idNumber' ? 'nationalId' : entry.key;
      final controller = c[targetKey];
      if (controller != null && controller.text != entry.value) {
        controller.value = TextEditingValue(
          text: entry.value,
          selection: TextSelection.collapsed(offset: entry.value.length),
        );
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _applyLiveOptions(Map<String, List<Map<String, dynamic>>> incoming) {
    bool changed = false;
    incoming.forEach((key, values) {
      if (values.isEmpty) return;
      final existing = options[key] ?? <Map<String, dynamic>>[];
      final merged = <Map<String, dynamic>>[
        ...existing.where((o) => o['_liveOnly'] != true)
      ];
      for (final option in values) {
        final value = option['value'] ??
            option['id'] ??
            option['displayName'] ??
            option['label'];
        final label = option['displayName'] ??
            option['label'] ??
            option['text'] ??
            value;
        if ('$value'.trim().isEmpty) continue;
        if (!merged.any((o) =>
            '${o['value'] ?? o['id'] ?? ''}' == '$value' ||
            '${o['displayName'] ?? o['label'] ?? ''}' == '$label')) {
          merged.add(<String, dynamic>{
            'value': value,
            'displayName': label,
            '_liveOnly': true,
          });
        }
      }
      options[key] = merged;
      changed = true;
    });
    if (changed && mounted) setState(() {});
  }

  dynamic _unwrap(dynamic d) =>
      d is Map && d['data'] != null ? d['data'] : d;

  Future<dynamic> _get(String endpoint) async {
    final encodedUrl = Uri.encodeFull('https://emis.moedu.gov.iq/api$endpoint');
    final response = await http.get(
      Uri.parse(encodedUrl),
      headers: h,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Map<String, dynamic>>> _list(String endpoint) async {
    try {
      final raw = _unwrap(await _get(endpoint));
      if (raw is! List) return <Map<String, dynamic>>[];
      final result = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          result.add(item.map((k, v) => MapEntry(k.toString(), v)));
        } else if (item != null) {
          final s = item.toString().trim();
          if (s.isNotEmpty) {
            result.add(<String, dynamic>{'value': s, 'displayName': s});
          }
        }
      }
      return result;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  String _value(Map<String, dynamic> x) =>
      '${x['value'] ?? x['id'] ?? x['code'] ?? ''}'.trim();

  String _text(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? _value(x)}'.trim();

  Future<void> _load() async {
    try {
      // إظهار الواجهة فوراً بالخيارات الثابتة ثم تحديث الخيارات من السيرفر
      if (mounted) setState(() => loading = false);

      for (final entry in _optionEndpoints.entries) {
        final fetched = await _list(entry.key == 'positionType'
            ? '/SelectOption/نوع الوظيفة'
            : entry.value);
        if (fetched.isNotEmpty) {
          final existing = options[entry.key] ?? <Map<String, dynamic>>[];
          final merged = <Map<String, dynamic>>[...fetched];
          for (final ex in existing) {
            final v = _value(ex);
            if (v.isNotEmpty && !merged.any((m) => _value(m) == v)) {
              merged.add(ex);
            }
          }
          options[entry.key] = merged;
        }
      }

      await _loadEmployeesOptions();
      await _loadCountryStructure();

      if ((options['positionType'] ?? []).isNotEmpty &&
          c['positionType']!.text.trim().isEmpty) {
        c['positionType']!.text = _value(options['positionType']!.first);
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('خطأ أثناء تحميل الخيارات المساندة: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadEmployeesOptions() async {
    try {
      final decoded = await _get('/employee/getemployeesoptions');
      if (decoded is! Map) return;

      void mergeSimple(String key, dynamic raw) {
        if (raw is! List) return;
        final existing = options[key] ?? <Map<String, dynamic>>[];
        final parsed = <Map<String, dynamic>>[];
        for (final item in raw) {
          if (item is Map) {
            final v = '${item['value'] ?? item['label'] ?? ''}'.trim();
            final t = '${item['label'] ?? item['displayName'] ?? v}'.trim();
            if (v.isNotEmpty) {
              parsed.add(<String, dynamic>{'value': v, 'displayName': t});
            }
          } else if (item != null) {
            final s = '$item'.trim();
            if (s.isNotEmpty) {
              parsed.add(<String, dynamic>{'value': s, 'displayName': s});
            }
          }
        }
        for (final ex in existing) {
          final v = _value(ex);
          if (v.isNotEmpty && !parsed.any((p) => _value(p) == v)) {
            parsed.add(ex);
          }
        }
        if (parsed.isNotEmpty) options[key] = parsed;
      }

      mergeSimple('classification', decoded['classification']);
      mergeSimple('status', decoded['currentemploymentstatus']);
    } catch (_) {}
  }

  Future<void> _loadCountryStructure() async {
    try {
      final list = await _list('/CountryStructure/getcountrystructure');
      if (list.isEmpty) return;
      _addressCountries = list;
      Map<String, dynamic>? iraq;
      for (final item in list) {
        if (_text(item).contains('العراق') ||
            _text(item).toLowerCase() == 'iraq') {
          iraq = item;
          break;
        }
      }
      iraq ??= list.first;
      _addressCountryId = _value(iraq);
      _addressGovernorates = _childrenOf(iraq);

      // اختيار محافظة القادسية افتراضياً إن وجدت لتسهيل الإدخال
      for (final gov in _addressGovernorates) {
        if (_text(gov).contains('القادسية') || _text(gov).contains('الديوانية')) {
          _addressGovernorateId = _value(gov);
          _addressDistricts = _childrenOf(gov);
          if (_addressDistricts.isNotEmpty) {
            _addressDistrictId = _value(_addressDistricts.first);
          }
          break;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
    final raw =
        node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  void _setAddressGovernorates(Map<String, dynamic> country) {
    _addressGovernorates = _childrenOf(country);
    _addressGovernorateId = null;
    _addressDistricts = [];
    _addressDistrictId = null;
  }

  void _setAddressDistricts(Map<String, dynamic> governorate) {
    _addressDistricts = _childrenOf(governorate);
    _addressDistrictId =
        _addressDistricts.isNotEmpty ? _value(_addressDistricts.first) : null;
  }

  // ==================== معالجة ورفع الصورة الشخصية ====================
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
          '${imageFile.path}_seg_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await normalizedFile.writeAsBytes(img.encodeJpg(source, quality: 90),
          flush: true);

      final mask = await segmenter.processImage(
        InputImage.fromFilePath(normalizedFile.path),
      );
      if (mask == null ||
          mask.width <= 0 ||
          mask.height <= 0 ||
          mask.confidences.isEmpty) {
        throw Exception('لم يتم الحصول على قناع صالح للشخص');
      }

      final result =
          img.Image(width: source.width, height: source.height, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final index = y * source.width + x;
          final confidence = mask.confidences[index].clamp(0.0, 1.0);
          final alpha =
              ((confidence - 0.35) / 0.40 * 255.0).round().clamp(0, 255);
          final pixel = source.getPixel(x, y);
          result.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
        }
      }

      final output = File(
          '${imageFile.path}_nobg_${DateTime.now().millisecondsSinceEpoch}.png');
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (picked != null && mounted) {
        await _showImagePreviewDialog(File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذر اختيار الصورة: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showImagePreviewDialog(File imageFile) async {
    File currentImage = imageFile;
    bool processing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('معاينة صورة المعلم',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                        child: Image.file(currentImage, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (processing)
                      const CircularProgressIndicator()
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            setDialogState(() => processing = true);
                            try {
                              final processed =
                                  await _removeBackgroundUsingSelfieSegmentation(
                                      currentImage);
                              if (processed != null && mounted) {
                                setDialogState(() {
                                  currentImage = processed;
                                  processing = false;
                                });
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setDialogState(() => processing = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('تعذر إزالة الخلفية: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          },
                          icon: const Icon(Icons.auto_fix_high,
                              color: Colors.black87),
                          label: const Text('حذف الخلفية',
                              style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amberAccent),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      processing ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: processing
                      ? null
                      : () {
                          setState(() => _pickedImage = currentImage);
                          Navigator.pop(dialogContext);
                        },
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('اعتماد',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _uploadImageToEmisServer(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://emis.moedu.gov.iq/api/employee/uploadimage'),
    );
    request.headers['Authorization'] = widget.token;
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath(
      'image',
      imageFile.path,
      filename: 'teacher.png',
    ));
    try {
      final streamed = await request.send();
      final responseData = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final jsonResponse = jsonDecode(responseData);
        if (jsonResponse is Map) return jsonResponse['imageUrl']?.toString();
      }
    } catch (e) {
      debugPrint('خطأ في رفع الصورة: $e');
    }
    return null;
  }

  // ==================== عناصر الواجهة والحقول ====================
  String _formatTypedDate(String value) {
    final digits = value
        .replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '')
        .replaceAllMapped(RegExp('[٠-٩]'),
            (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x0660 + 48))
        .replaceAllMapped(RegExp('[۰-۹]'),
            (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x06F0 + 48));
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    var out = limited.substring(0, limited.length >= 4 ? 4 : limited.length);
    if (limited.length > 4) {
      out += '-${limited.substring(4, limited.length >= 6 ? 6 : limited.length)}';
    }
    if (limited.length > 6) out += '-${limited.substring(6)}';
    return out;
  }

  bool _isDateKey(String key) => <String>{
        'dateOfBirth',
        'dateOfStartWorking',
        'statusDate',
        'issuingDate',
        'graduationYear',
      }.contains(key);

  Widget _addressDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final safe = items.any((x) => _value(x) == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safe,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
      style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: isDark ? Colors.black12 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
      ),
      items: items
          .map((x) => DropdownMenuItem<String>(
                value: _value(x),
                child: Text(
                  _text(x),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  List<Map<String, dynamic>> _values(String key) {
    final raw = options[key] ?? <Map<String, dynamic>>[];
    final unique = <Map<String, dynamic>>[];

    for (final item in raw) {
      final v = _value(item);
      if (v.isNotEmpty && !unique.any((u) => _value(u) == v)) {
        unique.add(item);
      }
    }

    final current = c[key]?.text.trim() ?? '';
    if (current.isNotEmpty && !unique.any((x) => _value(x) == current)) {
      unique.insert(0, <String, dynamic>{
        'value': current,
        'displayName': current,
      });
    }
    return unique;
  }

  Widget _textField(
    String key, {
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDate = _isDateKey(key);
    return TextFormField(
      controller: c[key],
      keyboardType: isDate ? TextInputType.number : keyboard,
      maxLines: maxLines,
      textDirection: TextDirection.rtl,
      inputFormatters: isDate
          ? [
              TextInputFormatter.withFunction((oldVal, newVal) {
                final formatted = _formatTypedDate(newVal.text);
                return TextEditingValue(
                  text: formatted,
                  selection: TextSelection.collapsed(offset: formatted.length),
                );
              }),
            ]
          : null,
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        hintText: isDate ? 'YYYY-MM-DD' : null,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: isDark ? Colors.black12 : Colors.white,
        suffixIcon: isDate
            ? IconButton(
                tooltip: 'اختر من التقويم',
                icon: const Icon(Icons.calendar_month),
                onPressed: () => _pickDate(key),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
      ),
      style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
      onChanged: (_) => _liveSyncKey.currentState?.pushValues(_liveValues()),
      onTap: () => _focusLive(key),
    );
  }

  Future<void> _pickDate(String key) async {
    final raw = c[key]?.text.trim() ?? '';
    final parsed = DateTime.tryParse(raw);
    final initial = parsed != null &&
            parsed.isAfter(DateTime(1900)) &&
            parsed.isBefore(DateTime(2100))
        ? parsed
        : DateTime(1990, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: labels[key],
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    c[key]!.text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    _focusLive(key);
    setState(() {});
  }

  Widget _select(
    String key, {
    bool required = false,
    List<String> fallback = const [],
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final values = _values(key);
    for (final x in fallback) {
      if (!values.any((v) => _value(v) == x)) {
        values.add(<String, dynamic>{'value': x, 'displayName': x});
      }
    }

    final current = c[key]!.text.trim();
    final safeValue = values.any((x) => _value(x) == current) ? current : null;

    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
      style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16),
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: isDark ? Colors.black12 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE1E6EF)),
        ),
      ),
      items: values
          .map(
            (x) => DropdownMenuItem<String>(
              value: _value(x),
              child: Text(
                _text(x),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
            ),
          )
          .where((x) => x.value != null && x.value!.isNotEmpty)
          .toList(),
      onTap: () => _focusLive(key),
      onChanged: (v) {
        setState(() {
          c[key]!.text = v ?? '';
          if (key == 'employmentType') {
            if (v == 'ملاك') c['classification']!.text = 'معلم';
            if (v == 'عقد') c['classification']!.text = 'موظف بعقد';
          }
        });
        _focusLive(key);
        if (key == 'employmentType') {
          _liveSyncKey.currentState?.refreshOptions(['classification']);
        }
      },
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
    );
  }

  Widget _section(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
  }

  // ==================== الحفظ والإرسال إلى EMIS ====================
  void _flattenToFormFields(
    Map<String, String> target,
    String prefix,
    dynamic value,
  ) {
    if (value == null) return;
    if (value is Map) {
      value.forEach((k, v) {
        final nextKey =
            prefix.isEmpty ? k.toString() : '$prefix.${k.toString()}';
        _flattenToFormFields(target, nextKey, v);
      });
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _flattenToFormFields(target, '$prefix[$i]', value[i]);
      }
    } else {
      target[prefix] = value.toString();
    }
  }

  Future<http.Response> _sendAddRequest(Map<String, dynamic> payload) async {
    final uri = Uri.parse('https://emis.moedu.gov.iq/api/employee/addemployee');
    final jsonString = jsonEncode(payload);

    // 1. المحاولة الأولى: POST بصيغة application/json (الطريقة الرسمية في store-B4UkWgHd.js)
    var response = await http.post(
      uri,
      headers: {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonString,
    );
    if (response.statusCode != 415 && response.statusCode != 405) {
      return response;
    }

    // 2. المحاولة الثانية: POST بصيغة multipart/form-data في حال طلب السيرفر FromForm
    final multipart = http.MultipartRequest('POST', uri);
    multipart.headers['Authorization'] = widget.token;
    multipart.headers['Accept'] = 'application/json';
    _flattenToFormFields(multipart.fields, '', payload);
    multipart.fields['emp'] = jsonString;
    final streamed = await multipart.send();
    return await http.Response.fromStream(streamed);
  }

  String? _dateOnly(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final v = raw.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(v);
    if (iso != null) {
      return '${iso.group(1)!.padLeft(4, '0')}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
    }
    if (RegExp(r'^\d{4}$').hasMatch(v)) {
      return '$v-01-01';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إكمال جميع الحقول المطلوبة المعلّمة بـ (*)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {
      // 1. رفع الصورة الشخصية إن تم اختيارها
      if (_pickedImage != null) {
        final uploaded = await _uploadImageToEmisServer(_pickedImage!);
        if (uploaded != null && uploaded.isNotEmpty) {
          _uploadedImageUrl = uploaded;
        }
      }

      // 2. التحقق من عدم تكرار رقم الهوية أو الرقم الوظيفي
      final idNumber = c['nationalId']!.text.trim();
      final idType = int.tryParse(c['idType']!.text.trim()) ?? 12;

      if (idType == 12 && idNumber.isNotEmpty) {
        try {
          final check = await _get(
            '/employee/checknationalidnumber?value=${Uri.encodeQueryComponent(idNumber)}',
          );
          if (check is Map && check['isUnique'] == false) {
            throw Exception('رقم البطاقة الوطنية الموحدة مسجل مسبقاً لمعلم آخر');
          }
        } catch (e) {
          if (e.toString().contains('مسجل مسبقاً')) rethrow;
        }
      }

      final empIdNum = c['employeeIdNumber']!.text.trim();
      if (empIdNum.isNotEmpty) {
        try {
          final checkEmp = await _get(
            '/employee/checkemployeeidnumber?employeeIdNumber=${Uri.encodeQueryComponent(empIdNum)}',
          );
          if (checkEmp is Map && checkEmp['isUnique'] == false) {
            throw Exception('الرقم الوظيفي مسجل مسبقاً لمعلم آخر');
          }
        } catch (e) {
          if (e.toString().contains('مسجل مسبقاً')) rethrow;
        }
      }

      final todayIso = DateTime.now().toIso8601String().split('T').first;
      final quota = int.tryParse(c['weeklyTeachingQuota']?.text.trim() ?? '');
      final empStatus = _n('status') ?? 'مستمر';
      final schoolIdInt = int.tryParse(widget.schoolId) ?? 1;
      final structureIdInt =
          int.tryParse(_addressDistrictId ?? _addressGovernorateId ?? '1') ?? 1;

      // 3. بناء الـ Payload مطابقاً تماماً لدالة X() في TeacherFormPage.js
      final payload = <String, dynamic>{
        'EmployeeIdNumber': empIdNum,
        'FamilyNumber': _n('familyNumber'),
        'IsTeacher': true,
        'EmploymentType': _n('employmentType'),
        'EmployeeCategory': _n('employeeCategory'),
        'Classification': _n('classification'),
        'JobDesignation': _n('jobDesignation'),
        'EmploymentGrade': _n('employmentGrade'),
        'WeeklyTeachingQuota': quota,
        'DateOfStartWorking':
            _dateOnly(_n('dateOfStartWorking')) ?? todayIso,
        'EducationLevel': _n('educationLevel') ?? 'ابتدائية',
        'GraduationYear': _dateOnly(_n('graduationYear')),
        'UniversityName': _n('universityName'),
        'Specialization': _n('specialization') ?? '',
        'Name': _n('name') ?? '',
        'FatherName': _n('fatherName') ?? '',
        'GrandFatherName': _n('grandFatherName') ?? '',
        'FathersGrandFatherName': _n('fathersGrandFatherName') ?? '',
        'SurName': _n('surName') ?? '',
        'MotherName': _n('motherName') ?? '',
        'MothersFatherName': _n('mothersFatherName') ?? '',
        'MothersGrandFatherName': _n('mothersGrandFatherName') ?? '',
        'ImageUrl': _uploadedImageUrl,
        'DateOfBirth': _dateOnly(_n('dateOfBirth')) ?? todayIso,
        'Gender': int.tryParse(c['gender']!.text.trim()) ?? 1,
        'Nationality': _n('nationality') ?? 'العراق',
        'CountryOfBirth': _n('countryOfBirth') ?? 'العراق',
        'HomeTown': _n('homeTown') ?? '',
        'IdentificationId': 0,
        'Identification': <String, dynamic>{
          'IdNumber': idNumber,
          'IssuingCountry': _n('issuingCountry') ?? 'العراق',
          'IdType': idType,
          'nameOfDocument': _n('nameOfDocument'),
          'recordNumber': _n('recordNumber'),
          'pageNumber': _n('pageNumber'),
          'issuer': _n('issuer'),
          'issuingDate': _dateOnly(_n('issuingDate')),
        },
        'FatherIdentificationId': null,
        'FatherIdentification': null,
        'MotherTongue': _n('motherTongue') ?? 'العربية',
        'MaritalStatus': _n('maritalStatus') ?? '',
        'BloodGroup': _n('bloodGroup') ?? '',
        'Religion': _n('religion') ?? 'الإسلام',
        'HomePhoneNumber': '',
        'Status': 1,
        'Notes': _n('notes') ?? '',
        'SpecialNeedsInformation': _n('specialNeedsInformation'),
        'EmergencyContactName': _n('emergencyContactName'),
        'EmergencyContactRelationship': _n('emergencyContactRelationship'),
        'EmergencyContactPhoneNumber': _n('emergencyContactPhoneNumber'),
        'Address': <String, dynamic>{
          'AddressType': 1,
          'Town': _n('town') ?? '',
          'Area': _n('area') ?? '',
          'Quarter': _n('quarter') ?? '',
          'Street': _n('street') ?? '',
          'ClosestLocation': _n('closestLocation') ?? '',
          'countryStructureId': structureIdInt,
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
        'AgeExceptionReason': null,
        'AgeExceptionAttachmentUrl': null,
        'ageExceptionAttachment': null,
        'EmploymentRecord': <String, dynamic>{
          'EmploymentStatuses': <Map<String, dynamic>>[
            <String, dynamic>{
              'StatusType': empStatus,
              'DisEngagementDate': null,
              'MinistryOfficialDocumentNumber': null,
              'Reason': _n('statusReason'),
              'AssignedEntityName': _n('assignedEntityName'),
              'CurrentBelongToEntityId': schoolIdInt,
            }
          ],
          'EmploymentPositions': <Map<String, dynamic>>[
            <String, dynamic>{
              'Position': _n('currentPosition') ?? '',
              'InitiateDate':
                  _dateOnly(_n('dateOfStartWorking')) ?? todayIso,
            }
          ],
          'IsCurrentlyActive': empStatus == 'مستمر',
          'CurrentBelongToEntityId': schoolIdInt,
          'CurrentEmploymentPosition': _n('positionType') ?? '',
        },
      };

      final response = await _sendAddRequest(payload);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'فشل الإضافة (HTTP ${response.statusCode}):\n${utf8.decode(response.bodyBytes)}',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة المعلم بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text('$e', maxLines: 5, overflow: TextOverflow.ellipsis),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String? _n(String key) {
    final value = c[key]?.text.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  List<Widget> _buildDynamicIdFields() {
    final idType = int.tryParse(c['idType']?.text.trim() ?? '12') ?? 12;
    if (idType == 3) {
      // هوية الأحوال المدنية
      return [
        _textField('nationalId', required: true),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _textField('recordNumber', required: true)),
            const SizedBox(width: 10),
            Expanded(child: _textField('pageNumber', required: true)),
          ],
        ),
        const SizedBox(height: 10),
        _textField('issuer'),
      ];
    } else if (idType == 22) {
      // شهادة الولادة
      return [
        Row(
          children: [
            Expanded(child: _textField('nationalId', required: true)),
            const SizedBox(width: 10),
            Expanded(child: _textField('issuingDate', required: true)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _textField('recordNumber', required: true)),
            const SizedBox(width: 10),
            Expanded(child: _textField('pageNumber', required: true)),
          ],
        ),
      ];
    } else if (idType == 16) {
      // وثيقة أخرى
      return [
        Row(
          children: [
            Expanded(child: _textField('nameOfDocument', required: true)),
            const SizedBox(width: 10),
            Expanded(child: _textField('nationalId', required: true)),
          ],
        ),
      ];
    } else {
      // البطاقة الوطنية الموحدة (12)
      return [
        _textField(
          'nationalId',
          required: true,
          keyboard: TextInputType.number,
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final eduLevel = c['educationLevel']?.text.trim() ?? '';
    final showUniv = eduLevel == 'دبلوم' || eduLevel == 'بكالوريوس';
    final showSpec =
        !const ['ابتدائية', 'متوسطة', 'إعدادية'].contains(eduLevel);
    final empStatus = c['status']?.text.trim() ?? 'مستمر';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
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
                        // قسم الصورة الشخصية
                        Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: const Color(0xFF4527A0), width: 3),
                                ),
                                child: ClipOval(
                                  child: _pickedImage != null
                                      ? Image.file(_pickedImage!,
                                          fit: BoxFit.cover)
                                      : Icon(Icons.person,
                                          size: 75, color: Colors.grey[400]),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  radius: 19,
                                  child: IconButton(
                                    icon: const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 17),
                                    onPressed: () =>
                                        _pickImage(ImageSource.camera),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                child: CircleAvatar(
                                  backgroundColor: Colors.green,
                                  radius: 19,
                                  child: IconButton(
                                    icon: const Icon(Icons.photo_library,
                                        color: Colors.white, size: 17),
                                    onPressed: () =>
                                        _pickImage(ImageSource.gallery),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _section('البيانات الشخصية والاسم الكامل', [
                          _textField('name', required: true),
                          const SizedBox(height: 10),
                          _textField('fatherName', required: true),
                          const SizedBox(height: 10),
                          _textField('grandFatherName', required: true),
                          const SizedBox(height: 10),
                          _textField('fathersGrandFatherName', required: true),
                          const SizedBox(height: 10),
                          _textField('surName', required: true),
                          const SizedBox(height: 10),
                          _textField('motherName', required: true),
                          const SizedBox(height: 10),
                          _textField('mothersFatherName', required: true),
                          const SizedBox(height: 10),
                          _textField('mothersGrandFatherName', required: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _select('gender', required: true)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _textField('dateOfBirth',
                                      required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _select('countryOfBirth')),
                              const SizedBox(width: 10),
                              Expanded(
                                  child:
                                      _select('nationality', required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField('homeTown'),
                        ]),
                        _section('الهوية والوثائق الرسمية', [
                          Row(
                            children: [
                              Expanded(
                                child: _select('idType', required: true),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _select(
                                  'issuingCountry',
                                  required: true,
                                  fallback: const ['العراق'],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ..._buildDynamicIdFields(),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _textField('employeeIdNumber')),
                              const SizedBox(width: 10),
                              Expanded(child: _textField('familyNumber')),
                            ],
                          ),
                        ]),
                        _section('البيانات الوظيفية', [
                          Row(
                            children: [
                              Expanded(
                                  child: _select('employmentType',
                                      required: true)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _select('employeeCategory',
                                      required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child: _select('classification',
                                      required: true)),
                              const SizedBox(width: 10),
                              Expanded(child: _textField('jobDesignation')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _select('employmentGrade')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _textField(
                                  'weeklyTeachingQuota',
                                  keyboard: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      _select('positionType', required: true)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _select('currentPosition',
                                      required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField('dateOfStartWorking', required: true),
                          const SizedBox(height: 12),
                          _section('الحالة الوظيفية', [
                            _select('status', required: true),
                            if (empStatus != 'مستمر') ...[
                              const SizedBox(height: 10),
                              _textField('statusReason',
                                  required: true, maxLines: 2),
                            ],
                            if (empStatus ==
                                'مكلف او منسب من وزارة التربية الى جهات أخرى') ...[
                              const SizedBox(height: 10),
                              _textField('assignedEntityName', required: true),
                            ],
                          ]),
                          const SizedBox(height: 10),
                          _select('educationLevel', required: true),
                          if (showUniv) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _textField('universityName')),
                                const SizedBox(width: 10),
                                Expanded(child: _textField('graduationYear')),
                              ],
                            ),
                          ],
                          if (showSpec) ...[
                            const SizedBox(height: 10),
                            _select('specialization', required: true),
                          ],
                        ]),
                        _section('البيانات الاجتماعية', [
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      _select('motherTongue', required: true)),
                              const SizedBox(width: 10),
                              Expanded(child: _select('maritalStatus')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _select('bloodGroup')),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _select('religion', required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField('specialNeedsInformation', maxLines: 2),
                          const SizedBox(height: 10),
                          _textField('notes', maxLines: 3),
                        ]),
                        _section('بيانات الاتصال في الحالات الطارئة', [
                          _textField('emergencyContactName'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child: _textField(
                                      'emergencyContactRelationship')),
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
                        _section('العنوان ومعلومات الاتصال', [
                          _addressDropdown(
                            label: 'الدولة',
                            value: _addressCountryId,
                            items: _addressCountries,
                            onChanged: (v) {
                              final item = _addressCountries
                                  .where((x) => _value(x) == v)
                                  .toList();
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
                              final item = _addressGovernorates
                                  .where((x) => _value(x) == v)
                                  .toList();
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
                            label: 'القضاء / الناحية *',
                            value: _addressDistrictId,
                            items: _addressDistricts,
                            onChanged: (v) {
                              setState(() => _addressDistrictId = v);
                              _focusLive('addressDistrict');
                            },
                          ),
                          const SizedBox(height: 10),
                          _textField('town', required: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child: _textField('area', required: true)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _textField('quarter', required: true)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField('street', required: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      _textField('address1', required: true)),
                              const SizedBox(width: 10),
                              Expanded(child: _textField('address2')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _textField('closestLocation', required: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _textField(
                                  'mobilePhoneNumber',
                                  required: true,
                                  keyboard: TextInputType.phone,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _textField(
                                  'email',
                                  keyboard: TextInputType.emailAddress,
                                ),
                              ),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text(
                              'حفظ المعلم',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 17),
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
                url:
                    'https://emis.moedu.gov.iq/centers/schools/${widget.schoolId}/individuals/teachers/management/add',
                mode: 'add',
                entity: 'teacher',
                token: widget.token,
                aliases: _liveAliases(),
                onSnapshot: _applyLiveSnapshot,
                onOptions: _applyLiveOptions,
                onStatus: (v) {
                  if (mounted) setState(() => _liveStatus = v);
                },
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
                    'جميع الحقول والقوائم مطابقة لنظام EMIS الرسمي.',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        fontSize: 13),
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
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red)),
      );
}
