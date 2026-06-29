package com.example.wallupi

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.example.wallupi.payment.PaymentIntentDetails
import com.example.wallupi.payment.PaymentOriginDetector
import com.example.wallupi.payment.PaymentRiskScorer
import com.example.wallupi.sms.NativeSmsRepository
import com.example.wallupi.telephony.CallStateManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    private val methodScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val nativeSmsRepository by lazy { NativeSmsRepository(applicationContext) }
    private val callStateManager by lazy { CallStateManager(applicationContext) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingCallPermissionResult: MethodChannel.Result? = null
    private var pendingPaymentIntentMap: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let { handleIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val details = PaymentOriginDetector.detect(this, intent) ?: return
        val riskResult = PaymentRiskScorer.calculateRisk(applicationContext, details)

        val resultData = mapOf(
            "details" to details.toMap(),
            "risk" to riskResult.toMap()
        )

        pendingPaymentIntentMap = resultData

        // Emit immediately to Flutter if the stream has a listener
        paymentEventSink?.let { sink ->
            mainHandler.post {
                sink.success(resultData)
                // Consume after emitting
                pendingPaymentIntentMap = null
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TELEPHONY_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    telephonyEventSink = events
                    callStateManager.register(events)
                }
                override fun onCancel(arguments: Any?) {
                    callStateManager.unregister()
                    telephonyEventSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    smsEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    smsEventSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PAYMENT_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    paymentEventSink = events
                    // Emit pending intent if we intercepted one while Dart wasn't listening yet
                    pendingPaymentIntentMap?.let {
                        events.success(it)
                        pendingPaymentIntentMap = null
                    }
                }
                override fun onCancel(arguments: Any?) {
                    paymentEventSink = null
                }
            })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSmsPermissions" -> result.success(nativeSmsRepository.hasSmsPermissions())

                "requestSmsPermissions" -> requestSmsPermissions(result)

                "getDetectorStatus" -> methodScope.launch {
                    runCatching { nativeSmsRepository.getDetectorStatus() }
                        .onSuccess(result::success)
                        .onFailure { result.error("STATUS_FAILED", it.message, null) }
                }

                "syncInbox" -> {
                    val limit = call.argument<Int>("limit") ?: DEFAULT_SYNC_LIMIT
                    methodScope.launch {
                        runCatching { nativeSmsRepository.syncInbox(limit).map { it.toMap() } }
                            .onSuccess(result::success)
                            .onFailure { result.error("SYNC_FAILED", it.message, null) }
                    }
                }

                "getProcessedSmsMessages" -> {
                    val limit = call.argument<Int>("limit") ?: DEFAULT_SYNC_LIMIT
                    methodScope.launch {
                        runCatching { nativeSmsRepository.getProcessedMessages(limit).map { it.toMap() } }
                            .onSuccess(result::success)
                            .onFailure { result.error("READ_FAILED", it.message, null) }
                    }
                }

                "analyzeSmsLocally" -> {
                    val sender = call.argument<String>("sender").orEmpty()
                    val body = call.argument<String>("body").orEmpty()
                    val persist = call.argument<Boolean>("persist") ?: true
                    if (body.isBlank()) {
                        result.error("INVALID_ARGS", "body is required", null)
                    } else {
                        methodScope.launch {
                            runCatching {
                                nativeSmsRepository.analyzeManualMessage(
                                    sender = sender,
                                    body = body,
                                    persistResult = persist
                                ).toMap()
                            }.onSuccess(result::success)
                                .onFailure { result.error("ANALYZE_FAILED", it.message, null) }
                        }
                    }
                }

                "getPendingCloudEscalations" -> result.success(nativeSmsRepository.getPendingCloudEscalations())

                "clearPendingCloudEscalations" -> {
                    nativeSmsRepository.clearPendingCloudEscalations()
                    result.success(true)
                }

                "requestCallStatePermissions" -> requestCallStatePermissions(result)

                "getCallState" -> result.success(callStateManager.getCurrentState())

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PAYMENT_CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPaymentIntent" -> {
                    result.success(pendingPaymentIntentMap)
                    pendingPaymentIntentMap = null
                }
                "calculatePaymentRiskLocally" -> {
                    val amount = call.argument<Double>("amount") ?: 0.0
                    val payeeAddress = call.argument<String>("payeeAddress").orEmpty().trim().lowercase()
                    val payeeName = call.argument<String>("payeeName").orEmpty().trim()
                    val transactionNote = call.argument<String>("transactionNote").orEmpty().trim()
                    val triggeredByQr = call.argument<Boolean>("triggeredByQr") ?: false
                    val triggeredByLink = call.argument<Boolean>("triggeredByLink") ?: false

                    val originCategory = when {
                        triggeredByQr -> "system"
                        triggeredByLink -> "browser"
                        else -> "unknown"
                    }

                    val encodedPayeeName = android.net.Uri.encode(payeeName)
                    val encodedNote = android.net.Uri.encode(transactionNote)
                    val upiUrl = "upi://pay?pa=$payeeAddress&pn=$encodedPayeeName&am=$amount&tn=$encodedNote"

                    val details = PaymentIntentDetails(
                        upiUrl = upiUrl,
                        payeeAddress = payeeAddress,
                        payeeName = payeeName,
                        amount = amount,
                        transactionNote = transactionNote,
                        transactionRef = "",
                        referrerPackage = if (triggeredByLink) "com.android.chrome" else null,
                        referrerUrl = if (triggeredByLink) "https://untrusted-referrer.xyz/pay" else null,
                        referrerAppLabel = if (triggeredByQr) "QR Scanner" else if (triggeredByLink) "Google Chrome" else "Manual Entry",
                        originCategory = originCategory
                    )

                    methodScope.launch {
                        runCatching {
                            PaymentRiskScorer.calculateRisk(applicationContext, details).toMap()
                        }.onSuccess { result.success(it) }
                         .onFailure { result.error("RISK_CALC_FAILED", it.message, null) }
                    }
                }
                "launchOfflinePayment" -> {
                    val method = call.argument<String>("method").orEmpty()
                    val number = when (method) {
                        "ussd" -> "*99%23" // %23 is #, necessary for Uri.parse
                        "ivr" -> "08045163666"
                        else -> null
                    }
                    if (number == null) {
                        result.error("INVALID_METHOD", "Unknown offline payment method", null)
                    } else {
                        try {
                            val intent = Intent(Intent.ACTION_DIAL).apply {
                                data = android.net.Uri.parse("tel:$number")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DIALER_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestCallStatePermissions(result: MethodChannel.Result) {
        val permissions = arrayOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.READ_CALL_LOG,
        )
        val allGranted = permissions.all {
            checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            result.success(true)
            return
        }
        if (pendingCallPermissionResult != null) {
            result.error("PERMISSION_PENDING", "A call permission request is already in progress", null)
            return
        }
        pendingCallPermissionResult = result
        ActivityCompat.requestPermissions(this, permissions, CALL_PERMISSION_REQUEST_CODE)
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (nativeSmsRepository.hasSmsPermissions()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.error("PERMISSION_PENDING", "A permission request is already in progress", null)
            return
        }

        pendingPermissionResult = result
        val permissions = mutableListOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE,
        )
        // Heads-up scam alerts need POST_NOTIFICATIONS on Android 13+ (runtime grant).
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        ActivityCompat.requestPermissions(
            this,
            permissions.toTypedArray(),
            SMS_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // POST_NOTIFICATIONS is optional (scam alerts are a bonus) — its denial must
        // not fail the required SMS/phone grant the feature depends on.
        val requiredResults = permissions.zip(grantResults.toList())
            .filter { it.first != Manifest.permission.POST_NOTIFICATIONS }
            .map { it.second }
        val granted = requiredResults.isNotEmpty() &&
            requiredResults.all { it == PackageManager.PERMISSION_GRANTED }
        when (requestCode) {
            SMS_PERMISSION_REQUEST_CODE -> {
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
                // READ_PHONE_STATE is now granted — register telephony listener immediately
                telephonyEventSink?.let { callStateManager.register(it) }
            }
            CALL_PERMISSION_REQUEST_CODE -> {
                pendingCallPermissionResult?.success(granted)
                pendingCallPermissionResult = null
                // Re-register now that READ_PHONE_STATE is granted
                telephonyEventSink?.let { callStateManager.register(it) }
            }
        }
    }

    override fun onDestroy() {
        callStateManager.unregister()
        methodScope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_NAME = "com.example.wallupi/sms_native"
        const val SMS_EVENT_CHANNEL = "com.example.wallupi/sms_events"
        const val TELEPHONY_EVENT_CHANNEL = "com.example.wallupi/telephony_events"
        
        private const val PAYMENT_CHANNEL_NAME = "com.example.wallupi/payment_native"
        const val PAYMENT_EVENT_CHANNEL = "com.example.wallupi/payment_events"

        private const val SMS_PERMISSION_REQUEST_CODE = 42021
        private const val CALL_PERMISSION_REQUEST_CODE = 42022
        private const val DEFAULT_SYNC_LIMIT = 120

        @Volatile var smsEventSink: EventChannel.EventSink? = null
        @Volatile var telephonyEventSink: EventChannel.EventSink? = null
        @Volatile var paymentEventSink: EventChannel.EventSink? = null
    }
}
