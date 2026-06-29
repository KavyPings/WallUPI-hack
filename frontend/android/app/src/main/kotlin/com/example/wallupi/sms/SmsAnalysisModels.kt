package com.example.wallupi.sms

data class SmsExtractedMetadata(
    val upiIds: List<String> = emptyList(),
    val phones: List<String> = emptyList(),
    val amounts: List<Double> = emptyList(),
    val urls: List<String> = emptyList(),
    val names: List<String> = emptyList()
) {
    fun toMap(): Map<String, Any> = mapOf(
        "upiIds" to upiIds,
        "phones" to phones,
        "amounts" to amounts,
        "urls" to urls,
        "names" to names
    )
}

data class ModelClassification(
    val label: String,
    val confidence: Float,
    val runnerUpLabel: String?,
    val runnerUpConfidence: Float,
    val confidenceGap: Float
)

data class SmsDetectionResult(
    val messageId: String,
    val nativeMessageId: String?,
    val sender: String,
    val body: String,
    val timestampMillis: Long,
    val localRiskScore: Float,
    val isFlagged: Boolean,
    val flags: List<String>,
    val classification: String,
    val ruleScore: Float,
    val modelConfidence: Float?,
    val modelAvailable: Boolean,
    val analysisSource: String,
    val shouldEscalateToCloud: Boolean,
    val cloudEscalationReason: String?,
    val sanitizedPreview: String?,
    val extractedMetadata: SmsExtractedMetadata,
    val summary: String
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to messageId,
        "nativeMessageId" to nativeMessageId,
        "sender" to sender,
        "body" to body,
        "timestampMillis" to timestampMillis,
        "localRiskScore" to localRiskScore.toDouble(),
        "isFlagged" to isFlagged,
        "flags" to flags,
        "classification" to classification,
        "ruleScore" to ruleScore.toDouble(),
        "modelConfidence" to modelConfidence?.toDouble(),
        "modelAvailable" to modelAvailable,
        "analysisSource" to analysisSource,
        "shouldEscalateToCloud" to shouldEscalateToCloud,
        "cloudEscalationReason" to cloudEscalationReason,
        "sanitizedPreview" to sanitizedPreview,
        "extractedMetadata" to extractedMetadata.toMap(),
        "summary" to summary
    )
}

data class PendingCloudEscalation(
    val messageId: String,
    val sanitizedBody: String,
    val reason: String,
    val classification: String,
    val localRiskScore: Float,
    val createdAtMillis: Long
) {
    fun toMap(): Map<String, Any> = mapOf(
        "messageId" to messageId,
        "sanitizedBody" to sanitizedBody,
        "reason" to reason,
        "classification" to classification,
        "localRiskScore" to localRiskScore.toDouble(),
        "createdAtMillis" to createdAtMillis
    )
}

