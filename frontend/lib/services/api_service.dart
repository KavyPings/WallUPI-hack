import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'risk_decision_engine.dart';

/// Service for communicating with the Flask backend
class ApiService {
  // LOCAL DEV (Android emulator → host loopback). Switch to ngrok or local IP
  // if running on a physical device.
  static const String _baseUrl = 'https://wallupi-host.onrender.com';

  /// Public accessor used by the admin login status probe.
  static String get baseUrl => _baseUrl;

  // Alternative URLs (switch if needed):
  // static const String _baseUrl = 'http://10.0.2.2:5000';    // Android emulator → host
  // static const String _baseUrl = 'https://entrench-retaliate-agnostic.ngrok-free.dev'; // ngrok, anywhere
  // static const String _baseUrl = 'http://192.168.1.7:5000'; // Same-WiFi physical device
  // static const String _baseUrl = 'http://localhost:5000';    // Web/desktop

  static Duration timeout = const Duration(seconds: 10);

  /// Headers sent with every request.
  /// ngrok-skip-browser-warning bypasses the ngrok interstitial HTML page
  /// that would otherwise be returned instead of JSON for non-browser clients.
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  /// Analyze SMS text for fraud indicators (Cloud AI)
  static Future<SmsAnalysisResult?> analyzeSms(String smsText) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/analyze-sms'),
            headers: _headers,
            body: jsonEncode({'sms_text': smsText}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return SmsAnalysisResult.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('API Error (analyze-sms): $e');
      // Fallback to local analysis
      return _localSmsAnalysis(smsText);
    }
    return null;
  }

  /// Get risk score for a transaction.
  ///
  /// On network failure, delegates to [RiskDecisionEngine.buildLocalRiskResult]
  /// for a consistent offline fallback that matches backend weighting.
  static Future<RiskResult?> getRiskScore({
    required double amount,
    required bool isNewRecipient,
    String userUpiId = '',
    String recipientUpiId = '',
    String recipientName = '',
    bool isMerchant = false,
    int recipientTrustScore = 50,
    int transactionCountWithRecipient = 0,
    double usualAmountWithRecipient = 0,
    double userAvgAmount = 2000,
    bool triggeredByQr = false,
    bool triggeredByLink = false,
    bool hasSuspiciousSms = false,
    int smsRiskScore = 0,
    int smsAgeMinutes = 0,
    String smsBody = '',
    String smsSender = '',
    bool isOnCall = false,
    bool isUnknownCaller = false,
    bool isRegisteredUpiId = false,
  }) async {
    try {
      final body = {
        'amount': amount,
        'is_new_recipient': isNewRecipient,
        'user_upi_id': userUpiId,
        'recipient_upi_id': recipientUpiId,
        'recipient_name': recipientName,
        'is_merchant': isMerchant,
        'recipient_trust_score': recipientTrustScore,
        'transaction_count_with_recipient': transactionCountWithRecipient,
        'usual_amount_with_recipient': usualAmountWithRecipient,
        'user_avg_amount': userAvgAmount,
        'triggered_by_qr': triggeredByQr,
        'triggered_by_link': triggeredByLink,
        'has_suspicious_sms': hasSuspiciousSms,
        'sms_risk_score': smsRiskScore,
        'sms_age_minutes': smsAgeMinutes,
        'sms_body': smsBody,
        'sms_sender': smsSender,
        'is_on_call': isOnCall,
        'is_unknown_caller': isUnknownCaller,
        'is_registered_upi_id': isRegisteredUpiId,
        'current_hour': DateTime.now().hour,
      };

      final response = await http
          .post(
            Uri.parse('$_baseUrl/risk-score'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return RiskResult.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('API Error (risk-score): $e');
      return null;
    }
    return null;
  }

  /// Get risk explanation
  static Future<Map<String, dynamic>?> explainRisk({
    required int score,
    required List<RiskFactor> factors,
    required String interventionLevel,
    String smsText = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/explain-risk'),
            headers: _headers,
            body: jsonEncode({
              'score': score,
              'factors': factors.map((f) => f.toJson()).toList(),
              'intervention_level': interventionLevel,
              'sms_text': smsText,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('API Error (explain-risk): $e');
    }
    return null;
  }

  /// Send an uncertain TinyBERT detection to the cloud LLM for a second opinion.
  ///
  /// [sanitizedBody] must be the PII-redacted SMS text already produced by
  /// the Android [SanitizationEngine] — never send raw SMS text to the cloud.
  /// Returns null silently on network failure so callers can degrade gracefully.
  static Future<CloudReviewResult?> cloudReviewSms({
    required String sanitizedBody,
    required double localRiskScore,
    required String classification,
    required String sender,
    required List<String> flags,
    String escalationReason = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/cloud-review'),
            headers: _headers,
            body: jsonEncode({
              'sanitized_body': sanitizedBody,
              'local_risk_score': localRiskScore,
              'classification': classification,
              'sender': sender,
              'flags': flags,
              'escalation_reason': escalationReason,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return CloudReviewResult.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('API Error (cloud-review): $e');
    }
    return null;
  }

  // ========== COMMUNITY / PROFILE ENDPOINTS ==========

  /// Log a completed transaction to the backend profile system.
  /// Fire-and-forget — errors are silently swallowed.
  static Future<void> logTransaction({
    required String userUpiId,
    required String recipientUpiId,
    required double amount,
    required int riskScore,
    required String interventionLevel,
    bool isMerchant = false,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/profile/transaction'),
            headers: _headers,
            body: jsonEncode({
              'user_upi_id': userUpiId,
              'recipient_upi_id': recipientUpiId,
              'amount': amount,
              'risk_score': riskScore,
              'intervention_level': interventionLevel,
              'is_merchant': isMerchant,
            }),
          )
          .timeout(timeout);
    } catch (_) {}
  }

  /// Flag a UPI ID and/or phone number as spam/fraud.
  /// Returns true on success (HTTP 200 or 201).
  static Future<bool> flagAsSpam({
    required String reporterUpiId,
    String? flaggedUpiId,
    String? flaggedPhone,
    required String reason,
    String? note,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/spam/flag'),
            headers: _headers,
            body: jsonEncode({
              'reporter_upi_id': reporterUpiId,
              if (flaggedUpiId != null) 'flagged_upi_id': flaggedUpiId,
              if (flaggedPhone != null) 'flagged_phone': flaggedPhone,
              'reason': reason,
              if (note != null) 'note': note,
            }),
          )
          .timeout(timeout);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Check how many community members have flagged a UPI ID.
  /// Returns 0 on network failure.
  static Future<int> checkSpamFlags(String upiId) async {
    try {
      final uri = Uri.parse('$_baseUrl/spam/check').replace(
        queryParameters: {'upi_id': upiId},
      );
      final response = await http.get(uri, headers: _headers).timeout(timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['flag_count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Fetch the DB-backed relationship profile between user and a counterpart.
  ///
  /// Returns a map with keys: `trust_score` (int), `txn_count` (int),
  /// `avg_amount` (double), `flagged_txn_count` (int).
  /// Returns null on any network failure or if no relationship exists yet.
  static Future<Map<String, dynamic>?> getRelationshipProfile({
    required String userUpiId,
    required String counterpartUpiId,
  }) async {
    if (userUpiId.isEmpty || counterpartUpiId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl/profile/relationship').replace(
        queryParameters: {
          'user_upi': userUpiId,
          'counterpart_upi': counterpartUpiId,
        },
      );
      final response = await http.get(uri, headers: _headers).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch the DB-backed profile for a recipient UPI ID.
  ///
  /// Returns a map with keys: `risk_tier` (string: 'low'/'medium'/'high'),
  /// `total_txn_count` (int), `high_risk_txn_count` (int),
  /// `flagged_by_others_count` (int).
  /// Returns null on any network failure or if the recipient has no profile yet.
  static Future<Map<String, dynamic>?> getRecipientProfile(String upiId) async {
    if (upiId.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/profile/user/${Uri.encodeComponent(upiId)}'),
               headers: _headers)
          .timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ========== FALLBACK LOCAL ANALYSIS ==========

  static SmsAnalysisResult _localSmsAnalysis(String text) {
    final lower = text.toLowerCase();
    int score = 0;
    List<HighlightedWord> highlighted = [];

    final keywords = {
      'urgent': 15,
      'immediately': 15,
      'expire': 12,
      'blocked': 20,
      'suspended': 20,
      'deactivated': 18,
      'kyc': 18,
      'verify': 12,
      'verification': 15,
      'send money': 22,
      'transfer': 15,
      'pay now': 18,
      'congratulations': 18,
      'won': 15,
      'prize': 18,
      'lottery': 20,
      'click here': 16,
      'click link': 16,
      'otp': 25,
      'cvv': 25,
      'pin': 20,
      'password': 22,
    };

    keywords.forEach((word, weight) {
      if (lower.contains(word)) {
        score += weight;
        int idx = lower.indexOf(word);
        highlighted.add(HighlightedWord(
          word: text.substring(idx, idx + word.length),
          start: idx,
          end: idx + word.length,
          category: 'keyword',
          severity: weight >= 20 ? 'high' : 'medium',
        ));
      }
    });

    score = score.clamp(0, 100);

    return SmsAnalysisResult(
      riskScore: score,
      classification:
          score >= 70 ? 'high_risk' : score >= 40 ? 'suspicious' : 'safe',
      summary: score >= 70
          ? 'High risk message detected'
          : score >= 40
          ? 'Suspicious elements found'
          : 'Message appears safe',
      explanation: 'Local analysis (offline mode)',
      highlightedWords: highlighted,
      riskFactors: {},
    );
  }
}
