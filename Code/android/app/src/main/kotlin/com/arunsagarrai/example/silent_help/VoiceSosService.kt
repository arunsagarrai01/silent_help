package com.arunsagarrai.example.silent_help

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
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
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Background voice-trigger SOS service.
 *
 * Runs as a foreground service (microphone type) so it keeps listening while
 * the app is minimized or the screen is off. It continuously runs Android's
 * SpeechRecognizer in a self-restarting loop, matches the user's configured
 * trigger phrase (fuzzily, to tolerate mishearings), and — on a match — sends
 * SMS DIRECTLY from native code using SmsManager. Sending natively is the
 * fastest path and does not require the Flutter engine to be alive.
 *
 * Config (phrase, contacts, message) is read from a dedicated prefs file
 * written by MainActivity, so it never depends on shared_preferences' internal
 * encoding.
 */
class VoiceSosService : Service() {

    companion object {
        const val CHANNEL_ID = "silent_help_voice"
        const val NOTIF_ID = 8422
        const val TAG = "VoiceSosService"

        const val CONFIG_PREFS = "silent_help_voice_config"
        const val CFG_PHRASE = "phrase"
        const val CFG_CONTACTS = "contactsJson"
        const val CFG_MESSAGE = "message"
        const val CFG_LAST_TRIGGER = "lastTriggerMs"

        const val DEFAULT_PHRASE = "silent help emergency"
        const val COOLDOWN_MS = 60_000L

        // After a successful match we pause recognition briefly, then resume so
        // the trigger keeps working for the next incident.
        const val POST_TRIGGER_RESUME_MS = 2_000L
    }

    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var muted = false

    // Guards against the same utterance firing SOS more than once (partial +
    // final results, or rapid repeats). Reset when we resume listening.
    private var triggeredThisUtterance = false

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
        return START_STICKY
    }

    // ---- foreground notification (silent) ----
    private fun startAsForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Voice monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

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
            .setOnlyAlertOnce(true)
            .setSound(null)
            .setVibrate(null)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    // ---- beep suppression ----
    //
    // The SpeechRecognizer start/stop "beep" plays through the SYSTEM /
    // NOTIFICATION streams (ToneGenerator). We mute THOSE continuously while the
    // service runs — they never carry the user's media, so this is safe and
    // does not affect music/alarms. (Muting STREAM_MUSIC would silence the
    // user's media the whole time, which we deliberately avoid.)
    private val mutedStreams = intArrayOf(
        AudioManager.STREAM_SYSTEM,
        AudioManager.STREAM_NOTIFICATION
    )

    private fun muteBeep() {
        if (muted) return
        muted = true
        for (s in mutedStreams) {
            try {
                audioManager.adjustStreamVolume(s, AudioManager.ADJUST_MUTE, 0)
            } catch (e: Exception) {
                Log.w(TAG, "muteBeep($s): ${e.message}")
            }
        }
    }

    private fun unmuteBeep() {
        if (!muted) return
        muted = false
        for (s in mutedStreams) {
            try {
                audioManager.adjustStreamVolume(s, AudioManager.ADJUST_UNMUTE, 0)
            } catch (e: Exception) {
                Log.w(TAG, "unmuteBeep($s): ${e.message}")
            }
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
            if (!running) return@post
            // A fresh utterance begins: allow one trigger again.
            triggeredThisUtterance = false
            try {
                if (recognizer == null) {
                    recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                    recognizer?.setRecognitionListener(listener)
                }
                // Always cancel any pending session first to avoid BUSY.
                try {
                    recognizer?.cancel()
                } catch (_: Exception) {
                }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                    // Do NOT force offline — missing packs break recognition.
                }
                recognizer?.startListening(intent)
            } catch (e: Exception) {
                Log.e(TAG, "startRecognition: ${e.message}")
                scheduleRestart(600)
            }
        }
    }

    private fun scheduleRestart(delayMs: Long = 400) {
        if (!running) return
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ startRecognition() }, delayMs)
    }

    /** Fully recreate the recognizer (needed after fatal CLIENT/BUSY errors). */
    private fun recreateRecognizer() {
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    private val listener = object : RecognitionListener {
        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            Log.d(TAG, "onResults=$matches")
            val fired = handleMatches(matches)
            // Always resume listening so the trigger keeps working repeatedly.
            scheduleRestart(if (fired) POST_TRIGGER_RESUME_MS else 400)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            // Fast path: react to partials too, but the per-utterance guard
            // prevents a double fire with onResults.
            handleMatches(
                partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            )
        }

        override fun onError(error: Int) {
            when (error) {
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                    recreateRecognizer()
                    scheduleRestart(700)
                }
                else -> scheduleRestart(400) // NO_MATCH / timeout = normal
            }
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    /** Returns true if a trigger fired. */
    private fun handleMatches(matches: List<String>?): Boolean {
        if (matches.isNullOrEmpty()) return false
        if (triggeredThisUtterance) return false

        val phraseWords = readPhrase()
            .split(Regex("\\s+")).filter { it.isNotBlank() }
        if (phraseWords.isEmpty()) return false

        for (m in matches) {
            if (isFuzzyMatch(m, phraseWords)) {
                Log.d(TAG, "Voice trigger matched on: '$m'")
                triggeredThisUtterance = true
                triggerSos()
                return true
            }
        }
        return false
    }

    /**
     * Forgiving wake-phrase match: trigger when >= 60% of phrase words match
     * (fuzzily) AND the last/most distinctive word matches. Tolerates common
     * mishearings like "silent help" -> "Silent Hill".
     */
    private fun isFuzzyMatch(spokenRaw: String, phraseWords: List<String>): Boolean {
        val spoken = spokenRaw.lowercase().replace(Regex("[^a-z0-9 ]"), " ")
        val spokenWords = spoken.split(Regex("\\s+")).filter { it.isNotBlank() }
        if (spokenWords.isEmpty()) return false

        var matched = 0
        for (pw in phraseWords) {
            if (spokenWords.any { sw -> wordsSimilar(pw, sw) }) matched++
        }
        val ratio = matched.toDouble() / phraseWords.size
        val keyPresent = spokenWords.any { sw -> wordsSimilar(phraseWords.last(), sw) }
        return keyPresent && ratio >= 0.6
    }

    private fun wordsSimilar(a: String, b: String): Boolean {
        if (a == b) return true
        if (a.length >= 3 && b.length >= 3 && (a.contains(b) || b.contains(a))) return true
        val dist = levenshtein(a, b)
        val maxLen = maxOf(a.length, b.length)
        if (maxLen == 0) return false
        return dist.toDouble() / maxLen <= 0.4
    }

    private fun levenshtein(a: String, b: String): Int {
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val temp = dp[j]
                dp[j] = minOf(
                    dp[j] + 1,
                    dp[j - 1] + 1,
                    prev + if (a[i - 1] == b[j - 1]) 0 else 1
                )
                prev = temp
            }
        }
        return dp[b.length]
    }

    private fun config() = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)

    // ---- SOS ----
    private fun triggerSos() {
        val prefs = config()
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
        sendSms(numbers, buildMessage())
    }

    private fun buildMessage(): String {
        val base = config().getString(CFG_MESSAGE, null)
            ?: "Emergency! I need help. This is an automated message from SilentHelp."

        val sb = StringBuilder(base)

        // Time.
        val time = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
            .format(Date())
        sb.append("\nTime: ").append(time)

        // Location (last-known, instant — never delays the SMS).
        val loc = lastKnownLocation()
        if (loc != null) {
            sb.append("\nLocation: https://maps.google.com/?q=")
                .append(loc.latitude).append(",").append(loc.longitude)
        } else {
            sb.append("\nLocation: unavailable")
        }

        sb.append("\nTriggered by: Voice SOS")
        return sb.toString()
    }

    /** Fast, non-blocking last-known location from GPS or network provider. */
    private fun lastKnownLocation(): Location? {
        val fineOk = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarseOk = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!fineOk && !coarseOk) return null

        return try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providers = listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER
            )
            var best: Location? = null
            for (p in providers) {
                val l = try {
                    lm.getLastKnownLocation(p)
                } catch (_: SecurityException) {
                    null
                }
                if (l != null && (best == null || l.time > best!!.time)) best = l
            }
            best
        } catch (e: Exception) {
            Log.w(TAG, "lastKnownLocation: ${e.message}")
            null
        }
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun sendSms(numbers: List<String>, message: String) {
        if (!hasSmsPermission()) {
            Log.e(TAG, "SEND_SMS permission NOT granted — cannot send voice SOS")
            return
        }
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
