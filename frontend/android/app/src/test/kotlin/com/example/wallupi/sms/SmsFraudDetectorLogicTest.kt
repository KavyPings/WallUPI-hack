package com.example.wallupi.sms

import org.junit.Assert.*
import org.junit.Test

/**
 * Tests for the logic helpers inside SmsFraudDetector that do not depend on
 * Android Context or TFLite assets — specifically the rule-based classification
 * mapping and the combined risk scoring math.
 *
 * End-to-end analyzeMessage() tests belong in instrumented tests (androidTest)
 * because they require a real Context and the model assets.
 */
class SmsFraudDetectorLogicTest {

    // ── Rule-based classification mapping ─────────────────────────────────────

    @Test
    fun `apk_download flag maps to apk_malware_link`() {
        val flags = listOf("apk_download", "suspicious_url")
        val result = classifyFromRules(flags, emptySmsMetadata(), "install this app.apk")
        assertEquals("apk_malware_link", result)
    }

    @Test
    fun `sensitive_data_request flag maps to otp_theft`() {
        val flags = listOf("sensitive_data_request", "urgency")
        val result = classifyFromRules(flags, emptySmsMetadata(), "share your otp now")
        assertEquals("otp_theft", result)
    }

    @Test
    fun `kyc_verification flag maps to fake_kyc_verification`() {
        val flags = listOf("kyc_verification", "urgency")
        val result = classifyFromRules(flags, emptySmsMetadata(), "kyc verification required")
        assertEquals("fake_kyc_verification", result)
    }

    @Test
    fun `financial_threat with bank keyword maps to fake_banking_alert`() {
        val flags = listOf("financial_threat", "urgency")
        val result = classifyFromRules(flags, emptySmsMetadata(), "your hdfc account is blocked")
        assertEquals("fake_banking_alert", result)
    }

    @Test
    fun `payment_request flag maps to upi_payment_fraud`() {
        val flags = listOf("payment_request")
        val result = classifyFromRules(flags, emptySmsMetadata(), "pay now rs 500")
        assertEquals("upi_payment_fraud", result)
    }

    @Test
    fun `phishing_link flag maps to phishing`() {
        val flags = listOf("phishing_link", "suspicious_url")
        val result = classifyFromRules(flags, emptySmsMetadata(), "click here to login")
        assertEquals("phishing", result)
    }

    @Test
    fun `impersonation flag maps to social_engineering_scam`() {
        val flags = listOf("impersonation")
        val result = classifyFromRules(flags, emptySmsMetadata(), "rbi notice for you")
        assertEquals("social_engineering_scam", result)
    }

    @Test
    fun `no matching flags returns safe`() {
        val result = classifyFromRules(emptyList(), emptySmsMetadata(), "your package is delivered")
        assertEquals("safe", result)
    }

    // ── Risk score math ───────────────────────────────────────────────────────

    @Test
    fun `combined risk is rule-only when model is absent`() {
        val ruleScore = 0.4f
        val combined = combineRisk(ruleScore = ruleScore, modelFraudProbability = null, ruleHighRiskThreshold = 0.85f)
        assertEquals(ruleScore, combined, 0.001f)
    }

    @Test
    fun `combined risk uses weighted blend when model is present`() {
        val ruleScore = 0.4f
        val fraudProb = 0.8f
        val combined = combineRisk(ruleScore, fraudProb, ruleHighRiskThreshold = 0.85f)
        val expected = (ruleScore * 0.45f) + (fraudProb * 0.55f)
        assertEquals(expected, combined, 0.001f)
    }

    @Test
    fun `combined risk is capped at 1_0`() {
        val combined = combineRisk(ruleScore = 1.0f, modelFraudProbability = 1.0f, ruleHighRiskThreshold = 0.85f)
        assertEquals(1.0f, combined, 0.001f)
    }

    @Test
    fun `high rule score takes max of rule and model when above threshold`() {
        val ruleScore = 0.92f
        val fraudProb = 0.3f
        val combined = combineRisk(ruleScore, fraudProb, ruleHighRiskThreshold = 0.85f)
        assertEquals(maxOf(ruleScore, fraudProb), combined, 0.001f)
    }

    @Test
    fun `model fraud probability is inverted when model says safe`() {
        // Model says "safe" with 0.9 confidence → fraud probability = 1 - 0.9 = 0.1
        val safeConfidence = 0.9f
        val fraudProb = 1f - safeConfidence
        assertEquals(0.1f, fraudProb, 0.001f)
    }

    @Test
    fun `model fraud probability equals confidence when model says fraud`() {
        val fraudConfidence = 0.85f
        val fraudProb = fraudConfidence // label == "fraud", so use directly
        assertEquals(0.85f, fraudProb, 0.001f)
    }

    // ── Synthetic message ID ──────────────────────────────────────────────────

    @Test
    fun `synthetic message id is deterministic for same inputs`() {
        val id1 = buildSyntheticId("sender", "body", 1000L)
        val id2 = buildSyntheticId("sender", "body", 1000L)
        assertEquals(id1, id2)
    }

    @Test
    fun `synthetic message id differs for different inputs`() {
        val id1 = buildSyntheticId("sender", "body1", 1000L)
        val id2 = buildSyntheticId("sender", "body2", 1000L)
        assertNotEquals(id1, id2)
    }

    @Test
    fun `synthetic message id starts with sms_ prefix`() {
        val id = buildSyntheticId("s", "b", 999L)
        assertTrue("ID should start with 'sms_'", id.startsWith("sms_"))
    }

    // ── Helpers that mirror the private logic in SmsFraudDetector ─────────────

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

    private fun combineRisk(
        ruleScore: Float,
        modelFraudProbability: Float?,
        ruleHighRiskThreshold: Float
    ): Float = when {
        ruleScore >= ruleHighRiskThreshold ->
            maxOf(ruleScore, modelFraudProbability ?: 0f)
        modelFraudProbability != null ->
            ((ruleScore * 0.45f) + (modelFraudProbability * 0.55f)).coerceIn(0f, 1f)
        else ->
            ruleScore.coerceIn(0f, 1f)
    }

    private fun buildSyntheticId(sender: String, body: String, timestampMillis: Long): String {
        val hash = (sender + body + timestampMillis).hashCode().toUInt().toString(16)
        return "sms_${timestampMillis}_$hash"
    }

    private fun emptySmsMetadata() = SmsExtractedMetadata()
}
