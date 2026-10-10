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
            widget.onStatus?.call('جاري فتح صفحة EMIS للمزامنة...');
          },
          onPageFinished: (url) async {
            if (_injectingToken) return;
            final reloaded = await _injectAuthentication();
            if (reloaded) return;
            await _installBridge();
            // The page may render the edit form after its first load event.
            // Request fresh schema and dropdowns after the form's async data.
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await refreshSchema();
            await Future<void>.delayed(const Duration(milliseconds: 700));
            widget.onStatus?.call('تم فتح نموذج EMIS وجلب بنيته وخياراته الحالية');
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
      last: '',
      schemaLast: ''
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
      // Prefer the human-readable EMIS label over generated Vue/Quasar IDs.
      // Generated IDs are often technically unique but useless as field titles.
      try {
        const parent=el.closest('.q-field');
        if(parent){
          const q=parent.querySelector('.q-field__label,.q-field__native-label,[data-label]');
          if(q){
            const clone=q.cloneNode(true);
            clone.querySelectorAll('i,svg,.q-icon,[class*=icon],button').forEach(n=>n.remove());
            const label=String(clone.innerText || clone.textContent || '').replace(/\s+/g,' ').trim();
            if(label && !/^(arrow_drop_down|expand_more|keyboard_arrow_down)\$/i.test(label)) return label;
          }
          const aria=parent.getAttribute('aria-label');
          if(aria && !/^(arrow_drop_down|expand_more|keyboard_arrow_down)\$/i.test(aria.trim())) return aria.trim();
        }
      } catch(e) {}
      try {
        const id=el.getAttribute('id');
        if(id){
          const lab=document.querySelector('label[for="'+CSS.escape(id)+'"]');
          if(lab && (lab.innerText || lab.textContent)) return String(lab.innerText || lab.textContent).trim();
        }
      } catch(e) {}
      try {
        const lab=el.closest('label');
        if(lab && (lab.innerText || lab.textContent)) return String(lab.innerText || lab.textContent).trim();
      } catch(e) {}
      for (const a of ['aria-label','placeholder','data-label']) {
        try { const v=el.getAttribute(a); if(v && v.trim()) return v.trim(); } catch(e) {}
      }
      for (const a of ['name','id','data-cy','data-test']) {
        try { const v=el.getAttribute(a); if(v && v.trim()) return v.trim(); } catch(e) {}
      }
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
      // Dynamic EMIS fields often have generated IDs. Prefer their visible
      // label as the key so Flutter can show a meaningful title and find the
      // same field again when the user edits it.
      const label=String(textOf(el) || '').trim();
      const q=el.closest ? el.closest('.q-field') : null;
      const generatedId=!!(q && (el.getAttribute('id') || '').match(/^(q-|input-|select-)/i));
      if(label && (!el.getAttribute('name') || generatedId)) return label;
      const raw=(el.getAttribute('name') || el.getAttribute('id') || el.getAttribute('data-cy') || el.getAttribute('data-test') || '').trim();
      if(raw){
        const cleaned=raw.replace(/\[(\d+)\]/g,'_\$1').replace(/[^a-zA-Z0-9_]/g,'_').replace(/_+/g,'_').replace(/^_+|_+\$/g,'');
        if(cleaned) return cleaned.charAt(0).toLowerCase()+cleaned.slice(1);
      }
      return label;
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
      const schema={};
      document.querySelectorAll('input,textarea,select,[contenteditable="true"]').forEach(el=>{
        const key=fieldKey(el); if(!key) return;
        const tag=String(el.tagName||'').toLowerCase();
        const q=el.closest ? el.closest('.q-field') : null;
        const label=textOf(el) || (q && q.querySelector('.q-field__label') ? q.querySelector('.q-field__label').innerText : '') || key;
        let kind=(tag==='select' || (q && q.classList.contains('q-select'))) ? 'select' : (tag==='textarea' ? 'textarea' : (String(el.type||'').toLowerCase()==='date' ? 'date' : 'text'));
        let opts=[];
        if(tag==='select') opts=[...el.options].map(o=>({value:String(o.value||o.textContent||'').trim(),label:String(o.textContent||'').trim()})).filter(o=>o.label);
        schema[key]={label:String(label).trim(),type:kind,required:!!el.required || String(el.getAttribute('aria-required')||'')==='true',value:String(readValue(el)||''),options:opts};
      });
      const b=window.__EMIS_APP_BRIDGE__;
      // Values are sent in snapshots; schema events are only for structural
      // changes. Including values here caused every keystroke to reopen all
      // dropdowns and prevented reliable live editing.
      const schemaShape={};
      Object.keys(schema).forEach(k=>{
        const meta=Object.assign({},schema[k]);
        delete meta.value;
        schemaShape[k]=meta;
      });
      const schemaSerial=JSON.stringify(schemaShape);
      if(schemaSerial!==b.schemaLast){
        b.schemaLast=schemaSerial;
        if(Object.keys(schema).length) {
          send('schema',{fields:schema,url:location.href});
          // EMIS uses Quasar QSelect controls which are not native <select>s.
          // Read their live menu options after the current DOM/schema settles.
          const selectKeys=Object.keys(schema).filter(k=>schema[k] && schema[k].type==='select');
          if(selectKeys.length) setTimeout(()=>collectOptions(selectKeys),180);
        }
      }
      const serial=JSON.stringify(fields);
      if(serial!==b.last){ b.last=serial; send('snapshot',{fields:fields,url:location.href}); }
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
      const wanted=norm(key);
      const aa=(aliases[key]||[]).map(norm);
      const all=[...document.querySelectorAll('.q-field, input,textarea,select,[contenteditable="true"]')];
      for(const el of all){
        const dynamicKey=norm(fieldKey(el));
        const cs=candidates(el);
        if(dynamicKey===wanted || cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c))))
          return el.classList?.contains('q-field') ? el : (el.closest('.q-field') || el);
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
        let menuItems=[];
        for(let attempt=0;attempt<30;attempt++){
          await sleep(100);
          menuItems=[...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"], [role="listbox"] [role="option"]')];
          if(menuItems.length) break;
        }
        const values=[];
        const seen=new Set();
        const collect=()=>{
          [...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"], [role="listbox"] [role="option"]')]
            .forEach(x=>{
              const clone=x.cloneNode(true);
              clone.querySelectorAll('i,svg,.q-icon,[class*=icon],button').forEach(n=>n.remove());
              const label=String(clone.innerText || clone.textContent || '').replace(/\s+/g,' ').trim();
              if(!label || /^(اختر|select|search|arrow_drop_down|expand_more)\$/i.test(label)) return;
              const value=String(x.getAttribute('data-value') || x.getAttribute('data-id') || x.getAttribute('value') || x.getAttribute('aria-valuetext') || label).trim();
              const signature=value+'|'+label;
              if(!seen.has(signature)){seen.add(signature);values.push({value:value,label:label});}
            });
        };
        collect();
        const menu=document.querySelector('.q-menu .q-virtual-scroll__content, .q-menu .scroll, .q-menu [role="listbox"]');
        if(menu){
          let unchanged=0;
          for(let i=0;i<80 && unchanged<5;i++){
            const before=seen.size;
            menu.scrollTop=Math.min(menu.scrollTop+Math.max(160,menu.clientHeight*0.75),menu.scrollHeight);
            await sleep(120);
            collect();
            unchanged=seen.size===before?unchanged+1:0;
            if(menu.scrollTop+menu.clientHeight>=menu.scrollHeight-2 && unchanged>=2) break;
          }
        }
        document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
        await sleep(80);
        return values;
      } catch(e) {
        try { document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true})); } catch(_) {}
        return [];
      }
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
    window.__EMIS_APP_BRIDGE__.scanNow = () => scan();

    window.__EMIS_APP_BRIDGE__.setFields = (values) => {
      const vals=values || {};
      for(const [key,value] of Object.entries(vals)){
        const wanted=norm(key);
        const aa=(aliases[key]||[]).map(norm);
        const all=[...document.querySelectorAll(
          'input,textarea,select,[contenteditable="true"]'
        )];
        let best=null;
        for(const el of all){
          const cs=candidates(el);
          if(norm(fieldKey(el))===wanted || cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))){
            best=el; break;
          }
        }
        if(!best) continue;
        try {
          const qfield=best.closest ? best.closest('.q-field') : null;
          const qnative=qfield ? qfield.querySelector('.q-field__native') : null;
          if(qfield && qnative && qfield.classList.contains('q-select')){
            const wanted=norm(String(value ?? ''));
            const current=norm(qnative.value || qfield.querySelector('.q-field__native')?.value || '');
            if(current===wanted) continue;
            qfield.scrollIntoView({block:'center',inline:'nearest'});
            (qfield.querySelector('.q-field__control') || qnative || qfield).click();
            setTimeout(()=>{
              const items=[...document.querySelectorAll('.q-menu .q-item, .q-menu [role="option"]')];
              const item=items.find(o=>{
                const text=norm(o.innerText||o.textContent||'');
                const attrs=['data-value','data-id','value','aria-label'].map(a=>norm(o.getAttribute(a)||''));
                return text===wanted || text.includes(wanted) || attrs.includes(wanted);
              });
              if(item) item.click();
              else document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
            },100);
          } else if(best.tagName==='SELECT'){
            const wanted=String(value ?? '');
            const option=[...best.options].find(o =>
              String(o.value)===wanted || norm(o.textContent)===norm(wanted)
            );
            if(option && (best.value!==option.value || norm(best.options[best.selectedIndex]?.textContent)!==norm(value))){
              best.value=option.value;
              best.dispatchEvent(new Event('input',{bubbles:true}));
              best.dispatchEvent(new Event('change',{bubbles:true}));
            }
          } else if(best.isContentEditable){
            if(norm(best.textContent)===norm(String(value ?? ''))) continue;
            best.textContent=String(value ?? '');
            best.dispatchEvent(new InputEvent('input',{
              bubbles:true,inputType:'insertText',data:String(value ?? '')
            }));
          } else {
            if(String(best.value ?? '')===String(value ?? '')) continue;
            nativeSet(best,value ?? '');
          }
        } catch(e) {}
      }
      scan();
    };

    window.__EMIS_APP_BRIDGE__.focusField = (key) => {
      const wanted=norm(key);
      const aa=(aliases[key]||[]).map(norm);
      const all=[...document.querySelectorAll(
        'input,textarea,select,[contenteditable="true"]'
      )];
      let best=null;
      for(const el of all){
        const cs=candidates(el);
        if(norm(fieldKey(el))===wanted || cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))){
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
          setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType','educationLevel','gender','maritalStatus']),1200); 
          setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType','educationLevel','gender','maritalStatus']),3000);
          return true;
        }
        return false;
      }
      const id=norm(b.recordId);
      if(!id) return false;
      // The edit screen now opens the exact EMIS edit URL from the moment
      // the user taps Edit. Do not search/click a management table again.
      const currentPath=norm(location.pathname);
      if(currentPath.includes('/management/edit/') && currentPath.includes(id)){
        b.opened=true;
        send('status',{message:'تم تحميل نموذج تعديل المعلم من EMIS وجاري جلب القيم والخيارات الحالية'});
        const selectKeys=()=>{
          const schema=window.__EMIS_APP_BRIDGE__;
          const all=[...document.querySelectorAll('input,textarea,select,[contenteditable="true"]')];
          const keys=[...new Set(all.map(el=>fieldKey(el)).filter(Boolean))];
          return keys.filter(k=>{const f=findField(k);return !!(f && (f.classList.contains('q-select') || f.querySelector('.q-select') || f.querySelector('select')));});
        };
        [500,1200,2400,4200].forEach(delay=>setTimeout(()=>{
          scan(); collectOptions(selectKeys());
        },delay));
        return true;
      }
      const rows=[...document.querySelectorAll('tr')];
      const row=rows.find(r=>norm(r.innerText).includes(id));
      if(row){
        row.scrollIntoView({block:'center'});
        const target=row.querySelector('button,a,td:nth-child(2) span,td:nth-child(2)') || row;
        try { target.click(); } catch(e) {}
        setTimeout(()=>clickText([/تعديل/i,/تحرير/i,/بيانات/i]),350);
        b.opened=true;
        send('status',{message:'تم فتح سجل EMIS للمزامنة'});
        setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType','educationLevel','gender','maritalStatus']),1500); 
        setTimeout(()=>collectOptions(['employmentType','employeeCategory','status','classification','currentPosition','positionType','educationLevel','gender','maritalStatus']),3200);
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

  Future<void> refreshSchema() async {
    if (!_ready) return;
    try {
      await controller.runJavaScript('''(function(){try{if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.scanNow) window.__EMIS_APP_BRIDGE__.scanNow();}catch(e){}})();''');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep a realistic mobile viewport. A 1x1 WebView breaks responsive EMIS
    // forms and causes Quasar dropdown menus to be clipped or fail to render.
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
