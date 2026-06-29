package com.example.wallupi.sms

/**
 * Fast heuristic pre-filter for SMS scam detection.
 *
 * Runs BEFORE the TinyBERT model (~1ms) to:
 *   - Short-circuit obvious scams (score > 0.85 → skip ML)
 *   - Short-circuit obvious safe messages (score < 0.15 → skip ML)
 *   - Provide additional signal for combined scoring
 *
 * Detects: suspicious URLs, urgency language, impersonation, shortened links,
 *          APK downloads, suspicious domains, excessive caps, money requests.
 */
object RuleEngine {

    data class RuleResult(
        val score: Float,
        val flags: List<String>,
        val shouldEscalateToML: Boolean,
        val details: Map<String, Any> = emptyMap()
    )

    // ── Trusted domains — URLs from these hosts are not flagged ─────────────
    private val TRUSTED_DOMAINS = setOf(
        // Telecom
        "airtel.in", "airtel.com", "jio.com", "vodafone.in", "vi.in", "bsnl.co.in",
        // Banks (official domains only — not subdomains of spoofed sites)
        "sbi.co.in", "onlinesbi.sbi", "hdfcbank.com", "icicibank.com", "axisbank.com",
        "kotak.com", "pnbindia.in", "bankofbaroda.in", "canarabank.in", "yesbank.in",
        "indusind.com", "federalbank.co.in", "idfcfirstbank.com", "rbi.org.in",
        // UPI / payments
        "npci.org.in", "bhimupi.org.in", "paytm.com", "phonepe.com", "gpay.app",
        // E-commerce / delivery
        "amazon.in", "amazon.com", "flipkart.com", "myntra.com", "meesho.com",
        "swiggy.com", "zomato.com", "bigbasket.com", "nykaa.com", "dunzo.com",
        // Government
        "gov.in", "nic.in", "uidai.gov.in", "incometax.gov.in", "mca.gov.in",
        // Big tech
        "google.com", "apple.com", "microsoft.com", "youtube.com",
    )

    private fun isTrustedUrl(url: String): Boolean {
        return try {
            val host = java.net.URI(url).host?.lowercase() ?: return false
            TRUSTED_DOMAINS.any { trusted -> host == trusted || host.endsWith(".$trusted") }
        } catch (_: Exception) {
            false
        }
    }

    // ── Suspicious URL patterns ──────────────────────────────────────────────
    private val SUSPICIOUS_URL_REGEX = Regex(
        """https?://[^\s]+""", RegexOption.IGNORE_CASE
    )
    private val SHORTENED_LINK_REGEX = Regex(
        """(?:bit\.ly|tinyurl\.com|goo\.gl|t\.co|is\.gd|rb\.gy|cutt\.ly|shorturl\.at|tiny\.cc)/[^\s]+""",
        RegexOption.IGNORE_CASE
    )
    private val APK_LINK_REGEX = Regex(
        """https?://[^\s]+\.apk""", RegexOption.IGNORE_CASE
    )
    private val SUSPICIOUS_DOMAIN_REGEX = Regex(
        """https?://(?:[^\s/]*(?:verify|secure|update|login|bank|sbi|icici|hdfc|paytm|phonepe|gpay|upi)[^\s/]*\.(?:xyz|tk|ml|ga|cf|gq|top|work|click|link|info|site|online|buzz))[^\s]*""",
        RegexOption.IGNORE_CASE
    )
    // A call-to-action verb sitting right next to any link ("Click bit.ly/x",
    // "Visit website.in/pay"). Catches phishing CTAs that don't use the exact
    // phrase "click here" — including bare links with no http:// scheme.
    private val LINK_CTA_REGEX = Regex(
        """\b(click|tap|visit|open|go to|login at|verify at|claim at|pay at)\b[^\n]{0,25}(https?://|www\.|bit\.ly|tinyurl|t\.co|cutt\.ly|rb\.gy|[a-z0-9-]{2,}\.(?:com|in|co|net|org|xyz|info|link|site|online|app|biz)/)""",
        RegexOption.IGNORE_CASE
    )

    // ── Urgency language ─────────────────────────────────────────────────────
    private val URGENCY_WORDS = listOf(
        "urgent", "immediately", "expire", "expiring", "hurry", "quick",
        "fast", "asap", "today only", "last chance", "deadline", "now only",
        "act now", "limited time", "don't delay", "within 24 hours",
        "account will be", "will be blocked", "will be suspended",
        "will be closed", "will be deactivated"
    )

    // ── Financial threat patterns ────────────────────────────────────────────
    private val FINANCIAL_THREAT_WORDS = listOf(
        "blocked", "block", "suspended", "suspend", "suspension",
        "deactivated", "deactivate", "closed", "frozen", "freeze",
        "limited", "restricted", "disabled", "terminated", "hold",
        "seized", "locked", "cancelled", "dormant"
    )

    // ── KYC/verification scam ────────────────────────────────────────────────
    private val KYC_SCAM_WORDS = listOf(
        "kyc", "verify", "verification", "update kyc", "pan card",
        "aadhar", "aadhaar", "identity verification", "document upload",
        "re-kyc", "e-kyc", "kyc expir"
    )

    // ── Money request patterns ───────────────────────────────────────────────
    private val MONEY_REQUEST_WORDS = listOf(
        "send money", "transfer", "pay now", "payment required",
        "amount due", "send rs", "deposit", "pay rs", "send ₹",
        "pay ₹", "processing fee", "registration fee"
    )

    // ── Prize/lottery scam ───────────────────────────────────────────────────
    private val PRIZE_SCAM_WORDS = listOf(
        "congratulations", "winner", "won", "prize", "lottery",
        "reward", "cashback", "bonus", "gift", "lucky draw",
        "you have been selected", "you are selected", "claim your"
    )

    // ── OTP/sensitive data request ───────────────────────────────────────────
    private val OTP_SCAM_WORDS = listOf(
        "share otp", "send otp", "share your otp", "tell your otp",
        "share pin", "share cvv", "card number", "enter otp",
        "share password", "send pin", "share your pin"
    )

    // ── Impersonation patterns ───────────────────────────────────────────────
    private val IMPERSONATION_WORDS = listOf(
        "rbi", "reserve bank", "income tax", "government of india",
        "police", "court", "legal action", "complaint filed",
        "cyber cell", "enforcement directorate", "cbi", "it department"
    )

    // ── Phishing action patterns ─────────────────────────────────────────────
    private val PHISHING_ACTION_WORDS = listOf(
        "click here", "click link", "tap here", "visit link",
        "login here", "sign in", "update now", "click below",
        "open link", "download app", "install app"
    )

    // ── Investment / stock-tip fraud (SEBI-flagged pump-and-dump, unregistered
    //    advisory). These are a huge category of Indian financial fraud and were
    //    previously invisible to the engine. ──────────────────────────────────
    private val INVESTMENT_SCAM_WORDS = listOf(
        "multibagger", "multi bagger", "multi-bagger", "stock tip", "stock alert",
        "intraday", "breakout", "break out alert", "guaranteed return",
        "guaranteed profit", "assured return", "sure shot", "jackpot", "penny stock",
        "ipo alert", "grey market", "gmp", "research report", "trading tips",
        "demat", "nse listed", "bse listed", "52 week high", "telegram channel",
        "join now for profit"
    )

    // Trading-call structure: "TGT 25", "SL 5", "@ 6.25", "Buy 9000 QTY",
    // "Target 38", explicit NSE/BSE references. Two or more of these in one
    // message is the signature of a stock-tip blast.
    private val TRADING_SIGNAL_PATTERNS = listOf(
        Regex("""\btgt\b""", RegexOption.IGNORE_CASE),
        Regex("""\btarget\s*[:\-]?\s*\d""", RegexOption.IGNORE_CASE),
        Regex("""\bsl\b""", RegexOption.IGNORE_CASE),
        Regex("""\bstop\s?loss\b""", RegexOption.IGNORE_CASE),
        Regex("""\bqty\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(nse|bse)\b""", RegexOption.IGNORE_CASE),
        Regex("""@\s?\d+(\.\d+)?""", RegexOption.IGNORE_CASE),
        Regex("""\bbuy\b.{0,20}\b(qty|shares?|stock|lot)\b""", RegexOption.IGNORE_CASE),
    )

    // ── Safety-advisory / negation context ───────────────────────────────────
    // Legitimate bank/telecom advisories ("Never share your OTP", "we will never
    // ask for your PIN") contain the same sensitive keywords as a scam but in a
    // protective, negated context. Detecting this prevents false positives.
    private val ADVISORY_CONTEXT_REGEX = Regex(
        """\b(never (share|respond|reveal|disclose|click|give)|do ?n['o]?t (share|respond|reveal|disclose|click|give)|we (will )?never ask|bank(s)? (will )?never ask|will never ask you|beware of (fraud|scam|fake)|fraud alert|safety tip|stay safe|do not entertain)\b""",
        RegexOption.IGNORE_CASE
    )

    /**
     * Analyze an SMS message using rule-based heuristics.
     *
     * @param sender The SMS sender (phone number or short code)
     * @param body The SMS body text
     * @return [RuleResult] with score (0.0–1.0), flags, and ML escalation decision
     */
    fun analyze(sender: String, body: String): RuleResult {
        val lower = body.lowercase()
        var score = 0f
        val flags = mutableListOf<String>()
        val details = mutableMapOf<String, Any>()

        // ── 1. URL Analysis ──────────────────────────────────────────────────
        val urls = SUSPICIOUS_URL_REGEX.findAll(body).map { it.value }.toList()
        if (urls.isNotEmpty()) {
            details["urls"] = urls
            val untrustedUrls = urls.filter { !isTrustedUrl(it) }
            if (untrustedUrls.isNotEmpty()) {
                score += 0.12f
                flags.add("suspicious_url")
            }
        }

        val shortened = SHORTENED_LINK_REGEX.findAll(body).map { it.value }.toList()
        if (shortened.isNotEmpty()) {
            // A shortened link hides its destination — a strong smishing signal
            // in an unsolicited SMS, even on its own.
            score += 0.30f
            flags.add("shortened_link")
            details["shortened_links"] = shortened
        }

        if (APK_LINK_REGEX.containsMatchIn(body)) {
            // A sideloaded APK delivered via SMS link is near-certain malware.
            score += 0.45f
            flags.add("apk_download")
        }

        if (SUSPICIOUS_DOMAIN_REGEX.containsMatchIn(body)) {
            score += 0.20f
            flags.add("suspicious_domain")
        }

        // A call-to-action verb next to a link ("Click bit.ly/x") is phishing
        // even without the literal phrase "click here". Also flags bare links
        // (no http:// scheme) that the URL regex above would otherwise miss.
        if (LINK_CTA_REGEX.containsMatchIn(body) && "phishing_link" !in flags) {
            score += 0.16f
            flags.add("phishing_link")
        }

        // ── 2. Keyword Category Matching ─────────────────────────────────────
        val categoryScores = mapOf(
            "urgency"           to Pair(URGENCY_WORDS, 0.12f),
            "financial_threat"  to Pair(FINANCIAL_THREAT_WORDS, 0.15f),
            "kyc_verification"  to Pair(KYC_SCAM_WORDS, 0.14f),
            "payment_request"   to Pair(MONEY_REQUEST_WORDS, 0.18f),
            "prize_scam"        to Pair(PRIZE_SCAM_WORDS, 0.16f),
            "sensitive_data_request" to Pair(OTP_SCAM_WORDS, 0.28f),
            "impersonation"     to Pair(IMPERSONATION_WORDS, 0.16f),
            "phishing_link"     to Pair(PHISHING_ACTION_WORDS, 0.14f),
        )

        var matchedCategories = 0
        for ((flag, pair) in categoryScores) {
            val (words, weight) = pair
            val matchCount = words.count { lower.contains(it) }
            if (matchCount > 0) {
                // Bonus for multiple matches within same category
                val categoryScore = weight * (1f + (matchCount - 1) * 0.2f)
                score += categoryScore
                flags.add(flag)
                matchedCategories++
            }
        }

        // ── 2b. Investment / stock-tip fraud ─────────────────────────────────
        // Pattern-based: keyword hits ("multibagger", "GMP") and/or structural
        // trading-call signals ("TGT 25", "Buy 9000 QTY", "@6.25 SL 5").
        val investmentWordMatches = INVESTMENT_SCAM_WORDS.count { lower.contains(it) }
        val tradingSignals = TRADING_SIGNAL_PATTERNS.count { it.containsMatchIn(body) }
        val isTradingCall = tradingSignals >= 2 ||
            investmentWordMatches >= 2 ||
            (investmentWordMatches >= 1 && tradingSignals >= 1)
        if (isTradingCall) {
            score += 0.45f
            flags.add("investment_scam")
            matchedCategories++
            details["investment_signals"] = investmentWordMatches + tradingSignals
        }

        // Compound risk: multiple categories = multiplicative boost
        if (matchedCategories >= 3) {
            score *= 1.15f
            flags.add("multi_category_compound")
        }
        if (matchedCategories >= 5) {
            score *= 1.10f
        }

        // ── 3. Sender Analysis ───────────────────────────────────────────────
        val senderClean = sender.replace(Regex("""[\s\-+]"""), "")
        val isNumericSender = senderClean.matches(Regex("""^\d{10,13}$"""))
        val isShortCode = senderClean.matches(Regex("""^[A-Z]{2,6}\d*$"""))

        if (isNumericSender && !isShortCode) {
            score += 0.05f
            flags.add("unknown_sender")
        }

        // ── 4. Excessive Capitals ────────────────────────────────────────────
        if (body.length > 20) {
            val upperCount = body.count { it.isUpperCase() }
            val ratio = upperCount.toFloat() / body.length
            if (ratio > 0.4f) {
                score += 0.06f
                flags.add("excessive_capitals")
            }
        }

        // ── Safety-advisory guard ────────────────────────────────────────────
        // A protective/negated advisory ("Never share your OTP", "we never ask
        // for PIN") trips the same keyword categories as a scam. If the message
        // reads as an advisory AND carries none of the hard scam signals (links,
        // APKs, money requests, stock-tip structure), strip the soft keyword
        // flags so it is not misclassified, and drop the score to safe.
        val hardScamSignal = listOf(
            "apk_download", "suspicious_url", "suspicious_domain",
            "shortened_link", "payment_request", "investment_scam"
        ).any { it in flags }
        if (ADVISORY_CONTEXT_REGEX.containsMatchIn(body) && !hardScamSignal) {
            flags.removeAll(
                listOf("kyc_verification", "sensitive_data_request", "urgency", "financial_threat")
            )
            flags.add("safety_advisory")
            score = minOf(score, 0.10f)
        }

        // ── Clamp and decide ─────────────────────────────────────────────────
        score = score.coerceIn(0f, 1f)

        // Short-circuit decisions:
        //   > 0.85: definitely scam, skip ML
        //   < 0.15: definitely safe, skip ML
        //   middle: escalate to ML for nuanced classification
        val shouldEscalateToML = score in 0.15f..0.85f

        return RuleResult(
            score = score,
            flags = flags,
            shouldEscalateToML = shouldEscalateToML,
            details = details
        )
    }
}
