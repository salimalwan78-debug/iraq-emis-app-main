import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'app_core.dart';
import 'emis_live_sync.dart';
import 'google_speech_service.dart';
import 'legacy_speech_service.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

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
  final Map<String, GlobalKey> _voiceFieldKeys = {};
  final Map<String, List<Map<String, dynamic>>> options = {};

  bool loading = true, saving = false;
  bool _speechListening = false;
  String? _speechError;
  String? _activeVoiceField;
  String? _pendingVoiceField;
  int? _activeVoiceSessionId;
  int _nextVoiceSessionId = 0;
  bool _speechStopRequested = false;
  bool _micPointerDown = false;
  bool _voiceArrowPointerDown = false;
  bool _voiceSequentialMode = false;
  int _sequentialVoiceIndex = 0;
  String? _voiceDropdownTarget;
  bool _voiceDropdownDialogOpen = false;
  bool _specialVoiceFailureShown = false;
  StreamSubscription<Map<String, dynamic>>? _googleSpeechSubscription;
  bool _legacySpeechInitialized = false;
  bool _legacySpeechAvailable = false;
  Timer? _legacyFinalizationTimer;
  Timer? _googleFinalizationTimer;

  GlobalKey _voiceFieldKey(String key) =>
      _voiceFieldKeys.putIfAbsent(key, GlobalKey.new);

  void _scrollVoiceFieldIntoView(String key) {
    if (!mounted) return;
    final fieldKey = _voiceFieldKeys[key];
    final fieldContext = fieldKey?.currentContext;
    if (fieldContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retryContext = _voiceFieldKeys[key]?.currentContext;
        if (retryContext != null) {
          Scrollable.ensureVisible(
            retryContext,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            alignment: 0.16,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _voiceFieldKeys[key]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.16,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  String? error;
  String? _saveStatus;
  bool _saveStatusIsError = false;
  final GlobalKey<EmisLiveSyncState> _liveSyncKey = GlobalKey<EmisLiveSyncState>();
  Timer? _liveTimer;
  String _liveStatus = 'المزامنة الحية مع EMIS قيد التشغيل';
  String? stageId, roomId;
  List<Map<String, dynamic>> stages = [], rooms = [];
  Map<String, dynamic>? stageDetails;

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

  static const Set<String> _voiceFields = {
    'name', 'fatherName', 'grandFatherName', 'fathersGrandFatherName',
    'surName', 'motherName', 'mothersFatherName', 'mothersGrandFatherName',
    'homeTown', 'issuer', 'nameOfDocument', 'town', 'area', 'quarter',
    'street', 'address1', 'address2', 'closestLocation',
  };

  static const Set<String> _numericVoiceFields = {
    'nationalId', 'idNumber', 'jinsiyaIdNumber', 'recordNumber',
    'pageNumber', 'birthCertificateNumber', 'otherIdNumber',
    'homePhoneNumber', 'censusNumber',
  };

  static const Set<String> _dropdownVoiceFields = {
    'gender', 'idType', 'issuingCountry',
    'maritalStatus', 'bloodGroup', 'religion',
    'economicLevel', 'specialNeeds', 'stageId',
    'addressGovernorate', 'addressDistrict',
    'isCoveredBySocialWelfare',
  };
  static const Set<String> _dateVoiceFields = {'dateOfBirth', 'issuingDate'};

  static const List<String> _voiceSequentialOrder = [
    'name', 'fatherName', 'grandFatherName', 'fathersGrandFatherName',
    'surName', 'motherName', 'mothersFatherName', 'mothersGrandFatherName',
    'gender', 'dateOfBirth', 'countryOfBirth', 'nationality', 'homeTown',
    'idType', 'nationalId', 'idNumber', 'jinsiyaIdNumber', 'issuer',
    'recordNumber', 'pageNumber', 'issuingCountry', 'issuingDate',
    'nameOfDocument', 'birthCertificateNumber', 'otherIdNumber',
    'motherTongue', 'studyLanguage', 'maritalStatus', 'bloodGroup',
    'religion', 'economicLevel', 'specialNeeds', 'isCoveredBySocialWelfare',
    'homePhoneNumber', 'notes', 'stageId', 'classRoomId', 'addressCountry',
    'addressGovernorate', 'addressDistrict', 'town', 'area', 'quarter',
    'street', 'address1', 'address2', 'closestLocation',
  ];

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
    'stageId': 'الصف الدراسي',
    'classRoomId': 'الشعبة',
    'isCoveredBySocialWelfare': 'مشمول بمنحة الرعاية الاجتماعية؟',
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
      'name', 'fatherName', 'grandFatherName', 'fathersGrandFatherName',
      'surName', 'motherName', 'mothersFatherName', 'mothersGrandFatherName',
      'nationalId', 'idNumber', 'idType', 'issuingCountry', 'dateOfBirth',
      'gender', 'nationality', 'countryOfBirth', 'homeTown', 'motherTongue',
      'studyLanguage', 'maritalStatus', 'bloodGroup', 'religion',
      'economicLevel', 'specialNeeds', 'notes', 'jinsiyaIdNumber', 'issuer',
      'recordNumber', 'pageNumber', 'issuingDate', 'nameOfDocument',
      'birthCertificateNumber', 'otherIdNumber', 'town', 'area', 'quarter',
      'street', 'address1', 'address2', 'closestLocation', 'homePhoneNumber',
      'censusNumber',
    ]) {
      c[key] = TextEditingController();
    }
    
    c['nationality']!.text = 'العراق';
    c['countryOfBirth']!.text = 'العراق';
    c['issuingCountry']!.text = 'العراق';
    c['idType']!.text = '12';
    c['studyLanguage']!.text = 'العربية';
    c['motherTongue']!.text = 'العربية';
    c['bloodGroup']!.text = 'O+';
    c['religion']!.text = 'الإسلام';
    c['economicLevel']!.text = 'الطبقة الوسطى';
    c['address2']!.text = '0';
    c['closestLocation']!.text = '0';

    _googleSpeechSubscription = GoogleSpeechService.events.listen(_handleGoogleSpeechEvent);
    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _load();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    unawaited(GoogleSpeechService.cancelListening());
    _googleSpeechSubscription?.cancel();
    _legacyFinalizationTimer?.cancel();
    _googleFinalizationTimer?.cancel();
    unawaited(LegacySpeechService.cancel());
    for (final controller in c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in labels.entries)
          entry.key: <String>[entry.key, entry.value],
        'stageId': ['stageId', 'الصف الدراسي'],
        'classRoomId': ['classRoomId', 'الشعبة'],
        'addressCountry': ['addressCountry', 'الدولة', 'country'],
        'addressGovernorate': ['addressGovernorate', 'المحافظة', 'governorate'],
        'addressDistrict': ['addressDistrict', 'القضاء', 'district'],
        'countryStructureId': ['countryStructureId', 'الموقع الجغرافي'],
        'isCoveredBySocialWelfare': ['isCoveredBySocialWelfare', 'مشمول بمنحة الرعاية الاجتماعية'],
      };

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
    if (saving) return;
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    if (saving) return;
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
    final response = await http
        .get(
          Uri.parse('https://emis.moedu.gov.iq/api$endpoint'),
          headers: h,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('انتهت مهلة الاتصال بخادم EMIS.'),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${utf8.decode(response.bodyBytes)}');
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
      _applyDefaultAddressValues();
      options['nationality'] = List<Map<String, dynamic>>.from(options['countryOfBirth'] ?? const []);
      options['studyLanguage'] = List<Map<String, dynamic>>.from(options['motherTongue'] ?? const []);
      
      if ((c['gender']?.text.trim() ?? '').isEmpty) {
        final genderItems = options['gender'] ?? const <Map<String, dynamic>>[];
        Map<String, dynamic>? male;
        for (final item in genderItems) {
          final label = _normalizeArabicForMatch(_text(item));
          if (label == _normalizeArabicForMatch('ذكر') || label.contains(_normalizeArabicForMatch('ذكر'))) {
            male = item;
            break;
          }
        }
        if (male == null) {
          for (final item in genderItems) { if (_value(item) == '1') { male = item; break; } }
        }
        if (male != null) c['gender']!.text = _value(male);
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

  void _applyDefaultAddressValues() {
    if (_addressGovernorates.isEmpty) return;

    Map<String, dynamic>? governorate;
    for (final item in _addressGovernorates) {
      final name = _text(item).trim();
      if (name == 'القادسية' || name.contains('القادسية')) {
        governorate = item;
        break;
      }
    }
    governorate ??= _addressGovernorates.firstWhere(
      (x) => _text(x).trim() == 'القادسية',
      orElse: () => <String, dynamic>{},
    );
    if (governorate.isEmpty) return;

    _addressGovernorateId = _value(governorate);
    _setAddressDistricts(governorate);

    Map<String, dynamic>? district;
    for (final item in _addressDistricts) {
      final name = _text(item).trim();
      if (name == 'الديوانية' || name.contains('الديوانية')) {
        district = item;
        break;
      }
    }
    if (district != null) {
      _addressDistrictId = _value(district);
    }
    c['town']!.text = 'الديوانية';
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
        _list('/selectoption/getClassRooms?schoolId=${widget.schoolId}&stageId=$value'),
        _get('/selectoption/getstagedetails/$value'),
      ]);
      if (!mounted) return;
      setState(() {
        rooms = result[0] as List<Map<String, dynamic>>;
        final raw = _unwrap(result[1]);
        stageDetails = raw is Map ? Map<String, dynamic>.from(raw) : null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  String _normalizeDigits(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final out = StringBuffer();
    for (final ch in value.runes) {
      final c = String.fromCharCode(ch);
      final a = arabicIndic.indexOf(c);
      if (a >= 0) {
        out.write(a);
        continue;
      }
      final e = easternArabicIndic.indexOf(c);
      if (e >= 0) {
        out.write(e);
        continue;
      }
      out.write(c);
    }
    return out.toString();
  }

  bool get _isNationalId => c['idType']!.text == '12';
  bool get _isCivilId => c['idType']!.text == '3';
  bool get _isBirthCertificate => c['idType']!.text == '22';
  bool get _isOtherId => c['idType']!.text == '16';

  void _showVoiceMessage(String message) {
    if (!mounted) return;
    setState(() => _speechError = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  String _normalizeArabicForMatch(String value) {
    var out = value.toLowerCase().trim();
    out = out.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
    out = out.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    out = out.replaceAll('ى', 'ي').replaceAll('ة', 'ه');
    out = out.replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9 ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  List<Map<String, dynamic>> _dropdownOptionsForVoice(String key) {
    final all = <Map<String, dynamic>>[];
    switch (key) {
      case 'stageId': all.addAll(stages); break;
      case 'classRoomId': all.addAll(rooms); break;
      case 'addressCountry': all.addAll(_addressCountries); break;
      case 'addressGovernorate': all.addAll(_addressGovernorates); break;
      case 'addressDistrict': all.addAll(_addressDistricts); break;
      case 'isCoveredBySocialWelfare':
        all.addAll(const [
          {'value': false, 'displayName': 'لا'},
          {'value': true, 'displayName': 'نعم'},
        ]);
        break;
      default: all.addAll(options[key] ?? []);
    }
    if (key == 'studyLanguage') {
      all.add({'value': 'العربية', 'displayName': 'العربية'});
    }
    final current = switch (key) {
      'stageId' => stageId ?? '',
      'classRoomId' => roomId ?? '',
      'addressCountry' => _addressCountryId ?? '',
      'addressGovernorate' => _addressGovernorateId ?? '',
      'addressDistrict' => _addressDistrictId ?? '',
      'isCoveredBySocialWelfare' => _socialWelfare.toString(),
      _ => c[key]?.text.trim() ?? '',
    };
    if (current.isNotEmpty && !all.any((item) => _value(item) == current)) {
      all.add({'value': current, 'displayName': current});
    }
    final seen = <String>{};
    return all.where((item) {
      final value = _value(item).trim();
      return value.isNotEmpty && seen.add(value);
    }).toList();
  }

  void _applyDropdownVoiceChoice(String key, Map<String, dynamic> item) {
    final value = _value(item);
    switch (key) {
      case 'stageId':
        unawaited(_stageChanged(value));
        break;
      case 'classRoomId':
        roomId = value;
        _focusLive('classRoomId');
        break;
      case 'addressCountry':
        _addressCountryId = value;
        _setAddressGovernorates(item);
        _focusLive('addressCountry');
        break;
      case 'addressGovernorate':
        _addressGovernorateId = value;
        _setAddressDistricts(item);
        _focusLive('addressGovernorate');
        break;
      case 'addressDistrict':
        _addressDistrictId = value;
        _focusLive('addressDistrict');
        break;
      case 'isCoveredBySocialWelfare':
        _socialWelfare = value == 'true' || _normalizeArabicForMatch(_text(item)) == _normalizeArabicForMatch('نعم');
        _focusLive('isCoveredBySocialWelfare');
        break;
      default:
        c[key]?.text = value;
        _focusLive(key);
    }
    _liveSyncKey.currentState?.pushValues(_liveValues());
    if (mounted) setState(() {});
  }

  Widget _dropdownVoiceMic(String key) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _markMicPointerDown(),
    child: IconButton(
      tooltip: 'اختيار ${labels[key] ?? key} بالصوت',
      onPressed: () => _startDropdownVoice(key),
      icon: Icon(
        _speechListening && _activeVoiceField == key ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _speechListening && _activeVoiceField == key ? Colors.red : null,
      ),
    ),
  );

  Map<String, dynamic>? _matchDropdownOption(String key, String spoken) {
    var target = _normalizeArabicForMatch(spoken);
    if (target.isEmpty) return null;
    target = target.replaceAll(RegExp(r'^(?:اختيار|القيمة|هي|هو)\s+'), '').trim();
    final items = _dropdownOptionsForVoice(key);
    if (items.isEmpty) return null;

    String compact(String value) => _normalizeArabicForMatch(value)
        .replaceAll(RegExp(r'\bال'), '')
        .replaceAll(' ', '');

    final exact = items.where((item) {
      final label = _normalizeArabicForMatch(_text(item));
      final value = _normalizeArabicForMatch(_value(item));
      return label == target || value == target || compact(label) == compact(target);
    }).toList();
    if (exact.length == 1) return exact.first;
    if (exact.length > 1) return exact.first;

    final targetTokens = target.split(' ').where((x) => x.length >= 2).toSet();
    if (targetTokens.isEmpty) return items.firstOrNull;
    
    int bestScore = 0;
    Map<String, dynamic>? best;
    for (final item in items) {
      final label = _normalizeArabicForMatch(_text(item));
      final value = _normalizeArabicForMatch(_value(item));
      if (label.isEmpty) continue;
      final labelCompact = compact(label);
      final targetCompact = compact(target);
      int score = 0;
      if (labelCompact.length >= 3 && targetCompact.length >= 3 &&
          (labelCompact.contains(targetCompact) || targetCompact.contains(labelCompact))) {
        score = 100 + (labelCompact.length < targetCompact.length ? labelCompact.length : targetCompact.length);
      } else {
        final tokens = label.split(' ').where((x) => x.length >= 2).toSet();
        final overlap = targetTokens.intersection(tokens).length;
        if (overlap > 0) {
          score = overlap * 10 + ((overlap == tokens.length) ? 3 : 0);
        }
        if (value.isNotEmpty && compact(value) == targetCompact) score += 100;
      }
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best ?? (items.isNotEmpty ? items.first : null);
  }

  String _normalizeSpokenWord(String word) {
    var out = _normalizeArabicForMatch(word).replaceAll(' ', '');
    const exact = {'واحد', 'واحدة', 'واحده'};
    if (out.startsWith('و') && out.length > 1 && !exact.contains(out)) out = out.substring(1);
    return out;
  }

  int? _smallArabicNumber(String raw) {
    final word = _normalizeSpokenWord(raw);
    const units = <String, int>{
      'صفر': 0, 'واحد': 1, 'واحدة': 1, 'واحده': 1, 'احد': 1,
      'اثنان': 2, 'اثنين': 2, 'اثنتان': 2, 'اثنتين': 2, 'اثنتا': 2,
      'اثنتي': 2, 'اثن': 2, 'ثنين': 2, 'ثنتين': 2,
      'ثلاثة': 3, 'ثلاث': 3, 'ثلاثه': 3, 'اربعة': 4, 'اربع': 4,
      'اربعه': 4, 'أربعة': 4, 'خمسة': 5, 'خمس': 5, 'خمسه': 5,
      'ستة': 6, 'سته': 6, 'ست': 6, 'سبعة': 7, 'سبع': 7, 'سبعه': 7,
      'ثمانية': 8, 'ثماني': 8, 'تمانية': 8, 'تمانيه': 8, 'ثمنية': 8,
      'تسعة': 9, 'تسع': 9, 'تسعه': 9, 'عشرة': 10, 'عشر': 10,
      'الفين': 2000, 'ألفين': 2000,
      'مائة': 100, 'مائه': 100, 'مئة': 100, 'ميه': 100,
      'مائتين': 200, 'مئتين': 200, 'ثلاثمائة': 300, 'ثلاثمائه': 300,
      'اربعمائة': 400, 'اربعمائه': 400, 'أربعمائة': 400, 'خمسمائة': 500,
      'خمسمائه': 500, 'ستمائة': 600, 'ستمائه': 600, 'سبعمائة': 700,
      'سبعمائه': 700, 'ثمانمائة': 800, 'ثمانمائه': 800,
      'تسعمائة': 900, 'تسعمائه': 900,
      'احدعشر': 11, 'احدعشرة': 11, 'اثناشر': 12, 'اثنعشر': 12,
      'عشرين': 20, 'عشرون': 20, 'ثلاثين': 30, 'ثلاثون': 30,
      'اربعين': 40, 'اربعون': 40, 'خمسين': 50, 'خمسون': 50,
      'ستين': 60, 'ستون': 60, 'سبعين': 70, 'سبعون': 70,
      'ثمانين': 80, 'ثمانون': 80, 'تسعين': 90, 'تسعون': 90,
    };
    if (units.containsKey(word)) return units[word];
    final digits = _normalizeDigits(word);
    return RegExp(r'^\d{1,4}$').hasMatch(digits) ? int.tryParse(digits) : null;
  }

  int? _arabicYearValue(List<String> words) {
    var total = 0;
    var found = false;
    for (var i = 0; i < words.length; i++) {
      final word = _normalizeSpokenWord(words[i]);
      if (word.isEmpty || word == 'و') continue;
      if (word == 'الفين' || word == 'ألفين') { total += 2000; found = true; continue; }
      if (word == 'الف' || word == 'الاف') { total += 1000; found = true; continue; }
      if (word == 'مائة' || word == 'مائه' || word == 'مئه' || word == 'مئة' || word == 'ميه') { total += 100; found = true; continue; }
      const hundreds = <String, int>{
        'مائتين': 200, 'مئتين': 200, 'ثلاثمائه': 300, 'اربعمائه': 400,
        'خمسمائه': 500, 'ستمائه': 600, 'سبعمائه': 700, 'ثمانمائه': 800,
        'تسعمائه': 900,
      };
      if (hundreds.containsKey(word)) { total += hundreds[word]!; found = true; continue; }

      final next = i + 1 < words.length ? _normalizeSpokenWord(words[i + 1]) : '';
      const hundredWords = {'مائة', 'مائه', 'مئه', 'مئة', 'ميه'};
      final leadingNumber = _smallArabicNumber(word);
      if (leadingNumber != null && leadingNumber >= 2 && leadingNumber <= 9 && hundredWords.contains(next)) {
        total += leadingNumber * 100;
        found = true;
        i++;
        continue;
      }

      final n = _smallArabicNumber(word);
      if (n != null) { total += n; found = true; continue; }
      final numeric = RegExp(r'\d{3,4}').firstMatch(_normalizeDigits(word));
      if (numeric != null) { total += int.parse(numeric.group(0)!); found = true; }
    }
    return found ? total : null;
  }

  DateTime? _parseSpokenDate(String raw, String key) {
    final normalizedDigits = _normalizeDigits(raw);
    final digitGroups = RegExp(r'\d+').allMatches(normalizedDigits)
        .map((m) => int.tryParse(m.group(0)!)).whereType<int>().toList();
    int? day, month, year;
    if (digitGroups.length >= 3) {
      day = digitGroups[0]; month = digitGroups[1]; year = digitGroups[2];
    } else {
      final cleaned = raw.replaceAll(RegExp(r'[,،;؛/\\|]+'), ' ')
          .replaceAll('-', ' ').replaceAll('ـ', ' ').trim();
      final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 3) return null;
      day = _smallArabicNumber(words[0]);
      month = _smallArabicNumber(words[1]);
      year = _arabicYearValue(words.sublist(2));
    }
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += year >= 50 ? 1900 : 2000;
    if (year < 1900 || year > DateTime.now().year || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    if (key == 'dateOfBirth' && date.isAfter(DateTime.now())) return null;
    return date;
  }

  void _applySpokenDate(String key, DateTime date) {
    final value = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().padLeft(4, '0')}';
    c[key]?.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _liveSyncKey.currentState?.pushValues(_liveValues());
    if (mounted) setState(() {});
  }

  String _dateForApi(String? raw) {
    final value = (raw ?? '').trim();
    final display = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(value);
    if (display != null) {
      return '${display.group(3)}-${display.group(2)!.padLeft(2, '0')}-${display.group(1)!.padLeft(2, '0')}';
    }
    return value;
  }

  bool _handleSpecialVoiceResult(String key, String raw, {required bool isFinal}) {
    if (_dropdownVoiceFields.contains(key)) {
      final matched = _matchDropdownOption(key, raw);
      if (matched == null) return true;
      _applyDropdownVoiceChoice(key, matched);
      _voiceDropdownTarget = null;
      _specialVoiceFailureShown = false;
      if (_voiceDropdownDialogOpen && mounted) Navigator.of(context, rootNavigator: true).pop();
      _requestSpeechStop();
      if (mounted) setState(() {});
      return true;
    }
    if (_dateVoiceFields.contains(key)) {
      final parsed = _parseSpokenDate(raw, key);
      if (parsed == null) {
        if (isFinal && !_specialVoiceFailureShown) {
          _specialVoiceFailureShown = true;
          _showVoiceMessage('يرجى نطق اليوم ثم الشهر ثم السنة بشكل واضح لتسجيل التاريخ.');
        }
        return true;
      }
      _specialVoiceFailureShown = false;
      _applySpokenDate(key, parsed);
      _requestSpeechStop();
      return true;
    }
    return false;
  }

  Future<void> _startDropdownVoice(String key) async {
    if (_activeVoiceField == key && _activeVoiceSessionId != null) {
      _voiceDropdownTarget = null;
      if (_voiceDropdownDialogOpen && mounted) Navigator.of(context, rootNavigator: true).pop();
      _requestSpeechStop();
      return;
    }
    if (!await _ensureMicrophoneAccess() || !mounted) return;
    final items = _dropdownOptionsForVoice(key);
    if (items.isEmpty) {
      _showVoiceMessage('لا توجد قيم متاحة في قائمة ${labels[key] ?? key}.');
      return;
    }
    _voiceDropdownTarget = key;
    _specialVoiceFailureShown = false;
    _voiceDropdownDialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('انطق قيمة ${labels[key] ?? key}', textAlign: TextAlign.center),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('انطق الاسم الكامل أو جزءاً منه.', textAlign: TextAlign.center),
            const SizedBox(height: 10),
            SizedBox(height: 320, child: ListView(shrinkWrap: true, children: items.map((item) => ListTile(
              title: Text(_text(item), textAlign: TextAlign.right),
              onTap: () {
                _applyDropdownVoiceChoice(key, item);
                _voiceDropdownTarget = null;
                _voiceDropdownDialogOpen = false;
                Navigator.of(dialogContext).pop();
                _requestSpeechStop();
                if (mounted) setState(() {});
              },
            )).toList())),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء'))],
      ),
    ).then<void>((_) {
      _voiceDropdownDialogOpen = false;
      if (_voiceDropdownTarget == key) {
        _voiceDropdownTarget = null;
        if (_activeVoiceField == key) _requestSpeechStop();
      }
    }));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted && _voiceDropdownTarget == key) await _toggleVoiceInput(key);
  }

  String _cleanArabicSpeech(String value) {
    var out = value.replaceAll(RegExp(r'[A-Za-z]'), '');
    out = out.replaceAll(RegExp(r'[\u0000-\u001F]'), '');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  String _cleanNumericSpeech(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    const wordDigits = <String, String>{
      'صفر': '0', 'واحد': '1', 'واحدة': '1', 'اثنان': '2', 'اثنين': '2',
      'اثنتان': '2', 'اثنتين': '2', 'ثلاثة': '3', 'ثلاث': '3', 'أربعة': '4',
      'اربعة': '4', 'خمسة': '5', 'خمس': '5', 'ستة': '6', 'ست': '6',
      'سبعة': '7', 'سبع': '7', 'ثمانية': '8', 'ثماني': '8', 'تسعة': '9', 'تسع': '9',
    };

    final normalized = value.replaceAll('،', ' ').replaceAll(',', ' ');
    final words = normalized.split(RegExp(r'\s+')).where((x) => x.isNotEmpty);
    final out = StringBuffer();
    for (final raw in words) {
      final word = raw.replaceAll(RegExp(r'[.\-_/]'), '');
      if (word.isEmpty) continue;
      final mapped = wordDigits[word.toLowerCase()];
      if (mapped != null) {
        out.write(mapped);
        continue;
      }
      for (final rune in word.runes) {
        final ch = String.fromCharCode(rune);
        final a = arabicIndic.indexOf(ch);
        if (a >= 0) { out.write(a); continue; }
        final e = easternArabicIndic.indexOf(ch);
        if (e >= 0) { out.write(e); continue; }
        if (RegExp(r'[0-9]').hasMatch(ch)) out.write(ch);
      }
    }
    return out.toString();
  }

  bool get _voiceAvailableBySetting => AppCore.voiceInputEnabled;

  Future<bool> _ensureMicrophoneAccess() async {
    if (!_voiceAvailableBySetting) {
      _showVoiceMessage('الميكروفون مغلق من الإعدادات.');
      return false;
    }
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final requested = await Permission.microphone.request();
    if (requested.isGranted) return true;
    _showVoiceMessage('لم يتم منح صلاحية الميكروفون.');
    return false;
  }

  bool get _usingLegacyVoice => AppCore.voiceRecognitionEngine == 'legacy';

  Future<bool> _initLegacySpeech() async {
    if (_legacySpeechInitialized) return _legacySpeechAvailable;
    _legacySpeechAvailable = await LegacySpeechService.initialize(
      onStatus: (status) {
        if (!mounted || !_usingLegacyVoice) return;
        final listening = status == 'listening';
        setState(() => _speechListening = listening);
        if (!listening && (_activeVoiceSessionId != null || _speechStopRequested)) {
          _scheduleLegacyFinalization();
        }
      },
      onError: (SpeechRecognitionError error) {
        if (!mounted || !_usingLegacyVoice) return;
        setState(() {
          _speechListening = false;
          _speechError = error.errorMsg;
        });
        _scheduleLegacyFinalization();
      },
    );
    _legacySpeechInitialized = true;
    return _legacySpeechAvailable;
  }

  void _scheduleLegacyFinalization() {
    _legacyFinalizationTimer?.cancel();
    _legacyFinalizationTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_usingLegacyVoice) return;
      _finishLegacyVoiceSessionAndStartPending();
    });
  }

  Future<void> _finishLegacyVoiceSessionAndStartPending() async {
    _legacyFinalizationTimer?.cancel();
    _legacyFinalizationTimer = null;
    final pending = _pendingVoiceField;
    _pendingVoiceField = null;
    _speechStopRequested = false;
    _activeVoiceSessionId = null;
    _activeVoiceField = null;
    if (mounted) setState(() => _speechListening = false);
    if (pending != null && mounted && _usingLegacyVoice) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) await _startVoiceSession(pending);
    }
  }

  Future<void> _startLegacyVoiceSession(String key) async {
    if (!mounted || saving) return;
    final available = await _initLegacySpeech();
    if (!available || !mounted) return;

    final sessionId = ++_nextVoiceSessionId;
    _activeVoiceSessionId = sessionId;
    _activeVoiceField = key;
    _specialVoiceFailureShown = false;
    _scrollVoiceFieldIntoView(key);
    _speechStopRequested = false;
    if (mounted) {
      setState(() {
        _speechError = null;
        _speechListening = true;
      });
    }

    try {
      await LegacySpeechService.listen(
        onResult: (dynamic result) {
          if (!mounted || !_usingLegacyVoice || _activeVoiceSessionId != sessionId) return;
          final raw = '${result.recognizedWords ?? ''}'.trim();
          if (raw.isEmpty) return;
          if (_handleSpecialVoiceResult(key, raw, isFinal: result.finalResult == true)) {
            if (result.finalResult == true && _speechStopRequested) _finishLegacyVoiceSessionAndStartPending();
            return;
          }
          final text = _numericVoiceFields.contains(key) ? _cleanNumericSpeech(raw) : _cleanArabicSpeech(raw);
          if (text.isEmpty) return;
          final controller = c[key];
          if (controller == null) return;
          controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          _liveSyncKey.currentState?.pushValues(_liveValues());
          if (result.finalResult == true) {
            _finishLegacyVoiceSessionAndStartPending();
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _speechError = '$e');
      _scheduleLegacyFinalization();
    }
  }

  void _requestLegacySpeechStop({String? nextField}) {
    if (nextField != null) _pendingVoiceField = nextField;
    if (_activeVoiceSessionId == null) return;
    if (_speechStopRequested) return;
    _speechStopRequested = true;
    if (mounted) setState(() => _speechListening = false);
    unawaited(LegacySpeechService.stop().whenComplete(_scheduleLegacyFinalization));
  }

  void _scheduleGoogleFinalizationFallback() {
    _googleFinalizationTimer?.cancel();
    _googleFinalizationTimer = Timer(Duration(milliseconds: AppCore.voiceFinalizationTimeoutMs), () {
      if (!mounted || _usingLegacyVoice) return;
      if (_activeVoiceSessionId != null && _speechStopRequested) {
        _finishVoiceSessionAndStartPending();
      }
    });
  }

  void _handleGoogleSpeechEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final sessionId = int.tryParse('${event['sessionId'] ?? ''}');
    if (sessionId == null || sessionId != _activeVoiceSessionId) return;

    final type = '${event['type'] ?? ''}';
    final key = _activeVoiceField;
    if (key == null) return;

    if (type == 'listening' || type == 'ready' || type == 'begin' || type == 'partial') {
      if (!_speechListening) setState(() => _speechListening = true);
    }

    if (type == 'partial' || type == 'result') {
      final alternates = (event['alternates'] is List)
          ? (event['alternates'] as List).map((e) => '$e').toList()
          : <String>[];
      final candidates = <String>[
        '${event['text'] ?? ''}',
        ...alternates,
      ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      if (_dropdownVoiceFields.contains(key) || _dateVoiceFields.contains(key)) {
        if (candidates.isNotEmpty) {
          for (final candidate in candidates) {
            if (_handleSpecialVoiceResult(key, candidate, isFinal: type == 'result')) {
              break;
            }
          }
        }
        if (type == 'result' && _speechStopRequested) _finishVoiceSessionAndStartPending();
        return;
      }

      String text = '';
      for (final raw in candidates) {
        final cleaned = _numericVoiceFields.contains(key) ? _cleanNumericSpeech(raw) : _cleanArabicSpeech(raw);
        if (cleaned.isNotEmpty) {
          text = cleaned;
          break;
        }
      }

      if (text.isNotEmpty) {
        final controller = c[key];
        if (controller != null) {
          final current = controller.text.trim();
          final shouldApply = type == 'result' || current.isEmpty || text.length >= current.length;
          if (shouldApply) {
            controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
            _liveSyncKey.currentState?.pushValues(_liveValues());
          }
        }
      }
    }

    if (type == 'error') {
      final message = '${event['message'] ?? ''}'.trim();
      if (message.isNotEmpty && event['code'] != 7) {
        setState(() => _speechError = message);
      }
      if (_speechStopRequested) {
        _finishVoiceSessionAndStartPending();
      }
      return;
    }

    if (type == 'result') {
      if (_speechStopRequested) {
        _finishVoiceSessionAndStartPending();
      }
    }

    if (type == 'stopped' && !_speechStopRequested) {
      setState(() => _speechListening = false);
    }
  }

  Future<void> _startVoiceSession(String key) async {
    if (!mounted || saving) return;
    if (!await _ensureMicrophoneAccess()) return;
    if (_usingLegacyVoice) {
      await _startLegacyVoiceSession(key);
      return;
    }

    final info = await GoogleSpeechService.getInfo();
    if (info['available'] != true) {
      _showVoiceMessage('خدمة Google للتعرف على الكلام غير متوفرة.');
      return;
    }

    final sessionId = ++_nextVoiceSessionId;
    _activeVoiceSessionId = sessionId;
    _activeVoiceField = key;
    _specialVoiceFailureShown = false;
    _scrollVoiceFieldIntoView(key);
    _speechStopRequested = false;
    if (mounted) {
      setState(() {
        _speechError = null;
        _speechListening = true;
      });
    }

    final started = await GoogleSpeechService.startListening(
      sessionId: sessionId,
      locale: 'ar-IQ',
    );
    if (!started && mounted && _activeVoiceSessionId == sessionId) {
      setState(() => _speechListening = false);
    }
  }

  void _requestSpeechStop({String? nextField}) {
    if (_usingLegacyVoice) {
      _requestLegacySpeechStop(nextField: nextField);
      return;
    }
    if (nextField != null) _pendingVoiceField = nextField;
    if (_activeVoiceSessionId == null) {
      final pending = _pendingVoiceField;
      if (pending != null) {
        _pendingVoiceField = null;
        _startVoiceSession(pending);
      }
      return;
    }
    if (_speechStopRequested) return;

    _speechStopRequested = true;
    setState(() => _speechListening = false);
    _scheduleGoogleFinalizationFallback();
    unawaited(GoogleSpeechService.stopListening());
  }

  Future<void> _finishVoiceSessionAndStartPending() async {
    _googleFinalizationTimer?.cancel();
    _googleFinalizationTimer = null;
    final pending = _pendingVoiceField;
    _pendingVoiceField = null;
    _speechStopRequested = false;
    _activeVoiceSessionId = null;
    _activeVoiceField = null;
    if (mounted) setState(() => _speechListening = false);

    if (pending != null && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted) await _startVoiceSession(pending);
    }
  }

  void _stopVoiceFromPointer() {
    if (_voiceArrowPointerDown || _micPointerDown) {
      _voiceArrowPointerDown = false;
      _micPointerDown = false;
      return;
    }
    if (_activeVoiceSessionId != null) {
      _pendingVoiceField = null;
      _requestSpeechStop();
    }
  }

  void _markMicPointerDown() {
    _micPointerDown = true;
    Future<void>.microtask(() => _micPointerDown = false);
  }

  bool _isVoiceFieldCurrentlyVisible(String key) {
    if (!_voiceFields.contains(key) && !_numericVoiceFields.contains(key) &&
        !_dropdownVoiceFields.contains(key) && !_dateVoiceFields.contains(key)) return false;
    if (key == 'nationalId') return _isNationalId;
    if (key == 'idNumber' || key == 'jinsiyaIdNumber' || key == 'recordNumber' || key == 'pageNumber') return _isCivilId;
    if (key == 'birthCertificateNumber') return _isBirthCertificate;
    if (key == 'otherIdNumber') return _isOtherId;
    if (key == 'nameOfDocument') return _isBirthCertificate || _isOtherId || _isCivilId;
    if (key == 'issuingDate' || key == 'issuingCountry' || key == 'issuer' ||
        key == 'recordNumber' || key == 'pageNumber' || key == 'jinsiyaIdNumber' ||
        key == 'nameOfDocument') return _isCivilId || _isBirthCertificate || _isOtherId;
    if (key == 'stageId') return stages.isNotEmpty;
    if (key == 'classRoomId') return rooms.isNotEmpty;
    if (key == 'addressCountry') return _addressCountries.isNotEmpty;
    if (key == 'addressGovernorate') return _addressGovernorates.isNotEmpty;
    if (key == 'addressDistrict') return _addressDistricts.isNotEmpty;
    return c.containsKey(key) || key == 'isCoveredBySocialWelfare';
  }

  List<String> _currentVoiceSequence() => _voiceSequentialOrder
      .where(_isVoiceFieldCurrentlyVisible)
      .toList(growable: false);

  Future<void> _startSequentialVoiceMode() async {
    if (saving || !AppCore.voiceInputEnabled) return;
    if (!await _ensureMicrophoneAccess()) return;
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) return;
    setState(() {
      _voiceSequentialMode = true;
      _sequentialVoiceIndex = 0;
    });
    await _startVoiceSession(sequence.first);
  }

  void _stopSequentialVoiceMode() {
    if (!_voiceSequentialMode) return;
    setState(() => _voiceSequentialMode = false);
    _pendingVoiceField = null;
    if (_activeVoiceSessionId != null) _requestSpeechStop();
  }

  Future<void> _activateSequentialVoiceField(String key) async {
    if (_dropdownVoiceFields.contains(key)) {
      await _startDropdownVoice(key);
      return;
    }
    if (_activeVoiceSessionId != null) {
      _pendingVoiceField = key;
      _requestSpeechStop(nextField: key);
    } else {
      await _startVoiceSession(key);
    }
  }

  Future<void> _advanceSequentialVoice() async {
    if (!_voiceSequentialMode || saving) return;
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) return;
    var index = _sequentialVoiceIndex;
    if (index >= sequence.length - 1) return;
    final nextIndex = index + 1;
    setState(() => _sequentialVoiceIndex = nextIndex);
    await _activateSequentialVoiceField(sequence[nextIndex]);
  }

  Future<void> _retreatSequentialVoice() async {
    if (!_voiceSequentialMode || saving) return;
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) return;
    var index = _sequentialVoiceIndex;
    if (index <= 0) return;
    final previousIndex = index - 1;
    setState(() => _sequentialVoiceIndex = previousIndex);
    await _activateSequentialVoiceField(sequence[previousIndex]);
  }

  void _markVoiceArrowPointerDown() {
    _voiceArrowPointerDown = true;
    Future<void>.microtask(() => _voiceArrowPointerDown = false);
  }

  Future<void> _toggleSequentialModeFromButton() async {
    if (_voiceSequentialMode) {
      _stopSequentialVoiceMode();
    } else {
      await _startSequentialVoiceMode();
    }
  }

  Widget _sequentialVoiceControl() {
    final enabled = _voiceSequentialMode;
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SwitchListTile(
        secondary: Icon(
          enabled ? Icons.keyboard_double_arrow_down_rounded : Icons.keyboard_arrow_down_rounded,
          color: enabled ? Colors.green : Colors.grey,
          size: 32,
        ),
        title: const Text('التنقل الصوتي بين الحقول', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('عند التفعيل يظهر سهمان للتنقل الصوتي السريع بين الحقول.', textDirection: TextDirection.rtl),
        value: enabled,
        activeColor: Colors.green,
        onChanged: (_) => _toggleSequentialModeFromButton(),
      ),
    );
  }

  Widget _fixedSequentialArrow() {
    if (!_voiceSequentialMode) return const SizedBox.shrink();
    final sequence = _currentVoiceSequence();
    final atFirst = _sequentialVoiceIndex <= 0 || sequence.isEmpty;
    final atLast = sequence.isEmpty || _sequentialVoiceIndex >= sequence.length - 1;

    Widget arrowButton({required IconData icon, required VoidCallback? onTap, required bool disabled, required String tooltip}) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: disabled ? null : onTap,
            child: SizedBox(
              width: 58,
              height: 68,
              child: Icon(icon, size: 54, color: disabled ? Colors.grey.shade400 : Colors.green.shade700),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      top: MediaQuery.of(context).size.height * 0.38,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _markVoiceArrowPointerDown(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(AppCore.voiceArrowOpacity),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
              boxShadow: const [BoxShadow(blurRadius: 9, offset: Offset(1, 2), color: Colors.black26)],
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                arrowButton(icon: Icons.keyboard_arrow_up_rounded, onTap: _retreatSequentialVoice, disabled: atFirst, tooltip: 'السابق'),
                Container(width: 36, height: 2, color: Colors.green.shade200),
                arrowButton(icon: Icons.keyboard_arrow_down_rounded, onTap: _advanceSequentialVoice, disabled: atLast, tooltip: 'التالي'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleVoiceInput(String key) async {
    if (saving) return;
    if (!_voiceAvailableBySetting) {
      _showVoiceMessage('الميكروفون مغلق من الإعدادات.');
      return;
    }
    if (_activeVoiceField == key && _activeVoiceSessionId != null) {
      _pendingVoiceField = null;
      _requestSpeechStop();
      return;
    }
    if (_activeVoiceSessionId != null) {
      _pendingVoiceField = key;
      _requestSpeechStop(nextField: key);
      return;
    }
    await _startVoiceSession(key);
  }

  // تنسيق التاريخ اليدوي بدقة: أقصى حد 8 أرقام مع إضافة الشرطات '-' تلقائياً (dd-mm-yyyy)
  void _onDateTextChanged(String key, String value) {
    final clean = _normalizeDigits(value).replaceAll(RegExp(r'[^\d]'), '');
    final limited = clean.length > 8 ? clean.substring(0, 8) : clean;
    var formatted = '';
    
    if (limited.length > 0) {
      formatted += limited.substring(0, limited.length >= 2 ? 2 : limited.length);
    }
    if (limited.length > 2) {
      formatted += '-${limited.substring(2, limited.length >= 4 ? 4 : limited.length)}';
    }
    if (limited.length > 4) {
      formatted += '-${limited.substring(4, limited.length)}';
    }

    if (formatted != value) {
      c[key]?.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  Widget _textField(String key, {bool required = false, int maxLines = 1, TextInputType? keyboard}) {
    final isDate = _dateVoiceFields.contains(key);
    return TextFormField(
      key: _voiceFieldKeys.containsKey(key) || _voiceFields.contains(key) || _numericVoiceFields.contains(key) || isDate
          ? _voiceFieldKey(key)
          : null,
      controller: c[key],
      maxLines: maxLines,
      keyboardType: isDate ? TextInputType.number : keyboard,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      textDirection: TextDirection.rtl,
      onChanged: (val) {
        if (isDate) {
          _onDateTextChanged(key, val);
        } else {
          _liveSyncKey.currentState?.pushValues(_liveValues());
        }
      },
      onTap: () => _focusLive(key),
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
        suffixIcon: (_voiceFields.contains(key) || _numericVoiceFields.contains(key) || isDate)
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _markMicPointerDown(),
                  child: IconButton(
                    tooltip: 'الإدخال الصوتي',
                    onPressed: () => _toggleVoiceInput(key),
                    icon: Icon(
                      _speechListening && _activeVoiceField == key ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _speechListening && _activeVoiceField == key ? Colors.red : null,
                    ),
                  ),
                ),
              ])
            : null,
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3949AB))),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  void _setSaveStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _saveStatus = message;
      _saveStatusIsError = isError;
    });
  }

  void _showSaveMessage(String message, {required bool isError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (saving || _activeVoiceSessionId != null) return;
    try {
      if (!mounted) return;
      setState(() {
        saving = true;
        error = null;
        _saveStatus = 'بدأت عملية حفظ الطالب...';
        _saveStatusIsError = false;
      });
      FocusScope.of(context).unfocus();

      final validationError = _validateBeforeSave();
      if (validationError != null) throw Exception(validationError);

      _setSaveStatus('جاري التحقق من البيانات...', isError: false);
      final idType = int.parse(c['idType']!.text);
      final identificationNumber = _isNationalId
          ? _normalizeDigits(_n('nationalId') ?? '')
          : (_isCivilId ? (_n('idNumber') ?? '') : (_isBirthCertificate ? (_n('birthCertificateNumber') ?? '') : (_isOtherId ? (_n('otherIdNumber') ?? '') : '')));

      if (_isNationalId) {
        final check = await _get('/student/checknationalidnumber?value=${Uri.encodeQueryComponent(identificationNumber)}');
        if (check is Map && check['isUnique'] == false) {
          throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً في EMIS');
        }
      }

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
        'dateOfBirth': _dateForApi(_n('dateOfBirth')),
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
          'issuingDate': _dateForApi(_n('issuingDate')),
        },
        'fatherIdentification': null,
        'specialNeeds': _n('specialNeeds') == null ? null : <String>[_n('specialNeeds')!],
        'studyLanguage': _n('studyLanguage') ?? 'العربية',
        'economicLevel': _n('economicLevel') ?? '',
        'isCoveredBySocialWelfare': _socialWelfare,
        'isDroppedOutFromSchool': false,
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
          'latitude': 0, 'longitude': 0,
          'schoolPhoneNumber': '', 'mobilePhoneNumber': '', 'email': '', 'website': '',
        },
      };

      final response = await http.post(
        Uri.parse('https://emis.moedu.gov.iq/api/student/addstudent'),
        headers: h,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      final responseText = utf8.decode(response.bodyBytes);
      dynamic responseJson;
      try { responseJson = jsonDecode(responseText); } catch (_) {}

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final serverMessage = responseJson is Map ? '${responseJson['message'] ?? responseJson['error'] ?? responseText}' : responseText;
        throw Exception('رفض EMIS الطلب: $serverMessage');
      }

      final successMessage = responseJson is Map && '${responseJson['message'] ?? ''}'.trim().isNotEmpty
          ? '${responseJson['message']}'
          : 'تمت إضافة الطالب بنجاح';

      if (!mounted) return;
      setState(() { error = null; _saveStatus = successMessage; _saveStatusIsError = false; });
      _showSaveMessage(successMessage, isError: false);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final friendly = _friendlyError(e);
      if (mounted) {
        setState(() { error = friendly; _saveStatus = friendly; _saveStatusIsError = true; });
        _showSaveMessage(friendly, isError: true);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  bool _socialWelfare = false;

  String? _n(String key) {
    final v = c[key]?.text.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  String? _validateBeforeSave() {
    if ((_n('name') ?? '').isEmpty) return 'يرجى إدخال الإسم';
    if ((_n('fatherName') ?? '').isEmpty) return 'يرجى إدخال إسم الأب';
    if ((_n('grandFatherName') ?? '').isEmpty) return 'يرجى إدخال اسم والد الأب';
    if ((_n('dateOfBirth') ?? '').isEmpty) return 'يرجى إدخال تاريخ التولد';
    if (stageId == null || stageId!.isEmpty) return 'يرجى اختيار الصف الدراسي';
    if (roomId == null || roomId!.isEmpty) return 'يرجى اختيار الشعبة';
    if (_addressDistrictId == null || _addressDistrictId!.isEmpty) return 'يرجى اختيار القضاء في العنوان';
    return null;
  }

  String _friendlyError(Object error) {
    final message = '$error';
    if (message.contains('SocketException')) return 'تعذر الاتصال بخادم EMIS.';
    return message.startsWith('Exception: ') ? message.substring('Exception: '.length) : message;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _stopVoiceFromPointer(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('إضافة طالب جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]),
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
                        cacheExtent: 5000,
                        padding: const EdgeInsets.all(17),
                        children: [
                          _intro(),
                          _sequentialVoiceControl(),
                          if (!AppCore.voiceInputEnabled) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                              child: const Text('الميكروفون مغلق من الإعدادات.', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                          if (_speechError != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                              child: Text(_speechError!, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                          if (error != null) ...[const SizedBox(height: 12), _error(error!)],
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
                          _section('وثيقة التعريف', [
                            _select('idType', required: true),
                            const SizedBox(height: 10),
                            if (_isNationalId) _textField('nationalId', required: true, keyboard: TextInputType.number),
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
                                Expanded(child: _select('studyLanguage', fallback: const ['العربية'])),
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
                            if (stageDetails != null) ...[const SizedBox(height: 10), _stageInfo()],
                          ]),
                          _section('العنوان', [
                            _addressDropdown(
                              label: 'الدولة',
                              voiceKey: 'addressCountry',
                              value: _addressCountryId,
                              items: _addressCountries,
                              showMic: false,
                              onChanged: (v) {
                                final item = _addressCountries.where((x) => _value(x) == v).toList();
                                if (item.isEmpty) return;
                                setState(() { _addressCountryId = v; _setAddressGovernorates(item.first); });
                                _focusLive('addressCountry');
                              },
                            ),
                            const SizedBox(height: 10),
                            _addressDropdown(
                              label: 'المحافظة',
                              voiceKey: 'addressGovernorate',
                              value: _addressGovernorateId,
                              items: _addressGovernorates,
                              onChanged: (v) {
                                final item = _addressGovernorates.where((x) => _value(x) == v).toList();
                                if (item.isEmpty) return;
                                setState(() { _addressGovernorateId = v; _setAddressDistricts(item.first); });
                                _focusLive('addressGovernorate');
                              },
                            ),
                            const SizedBox(height: 10),
                            _addressDropdown(
                              label: 'القضاء',
                              voiceKey: 'addressDistrict',
                              value: _addressDistrictId,
                              items: _addressDistricts,
                              onChanged: (v) { setState(() { _addressDistrictId = v; }); _focusLive('addressDistrict'); },
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
                          if (_saveStatus != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _saveStatusIsError ? Colors.red.shade50 : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(_saveStatus!, style: TextStyle(fontWeight: FontWeight.bold, color: _saveStatusIsError ? Colors.red.shade800 : Colors.green.shade800)),
                            ),
                          ],
                          const SizedBox(height: 15),
                          SizedBox(
                            height: 55,
                            child: FilledButton.icon(
                              onPressed: (saving || _activeVoiceSessionId != null) ? null : _save,
                              icon: saving ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person_add_alt_1_rounded),
                              label: Text(_activeVoiceSessionId != null ? 'أوقف الميكروفون أولاً' : 'حفظ الطالب', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            ),
                          ),
                          const SizedBox(height: 25),
                        ],
                      ),
                    ),
                  ),
            _fixedSequentialArrow(),
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
      ),
    );
  }

  Widget _select(String key, {bool required = false, List<String>? fallback}) {
    final values = <Map<String, dynamic>>[
      ...(options[key] ?? []),
      ...((fallback ?? []).map((x) => {'value': x, 'displayName': x})),
    ];
    final current = c[key]!.text.trim();
    if (current.isNotEmpty && !values.any((x) => _value(x) == current)) {
      values.insert(0, {'value': current, 'displayName': current});
    }

    return DropdownButtonFormField<String>(
      key: ValueKey<String>('voice-select-$key-$current'),
      value: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
        suffixIcon: _dropdownVoiceFields.contains(key) ? _dropdownVoiceMic(key) : null,
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      items: values.map((x) => DropdownMenuItem<String>(value: _value(x), child: Text(_text(x), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
      onChanged: (v) { setState(() => c[key]!.text = v ?? ''); _focusLive(key); },
    );
  }

  Widget _socialWelfareSelect() {
    return DropdownButtonFormField<bool>(
      value: _socialWelfare,
      isExpanded: true,
      decoration: _decoration('مشمول بمنحة الرعاية الاجتماعية؟').copyWith(suffixIcon: _dropdownVoiceMic('isCoveredBySocialWelfare')),
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      items: const [
        DropdownMenuItem<bool>(value: false, child: Text('لا', style: TextStyle(fontWeight: FontWeight.bold))),
        DropdownMenuItem<bool>(value: true, child: Text('نعم', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _socialWelfare = value);
        _focusLive('isCoveredBySocialWelfare');
      },
    );
  }

  Widget _addressDropdown({required String label, required String voiceKey, required String? value, required List<Map<String, dynamic>> items, required ValueChanged<String?> onChanged, bool showMic = true}) {
    final safe = items.any((x) => _value(x) == value) ? value : null;
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('voice-address-$voiceKey-${safe ?? ''}'),
      value: safe,
      isExpanded: true,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      decoration: _decoration(label).copyWith(
        suffixIcon: showMic && _dropdownVoiceFields.contains(voiceKey) ? _dropdownVoiceMic(voiceKey) : null,
      ),
      items: items.map((x) => DropdownMenuItem<String>(value: _value(x), child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _selectStage() => DropdownButtonFormField<String>(
        key: ValueKey<String>('voice-stage-${stageId ?? ''}'),
        value: stageId,
        isExpanded: true,
        decoration: _decoration('الصف الدراسي').copyWith(suffixIcon: _dropdownVoiceMic('stageId')),
        items: stages.map((x) => DropdownMenuItem(value: _value(x), child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
        onChanged: (v) { _stageChanged(v); _focusLive('stageId'); },
      );

  Widget _selectRoom() => DropdownButtonFormField<String>(
        key: ValueKey<String>('voice-room-${roomId ?? ''}'),
        value: roomId,
        isExpanded: true,
        decoration: _decoration('الشعبة'),
        items: rooms.map((x) => DropdownMenuItem(value: _value(x), child: Text(_text(x), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
        onChanged: (v) { setState(() => roomId = v); _focusLive('classRoomId'); },
      );

  Widget _stageInfo() {
    final d = stageDetails!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(13)),
      child: Text(
        'العمر المسموح: ${d['minAge'] ?? '-'} إلى ${d['maxAge'] ?? '-'} سنة',
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF294A85)),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E6EF))),
      );

  Widget _intro() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF4A90E2)], begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            CircleAvatar(radius: 27, backgroundColor: Colors.white24, child: Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 30)),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إضافة طالب جديد', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('الخيارات والصفوف والشعب تُقرأ مباشرة من EMIS.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _error(String text) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: Colors.red.withOpacity(.07), borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
      );
}
