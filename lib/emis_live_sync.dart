import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EmisLiveSync extends StatefulWidget {
  final String url;
  final String mode;
  final String entity;
  final String token;
  final String? recordId;
  final Map<String, List<String>> aliases;
  final ValueChanged<Map<String, String>> onSnapshot;
  final ValueChanged<Map<String, List<Map<String, dynamic>>>>? onOptions;
  final ValueChanged<Map<String, Map<String, dynamic>>>? onSchema;
  final ValueChanged<String>? onStatus;

  const EmisLiveSync({
    super.key,
    required this.url,
    required this.mode,
    required this.entity,
    required this.token,
    required this.aliases,
    required this.onSnapshot,
    this.onOptions,
    this.onSchema,
    this.recordId,
    this.onStatus,
  });

  @override
  State<EmisLiveSync> createState() => EmisLiveSyncState();
}

class EmisLiveSyncState extends State<EmisLiveSync> {
  late final WebViewController controller;
  bool _ready = false;
  bool _injectingToken = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'EmisSyncChannel',
        onMessageReceived: (message) {
          if (!mounted) return;
          try {
            final decoded = jsonDecode(message.message);
            if (decoded is! Map) return;
            final type = '${decoded['type'] ?? ''}';
            if (type == 'status') {
              widget.onStatus?.call('${decoded['message'] ?? ''}');
              return;
            }
            if (type == 'focus') {
              widget.onStatus?.call('مزامنة الحقل: ${decoded['field'] ?? ''}');
              return;
            }
            if (type == 'schema') {
              final raw = decoded['fields'];
              if (raw is! Map) return;
              final schema = <String, Map<String, dynamic>>{};
              for (final entry in raw.entries) {
                final key = '${entry.key}'.trim();
                if (key.isEmpty || entry.value is! Map) continue;
                schema[key] = Map<String, dynamic>.from(entry.value as Map);
              }
              if (schema.isNotEmpty) widget.onSchema?.call(schema);
              return;
            }
            if (type == 'options') {
              final raw = decoded['options'];
              if (raw is! Map) return;
              final result = <String, List<Map<String, dynamic>>>{};
              for (final entry in raw.entries) {
                final key = '${entry.key}'.trim();
                final list = entry.value;
                if (key.isEmpty || list is! List) continue;
                final values = <Map<String, dynamic>>[];
                final seen = <String>{};
                for (final item in list) {
                  final option = item is Map
                      ? Map<String, dynamic>.from(item)
                      : <String, dynamic>{'value': '$item', 'label': '$item'};
                  final value = '${option['value'] ?? option['id'] ?? option['label'] ?? ''}'.trim();
                  final label = '${option['label'] ?? option['displayName'] ?? option['text'] ?? value}'.trim();
                  if (value.isEmpty || label.isEmpty || !seen.add('$value|$label')) continue;
                  values.add({'value': value, 'displayName': label});
                }
                if (values.isNotEmpty) result[key] = values;
              }
              if (result.isNotEmpty) widget.onOptions?.call(result);
              return;
            }
            if (type != 'snapshot') return;
            final raw = decoded['fields'];
            if (raw is! Map) return;
            final snapshot = <String, String>{};
            for (final entry in raw.entries) {
              final key = '${entry.key}'.trim();
              if (key.isEmpty) continue;
              snapshot[key] = '${entry.value ?? ''}';
            }
            if (snapshot.isNotEmpty) widget.onSnapshot(snapshot);
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _ready = false;
            if (mounted) {
              widget.onStatus?.call('جاري فتح صفحة EMIS للمزامنة...');
            }
          },
          onPageFinished: (url) async {
            if (!mounted || _injectingToken) return;
            final reloaded = await _injectAuthentication();
            if (reloaded || !mounted) return;
            await _installBridge();
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;
            await refreshSchema();
            await Future<void>.delayed(const Duration(milliseconds: 700));
            if (mounted) {
              widget.onStatus?.call('تم فتح نموذج EMIS وجلب بنيته وخياراته');
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              widget.onStatus?.call('تعذر تحميل صفحة EMIS: ${error.errorCode}');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<bool> _injectAuthentication() async {
    final token = widget.token.trim();
    if (token.isEmpty) return false;

    final bearer = token.toLowerCase().startsWith('bearer ')
        ? token
        : 'Bearer $token';
    final raw = token.replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );

    final js = '''
(function(){
  try {
    if (sessionStorage.getItem('__EMIS_APP_AUTH_READY__') === '1') return false;
    var rawToken = ${jsonEncode(raw)};
    var bearerToken = ${jsonEncode(bearer)};
    var keys = [
      'token','access_token','accessToken','authToken','jwt',
      'Authorization','authorization','bearerToken'
    ];
    for (var i=0;i<keys.length;i++) {
      try {
        localStorage.setItem(
          keys[i],
          keys[i].toLowerCase().indexOf('authorization') >= 0
            ? bearerToken : rawToken
        );
      } catch(e) {}
      try {
        sessionStorage.setItem(
          keys[i],
          keys[i].toLowerCase().indexOf('authorization') >= 0
            ? bearerToken : rawToken
        );
      } catch(e) {}
    }
    try { localStorage.setItem('BearerToken', bearerToken); } catch(e) {}
    try { sessionStorage.setItem('BearerToken', bearerToken); } catch(e) {}
    sessionStorage.setItem('__EMIS_APP_AUTH_READY__','1');
    location.reload();
    return true;
  } catch(e) { return false; }
})();''';

    _injectingToken = true;
    try {
      final result = await controller.runJavaScriptReturningResult(js);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _injectingToken = false;
      return '$result'.toLowerCase().contains('true');
    } catch (_) {
      _injectingToken = false;
      return false;
    }
  }

  Future<void> _installBridge() async {
    final aliases = jsonEncode(widget.aliases);
    final id = jsonEncode(widget.recordId ?? '');
    final mode = jsonEncode(widget.mode);
    final entity = jsonEncode(widget.entity);

    final js = '''
(function(){
  try {
    // تنظيف أي مؤقتات أو مراقبات سابقة لمنع تسريب الذاكرة وتكرار الإرسال
    if (window.__EMIS_APP_BRIDGE__ && typeof window.__EMIS_APP_BRIDGE__.cleanup === 'function') {
      try { window.__EMIS_APP_BRIDGE__.cleanup(); } catch (_) {}
    }

    const prevApplied = (window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.appliedSelectValues) || {};

    window.__EMIS_APP_BRIDGE__ = {
      aliases: $aliases,
      recordId: $id,
      mode: $mode,
      entity: $entity,
      opened: false,
      last: '',
      schemaLast: '',
      triedEmptySelects: {},
      optionsCollected: {},
      appliedSelectValues: prevApplied,
      isSettingFields: false,
      timers: [],
      observers: [],
      listeners: []
    };

    const b = window.__EMIS_APP_BRIDGE__;

    const addTimer = (id) => { b.timers.push(id); return id; };
    const addListener = (target, type, fn, opts) => {
      target.addEventListener(type, fn, opts);
      b.listeners.push({target, type, fn, opts});
    };

    b.cleanup = () => {
      b.timers.forEach(t => { try { clearInterval(t); clearTimeout(t); } catch(e) {} });
      b.timers.length = 0;
      b.observers.forEach(o => { try { o.disconnect(); } catch(e) {} });
      b.observers.length = 0;
      b.listeners.forEach(l => { try { l.target.removeEventListener(l.type, l.fn, l.opts); } catch(e) {} });
      b.listeners.length = 0;
    };

    const send = (type, payload) => {
      try {
        EmisSyncChannel.postMessage(JSON.stringify(
          Object.assign({type:type}, payload || {})
        ));
      } catch(e) {}
    };

    const norm = (s) => String(s || '')
      .replace(/[\\u064B-\\u065F\\u0670]/g,'')
      .replace(/[أإآٱ]/g,'ا')
      .replace(/ة/g,'ه')
      .replace(/ى/g,'ي')
      .replace(/[\\u06CC\\u0649]/g,'ي')
      .replace(/ک/g,'ك')
      .replace(/\\s+/g,' ')
      .trim()
      .toLowerCase();

    const textOf = (el) => {
      if (!el) return '';
      try {
        const parent = el.closest('.q-field');
        if (parent) {
          const q = parent.querySelector('.q-field__label,.q-field__native-label,[data-label]');
          if (q) {
            const clone = q.cloneNode(true);
            clone.querySelectorAll('i,svg,.q-icon,[class*=icon],button').forEach(n => n.remove());
            const label = String(clone.innerText || clone.textContent || '').replace(/\\s+/g,' ').trim();
            if (label && !/^(arrow_drop_down|expand_more|keyboard_arrow_down)\$/i.test(label)) return label;
          }
          const aria = parent.getAttribute('aria-label');
          if (aria && !/^(arrow_drop_down|expand_more|keyboard_arrow_down)\$/i.test(aria.trim())) return aria.trim();
        }
      } catch(e) {}
      try {
        const id = el.getAttribute('id');
        if (id) {
          const lab = document.querySelector('label[for="' + CSS.escape(id) + '"]');
          if (lab && (lab.innerText || lab.textContent)) return String(lab.innerText || lab.textContent).trim();
        }
      } catch(e) {}
      try {
        const lab = el.closest('label');
        if (lab && (lab.innerText || lab.textContent)) return String(lab.innerText || lab.textContent).trim();
      } catch(e) {}
      for (const a of ['aria-label','placeholder','data-label']) {
        try { const v = el.getAttribute(a); if (v && v.trim()) return v.trim(); } catch(e) {}
      }
      for (const a of ['name','id','data-cy','data-test']) {
        try { const v = el.getAttribute(a); if (v && v.trim()) return v.trim(); } catch(e) {}
      }
      return '';
    };

    const candidates = (el) => {
      const out = [];
      ['id','name','aria-label','placeholder','data-cy','data-test'].forEach(a => {
        try { const v = el.getAttribute(a); if (v) out.push(v); } catch(e) {}
      });
      const t = textOf(el); if (t) out.push(t);
      return [...new Set(out.map(norm).filter(Boolean))];
    };

    const aliases = b.aliases || {};

    const sortedAliasKeys = Object.keys(aliases).sort((a, bKey) => {
      const la = Math.max(...(aliases[a] || ['']).map(s => norm(s).length), 0);
      const lb = Math.max(...(aliases[bKey] || ['']).map(s => norm(s).length), 0);
      return lb - la;
    });

    const fieldKey = (el) => {
      const cs = candidates(el);
      for (const k of Object.keys(aliases)) {
        const aa = (aliases[k] || []).map(norm);
        if (cs.some(c => aa.includes(c))) return k;
      }
      for (const k of sortedAliasKeys) {
        const aa = (aliases[k] || []).map(norm);
        if (cs.some(c => aa.some(a => a.length >= 4 && (c === a || c.includes(a) || a.includes(c))))) return k;
      }
      const label = String(textOf(el) || '').trim();
      const q = el.closest ? el.closest('.q-field') : null;
      const generatedId = !!(q && (el.getAttribute('id') || '').match(/^(q-|input-|select-)/i));
      if (label && (!el.getAttribute('name') || generatedId)) return label;
      const raw = (el.getAttribute('name') || el.getAttribute('id') || el.getAttribute('data-cy') || el.getAttribute('data-test') || '').trim();
      if (raw) {
        const cleaned = raw.replace(/\\[(\\d+)\\]/g,'_\$1').replace(/[^a-zA-Z0-9_]/g,'_').replace(/_+/g,'_').replace(/^_+|_+\$/g,'');
        if (cleaned) return cleaned.charAt(0).toLowerCase() + cleaned.slice(1);
      }
      return label;
    };

    const readValue = (el) => {
      try {
        if (el.tagName === 'SELECT') {
          const o = el.options && el.selectedIndex >= 0 ? el.options[el.selectedIndex] : null;
          return o ? (el.value || o.textContent || '') : (el.value || '');
        }
        if ('value' in el) return el.value;
        return el.textContent || '';
      } catch(e) { return ''; }
    };

    const detectKind = (el) => {
      const tag = String(el.tagName || '').toLowerCase();
      const type = String(el.type || '').toLowerCase();
      if (tag === 'select') return 'select';
      if (tag === 'textarea') return 'textarea';
      if (type === 'date') return 'date';
      if (type === 'checkbox' || type === 'radio') return 'checkbox';

      const q = el.closest ? el.closest('.q-field') : null;
      if (!q) return 'text';

      if (q.classList.contains('q-select')) return 'select';
      if (q.querySelector('.q-select')) return 'select';
      if (q.getAttribute('role') === 'combobox') return 'select';
      if (q.querySelector('[role="combobox"]')) return 'select';
      if (q.querySelector('input[aria-expanded]')) return 'select';
      if (el.getAttribute('role') === 'combobox') return 'select';

      const append = q.querySelector('.q-field__append');
      if (append) {
        const icon = append.querySelector('i, svg, .q-icon, [class*="arrow"], [class*="expand"], [class*="dropdown"]');
        if (icon) {
          const iconText = (icon.textContent || '').trim();
          const iconClass = String(icon.className || '');
          if (/arrow|expand|dropdown|drop/i.test(iconText) || /arrow|expand|dropdown|drop/i.test(iconClass)) return 'select';
        }
      }
      if (el.readOnly && q.querySelector('i, svg, .q-icon')) return 'select';
      return 'text';
    };

    const isReallyVisible = (el) => {
      if (!el) return false;
      if (el.offsetParent === null) {
        try {
          const st = window.getComputedStyle(el);
          if (st.display === 'none' || st.visibility === 'hidden') return false;
        } catch(e) { return false; }
      }
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    };

    let lastScanTime = 0;
    let lastDomSize = 0;

    const scan = () => {
      if (b.isSettingFields) return;
      const now = Date.now();
      const domSize = document.querySelectorAll('.q-field').length;

      if (now - lastScanTime < 120 && domSize === lastDomSize) return;
      lastScanTime = now;
      lastDomSize = domSize;

      const fields = {};
      const schema = {};
      const allInputs = [...document.querySelectorAll('input,textarea,select,[contenteditable="true"]')];
      let order = 0;
      allInputs.forEach(el => {
        const key = fieldKey(el);
        if (!key) return;
        const kind = detectKind(el);
        const q = el.closest ? el.closest('.q-field') : null;
        const isVisible = isReallyVisible(el) &&
          (!q || (q.style.display !== 'none' && q.style.visibility !== 'hidden'));
        const v = String(readValue(el) || '');
        if (!(key in fields) || v.trim() !== '') fields[key] = v;

        let label = textOf(el) ||
          (q && q.querySelector('.q-field__label') ? q.querySelector('.q-field__label').innerText : '') ||
          key;
        label = String(label).trim();
        if (label && /^(arrow_drop_down|expand_more|keyboard_arrow_down)\$/i.test(label)) label = key;

        let opts = [];
        if (el.tagName === 'SELECT') {
          opts = [...el.options]
            .map(o => ({value: String(o.value || o.textContent || '').trim(), label: String(o.textContent || '').trim()}))
            .filter(o => o.label);
        }

        schema[key] = {
          label: label,
          type: kind,
          required: !!el.required || String(el.getAttribute('aria-required') || '') === 'true',
          value: v,
          order: order++,
          visible: isVisible,
          options: opts,
        };
      });

      const schemaShape = {};
      Object.keys(schema).forEach(k => {
        const meta = Object.assign({}, schema[k]);
        delete meta.value;
        schemaShape[k] = meta;
      });
      const schemaSerial = JSON.stringify(schemaShape);
      if (schemaSerial !== b.schemaLast) {
        b.schemaLast = schemaSerial;
        if (Object.keys(schema).length) {
          send('schema', {fields: schema, url: location.href});
          const selectKeys = Object.keys(schema)
            .filter(k => schema[k] && schema[k].type === 'select')
            .filter(k => {
              const opts = schema[k].options || [];
              if (opts.length > 0) return false;
              const tries = b.triedEmptySelects[k] || 0;
              if (tries >= 2) return false;
              b.triedEmptySelects[k] = tries + 1;
              return true;
            });
          if (selectKeys.length) addTimer(setTimeout(() => collectOptions(selectKeys), 300));
        }
      }
      const serial = JSON.stringify(fields);
      if (serial !== b.last) { b.last = serial; send('snapshot', {fields: fields, url: location.href}); }
    };

    const nativeSet = (el, value) => {
      try {
        const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (setter) setter.call(el, String(value)); else el.value = String(value);
      } catch(e) {
        try { el.value = String(value); } catch(_) {}
      }
      try { el.dispatchEvent(new Event('input', {bubbles:true})); } catch(e) {}
      try { el.dispatchEvent(new Event('change', {bubbles:true})); } catch(e) {}
      try { el.dispatchEvent(new Event('blur', {bubbles:true})); } catch(e) {}
    };

    const sleep = (ms) => new Promise(resolve => addTimer(setTimeout(resolve, ms)));

    const findField = (key) => {
      const wanted = norm(key);
      const aa = (aliases[key] || []).map(norm);
      const all = [...document.querySelectorAll('.q-field, input,textarea,select,[contenteditable="true"]')];
      for (const el of all) {
        const dynamicKey = norm(fieldKey(el));
        const cs = candidates(el);
        if (dynamicKey === wanted || cs.some(c => aa.includes(c))) {
          return el.classList?.contains('q-field') ? el : (el.closest('.q-field') || el);
        }
      }
      for (const el of all) {
        const cs = candidates(el);
        if (cs.some(c => aa.some(a => a.length >= 4 && (c === a || (c.includes(a) && !c.match(new RegExp('^' + a + '.'))))))) {
          return el.classList?.contains('q-field') ? el : (el.closest('.q-field') || el);
        }
      }
      return null;
    };

    const readQSelectOptions = async (key) => {
      const field = findField(key);
      if (!field) return [];
      try {
        document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
        await sleep(120);

        field.scrollIntoView({block:'center', inline:'nearest'});
        await sleep(80);

        const targets = [
          field.querySelector('.q-field__control'),
          field.querySelector('.q-field__native'),
          field.querySelector('input'),
          field
        ].filter(Boolean);

        let menu = null;
        for (const target of targets) {
          try { target.click(); } catch(e) {}
          for (let attempt = 0; attempt < 8; attempt++) {
            await sleep(80);
            const menus = [...document.querySelectorAll('.q-menu')].filter(m => {
              const r = m.getBoundingClientRect();
              return r.width > 50 && r.height > 20 && m.offsetParent !== null;
            });
            if (menus.length) { menu = menus[menus.length - 1]; break; }
          }
          if (menu) break;
        }
        if (!menu) return [];

        const values = [];
        const seen = new Set();
        const collect = () => {
          menu.querySelectorAll('.q-item, [role="option"]').forEach(x => {
            const clone = x.cloneNode(true);
            clone.querySelectorAll('i,svg,.q-icon,[class*=icon],button').forEach(n => n.remove());
            const label = String(clone.innerText || clone.textContent || '').replace(/\\s+/g,' ').trim();
            if (!label || /^(اختر|select|search|arrow_drop_down|expand_more)\$/i.test(label)) return;
            const value = String(x.getAttribute('data-value') || x.getAttribute('data-id') || x.getAttribute('value') || label).trim();
            if (!seen.has(value)) { seen.add(value); values.push({value: value, label: label}); }
          });
        };
        collect();

        const scroll = menu.querySelector('.q-virtual-scroll__content, .scroll');
        if (scroll) {
          let unchanged = 0;
          for (let i = 0; i < 80 && unchanged < 4; i++) {
            const before = seen.size;
            scroll.scrollTop = Math.min(scroll.scrollTop + scroll.clientHeight * 0.8, scroll.scrollHeight);
            await sleep(90);
            collect();
            unchanged = seen.size === before ? unchanged + 1 : 0;
            if (scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 2 && unchanged >= 2) break;
          }
        }

        document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
        await sleep(150);
        return values;
      } catch (e) {
        try { document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true})); } catch(_) {}
        return [];
      }
    };

    const collectOptions = async (keys) => {
      const out = {};
      for (const key of keys) {
        const values = await readQSelectOptions(key);
        if (values.length) {
          out[key] = values;
          b.optionsCollected[key] = values.length;
        }
      }
      if (Object.keys(out).length) send('options', {options: out});
      return out;
    };
    b.collectOptions = (keys) => collectOptions(keys || []);
    b.scanNow = () => scan();

    b.setFields = (values) => {
      const vals = values || {};
      b.isSettingFields = true;
      try {
        for (const [key, value] of Object.entries(vals)) {
          const strVal = String(value ?? '').trim();
          if (!strVal) continue;
          const best = findField(key);
          if (!best) continue;
          try {
            const qfield = best.closest ? best.closest('.q-field') : null;
            const qnative = qfield ? qfield.querySelector('.q-field__native') : null;
            if (qfield && qnative && qfield.classList.contains('q-select')) {
              const wanted = norm(strVal);
              const current = norm(qnative.value || qnative.innerText || '');
              // منع إعادة فتح القائمة إذا تم تطبيق نفس القيمة سابقاً
              if (current === wanted || b.appliedSelectValues[key] === wanted) continue;
              b.appliedSelectValues[key] = wanted;

              qfield.scrollIntoView({block:'center', inline:'nearest'});
              (qfield.querySelector('.q-field__control') || qnative || qfield).click();
              addTimer(setTimeout(() => {
                const items = [...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"]')];
                const item = items.find(o => {
                  const text = norm(o.innerText || o.textContent || '');
                  const attrs = ['data-value','data-id','value','aria-label'].map(a => norm(o.getAttribute(a) || ''));
                  return text === wanted || text.includes(wanted) || attrs.includes(wanted);
                });
                if (item) item.click();
                else document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
              }, 120));
            } else if (best.tagName === 'SELECT') {
              const wanted = strVal;
              const option = [...best.options].find(o =>
                String(o.value) === wanted || norm(o.textContent) === norm(wanted)
              );
              if (option && (best.value !== option.value || norm(best.options[best.selectedIndex]?.textContent) !== norm(value))) {
                best.value = option.value;
                best.dispatchEvent(new Event('input', {bubbles:true}));
                best.dispatchEvent(new Event('change', {bubbles:true}));
              }
            } else if (best.isContentEditable) {
              if (norm(best.textContent) === norm(strVal)) continue;
              best.textContent = strVal;
              best.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data: strVal}));
            } else {
              const inputEl = (best.tagName === 'INPUT' || best.tagName === 'TEXTAREA')
                ? best
                : best.querySelector?.('input, textarea');
              if (!inputEl) continue;
              if (String(inputEl.value ?? '') === strVal) continue;
              nativeSet(inputEl, strVal);
            }
          } catch(e) {}
        }
      } finally {
        addTimer(setTimeout(() => {
          b.isSettingFields = false;
          scan();
        }, 350));
      }
    };

    b.focusField = (key) => {
      const best = findField(key);
      if (!best) return false;
      try {
        best.scrollIntoView({block:'center', inline:'nearest'});
        const inputEl = (best.tagName === 'INPUT' || best.tagName === 'TEXTAREA')
          ? best
          : (best.querySelector?.('input, textarea') || best);
        inputEl.focus?.();
        inputEl.click?.();
        send('focus', {field: key});
        return true;
      } catch(e) { return false; }
    };

    const openTarget = () => {
      if (b.opened) return true;
      const currentPath = norm(location.pathname);

      // دعم وضع الإضافة
      if (b.mode === 'add' && currentPath.includes('/management/add')) {
        if (document.querySelectorAll('.q-field, input, select').length > 0) {
          b.opened = true;
          send('status', {message: 'تم تحميل نموذج إضافة المعلم من EMIS'});
          return true;
        }
      }

      // دعم وضع التعديل
      const id = norm(b.recordId);
      if (id && currentPath.includes('/management/edit/') && currentPath.includes(id)) {
        if (document.querySelectorAll('.q-field, input, select').length > 0) {
          b.opened = true;
          send('status', {message: 'تم تحميل نموذج تعديل المعلم من EMIS'});
          return true;
        }
      }
      return false;
    };

    let scanTimer = null;
    const scheduleScan = (delay) => {
      if (scanTimer) clearTimeout(scanTimer);
      scanTimer = addTimer(setTimeout(() => { scanTimer = null; scan(); }, delay || 120));
    };

    addListener(document, 'input', () => scheduleScan(120), true);
    addListener(document, 'change', () => scheduleScan(120), true);
    addListener(document, 'blur', () => scheduleScan(100), true);
    addListener(document, 'focusin', (e) => {
      const key = fieldKey(e.target);
      if (key) send('focus', {field: key});
    }, true);

    const findFormContainers = () => {
      const candidates = document.querySelectorAll('.q-page, .q-card, form, .q-form, [class*="form-container"]');
      const containers = [];
      candidates.forEach(c => {
        if (c.offsetParent !== null && c.getBoundingClientRect().height > 100) {
          containers.push(c);
        }
      });
      return containers.length ? containers : [document.body];
    };

    const startObservers = () => {
      b.observers.forEach(o => { try { o.disconnect(); } catch(e) {} });
      b.observers.length = 0;
      const containers = findFormContainers();
      containers.forEach(container => {
        const obs = new MutationObserver(mutations => {
          if (b.isSettingFields) return;
          let relevant = false;
          for (const m of mutations) {
            if (m.type === 'childList') {
              for (const node of m.addedNodes) {
                if (node.nodeType === 1) {
                  if (node.matches?.('.q-field, input, select, textarea') ||
                      node.querySelector?.('.q-field, input, select, textarea')) {
                    relevant = true;
                    break;
                  }
                }
              }
            } else if (m.type === 'attributes') {
              const target = m.target;
              if (target.matches?.('.q-field, .q-field__native, input, select, textarea') ||
                  target.closest?.('.q-field')) {
                relevant = true;
              }
            }
            if (relevant) break;
          }
          if (relevant) scheduleScan(150);
        });
        obs.observe(container, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ['class', 'aria-expanded', 'aria-hidden', 'style', 'disabled', 'readonly', 'value']
        });
        b.observers.push(obs);
      });
    };

    const openAndScan = () => {
      const wasOpened = b.opened;
      const opened = openTarget();
      if (opened && !wasOpened) {
        startObservers();
      }
      scan();
    };

    let tries = 0;
    const bootstrapTimer = addTimer(setInterval(() => {
      tries++;
      openAndScan();
      if (b.opened || tries > 25) {
        clearInterval(bootstrapTimer);
        if (!b.opened) startObservers();
        addTimer(setInterval(() => {
          if (document.hidden || b.isSettingFields) return;
          scan();
        }, 2500));
      }
    }, 450));

    let lastHref = location.href;
    addTimer(setInterval(() => {
      if (location.href !== lastHref) {
        lastHref = location.href;
        b.opened = false;
        b.last = '';
        b.schemaLast = '';
        b.appliedSelectValues = {};
        scheduleScan(500);
      }
    }, 800));

    scan();
    send('status', {message: 'جسر المزامنة الذكي جاهز'});
  } catch(e) {
    try {
      EmisSyncChannel.postMessage(JSON.stringify({
        type: 'status', message: 'خطأ في جسر المزامنة: ' + e
      }));
    } catch(_) {}
  }
})();''';

    try {
      await controller.runJavaScript(js);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> refreshOptions(List<String> keys) async {
    if (!_ready || keys.isEmpty) return;
    final encoded = jsonEncode(keys);
    final js = '''
(function(){
  try {
    if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.collectOptions) {
      var keys = $encoded;
      for (var i = 0; i < keys.length; i++) {
        window.__EMIS_APP_BRIDGE__.triedEmptySelects[keys[i]] = 0;
      }
      window.__EMIS_APP_BRIDGE__.collectOptions(keys);
    }
  } catch(e) {}
})();''';
    try {
      await controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> refreshSchema() async {
    if (!_ready) return;
    try {
      await controller.runJavaScript(
        '''(function(){try{if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.scanNow) window.__EMIS_APP_BRIDGE__.scanNow();}catch(e){}})();''',
      );
    } catch (_) {}
  }

  Future<void> pushValues(Map<String, String> values) async {
    if (!_ready || values.isEmpty) return;
    final encoded = jsonEncode(values);
    final js = '''
(function(){
  try {
    if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.setFields){
      window.__EMIS_APP_BRIDGE__.setFields($encoded);
    }
  } catch(e) {}
})();''';
    try {
      await controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> focusField(String key) async {
    if (!_ready || key.trim().isEmpty) return;
    final js = '''
(function(){
  try {
    if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.focusField){
      window.__EMIS_APP_BRIDGE__.focusField(${jsonEncode(key)});
    }
  } catch(e) {}
})();''';
    try {
      await controller.runJavaScript(js);
    } catch (_) {}
  }

  @override
  void dispose() {
    // تنظيف موارد الجافاسكريبت وإيقاف الصفحة عند إغلاق الشاشة
    try {
      controller.runJavaScript(
        '''(function(){try{if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.cleanup) window.__EMIS_APP_BRIDGE__.cleanup();}catch(e){}})();''',
      );
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 390,
          height: 720,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
