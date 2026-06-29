package com.example.wallupi.payment

import android.content.Context
import android.net.Uri
import android.util.Log
import com.example.wallupi.sms.SmsLocalStore
import com.example.wallupi.sms.TinyBertTFLiteClassifier
import com.example.wallupi.telephony.CallStateManager

data class PaymentRiskFactor(
    val factor: String,
    val description: String,
    val contribution: Int,
    val severity: String
) {
    fun toMap(): Map<String, Any> = mapOf(
        "factor" to factor,
        "description" to description,
        "contribution" to contribution,
        "severity" to severity
    )
}

data class PaymentRiskResult(
    val score: Int,
    val interventionLevel: String,
    val interventionMessage: String,
    val factors: List<PaymentRiskFactor>,
    val breakdown: Map<String, Double>
) {
    fun toMap(): Map<String, Any> = mapOf(
        "score" to score,
        "interventionLevel" to interventionLevel,
        "interventionMessage" to interventionMessage,
        "factors" to factors.map { it.toMap() },
        "breakdown" to breakdown
    )
}

object PaymentRiskScorer {
    private const val TAG = "PaymentRiskScorer"

    private val SUSPICIOUS_TLDS = setOf(
        "xyz", "top", "click", "buzz", "online", "club", "info", "site", "work",
        "ml", "cf", "ga", "gq", "tk", "support", "help", "vip", "live"
    )

    private val PHISHING_KEYWORDS = listOf(
        "kyc", "verify", "verification", "update", "secure", "login", "bank",
        "sbi", "hdfc", "icici", "paytm", "phonepe", "gpay", "upi", "refund",
        "reward", "lottery", "cashback", "gift", "prize", "blocked", "suspended",
        "deactivated", "closed", "frozen", "limited", "restricted", "disabled"
    )

    fun calculateRisk(context: Context, details: PaymentIntentDetails): PaymentRiskResult {
        var score = 0
        val factors = mutableListOf<PaymentRiskFactor>()
        val breakdown = mutableMapOf<String, Double>()

        var originScore = 0.0
        var domainScore = 0.0
        var aiScore = 0.0
        var contextScore = 0.0

        // 1. Origin App Category Scoring
        when (details.originCategory) {
            "messaging", "sms" -> {
                val penalty = 30
                score += penalty
                originScore += penalty.toDouble()
                factors.add(PaymentRiskFactor(
                    factor = "Untrusted Referral Source",
                    description = "Payment intent launched from a messaging or SMS app (${details.referrerAppLabel}). Scam links are frequently distributed via chat platforms.",
                    contribution = penalty,
                    severity = "medium"
                ))
            }
            "unknown" -> {
                val penalty = 25
                score += penalty
                originScore += penalty.toDouble()
                factors.add(PaymentRiskFactor(
                    factor = "Unknown Referral App",
                    description = "Payment intent launched from an unknown or unregistered application (${details.referrerPackage ?: "Unknown"}).",
                    contribution = penalty,
                    severity = "medium"
                ))
            }
            "browser" -> {
                val penalty = 15
                score += penalty
                originScore += penalty.toDouble()
                factors.add(PaymentRiskFactor(
                    factor = "Web Browser Redirect",
                    description = "Payment intent initiated from a web browser (${details.referrerAppLabel}). Web redirects are a common method for launching fake KYC/refund pages.",
                    contribution = penalty,
                    severity = "low"
                ))
            }
            "system" -> {
                val penalty = 5
                score += penalty
                originScore += penalty.toDouble()
                // Not adding to factors as it's very low risk
            }
        }

        // 2. Referrer URL Domain Analysis
        val url = details.referrerUrl
        if (!url.isNullOrBlank()) {
            try {
                val uri = Uri.parse(url)
                val host = uri.host?.lowercase() ?: ""
                
                // Sketchy TLD Check
                val tld = host.substringAfterLast('.', "")
                if (tld.isNotEmpty() && SUSPICIOUS_TLDS.contains(tld)) {
                    val penalty = 20
                    score += penalty
                    domainScore += penalty.toDouble()
                    factors.add(PaymentRiskFactor(
                        factor = "Suspicious Top-Level Domain",
                        description = "Referring domain '$host' uses a low-trust top-level domain (.$tld) often used by fraudsters.",
                        contribution = penalty,
                        severity = "high"
                    ))
                }

                // Keyword Check in Domain
                val matchedKeyword = PHISHING_KEYWORDS.firstOrNull { host.contains(it) }
                if (matchedKeyword != null) {
                    val penalty = 25
                    score += penalty
                    domainScore += penalty.toDouble()
                    factors.add(PaymentRiskFactor(
                        factor = "Phishing Keyword in Web Domain",
                        description = "Referring domain '$host' contains the suspicious keyword '$matchedKeyword', simulating a secure portal.",
                        contribution = penalty,
                        severity = "high"
                    ))
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse referrer URL: ${e.message}")
            }
        }

        // 3. TinyBERT Text Classification
        // Load the classifier on demand to conserve resources
        val classifier = TinyBertTFLiteClassifier(context)
        try {
            if (classifier.modelAvailable) {
                val cfg = classifier.classifierConfig
                val threshold = cfg?.lowConfidenceThreshold ?: 0.62f

                // Run TinyBERT on the note (tn) and payee name (pn)
                val textsToClassify = listOf(
                    Pair("payee name", details.payeeName),
                    Pair("payment note", details.transactionNote)
                )

                for ((labelType, text) in textsToClassify) {
                    if (text.isNotBlank()) {
                        val classification = classifier.classify(text)
                        if (classification != null && classification.label == "fraud" && classification.confidence >= threshold) {
                            val confidencePercentage = (classification.confidence * 100).toInt()
                            val penalty = (35 * classification.confidence).toInt()
                            score += penalty
                            aiScore += penalty.toDouble()
                            factors.add(PaymentRiskFactor(
                                factor = "AI-Detected Scam Content",
                                description = "On-device TinyBERT model flagged the $labelType '$text' as fraudulent/impersonation with $confidencePercentage% confidence.",
                                contribution = penalty,
                                severity = "high"
                            ))
                        }
                    }
                }
            } else {
                Log.i(TAG, "TinyBERT TFLite model is not available for payment scoring")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error running TinyBERT classifier: ${e.message}")
        } finally {
            classifier.close()
        }

        // 4. Live Call Correlation
        val callManager = CallStateManager(context)
        val callState = callManager.getCurrentState()
        val isOnCall = callState["isOnCall"] as? Boolean ?: false
        if (isOnCall) {
            val penalty = 25
            score += penalty
            contextScore += penalty.toDouble()
            factors.add(PaymentRiskFactor(
                factor = "Active Call Correlation",
                description = "Transaction initiated while on an active voice call. Scammers frequently use phone guidance to force payments.",
                contribution = penalty,
                severity = "high"
            ))
        }

        // 5. SMS Correlation Check
        // Search the local SMS store for recently received flagged SMS messages containing matching targets.
        val store = SmsLocalStore(context)
        val recentSmsList = store.getProcessedMessages()
        val twoHoursAgo = System.currentTimeMillis() - (2 * 60 * 60 * 1000)

        val cleanPayee = details.payeeAddress.replace(" ", "").replace("-", "").replace("+", "")
        val cleanPayeeName = details.payeeName.lowercase()

        val matchingSms = recentSmsList.firstOrNull { sms ->
            sms.timestampMillis >= twoHoursAgo && sms.isFlagged && (
                sms.body.lowercase().contains(cleanPayee) ||
                (cleanPayeeName.isNotEmpty() && sms.body.lowercase().contains(cleanPayeeName)) ||
                sms.sender.replace(Regex("[\\s\\-+]"), "").contains(cleanPayee)
            )
        }

        if (matchingSms != null) {
            val penalty = 40
            score += penalty
            contextScore += penalty.toDouble()
            factors.add(PaymentRiskFactor(
                factor = "Correlated Phishing SMS",
                description = "Matching phishing SMS recently received from '${matchingSms.sender}'. The message is flagged and contains references matching this payment.",
                contribution = penalty,
                severity = "high"
            ))
        }

        // Clamp final score
        val finalScore = score.coerceIn(0, 100)

        // Determine intervention level
        val interventionLevel = when {
            finalScore >= 95 -> "critical"
            finalScore >= 80 -> "strong"
            finalScore >= 50 -> "soft"
            else -> "none"
        }

        val interventionMessage = when (interventionLevel) {
            "critical" -> "Critical threat detected — this payment originates from a suspected phishing page"
            "strong" -> "High risk source — this payment request was initiated by an external site/app"
            "soft" -> "Caution advised — review payment details and source before sending money"
            else -> "Payment source appears normal"
        }

        breakdown["originApp"] = originScore
        breakdown["referrerUrl"] = domainScore
        breakdown["textAi"] = aiScore
        breakdown["contextCorrelation"] = contextScore

        // Sort factors: positive contributions descending
        factors.sortByDescending { it.contribution }

        return PaymentRiskResult(
            score = finalScore,
            interventionLevel = interventionLevel,
            interventionMessage = interventionMessage,
            factors = factors,
            breakdown = breakdown
        )
    }
}
