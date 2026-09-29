package com.arunsagarrai.example.silent_help

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.telephony.SmsManager
import android.util.Log
import org.json.JSONArray

/**
 * Background voice-trigger SOS service.
 *
 * Runs as a foreground service (microphone type) so it keeps listening while
 * the app is minimized or the screen is off. It continuously runs Android's
 * SpeechRecognizer in a self-restarting loop, matches the user's configured
 * trigger phrase, and — on a match — sends SMS DIRECTLY from native code using
 * SmsManager. Sending natively is the fastest path and does not require the
 * Flutter engine to be alive.
 *
 * All configuration (phrase, contacts, message) is read from the SAME
 * SharedPreferences the Flutter app writes to (keys are prefixed "flutter.").
 */
class VoiceSosService : Service() {

    companion object {
        const val CHANNEL_ID = "silent_help_voice"
        const val NOTIF_ID = 8422
        const val TAG = "VoiceSosService"

        // Dedicated config prefs written by MainActivity (format-independent,
        // does not rely on shared_preferences internal encoding).
        const val CONFIG_PREFS = "silent_help_voice_config"
        const val CFG_PHRASE = "phrase"
        const val CFG_CONTACTS = "contactsJson"
        const val CFG_MESSAGE = "message"
        const val CFG_LAST_TRIGGER = "lastTriggerMs"

        const val DEFAULT_PHRASE = "silent help emergency"
        const val COOLDOWN_MS = 60_000L
    }

    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var muted = false
    private val handler = Handler(Looper.getMainLooper())

    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startAsForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!running) {
            running = true
            muteBeep()
            startRecognition()
        }
        // START_STICKY: the OS restarts the service if it is killed.
        return START_STICKY
    }

    private fun startAsForeground() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Voice monitoring",
            NotificationManager.IMPORTANCE_LOW
        ).apply { setSound(null, null) }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Calculator")
            .setContentText("Running")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ---- beep suppression ----
    @Suppress("DEPRECATION")
    private fun muteBeep() {
        if (muted) return
        muted = true
        try {
            intArrayOf(
                AudioManager.STREAM_SYSTEM,
                AudioManager.STREAM_NOTIFICATION,
                AudioManager.STREAM_MUSIC
            ).forEach {
                audioManager.adjustStreamVolume(it, AudioManager.ADJUST_MUTE, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "muteBeep: ${e.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun unmuteBeep() {
        if (!muted) return
        muted = false
        try {
            intArrayOf(
                AudioManager.STREAM_SYSTEM,
                AudioManager.STREAM_NOTIFICATION,
                AudioManager.STREAM_MUSIC
            ).forEach {
                audioManager.adjustStreamVolume(it, AudioManager.ADJUST_UNMUTE, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "unmuteBeep: ${e.message}")
        }
    }

    // ---- recognition loop ----
    private fun startRecognition() {
        if (!running) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "Recognition not available")
            return
        }
        handler.post {
            try {
                if (recognizer == null) {
                    recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                    recognizer?.setRecognitionListener(listener)
                }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    }
                }
                recognizer?.startListening(intent)
            } catch (e: Exception) {
                Log.e(TAG, "startRecognition: ${e.message}")
                scheduleRestart()
            }
        }
    }

    private fun scheduleRestart() {
        if (!running) return
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
            }
            startRecognition()
        }, 300)
    }

    private val listener = object : RecognitionListener {
        override fun onResults(results: Bundle?) {
            handleMatches(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
            scheduleRestart()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            handleMatches(partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION))
        }

        override fun onError(error: Int) {
            scheduleRestart()
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun handleMatches(matches: List<String>?) {
        if (matches.isNullOrEmpty()) return
        val phrase = readPhrase()
        val words = phrase.split(Regex("\\s+")).filter { it.isNotBlank() }
        if (words.isEmpty()) return
        for (m in matches) {
            val spoken = m.lowercase().replace(Regex("[^a-z0-9 ]"), " ")
            if (words.all { spoken.contains(it) }) {
                Log.d(TAG, "Voice trigger matched")
                triggerSos()
                return
            }
        }
    }

    private fun config() = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)

    // ---- SOS ----
    private fun triggerSos() {
        val prefs = config()

        // Cooldown.
        val last = prefs.getLong(CFG_LAST_TRIGGER, 0L)
        val now = System.currentTimeMillis()
        if (now - last < COOLDOWN_MS) {
            Log.d(TAG, "Cooldown active; skipping")
            return
        }
        prefs.edit().putLong(CFG_LAST_TRIGGER, now).apply()

        val numbers = readContacts()
        if (numbers.isEmpty()) {
            Log.w(TAG, "No trusted contacts")
            return
        }
        val message = buildMessage()
        sendSms(numbers, message)
    }

    private fun buildMessage(): String {
        val base = config().getString(CFG_MESSAGE, null)
            ?: "Emergency! I need help. This is an automated message from SilentHelp."
        // Location is best-effort; native quick path sends without a fix to be
        // fast. The Flutter path still records full history with location.
        return "$base\nTriggered by: Voice SOS"
    }

    private fun sendSms(numbers: List<String>, message: String) {
        try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            for (number in numbers) {
                try {
                    val parts = sms.divideMessage(message)
                    if (parts.size > 1) {
                        sms.sendMultipartTextMessage(number, null, parts, null, null)
                    } else {
                        sms.sendTextMessage(number, null, message, null, null)
                    }
                    Log.d(TAG, "SMS dispatched")
                } catch (e: Exception) {
                    Log.e(TAG, "sendSms one failed: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "sendSms failed: ${e.message}")
        }
    }

    // ---- config readers ----
    private fun readPhrase(): String {
        return (config().getString(CFG_PHRASE, null) ?: DEFAULT_PHRASE).lowercase()
    }

    private fun readContacts(): List<String> {
        val raw = config().getString(CFG_CONTACTS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                arr.getJSONObject(i).optString("phoneNumber").takeIf { it.isNotBlank() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "readContacts: ${e.message}")
            emptyList()
        }
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
        unmuteBeep()
        super.onDestroy()
    }
}
