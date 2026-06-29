package com.example.wallupi.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import com.example.wallupi.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION != intent.action) return

        val pendingResult = goAsync()
        processingScope.launch {
            try {
                val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                if (messages.isEmpty()) return@launch

                val sender = messages.firstOrNull()?.displayOriginatingAddress.orEmpty()
                val body = messages.joinToString(separator = "") { it.messageBody.orEmpty() }
                val timestampMillis = messages.minOfOrNull { it.timestampMillis }
                    ?: System.currentTimeMillis()

                // Reuse a single SmsFraudDetector across calls so the TFLite model
                // is memory-mapped once and not reloaded for every incoming SMS.
                val result = getSharedDetector(context.applicationContext).analyzeMessage(
                    sender = sender,
                    body = body,
                    timestampMillis = timestampMillis,
                    nativeMessageId = null,
                    persistResult = true
                )
                // Warn the user immediately with a heads-up notification — works even
                // when the app is closed and offline, driven by the on-device verdict.
                ScamNotifier.notify(context.applicationContext, result)

                // Push the analyzed result to Flutter immediately if the app is in foreground.
                val resultMap = result.toMap()
                Handler(Looper.getMainLooper()).post {
                    MainActivity.smsEventSink?.success(resultMap)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private val processingScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        @Volatile private var sharedDetector: SmsFraudDetector? = null

        private fun getSharedDetector(appContext: Context): SmsFraudDetector =
            sharedDetector ?: synchronized(SmsReceiver::class.java) {
                sharedDetector ?: SmsFraudDetector(appContext).also { sharedDetector = it }
            }
    }
}
