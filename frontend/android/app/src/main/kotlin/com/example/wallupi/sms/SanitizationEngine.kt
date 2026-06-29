package com.example.wallupi.sms

/**
 * PII Sanitization Engine — redacts sensitive data before any cloud upload.
 *
 * Redacts:
 *   - Phone numbers → [PHONE_REDACTED]
 *   - OTPs (4-8 digit codes near trigger words) → [OTP_REDACTED]
 *   - Bank account numbers → [ACCOUNT_REDACTED]
 *   - Card numbers (13-19 digits) → [CARD_REDACTED]
 *   - Aadhaar numbers (12 digits with optional spaces) → [AADHAAR_REDACTED]
 *   - PAN numbers (AAAAA0000A) → [PAN_REDACTED]
 *   - UPI PINs → [PIN_REDACTED]
 *   - Email addresses → [EMAIL_REDACTED]
 *   - Names after "Dear/Mr/Mrs/Ms" → [NAME_REDACTED]
 */
object SanitizationEngine {

    // Indian phone numbers: +91/91/0 prefix + 10 digits, or plain 10 digits starting 6-9
    private val PHONE_REGEX = Regex(
        """(?:\+91[\s\-]?|91[\s\-]?|0)?[6-9]\d{9}\b"""
    )

    // OTPs: 4-8 digit numbers near trigger words (OTP, code, pin, password, verification)
    // Looks for: "OTP is 123456" or "123456 is your OTP" patterns
    private val OTP_CONTEXT_REGEX = Regex(
        """(?:otp|code|pin|password|verification)\s*(?:is|:|\s)\s*(\d{4,8})|(\d{4,8})\s*(?:is\s+your\s+)?(?:otp|code|pin|password)""",
        RegexOption.IGNORE_CASE
    )

    // Bank account numbers: 9-18 digit sequences (typically preceded by context)
    private val ACCOUNT_REGEX = Regex(
        """(?:a/c|account|acct|ac)\s*(?:no\.?|number|#)?\s*:?\s*(?:xx|XX)?(\d{4,18})""",
        RegexOption.IGNORE_CASE
    )

    // Card numbers: 13-19 digits, possibly with spaces/dashes
    private val CARD_REGEX = Regex(
        """(?:\d{4}[\s\-]?){3,4}\d{1,4}"""
    )

    // Aadhaar: 12 digits with optional spaces (XXXX XXXX XXXX)
    private val AADHAAR_REGEX = Regex(
        """\b\d{4}\s?\d{4}\s?\d{4}\b"""
    )

    // PAN: AAAAA0000A format
    private val PAN_REGEX = Regex(
        """\b[A-Z]{5}\d{4}[A-Z]\b"""
    )

    // UPI PIN: 4-6 digit PIN near "upi pin" context
    private val UPI_PIN_REGEX = Regex(
        """(?:upi\s*pin|mpin)\s*(?:is|:|\s)\s*(\d{4,6})""",
        RegexOption.IGNORE_CASE
    )

    // Email addresses
    private val EMAIL_REGEX = Regex(
        """\b[\w.\-+]+@[\w.\-]+\.[a-zA-Z]{2,}\b"""
    )

    // Names after salutation: "Dear Kavya" → "Dear [NAME_REDACTED]"
    private val NAME_REGEX = Regex(
        """(?:dear|mr\.?|mrs\.?|ms\.?|shri|smt)\s+([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)""",
        RegexOption.IGNORE_CASE
    )

    /**
     * Sanitize an SMS body by redacting all PII.
     *
     * @param body Raw SMS body text
     * @return Sanitized text with PII replaced by redaction tokens
     */
    fun sanitize(body: String): String {
        var result = body

        // Order matters: more specific patterns first to avoid partial matches

        // 1. OTP context (before generic phone/number matching)
        result = OTP_CONTEXT_REGEX.replace(result) { match ->
            match.value.replace(Regex("""\d{4,8}"""), "[OTP_REDACTED]")
        }

        // 2. UPI PIN
        result = UPI_PIN_REGEX.replace(result) { match ->
            match.value.replace(Regex("""\d{4,6}"""), "[PIN_REDACTED]")
        }

        // 3. PAN (before generic alphanumeric stripping)
        result = PAN_REGEX.replace(result, "[PAN_REDACTED]")

        // 4. Aadhaar (before generic digit stripping)
        result = AADHAAR_REGEX.replace(result, "[AADHAAR_REDACTED]")

        // 5. Card numbers
        result = CARD_REGEX.replace(result) { match ->
            // Only redact if it looks like a real card (13-19 digits total)
            val digits = match.value.replace(Regex("""[\s\-]"""), "")
            if (digits.length in 13..19) "[CARD_REDACTED]" else match.value
        }

        // 6. Account numbers
        result = ACCOUNT_REGEX.replace(result) { match ->
            match.value.replace(Regex("""\d{4,18}"""), "[ACCOUNT_REDACTED]")
        }

        // 7. Phone numbers
        result = PHONE_REGEX.replace(result, "[PHONE_REDACTED]")

        // 8. Email
        result = EMAIL_REGEX.replace(result, "[EMAIL_REDACTED]")

        // 9. Names after salutation
        result = NAME_REGEX.replace(result) { match ->
            val salutation = match.value.substringBefore(" ").trim()
            "$salutation [NAME_REDACTED]"
        }

        return result
    }
}
