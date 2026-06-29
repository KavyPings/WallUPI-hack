import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SMS METADATA EXTRACTOR
// Extracts structured transaction signals from raw SMS text using regex.
// ─────────────────────────────────────────────────────────────────────────────
class SmsMetadataExtractor {
  /// UPI VPA: word@word (e.g. claim@rewards, kyc@sbi, pay@merchant)
  static final _upiPattern = RegExp(
    r'\b[\w.\-]+@[\w.\-]+\b',
    caseSensitive: false,
  );

  /// Indian mobile numbers: 10 digits starting 6-9, optionally prefixed +91 or 0
  static final _phonePattern = RegExp(
    r'(?:\+91|91|0)?[6-9]\d{9}\b',
  );

  /// Amounts: Rs. / Rs / ₹ followed by digits (commas allowed)
  static final _amountPattern = RegExp(
    r'(?:rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// URLs (http/https or known shorteners)
  static final _urlPattern = RegExp(
    r'https?://[^\s]+|bit\.ly/[^\s]+|tinyurl\.com/[^\s]+',
    caseSensitive: false,
  );

  /// Capitalised name-like tokens after trigger words
  static final _nameAfterTrigger = RegExp(
    r'(?:to|pay|send|transfer|from)\s+([A-Z][a-zA-Z]{2,}(?:\s+[A-Z][a-zA-Z]{2,})*)',
  );

  /// Run all patterns against [body] and return extracted metadata.
  static SmsMetadata extract(String body) {
    // UPI IDs — filter out obvious email-like false positives
    final upiIds = _upiPattern
        .allMatches(body)
        .map((m) => m.group(0)!.toLowerCase())
        .where((u) => !u.endsWith('.com') && !u.endsWith('.in') && !u.endsWith('.org'))
        .toSet()
        .toList();

    // Phone numbers — normalise to 10 digits
    final phones = _phonePattern
        .allMatches(body)
        .map((m) {
          String raw = m.group(0)!.replaceAll(RegExp(r'[\s\-+]'), '');
          if (raw.startsWith('91') && raw.length == 12) raw = raw.substring(2);
          if (raw.startsWith('0') && raw.length == 11) raw = raw.substring(1);
          return raw;
        })
        .where((p) => p.length == 10)
        .toSet()
        .toList();

    // Amounts
    final amounts = _amountPattern
        .allMatches(body)
        .map((m) {
          final digits = m.group(1)!.replaceAll(',', '');
          return double.tryParse(digits);
        })
        .whereType<double>()
        .toSet()
        .toList();

    // URLs
    final urls = _urlPattern
        .allMatches(body)
        .map((m) => m.group(0)!)
        .toList();

    // Names after trigger words
    final names = _nameAfterTrigger
        .allMatches(body)
        .map((m) => m.group(1)!.trim())
        .where((n) => n.length > 2)
        .toSet()
        .toList();

    return SmsMetadata(
      upiIds: upiIds,
      phones: phones,
      amounts: amounts,
      urls: urls,
      names: names,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMS DETECTOR
// On-device SMS fraud detection using rule-based keyword analysis
// ─────────────────────────────────────────────────────────────────────────────

/// On-device SMS fraud detection using rule-based keyword analysis.
/// This runs locally without needing the backend (privacy-first).
class SmsDetector {
  // Keyword categories with weights
  static const Map<String, Map<String, dynamic>> _fraudKeywords = {
    'urgency': {
      'words': ['urgent', 'immediately', 'expire', 'expiring', 'hurry', 'quick',
                'fast', 'now', 'today only', 'last chance', 'deadline', 'asap'],
      'weight': 0.15,
      'flag': 'urgency',
    },
    'financial_threat': {
      'words': ['blocked', 'suspended', 'deactivated', 'closed', 'frozen',
                'limited', 'restricted', 'disabled', 'terminated', 'hold'],
      'weight': 0.20,
      'flag': 'financial_threat',
    },
    'kyc_scam': {
      'words': ['kyc', 'verify', 'verification', 'update kyc', 'pan card',
                'aadhar', 'aadhaar', 'identity', 'document upload'],
      'weight': 0.18,
      'flag': 'kyc_verification',
    },
    'money_request': {
      'words': ['send money', 'transfer', 'pay now', 'payment required',
                'amount due', 'send rs', 'deposit'],
      'weight': 0.22,
      'flag': 'payment_request',
    },
    'prize_scam': {
      'words': ['congratulations', 'winner', 'won', 'prize', 'lottery',
                'reward', 'cashback', 'bonus', 'gift', 'lucky'],
      'weight': 0.18,
      'flag': 'prize_scam',
    },
    'phishing': {
      'words': ['click here', 'click link', 'tap here', 'visit link',
                'login here', 'sign in', 'update now'],
      'weight': 0.16,
      'flag': 'phishing_link',
    },
    'impersonation': {
      'words': ['rbi', 'reserve bank', 'income tax', 'government',
                'police', 'court', 'legal action', 'complaint filed'],
      'weight': 0.20,
      'flag': 'impersonation',
    },
    'otp_scam': {
      'words': ['otp', 'one time password', 'share otp', 'send otp',
                'pin', 'cvv', 'card number', 'password'],
      'weight': 0.25,
      'flag': 'sensitive_data_request',
    },
  };

  /// Analyze an SMS message locally.
  /// Automatically extracts structured metadata via [SmsMetadataExtractor].
  static SmsMessage analyzeMessage({
    required String id,
    required String sender,
    required String body,
    DateTime? timestamp,
  }) {
    final lower = body.toLowerCase();
    double riskScore = 0.0;
    List<String> flags = [];

    // Check keyword categories
    for (final entry in _fraudKeywords.entries) {
      final words = entry.value['words'] as List<String>;
      final weight = entry.value['weight'] as double;
      final flag = entry.value['flag'] as String;

      bool found = false;
      int matchCount = 0;
      for (final word in words) {
        if (lower.contains(word)) {
          found = true;
          matchCount++;
        }
      }

      if (found) {
        riskScore += weight * (1 + (matchCount - 1) * 0.3);
        flags.add(flag);
      }
    }

    // Check for suspicious URLs
    if (SmsMetadataExtractor._urlPattern.hasMatch(body)) {
      riskScore += 0.15;
      flags.add('suspicious_url');
    }

    // Check for unknown sender (number-only, not a bank short code)
    if (sender.startsWith('+91') || sender.startsWith('91') ||
        RegExp(r'^\d+$').hasMatch(sender)) {
      riskScore += 0.05;
      flags.add('unknown_sender');
    }

    // Check for excessive capitals
    int upperCount = body.split('').where((c) => c.toUpperCase() == c && c.toLowerCase() != c).length;
    if (body.length > 20 && upperCount / body.length > 0.4) {
      riskScore += 0.08;
      flags.add('excessive_capitals');
    }

    // Cap at 1.0
    riskScore = riskScore.clamp(0.0, 1.0);
    bool isFlagged = riskScore >= 0.4;

    // Extract structured metadata from the SMS body
    final metadata = SmsMetadataExtractor.extract(body);

    return SmsMessage(
      id: id,
      sender: sender,
      body: body,
      timestamp: timestamp ?? DateTime.now(),
      localRiskScore: riskScore,
      isFlagged: isFlagged,
      flags: flags,
      classification: _classifyFromFlags(flags),
      ruleScore: riskScore,
      analysisSource: 'flutter_rule_only',
      summary: isFlagged
          ? 'Flutter fallback rule engine flagged this SMS as suspicious.'
          : 'Flutter fallback rule engine found no major scam indicators.',
      extractedMetadata: metadata,
    );
  }

  /// Quick check if an SMS should trigger cloud analysis
  static bool shouldTriggerCloudAnalysis(SmsMessage sms) {
    return sms.isFlagged && sms.localRiskScore >= 0.4;
  }

  /// Get human-readable flag descriptions
  static String getFlagDescription(String flag) {
    switch (flag) {
      case 'urgency': return 'Creates false sense of urgency';
      case 'financial_threat': return 'Threatens account action';
      case 'kyc_verification': return 'Fake KYC/verification request';
      case 'payment_request': return 'Requests money transfer';
      case 'prize_scam': return 'Fake prize/reward claim';
      case 'phishing_link': return 'Contains suspicious link';
      case 'impersonation': return 'Impersonates authority';
      case 'sensitive_data_request': return 'Requests sensitive data (OTP/PIN)';
      case 'suspicious_url': return 'Contains suspicious URL';
      case 'unknown_sender': return 'From unknown sender';
      case 'excessive_capitals': return 'Uses pressure tactics (SHOUTING)';
      default: return flag;
    }
  }

  static String _classifyFromFlags(List<String> flags) {
    if (flags.contains('sensitive_data_request')) return 'otp_theft';
    if (flags.contains('kyc_verification')) return 'fake_kyc_verification';
    if (flags.contains('payment_request')) return 'upi_payment_fraud';
    if (flags.contains('phishing_link') || flags.contains('suspicious_url')) return 'phishing';
    if (flags.contains('financial_threat')) return 'fake_banking_alert';
    if (flags.contains('impersonation') || flags.contains('urgency')) return 'social_engineering_scam';
    return 'safe';
  }
}
