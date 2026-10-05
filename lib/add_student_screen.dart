import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';
import 'emis_live_sync.dart';

class AddStudentScreen extends StatefulWidget {
  final String token;
  final String schoolId;

  const AddStudentScreen({
    super.key,
    required this.token,
    required this.schoolId,
  });

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  final Map<String, List<Map<String, dynamic>>> options = {};

  bool loading = true, saving = false;
  String? error;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  bool _liveSnapshotSeen = false;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';
  String? stageId, roomId;
  List<Map<String, dynamic>> stages = [], rooms = [];
  Map<String, dynamic>? stageDetails;

  // هيكل العنوان الحقيقي من EMIS: بلد ← محافظة ← قضاء.
  List<Map<String, dynamic>> _addressCountries = [];
  List<Map<String, dynamic>> _addressGovernorates = [];
  List<Map<String, dynamic>> _addressDistricts = [];
  String? _addressCountryId;
  String? _addressGovernorateId;
  String? _addressDistrictId;

  final Map<String, String> endpoints = const {
    'gender': '/selectoption/Gender',
    'countryOfBirth': '/selectoption/بلد الولادة',
    'idType': '/selectoption/IdentificationType',
    'issuingCountry': '/selectoption/بلد الإصدار',
    'motherTongue': '/selectoption/لغة',
    'bloodGroup': '/selectoption/فصيلة الدم',
    'religion': '/selectoption/الديانة',
    'specialNeeds': '/selectoption/ذوي الإحتياجات الخاصة',
    'economicLevel': '/selectoption/حالة الاقتصادية',
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
    'idType': 'نوع الهوية',
    'issuingCountry': 'بلد الإصدار',
    'dateOfBirth': 'تاريخ التولد',
    'gender': 'الجنس',
    'nationality': 'الجنسية',
    'countryOfBirth': 'بلد الولادة',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم',
    'studyLanguage': 'لغة الدراسة',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة',
    'economicLevel': 'المستوى المعيشي',
    'specialNeeds': 'الاحتياجات الخاصة',
    'notes': 'ملاحظات',
    'jinsiyaIdNumber': 'رقم شهادة الجنسية',
    'issuer': 'جهة الإصدار',
    'recordNumber': 'رقم السجل',
    'pageNumber': 'رقم الصحيفة',
    'issuingDate': 'تاريخ الإصدار',
    'nameOfDocument': 'نوع الوثيقة',
    'birthCertificateNumber': 'رقم شهادة الولادة',
    'otherIdNumber': 'رقم الهوية الأخرى',
    'town': 'المدينة / القرية',
    'area': 'الحي',
    'quarter': 'المحلة',
    'street': 'الزقاق',
    'address1': 'عنوان 1',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة',
    'homePhoneNumber': 'رقم الهاتف',
    'addressCountry': 'الدولة',
    'addressGovernorate': 'المحافظة',
    'addressDistrict': 'القضاء',
    'censusNumber': 'رقم الإحصاء',
  };

  Map<String, String> get h => {
        'Authorization': widget.token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'fatherName',
      'grandFatherName',
      'fathersGrandFatherName',
      'surName',
      'motherName',
      'mothersFatherName',
      'mothersGrandFatherName',
      'nationalId',
      'idNumber',
      'idType',
      'issuingCountry',
      'dateOfBirth',
      'gender',
      'nationality',
      'countryOfBirth',
      'homeTown',
      'motherTongue',
      'studyLanguage',
      'maritalStatus',
      'bloodGroup',
      'religion',
      'economicLevel',
      'specialNeeds',
      'notes',
      'jinsiyaIdNumber',
      'issuer',
      'recordNumber',
      'pageNumber',
      'issuingDate',
      'nameOfDocument',
      'birthCertificateNumber',
      'otherIdNumber',
      'town',
      'area',
      'quarter',
      'street',
      'address1',
      'address2',
      'closestLocation',
      'homePhoneNumber',
      'censusNumber',
    ]) {
      c[key] = TextEditingController();
    }
    c['nationality']!.text = 'العراق';
    c['countryOfBirth']!.text = 'العراق';
    c['issuingCountry']!.text = 'العراق';
    c['idType']!.text = '12';
    c['studyLanguage']!.text = 'العربية';
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

  Map<String, List<String>> _liveAliases() {
    final aliases = <String, List<String>>{
      for (final entry in labels.entries)
        entry.key: <String>[entry.key, entry.value],
      'stageId': ['stageId', 'الصف الدراسي'],
      'classRoomId': ['classRoomId', 'الشعبة'],
      'addressCountry': ['addressCountry', 'الدولة', 'country'],
      'addressGovernorate': ['addressGovernorate', 'المحافظة', 'governorate'],
      'addressDistrict': ['addressDistrict', 'القضاء', 'district'],
      'countryStructureId': ['countryStructureId', 'الموقع الجغرافي'],
      'isCoveredBySocialWelfare': [
        'isCoveredBySocialWelfare',
        'مشمول بمنحة الرعاية الاجتماعية',
      ],
    };

    // EMIS الحقيقي يستخدم هذا الـ DOM id لحقل البطاقة الوطنية الموحدة.
    // نُبقي nationalId كمفتاح Flutter/API ولا نستبدله بالـ DOM id.
    aliases['nationalId'] = <String>[
      'nationalId',
      'رقم البطاقة الوطنية الموحدة',
      'رقم البطاقة الوطنية الموحدة *',
      'base-input-رقم-البطاقة-الوطنية-الموحدة',
      '#base-input-رقم-البطاقة-الوطنية-الموحدة',
    ];

    return aliases;
  }

  Map<String, String> _liveValues() => {
        for (final entry in c.entries) entry.key: entry.value.text,
        'stageId': stageId ?? '',
        'classRoomId': roomId ?? '',
        'addressCountry': _addressCountryId ?? '',
        'addressGovernorate': _addressGovernorateId ?? '',
        'addressDistrict': _addressDistrictId ?? '',
        'countryStructureId': _addressDistrictId ?? '',
        'isCoveredBySocialWelfare': _socialWelfare ? 'true' : 'false',
      };

  void _pushLive() {
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
    _liveSyncKey.currentState?.pushValues(_liveValues());
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
      }
    }
    if (values.containsKey('stageId') && stages.isNotEmpty) {
      final v = values['stageId']!;
      final match = stages.where((x) => _value(x) == v || _text(x) == v).toList();
      if (match.isNotEmpty && stageId != _value(match.first)) {
        _stageChanged(_value(match.first));
        changed = true;
      }
    }
    if (values.containsKey('classRoomId') && rooms.isNotEmpty) {
      final v = values['classRoomId']!;
      final match = rooms.where((x) => _value(x) == v || _text(x) == v).toList();
      if (match.isNotEmpty && roomId != _value(match.first)) {
        roomId = _value(match.first);
        changed = true;
      }
    }
    if (values.containsKey('addressCountry') && _addressCountries.isNotEmpty) {
      final v = values['addressCountry']!;
      final match = _addressCountries.where((x) => _value(x) == v || _text(x) == v).toList();
      if (match.isNotEmpty) {
        _addressCountryId = _value(match.first);
        _setAddressGovernorates(match.first);
        changed = true;
      }
    }
    if (values.containsKey('addressGovernorate') && _addressGovernorates.isNotEmpty) {
      final v = values['addressGovernorate']!;
      final match = _addressGovernorates.where((x) => _value(x) == v || _text(x) == v).toList();
      if (match.isNotEmpty) {
        _addressGovernorateId = _value(match.first);
        _setAddressDistricts(match.first);
        changed = true;
      }
    }
    if (values.containsKey('isCoveredBySocialWelfare')) {
      final v = values['isCoveredBySocialWelfare']!.trim().toLowerCase();
      final next = v == 'true' || v == 'نعم' || v == 'yes';
      if (_socialWelfare != next) {
        _socialWelfare = next;
        changed = true;
      }
    }
    if (values.containsKey('addressDistrict') && _addressDistricts.isNotEmpty) {
      final v = values['addressDistrict']!;
      final match = _addressDistricts.where((x) => _value(x) == v || _text(x) == v).toList();
      if (match.isNotEmpty) {
        _addressDistrictId = _value(match.first);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  dynamic _unwrap(dynamic value) =>
      value is Map && value['data'] != null ? value['data'] : value;

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
      final futures = <String, Future<List<Map<String, dynamic>>>>{};
      for (final e in endpoints.entries) {
        futures[e.key] = _list(e.value);
      }
      futures['stageId'] = _list(
        '/selectoption/getAvailableStagesForStudent?schoolId=${widget.schoolId}',
      );

      final results = <String, List<Map<String, dynamic>>>{};
      for (final e in futures.entries) {
        results[e.key] = await e.value;
      }

      stages = results.remove('stageId') ?? [];
      options.addAll(results);
      await _loadAddressStructure();
      options['nationality'] = List<Map<String, dynamic>>.from(options['countryOfBirth'] ?? const []);
      options['studyLanguage'] = List<Map<String, dynamic>>.from(options['motherTongue'] ?? const []);

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

  Future<void> _loadAddressStructure() async {
    try {
      final raw = _unwrap(await _get('/CountryStructure/getcountrystructure'));
      if (raw is! List) return;
      final nodes = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (nodes.isEmpty) return;

      _addressCountries = nodes;
      Map<String, dynamic>? iraq;
      for (final item in nodes) {
        final name = _text(item);
        if (name.contains('العراق') || name.toLowerCase() == 'iraq') {
          iraq = item;
          break;
        }
      }
      iraq ??= nodes.first;
      _addressCountryId = _value(iraq);
      _setAddressGovernorates(iraq);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('تعذر تحميل هيكل العنوان من EMIS: $e');
    }
  }

  List<Map<String, dynamic>> _children(Map<String, dynamic> node) {
    final raw = node['children'] ?? node['items'] ?? node['subItems'] ?? node['childs'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _setAddressGovernorates(Map<String, dynamic> country) {
    _addressGovernorates = _children(country);
    _addressGovernorateId = null;
    _addressDistricts = [];
    _addressDistrictId = null;
  }

  void _setAddressDistricts(Map<String, dynamic> governorate) {
    _addressDistricts = _children(governorate);
    _addressDistrictId = null;
  }

  Future<void> _pickDate(String key) async {
    final initial = DateTime.tryParse(c[key]?.text ?? '') ?? DateTime.now();
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

  Future<void> _stageChanged(String? value) async {
    setState(() {
      stageId = value;
      roomId = null;
      rooms = [];
      stageDetails = null;
    });
    if (value == null) return;

    try {
      final result = await Future.wait([
        _list(
          '/selectoption/getClassRooms?schoolId=${widget.schoolId}&stageId=$value',
        ),
        _get('/selectoption/getstagedetails/$value'),
      ]);
      if (!mounted) return;
      setState(() {
        rooms = result[0] as List<Map<String, dynamic>>;
        final raw = _unwrap(result[1]);
        stageDetails = raw is Map
            ? Map<String, dynamic>.from(raw)
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  List<DropdownMenuItem<String>> _items(String key) {
    return (options[key] ?? [])
        .map(
          (x) => DropdownMenuItem<String>(
            value: _value(x),
            child: Text(_text(x), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
        .where((x) => x.value != null && x.value!.isNotEmpty)
        .toList();
  }

  String? _n(String key) {
    final v = c[key]?.text.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  bool get _isNationalId => c['idType']!.text == '12';
  bool get _isCivilId => c['idType']!.text == '3';
  bool get _isBirthCertificate => c['idType']!.text == '22';
  bool get _isOtherId => c['idType']!.text == '16';

  Widget _textField(
    String key, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return TextFormField(
      controller: c[key],
      maxLines: maxLines,
      keyboardType: keyboard,
      readOnly: key == 'dateOfBirth',
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
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
      validator: null,
      onChanged: (_) => _liveSyncKey.currentState?.pushValues(_liveValues()),
      onTap: key == 'dateOfBirth' ? () => _pickDate(key) : () => _focusLive(key),
    );
  }

  Widget _select(
    String key, {
    bool required = false,
    List<String>? fallback,
  }) {
    final values = <Map<String, dynamic>>[
      ...(options[key] ?? []),
      ...((fallback ?? []).map((x) => {'value': x, 'displayName': x})),
    ];
    final current = c[key]!.text.trim();
    final valid = values.any((x) => _value(x) == current);
    if (current.isNotEmpty && !valid) {
      values.insert(0, {'value': current, 'displayName': current});
    }

    return DropdownButtonFormField<String>(
      value: current.isEmpty ? null : current,
      isExpanded: true,
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
      onChanged: (v) { setState(() => c[key]!.text = v ?? ''); _focusLive(key); },
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
                color: Color(0xFF3949AB),
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Future<void> _save() async {
    if (saving) return;

    FocusScope.of(context).unfocus();

    final validationError = _validateBeforeSave();
    if (validationError != null) {
      setState(() => error = validationError);
      return;
    }

    setState(() {
      saving = true;
      error = null;
    });

    try {
      final idType = int.parse(c['idType']!.text);
      final identificationNumber =
          (_isNationalId || _isCivilId || _isBirthCertificate || _isOtherId)
              ? (_n('idNumber') ?? '')
              : '';

      // EMIS performs this check before submitting a national ID.
      if (_isNationalId && identificationNumber.isNotEmpty) {
        final check = await _get(
          '/student/checknationalidnumber?value=${Uri.encodeQueryComponent(identificationNumber)}',
        );
        if (check is Map && check['isUnique'] == false) {
          throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً في EMIS');
        }
      }

      final selectedSpecialNeeds = _n('specialNeeds');

      // This structure mirrors the payload built by EMIS itself
      // (StudentFormPage -> addStudent).
      final payload = <String, dynamic>{
        'name': _n('name') ?? '',
        'fatherName': _n('fatherName') ?? '',
        'grandFatherName': _n('grandFatherName') ?? '',
        'fathersGrandFatherName': _n('fathersGrandFatherName') ?? '',
        'surName': _n('surName') ?? '',
        'motherName': _n('motherName') ?? '',
        'mothersFatherName': _n('mothersFatherName') ?? '',
        'mothersGrandFatherName': _n('mothersGrandFatherName') ?? '',
        'imageUrl': '',
        'dateOfBirth': _n('dateOfBirth') ?? '',
        'gender': int.parse(c['gender']!.text),
        'nationality': _n('nationality') ?? 'العراق',
        'countryOfBirth': _n('countryOfBirth') ?? 'العراق',
        'homeTown': _n('homeTown') ?? '',
        'motherTongue': _n('motherTongue') ?? 'العربية',
        'maritalStatus': _n('maritalStatus') ?? '',
        'bloodGroup': _n('bloodGroup') ?? 'غير معروف',
        'religion': _n('religion') ?? 'الإسلام',
        'homePhoneNumber': _n('homePhoneNumber') ?? '',
        'notes': _n('notes') ?? '',
        'censusNumber': _n('censusNumber') ?? '',
        'isDisabled': false,
        'identification': {
          'idNumber': identificationNumber,
          'issuingCountry': _n('issuingCountry') ?? 'العراق',
          'idType': idType,
          'nameOfDocument': _n('nameOfDocument') ?? '',
          'recordNumber': _n('recordNumber') ?? '',
          'pageNumber': _n('pageNumber') ?? '',
          'issuer': _n('issuer') ?? '',
          'issuingDate': _n('issuingDate'),
        },
        'fatherIdentification': null,
        'specialNeeds': selectedSpecialNeeds == null
            ? null
            : <String>[selectedSpecialNeeds],
        'studyLanguage': _n('studyLanguage') ?? 'العربية',
        'economicLevel': _n('economicLevel') ?? '',
        'isCoveredBySocialWelfare': _socialWelfare,
        'isDroppedOutFromSchool': false,
        // This is intentionally 3 because this is what the current
        // EMIS StudentFormPage sends when adding a student.
        'lastYearResult': 3,
        'schoolId': int.parse(widget.schoolId),
        'stageId': int.parse(stageId!),
        'classRoomId': int.parse(roomId!),
        'ageExceptionReason': null,
        'genderExceptionReason': null,
        'address': {
          'addressType': 1,
          'countryStructureId': int.parse(_addressDistrictId!),
          'town': _n('town') ?? '',
          'area': _n('area') ?? '',
          'quarter': _n('quarter') ?? '',
          'street': _n('street') ?? '',
          'apartmentNumber': '',
          'buildingNumber': '',
          'address1': _n('address1') ?? '',
          'address2': _n('address2') ?? '',
          'closestLocation': _n('closestLocation') ?? '',
          'latitude': 0,
          'longitude': 0,
          'schoolPhoneNumber': '',
          'mobilePhoneNumber': '',
          'email': '',
          'website': '',
        },
      };

      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api/student/addstudent'),
        headers: h,
        body: jsonEncode(payload),
      );

      final responseText = utf8.decode(response.bodyBytes);
      dynamic responseJson;
      try {
        responseJson = jsonDecode(responseText);
      } catch (_) {
        responseJson = null;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final serverMessage = responseJson is Map
            ? '${responseJson['message'] ?? responseJson['error'] ?? responseText}'
            : responseText;
        throw Exception('HTTP ${response.statusCode}: $serverMessage');
      }

      final successMessage = responseJson is Map &&
              '${responseJson['message'] ?? ''}'.trim().isNotEmpty
          ? '${responseJson['message']}'
          : 'تمت إضافة الطالب بنجاح';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successMessage,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  bool _socialWelfare = false;

  String? _validateBeforeSave() {
    final requiredFields = <String, String>{
      'name': 'الإسم',
      'fatherName': 'إسم الأب',
      'grandFatherName': 'اسم والد الأب',
      'surName': 'اللقب',
      'motherName': 'إسم الأم',
      'mothersFatherName': 'اسم والد الأم',
      'mothersGrandFatherName': 'اسم جد الأم',
      'dateOfBirth': 'تاريخ التولد',
      'gender': 'الجنس',
      'idType': 'نوع الهوية',
      'issuingCountry': 'بلد الإصدار',
      'studyLanguage': 'لغة الدراسة',
      'economicLevel': 'المستوى المعيشي',
      'homePhoneNumber': 'رقم الهاتف',
    };

    for (final entry in requiredFields.entries) {
      if ((_n(entry.key) ?? '').isEmpty) {
        return 'يرجى إدخال ${entry.value}';
      }
    }

    if (stageId == null || stageId!.isEmpty) {
      return 'يرجى اختيار الصف الدراسي';
    }
    if (roomId == null || roomId!.isEmpty) {
      return 'يرجى اختيار الشعبة';
    }
    if (_addressDistrictId == null || _addressDistrictId!.isEmpty) {
      return 'يرجى اختيار القضاء في العنوان';
    }

    final idNumber = _n('idNumber') ?? '';
    if (_isNationalId) {
      if (!RegExp(r'^\d{12}$').hasMatch(idNumber)) {
        return 'رقم البطاقة الوطنية الموحدة يجب أن يكون 12 رقماً';
      }
    } else if (idNumber.isEmpty) {
      return 'يرجى إدخال رقم الوثيقة';
    }

    final phone = _n('homePhoneNumber')!;
    if (!RegExp(r'^[0-9٠-٩+\\- ]{7,20}$').hasMatch(phone)) {
      return 'رقم الهاتف غير صالح';
    }

    return null;
  }

  String _friendlyError(Object error) {
    final message = '$error';
    if (message.contains('SocketException')) {
      return 'تعذر الاتصال بخادم EMIS. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.';
    }
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'إضافة طالب جديد',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
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
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(17),
                  children: [
                    _intro(),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      _error(error!),
                    ],
                    const SizedBox(height: 14),
                    _section('البيانات الأساسية', [
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
                          Expanded(
                            child: _select('gender', required: true),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField('dateOfBirth'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _select('countryOfBirth'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _select('nationality'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField('homeTown'),
                    ]),
                    _section('وثيقة التعريف', [
                      _select('idType', required: true),
                      const SizedBox(height: 10),
                      if (_isNationalId)
                        _textField('nationalId', required: true, keyboard: TextInputType.number),
                      if (_isCivilId) ...[
                        _textField('idNumber', required: true, keyboard: TextInputType.number),
                        const SizedBox(height: 10),
                        _textField('jinsiyaIdNumber', keyboard: TextInputType.number),
                        const SizedBox(height: 10),
                        _textField('issuer'),
                        const SizedBox(height: 10),
                        _textField('recordNumber', keyboard: TextInputType.number),
                        const SizedBox(height: 10),
                        _textField('pageNumber', keyboard: TextInputType.number),
                        const SizedBox(height: 10),
                        _select('issuingCountry'),
                        const SizedBox(height: 10),
                        _textField('issuingDate'),
                      ],
                      if (_isBirthCertificate) ...[
                        _textField('birthCertificateNumber', required: true),
                        const SizedBox(height: 10),
                        _textField('issuer'),
                        const SizedBox(height: 10),
                        _select('issuingCountry'),
                        const SizedBox(height: 10),
                        _textField('issuingDate'),
                        const SizedBox(height: 10),
                        _textField('nameOfDocument'),
                      ],
                      if (_isOtherId) ...[
                        _textField('otherIdNumber', required: true),
                        const SizedBox(height: 10),
                        _textField('issuer'),
                        const SizedBox(height: 10),
                        _select('issuingCountry'),
                        const SizedBox(height: 10),
                        _textField('issuingDate'),
                        const SizedBox(height: 10),
                        _textField('nameOfDocument'),
                      ],
                    ]),
                    _section('البيانات الدراسية والاجتماعية', [
                      Row(
                        children: [
                          Expanded(child: _select('motherTongue')),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _select(
                              'studyLanguage',
                              fallback: const ['العربية'],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('maritalStatus')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('bloodGroup')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _select('religion')),
                          const SizedBox(width: 10),
                          Expanded(child: _select('economicLevel')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _select('specialNeeds'),
                      const SizedBox(height: 10),
                      _socialWelfareSelect(),
                      const SizedBox(height: 10),
                      _textField('homePhoneNumber', required: true, keyboard: TextInputType.phone),
                      const SizedBox(height: 10),
                      _textField('notes', maxLines: 3),
                    ]),
                    _section('التسجيل الدراسي', [
                      _selectStage(),
                      const SizedBox(height: 10),
                      _selectRoom(),
                      if (stageDetails != null) ...[
                        const SizedBox(height: 10),
                        _stageInfo(),
                      ],
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
                          setState(() {
                            _addressDistrictId = v;
                          });
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
                    ]),
                    const SizedBox(height: 2),
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
                          'حفظ الطالب',
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
                url: 'https://emis.moedu.gov.iq/centers/schools/${widget.schoolId}/individuals/students/management',
                mode: 'add',
                entity: 'student',
                token: widget.token,
                aliases: _liveAliases(),
                onSnapshot: _applyLiveSnapshot,
                onStatus: (v) { if (mounted) setState(() => _liveStatus = v); },
              ),
            ),
        ],
      ),
    );
  }

  Widget _socialWelfareSelect() {
    return DropdownButtonFormField<bool>(
      value: _socialWelfare,
      isExpanded: true,
      decoration: _decoration('مشمول بمنحة الرعاية الاجتماعية؟'),
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
      items: const [
        DropdownMenuItem<bool>(
          value: false,
          child: Text('لا', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        DropdownMenuItem<bool>(
          value: true,
          child: Text('نعم', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _socialWelfare = value);
        _focusLive('isCoveredBySocialWelfare');
      },
    );
  }

  Widget _addressDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safe = items.any((x) => _value(x) == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safe,
      isExpanded: true,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      decoration: _decoration(label),
      items: items
          .map((x) => DropdownMenuItem<String>(
                value: _value(x),
                child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)),
              ))
          .where((x) => x.value != null && x.value!.isNotEmpty)
          .toList(),
      onChanged: onChanged,
      validator: null,
    );
  }

  Widget _selectStage() => DropdownButtonFormField<String>(
        value: stageId,
        isExpanded: true,
        decoration: _decoration('الصف الدراسي').copyWith(labelStyle: const TextStyle(fontWeight: FontWeight.bold)),
        items: stages
            .map(
              (x) => DropdownMenuItem(
                value: _value(x),
                child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
            .where((x) => x.value != null && x.value!.isNotEmpty)
            .toList(),
        onChanged: (v) { _stageChanged(v); _focusLive('stageId'); },
        validator: null,
      );

  Widget _selectRoom() => DropdownButtonFormField<String>(
        value: roomId,
        isExpanded: true,
        decoration: _decoration('الشعبة').copyWith(labelStyle: const TextStyle(fontWeight: FontWeight.bold)),
        items: rooms
            .map(
              (x) => DropdownMenuItem(
                value: _value(x),
                child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
            .where((x) => x.value != null && x.value!.isNotEmpty)
            .toList(),
        onChanged: (v) { setState(() => roomId = v); _focusLive('classRoomId'); },
        validator: null,
      );

  Widget _stageInfo() {
    final d = stageDetails!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        'العمر المسموح: ${d['minAge'] ?? '-'} إلى ${d['maxAge'] ?? '-'} سنة'
        '${d['currentAcademicYear'] == null ? '' : '  •  العام الدراسي: ${d['currentAcademicYear']}'}',
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.bold,color: Color(0xFF294A85)),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
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
      );

  Widget _intro() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF4A90E2)],
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
                  Text('إضافة طالب جديد',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text(
                    'الخيارات والصفوف والشعب تُقرأ مباشرة من EMIS.',
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
