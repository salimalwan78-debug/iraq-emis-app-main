package iq.moedu.emis.emis_app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "emis.google_speech"
    private val eventChannelName = "emis.google_speech/events"
    private val googlePackage = "com.google.android.googlequicksearchbox"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var active = false
    private var explicitStop = false
    private var currentSessionId = 0
    private var currentLocale = "ar-IQ"
    private var restartRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> {
                        val service = findGoogleRecognitionService()
                        result.success(
                            mapOf(
                                "available" to (service != null && SpeechRecognizer.isRecognitionAvailable(this)),
                                "package" to (service?.packageName ?: ""),
                                "service" to (service?.className ?: ""),
                                "provider" to if (service != null) "Google" else "",
                            )
                        )
                    }

                    "start" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        val locale = call.argument<String>("locale")?.takeIf { it.isNotBlank() } ?: "ar-IQ"
                        startGoogleRecognition(sessionId, locale, result)
                    }

                    "stop" -> {
                        stopGoogleRecognition(cancel = false)
                        result.success(true)
                    }

                    "cancel" -> {
                        stopGoogleRecognition(cancel = true)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun findGoogleRecognitionService(): ComponentName? {
        val intent = Intent(RecognitionService.SERVICE_INTERFACE)
        val services = try {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                packageManager.queryIntentServices(
                    intent,
                    PackageManager.ResolveInfoFlags.of(0L)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentServices(intent, 0)
            }
        } catch (_: Exception) {
            emptyList()
        }

        val google = services.firstOrNull {
            it.serviceInfo?.packageName == googlePackage
        }?.serviceInfo ?: return null

        return ComponentName(google.packageName, google.name)
    }

    private fun ensureRecognizer(): Boolean {
        if (recognizer != null) return true

        val service = findGoogleRecognitionService() ?: return false
        recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(this, service).also {
                it.setRecognitionListener(recognitionListener)
            }
        } catch (_: Exception) {
            null
        }
        return recognizer != null
    }

    private fun startGoogleRecognition(
        sessionId: Int,
        locale: String,
        result: MethodChannel.Result,
    ) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emit("error", sessionId, mapOf("message" to "لا توجد خدمة تعرف صوتي متاحة على الجهاز."))
            result.success(false)
            return
        }

        if (findGoogleRecognitionService() == null) {
            emit(
                "error",
                sessionId,
                mapOf("message" to "خدمة Google للتعرف على الكلام غير متوفرة على هذا الجهاز. تأكد من تثبيت/تحديث تطبيق Google.")
            )
            result.success(false)
            return
        }

        if (!ensureRecognizer()) {
            emit("error", sessionId, mapOf("message" to "تعذر تشغيل خدمة Google للتعرف على الكلام."))
            result.success(false)
            return
        }

        cancelScheduledRestart()
        active = true
        explicitStop = false
        currentSessionId = sessionId
        currentLocale = locale

        try {
            recognizer?.cancel()
            startListeningInternal()
            result.success(true)
        } catch (e: Exception) {
            active = false
            emit("error", sessionId, mapOf("message" to (e.message ?: "تعذر بدء التعرف الصوتي.")))
            result.success(false)
        }
    }

    private fun startListeningInternal() {
        if (!active || explicitStop) return

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, currentLocale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, currentLocale)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            // نطلب زمناً أطول قبل اعتبار الصمت نهاية للكلام. Google قد يتجاهل
            // هذه القيم حسب إصدار الخدمة، لذلك توجد إعادة تشغيل تلقائية أدناه.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 12000)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 10000)
        }
        try {
            recognizer?.startListening(intent)
            emit("listening", currentSessionId, emptyMap())
        } catch (e: Exception) {
            emit("error", currentSessionId, mapOf("message" to (e.message ?: "تعذر بدء الاستماع.")))
            scheduleRestart(500)
        }
    }

    private fun stopGoogleRecognition(cancel: Boolean) {
        explicitStop = true
        active = false
        cancelScheduledRestart()
        try {
            if (cancel) {
                recognizer?.cancel()
            } else {
                recognizer?.stopListening()
            }
        } catch (_: Exception) {
        }
        emit("stopped", currentSessionId, emptyMap())
    }

    private fun scheduleRestart(delayMs: Long) {
        if (!active || explicitStop) return
        cancelScheduledRestart()
        val session = currentSessionId
        restartRunnable = Runnable {
            restartRunnable = null
            if (active && !explicitStop && session == currentSessionId) {
                try {
                    recognizer?.cancel()
                } catch (_: Exception) {
                }
                startListeningInternal()
            }
        }
        mainHandler.postDelayed(restartRunnable!!, delayMs)
    }

    private fun cancelScheduledRestart() {
        restartRunnable?.let { mainHandler.removeCallbacks(it) }
        restartRunnable = null
    }

    private fun emit(type: String, sessionId: Int, data: Map<String, Any?>) {
        val payload = HashMap<String, Any?>()
        payload["type"] = type
        payload["sessionId"] = sessionId
        payload.putAll(data)
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            emit("ready", currentSessionId, emptyMap())
        }

        override fun onBeginningOfSpeech() {
            emit("begin", currentSessionId, emptyMap())
        }

        override fun onRmsChanged(rmsdB: Float) {
            emit("level", currentSessionId, mapOf("rms" to rmsdB))
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            emit("endOfSpeech", currentSessionId, emptyMap())
        }

        override fun onError(error: Int) {
            emit("error", currentSessionId, mapOf("code" to error, "message" to speechErrorMessage(error)))
            if (active && !explicitStop) {
                val delay = when (error) {
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> 600L
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                    SpeechRecognizer.ERROR_SERVER,
                    SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> 900L
                    else -> 250L
                }
                scheduleRestart(delay)
            }
        }

        override fun onResults(results: Bundle?) {
            val values = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = values?.firstOrNull()?.trim().orEmpty()
            emit("result", currentSessionId, mapOf("text" to text))
            if (active && !explicitStop) {
                // Google/Android قد ينهي جلسة التعرف تلقائياً بعد الصمت. نعيد
                // فتح جلسة جديدة داخل نفس sessionId حتى يبقى الميكروفون مفتوحاً
                // إلى أن يطلب المستخدم إيقافه بالنقر.
                scheduleRestart(120L)
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val values = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = values?.firstOrNull()?.trim().orEmpty()
            if (text.isNotEmpty()) {
                emit("partial", currentSessionId, mapOf("text" to text))
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun speechErrorMessage(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "تعذر الوصول إلى الميكروفون."
        SpeechRecognizer.ERROR_CLIENT -> "حدث خطأ في خدمة التعرف الصوتي."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "لم يتم منح صلاحية الميكروفون."
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "اللغة العربية غير مدعومة في خدمة Google الحالية."
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "اللغة العربية غير متاحة حالياً في خدمة Google."
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "تعذر الاتصال بخدمة Google للتعرف على الكلام."
        SpeechRecognizer.ERROR_NO_MATCH -> "لم يتم التعرف على الكلام."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "خدمة Google مشغولة، ستتم إعادة المحاولة تلقائياً."
        SpeechRecognizer.ERROR_SERVER,
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "حدث خطأ في خادم Google للتعرف على الكلام."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "لم يتم سماع كلام واضح، ستتم إعادة المحاولة تلقائياً."
        else -> "خطأ في التعرف الصوتي (رمز $code)."
    }

    override fun onDestroy() {
        active = false
        explicitStop = true
        cancelScheduledRestart()
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
        super.onDestroy()
    }
}
