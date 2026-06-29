import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/foundation.dart' show unawaited;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../data/demo_data.dart';
import '../services/storage_service.dart';
import '../services/sms_detector.dart';
import '../services/api_service.dart';
import '../services/risk_decision_engine.dart';
import '../services/native_sms_bridge.dart';
import '../services/native_telephony_bridge.dart';
import '../services/native_payment_bridge.dart';

/// Central state management for Wallupi app
class AppProvider extends ChangeNotifier {
  UserProfile? _user;
  List<Transaction> _transactions = [];
  List<SmsMessage> _smsMessages = [];
  List<Recipient> _recipients = [];
  bool _isOnCall = false;
  bool _isUnknownCaller = false;
  bool _isRegisteredUpiId = false;
  bool _isLoading = false;
  SmsMessage? _activeSuspiciousSms;
  NativeSmsDetectorStatus? _nativeSmsStatus;
  StreamSubscription<SmsMessage>? _smsStreamSubscription;
  StreamSubscription<CallStateEvent>? _telephonySubscription;
  StreamSubscription<PaymentIntentEvent>? _paymentStreamSubscription;
  bool _hasRealCall = false;
  PaymentIntentEvent? _pendingPaymentIntent;

  /// Ephemeral per-payment risk session. Created by [checkRisk], destroyed by
  /// [clearRiskSession]. This is the ONLY place that tracks whether a warning
  /// is currently active for a payment attempt.
  RiskSessionContext? _currentRiskSession;

  UserProfile? get user => _user;
  List<Transaction> get transactions => _transactions;
  List<SmsMessage> get smsMessages => _smsMessages;
  List<SmsMessage> get flaggedSms => _smsMessages.where((s) => s.isFlagged).toList();
  List<Recipient> get recipients => _recipients;
  bool get isOnCall => _isOnCall;
  bool get isUnknownCaller => _isUnknownCaller;
  bool get isRegisteredUpiId => _isRegisteredUpiId;
  bool get isLoading => _isLoading;
  bool get isAdmin => _user?.isAdmin ?? false;
  SmsMessage? get activeSuspiciousSms => _activeSuspiciousSms;
  bool get hasSuspiciousSms => _activeSuspiciousSms != null;
  RiskSessionContext? get currentRiskSession => _currentRiskSession;
  NativeSmsDetectorStatus? get nativeSmsStatus => _nativeSmsStatus;
  bool get hasRealCall => _hasRealCall;
  PaymentIntentEvent? get pendingPaymentIntent => _pendingPaymentIntent;

  Future<void> initialize() async {
    await StorageService.init();

    final isAdminUser = StorageService.getIsAdmin();
    _user = StorageService.getUserProfile() ?? (isAdminUser ? DemoData.demoUser : null);
    _transactions = StorageService.getTransactions();
    _smsMessages = StorageService.getSmsMessages();
    _recipients = StorageService.getRecipients();

    if (isAdminUser) {
      if (_transactions.isEmpty) {
        _transactions = DemoData.demoTransactions;
        await StorageService.saveTransactions(_transactions);
      }

      // Always overwrite the built-in demo SMS entries so classification/flag
      // corrections in DemoData take effect without needing to clear app storage.
      const demoIds = {'SMS001', 'SMS002', 'SMS003', 'SMS004', 'SMS005'};
      final nativeOnlySms = _smsMessages.where((s) => !demoIds.contains(s.id)).toList();
      _smsMessages = [...DemoData.allSmsMessages, ...nativeOnlySms];
      await StorageService.saveSmsMessages(_smsMessages);

      if (_recipients.isEmpty) {
        _recipients = [
          ...DemoData.knownRecipients,
          ...DemoData.suspiciousRecipients,
        ];
        await StorageService.saveRecipients(_recipients);
      }
    }

    _refreshActiveSuspiciousSms();
    _isOnCall = StorageService.getSimulateCallState();
    _isUnknownCaller = StorageService.getSimulateUnknownCaller();
    _isRegisteredUpiId = StorageService.getRegisteredUpiId();

    await refreshNativeSmsStatus(notify: false);
    await syncNativeSmsMessages(limit: 120, notify: false);

    // Subscribe once to the native SMS push stream so new messages appear
    // in Flutter immediately when SmsReceiver processes them in the foreground.
    if (NativeSmsBridge.isSupported) {
      _smsStreamSubscription ??= NativeSmsBridge.smsStream.listen(_onNativeSmsArrived);
    }

    // Subscribe to native payment intent stream and resolve initial intent
    if (NativePaymentBridge.isSupported) {
      _pendingPaymentIntent = await NativePaymentBridge.getInitialPaymentIntent();
      _paymentStreamSubscription ??= NativePaymentBridge.paymentIntentStream.listen(_onNativePaymentIntentArrived);
    }

    // Subscribe to real call state events; request permissions fire-and-forget.
    _telephonySubscription ??=
        NativeTelephonyBridge.callStateStream.listen(_onCallStateChanged);
    unawaited(NativeTelephonyBridge.requestCallStatePermissions());

    if (_user != null) {
      await StorageService.saveUserProfile(_user!);
    }
    notifyListeners();
  }

  void _onCallStateChanged(CallStateEvent event) {
    _hasRealCall = event.isOnCall;
    if (event.isOnCall) {
      _isOnCall = true;
      _isUnknownCaller = event.isUnknownCaller;
    } else {
      _isOnCall = StorageService.getSimulateCallState();
      _isUnknownCaller = StorageService.getSimulateUnknownCaller();
    }
    notifyListeners();
  }

  void _onNativeSmsArrived(SmsMessage sms) {
    _mergeMessages([sms]);
    StorageService.saveSmsMessages(_smsMessages);
    _refreshActiveSuspiciousSms();
    notifyListeners();
    // Fire-and-forget: show local result immediately, upgrade silently when the cloud LLM responds.
    unawaited(_maybeCloudReview(sms));
  }

  void _onNativePaymentIntentArrived(PaymentIntentEvent event) {
    _pendingPaymentIntent = event;
    notifyListeners();
  }

  void clearPendingPaymentIntent() {
    _pendingPaymentIntent = null;
    notifyListeners();
  }

  /// If the on-device analysis was uncertain, send the sanitized SMS body to
  /// the cloud LLM for a second opinion and silently update the message in state.
  Future<void> _maybeCloudReview(SmsMessage sms) async {
    if (!sms.shouldEscalateToCloud) return;
    final sanitized = sms.sanitizedPreview;
    if (sanitized == null || sanitized.isEmpty) return;

    final result = await ApiService.cloudReviewSms(
      sanitizedBody: sanitized,
      localRiskScore: sms.localRiskScore,
      classification: sms.classification,
      sender: sms.sender,
      flags: sms.flags,
      escalationReason: sms.cloudEscalationReason ?? 'Model uncertainty',
    );
    if (result == null) return;

    // Merge: take the higher of the two risk scores so we never downgrade a
    // message that the local rules already flagged as high-risk.
    final mergedScore = max(sms.localRiskScore, result.riskScore / 100.0);
    final isFlagged = mergedScore >= 0.45 || result.classification != 'safe';

    final updated = sms.copyWith(
      localRiskScore: mergedScore,
      isFlagged: isFlagged,
      classification: result.classification,
      summary: result.explanation,
      analysisSource: '${sms.analysisSource}+cloud',
      shouldEscalateToCloud: false, // escalation is now complete
    );

    _mergeMessages([updated]);
    await StorageService.saveSmsMessages(_smsMessages);
    _refreshActiveSuspiciousSms();
    notifyListeners();
  }

  @override
  void dispose() {
    _smsStreamSubscription?.cancel();
    _telephonySubscription?.cancel();
    _paymentStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> login(String name, String phone) async {
    final isAdminUser =
        phone.trim() == '0000000000' &&
        name.trim().toLowerCase() == 'kavy';

    _user = UserProfile(
      name: name,
      phone: phone,
      upiId: '${name.toLowerCase().replaceAll(' ', '')}@wallupi',
      balance: isAdminUser ? 999999.00 : 1000.00,
      isAdmin: isAdminUser,
      avgTransactionAmount: 2000,
      maxTransactionAmount: 15000,
      typicalTransactionHour: 14,
      frequentRecipients: isAdminUser
          ? ['rahul@upi', 'amazon@merchant', 'priya@upi']
          : [],
    );
    await StorageService.saveUserProfile(_user!);
    await StorageService.setLoggedIn(true);
    await StorageService.setIsAdmin(isAdminUser);
    await StorageService.setRegisteredPhone(phone);

    if (isAdminUser) {
      // Admin: load demo transactions, recipients, SMS
      _transactions = DemoData.demoTransactions;
      _recipients = [
        ...DemoData.knownRecipients,
        ...DemoData.suspiciousRecipients,
      ];
      const demoIds = {'SMS001', 'SMS002', 'SMS003', 'SMS004', 'SMS005'};
      final nativeOnly = _smsMessages.where((s) => !demoIds.contains(s.id)).toList();
      _smsMessages = [...DemoData.allSmsMessages, ...nativeOnly];
      await StorageService.saveTransactions(_transactions);
      await StorageService.saveRecipients(_recipients);
      await StorageService.saveSmsMessages(_smsMessages);
    } else {
      // Regular user: start fresh
      _transactions = [];
      _recipients = [];
      await StorageService.saveTransactions(_transactions);
      await StorageService.saveRecipients(_recipients);
    }

    _refreshActiveSuspiciousSms();
    await syncNativeSmsMessages(limit: 120, notify: false);
    notifyListeners();
  }

  Future<void> logout() async {
    _smsStreamSubscription?.cancel();
    _smsStreamSubscription = null;
    _telephonySubscription?.cancel();
    _telephonySubscription = null;
    _paymentStreamSubscription?.cancel();
    _paymentStreamSubscription = null;
    _pendingPaymentIntent = null;

    _user = null;
    _transactions = [];
    _smsMessages = [];
    _recipients = [];
    _isOnCall = false;
    _isUnknownCaller = false;
    _isRegisteredUpiId = false;
    _hasRealCall = false;
    _activeSuspiciousSms = null;
    _currentRiskSession = null;

    await StorageService.clearAll();
    notifyListeners();
  }

  Future<SmsMessage> addSms({
    required String sender,
    required String body,
  }) async {
    final sms = await NativeSmsBridge.analyzeSmsLocally(
          sender: sender,
          body: body,
          persist: true,
        ) ??
        SmsDetector.analyzeMessage(
          id: 'SMS${DateTime.now().millisecondsSinceEpoch}',
          sender: sender,
          body: body,
        );

    _mergeMessages([sms]);
    await StorageService.saveSmsMessages(_smsMessages);
    _refreshActiveSuspiciousSms();
    await refreshNativeSmsStatus(notify: false);

    notifyListeners();
    // Fire-and-forget cloud review — UI shows local result immediately.
    unawaited(_maybeCloudReview(sms));
    return sms;
  }

  Future<void> refreshNativeSmsStatus({bool notify = true}) async {
    _nativeSmsStatus = await NativeSmsBridge.getDetectorStatus();
    if (notify) notifyListeners();
  }

  Future<bool> requestSmsPermissions() async {
    final granted = await NativeSmsBridge.requestSmsPermissions();
    await refreshNativeSmsStatus(notify: false);
    if (granted) {
      await syncNativeSmsMessages(limit: 120, notify: false);
    }
    notifyListeners();
    return granted;
  }

  Future<int> syncNativeSmsMessages({
    int limit = 120,
    bool notify = true,
  }) async {
    if (!NativeSmsBridge.isSupported) return 0;

    final hasPermissions = await NativeSmsBridge.hasSmsPermissions();
    if (!hasPermissions) {
      await refreshNativeSmsStatus(notify: notify);
      return 0;
    }

    final nativeMessages = await NativeSmsBridge.syncInbox(limit: limit);
    if (nativeMessages.isNotEmpty) {
      _mergeMessages(nativeMessages);
      await StorageService.saveSmsMessages(_smsMessages);
      _refreshActiveSuspiciousSms();
    }
    await refreshNativeSmsStatus(notify: false);
    if (notify) notifyListeners();
    return nativeMessages.length;
  }

  Future<RiskSessionContext?> checkRisk({
    required double amount,
    required String recipientUpiId,
    required String recipientName,
    String note = '',
    bool triggeredByQr = false,
    SmsMessage? matchedSms,
    PaymentIntentEvent? paymentIntent,
  }) async {
    _isLoading = true;
    _currentRiskSession = null;
    notifyListeners();

    final recipient = _recipients.firstWhere(
      (r) => r.upiId == recipientUpiId,
      orElse: () => Recipient(name: 'Unknown', upiId: recipientUpiId, trustScore: 10),
    );

    final effectiveSms = matchedSms ?? _activeSuspiciousSms;
    final hasSms = effectiveSms != null || hasSuspiciousSms;
    final smsAgeMinutes = effectiveSms != null
        ? DateTime.now().difference(effectiveSms.timestamp).inMinutes
        : 0;

    // Query live call state directly from TelephonyManager at payment time.
    // The stream-based state (_isOnCall) may have missed a pre-existing call
    // if the listener hadn't registered yet when the call started.
    final liveCall = await NativeTelephonyBridge.getCallState();
    final effectiveIsOnCall = _isOnCall || liveCall.isOnCall;
    final effectiveIsUnknownCaller =
        _isOnCall ? _isUnknownCaller : liveCall.isUnknownCaller;

    // Sync provider state so UI reflects the real call if stream missed it
    if (liveCall.isOnCall && !_hasRealCall) {
      _hasRealCall = true;
      _isOnCall = true;
      _isUnknownCaller = liveCall.isUnknownCaller;
    }

    // Query the DB-backed relationship profile (fire in parallel with call state).
    // On first transaction the endpoint returns 404 → null; that's fine.
    // DB values take priority over in-memory data resets on reinstall but DB persists across sessions.
    final dbRel = await ApiService.getRelationshipProfile(
      userUpiId: _user?.upiId ?? '',
      counterpartUpiId: recipientUpiId,
    );

    final effectiveTrustScore = dbRel != null
        ? ((dbRel['trust_score'] as num?)?.toInt() ?? recipient.trustScore)
        : recipient.trustScore;
    final effectiveTxnCount = dbRel != null
        ? ((dbRel['txn_count'] as num?)?.toInt() ?? recipient.transactionCount)
        : recipient.transactionCount;
    final effectiveUsualAmount = dbRel != null
        ? ((dbRel['avg_amount'] as num?)?.toDouble() ?? recipient.usualAmount)
        : recipient.usualAmount;
    final effectiveIsNew = effectiveTxnCount == 0;

    RiskResult? result;
    bool isOffline = false;

    try {
      result = await ApiService.getRiskScore(
        amount: amount,
        isNewRecipient: effectiveIsNew,
        userUpiId: _user?.upiId ?? '',
        recipientUpiId: recipientUpiId,
        recipientName: recipientName,
        isMerchant: recipient.isMerchant,
        recipientTrustScore: effectiveTrustScore,
        transactionCountWithRecipient: effectiveTxnCount,
        usualAmountWithRecipient: effectiveUsualAmount,
        userAvgAmount: _user?.avgTransactionAmount ?? 2000,
        triggeredByQr: triggeredByQr,
        triggeredByLink: paymentIntent != null,
        hasSuspiciousSms: hasSms,
        smsRiskScore: effectiveSms != null ? (effectiveSms.localRiskScore * 100).round() : 0,
        smsAgeMinutes: smsAgeMinutes,
        smsBody: effectiveSms?.body ?? '',
        smsSender: effectiveSms?.sender ?? '',
        isOnCall: effectiveIsOnCall,
        isUnknownCaller: effectiveIsUnknownCaller,
        isRegisteredUpiId: _isRegisteredUpiId,
      );
    } catch (e) {
      debugPrint('Error getting risk score from API: $e');
    }

    if (result == null) {
      isOffline = true;
      if (NativePaymentBridge.isSupported) {
        final localResult = await NativePaymentBridge.calculatePaymentRiskLocally(
          amount: amount,
          payeeAddress: recipientUpiId,
          payeeName: recipientName,
          transactionNote: note,
          triggeredByQr: triggeredByQr,
          triggeredByLink: paymentIntent != null,
        );
        if (localResult != null) {
          result = RiskResult(
            score: localResult.score,
            interventionLevel: localResult.interventionLevel,
            interventionMessage: localResult.interventionMessage,
            factors: localResult.factors.map((f) => RiskFactor(
              factor: f.factor,
              description: f.description,
              contribution: f.contribution,
              severity: f.severity,
            )).toList(),
            breakdown: localResult.breakdown,
          );
        }
      }

      if (result == null) {
        result = RiskDecisionEngine.buildLocalRiskResult(
          amount: amount,
          userAvgAmount: _user?.avgTransactionAmount ?? 2000,
          isNewRecipient: effectiveIsNew,
          recipientUpiId: recipientUpiId,
          recipientName: recipientName,
          hasSuspiciousSms: hasSms,
          smsRiskScore: effectiveSms != null ? (effectiveSms.localRiskScore * 100).round() : 0,
          smsBody: effectiveSms?.body ?? '',
          smsSender: effectiveSms?.sender ?? '',
          isOnCall: effectiveIsOnCall,
          isUnknownCaller: effectiveIsUnknownCaller,
          isRegisteredUpiId: _isRegisteredUpiId,
          triggeredByQr: triggeredByQr,
          transactionCountWithRecipient: effectiveTxnCount,
          usualAmountWithRecipient: effectiveUsualAmount,
          recipientTrustScore: effectiveTrustScore,
          isMerchant: recipient.isMerchant,
          smsAgeMinutes: smsAgeMinutes,
        );
      }
    }

    _isLoading = false;

    // Merge origin-risk calculated on Android native side
    RiskResult finalResult = result;
    if (paymentIntent != null) {
      final intentRisk = paymentIntent.risk;
      if (intentRisk.score > finalResult.score) {
        final mergedFactors = List<RiskFactor>.from(finalResult.factors);
        for (final f in intentRisk.factors) {
          if (!mergedFactors.any((element) => element.factor == f.factor)) {
            mergedFactors.add(RiskFactor(
              factor: f.factor,
              description: f.description,
              contribution: f.contribution,
              severity: f.severity,
            ));
          }
        }

        final mergedBreakdown = Map<String, double>.from(finalResult.breakdown);
        mergedBreakdown['intent_origin_score'] = intentRisk.score.toDouble();

        finalResult = RiskResult(
          score: intentRisk.score,
          interventionLevel: intentRisk.interventionLevel,
          interventionMessage: intentRisk.interventionMessage,
          factors: mergedFactors,
          breakdown: mergedBreakdown,
        );
      }
    }

    final level = RiskDecisionEngine.levelFromString(finalResult.interventionLevel);
    final session = RiskSessionContext(
      result: finalResult,
      level: level,
      recipientName: recipientName,
      recipientUpiId: recipientUpiId,
      amount: amount,
      note: note,
      smsText: effectiveSms?.body,
      isOffline: isOffline,
    );

    _currentRiskSession = session;
    notifyListeners();
    return session;
  }

  void clearRiskSession() {
    if (_currentRiskSession != null) {
      _currentRiskSession = null;
      notifyListeners();
    }
  }

  Future<bool> flagAsSpam({
    String? flaggedUpiId,
    String? flaggedPhone,
    required String reason,
    String? note,
  }) async {
    final success = await ApiService.flagAsSpam(
      reporterUpiId: _user?.upiId ?? '',
      flaggedUpiId: flaggedUpiId,
      flaggedPhone: flaggedPhone,
      reason: reason,
      note: note,
    );
    if (success && flaggedUpiId != null) {
      final idx = _recipients.indexWhere((r) => r.upiId == flaggedUpiId);
      if (idx >= 0) {
        final r = _recipients[idx];
        _recipients[idx] = r.copyWith(
          flaggedCount: r.flaggedCount + 1,
          trustScore: (r.trustScore - 15).clamp(5, 95),
        );
        await StorageService.saveRecipients(_recipients);
        notifyListeners();
      }
    }
    return success;
  }

  Future<Transaction> processPayment({
    required String recipientName,
    required String recipientUpiId,
    required double amount,
    String note = '',
    int riskScore = 0,
    bool wasCorrelatedWithSms = false,
  }) async {
    final transaction = Transaction(
      id: 'TXN${DateTime.now().millisecondsSinceEpoch}',
      recipientName: recipientName,
      recipientUpiId: recipientUpiId,
      amount: amount,
      timestamp: DateTime.now(),
      status: 'success',
      riskScore: riskScore,
      note: note,
    );

    _transactions.insert(0, transaction);
    // Admin has unlimited balance — never deduct
    if (!(_user?.isAdmin ?? false)) {
      _user = _user?.copyWith(
        balance: (_user!.balance - amount).clamp(0, double.infinity),
      );
    }

    await StorageService.addTransaction(transaction);
    await StorageService.saveUserProfile(_user!);

    unawaited(ApiService.logTransaction(
      userUpiId: _user?.upiId ?? '',
      recipientUpiId: recipientUpiId,
      amount: amount,
      riskScore: riskScore,
      interventionLevel: _currentRiskSession?.result.interventionLevel ?? 'none',
      isMerchant: _recipients
          .where((r) => r.upiId == recipientUpiId)
          .firstOrNull
          ?.isMerchant ?? false,
    ));

    await _updateRecipientProfile(
      upiId: recipientUpiId,
      name: recipientName,
      amount: amount,
      wasCorrelatedWithSms: wasCorrelatedWithSms,
    );

    _currentRiskSession = null;
    _activeSuspiciousSms = null;

    notifyListeners();
    return transaction;
  }

  Future<void> _updateRecipientProfile({
    required String upiId,
    required String name,
    required double amount,
    bool wasCorrelatedWithSms = false,
  }) async {
    final idx = _recipients.indexWhere((r) => r.upiId == upiId);

    Recipient updated;
    if (idx >= 0) {
      final existing = _recipients[idx];
      final newAmounts = [amount, ...existing.recentAmounts].take(5).toList();
      final newAvg = newAmounts.reduce((a, b) => a + b) / newAmounts.length;
      final newCount = existing.transactionCount + 1;
      final newFlagged = existing.flaggedCount + (wasCorrelatedWithSms ? 1 : 0);
      final paymentBonus = (newCount * (existing.isMerchant ? 4 : 3)).clamp(0, 30);
      final flagPenalty = newFlagged * 15;
      final newTrust = (50 + paymentBonus - flagPenalty).clamp(5, 95).toInt();

      updated = existing.copyWith(
        name: name,
        transactionCount: newCount,
        usualAmount: newAvg,
        recentAmounts: newAmounts,
        lastTransactionDate: DateTime.now(),
        flaggedCount: newFlagged,
        trustScore: newTrust,
      );
      _recipients[idx] = updated;
    } else {
      updated = Recipient(
        name: name,
        upiId: upiId,
        transactionCount: 1,
        usualAmount: amount,
        recentAmounts: [amount],
        lastTransactionDate: DateTime.now(),
        flaggedCount: wasCorrelatedWithSms ? 1 : 0,
        trustScore: wasCorrelatedWithSms ? 35 : 50,
      );
      _recipients.add(updated);
    }

    await StorageService.saveRecipients(_recipients);
  }

  void toggleCallState(bool value) {
    _isOnCall = value;
    StorageService.setSimulateCallState(value);
    notifyListeners();
  }

  void toggleUnknownCaller(bool value) {
    _isUnknownCaller = value;
    StorageService.setSimulateUnknownCaller(value);
    notifyListeners();
  }

  void toggleRegisteredUpiId(bool value) {
    _isRegisteredUpiId = value;
    StorageService.setRegisteredUpiId(value);
    notifyListeners();
  }

  void clearSuspiciousSms() {
    _activeSuspiciousSms = null;
    notifyListeners();
  }

  Recipient? findRecipient(String query) {
    if (query.isEmpty) return null;
    try {
      return _recipients.firstWhere((r) => r.matches(query));
    } catch (_) {
      return null;
    }
  }

  String getRecipientName(String upiId) {
    return findRecipient(upiId)?.name ?? upiId;
  }

  void _mergeMessages(List<SmsMessage> incoming) {
    final merged = <String, SmsMessage>{};
    for (final sms in [..._smsMessages, ...incoming]) {
      final key = sms.nativeMessageId ?? sms.id;
      merged[key] = sms;
    }
    _smsMessages = merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _refreshActiveSuspiciousSms() {
    final flagged = flaggedSms;
    _activeSuspiciousSms = flagged.isNotEmpty ? flagged.first : null;
  }
}
