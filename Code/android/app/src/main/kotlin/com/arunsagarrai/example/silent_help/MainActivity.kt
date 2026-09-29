package com.arunsagarrai.example.silent_help

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Continuous, always-restarting voice wake-word detector for "SilentHelp Emergency".
///
/// Android's SpeechRecognizer is one-shot, so we automatically restart it after
/// every result / error to simulate continuous listening. When the wake phrase
/// is detected we notify Flutter through the method channel (`onWakeWord`).
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "silent_help/speech"
        const val PERMISSION_REQUEST_CODE = 1001
        const val TAG = "SpeechService"
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var methodChannel: MethodChannel? = null
    private var isListening = false
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    if (!checkPermission()) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            PERMISSION_REQUEST_CODE
                        )
                        result.success("PERMISSION_REQUESTED")
                    } else {
                        isListening = true
                        startRecognition()
                        result.success("LISTENING_STARTED")
                    }
                }
                "stopListening" -> {
                    isListening = false
                    stopRecognition()
                    result.success("LISTENING_STOPPED")
                }
                "isAvailable" -> {
                    result.success(SpeechRecognizer.isRecognitionAvailable(this))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startRecognition() {
        if (!isListening) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "Speech recognition not available on this device")
            return
        }

        runOnUiThread {
            try {
                if (speechRecognizer == null) {
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                    speechRecognizer?.setRecognitionListener(recognitionListener)
                }

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                }
                speechRecognizer?.startListening(intent)
            } catch (e: Exception) {
                Log.e(TAG, "startRecognition failed: ${e.message}")
                scheduleRestart()
            }
        }
    }

    private fun stopRecognition() {
        handler.removeCallbacksAndMessages(null)
        runOnUiThread {
            try {
                speechRecognizer?.stopListening()
                speechRecognizer?.cancel()
                speechRecognizer?.destroy()
            } catch (_: Exception) {
            } finally {
                speechRecognizer = null
            }
        }
    }

    /// Restart after a short delay so we keep listening continuously.
    private fun scheduleRestart() {
        if (!isListening) return
        handler.postDelayed({ startRecognition() }, 600)
    }

    private fun handleMatches(matches: List<String>?) {
        if (matches.isNullOrEmpty()) return
        for (phrase in matches) {
            val lower = phrase.lowercase()
            val hasName = lower.contains("silent help") ||
                lower.contains("silenthelp") ||
                lower.contains("silent") && lower.contains("help")
            val hasIntent = lower.contains("emergency") ||
                lower.contains("sos") ||
                lower.contains("help me") ||
                lower.contains("save me")
            if (hasName && hasIntent) {
                Log.d(TAG, "Wake phrase detected: $phrase")
                methodChannel?.invokeMethod("onWakeWord", phrase)
                return
            }
        }
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onResults(results: Bundle?) {
            handleMatches(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
            scheduleRestart()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            handleMatches(partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
        }

        override fun onError(error: Int) {
            // Errors are normal (e.g. no speech). Just restart.
            scheduleRestart()
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                isListening = true
                startRecognition()
                methodChannel?.invokeMethod("onPermissionGranted", null)
            } else {
                methodChannel?.invokeMethod("onPermissionDenied", null)
            }
        }
    }

    private fun checkPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onDestroy() {
        isListening = false
        stopRecognition()
        super.onDestroy()
    }
}
