package com.example.wallupi.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.content.ContextCompat

class NativeSmsRepository(private val context: Context) {

    private val detector by lazy { SmsFraudDetector(context) }
    private val store by lazy { SmsLocalStore(context) }

    fun hasSmsPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    }

    fun analyzeManualMessage(sender: String, body: String, persistResult: Boolean): SmsDetectionResult {
        return detector.analyzeMessage(
            sender = sender,
            body = body,
            timestampMillis = System.currentTimeMillis(),
            nativeMessageId = null,
            persistResult = persistResult
        )
    }

    fun syncInbox(limit: Int): List<SmsDetectionResult> {
        if (!hasSmsPermissions()) return emptyList()

        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )

        val results = mutableListOf<SmsDetectionResult>()
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            null,
            null,
            Telephony.Sms.DEFAULT_SORT_ORDER
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addressIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

            var count = 0
            while (cursor.moveToNext() && count < limit) {
                val nativeId = cursor.getString(idIndex)
                val sender = cursor.getString(addressIndex).orEmpty()
                val body = cursor.getString(bodyIndex).orEmpty()
                val timestampMillis = cursor.getLong(dateIndex)
                results += detector.analyzeMessage(
                    sender = sender,
                    body = body,
                    timestampMillis = timestampMillis,
                    nativeMessageId = nativeId,
                    persistResult = true
                )
                count += 1
            }
        }

        store.setLastInboxSync(System.currentTimeMillis())
        return results.sortedByDescending { it.timestampMillis }
    }

    fun getProcessedMessages(limit: Int): List<SmsDetectionResult> {
        return store.getProcessedMessages()
            .sortedByDescending { it.timestampMillis }
            .take(limit)
    }

    fun getPendingCloudEscalations(): List<Map<String, Any>> {
        return store.getPendingEscalations().map { it.toMap() }
    }

    fun clearPendingCloudEscalations() {
        store.clearPendingEscalations()
    }

    fun getDetectorStatus(): Map<String, Any?> {
        return detector.getDetectorStatus() + mapOf(
            "hasSmsPermissions" to hasSmsPermissions()
        )
    }
}

