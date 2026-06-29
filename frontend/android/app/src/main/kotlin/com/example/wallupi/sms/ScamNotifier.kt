package com.example.wallupi.sms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.wallupi.MainActivity

/**
 * Posts a heads-up system notification the instant a risky SMS is detected, so the
 * user is warned at the moment of danger instead of having to open the app and
 * scroll to a manual review screen.
 *
 * Fires entirely on-device from the on-device verdict — no network needed — so the
 * warning is immediate even offline. The cloud review (when it runs) can re-post an
 * upgraded verdict for the same message via [notify] (same notification id replaces).
 */
object ScamNotifier {

    private const val CHANNEL_ID = "scam_alerts"
    private const val CHANNEL_NAME = "Scam alerts"

    /** Only warn for messages at or above this local risk. Below it stays silent. */
    private const val NOTIFY_THRESHOLD = 0.45f

    /**
     * Show a scam warning for [result] if it clears the risk threshold.
     * Safe to call for every message — it self-filters and no-ops when notifications
     * are disabled or permission has not been granted.
     */
    fun notify(context: Context, result: SmsDetectionResult) {
        if (!result.isFlagged || result.localRiskScore < NOTIFY_THRESHOLD) return

        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return

        ensureChannel(context)

        val riskPct = (result.localRiskScore * 100).toInt()
        val high = result.localRiskScore >= 0.70f
        val prettyType = result.classification.replace('_', ' ')
            .replaceFirstChar { it.uppercase() }

        val title = if (high) "⚠️ Likely scam detected" else "⚠️ Suspicious message"
        val shortLine = if (high) {
            "$prettyType ($riskPct% risk). Don't tap links, share OTP/PIN, or pay."
        } else {
            "Possible $prettyType ($riskPct% risk). Be careful — tap to review."
        }
        val senderLine = if (result.sender.isNotBlank()) "From ${result.sender}\n" else ""

        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentIntent = PendingIntent.getActivity(
            context, result.messageId.hashCode(), openApp, pendingFlags
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle(title)
            .setContentText(shortLine)
            .setStyle(NotificationCompat.BigTextStyle().bigText(senderLine + shortLine))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setColor(0xFFD32F2F.toInt())
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            // Stable id per message so a later cloud verdict replaces (not duplicates) it.
            manager.notify(result.messageId.hashCode(), notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted on Android 13+; warning silently skipped.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Immediate warnings when a likely scam SMS is received"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
