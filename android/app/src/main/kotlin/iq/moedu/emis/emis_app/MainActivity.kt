package iq.moedu.emis.emis_app

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "emis.voice/audio"
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var enhancementActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVoiceProcessingCapabilities" -> {
                        result.success(
                            mapOf(
                                "noiseSuppressorAvailable" to NoiseSuppressor.isAvailable(),
                                "acousticEchoCancelerAvailable" to AcousticEchoCanceler.isAvailable(),
                                "modeApplied" to enhancementActive
                            )
                        )
                    }
                    "enableVoiceEnhancement" -> {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (!enhancementActive) {
                            previousAudioMode = audioManager.mode
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            enhancementActive = true
                        }
                        result.success(true)
                    }
                    "disableVoiceEnhancement" -> {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (enhancementActive) {
                            audioManager.mode = previousAudioMode
                            enhancementActive = false
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (enhancementActive) audioManager.mode = previousAudioMode
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
