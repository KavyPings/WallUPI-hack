package com.example.wallupi.sms

object SmsSignalExtractor {

    private val upiRegex = Regex("""\b[\w.\-]+@[\w.\-]+\b""", RegexOption.IGNORE_CASE)
    private val phoneRegex = Regex("""(?:\+91|91|0)?[6-9]\d{9}\b""")
    private val amountRegex = Regex("""(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)
    private val urlRegex = Regex("""https?://[^\s]+|bit\.ly/[^\s]+|tinyurl\.com/[^\s]+""", RegexOption.IGNORE_CASE)
    private val nameRegex = Regex("""(?:to|pay|send|transfer|from)\s+([A-Z][a-zA-Z]{2,}(?:\s+[A-Z][a-zA-Z]{2,})*)""")

    fun extract(body: String): SmsExtractedMetadata {
        val upiIds = upiRegex.findAll(body)
            .map { it.value.lowercase() }
            .filterNot { it.endsWith(".com") || it.endsWith(".in") || it.endsWith(".org") }
            .distinct()
            .toList()

        val phones = phoneRegex.findAll(body)
            .map { normalizePhone(it.value) }
            .filter { it.length == 10 }
            .distinct()
            .toList()

        val amounts = amountRegex.findAll(body)
            .mapNotNull { it.groupValues.getOrNull(1)?.replace(",", "")?.toDoubleOrNull() }
            .distinct()
            .toList()

        val urls = urlRegex.findAll(body)
            .map { it.value }
            .distinct()
            .toList()

        val names = nameRegex.findAll(body)
            .map { it.groupValues[1].trim() }
            .filter { it.length > 2 }
            .distinct()
            .toList()

        return SmsExtractedMetadata(
            upiIds = upiIds,
            phones = phones,
            amounts = amounts,
            urls = urls,
            names = names
        )
    }

    private fun normalizePhone(raw: String): String {
        var digits = raw.replace(Regex("""[\s\-+]"""), "")
        if (digits.startsWith("91") && digits.length == 12) digits = digits.substring(2)
        if (digits.startsWith("0") && digits.length == 11) digits = digits.substring(1)
        return digits
    }
}

