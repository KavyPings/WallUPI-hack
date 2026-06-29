package com.example.wallupi.sms

import android.content.Context

class SmsFraudDetector(private val context: Context) {

    private val classifier by lazy { TinyBertTFLiteClassifier(context) }
    private val store by lazy { SmsLocalStore(context) }

    fun analyzeMessage(
        sender: String,
        body: String,
        timestampMillis: Long,
        nativeMessageId: String? = null,
        persistResult: Boolean = true
    ): SmsDetectionResult {
        val ruleResult = RuleEngine.analyze(sender, body)
        val extractedMetadata = SmsSignalExtractor.extract(body)
        val config = classifier.classifierConfig

        val ruleHighRiskThreshold = config?.ruleHighRiskThreshold ?: 0.85f
        val flaggedRiskThreshold = config?.flaggedRiskThreshold ?: 0.45f
        val lowConfidenceThreshold = config?.lowConfidenceThreshold ?: 0.62f
        val uncertainGapThreshold = config?.uncertainGapThreshold ?: 0.18f
        val cloudEscalationMinRisk = config?.cloudEscalationMinRisk ?: 0.55f

        val shouldRunModel = ruleResult.shouldEscalateToML && classifier.modelAvailable
        val modelResult = if (shouldRunModel) classifier.classify(body) else null

        // For the binary model, derive a fraud probability from the classification result.
        // - label="fraud": fraudProbability = confidence
        // - label="safe":  fraudProbability = 1 - confidence (inverted)
        // This ensures the combined risk score correctly reflects the fraud signal.
        val modelFraudProbability: Float? = modelResult?.let { m ->
            if (m.label == "fraud") m.confidence else 1f - m.confidence
        }

        val classificationFromRules = classifyFromRules(ruleResult.flags, extractedMetadata, body)
        val modelIndicatesFraud = modelResult != null &&
            modelResult.label == "fraud" &&
            modelResult.confidence >= lowConfidenceThreshold

        // Classification priority:
        // 1. High-confidence rule hit → detailed rule label
        // 2. Model says fraud + rule also sees fraud → rule's detailed label
        // 3. Model says fraud confidently, rules see safe → generic fraud label
        // 4. Rules have a non-safe signal → rule label
        // 5. Fallback → safe
        val finalClassification = when {
            ruleResult.score >= ruleHighRiskThreshold && classificationFromRules != "safe" ->
                classificationFromRules
            modelIndicatesFraud && classificationFromRules != "safe" ->
                classificationFromRules
            modelIndicatesFraud ->
                "social_engineering_scam"
            classificationFromRules != "safe" ->
                classificationFromRules
            // Safety net: high rule score but no specific category matched — avoid silent "safe"
            ruleResult.score >= flaggedRiskThreshold ->
                "social_engineering_scam"
            else -> "safe"
        }

        // TinyBERT is an additive signal only — it can push the score higher when it
        // detects fraud, but it cannot pull the score below what the rule engine already
        // established from hard evidence (keywords, URL patterns). This prevents the model
        // from overriding concrete rule hits by calling ambiguous scam text "safe".
        val combinedRisk = when {
            ruleResult.score >= ruleHighRiskThreshold ->
                maxOf(ruleResult.score, modelFraudProbability ?: 0f)
            modelFraudProbability != null ->
                maxOf(ruleResult.score, (ruleResult.score * 0.45f) + (modelFraudProbability * 0.55f))
                    .coerceIn(0f, 1f)
            else ->
                ruleResult.score.coerceIn(0f, 1f)
        }

        val uncertainModel = modelResult != null &&
            (modelResult.confidence < lowConfidenceThreshold || modelResult.confidenceGap < uncertainGapThreshold)

        // TinyBERT contradicts the rule engine: rules flag ≥45% risk but model is
        // confidently calling it safe. Given TinyBERT's known bias toward "safe" on
        // Indian SMS scam patterns, this disagreement is itself a signal of uncertainty.
        val modelDisagreesWithRules = modelResult != null &&
            modelResult.label == "safe" &&
            modelResult.confidence >= 0.80f &&
            ruleResult.score >= 0.45f

        val suspiciousButUncertain = combinedRisk >= cloudEscalationMinRisk &&
            (uncertainModel || modelDisagreesWithRules || (modelResult == null && ruleResult.shouldEscalateToML))

        // Hard signals are concrete evidence of fraud intent (hidden/shortened
        // link, malware APK, sensitive-data ask, money request, spoofed domain,
        // stock-tip blast). When one is present and the message is not clearly
        // safe, ALWAYS get the cloud LLM's verdict — TinyBERT's "safe" guess must
        // never be allowed to bury a hard signal and block escalation.
        val hardSignalFlags = setOf(
            "apk_download", "suspicious_url", "suspicious_domain", "shortened_link",
            "phishing_link", "sensitive_data_request", "payment_request", "investment_scam"
        )
        val hasHardSignal = ruleResult.flags.any { it in hardSignalFlags }
        val hardSignalEscalation = hasHardSignal &&
            finalClassification != "safe" &&
            combinedRisk >= flaggedRiskThreshold

        val shouldEscalateToCloud = suspiciousButUncertain || hardSignalEscalation
        val escalationReason = when {
            !shouldEscalateToCloud -> null
            hardSignalEscalation && !suspiciousButUncertain ->
                "Hard fraud signal (${ruleResult.flags.firstOrNull { it in hardSignalFlags }}) present; escalating for cloud review"
            modelResult == null && classifier.modelAvailable ->
                "Model output unavailable for suspicious SMS"
            modelResult == null ->
                "Local TinyBERT asset missing; escalation queued as fallback"
            modelDisagreesWithRules ->
                "Rule engine (${(ruleResult.score * 100).toInt()}% risk) contradicts local model (safe ${(modelResult!!.confidence * 100).toInt()}%); escalating for cloud review"
            modelResult.confidence < lowConfidenceThreshold ->
                "Local model confidence below threshold (${modelResult.confidence})"
            modelResult.confidenceGap < uncertainGapThreshold ->
                "Local model uncertain: confidence gap ${modelResult.confidenceGap} < $uncertainGapThreshold"
            else -> "Suspicious message queued for cloud review"
        }

        val sanitizedPreview = if (shouldEscalateToCloud) SanitizationEngine.sanitize(body) else null
        val analysisSource = if (modelResult != null) "android_rule_tinybert" else "android_rule_only"
        val summary = buildSummary(finalClassification, combinedRisk, ruleResult.flags, modelResult != null)
        val messageId = nativeMessageId ?: buildSyntheticMessageId(sender, body, timestampMillis)

        val result = SmsDetectionResult(
            messageId = messageId,
            nativeMessageId = nativeMessageId,
            sender = sender,
            body = body,
            timestampMillis = timestampMillis,
            localRiskScore = combinedRisk,
            isFlagged = combinedRisk >= flaggedRiskThreshold || finalClassification != "safe",
            flags = ruleResult.flags.distinct(),
            classification = finalClassification,
            ruleScore = ruleResult.score,
            modelConfidence = modelResult?.confidence,
            modelAvailable = classifier.modelAvailable,
            analysisSource = analysisSource,
            shouldEscalateToCloud = shouldEscalateToCloud,
            cloudEscalationReason = escalationReason,
            sanitizedPreview = sanitizedPreview,
            extractedMetadata = extractedMetadata,
            summary = summary
        )

        if (persistResult) {
            store.upsertProcessedMessage(result)
            if (shouldEscalateToCloud && sanitizedPreview != null && escalationReason != null) {
                store.savePendingEscalation(
                    PendingCloudEscalation(
                        messageId = result.messageId,
                        sanitizedBody = sanitizedPreview,
                        reason = escalationReason,
                        classification = result.classification,
                        localRiskScore = result.localRiskScore,
                        createdAtMillis = System.currentTimeMillis()
                    )
                )
            }
        }

        return result
    }

    fun getDetectorStatus(): Map<String, Any?> {
        val config = classifier.classifierConfig
        val localStore = SmsLocalStore(context)
        return mapOf(
            "modelAvailable" to classifier.modelAvailable,
            "vocabAvailable" to classifier.vocabAvailable,
            "ruleEngineAvailable" to true,
            "cloudConfigured" to false,
            "pendingCloudEscalations" to localStore.getPendingEscalations().size,
            "lastInboxSyncMillis" to localStore.getLastInboxSync(),
            "configuredLabels" to (config?.labels ?: emptyList<String>()),
            "maxSeqLength" to (config?.maxSeqLength ?: 0),
            "ruleOnlyFallbackActive" to !classifier.modelAvailable
        )
    }

    private fun classifyFromRules(
        flags: List<String>,
        metadata: SmsExtractedMetadata,
        body: String
    ): String {
        val lowerBody = body.lowercase()
        val suspiciousPaymentContext = "payment_request" in flags ||
            "phishing_link" in flags ||
            "suspicious_url" in flags ||
            "suspicious_domain" in flags ||
            "urgency" in flags
        return when {
            "apk_download" in flags -> "apk_malware_link"
            "investment_scam" in flags -> "investment_advisory_fraud"
            "sensitive_data_request" in flags -> "otp_theft"
            "kyc_verification" in flags -> "fake_kyc_verification"
            "financial_threat" in flags &&
                (lowerBody.contains("bank") || lowerBody.contains("account") ||
                    lowerBody.contains("sbi") || lowerBody.contains("hdfc") ||
                    lowerBody.contains("icici")) -> "fake_banking_alert"
            "payment_request" in flags ||
                (metadata.upiIds.isNotEmpty() && suspiciousPaymentContext) -> "upi_payment_fraud"
            "phishing_link" in flags || "suspicious_url" in flags ||
                "suspicious_domain" in flags || "shortened_link" in flags -> "phishing"
            "impersonation" in flags || "urgency" in flags ||
                "prize_scam" in flags -> "social_engineering_scam"
            else -> "safe"
        }
    }

    private fun buildSummary(
        classification: String,
        riskScore: Float,
        flags: List<String>,
        usedModel: Boolean
    ): String {
        val mode = if (usedModel) "Rule Engine + TinyBERT" else "Rule Engine"
        val prettyClassification = classification.replace('_', ' ')
        val topFlags = flags.take(3).joinToString(", ")
        return "$mode classified this SMS as $prettyClassification with " +
            "${(riskScore * 100).toInt()}% local risk" +
            if (topFlags.isNotBlank()) " based on $topFlags." else "."
    }

    private fun buildSyntheticMessageId(sender: String, body: String, timestampMillis: Long): String {
        val hash = (sender + body + timestampMillis).hashCode().toUInt().toString(16)
        return "sms_${timestampMillis}_$hash"
    }
}
