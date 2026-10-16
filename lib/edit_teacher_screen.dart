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
  bool _isLoading = true;
  bool _isSaving = false;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _teacherData;
  File? _pickedImage;
  final Map<String, TextEditingController> _dateControllers = {};

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
    'nationality': '/selectoption/الجنسية',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'gender': '/selectoption/Gender',
    'motherTongue': '/selectoption/لغة',
    'maritalStatus': '/selectoption/الحالة الاجتماعية',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'educationLevel': '/selectoption/تحصیل الدراسي',
    'positionType': '/SelectOption/نوع الوظيفة',
    'specialization': '/selectoption/الإختصاص',
  };

  static final Map<String, List<Map<String, dynamic>>> _defaultStaticOptions = {
    'gender': [
      <String, dynamic>{'value': 1, 'displayName': 'ذكر'},
      <String, dynamic>{'value': 2, 'displayName': 'أنثى'},
    ],
    'idType': [
      <String, dynamic>{'value': 3, 'displayName': 'هوية الأحوال المدنية'},
      <String, dynamic>{'value': 12, 'displayName': 'البطاقة الوطنية الموحدة'},
      <String, dynamic>{'value': 22, 'displayName': 'شهادة الولادة'},
      <String, dynamic>{'value': 16, 'displayName': 'أخرى'},
    ],
    'employmentType': [
      <String, dynamic>{'value': 'ملاك دائم', 'displayName': 'ملاك دائم'},
      <String, dynamic>{'value': 'ملاك', 'displayName': 'ملاك'},
      <String, dynamic>{'value': 'عقد', 'displayName': 'عقد'},
      <String, dynamic>{'value': 'محاضر', 'displayName': 'محاضر'},
      <String, dynamic>{'value': 'أجر يومي', 'displayName': 'أجر يومي'},
    ],
    'employeeCategory': [
      <String, dynamic>{'value': 'تدريسي', 'displayName': 'تدريسي'},
      <String, dynamic>{'value': 'إداري', 'displayName': 'إداري'},
      <String, dynamic>{'value': 'خدمي', 'displayName': 'خدمي'},
    ],
    'employmentStatus': [
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
    'status': [
      <String, dynamic>{'value': 1, 'displayName': 'مفعّل'},
      <String, dynamic>{'value': 2, 'displayName': 'غير مفعّل'},
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
  };

  final Map<String, String> _officialArabicNames = {
    'name': 'الإسم *',
    'fatherName': 'إسم الأب *',
    'grandFatherName': 'اسم والد الأب *',
    'fathersGrandFatherName': 'اسم جد الأب *',
    'surName': 'اللقب *',
    'motherName': 'إسم الأم *',
    'mothersFatherName': 'اسم والد الأم *',
    'mothersGrandFatherName': 'اسم جد الأم *',
    'dateOfBirth': 'تاريخ التولّد *',
    'gender': 'الجنس *',
    'nationality': 'الجنسية *',
    'countryOfBirth': 'محل الولادة',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم *',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة *',
    'notes': 'ملاحظات',
    'idType': 'نوع الهوية *',
    'issuingCountry': 'بلد الإصدار *',
    'idNumber': 'رقم الوثيقة / البطاقة الوطنية *',
    'issuingDate': 'تاريخ الإصدار',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'nameOfDocument': 'نوع الوثيقة *',
    'issuer': 'جهة الإصدار',
    'recordNumber': 'رقم السجل *',
    'pageNumber': 'رقم الصحيفة *',
    'employmentType': 'نوع التوظيف *',
    'employeeCategory': 'نوع الموظف *',
    'classification': 'التصنيف *',
    'jobDesignation': 'المسمى الوظيفي',
    'positionType': 'العنوان الوظيفي *',
    'employmentGrade': 'الدرجة الوظيفية',
    'weeklyTeachingQuota': 'النصاب الأسبوعي للحصص',
    'dateOfStartWorking': 'تاريخ أول تعيين للموظف *',
    'currentPosition': 'المنصب الحالي *',
    'employmentStatus': 'الحالة الوظيفية *',
    'employmentStatusReason': 'سبب الحالة الوظيفية',
    'assignedEntityName': 'الجهة المنسب أو المكلف إليها',
    'status': 'حالة السجل',
    'educationLevel': 'التحصيل الدراسي *',
    'universityName': 'إسم الكلية / المعهد',
    'graduationYear': 'سنة التخرج',
    'specialization': 'الإختصاص *',
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة إن وجدت',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال في الحالات الطارئة',
    'countryStructureId': 'الموقع الجغرافي *',
    'town': 'المدينة/القرية *',
    'area': 'الحي *',
    'quarter': 'المحلة *',
    'street': 'زقاق *',
    'address1': 'عنوان 1 *',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة *',
    'email': 'البريد الإلكتروني',
    'mobilePhoneNumber': 'رقم هاتف المعلم *',
    'homePhoneNumber': 'رقم الهاتف الأرضي',
    'imageUrl': 'الصورة الشخصية',
  };

  Map<String, String> get h => {'Authorization': widget.token, 'Accept': 'application/json'};

  @override
  void initState() {
    super.initState();
    _initStaticOptions();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _fetchTeacherData();
  }

  void _initStaticOptions() {
    for (final entry in _defaultStaticOptions.entries) {
      _options[entry.key] = entry.value
          .map((item) => <String, dynamic>{
                'value': item['value'],
                'displayName': item['displayName'],
              })
          .toList();
    }
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in _officialArabicNames.entries)
          entry.key: <String>[
            entry.key,
            entry.value.replaceAll(' *', '').trim(),
            entry.value,
          ],
      };

  Map<String, String> _liveValues() {
    final result = <String, String>{};
    final data = _teacherData;
    if (data == null) return result;
    final identification = data['identification'] is Map
        ? Map<String, dynamic>.from(data['identification'] as Map)
        : <String, dynamic>{};
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'] as Map)
        : <String, dynamic>{};
    for (final key in _officialArabicNames.keys) {
      dynamic value;
      if (data.containsKey(key)) {
        value = data[key];
      } else if (identification.containsKey(key)) {
        value = identification[key];
      } else if (address.containsKey(key)) {
        value = address[key];
      }
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
    final data = _teacherData;
    if (data == null) return;
    final identification = data['identification'] is Map
        ? Map<String, dynamic>.from(data['identification'] as Map)
        : <String, dynamic>{};
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'] as Map)
        : <String, dynamic>{};
    bool changed = false;
    for (final entry in values.entries) {
      final key = entry.key;
      if (data.containsKey(key)) {
        final next = _liveCoerce(data[key], entry.value);
        if ('${data[key]}' != '$next') {
          data[key] = next;
          changed = true;
        }
      } else if (identification.containsKey(key)) {
        final next = _liveCoerce(identification[key], entry.value);
        if ('${identification[key]}' != '$next') {
          identification[key] = next;
          changed = true;
        }
      } else if (address.containsKey(key)) {
        final next = _liveCoerce(address[key], entry.value);
        if ('${address[key]}' != '$next') {
          address[key] = next;
          changed = true;
        }
      }
    }
    if (changed) {
      data['identification'] = identification;
      data['address'] = address;
      if (mounted) setState(() {});
    }
  }

  Map<String, dynamic> _unwrap(dynamic decoded) {
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v));
      }
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    throw Exception('استجابة بيانات المعلم غير صالحة');
  }

  void _normalizeTeacherFields(Map<String, dynamic> teacher) {
    final rawId = teacher['identification'];
    final identification = rawId is Map
        ? rawId.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    identification['idNumber'] = (identification['idNumber'] ?? identification['IdNumber'] ?? '').toString();
    identification['issuingCountry'] = (identification['issuingCountry'] ?? identification['IssuingCountry'] ?? 'العراق').toString();
    identification['idType'] = identification['idType'] ?? identification['IdType'] ?? 12;
    identification['nameOfDocument'] = (identification['nameOfDocument'] ?? '').toString();
    identification['recordNumber'] = (identification['recordNumber'] ?? '').toString();
    identification['pageNumber'] = (identification['pageNumber'] ?? '').toString();
    identification['issuer'] = (identification['issuer'] ?? '').toString();
    identification['issuingDate'] = _cleanDate(identification['issuingDate']);
    teacher['identification'] = identification;

    final rawEmp = teacher['employmentRecord'];
    final employment = rawEmp is Map
        ? rawEmp.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    final rawStatuses = employment['employmentStatuses'] ?? employment['EmploymentStatuses'];
    final statuses = rawStatuses is List
        ? rawStatuses.whereType<Map>().map((x) => x.map((k, v) => MapEntry(k.toString(), v))).toList()
        : <Map<String, dynamic>>[];

    final rawPositions = employment['employmentPositions'] ?? employment['EmploymentPositions'];
    final positions = rawPositions is List
        ? rawPositions.whereType<Map>().map((x) => x.map((k, v) => MapEntry(k.toString(), v))).toList()
        : <Map<String, dynamic>>[];

    Map<String, dynamic>? latestStatus = statuses.isNotEmpty ? statuses.first : null;
    Map<String, dynamic>? latestPosition = positions.isNotEmpty ? positions.first : null;

    final rawStatusType = (latestStatus?['statusType'] ?? latestStatus?['StatusType'] ?? 'مستمر').toString();
    teacher['employmentStatus'] = rawStatusType == 'Active' ? 'مستمر' : (rawStatusType.isEmpty ? 'مستمر' : rawStatusType);
    teacher['employmentStatusReason'] = (latestStatus?['reason'] ?? latestStatus?['Reason'] ?? '').toString();
    teacher['assignedEntityName'] = (latestStatus?['assignedEntityName'] ?? latestStatus?['AssignedEntityName'] ?? '').toString();

    teacher['positionType'] = (employment['currentEmploymentPosition'] ??
            employment['CurrentEmploymentPosition'] ??
            teacher['positionType'] ??
            '')
        .toString();
    teacher['currentPosition'] = (latestPosition?['position'] ??
            latestPosition?['Position'] ??
            teacher['currentPosition'] ??
            '')
        .toString();

    teacher['employmentRecord'] = employment;

    final rawAddr = teacher['address'];
    final address = rawAddr is Map
        ? rawAddr.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    address['addressType'] = address['addressType'] ?? 1;
    address['countryStructureId'] = address['countryStructureId'] ?? 1;
    address['town'] = (address['town'] ?? '').toString();
    address['area'] = (address['area'] ?? '').toString();
    address['quarter'] = (address['quarter'] ?? '').toString();
    address['street'] = (address['street'] ?? '').toString();
    address['address1'] = (address['branch'] ?? address['address1'] ?? '').toString();
    address['address2'] = (address['neighborhood'] ?? address['address2'] ?? '').toString();
    address['closestLocation'] = (address['closestLocation'] ?? '').toString();
    address['mobilePhoneNumber'] = (address['mobilePhoneNumber'] ?? '').toString();
    address['email'] = (address['email'] ?? '').toString();
    teacher['address'] = address;

    teacher['name'] = (teacher['name'] ?? '').toString();
    teacher['fatherName'] = (teacher['fatherName'] ?? '').toString();
    teacher['grandFatherName'] = (teacher['grandFatherName'] ?? '').toString();
    teacher['fathersGrandFatherName'] = (teacher['fathersGrandFatherName'] ?? '').toString();
    teacher['surName'] = (teacher['surName'] ?? '').toString();
    teacher['motherName'] = (teacher['motherName'] ?? '').toString();
    teacher['mothersFatherName'] = (teacher['mothersFatherName'] ?? '').toString();
    teacher['mothersGrandFatherName'] = (teacher['mothersGrandFatherName'] ?? '').toString();
    teacher['dateOfBirth'] = _cleanDate(teacher['dateOfBirth']);
    teacher['gender'] = teacher['gender'] ?? 1;
    teacher['nationality'] = (teacher['nationality'] ?? 'العراق').toString();
    teacher['countryOfBirth'] = (teacher['countryOfBirth'] ?? 'العراق').toString();
    teacher['homeTown'] = (teacher['homeTown'] ?? '').toString();
    teacher['motherTongue'] = (teacher['motherTongue'] ?? 'العربية').toString();
    teacher['maritalStatus'] = (teacher['maritalStatus'] ?? '').toString();
    teacher['bloodGroup'] = (teacher['bloodGroup'] ?? '').toString();
    teacher['religion'] = (teacher['religion'] ?? 'الإسلام').toString();
    teacher['employeeIdNumber'] = (teacher['employeeIdNumber'] ?? '').toString();
    teacher['familyNumber'] = (teacher['familyNumber'] ?? '').toString();
    teacher['notes'] = (teacher['notes'] ?? '').toString();
    teacher['status'] = teacher['status'] ?? 1;

    teacher['employmentType'] = (teacher['employmentType'] ?? teacher['EmploymentType'] ?? '').toString();
    teacher['employeeCategory'] = (teacher['employeeCategory'] ?? '').toString();
    teacher['classification'] = (teacher['classification'] ?? teacher['Classification'] ?? '').toString();
    teacher['jobDesignation'] = (teacher['jobDesignation'] ?? '').toString();
    teacher['employmentGrade'] = (teacher['employmentGrade'] ?? '').toString();
    teacher['weeklyTeachingQuota'] = (teacher['weeklyTeachingQuota'] ?? '').toString();
    teacher['dateOfStartWorking'] = _cleanDate(teacher['dateOfStartWorking']);
    teacher['educationLevel'] = (teacher['educationLevel'] ?? 'بكالوريوس').toString();
    teacher['universityName'] = (teacher['universityName'] ?? '').toString();
    teacher['graduationYear'] = _cleanDate(teacher['graduationYear']);
    teacher['specialization'] = (teacher['specialization'] ?? '').toString();
    teacher['specialNeedsInformation'] = (teacher['specialNeedsInformation'] ?? '').toString();
    teacher['emergencyContactName'] = (teacher['emergencyContactName'] ?? '').toString();
    teacher['emergencyContactRelationship'] = (teacher['emergencyContactRelationship'] ?? '').toString();
    teacher['emergencyContactPhoneNumber'] = (teacher['emergencyContactPhoneNumber'] ?? '').toString();
  }

  String _cleanDate(dynamic raw) {
    if (raw == null) return '';
    final str = raw.toString().trim();
    if (str.isEmpty || str.startsWith('0001-01-01') || str == '1-01-01') return '';
    if (str.contains('T')) return str.split('T').first;
    return str;
  }

  Future<void> _fetchTeacherData() async {
    try {
      setState(() => _isLoading = true);

      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/getemployee/${widget.teacherId}'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final teacher = _unwrap(jsonDecode(utf8.decode(response.bodyBytes)));
      _normalizeTeacherFields(teacher);

      _teacherData = teacher;
      _ensureOptionIncludesCurrentValue(teacher);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      for (final key in _optionEndpoints.keys) {
        await _loadOptions(key);
      }
      await _loadEmployeesOptions();
      _ensureOptionIncludesCurrentValue(teacher);
      await _loadCountryStructure();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('خطأ في جلب بيانات المعلم: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب بيانات المعلم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _ensureOptionIncludesCurrentValue(Map<String, dynamic> teacher) {
    final identification = teacher['identification'] is Map
        ? Map<String, dynamic>.from(teacher['identification'] as Map)
        : <String, dynamic>{};

    void checkAndAdd(String key, dynamic val) {
      if (val == null) return;
      final sVal = val.toString().trim();
      if (sVal.isEmpty) return;
      final list = _options.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      final exists = list.any((item) => _sameValue(_optionValue(item), val));
      if (!exists) {
        list.add(<String, dynamic>{
          'value': val,
          'displayName': sVal,
        });
      }
    }

    checkAndAdd('employmentType', teacher['employmentType']);
    checkAndAdd('employeeCategory', teacher['employeeCategory']);
    checkAndAdd('classification', teacher['classification']);
    checkAndAdd('employmentGrade', teacher['employmentGrade']);
    checkAndAdd('employmentStatus', teacher['employmentStatus']);
    checkAndAdd('status', teacher['status']);
    checkAndAdd('educationLevel', teacher['educationLevel']);
    checkAndAdd('positionType', teacher['positionType']);
    checkAndAdd('currentPosition', teacher['currentPosition']);
    checkAndAdd('specialization', teacher['specialization']);
    checkAndAdd('gender', teacher['gender']);
    checkAndAdd('nationality', teacher['nationality']);
    checkAndAdd('countryOfBirth', teacher['countryOfBirth']);
    checkAndAdd('motherTongue', teacher['motherTongue']);
    checkAndAdd('maritalStatus', teacher['maritalStatus']);
    checkAndAdd('bloodGroup', teacher['bloodGroup']);
    checkAndAdd('religion', teacher['religion']);

    if (identification.isNotEmpty) {
      checkAndAdd('idType', identification['idType']);
      checkAndAdd('issuingCountry', identification['issuingCountry']);
    }
  }

  Future<List<Map<String, dynamic>>> _getOptions(String path) async {
    try {
      final encodedPath = Uri.encodeFull('https://emis.moedu.gov.iq/api$path');
      final response = await http.get(
        Uri.parse(encodedPath),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      dynamic value = decoded;
      if (value is Map) {
        value = value['data'] ?? value['items'] ?? value['results'] ?? value;
      }
      if (value is! List) return <Map<String, dynamic>>[];

      final result = <Map<String, dynamic>>[];
      for (final item in value) {
        if (item is Map) {
          result.add(item.map((k, v) => MapEntry(k.toString(), v)));
        } else if (item != null) {
          final str = item.toString().trim();
          if (str.isNotEmpty) {
            result.add(<String, dynamic>{'value': str, 'displayName': str});
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('تجاوز خطأ خيارات $path: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadOptions(String key) async {
    if (_loadingOptions.contains(key)) return;
    final endpoint = _optionEndpoints[key];
    if (endpoint == null) return;
    _loadingOptions.add(key);
    try {
      final fetched = await _getOptions(endpoint);
      if (fetched.isNotEmpty) {
        final existing = _options[key] ?? <Map<String, dynamic>>[];
        final merged = <Map<String, dynamic>>[...fetched];
        for (final item in existing) {
          final v = _optionValue(item);
          if (!merged.any((m) => _sameValue(_optionValue(m), v))) {
            merged.add(item);
          }
        }
        _options[key] = merged;
      }
    } catch (e) {
      debugPrint('تعذر تحميل خيارات $key: $e');
    } finally {
      _loadingOptions.remove(key);
    }
  }

  Future<void> _loadEmployeesOptions() async {
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/getemployeesoptions'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return;

      void loadSimple(String key, dynamic raw) {
        if (raw is! List) return;
        final existing = _options[key] ?? <Map<String, dynamic>>[];
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

        if (parsed.isNotEmpty) {
          for (final ex in existing) {
            final v = _optionValue(ex);
            if (!parsed.any((p) => _sameValue(_optionValue(p), v))) {
              parsed.add(ex);
            }
          }
          _options[key] = parsed;
        }
      }

      loadSimple('classification', decoded['classification']);
      loadSimple('employmentStatus', decoded['currentemploymentstatus']);
      loadSimple('employeeCategory', decoded['employeecategory'] ?? decoded['employeeCategory']);
    } catch (e) {
      debugPrint('تجاوز خطأ getemployeesoptions: $e');
    }
  }

  Future<void> _loadCountryStructure() async {
    try {
      final list = await _getOptions('/CountryStructure/getcountrystructure');
      if (list.isEmpty) return;
      _addressCountries = list;

      final address = _teacherData?['address'] is Map
          ? Map<String, dynamic>.from(_teacherData!['address'] as Map)
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
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('تعذر تحميل هيكل العناوين: $e');
    }
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
    final raw = node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  String _formatDateValue(String value) {
    final v = value.trim();
    final iso = RegExp(r'^(\d{4})[-/]?(\d{2})[-/]?(\d{2})$').firstMatch(v);
    if (iso != null) return '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    final dmy = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(v);
    if (dmy != null) {
      return '${dmy.group(3)}-${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(1)!.padLeft(2, '0')}';
    }
    return v.replaceAll('/', '-');
  }

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

  String _label(String key) => _officialArabicNames[key] ?? key;

  bool _isDateField(String key) => <String>{
        'dateOfBirth',
        'issuingDate',
        'dateOfStartWorking',
        'graduationYear',
      }.contains(key);

  bool _isDropdownField(String key) =>
      _optionEndpoints.containsKey(key) ||
      _defaultStaticOptions.containsKey(key) ||
      <String>{
        'employmentType',
        'employeeCategory',
        'classification',
        'employmentGrade',
        'currentPosition',
        'positionType',
        'employmentStatus',
        'status',
        'educationLevel',
        'specialization',
      }.contains(key);

  dynamic _optionValue(Map<String, dynamic> option) => option['value'] ?? option['id'];
  String _optionText(Map<String, dynamic> option) =>
      (option['displayName'] ??
              option['name'] ??
              option['label'] ??
              option['text'] ??
              _optionValue(option)?.toString() ??
              '')
          .toString();

  bool _sameValue(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.toString().trim() == b.toString().trim();
  }

  Widget _dropdownField({
    required String key,
    required Map<String, dynamic> owner,
    required bool isDark,
    required Color textColor,
  }) {
    final rawItems = _options[key] ?? const <Map<String, dynamic>>[];
    final value = owner[key];

    final uniqueItems = <Map<String, dynamic>>[];
    for (final item in rawItems) {
      final v = _optionValue(item);
      if (v != null &&
          v.toString().trim().isNotEmpty &&
          !uniqueItems.any((u) => _sameValue(_optionValue(u), v))) {
        uniqueItems.add(item);
      }
    }

    if (value != null &&
        value.toString().trim().isNotEmpty &&
        !uniqueItems.any((u) => _sameValue(_optionValue(u), value))) {
      uniqueItems.add(<String, dynamic>{
        'value': value,
        'displayName': value.toString(),
      });
    }

    dynamic safeValue;
    for (final item in uniqueItems) {
      if (_sameValue(_optionValue(item), value)) {
        safeValue = _optionValue(item);
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<dynamic>(
        value: safeValue,
        isExpanded: true,
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        style: TextStyle(color: isDark ? Colors.white : textColor, fontSize: 16, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: _label(key),
          labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: uniqueItems.map((item) {
          return DropdownMenuItem<dynamic>(
            value: _optionValue(item),
            child: Text(
              _optionText(item),
              style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor),
            ),
          );
        }).toList(),
        onChanged: (newValue) {
          setState(() => owner[key] = newValue);
          _focusLive(key);
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
      initialDate: initial.isAfter(DateTime(2100)) || initial.isBefore(DateTime(1900))
          ? DateTime(1985, 1, 1)
          : initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null && mounted) {
      final formatted =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _dateControllers.putIfAbsent(key, () => TextEditingController()).value =
          TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      setState(() => owner[key] = formatted);
      _focusLive(key);
    }
  }

  Widget _fieldFor(
    String key,
    dynamic value,
    Map<String, dynamic> owner,
    bool isDark,
    Color textColor,
  ) {
    if (_isDropdownField(key)) {
      return _dropdownField(
          key: key, owner: owner, isDark: isDark, textColor: textColor);
    }

    if (_isDateField(key)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextFormField(
          key: ValueKey('date-$key'),
          controller: _dateControllers.putIfAbsent(
            key,
            () => TextEditingController(
                text: _formatDateValue(value?.toString() ?? '')),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              final formatted = _formatTypedDate(newValue.text);
              return TextEditingValue(
                text: formatted,
                selection: TextSelection.collapsed(offset: formatted.length),
              );
            }),
          ],
          onChanged: (v) {
            owner[key] = v;
            _focusLive(key);
          },
          onTap: () => _focusLive(key),
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: _label(key),
            suffixIcon: IconButton(
              tooltip: 'اختيار التاريخ',
              onPressed: () => _pickDate(owner, key),
              icon: const Icon(Icons.calendar_month),
            ),
            filled: true,
            fillColor: isDark ? Colors.black12 : Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return PlainTextField(
      label: _label(key),
      initialValue: value,
      isDark: isDark,
      textColor: textColor,
      onChanged: (v) {
        owner[key] = v;
        _focusLive(key);
      },
      onTap: () => _focusLive(key),
    );
  }

  Widget _teacherSection(
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
    for (var i = 0; i < children.length;) {
      final current = children[i];
      final isDate = current is Padding &&
          current.child is TextFormField &&
          (current.child as TextFormField).key is ValueKey &&
          ((current.child as TextFormField).key as ValueKey)
              .value
              .toString()
              .startsWith('date-');
      if (isDate) {
        rows.add(SizedBox(width: double.infinity, child: current));
        i++;
      } else {
        final next =
            i + 1 < children.length ? children[i + 1] : const SizedBox();
        final nextIsDate = next is Padding &&
            next.child is TextFormField &&
            (next.child as TextFormField).key is ValueKey &&
            ((next.child as TextFormField).key as ValueKey)
                .value
                .toString()
                .startsWith('date-');
        if (nextIsDate) {
          rows.add(SizedBox(width: double.infinity, child: current));
          i++;
        } else {
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: current),
              const SizedBox(width: 10),
              Expanded(child: next),
            ],
          ));
          i += 2;
        }
      }
      if (i < children.length) rows.add(const SizedBox(height: 12));
    }
    return rows;
  }

  Widget _addressDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    bool isDark,
    Color textColor,
    ValueChanged<String?> onChanged,
  ) {
    final safe =
        items.any((x) => _optionValue(x)?.toString() == value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        value: safe,
        isExpanded: true,
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
        ),
        style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor, fontSize: 16),
        items: items
            .map((item) => DropdownMenuItem<String>(
                  value: _optionValue(item)?.toString(),
                  child: Text(
                    _optionText(item),
                    style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : textColor),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  List<Widget> _buildIdentificationFields(
    Map<String, dynamic> identification,
    Map<String, dynamic> teacher,
    bool isDark,
    Color textColor,
  ) {
    final idType = int.tryParse(identification['idType']?.toString() ?? '') ?? 12;
    final widgets = <Widget>[
      _fieldFor('idType', identification['idType'], identification, isDark, textColor),
      _fieldFor('issuingCountry', identification['issuingCountry'], identification, isDark, textColor),
    ];

    if (idType == 3) {
      widgets.addAll([
        _fieldFor('idNumber', identification['idNumber'], identification, isDark, textColor),
        _fieldFor('recordNumber', identification['recordNumber'], identification, isDark, textColor),
        _fieldFor('pageNumber', identification['pageNumber'], identification, isDark, textColor),
        _fieldFor('issuer', identification['issuer'], identification, isDark, textColor),
      ]);
    } else if (idType == 12) {
      widgets.add(
        _fieldFor('idNumber', identification['idNumber'], identification, isDark, textColor),
      );
    } else if (idType == 22) {
      widgets.addAll([
        _fieldFor('idNumber', identification['idNumber'], identification, isDark, textColor),
        _fieldFor('issuingDate', identification['issuingDate'], identification, isDark, textColor),
        _fieldFor('recordNumber', identification['recordNumber'], identification, isDark, textColor),
        _fieldFor('pageNumber', identification['pageNumber'], identification, isDark, textColor),
      ]);
    } else if (idType == 16) {
      widgets.addAll([
        _fieldFor('nameOfDocument', identification['nameOfDocument'], identification, isDark, textColor),
        _fieldFor('idNumber', identification['idNumber'], identification, isDark, textColor),
      ]);
    } else {
      widgets.add(
        _fieldFor('idNumber', identification['idNumber'], identification, isDark, textColor),
      );
    }

    widgets.addAll([
      _fieldFor('employeeIdNumber', teacher['employeeIdNumber'], teacher, isDark, textColor),
      _fieldFor('familyNumber', teacher['familyNumber'], teacher, isDark, textColor),
    ]);

    return widgets;
  }

  List<Widget> _buildTeacherFormSections(bool isDark, Color textColor) {
    final teacher = _teacherData!;
    final identification = teacher['identification'] is Map
        ? Map<String, dynamic>.from(teacher['identification'] as Map)
        : <String, dynamic>{};
    final address = teacher['address'] is Map
        ? Map<String, dynamic>.from(teacher['address'] as Map)
        : <String, dynamic>{};
    final employment = teacher['employmentRecord'] is Map
        ? Map<String, dynamic>.from(teacher['employmentRecord'] as Map)
        : <String, dynamic>{};

    teacher['identification'] = identification;
    teacher['address'] = address;
    teacher['employmentRecord'] = employment;

    Widget field(String key, [Map<String, dynamic>? owner]) {
      final target = owner ?? teacher;
      return _fieldFor(key, target[key], target, isDark, textColor);
    }

    return <Widget>[
      _teacherSection(
        'الاسم الكامل',
        [
          field('name'),
          field('fatherName'),
          field('grandFatherName'),
          field('fathersGrandFatherName'),
          field('surName'),
          field('motherName'),
          field('mothersFatherName'),
          field('mothersGrandFatherName'),
        ],
        isDark,
      ),
      _teacherSection(
        'وثيقة التعريف والرقم الوظيفي',
        _buildIdentificationFields(identification, teacher, isDark, textColor),
        isDark,
      ),
      _teacherSection(
        'البيانات الشخصية',
        [
          field('dateOfBirth'),
          field('countryOfBirth'),
          field('gender'),
          field('nationality'),
          field('homeTown'),
          field('motherTongue'),
          field('maritalStatus'),
          field('bloodGroup'),
          field('religion'),
          field('notes'),
        ],
        isDark,
      ),
      _teacherSection(
        'البيانات الوظيفية',
        [
          field('employmentType'),
          field('employeeCategory'),
          field('classification'),
          field('positionType'),
          field('currentPosition'),
          field('jobDesignation'),
          field('employmentGrade'),
          field('weeklyTeachingQuota'),
          field('dateOfStartWorking'),
        ],
        isDark,
      ),
      _teacherSection(
        'الحالة الوظيفية',
        [
          field('employmentStatus'),
          if (teacher['employmentStatus'] != 'مستمر')
            field('employmentStatusReason'),
          if (teacher['employmentStatus'] ==
              'مكلف او منسب من وزارة التربية الى جهات أخرى')
            field('assignedEntityName'),
          field('status'),
        ],
        isDark,
      ),
      _teacherSection(
        'التحصيل الدراسي والاختصاص',
        [
          field('educationLevel'),
          if (teacher['educationLevel'] == 'دبلوم' ||
              teacher['educationLevel'] == 'بكالوريوس') ...[
            field('universityName'),
            field('graduationYear'),
          ],
          if (!<String>['ابتدائية', 'متوسطة', 'إعدادية']
              .contains(teacher['educationLevel']))
            field('specialization'),
        ],
        isDark,
      ),
      _teacherSection(
        'ذوو الاحتياجات الخاصة والاتصال الطارئ',
        [
          field('specialNeedsInformation'),
          field('emergencyContactName'),
          field('emergencyContactRelationship'),
          field('emergencyContactPhoneNumber'),
        ],
        isDark,
      ),
      _teacherSection(
        'العنوان ومعلومات الاتصال',
        [
          _addressDropdown(
            'الدولة',
            _addressCountryId,
            _addressCountries,
            isDark,
            textColor,
            (v) {
              final country = _addressCountries
                  .where((x) => _value(x) == v)
                  .toList();
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
            },
          ),
          _addressDropdown(
            'المحافظة',
            _addressGovernorateId,
            _addressGovernorates,
            isDark,
            textColor,
            (v) {
              final gov = _addressGovernorates
                  .where((x) => _value(x) == v)
                  .toList();
              if (gov.isEmpty) return;
              setState(() {
                _addressGovernorateId = v;
                _addressDistricts = _childrenOf(gov.first);
                _addressDistrictId = null;
                address['countryStructureId'] = null;
              });
              _focusLive('countryStructureId');
            },
          ),
          _addressDropdown(
            'القضاء / الناحية',
            _addressDistrictId,
            _addressDistricts,
            isDark,
            textColor,
            (v) {
              setState(() {
                _addressDistrictId = v;
                address['countryStructureId'] =
                    v == null ? null : int.tryParse(v);
              });
              _focusLive('countryStructureId');
            },
          ),
          field('town', address),
          field('area', address),
          field('quarter', address),
          field('street', address),
          field('address1', address),
          field('address2', address),
          field('closestLocation', address),
          field('email', address),
          field('mobilePhoneNumber', address),
        ],
        isDark,
      ),
    ];
  }

  SelfieSegmenter? _selfieSegmenter;

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
      if (mask.width != source.width || mask.height != source.height) {
        throw Exception('أبعاد القناع غير متطابقة');
      }

      final result =
          img.Image(width: source.width, height: source.height, numChannels: 4);
      final pixelCount = source.width * source.height;
      if (mask.confidences.length < pixelCount) {
        throw Exception('بيانات القناع غير مكتملة');
      }

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
                      height: 240,
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
                          child: Image.file(currentImage, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('يمكنك تقريب الصورة لمراجعتها قبل اعتمادها',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontSize: 12)),
                    const SizedBox(height: 15),
                    if (processing)
                      const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('جاري إزالة الخلفية...'),
                        ],
                      )
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
                              if (processed == null) {
                                throw Exception(
                                    'لم يتم الحصول على الصورة المعالجة');
                              }
                              if (!mounted) return;
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
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteCurrentPhoto() {
    setState(() {
      _pickedImage = null;
      if (_teacherData != null) _teacherData!['imageUrl'] = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف صورة المعلم')),
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
      final streamedResponse = await request.send();
      final responseData = await streamedResponse.stream.bytesToString();
      if (streamedResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(responseData);
        if (jsonResponse is Map) return jsonResponse['imageUrl']?.toString();
      }
      debugPrint('استجابة رفع الصورة: $responseData');
    } catch (e) {
      debugPrint('خطأ في رفع الصورة إلى EMIS: $e');
    }
    return null;
  }

  void _flattenToFormFields(
    Map<String, String> target,
    String prefix,
    dynamic value,
  ) {
    if (value == null) return;
    if (value is Map) {
      value.forEach((k, v) {
        final nextKey = prefix.isEmpty ? k.toString() : '$prefix.${k.toString()}';
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

  Future<http.Response> _sendUpdateRequest(Map<String, dynamic> payload) async {
    final uri = Uri.parse('https://emis.moedu.gov.iq/api/employee/updateemployee');
    final jsonString = jsonEncode(payload);

    var response = await http.put(
      uri,
      headers: {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonString,
    );
    if (response.statusCode != 405 && response.statusCode != 415) {
      return response;
    }

    response = await http.post(
      uri,
      headers: {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonString,
    );
    if (response.statusCode != 405 && response.statusCode != 415) {
      return response;
    }

    final postMultipart = http.MultipartRequest('POST', uri);
    postMultipart.headers['Authorization'] = widget.token;
    postMultipart.headers['Accept'] = 'application/json';
    _flattenToFormFields(postMultipart.fields, '', payload);
    postMultipart.fields['emp'] = jsonString;
    var streamed = await postMultipart.send();
    response = await http.Response.fromStream(streamed);
    if (response.statusCode != 405 && response.statusCode != 415) {
      return response;
    }

    final putMultipart = http.MultipartRequest('PUT', uri);
    putMultipart.headers['Authorization'] = widget.token;
    putMultipart.headers['Accept'] = 'application/json';
    _flattenToFormFields(putMultipart.fields, '', payload);
    putMultipart.fields['emp'] = jsonString;
    streamed = await putMultipart.send();
    return await http.Response.fromStream(streamed);
  }

  Future<void> _saveTeacherData() async {
    if (_teacherData == null) return;
    setState(() => _isSaving = true);

    try {
      if (_pickedImage != null) {
        final newImageUrl = await _uploadImageToEmisServer(_pickedImage!);
        if (newImageUrl != null && newImageUrl.isNotEmpty) {
          _teacherData!['imageUrl'] = newImageUrl;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('تعذر رفع صورة المعلم'),
                  backgroundColor: Colors.red),
            );
          }
          return;
        }
      }

      String? dateOnly(dynamic value) {
        if (value == null) return null;
        final raw = value.toString().trim();
        if (raw.isEmpty) return null;
        final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw);
        if (iso != null) {
          final year = int.parse(iso.group(1)!);
          final month = int.parse(iso.group(2)!);
          final day = int.parse(iso.group(3)!);
          return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
        if (RegExp(r'^\d{4}$').hasMatch(raw)) {
          return '$raw-01-01';
        }
        return null;
      }

      final old = _teacherData!;
      final identification = old['identification'] is Map
          ? Map<String, dynamic>.from(old['identification'] as Map)
          : <String, dynamic>{};
      final oldAddress = old['address'] is Map
          ? Map<String, dynamic>.from(old['address'] as Map)
          : <String, dynamic>{};
      final oldEmployment = old['employmentRecord'] is Map
          ? Map<String, dynamic>.from(old['employmentRecord'] as Map)
          : <String, dynamic>{};

      String text(String key) {
        final v = old[key];
        return v == null ? '' : '$v'.trim();
      }

      final quota = int.tryParse(text('weeklyTeachingQuota'));
      final todayIso = DateTime.now().toIso8601String().split('T').first;

      final payload = <String, dynamic>{
        'Id': int.tryParse(widget.teacherId) ?? old['id'],
        'EmployeeIdNumber': text('employeeIdNumber'),
        'FamilyNumber': _nullable(text('familyNumber')),
        'IsTeacher': true,
        'EmploymentType': _nullable(text('employmentType')),
        'EmployeeCategory': _nullable(text('employeeCategory')),
        'Classification': _nullable(text('classification')),
        'JobDesignation': _nullable(text('jobDesignation')),
        'EmploymentGrade': _nullable(text('employmentGrade')),
        'WeeklyTeachingQuota': quota,
        'DateOfStartWorking':
            dateOnly(text('dateOfStartWorking')) ?? todayIso,
        'EducationLevel': text('educationLevel').isNotEmpty
            ? text('educationLevel')
            : 'ابتدائية',
        'GraduationYear': _nullable(dateOnly(text('graduationYear'))),
        'UniversityName': _nullable(text('universityName')),
        'Specialization': text('specialization'),
        'Name': text('name'),
        'FatherName': text('fatherName'),
        'GrandFatherName': text('grandFatherName'),
        'FathersGrandFatherName': text('fathersGrandFatherName'),
        'SurName': text('surName'),
        'MotherName': text('motherName'),
        'MothersFatherName': text('mothersFatherName'),
        'MothersGrandFatherName': text('mothersGrandFatherName'),
        'ImageUrl': old['imageUrl']?.toString() ?? '',
        'DateOfBirth': dateOnly(text('dateOfBirth')) ?? todayIso,
        'Gender': _intOrNull(text('gender')) ?? 1,
        'Nationality': text('nationality'),
        'CountryOfBirth': text('countryOfBirth'),
        'HomeTown': text('homeTown'),
        'IdentificationId': 0,
        'Identification': <String, dynamic>{
          'IdNumber': (identification['idNumber'] ?? '').toString().trim(),
          'IssuingCountry':
              (identification['issuingCountry'] ?? 'العراق').toString().trim(),
          'IdType':
              _intOrNull(identification['idType']?.toString() ?? '') ?? 12,
          'nameOfDocument':
              _nullable(identification['nameOfDocument']?.toString()),
          'recordNumber': _nullable(identification['recordNumber']?.toString()),
          'pageNumber': _nullable(identification['pageNumber']?.toString()),
          'issuer': _nullable(identification['issuer']?.toString()),
          'issuingDate': dateOnly(identification['issuingDate']),
        },
        'FatherIdentificationId': null,
        'FatherIdentification': null,
        'MotherTongue':
            text('motherTongue').isNotEmpty ? text('motherTongue') : 'العربية',
        'MaritalStatus': text('maritalStatus'),
        'BloodGroup': text('bloodGroup'),
        'Religion': text('religion'),
        'HomePhoneNumber': old['homePhoneNumber']?.toString() ?? '',
        'Status': _intOrNull(text('status')) ?? 1,
        'Notes': text('notes'),
        'SpecialNeedsInformation': _nullable(text('specialNeedsInformation')),
        'EmergencyContactName': _nullable(text('emergencyContactName')),
        'EmergencyContactRelationship':
            _nullable(text('emergencyContactRelationship')),
        'EmergencyContactPhoneNumber':
            _nullable(text('emergencyContactPhoneNumber')),
        'Address': <String, dynamic>{
          'AddressType': 1,
          'Town': (oldAddress['town'] ?? '').toString().trim(),
          'Area': (oldAddress['area'] ?? '').toString().trim(),
          'Quarter': (oldAddress['quarter'] ?? '').toString().trim(),
          'Street': (oldAddress['street'] ?? '').toString().trim(),
          'ClosestLocation':
              (oldAddress['closestLocation'] ?? '').toString().trim(),
          'countryStructureId': oldAddress['countryStructureId'] ?? 1,
          'Latitude': '0',
          'Longitude': '0',
          'ApartmentNumber': oldAddress['apartmentNumber']?.toString() ?? '',
          'BuildingNumber': oldAddress['buildingNumber']?.toString() ?? '',
          'Address1': (oldAddress['address1'] ?? '').toString().trim(),
          'Address2': (oldAddress['address2'] ?? '').toString().trim(),
          'SchoolPhoneNumber':
              oldAddress['schoolPhoneNumber']?.toString() ?? '',
          'MobilePhoneNumber':
              (oldAddress['mobilePhoneNumber'] ?? '').toString().trim(),
          'Email': (oldAddress['email'] ?? '').toString().trim(),
          'Fax': '',
          'Website': oldAddress['website']?.toString() ?? '',
        },
        'AgeExceptionReason': old['ageExceptionReason'],
        'AgeExceptionAttachmentUrl': old['ageExceptionAttachmentUrl'],
        'ageExceptionAttachment': null,
        'EmploymentRecord': _buildEmploymentRecord(oldEmployment),
      };

      final response = await _sendUpdateRequest(payload);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ تعديلات المعلم بنجاح!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else {
        debugPrint('Update teacher status: ${response.statusCode}');
        debugPrint('Update teacher response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: Text(
                'فشل الحفظ (HTTP ${response.statusCode})\n${response.body}',
                maxLines: 6,
                overflow: TextOverflow.ellipsis),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات المعلم: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: Text('تعذر إكمال الحفظ\n$e',
                maxLines: 6, overflow: TextOverflow.ellipsis),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Map<String, dynamic> _buildEmploymentRecord(Map<String, dynamic> old) {
    final schoolIdInt = int.tryParse(widget.schoolId) ??
        (old['currentBelongToEntityId'] is int
            ? old['currentBelongToEntityId'] as int
            : 1);
    final empStatus = (_teacherData?['employmentStatus'] ?? 'مستمر').toString();
    final isCurrentlyActive = empStatus.isEmpty || empStatus == 'مستمر';
    final startWorking =
        _cleanDate(_teacherData?['dateOfStartWorking']).isNotEmpty
            ? _cleanDate(_teacherData?['dateOfStartWorking'])
            : DateTime.now().toIso8601String().split('T').first;

    return <String, dynamic>{
      'EmploymentStatuses': <Map<String, dynamic>>[
        <String, dynamic>{
          'StatusType': empStatus,
          'DisEngagementDate': null,
          'MinistryOfficialDocumentNumber': null,
          'Reason':
              _nullable(_teacherData?['employmentStatusReason']?.toString()),
          'AssignedEntityName':
              _nullable(_teacherData?['assignedEntityName']?.toString()),
          'CurrentBelongToEntityId': schoolIdInt,
        }
      ],
      'EmploymentPositions': <Map<String, dynamic>>[
        <String, dynamic>{
          'Position': (_teacherData?['currentPosition'] ?? '').toString(),
          'InitiateDate': startWorking,
        }
      ],
      'IsCurrentlyActive': isCurrentlyActive,
      'CurrentBelongToEntityId': schoolIdInt,
      'CurrentEmploymentPosition':
          (_teacherData?['positionType'] ?? '').toString(),
    };
  }

  dynamic _nullable(dynamic value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : s;
  }

  int? _intOrNull(String value) => int.tryParse(value.trim());

  @override
  void dispose() {
    _liveTimer?.cancel();
    final segmenter = _selfieSegmenter;
    _selfieSegmenter = null;
    if (segmenter != null) segmenter.close();
    for (final controller in _dateControllers.values) {
      controller.dispose();
    }
    _dateControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    String imgUrl = _teacherData?['imageUrl']?.toString() ?? '';
    if (imgUrl.isNotEmpty && !imgUrl.startsWith('http')) {
      imgUrl = 'https://emis.moedu.gov.iq$imgUrl';
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('تعديل بيانات المعلم',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _teacherData == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('فشل جلب البيانات',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _fetchTeacherData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    )
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
                                              width: 3),
                                        ),
                                        child: ClipOval(
                                          child: _pickedImage != null
                                              ? Image.file(_pickedImage!,
                                                  fit: BoxFit.cover)
                                              : imgUrl.isNotEmpty
                                                  ? Image.network(
                                                      imgUrl,
                                                      headers: {
                                                        'Authorization':
                                                            widget.token
                                                      },
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) => Icon(
                                                              Icons.person,
                                                              size: 80,
                                                              color: Colors
                                                                  .grey[400]),
                                                    )
                                                  : Icon(Icons.person,
                                                      size: 80,
                                                      color: Colors.grey[400]),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: CircleAvatar(
                                          backgroundColor: Colors.blue,
                                          radius: 20,
                                          child: IconButton(
                                            icon: const Icon(Icons.camera_alt,
                                                color: Colors.white, size: 18),
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
                                          radius: 20,
                                          child: IconButton(
                                            icon: const Icon(
                                                Icons.photo_library,
                                                color: Colors.white,
                                                size: 18),
                                            onPressed: () =>
                                                _pickImage(ImageSource.gallery),
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
                                    icon: const Icon(Icons.delete_forever,
                                        color: Colors.red),
                                    label: const Text('حذف الصورة الحالية',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                ..._buildTeacherFormSections(isDark, textColor),
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
                              onPressed: _isSaving ? null : _saveTeacherData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text('حفظ',
                                      style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ],
                    ),
          Positioned(
            left: 0,
            bottom: 0,
            child: EmisLiveSync(
              key: _liveSyncKey,
              url:
                  'https://emis.moedu.gov.iq/centers/schools/${widget.schoolId}/individuals/teachers/management/edit/${widget.teacherId}',
              mode: 'edit',
              entity: 'teacher',
              token: widget.token,
              recordId: widget.teacherId,
              aliases: _liveAliases(),
              onSnapshot: _applyLiveSnapshot,
              onStatus: (v) {
                if (mounted) setState(() => _liveStatus = v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PlainTextField extends StatefulWidget {
  final String label;
  final dynamic initialValue;
  final bool isDark;
  final Color textColor;
  final Function(String) onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final VoidCallback? onMic;
  final bool micActive;

  const PlainTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.isDark,
    required this.textColor,
    required this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.onMic,
    this.micActive = false,
  });

  @override
  State<PlainTextField> createState() => _PlainTextFieldState();
}

class _PlainTextFieldState extends State<PlainTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialValue?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant PlainTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialValue?.toString() ?? '';
    if (next != _controller.text) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
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
        onTap: widget.onTap,
        validator: null,
        style: TextStyle(
            fontWeight: FontWeight.bold, color: widget.textColor, fontSize: 16),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle:
              const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: widget.isDark ? Colors.black12 : Colors.grey[50],
          suffixIcon: widget.onMic == null
              ? null
              : IconButton(
                  tooltip: 'الإدخال الصوتي',
                  onPressed: widget.onMic,
                  icon: Icon(
                    widget.micActive
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: widget.micActive ? Colors.red : null,
                  ),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }
}
