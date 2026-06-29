package com.example.wallupi.sms

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for [TinyBertTFLiteClassifier] and [SmsFraudDetector].
 *
 * These run on a real Android device or emulator and require the model assets
 * (tinybert_sms_classifier.tflite, tinybert_vocab.txt) to be present in assets/ml/.
 *
 * Run with:  ./gradlew connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class TinyBertClassifierInstrumentedTest {

    private lateinit var classifier: TinyBertTFLiteClassifier
    private lateinit var detector: SmsFraudDetector

    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        classifier = TinyBertTFLiteClassifier(context)
        detector = SmsFraudDetector(context)
    }

    @After
    fun tearDown() {
        classifier.close()
    }

    // ── Model loading ─────────────────────────────────────────────────────────

    @Test
    fun classifierConfig_isLoadedFromAssets() {
        val config = classifier.classifierConfig
        assertNotNull("Config should load from assets/ml/sms_tinybert_config.json", config)
        assertEquals(128, config!!.maxSeqLength)
        assertTrue("Config must define at least 2 labels", config.labels.size >= 2)
        assertTrue("Labels must include 'safe'", "safe" in config.labels)
    }

    @Test
    fun modelAndVocab_areAvailableWhenAssetsPresent() {
        assertTrue("Vocab should load from tinybert_vocab.txt", classifier.vocabAvailable)
        assertTrue("Model should load from tinybert_sms_classifier.tflite", classifier.modelAvailable)
    }

    // ── Inference sanity checks ───────────────────────────────────────────────

    @Test
    fun classify_safeMessage_returnsSafeOrLowFraudConfidence() {
        if (!classifier.modelAvailable) return // skip if assets missing

        val result = classifier.classify(
            "Your Amazon order #123-456789 will be delivered tomorrow between 10am and 2pm."
        )
        assertNotNull("classify() must return a result for valid input", result)
        checkNotNull(result)
        assertEquals("Expected binary label 'safe'", "safe", result.label)
        assertTrue("Confidence must be in [0, 1]", result.confidence in 0f..1f)
    }

    @Test
    fun classify_obviousFraudMessage_returnsFraudOrHighRisk() {
        if (!classifier.modelAvailable) return

        val result = classifier.classify(
            "URGENT! Your SBI account will be BLOCKED. Share your OTP immediately to KYC verify at http://sbi.secure.xyz/verify"
        )
        assertNotNull(result)
        checkNotNull(result)
        assertTrue(
            "Model should indicate fraud for obvious scam; got label=${result.label} confidence=${result.confidence}",
            result.label == "fraud" || result.confidence > 0.3f
        )
    }

    @Test
    fun classify_outputsConfidenceInValidRange() {
        if (!classifier.modelAvailable) return

        val result = classifier.classify("Hello, your package is ready for pickup.")
        assertNotNull(result)
        checkNotNull(result)
        assertTrue("confidence must be in [0,1]", result.confidence in 0f..1f)
        assertTrue("runnerUpConfidence must be in [0,1]", result.runnerUpConfidence in 0f..1f)
        assertTrue("confidenceGap must be non-negative", result.confidenceGap >= 0f)
    }

    @Test
    fun classify_returnsNullGracefullyWhenModelMissing() {
        // Verified indirectly: if modelAvailable is false, classify returns null.
        if (classifier.modelAvailable) {
            // Model is present — just confirm classify doesn't crash
            val r = classifier.classify("test")
            // Result may be null or non-null; we just ensure no exception was thrown
        } else {
            val result = classifier.classify("test")
            assertNull("Should return null when model is unavailable", result)
        }
    }

    // ── Full detector pipeline ────────────────────────────────────────────────

    @Test
    fun analyzeMessage_safeMessage_producesLowRiskAndSafeClassification() {
        val result = detector.analyzeMessage(
            sender = "DM-AMZN",
            body = "Your package has been dispatched and will arrive tomorrow.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertFalse("Safe message should not be flagged", result.isFlagged)
        assertTrue("Risk score should be low for safe message", result.localRiskScore < 0.5f)
    }

    @Test
    fun analyzeMessage_obviousScam_isFlagged() {
        val result = detector.analyzeMessage(
            sender = "9876543210",
            body = "URGENT: Share your OTP now. Your account will be blocked if you don't verify KYC immediately.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("Obvious scam should be flagged", result.isFlagged)
        assertTrue("Risk score should be high", result.localRiskScore >= 0.45f)
    }

    @Test
    fun analyzeMessage_setsAnalysisSource_correctly() {
        val result = detector.analyzeMessage(
            sender = "VM-BANK",
            body = "Your balance is Rs 5,000. Have a nice day.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        val validSources = listOf("android_rule_only", "android_rule_tinybert")
        assertTrue(
            "analysisSource must be one of $validSources, got: ${result.analysisSource}",
            result.analysisSource in validSources
        )
    }

    @Test
    fun analyzeMessage_alwaysReturnsNonEmptyMessageId() {
        val result = detector.analyzeMessage(
            sender = "TEST",
            body = "test body",
            timestampMillis = 1000L,
            persistResult = false
        )
        assertTrue("messageId must be non-empty", result.messageId.isNotBlank())
    }

    @Test
    fun getDetectorStatus_containsRequiredKeys() {
        val status = detector.getDetectorStatus()
        assertTrue(status.containsKey("modelAvailable"))
        assertTrue(status.containsKey("vocabAvailable"))
        assertTrue(status.containsKey("ruleEngineAvailable"))
        assertTrue(status.containsKey("ruleOnlyFallbackActive"))
        assertEquals(true, status["ruleEngineAvailable"])
    }

    // ── Sample SMS validation cases ───────────────────────────────────────────

    @Test
    fun sampleSms_phishingLink_isDetectedAsFraud() {
        val result = detector.analyzeMessage(
            sender = "9000000001",
            body = "Your HDFC netbanking is suspended. Login now: http://hdfc.secure-verify.xyz/login",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("Phishing link SMS should be flagged", result.isFlagged)
        assertNotEquals("Classification should not be 'safe'", "safe", result.classification)
    }

    @Test
    fun sampleSms_legitimateBankOtp_isNotFlagged() {
        val result = detector.analyzeMessage(
            sender = "VM-SBIBNK",
            body = "Your OTP for SBI NetBanking login is 734291. Valid for 5 minutes. Do not share with anyone.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertFalse("Legitimate OTP from bank should NOT be flagged", result.isFlagged)
    }

    @Test
    fun sampleSms_otpTheft_isDetected() {
        val result = detector.analyzeMessage(
            sender = "9123456789",
            body = "Hello, I am from bank support. Please share your OTP and card number to unblock your account.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("OTP theft attempt should be flagged", result.isFlagged)
    }

    @Test
    fun sampleSms_apkMalware_isDetected() {
        val result = detector.analyzeMessage(
            sender = "8800001234",
            body = "Download our banking app: http://mybank-secure.xyz/banking.apk. Install and login now.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("APK malware SMS should be flagged", result.isFlagged)
        assertEquals("apk_malware_link", result.classification)
    }

    // ── Extended accuracy test cases ──────────────────────────────────────────

    @Test
    fun accuracyTest_legitimateBankOtp_isSafeWithLowRisk() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "VM-SBIBNK",
            body = "Your OTP for SBI NetBanking is 823641. Valid for 10 minutes. Do NOT share this with anyone.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertFalse(
            "Legitimate bank OTP should not be flagged; classification=${result.classification} risk=${result.localRiskScore}",
            result.isFlagged
        )
        assertTrue(
            "Risk score should be below 0.15 for a genuine bank OTP; got ${result.localRiskScore}",
            result.localRiskScore < 0.15f
        )
        assertEquals("Classification should be safe", "safe", result.classification)
    }

    @Test
    fun accuracyTest_prizeLotteryScam_isFraudWithHighRisk() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "9111222333",
            body = "Congratulations! You have WON Rs.50,00,000 LOTTERY. To claim, pay Rs.5000 processing fee to UPI ID: claim@rewards. Hurry, offer expires TODAY!",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue(
            "Prize lottery scam should be flagged; isFlagged=${result.isFlagged}",
            result.isFlagged
        )
        assertTrue(
            "Risk score should exceed 0.60 for a prize lottery scam; got ${result.localRiskScore}",
            result.localRiskScore > 0.60f
        )
        assertNotEquals("Classification should not be safe", "safe", result.classification)
    }

    @Test
    fun accuracyTest_kycExpiryScamWithUrl_isFakeKycVerification() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "9000111222",
            body = "URGENT: Your KYC has expired. Your account will be blocked in 24 hours. Update KYC now: http://sbi-kyc-verify.xyz/update",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("KYC scam with URL should be flagged", result.isFlagged)
        assertTrue(
            "Risk score should exceed 0.70 for a KYC scam with URL; got ${result.localRiskScore}",
            result.localRiskScore > 0.70f
        )
        assertEquals(
            "KYC scam should be classified as fake_kyc_verification",
            "fake_kyc_verification",
            result.classification
        )
    }

    @Test
    fun accuracyTest_apkMalwareLink_isVeryHighRisk() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "8899001122",
            body = "Download our secure banking app: http://hdfc-mobile.xyz/hdfc-bank.apk. Install and login to unlock your account now.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("APK malware SMS should be flagged", result.isFlagged)
        assertTrue(
            "Risk score should exceed 0.80 for an APK malware link; got ${result.localRiskScore}",
            result.localRiskScore > 0.80f
        )
        assertEquals(
            "APK link should be classified as apk_malware_link",
            "apk_malware_link",
            result.classification
        )
    }

    @Test
    fun accuracyTest_normalBalanceUpdate_isSafeWithLowRisk() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "DM-HDFCBK",
            body = "Your account XX5678 credited Rs.3200.00 on 24-05-2026. Available balance: Rs.18,450.00. —HDFC Bank",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertFalse(
            "Normal balance update SMS should not be flagged; classification=${result.classification} risk=${result.localRiskScore}",
            result.isFlagged
        )
        assertTrue(
            "Risk score should be below 0.15 for a balance update SMS; got ${result.localRiskScore}",
            result.localRiskScore < 0.15f
        )
        assertEquals("Classification should be safe", "safe", result.classification)
    }

    @Test
    fun accuracyTest_otpShareRequest_isOtpTheftWithHighRisk() {
        if (!classifier.modelAvailable) return

        val result = detector.analyzeMessage(
            sender = "9876001234",
            body = "Hi, I am calling from ICICI Bank support. Your account will be deactivated. Please share your OTP and card number to verify your identity immediately.",
            timestampMillis = System.currentTimeMillis(),
            persistResult = false
        )
        assertTrue("OTP share request should be flagged", result.isFlagged)
        assertTrue(
            "Risk score should exceed 0.70 for an OTP share request; got ${result.localRiskScore}",
            result.localRiskScore > 0.70f
        )
        assertEquals(
            "OTP share request should be classified as otp_theft",
            "otp_theft",
            result.classification
        )
    }
}
