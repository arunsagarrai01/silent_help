package com.arunsagarrai.example.silent_help

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter <-> the native background voice service.
 *
 * Voice recognition itself runs in [VoiceSosService] (a foreground service),
 * so it keeps working in the background / screen off, exactly like shake
 * detection. This activity only starts/stops that service and handles the
 * RECORD_AUDIO runtime permission.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "silent_help/speech"
        const val PERMISSION_REQUEST_CODE = 1001
    }

    private var methodChannel: MethodChannel? = null
    private var pendingStart = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVoiceService" -> {
                    // Persist config passed from Dart into VoiceSosService's own
                    // prefs file so it never depends on shared_preferences format.
                    saveConfig(
                        call.argument<String>("phrase"),
                        call.argument<String>("contactsJson"),
                        call.argument<String>("message"),
                    )
                    if (!hasMicPermission()) {
                        pendingStart = true
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            PERMISSION_REQUEST_CODE
                        )
                        result.success("PERMISSION_REQUESTED")
                    } else {
                        startVoiceService()
                        result.success("STARTED")
                    }
                }
                "updateVoiceConfig" -> {
                    saveConfig(
                        call.argument<String>("phrase"),
                        call.argument<String>("contactsJson"),
                        call.argument<String>("message"),
                    )
                    result.success(true)
                }
                "stopVoiceService" -> {
                    stopVoiceService()
                    result.success("STOPPED")
                }
                "isVoiceServiceAvailable" -> {
                    result.success(SpeechRecognizer.isRecognitionAvailable(this))
                }
                "hasMicPermission" -> {
                    result.success(hasMicPermission())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveConfig(phrase: String?, contactsJson: String?, message: String?) {
        val prefs = getSharedPreferences(VoiceSosService.CONFIG_PREFS, MODE_PRIVATE)
        val edit = prefs.edit()
        if (!phrase.isNullOrBlank()) edit.putString(VoiceSosService.CFG_PHRASE, phrase.lowercase())
        if (contactsJson != null) edit.putString(VoiceSosService.CFG_CONTACTS, contactsJson)
        if (message != null) edit.putString(VoiceSosService.CFG_MESSAGE, message)
        edit.apply()
    }

    private fun startVoiceService() {
        val intent = Intent(this, VoiceSosService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVoiceService() {
        stopService(Intent(this, VoiceSosService::class.java))
    }

    private fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && pendingStart) {
                startVoiceService()
                methodChannel?.invokeMethod("onPermissionGranted", null)
            } else if (!granted) {
                methodChannel?.invokeMethod("onPermissionDenied", null)
            }
            pendingStart = false
        }
    }
}
