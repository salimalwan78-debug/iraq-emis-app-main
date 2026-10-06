package iq.moedu.emis.emis_app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private val googleQuickSearchPackage = "com.google.android.googlequicksearchbox"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var active = false
    private var explicitStop = false
    private var currentSessionId = 0
    private var currentLocale = "ar-IQ"
    private var currentEngine = "google"
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
                    "getInfo" -> result.success(getRecognitionInfo())

                    "start" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        val locale = call.argument<String>("locale")?.takeIf { it.isNotBlank() } ?: "ar-IQ"
                        val engine = call.argument<String>("engine")?.takeIf { it.isNotBlank() } ?: "google"
                        startRecognition(sessionId, locale, engine, result)
                    }

                    "stop" -> {
                        stopRecognition(cancel = false)
                        result.success(true)
                    }

                    "cancel" -> {
                        stopRecognition(cancel = true)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android itself decides which service is the default SpeechRecognizer through
     * "voice_recognition_service". On some Samsung/Android builds the
     * Google app is installed and works perfectly, but it does NOT publish the
     * recognition service under com.google.android.googlequicksearchbox. Therefore
     * requiring that exact package was the reason the previous build reported
     * "Google service unavailable".
     */
    private fun defaultRecognitionService(): ComponentName? {
        val flattened = try {
            Settings.Secure.getString(
                contentResolver,
                "voice_recognition_service"
            )
        } catch (_: Exception) {
            null
        }
        return flattened?.takeIf { it.isNotBlank() }?.let {
            ComponentName.unflattenFromString(it)
        }
    }

    private fun allRecognitionServices(): List<ComponentName> {
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

        return services.mapNotNull { info ->
            val service = info.serviceInfo ?: return@mapNotNull null
            ComponentName(service.packageName, service.name)
        }
    }

    private fun findGoogleRecognitionService(): ComponentName? {
        val services = allRecognitionServices()
        val default = defaultRecognitionService()

        // الأفضل: إذا كانت خدمة النظام الافتراضية نفسها Google، نستخدمها.
        if (default != null && default.packageName.startsWith("com.google.android")) {
            return default
        }

        // بعض الأجهزة تعرض Google كتطبيق Google Quick Search Box.
        services.firstOrNull { it.packageName == googleQuickSearchPackage }?.let { return it }

        // بعض إصدارات Android/Google تعرض Speech Recognition تحت حزمة Google أخرى.
        services.firstOrNull { it.packageName.startsWith("com.google.android") }?.let { return it }

        return null
    }

    private fun getRecognitionInfo(): Map<String, Any?> {
        val default = defaultRecognitionService()
        val google = findGoogleRecognitionService()
        val frameworkAvailable = try {
            SpeechRecognizer.isRecognitionAvailable(this)
        } catch (_: Exception) {
            false
        }

        val effective = google ?: default
        val provider = when {
            effective?.packageName?.startsWith("com.google.android") == true -> "Google"
            effective != null -> "النظام / مزود التعرف الافتراضي"
            else -> ""
        }

        return mapOf(
            // مهم: available لا يعتمد على وجود com.google.android.googlequicksearchbox فقط.
            "available" to (frameworkAvailable && effective != null),
            "frameworkAvailable" to frameworkAvailable,
            "package" to (effective?.packageName ?: ""),
            "service" to (effective?.className ?: ""),
            "defaultPackage" to (default?.packageName ?: ""),
            "defaultService" to (default?.className ?: ""),
            "googleAvailable" to (google != null),
            "googlePackage" to (google?.packageName ?: ""),
            "googleService" to (google?.className ?: ""),
            "provider" to provider,
        )
    }

    private fun createRecognizer(engine: String): SpeechRecognizer? {
        val service = if (engine == "google") findGoogleRecognitionService() else null

        return try {
            if (service != null) {
                SpeechRecognizer.createSpeechRecognizer(this, service)
            } else {
                // هذا هو المسار المهم على الأجهزة التي يكون فيها Google هو
                // مزود النظام لكن لا يمكن العثور عليه تحت اسم حزمة Google المتوقّع.
                SpeechRecognizer.createSpeechRecognizer(this)
            }.also {
                it.setRecognitionListener(recognitionListener)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureRecognizer(engine: String): Boolean {
        if (recognizer != null && currentEngine == engine) return true

        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = createRecognizer(engine)
        currentEngine = engine
        return recognizer != null
    }

    private fun startRecognition(
        sessionId: Int,
        locale: String,
        engine: String,
        result: MethodChannel.Result,
    ) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emit("error", sessionId, mapOf("message" to "لا توجد خدمة تعرف صوتي متاحة على الجهاز."))
            result.success(false)
            return
        }

        val requestedEngine = if (engine == "legacy") "google" else "google"
        // Google mode: use Google's explicit service when Android exposes it;
        // otherwise use Android's own default SpeechRecognizer service.
        // We deliberately do NOT require the Google package to be discoverable:
        // on some devices Google performs speech recognition through the default
        // Android service even though its package is not listed as a direct
        // RecognitionService. Android documents createSpeechRecognizer(context)
        // as the normal way to use that default service.

        if (!ensureRecognizer(requestedEngine)) {
            emit("error", sessionId, mapOf("message" to "تعذر إنشاء خدمة التعرف الصوتي. سيتمكن التطبيق من استخدام المسار الاحتياطي من إعدادات EMIS."))
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
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
            // نستخدم نموذج web_search لأن خدمة Google التي يستخدمها تطبيق Google
            // نفسه محسّنة لعدد أكبر من اللغات من free_form، وهو مهم للعربية.
            // نُبقي ar-IQ كلغة مطلوبة حتى يفهم أسماء الطلاب والألفاظ العراقية.
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, currentLocale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, currentLocale)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            // لا نطلب التعرف دون اتصال قسراً. إذا كانت خدمة Google تستطيع
            // استخدام التعرف الشبكي فلتستخدمه، لأن ذلك غالباً أفضل للعبارات
            // العربية الضعيفة والأسماء.
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            // نمنح الخدمة زمناً أطول قبل اعتبار الكلام منتهياً. بعض الخدمات
            // قد تتجاهل هذه القيم، لكن لا توجد هنا قيمة قصيرة تفرض الإغلاق.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 15000)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 12000)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 250)
        }
        try {
            recognizer?.startListening(intent)
            emit("listening", currentSessionId, emptyMap())
        } catch (e: Exception) {
            emit("error", currentSessionId, mapOf("message" to (e.message ?: "تعذر بدء الاستماع.")))
            scheduleRestart(500)
        }
    }

    private fun stopRecognition(cancel: Boolean) {
        explicitStop = true
        active = false
        cancelScheduledRestart()
        try {
            if (cancel) recognizer?.cancel() else recognizer?.stopListening()
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
        mainHandler.post { eventSink?.success(payload) }
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
            val values = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
            val confidences = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
            val text = values.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
            emit(
                "result",
                currentSessionId,
                mapOf(
                    "text" to text,
                    "alternates" to values,
                    "confidences" to (confidences?.toList() ?: emptyList<Float>())
                )
            )
            if (active && !explicitStop) scheduleRestart(120L)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val values = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
            val text = values.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
            if (text.isNotEmpty()) {
                emit(
                    "partial",
                    currentSessionId,
                    mapOf("text" to text, "alternates" to values)
                )
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun speechErrorMessage(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "تعذر الوصول إلى الميكروفون."
        SpeechRecognizer.ERROR_CLIENT -> "حدث خطأ في خدمة التعرف الصوتي."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "لم يتم منح صلاحية الميكروفون."
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "اللغة العربية غير مدعومة في خدمة التعرف الحالية."
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "اللغة العربية غير متاحة حالياً في خدمة التعرف."
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "تعذر الاتصال بخدمة التعرف على الكلام."
        SpeechRecognizer.ERROR_NO_MATCH -> "لم يتم التعرف على الكلام."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "خدمة التعرف مشغولة، ستتم إعادة المحاولة تلقائياً."
        SpeechRecognizer.ERROR_SERVER,
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "حدث خطأ في خادم التعرف على الكلام."
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
