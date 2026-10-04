import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// جسر مزامنة حي بين نموذج التطبيق وصفحة EMIS داخل WebView.
///
/// لا يستبدل API الخاص بالتطبيق؛ بل يبقي صفحة EMIS الحقيقية مفتوحة في WebView
/// ويراقب حقولها عبر JavaScript، ثم يرسل التغييرات إلى النموذج، والعكس صحيح.
class EmisLiveSync extends StatefulWidget {
  final String url;
  final String mode; // add | edit
  final String entity; // student | teacher
  final String? recordId;
  final Map<String, List<String>> aliases;
  final ValueChanged<Map<String, String>> onSnapshot;
  final ValueChanged<String>? onStatus;

  const EmisLiveSync({
    super.key,
    required this.url,
    required this.mode,
    required this.entity,
    required this.aliases,
    required this.onSnapshot,
    this.recordId,
    this.onStatus,
  });

  @override
  State<EmisLiveSync> createState() => EmisLiveSyncState();
}

class EmisLiveSyncState extends State<EmisLiveSync> {
  late final WebViewController controller;
  Timer? _retryTimer;
  bool _ready = false;
  String _lastUrl = '';

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
          onPageStarted: (url) {
            _ready = false;
            _lastUrl = url;
            widget.onStatus?.call('جاري فتح صفحة EMIS الحية...');
          },
          onPageFinished: (url) async {
            _lastUrl = url;
            await _installBridge();
          },
          onUrlChange: (change) {
            if (change.url != null) _lastUrl = change.url!;
          },
          onWebResourceError: (error) {
            widget.onStatus?.call('تعذر تحميل صفحة EMIS الحية: ${error.errorCode}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
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
      try { EmisSyncChannel.postMessage(JSON.stringify(Object.assign({type:type}, payload||{}))); } catch(e) {}
    };
    const norm = (s) => String(s||'').replace(/\\s+/g,' ').trim().toLowerCase();
    const textOf = (el) => {
      if (!el) return '';
      const a = el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('name') || el.getAttribute('id'));
      if (a) return a;
      const lab = el.closest && el.closest('label');
      if (lab) return lab.innerText || '';
      const parent = el.parentElement;
      if (parent) {
        const q = parent.querySelector('label,.q-field__label,.q-field__native-label');
        if (q) return q.innerText || '';
      }
      return '';
    };
    const candidates = (el) => {
      const out=[];
      ['id','name','aria-label','placeholder','data-cy','data-test'].forEach(a=>{try{const v=el.getAttribute(a);if(v)out.push(v)}catch(e){}});
      const t=textOf(el); if(t) out.push(t);
      const parent=el.closest && el.closest('.q-field');
      if(parent){
        const l=parent.querySelector('.q-field__label'); if(l) out.push(l.innerText||'');
      }
      return [...new Set(out.map(norm).filter(Boolean))];
    };
    const aliases = window.__EMIS_APP_BRIDGE__.aliases || {};
    const fieldKey = (el) => {
      const cs=candidates(el);
      for(const k of Object.keys(aliases)){
        const aa=(aliases[k]||[]).map(norm);
        if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))) return k;
      }
      return cs[0] || '';
    };
    const readValue = (el) => {
      if (el.tagName==='SELECT') {
        const o=el.options && el.selectedIndex>=0 ? el.options[el.selectedIndex] : null;
        return o ? (el.value || o.textContent || '') : (el.value || '');
      }
      return ('value' in el) ? el.value : (el.textContent || '');
    };
    const scan = () => {
      const fields={};
      document.querySelectorAll('input,textarea,select,[contenteditable="true"]').forEach(el=>{
        const key=fieldKey(el); if(!key) return;
        const v=String(readValue(el)||'');
        if(!(key in fields) || v.trim()!=='') fields[key]=v;
      });
      const serial=JSON.stringify(fields);
      if(serial!==window.__EMIS_APP_BRIDGE__.last){
        window.__EMIS_APP_BRIDGE__.last=serial;
        send('snapshot',{fields:fields,url:location.href});
      }
    };
    const nativeSet = (el, value) => {
      try {
        const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto,'value')?.set;
        if(setter) setter.call(el,String(value)); else el.value=String(value);
      } catch(e) { try{el.value=String(value)}catch(_){ } }
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new Event('change',{bubbles:true}));
      el.dispatchEvent(new Event('blur',{bubbles:true}));
    };
    window.__EMIS_APP_BRIDGE__.setFields = (values) => {
      const vals=values||{};
      for(const [key,value] of Object.entries(vals)){
        const aa=(aliases[key]||[]).map(norm);
        const all=[...document.querySelectorAll('input,textarea,select,[contenteditable="true"]')];
        let best=null;
        for(const el of all){
          const cs=candidates(el);
          if(cs.some(c=>aa.some(a=>c===a || c.includes(a) || a.includes(c)))){best=el;break;}
        }
        if(!best) continue;
        if(best.tagName==='SELECT'){
          const wanted=String(value);
          const option=[...best.options].find(o=>String(o.value)===wanted || norm(o.textContent)===norm(wanted));
          if(option){best.value=option.value;best.dispatchEvent(new Event('change',{bubbles:true}));}
        }else if(best.isContentEditable){best.textContent=String(value);best.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:String(value)}));}
        else nativeSet(best,value);
      }
      scan();
    };

    const clickText = (patterns) => {
      const els=[...document.querySelectorAll('button,a,[role="button"],.q-btn,.q-item')];
      for(const el of els){
        const t=norm(el.innerText||el.getAttribute('aria-label')||'');
        if(patterns.some(p=>p.test(t))){el.click();return true;}
      }
      return false;
    };
    const openTarget = () => {
      const b=window.__EMIS_APP_BRIDGE__;
      if(b.opened) return true;
      if(b.mode==='add'){
        const re=b.entity==='student' ? [/إضافة\\s*طالب/,/طالب\\s*جديد/,/إضافة/] : [/إضافة\\s*معلم/,/معلم\\s*جديد/,/إضافة/];
        if(clickText(re)){b.opened=true;send('status',{message:'تم فتح نموذج الإضافة من EMIS'});return true;}
        return false;
      }
      const id=norm(b.recordId);
      const rows=[...document.querySelectorAll('tr')];
      const row=rows.find(r=>id && norm(r.innerText).includes(id));
      if(row){
        row.scrollIntoView({block:'center'});
        const target=row.querySelector('td:nth-child(2) span,td:nth-child(2)') || row;
        target.click();
        setTimeout(()=>{clickText([/تعديل/,/تحرير/,/بيانات/,/إدارة/]);},350);
        b.opened=true;send('status',{message:'تم فتح سجل ${entity} من EMIS'});return true;}
      return false;
    };
    window.__EMIS_APP_BRIDGE__.scan=scan;
    window.__EMIS_APP_BRIDGE__.openTarget=openTarget;
    document.addEventListener('input',scan,true);
    document.addEventListener('change',scan,true);
    new MutationObserver(()=>setTimeout(scan,50)).observe(document.documentElement,{subtree:true,childList:true,attributes:true});
    let tries=0;
    const timer=setInterval(()=>{tries++; if(openTarget() || tries>30) clearInterval(timer); scan();},500);
    scan();
    send('status',{message:'مزامنة EMIS مفعّلة'});
  } catch(e) {
    try{EmisSyncChannel.postMessage(JSON.stringify({type:'status',message:'خطأ في جسر المزامنة: '+e}))}catch(_){}
  }
})();''';

    try {
      await controller.runJavaScript(js);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> pushValues(Map<String, String> values) async {
    if (!_ready || values.isEmpty) return;
    final encoded = jsonEncode(values);
    final js = '''
(function(){
  try{
    if(window.__EMIS_APP_BRIDGE__ && window.__EMIS_APP_BRIDGE__.setFields){
      window.__EMIS_APP_BRIDGE__.setFields($encoded);
    }
  }catch(e){}
})();''';
    try {
      await controller.runJavaScript(js);
    } catch (_) {}
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 2,
          height: 2,
          child: WebViewWidget(controller: controller),
        ),
      ),
    );
  }
}
