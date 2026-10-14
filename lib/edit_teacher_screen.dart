import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  bool _schemaReceived = false;
  bool _schemaStable = false;
  Timer? _schemaDebounce;
  Timer? _stabilityTimer;
  int _lastSchemaFieldCount = 0;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';
  String? _error;
  Map<String, dynamic>? _employee;
  File? _pickedImage;
  bool _removeExistingPhoto = false;
  SelfieSegmenter? _selfieSegmenter;

  final Map<String, TextEditingController> _c = {};
  final Map<String, List<Map<String, dynamic>>> _options = {};
  final Map<String, Map<String, dynamic>> _liveSchema = {};
  final Set<String> _liveDiscoveredFields = {};

  List<Map<String, dynamic>> _addressCountries = [];
  List<Map<String, dynamic>> _addressGovernorates = [];
  List<Map<String, dynamic>> _addressDistricts = [];
  String? _addressCountryId;
  String? _addressGovernorateId;
  String? _addressDistrictId;

  static const _commonOptionEndpoints = <String, String>{
    'countryOfBirth': '/selectoption/بلد الولادة',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'gender': '/selectoption/Gender',
    'nationality': '/selectoption/الجنسية',
    'motherTongue': '/selectoption/لغة',
    'maritalStatus': '/selectoption/الحالة الاجتماعية',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'educationLevel': '/selectoption/تحصیل الدراسي',
    'positionType': '/SelectOption/نوع الوظيفة',
    'specialization': '/selectoption/الإختصاص',
  };

  static const _statusOrder = <String>[
    'مستمر', 'متقاعد', 'مفصول', 'متوفى', 'استقالة',
    'منقول الى وزارة أخرى', 'العزل',
    'مكلف او منسبي من خارج الوزاراة',
    'مكلف او منسب من وزارة التربية الى جهات أخرى',
    'في إجازة دراسية', 'في إجازة أمومة', 'أخرى',
  ];

  static final Map<String, String> _labels = <String, String>{
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
    'gender': 'الجنس',
    'nationality': 'الجنسية',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة',
    'notes': 'ملاحظات',
    'idType': 'نوع الهوية',
    'issuingCountry': 'بلد الإصدار',
    'nationalId': 'رقم البطاقة الوطنية الموحدة',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'documentType': 'نوع الوثيقة',
    'documentNumber': 'رقم الوثيقة',
    'civilRegistryNumber': 'رقم جهة الأحوال المدنية',
    'recordNumber': 'رقم السجل',
    'pageNumber': 'رقم الصحیفة',
    'issuingAuthority': 'جهة الإصدار',
    'employmentType': 'نوع التوظيف',
    'employeeCategory': 'نوع الموظف',
    'classification': 'التصنيف',
    'jobDesignation': 'المسمى الوظيفي',
    'employmentGrade': 'الدرجة الوظيفية',
    'jobTitle': 'العنوان الوظيفي',
    'currentPosition': 'المنصب الحالي',
    'positionType': 'نوع الوظيفة',
    'dateOfStartWorking': 'تاريخ اول تعيين للموظف',
    'schoolName': 'إسم المدرسة',
    'status': 'الحالة الوظيفية',
    'statusDate': 'تاريخ سريان الحالة الوظيفية',
    'statusReason': 'سبب تغيير الحالة الوظيفية',
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
    _schemaDebounce?.cancel();
    _stabilityTimer?.cancel();
    _selfieSegmenter?.close();
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in _labels.entries)
          entry.key: <String>[entry.key, entry.value],
      };

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
  }

  void _pushFieldLive(String key, String value) {
    var liveValue = value;
    for (final option in _options[key] ?? const <Map<String, dynamic>>[]) {
      if ('${_optionValue(option) ?? ''}' == value) {
        liveValue = _optionText(option);
        break;
      }
    }
    _liveSyncKey.currentState?.pushValues({key: liveValue});
  }

  // ✅ مع MutationObserver، إعادتان كافيتان
  void _scheduleMultiRefresh() {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _liveSyncKey.currentState?.refreshSchema();
    });
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _liveSyncKey.currentState?.refreshSchema();
    });
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    bool changed = false;
    for (final entry in values.entries) {
      final controller = _c[entry.key];
      if (controller == null) continue;
      var syncedValue = entry.value;
      for (final option in _options[entry.key] ?? const <Map<String, dynamic>>[]) {
        if (_optionText(option).trim() == entry.value.trim()) {
          final apiValue = _optionValue(option);
          if (apiValue != null && '$apiValue'.trim().isNotEmpty) {
            syncedValue = '$apiValue';
            break;
          }
        }
      }
      if (controller.text != syncedValue) {
        controller.value = TextEditingValue(
          text: syncedValue,
          selection: TextSelection.collapsed(offset: syncedValue.length),
        );
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  String _canonicalLiveKey(String rawKey, [String label = '']) {
    String norm(String value) => value
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u06CC\u0649]'), 'ي')
        .replaceAll('ک', 'ك')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
    final wantedKey = norm(rawKey);
    final wantedLabel = norm(label);
    for (final entry in _labels.entries) {
      if (norm(entry.key) == wantedKey ||
          norm(entry.value) == wantedKey ||
          (wantedLabel.isNotEmpty && norm(entry.value) == wantedLabel)) {
        return entry.key;
      }
    }
    return rawKey.trim();
  }

  void _applyLiveOptions(Map<String, List<Map<String, dynamic>>> incoming) {
    bool changed = false;
    incoming.forEach((rawKey, values) {
      if (values.isEmpty) return;
      final key = _canonicalLiveKey(rawKey);
      final existing = _options[key] ?? <Map<String, dynamic>>[];

      final hasApiBacked = existing.any((o) => o['_liveOnly'] != true);
      if (hasApiBacked && _commonOptionEndpoints.containsKey(key)) {
        return;
      }

      final live = values.map((option) => <String, dynamic>{
        'value': option['value'] ?? option['id'] ?? option['displayName'] ?? option['label'],
        'displayName': option['displayName'] ?? option['label'] ?? option['text'] ?? option['value'],
        '_liveOnly': true,
      }).where((o) => '${o['value'] ?? ''}'.trim().isNotEmpty).toList();

      final apiBacked = existing.where((o) => o['_liveOnly'] != true).toList();
      final merged = <Map<String, dynamic>>[...apiBacked];
      for (final item in live) {
        if (!merged.any((o) => _optionText(o) == _optionText(item))) {
          item['_liveOnly'] = true;
          merged.add(item);
        }
      }
      if (jsonEncode(existing) != jsonEncode(merged)) changed = true;
      _options[key] = merged;
    });
    if (changed && mounted) setState(() {});
  }

  void _applyLiveSchema(Map<String, Map<String, dynamic>> incoming) {
    _schemaDebounce?.cancel();
    _schemaDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _commitSchema(incoming);
    });
  }

  void _commitSchema(Map<String, Map<String, dynamic>> incoming) {
    if (!_schemaReceived && incoming.length < 15) {
      _lastSchemaFieldCount = incoming.length;
      return;
    }
    _schemaReceived = true;
    _lastSchemaFieldCount = incoming.length;

    bool changed = false;
    final canonicalIncoming = <String, Map<String, dynamic>>{};
    incoming.forEach((rawKey, rawMeta) {
      final meta = Map<String, dynamic>.from(rawMeta);
      final key = _canonicalLiveKey(rawKey, '${meta['label'] ?? ''}');
      if (key.isNotEmpty) canonicalIncoming[key] = meta;
    });

    final incomingKeys = canonicalIncoming.keys.toSet();
    final removed = _liveSchema.keys.where((key) {
      if (incomingKeys.contains(key)) return false;
      if (_labels.containsKey(key) && !_liveDiscoveredFields.contains(key)) {
        return false;
      }
      if (_commonOptionEndpoints.containsKey(key)) return false;
      return true;
    }).toList();

    for (final key in removed) {
      _liveSchema.remove(key);
      if (_liveDiscoveredFields.remove(key)) {
        _options.remove(key);
        _c.remove(key)?.dispose();
      }
      changed = true;
    }

    for (final entry in canonicalIncoming.entries) {
      final key = entry.key;
      final meta = Map<String, dynamic>.from(entry.value);
      final previousMeta = _liveSchema[key];
      final previousShape = previousMeta == null
          ? null
          : (Map<String, dynamic>.from(previousMeta)..remove('value'));
      final currentShape = Map<String, dynamic>.from(meta)..remove('value');
      if (previousShape == null || jsonEncode(previousShape) != jsonEncode(currentShape)) {
        changed = true;
      }
      _liveSchema[key] = meta;
      final label = '${meta['label'] ?? key}'.trim();
      if (!_labels.containsKey(key) && label.isNotEmpty) {
        _labels[key] = label;
        _liveDiscoveredFields.add(key);
      }
      if (!_c.containsKey(key)) {
        _c[key] = TextEditingController(text: '${meta['value'] ?? ''}');
        changed = true;
      } else if ((_c[key]!.text.isEmpty) && '${meta['value'] ?? ''}'.isNotEmpty) {
        _c[key]!.text = '${meta['value']}';
        changed = true;
      }
      final rawOptions = meta['options'];
      if (rawOptions is List && rawOptions.isNotEmpty) {
        final parsed = <Map<String, dynamic>>[];
        for (final raw in rawOptions) {
          if (raw is Map) {
            final value = '${raw['value'] ?? raw['label'] ?? ''}'.trim();
            final text = '${raw['label'] ?? raw['value'] ?? ''}'.trim();
            if (value.isNotEmpty) parsed.add({'value': value, 'displayName': text});
          }
        }
        if (parsed.isNotEmpty) {
          final existing = _options[key] ?? <Map<String, dynamic>>[];
          if (existing.any((o) => o['_liveOnly'] != true) &&
              _commonOptionEndpoints.containsKey(key)) {
            // نثق بالـ API
          } else {
            final merged = <Map<String, dynamic>>[...existing.where((o) => o['_liveOnly'] != true)];
            for (final item in parsed) {
              if (!merged.any((o) =>
                  '${_optionValue(o)}' == '${_optionValue(item)}' ||
                  _optionText(o).trim() == _optionText(item).trim())) {
                merged.add({...item, '_liveOnly': true});
              }
            }
            final oldJson = jsonEncode(existing);
            _options[key] = merged;
            if (oldJson != jsonEncode(merged)) changed = true;
          }
        }
      }
    }
    if (changed && mounted) setState(() {});

    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _schemaReceived) {
        setState(() => _schemaStable = true);
      }
    });
  }

  bool _visible(String key) {
    if (!_schemaReceived) return true;

    final isKnownField =
        _labels.containsKey(key) && !_liveDiscoveredFields.contains(key);
    if (isKnownField) {
      final meta = _liveSchema[key];
      if (!_schemaStable) {
        if (meta != null && meta['visible'] == false) return false;
        return true;
      }
      if (meta == null) return false;
      return meta['visible'] != false;
    }

    final meta = _liveSchema[key];
    if (meta == null) return false;
    return meta['visible'] != false;
  }

  List<String> _classificationFallback() {
    final type = _c['employmentType']?.text.trim();
    if (type == 'ملاك' || type == 'ملاك دائم') return const ['موظف', 'معلم'];
    if (type == 'عقد' || type == 'محاضر') return const ['موظف بعقد', 'محاضر بعقد'];
    return const [];
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
        _loadEmployeesOptions(),
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
        _options[key] = raw
            .map((item) {
              if (item is Map) {
                final v = '${item['value'] ?? item['label'] ?? ''}'.trim();
                final t = '${item['label'] ?? item['displayName'] ?? v}'.trim();
                return {'value': v, 'displayName': t};
              }
              final s = '$item'.trim();
              return {'value': s, 'displayName': s};
            })
            .where((o) => '${o['value']}'.trim().isNotEmpty)
            .toList();
      }

      loadSimple('classification', decoded['classification']);
      loadSimple('status', decoded['currentemploymentstatus']);
      loadSimple('ministryEntity', decoded['ministryentity']);
    } catch (_) {}
  }

  int? _statusToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    final s = '$value'.trim();
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    final idx = _statusOrder.indexOf(s);
    return idx >= 0 ? idx + 1 : null;
  }

  void _initControllers(Map<String, dynamic> e) {
    final identification = e['identification'] is Map
        ? Map<String, dynamic>.from(e['identification'])
        : <String, dynamic>{};
    final address = e['address'] is Map
        ? Map<String, dynamic>.from(e['address'])
        : <String, dynamic>{};
    final employment = e['employmentRecord'] is Map
        ? Map<String, dynamic>.from(e['employmentRecord'])
        : <String, dynamic>{};
    final positions = employment['employmentPositions'];
    final statuses = employment['employmentStatuses'];
    final positionType = e['currentEmploymentPosition'] ?? employment['currentEmploymentPosition'];
    final currentPosition = positions is List && positions.isNotEmpty && positions.first is Map
        ? ((positions.first as Map)['position'] ?? (positions.first as Map)['Position'])
        : null;
    final currentStatusRecord = statuses is List && statuses.isNotEmpty && statuses.first is Map
        ? Map<String, dynamic>.from(statuses.first)
        : <String, dynamic>{};

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
      'employmentType': e['employmentType'] ?? employment['employmentType'],
      'employeeCategory': e['employeeCategory'] ?? employment['employeeCategory'],
      'status': _statusToInt(
        currentStatusRecord['statusType'] ??
            currentStatusRecord['StatusType'] ??
            e['currentEmploymentStatus'] ??
            e['status'],
      ),
      'statusDate': _dateOnly(currentStatusRecord['statusDate'] ??
          currentStatusRecord['effectiveDate'] ??
          currentStatusRecord['date']),
      'statusReason': currentStatusRecord['reason'],
      'jobDesignation': e['jobDesignation'] ?? employment['jobDesignation'],
      'employmentGrade': e['employmentGrade'] ?? employment['employmentGrade'],
      'classification': e['classification'] ?? employment['classification'],
      'currentPosition': currentPosition,
      'positionType': positionType,
      'dateOfStartWorking': _dateOnly(e['dateOfStartWorking']),
      'educationLevel': e['educationLevel'] ?? employment['educationLevel'],
      'universityName': e['universityName'] ?? employment['universityName'],
      'graduationYear': _dateOnly(e['graduationYear']),
      'specialization': e['specialization'] ?? employment['specialization'],
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

  List<String> _optionEndpointCandidates(String key) {
    if (key == 'positionType') return const ['/SelectOption/نوع الوظيفة'];
    if (key == 'nationality') return const ['/selectoption/الجنسية', '/selectoption/بلد الولادة'];
    return _commonOptionEndpoints.containsKey(key)
        ? <String>[_commonOptionEndpoints[key]!]
        : const [];
  }

  Future<void> _loadOption(String key) async {
    for (final endpoint in _optionEndpointCandidates(key)) {
      try {
        final response = await http.get(
          Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
          headers: {'Authorization': widget.token, 'Accept': 'application/json'},
        );
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final raw = decoded is Map ? (decoded['data'] ?? decoded['items'] ?? decoded['results']) : decoded;
        if (raw is List && raw.isNotEmpty) {
          _options[key] = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          return;
        }
      } catch (_) {}
    }
  }

  List<Map<String, dynamic>>? _findPath(List<Map<String, dynamic>> nodes, String targetId) {
    for (final node in nodes) {
      if (_optionValue(node)?.toString() == targetId) return [node];
      final sub = _findPath(_childrenOf(node), targetId);
      if (sub != null) return [node, ...sub];
    }
    return null;
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
      if (raw is! List) return;
      _addressCountries = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final address = _employee?['address'] is Map
          ? Map<String, dynamic>.from(_employee!['address'])
          : <String, dynamic>{};
      final stored = address['countryStructureId']?.toString();

      if (stored != null && stored.isNotEmpty) {
        final path = _findPath(_addressCountries, stored);
        if (path != null && path.length >= 3) {
          _addressCountryId = _optionValue(path[0])?.toString();
          _addressGovernorates = _childrenOf(path[0]);
          _addressGovernorateId = _optionValue(path[1])?.toString();
          _addressDistricts = _childrenOf(path[1]);
          _addressDistrictId = _optionValue(path.last)?.toString();
        }
      }

      if (_addressCountryId == null) {
        Map<String, dynamic>? iraq;
        for (final country in _addressCountries) {
          final t = _optionText(country);
          if (t.contains('العراق') || t.toLowerCase() == 'iraq') {
            iraq = country;
            break;
          }
        }
        iraq ??= _addressCountries.isNotEmpty ? _addressCountries.first : null;
        if (iraq == null) return;
        _addressCountryId = _optionValue(iraq)?.toString();
        _addressGovernorates = _childrenOf(iraq);
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
    final raw = node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  dynamic _optionValue(Map<String, dynamic> x) => x['value'] ?? x['id'] ?? x['code'];
  String _optionText(Map<String, dynamic> x) =>
      '${x['displayName'] ?? x['label'] ?? x['name'] ?? x['text'] ?? _optionValue(x) ?? ''}';

  Widget _addressDropdown(String label, String? value,
      List<Map<String, dynamic>> items, ValueChanged<String?> onChanged) {
    final safe = items.any((x) => _optionValue(x)?.toString() == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safe,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        filled: true,
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      items: items
          .map((x) => DropdownMenuItem<String>(
                value: _optionValue(x)?.toString(),
                child: Text(_optionText(x),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  List<String> _stringOptions(String key, {List<String> fallback = const []}) {
    final result = <String>[];
    for (final item in _options[key] ?? const <Map<String, dynamic>>[]) {
      final value = item['value'] ?? item['displayName'] ?? item['name'];
      if (value != null && '$value'.trim().isNotEmpty) result.add('$value');
    }
    if (key == 'classification') {
      for (final item in _classificationFallback()) {
        if (!result.contains(item)) result.add(item);
      }
    }
    for (final item in fallback) {
      if (!result.contains(item)) result.add(item);
    }
    final current = _c[key]?.text.trim() ?? '';
    if (current.isNotEmpty && !result.contains(current)) result.insert(0, current);
    return result;
  }

  String? _selected(String key) =>
      _c[key]?.text.trim().isEmpty == true ? null : _c[key]?.text.trim();

  Widget _textField(String key,
      {bool required = false,
      int maxLines = 1,
      TextInputType? keyboardType,
      bool readOnly = false}) {
    if (_liveSchema[key]?['type'] == 'select') {
      return _selectField(key, required: required || _liveSchema[key]?['required'] == true);
    }
    final controller = _c[key];
    if (controller == null) return const SizedBox.shrink();
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: _labels[key],
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.03)
            : Colors.white,
      ),
      validator: null,
      onChanged: (_) => _pushFieldLive(key, controller.text),
      onTap: readOnly &&
              (key == 'dateOfBirth' ||
                  key == 'dateOfStartWorking' ||
                  key == 'graduationYear' ||
                  key == 'statusDate')
          ? () {
              _focusLive(key);
              _pickDate(key);
            }
          : () => _focusLive(key),
    );
  }

  Widget _selectField(String key, {bool required = false, List<String> fallback = const []}) {
    final values = _stringOptions(key, fallback: fallback);
    return DropdownButtonFormField<String>(
      value: _selected(key),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _labels[key],
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.03)
            : Colors.white,
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      items: (() {
        final raw = _options[key] ?? <Map<String, dynamic>>[];
        final mapped = <DropdownMenuItem<String>>[];
        for (final item in raw) {
          final value = '${_optionValue(item) ?? ''}'.trim();
          final label = _optionText(item).trim();
          if (value.isNotEmpty && !mapped.any((x) => x.value == value)) {
            mapped.add(DropdownMenuItem<String>(
              value: value,
              child: Text(
                label.isEmpty ? value : label,
                textDirection: TextDirection.rtl,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ));
          }
        }
        for (final value in values) {
          if (!mapped.any((x) => x.value == value)) {
            mapped.add(DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                textDirection: TextDirection.rtl,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ));
          }
        }
        return mapped;
      })(),
      onTap: () => _focusLive(key),
      onChanged: (value) {
        setState(() => _c[key]!.text = value ?? '');
        _pushFieldLive(key, value ?? '');
        _focusLive(key);
        _scheduleMultiRefresh();
      },
      validator: null,
    );
  }

  List<Widget> _buildDiscoveredFields() {
    if (!_schemaReceived) return const <Widget>[];
    final sortedKeys = _liveSchema.keys.toList()
      ..sort((a, b) {
        final oa = (_liveSchema[a]?['order'] as num?)?.toInt() ?? 99999;
        final ob = (_liveSchema[b]?['order'] as num?)?.toInt() ?? 99999;
        return oa.compareTo(ob);
      });
    final fields = <Widget>[];
    for (final key in sortedKeys) {
      final meta = _liveSchema[key];
      if (meta == null) continue;
      if (meta['visible'] == false) continue;
      if (_labels.containsKey(key)) continue;
      if (_c[key] == null) continue;
      final type = '${meta['type'] ?? 'text'}';
      final label = '${meta['label'] ?? key}'.trim();
      if (label.isEmpty) continue;
      if (RegExp(r'^(arrow_drop_down|expand_more|keyboard_arrow_down)$',
              caseSensitive: false)
          .hasMatch(label)) continue;
      if (type == 'select' || type == 'checkbox') {
        fields.add(_selectField(key, required: meta['required'] == true));
      } else {
        fields.add(_textField(
          key,
          required: meta['required'] == true,
          maxLines: type == 'textarea' ? 3 : 1,
          readOnly: type == 'date',
        ));
      }
    }
    if (fields.isEmpty) return const <Widget>[];
    return <Widget>[_section('حقول إضافية من EMIS', fields)];
  }

  Widget _section(String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
          ),
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
          '${imageFile.path}_teacher_seg_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await normalizedFile.writeAsBytes(img.encodeJpg(source, quality: 90), flush: true);

      final mask = await segmenter.processImage(InputImage.fromFilePath(normalizedFile.path));
      if (mask == null || mask.width <= 0 || mask.height <= 0 || mask.confidences.isEmpty) {
        throw Exception('لم يتم الحصول على قناع صالح للشخص');
      }
      if (mask.width != source.width || mask.height != source.height) {
        throw Exception('أبعاد قناع إزالة الخلفية غير متطابقة');
      }

      final result = img.Image(width: source.width, height: source.height, numChannels: 4);
      final pixelCount = source.width * source.height;
      if (mask.confidences.length < pixelCount) {
        throw Exception('بيانات القناع غير مكتملة');
      }

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
          '${imageFile.path}_teacher_nobg_${DateTime.now().millisecondsSinceEpoch}.png');
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
              title: const Text('معاينة صورة المعلم',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12),
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
                                final processed =
                                    await _removeBackgroundUsingSelfieSegmentation(currentImage);
                                if (!mounted) return;
                                if (processed == null) {
                                  throw Exception('لم يتم الحصول على الصورة المعالجة');
                                }
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
                      icon: processing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
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
                  child: const Text('اعتماد',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
      Uri.parse('https://emis.moedu.gov.iq/api/employee/uploadimage'),
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
      _c[key]!.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employee == null) return;
    setState(() => _saving = true);

    try {
      final old = _employee!;
      final nationalId = _c['nationalId']?.text.trim() ?? '';
      if (nationalId.isNotEmpty) {
        final check = await http.get(
          Uri.parse(
              'https://emis.moedu.gov.iq/api/employee/checknationalidnumber?value=${Uri.encodeQueryComponent(nationalId)}&excludeId=${Uri.encodeQueryComponent(widget.teacherId)}'),
          headers: {'Authorization': widget.token, 'Accept': 'application/json'},
        );
        if (check.statusCode == 200) {
          final result = jsonDecode(utf8.decode(check.bodyBytes));
          if (result is Map && result['isUnique'] == false) {
            throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً');
          }
        }
      }
      final identification = old['identification'] is Map
          ? Map<String, dynamic>.from(old['identification'])
          : <String, dynamic>{};
      final oldAddress = old['address'] is Map
          ? Map<String, dynamic>.from(old['address'])
          : <String, dynamic>{};
      final oldEmployment = old['employmentRecord'] is Map
          ? Map<String, dynamic>.from(old['employmentRecord'])
          : <String, dynamic>{};

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

      String text(String key) => _c[key]?.text.trim() ?? '';

      final payload = <String, dynamic>{
        'Id': old['id'],
        'EmployeeIdNumber': text('employeeIdNumber'),
        'FamilyNumber': _nullable(text('familyNumber')),
        'IsTeacher': true,
        'EmploymentType': text('employmentType'),
        'EmployeeCategory': text('employeeCategory'),
        'Classification': text('classification'),
        'JobDesignation': _nullable(text('jobDesignation')),
        'EmploymentGrade': _nullable(text('employmentGrade')),
        'DateOfStartWorking': _nullable(text('dateOfStartWorking')),
        'EducationLevel': _nullable(text('educationLevel')),
        'GraduationYear': _nullable(text('graduationYear')),
        'UniversityName': _nullable(text('universityName')),
        'Specialization': _nullable(text('specialization')),
        'Name': text('name'),
        'FatherName': text('fatherName'),
        'GrandFatherName': text('grandFatherName'),
        'FathersGrandFatherName': text('fathersGrandFatherName'),
        'SurName': text('surName'),
        'MotherName': text('motherName'),
        'MothersFatherName': text('mothersFatherName'),
        'MothersGrandFatherName': text('mothersGrandFatherName'),
        'ImageUrl': imageUrl,
        'DateOfBirth': _nullable(text('dateOfBirth')),
        'Gender': _intOrNull(text('gender')),
        'Nationality': text('nationality'),
        'CountryOfBirth': text('countryOfBirth'),
        'HomeTown': text('homeTown'),
        'IdentificationId': 0,
        'Identification': {
          'IdNumber': nationalId,
          'IssuingCountry': text('issuingCountry'),
          'IdType': _intOrNull(text('idType')),
          'issuingDate': identification['issuingDate'],
        },
        'FatherIdentificationId': old['fatherIdentificationId'],
        'FatherIdentification': {
          'IdNumber': '',
          'IssuingCountry': 'العراق',
          'IdType': 0,
          'issuingDate': null,
        },
        'MotherTongue': text('motherTongue'),
        'MaritalStatus': text('maritalStatus'),
        'BloodGroup': text('bloodGroup'),
        'Religion': text('religion'),
        'HomePhoneNumber': _nullable(old['homePhoneNumber']),
        'Status': _intOrNull(text('status')),
        'Notes': text('notes'),
        'SpecialNeedsInformation': _nullable(text('specialNeedsInformation')),
        'EmergencyContactName': _nullable(text('emergencyContactName')),
        'EmergencyContactRelationship': _nullable(text('emergencyContactRelationship')),
        'EmergencyContactPhoneNumber': _nullable(text('emergencyContactPhoneNumber')),
        'Address': {
          'AddressType': 1,
          'Town': text('town'),
          'Area': text('area'),
          'Quarter': text('quarter'),
          'Street': text('street'),
          'ClosestLocation': text('closestLocation'),
          'countryStructureId': _addressDistrictId == null
              ? oldAddress['countryStructureId']
              : int.tryParse(_addressDistrictId!),
          'Latitude': '${oldAddress['latitude'] ?? 0}',
          'Longitude': '${oldAddress['longitude'] ?? 0}',
          'ApartmentNumber': oldAddress['apartmentNumber'] ?? '',
          'BuildingNumber': oldAddress['buildingNumber'] ?? '',
          'Address1': text('address1'),
          'Address2': text('address2'),
          'SchoolPhoneNumber': oldAddress['schoolPhoneNumber'] ?? '',
          'MobilePhoneNumber': text('mobilePhoneNumber'),
          'Email': text('email'),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث المعلم بنجاح')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تحديث المعلم: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Map<String, dynamic> _buildEmploymentRecord(Map<String, dynamic> old) {
    final record = Map<String, dynamic>.from(old);
    final statuses = old['employmentStatuses'] is List
        ? (old['employmentStatuses'] as List)
            .map((x) => x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];
    final positions = old['employmentPositions'] is List
        ? (old['employmentPositions'] as List)
            .map((x) => x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    final status = statuses.isNotEmpty ? statuses.first : <String, dynamic>{};
    status['StatusType'] = _c['status']!.text.trim();
    status['Reason'] =
        _c['statusReason']!.text.trim().isEmpty ? null : _c['statusReason']!.text.trim();
    status['StatusDate'] =
        _c['statusDate']!.text.trim().isEmpty ? null : _c['statusDate']!.text.trim();
    status['CurrentBelongToEntityId'] = int.tryParse(widget.schoolId);
    if (statuses.isEmpty) statuses.add(status);

    final position = positions.isNotEmpty ? positions.first : <String, dynamic>{};
    position['Position'] = _c['currentPosition']!.text.trim();
    position['InitiateDate'] = _c['dateOfStartWorking']!.text.trim();
    if (positions.isEmpty) positions.add(position);

    record['EmploymentStatuses'] = statuses;
    record['EmploymentPositions'] = positions;
    final statusValue = _c['status']!.text.trim();
    record['IsCurrentlyActive'] =
        statusValue.isEmpty || statusValue == '1' || statusValue == 'مستمر';
    record['CurrentBelongToEntityId'] = int.tryParse(widget.schoolId);
    record['CurrentEmploymentPosition'] = _c['positionType']!.text.trim();
    return record;
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
            const Text('الصورة الشخصية للمعلم',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                                errorBuilder: (_, __, ___) => const Icon(Icons.person,
                                    size: 80, color: Colors.grey),
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
              label: const Text('إزالة الصورة الحالية',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
        title: const Text('تعديل بيانات المعلم',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: const Color(0xFF4527A0),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
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
                              if (_visible('name')) _textField('name', required: true),
                              if (_visible('fatherName')) _textField('fatherName', required: true),
                              if (_visible('grandFatherName')) _textField('grandFatherName', required: true),
                              if (_visible('fathersGrandFatherName')) _textField('fathersGrandFatherName', required: true),
                              if (_visible('surName')) _textField('surName', required: true),
                              if (_visible('motherName')) _textField('motherName'),
                              if (_visible('mothersFatherName')) _textField('mothersFatherName'),
                              if (_visible('mothersGrandFatherName')) _textField('mothersGrandFatherName'),
                            ]),

                            _section('البيانات الشخصية', [
                              if (_visible('dateOfBirth'))
                                _textField('dateOfBirth', required: true, readOnly: true),
                              if (_visible('countryOfBirth'))
                                _selectField('countryOfBirth', required: true),
                              if (_visible('gender')) _selectField('gender', required: true),
                              if (_visible('nationality'))
                                _selectField('nationality', required: true),
                              if (_visible('homeTown')) _textField('homeTown'),
                              if (_visible('motherTongue')) _selectField('motherTongue'),
                              if (_visible('maritalStatus')) _selectField('maritalStatus'),
                              if (_visible('bloodGroup')) _selectField('bloodGroup'),
                              if (_visible('religion')) _selectField('religion'),
                              if (_visible('notes')) _textField('notes', maxLines: 3),
                            ]),

                            _section('وثيقة التعريف', [
                              if (_visible('idType')) _selectField('idType', required: true),
                              if (_visible('issuingCountry'))
                                _selectField('issuingCountry', required: true),
                              if (_visible('nationalId'))
                                _textField('nationalId',
                                    required: true, keyboardType: TextInputType.number),
                              if (_visible('employeeIdNumber'))
                                _textField('employeeIdNumber',
                                    keyboardType: TextInputType.number),
                              if (_visible('familyNumber'))
                                _textField('familyNumber',
                                    keyboardType: TextInputType.number),
                              if (_visible('documentType')) _textField('documentType'),
                              if (_visible('documentNumber')) _textField('documentNumber'),
                              if (_visible('civilRegistryNumber'))
                                _textField('civilRegistryNumber'),
                              if (_visible('recordNumber')) _textField('recordNumber'),
                              if (_visible('pageNumber')) _textField('pageNumber'),
                              if (_visible('issuingAuthority')) _textField('issuingAuthority'),
                            ]),

                            _section('البيانات الوظيفية', [
                              if (_visible('employmentType'))
                                _selectField('employmentType',
                                    required: true,
                                    fallback: const [
                                      'ملاك',
                                      'عقد',
                                      'ملاك دائم',
                                      'محاضر'
                                    ]),
                              if (_visible('employeeCategory'))
                                _selectField('employeeCategory',
                                    required: true,
                                    fallback: const ['تدريسي', 'إداري']),
                              if (_visible('classification'))
                                _selectField('classification', required: true),
                              if (_visible('jobDesignation')) _textField('jobDesignation'),
                              if (_visible('employmentGrade')) _textField('employmentGrade'),
                              if (_visible('jobTitle')) _selectField('jobTitle'),
                              if (_visible('currentPosition')) _selectField('currentPosition'),
                              if (_visible('positionType'))
                                _selectField('positionType', required: true),
                              if (_visible('dateOfStartWorking'))
                                _textField('dateOfStartWorking',
                                    required: true, readOnly: true),
                              if (_visible('schoolName')) _textField('schoolName'),
                            ]),

                            _section('الحالة الوظيفية', [
                              if (_visible('status')) _selectField('status', required: true),
                              if (_visible('statusDate'))
                                _textField('statusDate', readOnly: true),
                              if (_visible('statusReason'))
                                _textField('statusReason', maxLines: 2),
                            ]),

                            _section('التحصيل الدراسي', [
                              if (_visible('educationLevel'))
                                _selectField('educationLevel',
                                    fallback: const [
                                      'ابتدائية',
                                      'متوسطة',
                                      'إعدادية',
                                      'دبلوم',
                                      'بكالوريوس',
                                      'دبلوم عالي',
                                      'ماجستير',
                                      'دكتوراه'
                                    ]),
                              if (_visible('universityName')) _textField('universityName'),
                              if (_visible('graduationYear'))
                                _textField('graduationYear', readOnly: true),
                              if (_visible('specialization')) _textField('specialization'),
                            ]),

                            _section('ذوو الاحتياجات الخاصة والاتصال الطارئ', [
                              if (_visible('specialNeedsInformation'))
                                _textField('specialNeedsInformation'),
                              if (_visible('emergencyContactName'))
                                _textField('emergencyContactName'),
                              if (_visible('emergencyContactRelationship'))
                                _textField('emergencyContactRelationship'),
                              if (_visible('emergencyContactPhoneNumber'))
                                _textField('emergencyContactPhoneNumber',
                                    keyboardType: TextInputType.phone),
                            ]),

                            _section('العنوان ومعلومات الاتصال', [
                              _addressDropdown('الدولة', _addressCountryId, _addressCountries,
                                  (v) {
                                final country = _addressCountries
                                    .where((x) => _optionValue(x)?.toString() == v)
                                    .toList();
                                if (country.isEmpty) return;
                                setState(() {
                                  _addressCountryId = v;
                                  _addressGovernorates = _childrenOf(country.first);
                                  _addressGovernorateId = null;
                                  _addressDistricts = [];
                                  _addressDistrictId = null;
                                  if (_employee?['address'] is Map) {
                                    _employee!['address']['countryStructureId'] = null;
                                  }
                                });
                              }),
                              _addressDropdown('المحافظة', _addressGovernorateId,
                                  _addressGovernorates, (v) {
                                final gov = _addressGovernorates
                                    .where((x) => _optionValue(x)?.toString() == v)
                                    .toList();
                                if (gov.isEmpty) return;
                                setState(() {
                                  _addressGovernorateId = v;
                                  _addressDistricts = _childrenOf(gov.first);
                                  _addressDistrictId = null;
                                  if (_employee?['address'] is Map) {
                                    _employee!['address']['countryStructureId'] = null;
                                  }
                                });
                              }),
                              _addressDropdown('القضاء', _addressDistrictId, _addressDistricts,
                                  (v) {
                                setState(() {
                                  _addressDistrictId = v;
                                  if (_employee?['address'] is Map) {
                                    _employee!['address']['countryStructureId'] =
                                        v == null ? null : int.tryParse(v);
                                  }
                                });
                              }),
                              if (_visible('town')) _textField('town'),
                              if (_visible('area')) _textField('area'),
                              if (_visible('quarter')) _textField('quarter'),
                              if (_visible('street')) _textField('street'),
                              if (_visible('address1')) _textField('address1'),
                              if (_visible('address2')) _textField('address2'),
                              if (_visible('closestLocation')) _textField('closestLocation'),
                              if (_visible('email'))
                                _textField('email',
                                    keyboardType: TextInputType.emailAddress),
                              if (_visible('mobilePhoneNumber'))
                                _textField('mobilePhoneNumber',
                                    keyboardType: TextInputType.phone),
                            ]),

                            ..._buildDiscoveredFields(),

                            const SizedBox(height: 4),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save),
                                label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ بيانات المعلم'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
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
              onOptions: _applyLiveOptions,
              onSchema: _applyLiveSchema,
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
