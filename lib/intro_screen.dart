import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'emis_webview_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    // ربط ملف الفيديو المحلي
    _controller = VideoPlayerController.asset('assets/intro.mp4');

    try {
      // الانتظار حتى يتم تهيئة الفيديو بالكامل في الذاكرة
      await _controller.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        // بدء التشغيل فوراً بعد اكتمال التهيئة
        await _controller.play();
        _controller.setLooping(false);
      }
    } catch (e) {
      // في حال واجه الجهاز أي مشكلة في الترميز، يتم الانتقال للمتصفح تلقائياً لمنع التوقف
      _navigateToWebView();
    }

    // مراقبة انتهاء الفيديو بدقة للانتقال التلقائي
    _controller.addListener(() {
      if (_controller.value.isInitialized &&
          _controller.value.position >= _controller.value.duration) {
        _navigateToWebView();
      }
    });
  }

  void _navigateToWebView() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const EmisWebviewScreen()),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isInitialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const CircularProgressIndicator(
                color: Colors.white,
              ), // مؤشر تحميل أنيق ريثما يجهز الفيديو
      ),
    );
  }
}
