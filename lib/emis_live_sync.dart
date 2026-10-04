import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// مزامنة ثنائية الاتجاه بين نموذج التطبيق وصفحة EMIS الحقيقية.
/// تعمل الصفحة في WebView مخفي، وتستخدم JavaScript لمراقبة الحقول
/// وإرسال تغييرات EMIS إلى التطبيق، كما تستقبل تغييرات التطبيق فوراً.
class EmisLiveSync extends StatefulWidget {
  final String url;
  final String mode;
  final String entity;
  final String token;
  final String? recordId;
  final Map<String, List<String>> aliases;
  final ValueChanged<Map<String, String>> onSnapshot;
  final ValueChanged<Map<String, List<String>>>? onOptions;
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
            if (type == 'options') {
              final raw = decoded['options'];
              if (raw is! Map) return;
              final result = <String, List<String>>{};
              for (final entry in raw.entries) {
                final key = '${entry.key}'.trim();
                final list = entry.value;
                if (key.isEmpty || list is! List) continue;
                final values = list.map((v) => '$v'.trim()).where((v) => v.isNotEmpty).toSet().toList();
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
            widget.onStatus?.call('جاري فتح صفحة EMIS للمزامنة...');
          },
          onPageFinished: (url) async {
            if (_injectingToken) return;
            final reloaded = await _injectAuthentication();
            if (reloaded) return;
            await _installBridge();
            widget.onStatus?.call('المزامنة اللحظية مع EMIS مفعّلة');
          },
          onWebResourceError: (error) {
            widget.onStatus?.call(
              'تعذر تحميل صفحة EMIS للمزامنة: ${error.errorCode}',
            );
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
    window.__EMIS_APP_BRIDGE__ = {
      aliases: $aliases,
      recordId: $id,
      mode: $mode,
      entity: $entity,
      opened: false,
      last: ''
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
      .replace(/\\s+/g,' ')
      .trim()
      .toLowerCase();

    const textOf = (el) => {
      if (!el) return '';
      const attrs = ['aria-label','placeholder','name','id','data-cy','data-test'];
      for (const a of attrs) {
        try { const v=el.getAttribute(a); if(v) return v; } catch(e) {}
      }
      try {
        const lab=el.closest('label');
        if(lab && lab.innerText) return lab.innerText;
      } catch(e) {}
      try {
        const parent=el.closest('.q-field');
        if(parent){
          const q=parent.querySelector('.q-field__label,.q-field__native-label,label');
          if(q && q.innerText) return q.innerText;
        }
      } catch(e) {}
      return '';
    };

    const candidates = (el) => {
      const out=[];
      ['id','name','aria-label','placeholder','data-cy','data-test']
        .forEach(a=>{
          try { const v=el.getAttribute(a); if(v) out.push(v); } catch(e) {}
        });
      const t=textOf(el); if(t) out.push(t);
      return [...new Set(out.map(norm).filter(Boolean))];
    };

    const aliases = window.__EMIS_APP_BRIDGE__.aliases || {};
    const fieldKey = (el) => {
      const cs=candidates(el);
      for(const k of Object.keys(aliases)){
        const aa=(aliases[k]||[]).map(norm);
        if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))) return k;
      }
      return '';
    };

    const readValue = (el) => {
      try {
        if (el.tagName === 'SELECT') {
          const o=el.options && el.selectedIndex>=0
            ? el.options[el.selectedIndex] : null;
          return o ? (el.value || o.textContent || '') : (el.value || '');
        }
        if ('value' in el) return el.value;
        return el.textContent || '';
      } catch(e) { return ''; }
    };

    const scan = () => {
      const fields={};
      document.querySelectorAll(
        'input,textarea,select,[contenteditable="true"]'
      ).forEach(el=>{
        const key=fieldKey(el);
        if(!key) return;
        const v=String(readValue(el)||'');
        if(!(key in fields) || v.trim()!=='') fields[key]=v;
      });
      const serial=JSON.stringify(fields);
      const b=window.__EMIS_APP_BRIDGE__;
      if(serial!==b.last){
        b.last=serial;
        send('snapshot',{fields:fields,url:location.href});
      }
    };

    const nativeSet = (el,value) => {
      try {
        const proto = el instanceof HTMLTextAreaElement
          ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto,'value')?.set;
        if(setter) setter.call(el,String(value)); else el.value=String(value);
      } catch(e) {
        try { el.value=String(value); } catch(_) {}
      }
      try { el.dispatchEvent(new Event('input',{bubbles:true})); } catch(e) {}
      try { el.dispatchEvent(new Event('change',{bubbles:true})); } catch(e) {}
      try { el.dispatchEvent(new Event('blur',{bubbles:true})); } catch(e) {}
    };

    const sleep = (ms) => new Promise(resolve => setTimeout(resolve,ms));

    const findField = (key) => {
      const aa=(aliases[key]||[]).map(norm);
      if(!aa.length) return null;
      const all=[...document.querySelectorAll('.q-field, input,textarea,select,[contenteditable="true"]')];
      for(const el of all){
        const cs=candidates(el);
        if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))) return el.classList?.contains('q-field') ? el : (el.closest('.q-field') || el);
      }
      return null;
    };

    const readQSelectOptions = async (key) => {
      const field=findField(key);
      if(!field) return [];
      try {
        field.scrollIntoView({block:'center',inline:'nearest'});
        const clickable=field.querySelector('.q-field__control,.q-field__native') || field;
        clickable.click();
        await sleep(120);
        const menuItems=[...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"]')];
        const values=menuItems.map(x=>String(x.innerText || x.textContent || '').trim()).filter(Boolean);
        document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
        await sleep(60);
        return [...new Set(values)];
      } catch(e) { return []; }
    };

    const collectOptions = async (keys) => {
      const out={};
      for(const key of keys){
        const values=await readQSelectOptions(key);
        if(values.length) out[key]=values;
      }
      if(Object.keys(out).length) send('options',{options:out});
      return out;
    };
    window.__EMIS_APP_BRIDGE__.collectOptions = (keys) => collectOptions(keys || []);

    window.__EMIS_APP_BRIDGE__.setFields = (values) => {
      const vals=values || {};
      for(const [key,value] of Object.entries(vals)){
        const aa=(aliases[key]||[]).map(norm);
        if(!aa.length) continue;
        const all=[...document.querySelectorAll(
          'input,textarea,select,[contenteditable="true"]'
        )];
        let best=null;
        for(const el of all){
          const cs=candidates(el);
          if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))){
            best=el; break;
          }
        }
        if(!best) continue;
        try {
          const qfield=best.closest ? best.closest('.q-field') : null;
          const qnative=qfield ? qfield.querySelector('.q-field__native') : null;
          if(qfield && qnative && qfield.classList.contains('q-select')){
            qfield.scrollIntoView({block:'center',inline:'nearest'});
            (qfield.querySelector('.q-field__control') || qnative || qfield).click();
            setTimeout(()=>{
              const wanted=norm(String(value ?? ''));
              const items=[...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"]')];
              const item=items.find(o=>norm(o.innerText||o.textContent||'')===wanted || norm(o.innerText||o.textContent||'').includes(wanted));
              if(item) item.click();
            },80);
          } else if(best.tagName==='SELECT'){
            const wanted=String(value ?? '');
            const option=[...best.options].find(o =>
              String(o.value)===wanted || norm(o.textContent)===norm(wanted)
            );
            if(option){
              best.value=option.value;
              best.dispatchEvent(new Event('input',{bubbles:true}));
              best.dispatchEvent(new Event('change',{bubbles:true}));
            }
          } else if(best.isContentEditable){
            best.textContent=String(value ?? '');
            best.dispatchEvent(new InputEvent('input',{
              bubbles:true,inputType:'insertText',data:String(value ?? '')
            }));
          } else {
            nativeSet(best,value ?? '');
          }
        } catch(e) {}
      }
      scan();
    };

    window.__EMIS_APP_BRIDGE__.focusField = (key) => {
      const aa=(aliases[key]||[]).map(norm);
      if(!aa.length) return false;
      const all=[...document.querySelectorAll(
        'input,textarea,select,[contenteditable="true"]'
      )];
      let best=null;
      for(const el of all){
        const cs=candidates(el);
        if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))){
          best=el; break;
        }
      }
      if(!best) return false;
      try {
        best.scrollIntoView({block:'center',inline:'nearest'});
        best.focus();
        best.click();
        send('focus',{field:key});
        return true;
      } catch(e) { return false; }
    };

    const clickText = (patterns) => {
      const els=[...document.querySelectorAll(
        'button,a,[role="button"],.q-btn,.q-item'
      )];
      for(const el of els){
        const t=norm(el.innerText || el.getAttribute('aria-label') || '');
        if(patterns.some(p=>p.test(t))){
          try { el.click(); return true; } catch(e) {}
        }
      }
      return false;
    };

    const openTarget = () => {
      const b=window.__EMIS_APP_BRIDGE__;
      if(b.opened) return true;
      if(b.mode==='add'){
        const re=b.entity==='student'
          ? [/إضافة\\s*طالب/i,/طالب\\s*جديد/i]
          : [/إضافة\\s*معلم/i,/معلم\\s*جديد/i];
        if(clickText(re)){
          b.opened=true;
          send('status',{message:'تم فتح نموذج الإضافة من EMIS'});
          setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType']),1200); setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType']),3000);
          return true;
        }
        return false;
      }
      const id=norm(b.recordId);
      if(!id) return false;
      const rows=[...document.querySelectorAll('tr')];
      const row=rows.find(r=>norm(r.innerText).includes(id));
      if(row){
        row.scrollIntoView({block:'center'});
        const target=row.querySelector('button,a,td:nth-child(2) span,td:nth-child(2)') || row;
        try { target.click(); } catch(e) {}
        setTimeout(()=>clickText([/تعديل/i,/تحرير/i,/بيانات/i]),350);
        b.opened=true;
        send('status',{message:'تم فتح سجل EMIS للمزامنة'});
        setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType']),1500); setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType']),3200);
        return true;
      }
      return false;
    };

    document.addEventListener('input',scan,true);
    document.addEventListener('change',scan,true);
    document.addEventListener('focusin',(e)=>{
      const key=fieldKey(e.target);
      if(key) send('focus',{field:key});
    },true);
    new MutationObserver(()=>setTimeout(scan,40)).observe(
      document.documentElement,
      {subtree:true,childList:true,attributes:true}
    );

    let tries=0;
    const timer=setInterval(()=>{
      tries++;
      if(openTarget() || tries>40) clearInterval(timer);
      scan();
    },350);
    scan();
    send('status',{message:'جسر المزامنة جاهز'});
  } catch(e) {
    try {
      EmisSyncChannel.postMessage(JSON.stringify({
        type:'status',message:'خطأ في جسر المزامنة: '+e
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
  try { if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.collectOptions) window.__EMIS_APP_BRIDGE__.collectOptions($encoded); } catch(e) {}
})();''';
    try { await controller.runJavaScript(js); } catch (_) {}
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
