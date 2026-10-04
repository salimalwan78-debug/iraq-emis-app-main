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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(
        'AuthChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            final schoolId = data['schoolId'];
            final token = data['token'];
            
            if (schoolId != null && token != null) {
              // التوجيه إلى شاشة التحميل لجلب كافة البيانات
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => LoadingDataScreen(
                    token: token.toString(),
                    schoolId: schoolId.toString(),
                  ),
                ),
              );
            }
          } catch (e) {
            debugPrint("خطأ في قراءة بيانات الدخول: $e");
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
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
  }

  void _injectTokenScanner() {
    const String jsCode = r'''
      (function() {
        var schoolMatch = location.pathname.match(/\/centers\/schools\/(\d+)/);
        function cleanBearer(value) {
            if (!value) return null;
            var s = String(value).trim();
            if (/^Bearer\s+/i.test(s)) {
                var t = s.replace(/^Bearer\s+/i, "").trim();
                if (/^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(t)) return t;
            }
            if (/^ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(s)) return s;
            return null;
        }

        function searchStorage(storage) {
            try {
                for (var i = 0; i < storage.length; i++) {
                    var key = storage.key(i);
                    var value = storage.getItem(key);
                    var token = cleanBearer(value);
                    if (token) return token;
                    try {
                        var obj = JSON.parse(value);
                        var walk = function(x) {
                            if (!x) return null;
                            if (typeof x === "string") return cleanBearer(x);
                            if (typeof x === "object") {
                                for (var k in x) {
                                    var result = walk(x[k]);
                                    if (result) return result;
                                }
                            }
                            return null;
                        };
                        token = walk(obj);
                        if (token) return token;
                    } catch(e) {}
                }
            } catch(e) {}
            return null;
        }

        var foundToken = searchStorage(localStorage) || searchStorage(sessionStorage);
        if (schoolMatch && foundToken) {
            AuthChannel.postMessage(JSON.stringify({
                schoolId: schoolMatch[1],
                token: foundToken
            }));
        }
      })();
    ''';
    
    _controller.runJavaScript(jsCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text(
          'بوابة تسجيل الدخول - EMIS الرسمية',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
