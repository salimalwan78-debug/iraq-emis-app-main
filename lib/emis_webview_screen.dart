import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'loading_data_screen.dart';

class EmisWebviewScreen extends StatefulWidget {
  const EmisWebviewScreen({super.key});

  @override
  State<EmisWebviewScreen> createState() => _EmisWebviewScreenState();
}

class _EmisWebviewScreenState extends State<EmisWebviewScreen> {
  late final WebViewController _controller;
  Timer? _scanTimer;
  bool _isLoading = true;
  bool _handoffSent = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(
        'AuthChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleAuthMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
            _injectTokenScanner();
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _injectTokenScanner();
          },
          onUrlChange: (UrlChange change) {
            _injectTokenScanner();
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://emis.moedu.gov.iq'));

    // عند إعادة فتح التطبيق قد تكون جلسة EMIS موجودة مسبقاً.
    // Pinia قد يحتاج وقتاً لإعادة Hydration، لذلك لا نعتمد على فحص واحد.
    _scanTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_handoffSent) _injectTokenScanner();
    });
  }

  void _handleAuthMessage(String raw) {
    if (_handoffSent || !mounted) return;

    try {
      final data = jsonDecode(raw);
      final schoolId = data['schoolId']?.toString().trim();
      final token = data['token']?.toString().trim();
      final refreshToken = data['refreshToken']?.toString().trim();

      if (schoolId == null || schoolId.isEmpty || token == null || token.isEmpty) {
        return;
      }

      _handoffSent = true;
      _scanTimer?.cancel();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoadingDataScreen(
            token: token,
            refreshToken: refreshToken?.isEmpty == true ? null : refreshToken,
            schoolId: schoolId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('خطأ في قراءة بيانات جلسة EMIS: $e');
    }
  }

  void _injectTokenScanner() {
    const String jsCode = r'''
      (function() {
        function cleanBearer(value) {
          if (!value) return null;
          var s = String(value).trim();
          if (/^Bearer\s+/i.test(s)) s = s.replace(/^Bearer\s+/i, '').trim();
          return /^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(s) ? s : null;
        }

        function parseJson(value) {
          try { return JSON.parse(value); } catch (_) { return null; }
        }

        function walk(value, depth) {
          if (depth > 8 || value == null) return null;
          if (typeof value === 'string') return cleanBearer(value);
          if (typeof value !== 'object') return null;
          for (var key in value) {
            try {
              var found = walk(value[key], depth + 1);
              if (found) return found;
            } catch (_) {}
          }
          return null;
        }

        // EMIS uses a persisted Pinia auth store. Prefer it over arbitrary JWTs
        // so an old token from another storage entry cannot be selected.
        function targetedAuth() {
          var keys = ['auth', 'pinia:auth', 'auth-store'];
          for (var i = 0; i < keys.length; i++) {
            try {
              var raw = localStorage.getItem(keys[i]);
              if (!raw) continue;
              var obj = parseJson(raw);
              if (!obj) continue;
              var tokenObj = obj.token || obj.tokens || {};
              var access = cleanBearer(tokenObj.accessToken || obj.accessToken || obj.token);
              var refresh = tokenObj.refreshToken || obj.refreshToken || null;
              var school = obj.selectedSchoolId || obj.schoolId || null;
              if (access) {
                return {token: access, refreshToken: refresh ? String(refresh) : null, schoolId: school ? String(school) : null};
              }
            } catch (_) {}
          }
          return null;
        }

        function storageToken() {
          try {
            for (var i = 0; i < localStorage.length; i++) {
              var key = localStorage.key(i);
              var raw = localStorage.getItem(key);
              if (!raw) continue;
              var direct = cleanBearer(raw);
              if (direct) return {token: direct, refreshToken: null, schoolId: null};
              var obj = parseJson(raw);
              var nested = walk(obj, 0);
              if (nested) return {token: nested, refreshToken: null, schoolId: null};
            }
          } catch (_) {}
          return null;
        }

        function findSchoolId() {
          var sources = [location.href, location.pathname];
          var patterns = [
            /\/centers\/schools\/(\d+)/i,
            /[?&](?:schoolId|schoolID|school_id)=(\d+)/i
          ];
          for (var i = 0; i < sources.length; i++) {
            for (var j = 0; j < patterns.length; j++) {
              var m = String(sources[i]).match(patterns[j]);
              if (m) return m[1];
            }
          }
          try {
            var raw = localStorage.getItem('auth');
            var obj = raw ? parseJson(raw) : null;
            if (obj) {
              if (obj.selectedSchoolId) return String(obj.selectedSchoolId);
              if (obj.schoolId) return String(obj.schoolId);
              var entities = obj.user && Array.isArray(obj.user.entities) ? obj.user.entities : [];
              if (entities.length === 1 && entities[0] && entities[0].id != null) return String(entities[0].id);
            }
          } catch (_) {}
          return null;
        }

        var auth = targetedAuth() || storageToken();
        var schoolId = findSchoolId() || (auth && auth.schoolId ? auth.schoolId : null);
        if (auth && auth.token && schoolId && window.AuthChannel) {
          window.AuthChannel.postMessage(JSON.stringify({
            schoolId: String(schoolId),
            token: String(auth.token),
            refreshToken: auth.refreshToken ? String(auth.refreshToken) : null
          }));
        }
      })();
    ''';

    try {
      _controller.runJavaScript(jsCode);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text(
          'بوابة تسجيل الدخول - EMIS الرسمية',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _handoffSent = false;
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
