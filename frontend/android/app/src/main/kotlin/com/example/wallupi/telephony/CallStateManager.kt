package com.example.wallupi.telephony

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

class CallStateManager(private val context: Context) {

    private val telephonyManager =
        context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    // API 31+ callback (kept as Any? to avoid hard compile-time dependency on S)
    private var modernCallback: TelephonyCallback? = null

    @Suppress("DEPRECATION")
    private val legacyListener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            emitCallState(state, phoneNumber)
        }
    }

    fun register(eventSink: EventChannel.EventSink) {
        sink = eventSink
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                registerModern()
            } else {
                @Suppress("DEPRECATION")
                telephonyManager.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
            }
        } catch (_: SecurityException) {
            // READ_PHONE_STATE not granted yet; re-register after permission grant
        }
    }

    fun unregister() {
        sink = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            unregisterModern()
        } else {
            @Suppress("DEPRECATION")
            telephonyManager.listen(legacyListener, PhoneStateListener.LISTEN_NONE)
        }
    }

    private fun registerModern() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    // API 31 callback does not provide phone number; pass null
                    emitCallState(state, null)
                }
            }
            modernCallback = cb
            telephonyManager.registerTelephonyCallback(context.mainExecutor, cb)
        }
    }

    private fun unregisterModern() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modernCallback?.let { telephonyManager.unregisterTelephonyCallback(it) }
            modernCallback = null
        }
    }

    private fun emitCallState(state: Int, phoneNumber: String?) {
        val stateStr = when (state) {
            TelephonyManager.CALL_STATE_IDLE -> "idle"
            TelephonyManager.CALL_STATE_RINGING -> "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
            else -> return
        }

        val isOnCall = state != TelephonyManager.CALL_STATE_IDLE
        val isUnknownCaller = if (isOnCall && !phoneNumber.isNullOrEmpty()) {
            !isNumberInContacts(phoneNumber)
        } else {
            false
        }

        val event = mapOf(
            "state" to stateStr,
            "isOnCall" to isOnCall,
            "isUnknownCaller" to isUnknownCaller,
        )

        mainHandler.post {
            sink?.success(event)
        }
    }

    fun getCurrentState(): Map<String, Any> {
        return try {
            @Suppress("DEPRECATION")
            val state = telephonyManager.callState
            val isOnCall = state != TelephonyManager.CALL_STATE_IDLE
            mapOf("isOnCall" to isOnCall, "isUnknownCaller" to false)
        } catch (_: SecurityException) {
            mapOf("isOnCall" to false, "isUnknownCaller" to false)
        }
    }

    private fun isNumberInContacts(phoneNumber: String): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
            != PackageManager.PERMISSION_GRANTED
        ) return false

        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(phoneNumber)
        )
        return context.contentResolver.query(
            uri,
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
            null, null, null
        )?.use { it.moveToFirst() } ?: false
    }
}
