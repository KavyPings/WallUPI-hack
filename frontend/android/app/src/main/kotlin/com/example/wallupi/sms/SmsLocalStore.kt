package com.example.wallupi.sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class SmsLocalStore(context: Context) {

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun upsertProcessedMessage(result: SmsDetectionResult) {
        val existing = getProcessedMessages().toMutableList()
        val index = existing.indexOfFirst { message ->
            message.messageId == result.messageId ||
                (!result.nativeMessageId.isNullOrBlank() && result.nativeMessageId == message.nativeMessageId)
        }
        if (index >= 0) {
            existing[index] = result
        } else {
            existing.add(0, result)
        }
        val compact = existing
            .distinctBy { it.nativeMessageId ?: it.messageId }
            .sortedByDescending { it.timestampMillis }
            .take(MAX_STORED_MESSAGES)
        prefs.edit()
            .putString(KEY_PROCESSED_MESSAGES, JSONArray(compact.map { toJson(it) }).toString())
            .apply()
    }

    fun getProcessedMessages(): List<SmsDetectionResult> {
        val raw = prefs.getString(KEY_PROCESSED_MESSAGES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val objectValue = array.optJSONObject(index) ?: continue
                    add(fromJson(objectValue))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun savePendingEscalation(escalation: PendingCloudEscalation) {
        val existing = getPendingEscalations().toMutableList()
        if (existing.none { it.messageId == escalation.messageId }) {
            existing.add(0, escalation)
        }
        prefs.edit()
            .putString(KEY_PENDING_ESCALATIONS, JSONArray(existing.map { toJson(it) }).toString())
            .apply()
    }

    fun getPendingEscalations(): List<PendingCloudEscalation> {
        val raw = prefs.getString(KEY_PENDING_ESCALATIONS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val objectValue = array.optJSONObject(index) ?: continue
                    add(fromEscalationJson(objectValue))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun clearPendingEscalations() {
        prefs.edit().remove(KEY_PENDING_ESCALATIONS).apply()
    }

    fun setLastInboxSync(timestampMillis: Long) {
        prefs.edit().putLong(KEY_LAST_SYNC, timestampMillis).apply()
    }

    fun getLastInboxSync(): Long = prefs.getLong(KEY_LAST_SYNC, 0L)

    private fun toJson(result: SmsDetectionResult): JSONObject = JSONObject().apply {
        put("id", result.messageId)
        put("nativeMessageId", result.nativeMessageId)
        put("sender", result.sender)
        put("body", result.body)
        put("timestampMillis", result.timestampMillis)
        put("localRiskScore", result.localRiskScore.toDouble())
        put("isFlagged", result.isFlagged)
        put("flags", JSONArray(result.flags))
        put("classification", result.classification)
        put("ruleScore", result.ruleScore.toDouble())
        put("modelConfidence", result.modelConfidence?.toDouble())
        put("modelAvailable", result.modelAvailable)
        put("analysisSource", result.analysisSource)
        put("shouldEscalateToCloud", result.shouldEscalateToCloud)
        put("cloudEscalationReason", result.cloudEscalationReason)
        put("sanitizedPreview", result.sanitizedPreview)
        put("summary", result.summary)
        put(
            "extractedMetadata",
            JSONObject().apply {
                put("upiIds", JSONArray(result.extractedMetadata.upiIds))
                put("phones", JSONArray(result.extractedMetadata.phones))
                put("amounts", JSONArray(result.extractedMetadata.amounts))
                put("urls", JSONArray(result.extractedMetadata.urls))
                put("names", JSONArray(result.extractedMetadata.names))
            }
        )
    }

    private fun fromJson(json: JSONObject): SmsDetectionResult {
        val metadataJson = json.optJSONObject("extractedMetadata") ?: JSONObject()
        return SmsDetectionResult(
            messageId = json.optString("id"),
            nativeMessageId = json.optString("nativeMessageId").takeIf { it.isNotBlank() },
            sender = json.optString("sender"),
            body = json.optString("body"),
            timestampMillis = json.optLong("timestampMillis"),
            localRiskScore = json.optDouble("localRiskScore", 0.0).toFloat(),
            isFlagged = json.optBoolean("isFlagged", false),
            flags = json.optJSONArray("flags").toStringList(),
            classification = json.optString("classification", "safe"),
            ruleScore = json.optDouble("ruleScore", 0.0).toFloat(),
            modelConfidence = if (json.has("modelConfidence")) json.optDouble("modelConfidence").toFloat() else null,
            modelAvailable = json.optBoolean("modelAvailable", false),
            analysisSource = json.optString("analysisSource", "android_rule_only"),
            shouldEscalateToCloud = json.optBoolean("shouldEscalateToCloud", false),
            cloudEscalationReason = json.optString("cloudEscalationReason").takeIf { it.isNotBlank() },
            sanitizedPreview = json.optString("sanitizedPreview").takeIf { it.isNotBlank() },
            summary = json.optString("summary", ""),
            extractedMetadata = SmsExtractedMetadata(
                upiIds = metadataJson.optJSONArray("upiIds").toStringList(),
                phones = metadataJson.optJSONArray("phones").toStringList(),
                amounts = metadataJson.optJSONArray("amounts").toDoubleList(),
                urls = metadataJson.optJSONArray("urls").toStringList(),
                names = metadataJson.optJSONArray("names").toStringList()
            )
        )
    }

    private fun toJson(escalation: PendingCloudEscalation): JSONObject = JSONObject().apply {
        put("messageId", escalation.messageId)
        put("sanitizedBody", escalation.sanitizedBody)
        put("reason", escalation.reason)
        put("classification", escalation.classification)
        put("localRiskScore", escalation.localRiskScore.toDouble())
        put("createdAtMillis", escalation.createdAtMillis)
    }

    private fun fromEscalationJson(json: JSONObject): PendingCloudEscalation = PendingCloudEscalation(
        messageId = json.optString("messageId"),
        sanitizedBody = json.optString("sanitizedBody"),
        reason = json.optString("reason"),
        classification = json.optString("classification"),
        localRiskScore = json.optDouble("localRiskScore", 0.0).toFloat(),
        createdAtMillis = json.optLong("createdAtMillis")
    )

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                add(optString(index))
            }
        }
    }

    private fun JSONArray?.toDoubleList(): List<Double> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                add(optDouble(index))
            }
        }
    }

    companion object {
        private const val PREFS_NAME = "wallupi_native_sms"
        private const val KEY_PROCESSED_MESSAGES = "processed_messages"
        private const val KEY_PENDING_ESCALATIONS = "pending_cloud_escalations"
        private const val KEY_LAST_SYNC = "last_inbox_sync"
        private const val MAX_STORED_MESSAGES = 250
    }
}

