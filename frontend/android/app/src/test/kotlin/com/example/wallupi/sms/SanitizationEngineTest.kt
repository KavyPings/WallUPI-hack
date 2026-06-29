package com.example.wallupi.sms

import org.junit.Assert.*
import org.junit.Test

class SanitizationEngineTest {

    @Test
    fun `OTP is redacted`() {
        val input = "Your OTP is 482931. Do not share."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Raw OTP should be redacted", output.contains("482931"))
        assertTrue("OTP placeholder should appear", output.contains("[OTP_REDACTED]"))
    }

    @Test
    fun `PAN number is redacted`() {
        val input = "Please provide your PAN ABCDE1234F for verification."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Raw PAN should be redacted", output.contains("ABCDE1234F"))
        assertTrue("PAN placeholder should appear", output.contains("[PAN_REDACTED]"))
    }

    @Test
    fun `phone number is redacted`() {
        val input = "Call us at 9876543210 for assistance."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Raw phone number should be redacted", output.contains("9876543210"))
        assertTrue("Phone placeholder should appear", output.contains("[PHONE_REDACTED]"))
    }

    @Test
    fun `email address is redacted`() {
        val input = "Send your details to user@example.com immediately."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Raw email should be redacted", output.contains("user@example.com"))
        assertTrue("Email placeholder should appear", output.contains("[EMAIL_REDACTED]"))
    }

    @Test
    fun `Aadhaar number is redacted`() {
        val input = "Link your Aadhaar 1234 5678 9012 to your account."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Raw Aadhaar should be redacted", output.contains("1234 5678 9012"))
        assertTrue("Aadhaar placeholder should appear", output.contains("[AADHAAR_REDACTED]"))
    }

    @Test
    fun `safe message is not altered significantly`() {
        val input = "Your Amazon package has been delivered."
        val output = SanitizationEngine.sanitize(input)
        // No PII in this message, output should be structurally similar
        assertTrue("Safe message should still contain non-PII words",
            output.contains("Amazon") || output.contains("package") || output.contains("delivered"))
    }

    @Test
    fun `name after Dear salutation is redacted`() {
        val input = "Dear Rahul, your account has been updated."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Name should be redacted", output.contains("Rahul"))
    }

    @Test
    fun `output never contains raw card number`() {
        val input = "Your card 4111 1111 1111 1111 has been charged."
        val output = SanitizationEngine.sanitize(input)
        assertFalse("Card number should be redacted", output.contains("4111"))
    }

    @Test
    fun `multiple PII types are all redacted`() {
        val input = "Dear John, your OTP is 123456. Contact 9988776655 or john@mail.com."
        val output = SanitizationEngine.sanitize(input)
        assertFalse(output.contains("123456"))
        assertFalse(output.contains("9988776655"))
        assertFalse(output.contains("john@mail.com"))
    }
}
