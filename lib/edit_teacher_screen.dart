import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
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

  // ============================================================
  // EMIS LIVE REFERENCE DATA
  // ============================================================

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

  // ✅ خريطة الأسماء العربية الموحّدة — نفس نمط صفحة الطالب
  final Map<String, String> _officialArabicNames = {
    // الاسم
    'name': 'الإسم',
    'fatherName': 'إسم الأب',
    'grandFatherName': 'اسم والد الأب',
    'fathersGrandFatherName': 'اسم جد الأب',
    'surName': 'اللقب',
    'motherName': 'إسم الأم',
    'mothersFatherName': 'اسم والد الأم',
    'mothersGrandFatherName': 'اسم جد الأم',
    // شخصية
    'dateOfBirth': 'تاريخ التولّد',
    'gender': 'الجنس',
    'nationality': 'الجنسية',
    'countryOfBirth': 'محل الولادة',
    'homeTown': 'مسقط الرأس',
    'motherTongue': 'اللغة الأم',
    'maritalStatus': 'الحالة الاجتماعية',
    'bloodGroup': 'فئة الدم',
    'religion': 'الديانة',
    'notes': 'ملاحظات',
    // وثيقة التعريف
    'idType': 'نوع الهوية',
    'issuingCountry': 'بلد الإصدار',
    'idNumber': 'رقم البطاقة الوطنية الموحدة',
    'issuingDate': 'تاريخ الإصدار',
    'employeeIdNumber': 'الرقم الوظيفي',
    'familyNumber': 'الرقم العائلي',
    'nameOfDocument': 'نوع الوثيقة',
    'issuer': 'جهة الإصدار',
    'recordNumber': 'رقم السجل',
    'pageNumber': 'رقم الصحيفة',
    'jinsiyaIdNumber': 'رقم شهادة الجنسية',
    'otherIdNumber': 'رقم الهوية الأخرى',
    'birthCertificateNumber': 'رقم شهادة الولادة',
    // وظيفية
    'employmentType': 'نوع التوظيف',
    'employeeCategory': 'نوع الموظف',
    'classification': 'التصنيف',
    'jobDesignation': 'المسمى الوظيفي',
    'employmentGrade': 'الدرجة الوظيفية',
    'currentPosition': 'المنصب الحالي',
    'positionType': 'نوع الوظيفة',
    'dateOfStartWorking': 'تاريخ أول تعيين للموظف',
    // حالة وظيفية
    'status': 'الحالة الوظيفية',
    'statusDate': 'تاريخ سريان الحالة الوظيفية',
    'statusReason': 'سبب تغيير الحالة الوظيفية',
    // تحصيل
    'educationLevel': 'التحصيل الدراسي',
    'universityName': 'إسم الكلية / المعهد',
    'graduationYear': 'سنة التخرج',
    'specialization': 'الإختصاص',
    // احتياجات خاصة واتصال طارئ
    'specialNeedsInformation': 'معلومات ذوي الاحتياجات الخاصة إن وجدت',
    'emergencyContactName': 'اسم جهة الاتصال في الحالات الطارئة',
    'emergencyContactRelationship': 'صلة جهة الاتصال',
    'emergencyContactPhoneNumber': 'رقم هاتف جهة الاتصال',
    // عنوان
    'countryStructureId': 'الموقع الجغرافي',
    'town': 'المدينة/القرية',
    'area': 'الحي',
    'quarter': 'المحلة',
    'street': 'زقاق',
    'address1': 'عنوان 1',
    'address2': 'عنوان 2',
    'closestLocation': 'أقرب نقطة دالة',
    'email': 'البريد الإلكتروني',
    'mobilePhoneNumber': 'رقم هاتف المعلم',
    'homePhoneNumber': 'رقم الهاتف',
    // صور
    'imageUrl': 'الصورة',
    // مرافق
    'identification': 'وثيقة التعريف',
    'address': 'العنوان',
    'employmentRecord': 'سجل التوظيف',
  };

  @override
  void initState() {
    super.initState();
    // ✅ مثل صفحة الطالب: polling كل 700ms لدفع القيم إلى WebView
    _liveTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _pushLive());
    _fetchTeacherData();
  }

  Map<String, List<String>> _liveAliases() => {
        for (final entry in _officialArabicNames.entries)
          entry.key: <String>[entry.key, entry.value],
      };

  /// ✅ نسخة من قيم المعلم — تُرسَل إلى EMIS live
  Map<String, String> _liveValues() {
    final result = <String, String>{};
    final data = _teacherData;
    if (data == null) return result;
    final identification = data['identification'] is Map
        ? Map<String, dynamic>.from(data['identification'])
        : <String, dynamic>{};
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'])
        : <String, dynamic>{};
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

  /// ✅ يحفظ التغييرات القادمة من EMIS في `_teacherData`
  void _applyLiveSnapshot(Map<String, String> values) {
    final data = _teacherData;
    if (data == null) return;
    final identification = data['identification'] is Map
        ? Map<String, dynamic>.from(data['identification'])
        : <String, dynamic>{};
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'])
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
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return decoded;
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('استجابة بيانات المعلم غير صالحة');
  }

  Future<void> _fetchTeacherData() async {
    try {
      final response = await http.get(
        Uri.parse('https://emis.moedu.gov.iq/api/employee/getemployee/${widget.teacherId}'),
        headers: {'Authorization': widget.token, 'Accept': 'application/json'},
      );
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final teacher = _unwrap(jsonDecode(utf8.decode(response.bodyBytes)));

      // حمّل الخيارات المعروفة
      for (final key in _optionEndpoints.keys) {
        await _loadOptions(key);
      }
      await _loadEmployeesOptions();

      _teacherData = teacher;
      await _loadCountryStructure();

      if (!mounted) return;
      setState(() {
        _teacherData = teacher;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في جلب بيانات المعلم: $e');
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
    } catch (_) {}
  }

  Future<void> _loadCountryStructure() async {
    try {
      final list = await _getOptions('/CountryStructure/getcountrystructure');
      if (list.isEmpty) return;
      _addressCountries = list;

      final address = _teacherData?['address'] is Map
          ? Map<String, dynamic>.from(_teacherData!['address'])
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
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
        'dateOfBirth', 'issuingDate', 'dateOfStartWorking', 'graduationYear',
        'statusDate',
      }.contains(key);

  dynamic _optionValue(Map<String, dynamic> option) => option['value'] ?? option['id'];
  String _optionText(Map<String, dynamic> option) =>
      (option['displayName'] ?? option['name'] ?? option['label'] ?? option['text'] ?? _optionValue(option)?.toString() ?? '').toString();

  bool _sameValue(dynamic a, dynamic b) => a?.toString() == b?.toString();

  // ============================================================
  // WIDGETS
  // ============================================================

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
      if (_sameValue(_optionValue(item), value)) {
        selected = item;
        break;
      }
    }
    final safeValue = selected == null ? null : _optionValue(selected);

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<dynamic>(
        value: safeValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _label(key),
          labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: isDark ? Colors.black12 : Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dropdownColor: isDark ? const Color(0xFF252525) : Colors.white,
        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
        items: items.map((item) {
          return DropdownMenuItem<dynamic>(
            value: _optionValue(item),
            child: Text(_optionText(item),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          );
        }).toList(),
        validator: null,
        onTap: () => _focusLive(key),
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
      initialDate: initial,
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
    if (_optionEndpoints.containsKey(key) ||
        key == 'employmentType' ||
        key == 'employeeCategory' ||
        key == 'classification' ||
        key == 'status' ||
        key == 'positionType') {
      return _dropdownField(key: key, owner: owner, isDark: isDark, textColor: textColor);
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
                selection:
                    TextSelection.collapsed(offset: formatted.length),
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

  // ============================================================
  // SECTIONS
  // ============================================================

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
            Text(title,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade400)),
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
        final next = i + 1 < children.length
            ? children[i + 1]
            : const SizedBox();
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

  Widget _addressDropdown(String label, String? value,
      List<Map<String, dynamic>> items, ValueChanged<String?> onChanged) {
    final safe =
        items.any((x) => _optionValue(x)?.toString() == value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        value: safe,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        items: items
            .map((item) => DropdownMenuItem<String>(
                  value: _optionValue(item)?.toString(),
                  child: Text(_optionText(item),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  bool _identityFieldVisible(String key, dynamic idType) {
    final t = int.tryParse(idType?.toString() ?? '');
    if (t == 3) {
      return {
        'idNumber', 'jinsiyaIdNumber', 'issuer', 'recordNumber',
        'pageNumber', 'issuingCountry', 'issuingDate', 'nameOfDocument'
      }.contains(key);
    }
    if (t == 12) return {'idNumber'}.contains(key);
    if (t == 22) {
      return {
        'birthCertificateNumber', 'issuer', 'issuingDate',
        'issuingCountry', 'nameOfDocument'
      }.contains(key);
    }
    if (t == 16) {
      return {
        'otherIdNumber', 'nameOfDocument', 'issuer', 'issuingDate',
        'issuingCountry'
      }.contains(key);
    }
    return true;
  }

  // ============================================================
  // BUILD FORM
  // ============================================================

  List<Widget> _buildTeacherFormSections(bool isDark, Color textColor) {
    final teacher = _teacherData!;
    final identification = teacher['identification'] is Map<String, dynamic>
        ? teacher['identification'] as Map<String, dynamic>
        : teacher['identification'] is Map
            ? Map<String, dynamic>.from(teacher['identification'] as Map)
            : <String, dynamic>{};
    final address = teacher['address'] is Map<String, dynamic>
        ? teacher['address'] as Map<String, dynamic>
        : teacher['address'] is Map
            ? Map<String, dynamic>.from(teacher['address'] as Map)
            : <String, dynamic>{};
    final employment = teacher['employmentRecord'] is Map<String, dynamic>
        ? teacher['employmentRecord'] as Map<String, dynamic>
        : teacher['employmentRecord'] is Map
            ? Map<String, dynamic>.from(teacher['employmentRecord'] as Map)
            : <String, dynamic>{};
    teacher['identification'] = identification;
    teacher['address'] = address;
    teacher['employmentRecord'] = employment;

    Widget field(String key, [Map<String, dynamic>? owner]) {
      final target = owner ?? teacher;
      if (!target.containsKey(key)) return const SizedBox.shrink();
      return _fieldFor(key, target[key], target, isDark, textColor);
    }

    final result = <Widget>[
      // ============ الاسم الكامل ============
      _teacherSection('الاسم الكامل', [
        field('name'),
        field('fatherName'),
        field('grandFatherName'),
        field('fathersGrandFatherName'),
        field('surName'),
        field('motherName'),
        field('mothersFatherName'),
        field('mothersGrandFatherName'),
      ], isDark),

      // ============ البيانات الشخصية ============
      _teacherSection('البيانات الشخصية', [
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
      ], isDark),

      // ============ وثيقة التعريف ============
      _teacherSection('وثيقة التعريف', [
        if (identification.containsKey('idType'))
          _dropdownField(
              key: 'idType',
              owner: identification,
              isDark: isDark,
              textColor: textColor),
        ...identification.entries
            .where((entry) =>
                entry.key != 'idType' &&
                _identityFieldVisible(entry.key, identification['idType']))
            .map((entry) =>
                _fieldFor(entry.key, entry.value, identification, isDark, textColor)),
        field('employeeIdNumber'),
        field('familyNumber'),
      ], isDark),

      // ============ البيانات الوظيفية ============
      _teacherSection('البيانات الوظيفية', [
        field('employmentType'),
        field('employeeCategory'),
        field('classification'),
        field('jobDesignation'),
        field('employmentGrade'),
        field('currentPosition'),
        field('positionType'),
        field('dateOfStartWorking'),
      ], isDark),

      // ============ الحالة الوظيفية ============
      _teacherSection('الحالة الوظيفية', [
        field('status'),
        field('statusDate'),
        field('statusReason'),
      ], isDark),

      // ============ التحصيل الدراسي ============
      _teacherSection('التحصيل الدراسي', [
        field('educationLevel'),
        field('universityName'),
        field('graduationYear'),
        field('specialization'),
      ], isDark),

      // ============ احتياجات خاصة واتصال طارئ ============
      _teacherSection('ذوو الاحتياجات الخاصة والاتصال الطارئ', [
        field('specialNeedsInformation'),
        field('emergencyContactName'),
        field('emergencyContactRelationship'),
        field('emergencyContactPhoneNumber'),
      ], isDark),

      // ============ العنوان ============
      _teacherSection('العنوان ومعلومات الاتصال', [
        _addressDropdown('الدولة', _addressCountryId, _addressCountries, (v) {
          final country =
              _addressCountries.where((x) => _optionValue(x)?.toString() == v).toList();
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
        }),
        _addressDropdown('المحافظة', _addressGovernorateId, _addressGovernorates, (v) {
          final gov =
              _addressGovernorates.where((x) => _optionValue(x)?.toString() == v).toList();
          if (gov.isEmpty) return;
          setState(() {
            _addressGovernorateId = v;
            _addressDistricts = _childrenOf(gov.first);
            _addressDistrictId = null;
            address['countryStructureId'] = null;
          });
          _focusLive('countryStructureId');
        }),
        _addressDropdown('القضاء', _addressDistrictId, _addressDistricts, (v) {
          setState(() {
            _addressDistrictId = v;
            address['countryStructureId'] = v == null ? null : int.tryParse(v);
          });
          _focusLive('countryStructureId');
        }),
        field('town', address),
        field('area', address),
        field('quarter', address),
        field('street', address),
        field('address1', address),
        field('address2', address),
        field('closestLocation', address),
        field('email', address),
        field('mobilePhoneNumber', address),
      ], isDark),
    ];

    return result;
  }

  // ============================================================
  // IMAGE
  // ============================================================

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
      await normalizedFile.writeAsBytes(img.encodeJpg(source, quality: 90), flush: true);

      final mask = await segmenter.processImage(
        InputImage.fromFilePath(normalizedFile.path),
      );
      if (mask == null || mask.width <= 0 || mask.height <= 0 || mask.confidences.isEmpty) {
        throw Exception('لم يتم الحصول على قناع صالح للشخص');
      }
      if (mask.width != source.width || mask.height != source.height) {
        throw Exception('أبعاد القناع غير متطابقة');
      }

      final result = img.Image(
          width: source.width, height: source.height, numChannels: 4);
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                                throw Exception('لم يتم الحصول على الصورة المعالجة');
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
                          icon: const Icon(Icons.auto_fix_high, color: Colors.black87),
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
                  onPressed: processing ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: processing
                      ? null
                      : () {
                          setState(() => _pickedImage = currentImage);
                          Navigator.pop(dialogContext);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
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

  // ============================================================
  // SAVE
  // ============================================================

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
        return null;
      }

      // بناء Payload مطابق لـ EMIS updateemployee
      final old = _teacherData!;
      final identification = old['identification'] is Map
          ? Map<String, dynamic>.from(old['identification'])
          : <String, dynamic>{};
      final oldAddress = old['address'] is Map
          ? Map<String, dynamic>.from(old['address'])
          : <String, dynamic>{};
      final oldEmployment = old['employmentRecord'] is Map
          ? Map<String, dynamic>.from(old['employmentRecord'])
          : <String, dynamic>{};

      String text(String key) {
        final v = old[key];
        return v == null ? '' : '$v'.trim();
      }

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
        'DateOfStartWorking': _nullable(dateOnly(text('dateOfStartWorking'))),
        'EducationLevel': _nullable(text('educationLevel')),
        'GraduationYear': _nullable(dateOnly(text('graduationYear'))),
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
        'ImageUrl': old['imageUrl']?.toString() ?? '',
        'DateOfBirth': _nullable(dateOnly(text('dateOfBirth'))),
        'Gender': _intOrNull(text('gender')),
        'Nationality': text('nationality'),
        'CountryOfBirth': text('countryOfBirth'),
        'HomeTown': text('homeTown'),
        'IdentificationId': 0,
        'Identification': {
          'IdNumber': identification['idNumber']?.toString() ?? '',
          'IssuingCountry': identification['issuingCountry']?.toString() ?? '',
          'IdType': _intOrNull(identification['idType']?.toString() ?? ''),
          'issuingDate': dateOnly(identification['issuingDate']),
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
        'EmergencyContactRelationship':
            _nullable(text('emergencyContactRelationship')),
        'EmergencyContactPhoneNumber':
            _nullable(text('emergencyContactPhoneNumber')),
        'Address': {
          'AddressType': 1,
          'Town': oldAddress['town']?.toString() ?? '',
          'Area': oldAddress['area']?.toString() ?? '',
          'Quarter': oldAddress['quarter']?.toString() ?? '',
          'Street': oldAddress['street']?.toString() ?? '',
          'ClosestLocation': oldAddress['closestLocation']?.toString() ?? '',
          'countryStructureId': oldAddress['countryStructureId'],
          'Latitude': '${oldAddress['latitude'] ?? 0}',
          'Longitude': '${oldAddress['longitude'] ?? 0}',
          'ApartmentNumber': oldAddress['apartmentNumber'] ?? '',
          'BuildingNumber': oldAddress['buildingNumber'] ?? '',
          'Address1': oldAddress['address1']?.toString() ?? '',
          'Address2': oldAddress['address2']?.toString() ?? '',
          'SchoolPhoneNumber': oldAddress['schoolPhoneNumber'] ?? '',
          'MobilePhoneNumber': oldAddress['mobilePhoneNumber']?.toString() ?? '',
          'Email': oldAddress['email']?.toString() ?? '',
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
        headers: {
          'Authorization': widget.token,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم الحفظ بنجاح!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else {
        debugPrint('Update teacher status: ${response.statusCode}');
        debugPrint('Update teacher response: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 12),
            content: Text('فشل الحفظ (HTTP ${response.statusCode})\n${response.body}',
                maxLines: 6, overflow: TextOverflow.ellipsis),
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
    final record = Map<String, dynamic>.from(old);
    final statuses = old['employmentStatuses'] is List
        ? (old['employmentStatuses'] as List)
            .map((x) =>
                x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];
    final positions = old['employmentPositions'] is List
        ? (old['employmentPositions'] as List)
            .map((x) =>
                x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{})
            .toList()
        : <Map<String, dynamic>>[];

    if (statuses.isNotEmpty) {
      final status = statuses.first;
      status['StatusType'] = _teacherData?['status']?.toString() ?? '';
      status['Reason'] = _nullable(_teacherData?['statusReason']?.toString());
      status['StatusDate'] = _nullable(_teacherData?['statusDate']?.toString());
      status['CurrentBelongToEntityId'] = int.tryParse(widget.schoolId);
    }
    if (positions.isNotEmpty) {
      final pos = positions.first;
      pos['Position'] = _teacherData?['currentPosition']?.toString() ?? '';
      pos['InitiateDate'] =
          _teacherData?['dateOfStartWorking']?.toString() ?? '';
    }

    record['EmploymentStatuses'] = statuses;
    record['EmploymentPositions'] = positions;
    record['CurrentBelongToEntityId'] = int.tryParse(widget.schoolId);
    record['CurrentEmploymentPosition'] =
        _teacherData?['positionType']?.toString() ?? '';
    return record;
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

  // ============================================================
  // BUILD
  // ============================================================

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
            gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF4A90E2)]),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _teacherData == null
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
                                              color: Colors.blueAccent, width: 3),
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
                                                              color:
                                                                  Colors.grey[400]),
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

// ================================================================
// NORMAL TEXT FIELD — نفس نمط صفحة الطالب
// ================================================================

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
                    widget.micActive ? Icons.mic_rounded : Icons.mic_none_rounded,
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
