package com.example.wallupi.payment

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

data class PaymentIntentDetails(
    val upiUrl: String,
    val payeeAddress: String,
    val payeeName: String,
    val amount: Double,
    val transactionNote: String,
    val transactionRef: String,
    val referrerPackage: String?,
    val referrerUrl: String?,
    val referrerAppLabel: String?,
    val originCategory: String
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "upiUrl" to upiUrl,
        "payeeAddress" to payeeAddress,
        "payeeName" to payeeName,
        "amount" to amount,
        "transactionNote" to transactionNote,
        "transactionRef" to transactionRef,
        "referrerPackage" to referrerPackage,
        "referrerUrl" to referrerUrl,
        "referrerAppLabel" to referrerAppLabel,
        "originCategory" to originCategory
    )
}

object PaymentOriginDetector {
    private const val TAG = "PaymentOriginDetector"

    // Map of common packages to labels and categories
    private val PACKAGE_MAP = mapOf(
        "com.android.chrome" to Pair("Google Chrome", "browser"),
        "org.mozilla.firefox" to Pair("Mozilla Firefox", "browser"),
        "com.microsoft.emmx" to Pair("Microsoft Edge", "browser"),
        "com.opera.browser" to Pair("Opera", "browser"),
        "com.sec.android.app.sbrowser" to Pair("Samsung Internet", "browser"),
        "com.brave.browser" to Pair("Brave Browser", "browser"),
        "com.duckduckgo.mobile.android" to Pair("DuckDuckGo", "browser"),
        
        "com.whatsapp" to Pair("WhatsApp", "messaging"),
        "com.whatsapp.w4b" to Pair("WhatsApp Business", "messaging"),
        "org.telegram.messenger" to Pair("Telegram", "messaging"),
        "com.discord" to Pair("Discord", "messaging"),
        "com.facebook.orca" to Pair("Facebook Messenger", "messaging"),
        "com.facebook.katana" to Pair("Facebook", "messaging"),
        "com.instagram.android" to Pair("Instagram", "messaging"),
        "com.twitter.android" to Pair("X (Twitter)", "messaging"),
        "com.reddit.frontpage" to Pair("Reddit", "messaging"),

        "com.google.android.apps.messaging" to Pair("Google Messages", "sms"),
        "com.android.mms" to Pair("Samsung Messages", "sms"),
        
        "com.google.android.googlequicksearchbox" to Pair("Google Search", "system")
    )

    fun detect(activity: Activity, intent: Intent): PaymentIntentDetails? {
        val dataUri = intent.data ?: return null
        if (dataUri.scheme != "upi" || dataUri.host != "pay") return null

        val upiUrl = dataUri.toString()
        val payeeAddress = dataUri.getQueryParameter("pa").orEmpty().trim().lowercase()
        if (payeeAddress.isEmpty()) return null

        val payeeName = dataUri.getQueryParameter("pn").orEmpty().trim()
        val amount = dataUri.getQueryParameter("am")?.toDoubleOrNull() ?: 0.0
        val transactionNote = dataUri.getQueryParameter("tn").orEmpty().trim()
        val transactionRef = dataUri.getQueryParameter("tr").orEmpty().trim()

        // 1. Resolve referrer package
        var referrerPackage: String? = null
        val referrerUri = activity.referrer // Returns android-app://package_name or https://domain
        if (referrerUri != null) {
            if (referrerUri.scheme == "android-app") {
                referrerPackage = referrerUri.host
            } else if (referrerUri.scheme == "http" || referrerUri.scheme == "https") {
                // If it's a direct web referrer URL
                referrerPackage = referrerUri.toString()
            }
        }

        // Fallback checks on intent extras if activity.referrer is null or empty
        if (referrerPackage == null) {
            val referrerExtra = intent.getParcelableExtra<Uri>(Intent.EXTRA_REFERRER)
                ?: intent.getParcelableExtra<Uri>("android.intent.extra.REFERRER")
            if (referrerExtra != null) {
                referrerPackage = if (referrerExtra.scheme == "android-app") {
                    referrerExtra.host
                } else {
                    referrerExtra.toString()
                }
            }
        }

        if (referrerPackage == null) {
            val referrerNameExtra = intent.getStringExtra(Intent.EXTRA_REFERRER_NAME)
                ?: intent.getStringExtra("android.intent.extra.REFERRER_NAME")
            if (!referrerNameExtra.isNullOrBlank()) {
                referrerPackage = referrerNameExtra
            }
        }

        // Special check for chromium custom tabs/browser extra referrer headers
        if (referrerPackage == null) {
            val customReferrer = intent.getStringExtra("org.chromium.chrome.extra.REFERRER")
            if (!customReferrer.isNullOrBlank()) {
                referrerPackage = customReferrer
            }
        }

        // 2. Resolve referrer URL (web domain if clicked inside a browser)
        var referrerUrl: String? = null
        if (referrerUri != null && (referrerUri.scheme == "http" || referrerUri.scheme == "https")) {
            referrerUrl = referrerUri.toString()
        }
        
        // Sometimes the URL is passed as a string extra or inside android.intent.extra.REFERRER
        if (referrerUrl == null) {
            val extraReferrer = intent.getParcelableExtra<Uri>(Intent.EXTRA_REFERRER)
            if (extraReferrer != null && (extraReferrer.scheme == "http" || extraReferrer.scheme == "https")) {
                referrerUrl = extraReferrer.toString()
            }
        }

        // 3. Resolve app details from package
        var referrerAppLabel: String? = null
        var originCategory = "unknown"

        if (referrerPackage != null) {
            val mapped = PACKAGE_MAP[referrerPackage]
            if (mapped != null) {
                referrerAppLabel = mapped.first
                originCategory = mapped.second
            } else {
                // Check if it's a web URL directly
                if (referrerPackage.startsWith("http://") || referrerPackage.startsWith("https://")) {
                    referrerUrl = referrerPackage
                    referrerAppLabel = Uri.parse(referrerPackage).host ?: "Web Browser"
                    originCategory = "browser"
                } else {
                    // Try to resolve app label from PackageManager
                    try {
                        val pm = activity.packageManager
                        val appInfo = pm.getApplicationInfo(referrerPackage, 0)
                        referrerAppLabel = pm.getApplicationLabel(appInfo).toString()
                        
                        // Infer category from package name
                        originCategory = when {
                            referrerPackage.contains("browser") || referrerPackage.contains("chrome") || referrerPackage.contains("firefox") -> "browser"
                            referrerPackage.contains("whatsapp") || referrerPackage.contains("telegram") || referrerPackage.contains("messenger") || referrerPackage.contains("chat") -> "messaging"
                            referrerPackage.contains("sms") || referrerPackage.contains("mms") || referrerPackage.contains("message") -> "sms"
                            else -> "unknown"
                        }
                    } catch (e: Exception) {
                        referrerAppLabel = referrerPackage
                    }
                }
            }
        }

        // Special handling: if we have a referrer URL but no app package, we know it's a browser.
        if (referrerUrl != null && originCategory == "unknown") {
            originCategory = "browser"
            if (referrerAppLabel == null) {
                referrerAppLabel = Uri.parse(referrerUrl).host ?: "Web Browser"
            }
        }

        return PaymentIntentDetails(
            upiUrl = upiUrl,
            payeeAddress = payeeAddress,
            payeeName = payeeName,
            amount = amount,
            transactionNote = transactionNote,
            transactionRef = transactionRef,
            referrerPackage = referrerPackage,
            referrerUrl = referrerUrl,
            referrerAppLabel = referrerAppLabel ?: "External Source",
            originCategory = originCategory
        )
    }
}
