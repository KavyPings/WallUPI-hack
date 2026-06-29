import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PaymentIntentDetails {
  final String upiUrl;
  final String payeeAddress;
  final String payeeName;
  final double amount;
  final String transactionNote;
  final String transactionRef;
  final String? referrerPackage;
  final String? referrerUrl;
  final String referrerAppLabel;
  final String originCategory; // browser, messaging, sms, system, unknown

  PaymentIntentDetails({
    required this.upiUrl,
    required this.payeeAddress,
    required this.payeeName,
    required this.amount,
    required this.transactionNote,
    required this.transactionRef,
    this.referrerPackage,
    this.referrerUrl,
    required this.referrerAppLabel,
    required this.originCategory,
  });

  factory PaymentIntentDetails.fromMap(Map<dynamic, dynamic> map) {
    return PaymentIntentDetails(
      upiUrl: (map['upiUrl'] ?? '').toString(),
      payeeAddress: (map['payeeAddress'] ?? '').toString(),
      payeeName: (map['payeeName'] ?? '').toString(),
      amount: ((map['amount'] ?? 0.0) as num).toDouble(),
      transactionNote: (map['transactionNote'] ?? '').toString(),
      transactionRef: (map['transactionRef'] ?? '').toString(),
      referrerPackage: map['referrerPackage']?.toString(),
      referrerUrl: map['referrerUrl']?.toString(),
      referrerAppLabel: (map['referrerAppLabel'] ?? 'External Source').toString(),
      originCategory: (map['originCategory'] ?? 'unknown').toString(),
    );
  }
}

class PaymentOriginRiskFactor {
  final String factor;
  final String description;
  final int contribution;
  final String severity; // low, medium, high

  PaymentOriginRiskFactor({
    required this.factor,
    required this.description,
    required this.contribution,
    required this.severity,
  });

  factory PaymentOriginRiskFactor.fromMap(Map<dynamic, dynamic> map) {
    return PaymentOriginRiskFactor(
      factor: (map['factor'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      contribution: ((map['contribution'] ?? 0) as num).toInt(),
      severity: (map['severity'] ?? 'low').toString(),
    );
  }
}

class PaymentOriginRiskResult {
  final int score;
  final String interventionLevel; // none, soft, strong, critical
  final String interventionMessage;
  final List<PaymentOriginRiskFactor> factors;
  final Map<String, double> breakdown;

  PaymentOriginRiskResult({
    required this.score,
    required this.interventionLevel,
    required this.interventionMessage,
    required this.factors,
    required this.breakdown,
  });

  factory PaymentOriginRiskResult.fromMap(Map<dynamic, dynamic> map) {
    final factorsList = map['factors'] as List? ?? [];
    final breakdownRaw = map['breakdown'] as Map? ?? {};
    
    return PaymentOriginRiskResult(
      score: ((map['score'] ?? 0) as num).toInt(),
      interventionLevel: (map['interventionLevel'] ?? 'none').toString(),
      interventionMessage: (map['interventionMessage'] ?? '').toString(),
      factors: factorsList
          .whereType<Map<dynamic, dynamic>>()
          .map(PaymentOriginRiskFactor.fromMap)
          .toList(),
      breakdown: breakdownRaw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
    );
  }
}

class PaymentIntentEvent {
  final PaymentIntentDetails details;
  final PaymentOriginRiskResult risk;

  PaymentIntentEvent({
    required this.details,
    required this.risk,
  });

  factory PaymentIntentEvent.fromMap(Map<dynamic, dynamic> map) {
    return PaymentIntentEvent(
      details: PaymentIntentDetails.fromMap(map['details'] as Map? ?? {}),
      risk: PaymentOriginRiskResult.fromMap(map['risk'] as Map? ?? {}),
    );
  }
}

class NativePaymentBridge {
  static const MethodChannel _channel = MethodChannel('com.example.wallupi/payment_native');
  static const EventChannel _eventChannel = EventChannel('com.example.wallupi/payment_events');

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Retrieves any pending payment intent that launched the app during a cold start.
  static Future<PaymentIntentEvent?> getInitialPaymentIntent() async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>('getInitialPaymentIntent');
      if (map == null) return null;
      return PaymentIntentEvent.fromMap(map);
    } catch (e) {
      debugPrint('Error getting initial payment intent: $e');
      return null;
    }
  }

  /// Stream of payment intents intercepted while the app is in the foreground/background running state.
  static Stream<PaymentIntentEvent> get paymentIntentStream {
    if (!isSupported) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((e) => e is Map<dynamic, dynamic>)
        .cast<Map<dynamic, dynamic>>()
        .map(PaymentIntentEvent.fromMap);
  }

  /// Calculates payment risk score locally on Android using on-device rules and TinyBERT.
  static Future<PaymentOriginRiskResult?> calculatePaymentRiskLocally({
    required double amount,
    required String payeeAddress,
    required String payeeName,
    required String transactionNote,
    required bool triggeredByQr,
    required bool triggeredByLink,
  }) async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
        'calculatePaymentRiskLocally',
        {
          'amount': amount,
          'payeeAddress': payeeAddress,
          'payeeName': payeeName,
          'transactionNote': transactionNote,
          'triggeredByQr': triggeredByQr,
          'triggeredByLink': triggeredByLink,
        },
      );
      if (map == null) return null;
      return PaymentOriginRiskResult.fromMap(map);
    } catch (e) {
      debugPrint('Error calculating local risk: $e');
      return null;
    }
  }

  /// Launches the native offline payment dialer.
  /// [method] can be 'ussd' or 'ivr'.
  static Future<bool> launchOfflinePayment({required String method}) async {
    if (!isSupported) return false;
    try {
      final success = await _channel.invokeMethod<bool>(
        'launchOfflinePayment',
        {'method': method},
      );
      return success ?? false;
    } catch (e) {
      debugPrint('Error launching offline payment: $e');
      return false;
    }
  }
}
