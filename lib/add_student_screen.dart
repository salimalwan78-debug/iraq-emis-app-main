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
      // ListView يبني العناصر القريبة من الشاشة فقط؛ أعد المحاولة بعد اكتمال
      // دورة البناء حتى يكون الحقل قد دخل شجرة العناصر.
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

  // حقول النص العربي التي نسمح لها بالإدخال الصوتي.
  // الحقول النصية العربية التي تستخدم التعرف الصوتي.
  static const Set<String> _voiceFields = {
    'name',
    'fatherName',
    'grandFatherName',
    'fathersGrandFatherName',
    'surName',
    'motherName',
    'mothersFatherName',
    'mothersGrandFatherName',
    'homeTown',
    'issuer',
    'nameOfDocument',
    'town',
    'area',
    'quarter',
    'street',
    'address1',
    'address2',
    'closestLocation',
    'notes',
  };

  // الحقول الرقمية التي يمكن أن تستفيد من التعرف الصوتي مع تحويل الكلمات
  // والأرقام العربية إلى أرقام إنجليزية قبل وضعها في الحقل.
  static const Set<String> _numericVoiceFields = {
    'nationalId',
    'idNumber',
    'jinsiyaIdNumber',
    'recordNumber',
    'pageNumber',
    'birthCertificateNumber',
    'otherIdNumber',
    'homePhoneNumber',
    'censusNumber',
  };

  // الحقول التي تستخدم قائمة منسدلة ويمكن اختيار قيمتها بالصوت.
  static const Set<String> _dropdownVoiceFields = {
    'gender',
    'countryOfBirth',
    'nationality',
    'idType',
    'issuingCountry',
    'motherTongue',
    'studyLanguage',
    'maritalStatus',
    'bloodGroup',
    'religion',
    'economicLevel',
    'specialNeeds',
    'isCoveredBySocialWelfare',
    'addressCountry',
    'addressGovernorate',
    'addressDistrict',
    'stageId',
    'classRoomId',
  };

  // الحقول التي تعرض تقويماً ويمكن تعبئتها صوتياً.
  static const Set<String> _dateVoiceFields = {
    'dateOfBirth',
    'issuingDate',
  };

  String? _activeVoiceSelectionKey;
  BuildContext? _voiceSelectionSheetContext;

  // ترتيب الحقول التي ينتقل بينها زر السهم الثابت. الحقول المخفية بحسب نوع
  // الهوية لا تدخل في التسلسل، وكذلك أي حقل غير ظاهر فعلياً في الشاشة.
  static const List<String> _voiceSequentialOrder = [
    'name', 'fatherName', 'grandFatherName', 'fathersGrandFatherName',
    'surName', 'motherName', 'mothersFatherName', 'mothersGrandFatherName',
    'gender', 'dateOfBirth', 'countryOfBirth', 'nationality', 'homeTown',
    'idType', 'nationalId', 'idNumber', 'jinsiyaIdNumber', 'issuer',
    'recordNumber', 'pageNumber', 'issuingCountry', 'issuingDate',
    'birthCertificateNumber', 'otherIdNumber', 'nameOfDocument',
    'motherTongue', 'studyLanguage', 'maritalStatus', 'bloodGroup',
    'religion', 'economicLevel', 'specialNeeds', 'homePhoneNumber', 'notes',
    'stageId', 'classRoomId', 'addressCountry', 'addressGovernorate',
    'addressDistrict', 'town', 'area', 'quarter', 'street', 'address1',
    'address2', 'closestLocation', 'censusNumber',
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
    c['gender']!.text = '1';
    c['studyLanguage']!.text = 'العربية';
    // القيم الافتراضية المطلوبة عند فتح نموذج إضافة الطالب.
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
    // أثناء الحفظ نوقف المزامنة العكسية مؤقتاً حتى لا تقوم صفحة EMIS
    // بإعادة قيمة قديمة إلى الحقول أثناء تنفيذ طلب addstudent.
    if (saving) return;
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _focusLive(String key) {
    _liveSyncKey.currentState?.focusField(key);
    _liveSyncKey.currentState?.pushValues(_liveValues());
  }

  void _applyLiveSnapshot(Map<String, String> values) {
    // لا نسمح للمزامنة الحية بتغيير بيانات الطالب أثناء عملية الحفظ.
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
          onTimeout: () => throw TimeoutException(
            'انتهت مهلة الاتصال بخادم EMIS.',
          ),
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
      final genderOptions = options['gender'] ?? const <Map<String, dynamic>>[];
      final male = genderOptions.where((x) => _normalizeVoiceMatch(_text(x)) == 'ذكر').toList();
      if (male.isNotEmpty) c['gender']!.text = _value(male.first);
      await _loadAddressStructure();
      _applyDefaultAddressValues();
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
      'صفر': '0',
      'واحد': '1',
      'واحدة': '1',
      'اثنان': '2',
      'اثنين': '2',
      'اثنتان': '2',
      'اثنتين': '2',
      'ثلاثة': '3',
      'ثلاث': '3',
      'أربعة': '4',
      'اربعة': '4',
      'أربعه': '4',
      'اربعه': '4',
      'خمسة': '5',
      'خمس': '5',
      'ستة': '6',
      'ست': '6',
      'سبعة': '7',
      'سبع': '7',
      'ثمانية': '8',
      'ثماني': '8',
      'تسعة': '9',
      'تسع': '9',
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
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
        if (a >= 0) {
          out.write(a);
          continue;
        }
        final e = easternArabicIndic.indexOf(ch);
        if (e >= 0) {
          out.write(e);
          continue;
        }
        if (RegExp(r'[0-9]').hasMatch(ch)) out.write(ch);
      }
    }
    return out.toString();
  }

  int? _arabicNumber(String raw) {
    final s = _normalizeVoiceMatch(raw);
    if (s.isEmpty) return null;
    final direct = int.tryParse(_cleanNumericSpeech(s));
    if (direct != null) return direct;
    final ones = <String,int>{'صفر':0,'واحد':1,'واحدة':1,'اثنان':2,'اثنين':2,'اثنتان':2,'اثنتين':2,'ثلاثة':3,'ثلاث':3,'اربعة':4,'أربعة':4,'اربعه':4,'أربعه':4,'خمسة':5,'خمس':5,'ستة':6,'ست':6,'سبعة':7,'سبع':7,'ثمانية':8,'ثماني':8,'تمانية':8,'تمانيه':8,'تسعة':9,'تسع':9,'عشرة':10,'عشر':10,'احد عشر':11,'أحد عشر':11,'اثنا عشر':12,'اثني عشر':12,'ثلاثة عشر':13,'اربعة عشر':14,'خمسة عشر':15,'ستة عشر':16,'سبعة عشر':17,'ثمانية عشر':18,'تسعة عشر':19};
    final tens = <String,int>{'عشرون':20,'عشرين':20,'ثلاثون':30,'ثلاثين':30,'اربعون':40,'أربعون':40,'اربعين':40,'خمسون':50,'خمسين':50,'ستون':60,'ستين':60,'سبعون':70,'سبعين':70,'ثمانون':80,'ثمانين':80,'تسعون':90,'تسعين':90};
    final hundreds = <String,int>{'مائة':100,'مئه':100,'مية':100,'مئتان':200,'مائتان':200,'مئتين':200,'مائتين':200,'ثلاثمائة':300,'ثلاثمئه':300,'أربعمائة':400,'اربعمائة':400,'خمسمائة':500,'ستمائة':600,'سبعمائة':700,'ثمانمائة':800,'تسعمائة':900};
    var total = 0, current = 0;
    final words = s.replaceAll('و', ' و ').split(RegExp(r'\s+')).where((x)=>x.isNotEmpty).toList();
    for (final w0 in words) {
      final w = w0.trim();
      if (w == 'و') continue;
      if (w == 'الف' || w == 'ألف') { current = current == 0 ? 1 : current; total += current * 1000; current = 0; continue; }
      if (hundreds.containsKey(w)) { current += hundreds[w]!; continue; }
      if (tens.containsKey(w)) { current += tens[w]!; continue; }
      if (ones.containsKey(w)) { current += ones[w]!; continue; }
      if (w.startsWith('الف')) { total += 1000; current = 0; continue; }
    }
    final result = total + current;
    return result > 0 ? result : null;
  }

  String? _parseSpokenDate(String raw) {
    var text = raw.replaceAll('،', ' ').replaceAll('-', ' ').replaceAll('/', ' ');
    text = text.replaceAll('\u0660','0').replaceAll('\u0661','1').replaceAll('\u0662','2').replaceAll('\u0663','3').replaceAll('\u0664','4').replaceAll('\u0665','5').replaceAll('\u0666','6').replaceAll('\u0667','7').replaceAll('\u0668','8').replaceAll('\u0669','9');
    final yearMarkers = RegExp(r'\b(?:الف|ألف|الفين|ألفين|مائة|مئه|مائة|مائتين|مئتين|تسعمائة|ثمانمائة|سبعمائة|ستمائة|خمسمائة|أربعمائة|اربعمائة|ثلاثمائة)\b');
    final match = yearMarkers.firstMatch(text);
    String first = text, yearPart = '';
    if (match != null) { first = text.substring(0, match.start); yearPart = text.substring(match.start); }
    final numericTokens = RegExp(r'\d+').allMatches(first).map((m)=>int.tryParse(m.group(0)!)).whereType<int>().toList();
    final spokenTokens = first.split(RegExp(r'\s+')).where((x)=>x.isNotEmpty).toList();
    final firstNums = <int>[];
    for (final token in spokenTokens) {
      final n = int.tryParse(token) ?? _arabicNumber(token);
      if (n != null && n >= 0 && n <= 31) firstNums.add(n);
    }
    final nums = numericTokens.length >= 2 ? numericTokens : firstNums;
    if (nums.length < 2) return null;
    final day = nums[0], month = nums[1];
    int? year;
    if (yearPart.isNotEmpty) year = _arabicNumber(yearPart);
    if (year == null) {
      final allNums = RegExp(r'\d+').allMatches(text).map((m)=>int.tryParse(m.group(0)!)).whereType<int>().toList();
      if (allNums.length >= 3) year = allNums.last;
    }
    if (year == null || day < 1 || day > 31 || month < 1 || month > 12 || year < 1900 || year > DateTime.now().year) return null;
    try { final d = DateTime(year, month, day); if (d.year != year || d.month != month || d.day != day) return null; } catch (_) { return null; }
    return '${year.toString().padLeft(4,'0')}-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';
  }

  bool get _voiceAvailableBySetting => AppCore.voiceInputEnabled;

  Future<bool> _ensureMicrophoneAccess() async {
    if (!_voiceAvailableBySetting) {
      _showVoiceMessage(
        'الميكروفون مغلق من الإعدادات. افتح الإعدادات وفَعّل «الميكروفون والتعرف الصوتي» ثم عد إلى إضافة الطالب.',
      );
      return false;
    }

    final status = await Permission.microphone.status;
    if (status.isGranted) return true;

    final requested = await Permission.microphone.request();
    if (requested.isGranted) return true;

    _showVoiceMessage(
      'لم يتم منح صلاحية الميكروفون. افتح إعدادات Android واسمح للتطبيق باستخدام الميكروفون.',
    );
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
        if (!listening && _activeVoiceSessionId != null && !_speechStopRequested) {
          _scheduleLegacyFinalization();
        }
        if (!listening && _speechStopRequested) {
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
    if (!available || !mounted) {
      _showVoiceMessage('التعرف الصوتي الاحتياطي غير متاح على الجهاز.');
      return;
    }

    final sessionId = ++_nextVoiceSessionId;
    _activeVoiceSessionId = sessionId;
    _activeVoiceField = key;
    _scrollVoiceFieldIntoView(key);
    if (_dropdownVoiceFields.contains(key)) {
      unawaited(_openVoiceOptions(key));
    }
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
          final text = _numericVoiceFields.contains(key)
              ? _cleanNumericSpeech(raw)
              : _cleanArabicSpeech(raw);
          if (text.isEmpty) return;
          if (_dropdownVoiceFields.contains(key)) {
            _applyVoiceDropdownSelection(key, text);
          } else if (_dateVoiceFields.contains(key)) {
            final parsed = _parseSpokenDate(text);
            if (parsed != null && c[key] != null) {
              c[key]!.text = parsed;
              _liveSyncKey.currentState?.pushValues(_liveValues());
            }
          } else {
            final controller = c[key];
            if (controller == null) return;
            controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
            _liveSyncKey.currentState?.pushValues(_liveValues());
          }
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
      ].map((e) => e.trim()).where((e) => e.isNotEmpty);

      String text = '';
      for (final raw in candidates) {
        final cleaned = _numericVoiceFields.contains(key)
            ? _cleanNumericSpeech(raw)
            : _cleanArabicSpeech(raw);
        if (cleaned.isNotEmpty) { text = cleaned; break; }
      }

      if (text.isNotEmpty && _dropdownVoiceFields.contains(key) && type == 'result') {
        final selected = _applyVoiceDropdownSelection(key, text);
        if (!selected && _voiceSelectionSheetContext != null) {
          _showVoiceMessage('لم أتعرف على «$text» كقيمة في هذه القائمة. أعد النطق أو اخترها يدويًا.');
        }
      } else if (text.isNotEmpty && _dateVoiceFields.contains(key) && type == 'result') {
        final parsed = _parseSpokenDate(text);
        if (parsed != null) {
          final controller = c[key];
          if (controller != null) {
            controller.value = TextEditingValue(text: parsed, selection: TextSelection.collapsed(offset: parsed.length));
            _liveSyncKey.currentState?.pushValues(_liveValues());
          }
        }
      } else if (text.isNotEmpty) {
        final controller = c[key];
        if (controller != null) {
          final current = controller.text.trim();
          final shouldApply = type == 'result' || current.isEmpty || text.length >= current.length;
          if (shouldApply) {
            controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
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
      // هذه النتيجة تخص sessionId نفسه. لا نستخدم الحقل الحالي بشكل عشوائي؛
      // key محفوظ مع الجلسة الحالية، ثم نبدأ الحقل المعلّق فقط بعد وصول النتيجة.
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
      _showVoiceMessage(
        'خدمة Google للتعرف على الكلام غير متوفرة. تأكد من تثبيت أو تحديث تطبيق Google ثم أعد المحاولة.',
      );
      return;
    }

    final sessionId = ++_nextVoiceSessionId;
    _activeVoiceSessionId = sessionId;
    _activeVoiceField = key;
    _scrollVoiceFieldIntoView(key);
    if (_dropdownVoiceFields.contains(key)) {
      unawaited(_openVoiceOptions(key));
    }
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
    // لا ننتظر هنا. Google يعيد النتيجة النهائية بعد stopListening، وبعدها
    // _handleGoogleSpeechEvent يربطها بنفس sessionId ثم يفتح الحقل التالي.
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
    // السهم الثابت يضع هذا العلم قبل أن يصل pointer إلى Listener الأب؛
    if (_voiceArrowPointerDown) {
      _voiceArrowPointerDown = false;
      return;
    }
    // الميكروفون نفسه يضع هذا العلم قبل أن يصل pointer إلى Listener الأب؛
    // لذلك الضغط على الميكروفون لا يوقف الجلسة قبل تنفيذ onPressed.
    if (_micPointerDown) {
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
    if (!_voiceFields.contains(key) &&
        !_numericVoiceFields.contains(key) &&
        !_dropdownVoiceFields.contains(key) &&
        !_dateVoiceFields.contains(key)) return false;
    if (key == 'nationalId') return _isNationalId;
    if (key == 'idNumber' || key == 'jinsiyaIdNumber' || key == 'recordNumber' || key == 'pageNumber') return _isCivilId;
    if (key == 'birthCertificateNumber') return _isBirthCertificate;
    if (key == 'otherIdNumber') return _isOtherId;
    if (key == 'nameOfDocument') return _isBirthCertificate || _isOtherId || _isCivilId;
    if (key == 'issuer' || key == 'issuingCountry' || key == 'issuingDate') return _isCivilId || _isBirthCertificate || _isOtherId;
    if (key == 'classRoomId') return rooms.isNotEmpty;
    if (key == 'addressCountry') return _addressCountries.isNotEmpty;
    if (key == 'addressGovernorate') return _addressGovernorates.isNotEmpty;
    if (key == 'addressDistrict') return _addressDistricts.isNotEmpty;
    return c.containsKey(key) || key == 'stageId';
  }

  List<String> _currentVoiceSequence() => _voiceSequentialOrder
      .where(_isVoiceFieldCurrentlyVisible)
      .toList(growable: false);

  List<Map<String, dynamic>> _voiceOptionsForKey(String key) {
    if (key == 'isCoveredBySocialWelfare') {
      return const [
        {'value': 'false', 'displayName': 'لا'},
        {'value': 'true', 'displayName': 'نعم'},
      ];
    }
    if (key == 'stageId') return stages;
    if (key == 'classRoomId') return rooms;
    if (key == 'addressCountry') return _addressCountries;
    if (key == 'addressGovernorate') return _addressGovernorates;
    if (key == 'addressDistrict') return _addressDistricts;
    return options[key] ?? const <Map<String, dynamic>>[];
  }

  String _normalizeVoiceMatch(String value) {
    var s = value.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[إأآٱ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '');
    s = s.replaceAll(RegExp(r'[^؀-ۿa-z0-9]+'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _applyVoiceDropdownSelection(String key, String spoken) {
    final spokenNorm = _normalizeVoiceMatch(spoken);
    if (spokenNorm.isEmpty) return false;
    final items = _voiceOptionsForKey(key);
    if (items.isEmpty) return false;

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final item in items) {
      final name = _normalizeVoiceMatch(_text(item));
      if (name.isEmpty) continue;
      var score = 0;
      if (spokenNorm == name) {
        score = 1000;
      } else if (spokenNorm.contains(name)) {
        score = 800 + name.length;
      } else if (name.contains(spokenNorm)) {
        score = 600 + spokenNorm.length;
      } else {
        for (final word in name.split(' ')) {
          if (word.length >= 2 && spokenNorm.contains(word)) {
            score = score < 400 ? 400 + word.length : score;
          }
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    // لا نغلق قائمة الاختيارات عند عدم العثور على تطابق؛ يبقى بإمكان المستخدم
    // إعادة النطق أو اختيار القيمة يدويًا دون فقدان الصفحة أو القائمة.
    if (best == null || bestScore < 400) return false;

    final value = _value(best);
    if (key == 'isCoveredBySocialWelfare') {
      final v = value == 'true' || _normalizeVoiceMatch(_text(best)) == 'نعم';
      setState(() => _socialWelfare = v);
      _focusLive(key);
    } else if (key == 'stageId') {
      _stageChanged(value);
      _focusLive(key);
    } else if (key == 'classRoomId') {
      setState(() => roomId = value);
      _focusLive(key);
    } else if (key == 'addressCountry') {
      final item = _addressCountries.firstWhere(
        (x) => _value(x) == value,
        orElse: () => <String, dynamic>{},
      );
      if (item.isEmpty) return false;
      setState(() {
        _addressCountryId = value;
        _setAddressGovernorates(item);
      });
      _focusLive(key);
    } else if (key == 'addressGovernorate') {
      final item = _addressGovernorates.firstWhere(
        (x) => _value(x) == value,
        orElse: () => <String, dynamic>{},
      );
      if (item.isEmpty) return false;
      setState(() {
        _addressGovernorateId = value;
        _setAddressDistricts(item);
      });
      _focusLive(key);
    } else if (key == 'addressDistrict') {
      setState(() => _addressDistrictId = value);
      _focusLive(key);
    } else {
      final controller = c[key];
      if (controller == null) return false;
      setState(() => controller.text = value);
      _focusLive(key);
    }
    _closeVoiceOptions();
    return true;
  }

  Future<void> _openVoiceOptions(String key) async {
    if (!mounted) return;
    final items = _voiceOptionsForKey(key);
    if (items.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) {
        _voiceSelectionSheetContext = sheetContext;
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * .62),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final selected = key == 'stageId' ? stageId == _value(item) :
                      key == 'classRoomId' ? roomId == _value(item) :
                      key == 'addressCountry' ? _addressCountryId == _value(item) :
                      key == 'addressGovernorate' ? _addressGovernorateId == _value(item) :
                      key == 'addressDistrict' ? _addressDistrictId == _value(item) :
                      key == 'isCoveredBySocialWelfare' ? (_socialWelfare == (_value(item) == 'true')) :
                      c[key]?.text == _value(item);
                  return ListTile(
                    leading: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? Colors.green : Colors.grey),
                    title: Text(_text(item), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      // _applyVoiceDropdownSelection يغلق نافذة الخيارات بنفسه.
                      // لا تنفذ pop ثانية هنا، وإلا ستُغلق الصفحة الأم (إضافة طالب).
                      _pendingVoiceField = null;
                      _requestSpeechStop();
                      _applyVoiceDropdownSelection(key, _text(item));
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    _voiceSelectionSheetContext = null;
  }

  void _closeVoiceOptions() {
    final sheetContext = _voiceSelectionSheetContext;
    _voiceSelectionSheetContext = null;
    if (sheetContext != null && sheetContext.mounted) Navigator.of(sheetContext).pop();
  }

  Future<void> _startSequentialVoiceMode() async {
    if (saving || !AppCore.voiceInputEnabled) return;
    if (!await _ensureMicrophoneAccess()) return;
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) {
      _showVoiceMessage('لا توجد حقول صوتية متاحة حالياً.');
      return;
    }
    setState(() {
      _voiceSequentialMode = true;
      _sequentialVoiceIndex = 0;
    });
    await _startVoiceSession(sequence.first);
    if (mounted && _activeVoiceSessionId == null) {
      setState(() => _voiceSequentialMode = false);
    }
  }

  void _stopSequentialVoiceMode() {
    if (!_voiceSequentialMode) return;
    setState(() => _voiceSequentialMode = false);
    _pendingVoiceField = null;
    if (_activeVoiceSessionId != null) _requestSpeechStop();
  }

  Future<void> _advanceSequentialVoice() async {
    if (!_voiceSequentialMode || saving) return;
    if (!AppCore.voiceInputEnabled) {
      _showVoiceMessage('الميكروفون مغلق من الإعدادات.');
      return;
    }
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) return;

    var index = _sequentialVoiceIndex;
    if (index >= sequence.length) index = sequence.length - 1;
    if (index >= sequence.length - 1) {
      _showVoiceMessage('تم الوصول إلى آخر حقل صوتي.');
      return;
    }

    final nextIndex = index + 1;
    final next = sequence[nextIndex];
    if (mounted) setState(() => _sequentialVoiceIndex = nextIndex);

    if (_activeVoiceSessionId != null) {
      _pendingVoiceField = next;
      _requestSpeechStop(nextField: next);
    } else {
      await _startVoiceSession(next);
    }
  }

  Future<void> _retreatSequentialVoice() async {
    if (!_voiceSequentialMode || saving) return;
    if (!AppCore.voiceInputEnabled) {
      _showVoiceMessage('الميكروفون مغلق من الإعدادات.');
      return;
    }
    final sequence = _currentVoiceSequence();
    if (sequence.isEmpty) return;

    var index = _sequentialVoiceIndex;
    if (index <= 0) {
      _showVoiceMessage('أنت عند أول حقل صوتي.');
      return;
    }

    final previousIndex = index - 1;
    final previous = sequence[previousIndex];
    if (mounted) setState(() => _sequentialVoiceIndex = previousIndex);

    if (_activeVoiceSessionId != null) {
      _pendingVoiceField = previous;
      _requestSpeechStop(nextField: previous);
    } else {
      await _startVoiceSession(previous);
    }
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
        title: const Text(
          'التنقل الصوتي بين الحقول',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'عند التفعيل يبدأ من أول حقل صوتي ويظهر سهمان ثابتان يسار الشاشة: للأعلى للرجوع وللأسفل للانتقال.',
          textDirection: TextDirection.rtl,
        ),
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

    Widget arrowButton({
      required IconData icon,
      required VoidCallback? onTap,
      required bool disabled,
      required String tooltip,
    }) {
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
              child: Icon(
                icon,
                size: 54,
                color: disabled ? Colors.grey.shade400 : Colors.green.shade700,
              ),
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
              boxShadow: const [
                BoxShadow(blurRadius: 9, offset: Offset(1, 2), color: Colors.black26),
              ],
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                arrowButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  onTap: _retreatSequentialVoice,
                  disabled: atFirst,
                  tooltip: 'العودة إلى الحقل الصوتي السابق',
                ),
                Container(
                  width: 36,
                  height: 2,
                  color: Colors.green.shade200,
                ),
                arrowButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: _advanceSequentialVoice,
                  disabled: atLast,
                  tooltip: 'الانتقال إلى الحقل الصوتي التالي',
                ),
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
      _showVoiceMessage(
        'الميكروفون مغلق من الإعدادات. افتح الإعدادات وفَعّل «الميكروفون والتعرف الصوتي» ثم عد إلى إضافة الطالب.',
      );
      return;
    }

    if (_voiceSequentialMode) {
      final sequence = _currentVoiceSequence();
      final selectedIndex = sequence.indexOf(key);
      if (selectedIndex >= 0 && mounted) {
        setState(() => _sequentialVoiceIndex = selectedIndex);
      }
    }

    final current = _activeVoiceField;
    if (current == key && _activeVoiceSessionId != null) {
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

  Widget _textField(
    String key, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return TextFormField(
      key: (_voiceFields.contains(key) || _numericVoiceFields.contains(key) || _dateVoiceFields.contains(key))
          ? _voiceFieldKey(key)
          : null,
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
        suffixIcon: (_voiceFields.contains(key) || _numericVoiceFields.contains(key) || _dateVoiceFields.contains(key))
            ? Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _markMicPointerDown(),
                child: IconButton(
                  tooltip: _speechListening && _activeVoiceField == key
                      ? 'إيقاف التسجيل'
                      : (_dateVoiceFields.contains(key)
                          ? 'إدخال التاريخ بالصوت: اليوم ثم الشهر ثم السنة'
                          : (_numericVoiceFields.contains(key)
                              ? 'الإدخال الصوتي للأرقام عبر Google'
                              : 'الإدخال الصوتي بالعربية عبر Google')),
                  onPressed: () => _toggleVoiceInput(key),
                  icon: Icon(
                    _speechListening && _activeVoiceField == key
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: _speechListening && _activeVoiceField == key
                        ? Colors.red
                        : null,
                  ),
                ),
              )
            : null,
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
      key: _voiceFieldKey(key),
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
        suffixIcon: _dropdownVoiceFields.contains(key)
            ? IconButton(
                tooltip: 'اختيار ${labels[key] ?? key} بالصوت',
                icon: Icon(_speechListening && _activeVoiceField == key ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _speechListening && _activeVoiceField == key ? Colors.red : null),
                onPressed: () => _toggleVoiceInput(key),
              )
            : null,
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
        content: Text(
          message,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: isError ? 5 : 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (saving || _activeVoiceSessionId != null) return;

    // كل مراحل الحفظ أصبحت داخل try/catch حتى لا تبقى رسالة
    // "بدأت عملية حفظ الطالب..." ظاهرة إذا حدث استثناء قبل إرسال الطلب.
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
      if (validationError != null) {
        throw Exception(validationError);
      }

      _setSaveStatus('جاري التحقق من البيانات...', isError: false);
      _showSaveMessage('جاري التحقق من البيانات وإرسال الطالب إلى EMIS...', isError: false);

      final idType = int.parse(c['idType']!.text);

      // مهم جداً: عند اختيار نوع الهوية 12، الحقل الصحيح هو nationalId
      // وليس idNumber.
      final identificationNumber = _isNationalId
          ? _normalizeDigits(_n('nationalId') ?? '')
          : (_isCivilId
              ? (_n('idNumber') ?? '')
              : (_isBirthCertificate
                  ? (_n('birthCertificateNumber') ?? '')
                  : (_isOtherId ? (_n('otherIdNumber') ?? '') : '')));

      if (_isNationalId) {
        _setSaveStatus(
          'جاري التحقق من رقم البطاقة الوطنية الموحدة...',
          isError: false,
        );

        final check = await _get(
          '/student/checknationalidnumber?value=${Uri.encodeQueryComponent(identificationNumber)}',
        );

        if (check is Map && check['isUnique'] == false) {
          throw Exception('رقم البطاقة الوطنية مستخدم مسبقاً في EMIS');
        }
      }

      _setSaveStatus(
        'تم التحقق من رقم الهوية. جاري تجهيز بيانات الطالب...',
        isError: false,
      );

      final selectedSpecialNeeds = _n('specialNeeds');

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

      _setSaveStatus('جاري إرسال بيانات الطالب إلى EMIS...', isError: false);

      final encodedPayload = jsonEncode(payload);
      debugPrint('EMIS addstudent payload: $encodedPayload');

      final response = await http
          .post(
            Uri.parse('https://emis.moedu.gov.iq/api/student/addstudent'),
            headers: h,
            body: encodedPayload,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'انتهت مهلة الاتصال بخادم EMIS أثناء حفظ الطالب.',
            ),
          );

      final responseText = utf8.decode(response.bodyBytes);
      debugPrint(
        'EMIS addstudent response ${response.statusCode}: $responseText',
      );

      dynamic responseJson;
      try {
        responseJson = jsonDecode(responseText);
      } catch (_) {
        responseJson = null;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final serverMessage = responseJson is Map
            ? '${responseJson['message'] ?? responseJson['error'] ?? responseJson['errors'] ?? responseText}'
            : responseText;
        throw Exception(
          'رفض EMIS الطلب (HTTP ${response.statusCode}): $serverMessage',
        );
      }

      final successMessage = responseJson is Map &&
              '${responseJson['message'] ?? ''}'.trim().isNotEmpty
          ? '${responseJson['message']}'
          : 'تمت إضافة الطالب بنجاح';

      if (!mounted) return;

      setState(() {
        error = null;
        _saveStatus = successMessage;
        _saveStatusIsError = false;
      });
      _showSaveMessage(successMessage, isError: false);

      // إبقاء رسالة النجاح ظاهرة قليلاً قبل العودة إلى قائمة الطلاب.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final friendly = _friendlyError(e);
      debugPrint('EMIS add student error: $friendly');

      if (mounted) {
        setState(() {
          error = friendly;
          _saveStatus = friendly;
          _saveStatusIsError = true;
        });
        _showSaveMessage(friendly, isError: true);
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

    final idNumber = _isNationalId
        ? _normalizeDigits(c['nationalId']?.text.trim() ?? '')
        : (_isCivilId
            ? (_n('idNumber') ?? '')
            : (_isBirthCertificate
                ? (_n('birthCertificateNumber') ?? '')
                : (_isOtherId ? (_n('otherIdNumber') ?? '') : '')));
    if (_isNationalId) {
      if (!RegExp(r'^\d{12}$').hasMatch(idNumber)) {
        return 'رقم البطاقة الوطنية الموحدة يجب أن يكون 12 رقماً';
      }
    } else if (idNumber.isEmpty) {
      return 'يرجى إدخال رقم الوثيقة';
    }

    final phone = _n('homePhoneNumber')!;
    if (!RegExp(r'^[0-9٠-٩+ -]{7,20}$').hasMatch(phone)) {
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _stopVoiceFromPointer(),
      child: Scaffold(
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
                  cacheExtent: 5000,
                  padding: const EdgeInsets.all(17),
                  children: [
                    _intro(),
                    _sequentialVoiceControl(),
                    if (!AppCore.voiceInputEnabled) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.mic_off_outlined, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الميكروفون مغلق من الإعدادات. إذا أردت استخدام الإدخال الصوتي، افتح الإعدادات وفَعّل الميكروفون والتعرف الصوتي.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_speechError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic_off_outlined, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _speechError!,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                    if (_saveStatus != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _saveStatusIsError
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _saveStatusIsError
                                ? Colors.red.shade200
                                : Colors.green.shade200,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _saveStatusIsError
                                  ? Icons.error_outline_rounded
                                  : (saving
                                      ? Icons.sync_rounded
                                      : Icons.check_circle_outline_rounded),
                              color: _saveStatusIsError
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _saveStatus!,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _saveStatusIsError
                                      ? Colors.red.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 55,
                      child: FilledButton.icon(
                        onPressed: (saving || _activeVoiceSessionId != null) ? null : _save,
                        icon: saving
                            ? const SizedBox(
                                width: 21,
                                height: 21,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          _activeVoiceSessionId != null ? 'أوقف الميكروفون أولاً' : 'حفظ الطالب',
                          style: const TextStyle(fontWeight: FontWeight.bold,fontSize: 17),
                        ),
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

  Widget _socialWelfareSelect() {
    return DropdownButtonFormField<bool>(
      key: _voiceFieldKey('isCoveredBySocialWelfare'),
      value: _socialWelfare,
      isExpanded: true,
      decoration: _decoration('مشمول بمنحة الرعاية الاجتماعية؟').copyWith(
        suffixIcon: IconButton(tooltip: 'اختيار الحالة بالصوت', icon: Icon(_speechListening && _activeVoiceField == 'isCoveredBySocialWelfare' ? Icons.mic_rounded : Icons.mic_none_rounded, color: _speechListening && _activeVoiceField == 'isCoveredBySocialWelfare' ? Colors.red : null), onPressed: () => _toggleVoiceInput('isCoveredBySocialWelfare')),
      ),
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
    final key = label == 'الدولة' ? 'addressCountry' : label == 'المحافظة' ? 'addressGovernorate' : 'addressDistrict';
    final safe = items.any((x) => _value(x) == value) ? value : null;
    return DropdownButtonFormField<String>(
      key: _voiceFieldKey(key),
      value: safe,
      isExpanded: true,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      decoration: _decoration(label).copyWith(
        suffixIcon: IconButton(
          tooltip: 'اختيار $label بالصوت',
          icon: Icon(_speechListening && _activeVoiceField == key ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: _speechListening && _activeVoiceField == key ? Colors.red : null),
          onPressed: () => _toggleVoiceInput(key),
        ),
      ),
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
        key: _voiceFieldKey('stageId'),
        value: stageId,
        isExpanded: true,
        decoration: _decoration('الصف الدراسي').copyWith(labelStyle: const TextStyle(fontWeight: FontWeight.bold), suffixIcon: IconButton(tooltip: 'اختيار الصف بالصوت', icon: Icon(_speechListening && _activeVoiceField == 'stageId' ? Icons.mic_rounded : Icons.mic_none_rounded, color: _speechListening && _activeVoiceField == 'stageId' ? Colors.red : null), onPressed: () => _toggleVoiceInput('stageId'))),
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
        key: _voiceFieldKey('classRoomId'),
        value: roomId,
        isExpanded: true,
        decoration: _decoration('الشعبة').copyWith(labelStyle: const TextStyle(fontWeight: FontWeight.bold), suffixIcon: IconButton(tooltip: 'اختيار الشعبة بالصوت', icon: Icon(_speechListening && _activeVoiceField == 'classRoomId' ? Icons.mic_rounded : Icons.mic_none_rounded, color: _speechListening && _activeVoiceField == 'classRoomId' ? Colors.red : null), onPressed: () => _toggleVoiceInput('classRoomId'))),
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
