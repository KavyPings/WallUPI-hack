/// Data models for Wallupi app

/// Risk level tiers — single source of truth for routing decisions
enum RiskLevel {
  safe,     // 0–49: proceed directly
  soft,     // 50–79: lightweight warning, no friction
  strong,   // 80–94: detailed warning + checkbox required
  critical, // 95–100: 10-second delay + checkbox required
}

/// Ephemeral per-payment risk session. Created when risk is checked,
/// destroyed on cancel, back navigation, or successful payment.
class RiskSessionContext {
  final RiskResult result;
  final RiskLevel level;
  final String recipientName;
  final String recipientUpiId;
  final double amount;
  final String note;
  final String? smsText;
  final DateTime createdAt;
  final bool isOffline;

  RiskSessionContext({
    required this.result,
    required this.level,
    required this.recipientName,
    required this.recipientUpiId,
    required this.amount,
    this.note = '',
    this.smsText,
    this.isOffline = false,
  }) : createdAt = DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// SMS METADATA — extracted transaction signals from an SMS body
// ─────────────────────────────────────────────────────────────────────────────

/// Structured data extracted from an SMS body via regex.
/// Used to cross-match against a payment's UPI ID / amount / payee.
class SmsMetadata {
  /// UPI IDs found in the SMS (e.g. "claim@rewards", "kyc@sbi")
  final List<String> upiIds;

  /// Phone numbers found (normalised — digits only, no country code prefix)
  final List<String> phones;

  /// Monetary amounts mentioned (e.g. 5000.0, 99.0)
  final List<double> amounts;

  /// Suspicious URLs found
  final List<String> urls;

  /// Payee/person names (capitalised words following "to" / "pay")
  final List<String> names;

  const SmsMetadata({
    this.upiIds = const [],
    this.phones = const [],
    this.amounts = const [],
    this.urls = const [],
    this.names = const [],
  });

  bool get isEmpty =>
      upiIds.isEmpty && phones.isEmpty && amounts.isEmpty &&
      urls.isEmpty && names.isEmpty;

  Map<String, dynamic> toJson() => {
    'upiIds': upiIds,
    'phones': phones,
    'amounts': amounts,
    'urls': urls,
    'names': names,
  };

  factory SmsMetadata.fromJson(Map<String, dynamic> json) => SmsMetadata(
    upiIds: List<String>.from(json['upiIds'] ?? []),
    phones: List<String>.from(json['phones'] ?? []),
    amounts: (json['amounts'] as List? ?? []).map((v) => (v as num).toDouble()).toList(),
    urls: List<String>.from(json['urls'] ?? []),
    names: List<String>.from(json['names'] ?? []),
  );
}

class UserProfile {
  final String name;
  final String phone;
  final String upiId;
  final double balance;
  final bool isAdmin;
  final double avgTransactionAmount;
  final double maxTransactionAmount;
  final int typicalTransactionHour;
  final List<String> frequentRecipients;

  UserProfile({
    required this.name,
    required this.phone,
    required this.upiId,
    required this.balance,
    this.isAdmin = false,
    this.avgTransactionAmount = 2000,
    this.maxTransactionAmount = 10000,
    this.typicalTransactionHour = 14,
    this.frequentRecipients = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'upiId': upiId,
    'balance': balance,
    'isAdmin': isAdmin,
    'avgTransactionAmount': avgTransactionAmount,
    'maxTransactionAmount': maxTransactionAmount,
    'typicalTransactionHour': typicalTransactionHour,
    'frequentRecipients': frequentRecipients,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] ?? '',
    phone: json['phone'] ?? '',
    upiId: json['upiId'] ?? '',
    balance: (json['balance'] ?? 0).toDouble(),
    isAdmin: json['isAdmin'] ?? false,
    avgTransactionAmount: (json['avgTransactionAmount'] ?? 2000).toDouble(),
    maxTransactionAmount: (json['maxTransactionAmount'] ?? 10000).toDouble(),
    typicalTransactionHour: json['typicalTransactionHour'] ?? 14,
    frequentRecipients: List<String>.from(json['frequentRecipients'] ?? []),
  );

  UserProfile copyWith({double? balance, bool? isAdmin}) => UserProfile(
    name: name,
    phone: phone,
    upiId: upiId,
    balance: balance ?? this.balance,
    isAdmin: isAdmin ?? this.isAdmin,
    avgTransactionAmount: avgTransactionAmount,
    maxTransactionAmount: maxTransactionAmount,
    typicalTransactionHour: typicalTransactionHour,
    frequentRecipients: frequentRecipients,
  );
}

class Transaction {
  final String id;
  final String recipientName;
  final String recipientUpiId;
  final double amount;
  final DateTime timestamp;
  final String status; // 'success', 'failed', 'cancelled'
  final int riskScore;
  final String note;
  final bool isIncoming;

  Transaction({
    required this.id,
    required this.recipientName,
    required this.recipientUpiId,
    required this.amount,
    required this.timestamp,
    this.status = 'success',
    this.riskScore = 0,
    this.note = '',
    this.isIncoming = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipientName': recipientName,
    'recipientUpiId': recipientUpiId,
    'amount': amount,
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'riskScore': riskScore,
    'note': note,
    'isIncoming': isIncoming,
  };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'] ?? '',
    recipientName: json['recipientName'] ?? '',
    recipientUpiId: json['recipientUpiId'] ?? '',
    amount: (json['amount'] ?? 0).toDouble(),
    timestamp: DateTime.parse(json['timestamp']),
    status: json['status'] ?? 'success',
    riskScore: json['riskScore'] ?? 0,
    note: json['note'] ?? '',
    isIncoming: json['isIncoming'] ?? false,
  );
}

class SmsMessage {
  final String id;
  final String? nativeMessageId;
  final String sender;
  final String body;
  final DateTime timestamp;
  final double localRiskScore; // 0.0 - 1.0
  final bool isFlagged;
  final List<String> flags;
  final String classification;
  final double? modelConfidence;
  final double? ruleScore;
  final bool modelAvailable;
  final String analysisSource;
  final bool shouldEscalateToCloud;
  final String? cloudEscalationReason;
  final String? sanitizedPreview;
  final String? summary;

  /// Structured data extracted from [body] via regex.
  /// Populated by [SmsDetector.analyzeMessage]; null for legacy objects.
  final SmsMetadata? extractedMetadata;

  SmsMessage({
    required this.id,
    this.nativeMessageId,
    required this.sender,
    required this.body,
    required this.timestamp,
    this.localRiskScore = 0.0,
    this.isFlagged = false,
    this.flags = const [],
    this.classification = 'safe',
    this.modelConfidence,
    this.ruleScore,
    this.modelAvailable = false,
    this.analysisSource = 'flutter_rule_only',
    this.shouldEscalateToCloud = false,
    this.cloudEscalationReason,
    this.sanitizedPreview,
    this.summary,
    this.extractedMetadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nativeMessageId': nativeMessageId,
    'sender': sender,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'localRiskScore': localRiskScore,
    'isFlagged': isFlagged,
    'flags': flags,
    'classification': classification,
    'modelConfidence': modelConfidence,
    'ruleScore': ruleScore,
    'modelAvailable': modelAvailable,
    'analysisSource': analysisSource,
    'shouldEscalateToCloud': shouldEscalateToCloud,
    'cloudEscalationReason': cloudEscalationReason,
    'sanitizedPreview': sanitizedPreview,
    'summary': summary,
    'extractedMetadata': extractedMetadata?.toJson(),
  };

  factory SmsMessage.fromJson(Map<String, dynamic> json) => SmsMessage(
    id: json['id'] ?? '',
    nativeMessageId: json['nativeMessageId'],
    sender: json['sender'] ?? '',
    body: json['body'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
    localRiskScore: (json['localRiskScore'] ?? 0).toDouble(),
    isFlagged: json['isFlagged'] ?? false,
    flags: List<String>.from(json['flags'] ?? []),
    classification: json['classification'] ?? 'safe',
    modelConfidence: (json['modelConfidence'] as num?)?.toDouble(),
    ruleScore: (json['ruleScore'] as num?)?.toDouble(),
    modelAvailable: json['modelAvailable'] ?? false,
    analysisSource: json['analysisSource'] ?? 'flutter_rule_only',
    shouldEscalateToCloud: json['shouldEscalateToCloud'] ?? false,
    cloudEscalationReason: json['cloudEscalationReason'],
    sanitizedPreview: json['sanitizedPreview'],
    summary: json['summary'],
    extractedMetadata: json['extractedMetadata'] != null
        ? SmsMetadata.fromJson(json['extractedMetadata'])
        : null,
  );

  factory SmsMessage.fromNativeMap(Map<dynamic, dynamic> map) {
    final extracted = map['extractedMetadata'];
    return SmsMessage(
      id: (map['id'] ?? '').toString(),
      nativeMessageId: map['nativeMessageId']?.toString(),
      sender: (map['sender'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((map['timestampMillis'] ?? 0) as num).toInt(),
      ),
      localRiskScore: ((map['localRiskScore'] ?? 0) as num).toDouble(),
      isFlagged: map['isFlagged'] == true,
      flags: List<String>.from(map['flags'] ?? const []),
      classification: (map['classification'] ?? 'safe').toString(),
      modelConfidence: (map['modelConfidence'] as num?)?.toDouble(),
      ruleScore: (map['ruleScore'] as num?)?.toDouble(),
      modelAvailable: map['modelAvailable'] == true,
      analysisSource: (map['analysisSource'] ?? 'android_rule_only').toString(),
      shouldEscalateToCloud: map['shouldEscalateToCloud'] == true,
      cloudEscalationReason: map['cloudEscalationReason']?.toString(),
      sanitizedPreview: map['sanitizedPreview']?.toString(),
      summary: map['summary']?.toString(),
      extractedMetadata: extracted is Map
          ? SmsMetadata.fromJson(Map<String, dynamic>.from(extracted))
          : null,
    );
  }

  SmsMessage copyWith({
    String? id,
    String? nativeMessageId,
    String? sender,
    String? body,
    DateTime? timestamp,
    double? localRiskScore,
    bool? isFlagged,
    List<String>? flags,
    String? classification,
    double? modelConfidence,
    double? ruleScore,
    bool? modelAvailable,
    String? analysisSource,
    bool? shouldEscalateToCloud,
    String? cloudEscalationReason,
    String? sanitizedPreview,
    String? summary,
    SmsMetadata? extractedMetadata,
  }) => SmsMessage(
    id: id ?? this.id,
    nativeMessageId: nativeMessageId ?? this.nativeMessageId,
    sender: sender ?? this.sender,
    body: body ?? this.body,
    timestamp: timestamp ?? this.timestamp,
    localRiskScore: localRiskScore ?? this.localRiskScore,
    isFlagged: isFlagged ?? this.isFlagged,
    flags: flags ?? this.flags,
    classification: classification ?? this.classification,
    modelConfidence: modelConfidence ?? this.modelConfidence,
    ruleScore: ruleScore ?? this.ruleScore,
    modelAvailable: modelAvailable ?? this.modelAvailable,
    analysisSource: analysisSource ?? this.analysisSource,
    shouldEscalateToCloud: shouldEscalateToCloud ?? this.shouldEscalateToCloud,
    cloudEscalationReason: cloudEscalationReason ?? this.cloudEscalationReason,
    sanitizedPreview: sanitizedPreview ?? this.sanitizedPreview,
    summary: summary ?? this.summary,
    extractedMetadata: extractedMetadata ?? this.extractedMetadata,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RECIPIENT — with dynamic relationship profile
// ─────────────────────────────────────────────────────────────────────────────

class Recipient {
  final String name;
  final String upiId;

  /// Optional phone number — used for SMS sender correlation
  final String? phone;

  final bool isMerchant;
  final int transactionCount;
  final double usualAmount;
  final int trustScore; // 0-100

  /// Rolling list of last 5 transaction amounts (newest first)
  final List<double> recentAmounts;

  /// Date of the most recent transaction with this recipient
  final DateTime? lastTransactionDate;

  /// Count of times this recipient appeared in a flagged interaction
  final int flaggedCount;

  Recipient({
    required this.name,
    required this.upiId,
    this.phone,
    this.isMerchant = false,
    this.transactionCount = 0,
    this.usualAmount = 0,
    this.trustScore = 50,
    this.recentAmounts = const [],
    this.lastTransactionDate,
    this.flaggedCount = 0,
  });

  /// Returns true if [query] matches the UPI ID or phone number
  bool matches(String query) {
    final q = query.toLowerCase().replaceAll(RegExp(r'[\s\-+]'), '');
    final upi = upiId.toLowerCase();
    final ph = (phone ?? '').replaceAll(RegExp(r'[\s\-+]'), '');
    return upi == q || upi.contains(q) || (ph.isNotEmpty && (ph == q || ph.contains(q) || q.contains(ph)));
  }

  Recipient copyWith({
    String? name,
    String? upiId,
    String? phone,
    bool? isMerchant,
    int? transactionCount,
    double? usualAmount,
    int? trustScore,
    List<double>? recentAmounts,
    DateTime? lastTransactionDate,
    int? flaggedCount,
  }) => Recipient(
    name: name ?? this.name,
    upiId: upiId ?? this.upiId,
    phone: phone ?? this.phone,
    isMerchant: isMerchant ?? this.isMerchant,
    transactionCount: transactionCount ?? this.transactionCount,
    usualAmount: usualAmount ?? this.usualAmount,
    trustScore: trustScore ?? this.trustScore,
    recentAmounts: recentAmounts ?? this.recentAmounts,
    lastTransactionDate: lastTransactionDate ?? this.lastTransactionDate,
    flaggedCount: flaggedCount ?? this.flaggedCount,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'upiId': upiId,
    'phone': phone,
    'isMerchant': isMerchant,
    'transactionCount': transactionCount,
    'usualAmount': usualAmount,
    'trustScore': trustScore,
    'recentAmounts': recentAmounts,
    'lastTransactionDate': lastTransactionDate?.toIso8601String(),
    'flaggedCount': flaggedCount,
  };

  factory Recipient.fromJson(Map<String, dynamic> json) => Recipient(
    name: json['name'] ?? '',
    upiId: json['upiId'] ?? '',
    phone: json['phone'],
    isMerchant: json['isMerchant'] ?? false,
    transactionCount: json['transactionCount'] ?? 0,
    usualAmount: (json['usualAmount'] ?? 0).toDouble(),
    trustScore: json['trustScore'] ?? 50,
    recentAmounts: (json['recentAmounts'] as List? ?? [])
        .map((v) => (v as num).toDouble()).toList(),
    lastTransactionDate: json['lastTransactionDate'] != null
        ? DateTime.tryParse(json['lastTransactionDate'])
        : null,
    flaggedCount: json['flaggedCount'] ?? 0,
  );
}

class RiskResult {
  final int score;
  final String interventionLevel; // none, soft, strong, critical
  final String interventionMessage;
  final List<RiskFactor> factors;
  final Map<String, double> breakdown;

  RiskResult({
    required this.score,
    required this.interventionLevel,
    required this.interventionMessage,
    required this.factors,
    required this.breakdown,
  });

  factory RiskResult.fromJson(Map<String, dynamic> json) => RiskResult(
    score: json['score'] ?? 0,
    interventionLevel: json['intervention_level'] ?? 'none',
    interventionMessage: json['intervention_message'] ?? '',
    factors: (json['factors'] as List? ?? [])
        .map((f) => RiskFactor.fromJson(f))
        .toList(),
    breakdown: Map<String, double>.fromEntries(
      (json['breakdown'] as Map? ?? {}).entries
          .where((e) => e.value is num)
          .map((e) => MapEntry(e.key as String, (e.value as num).toDouble())),
    ),
  );
}

class RiskFactor {
  final String factor;
  final String description;
  final int contribution;
  final String severity;

  RiskFactor({
    required this.factor,
    required this.description,
    required this.contribution,
    required this.severity,
  });

  factory RiskFactor.fromJson(Map<String, dynamic> json) => RiskFactor(
    factor: json['factor'] ?? '',
    description: json['description'] ?? '',
    contribution: json['contribution'] ?? 0,
    severity: json['severity'] ?? 'low',
  );

  Map<String, dynamic> toJson() => {
    'factor': factor,
    'description': description,
    'contribution': contribution,
    'severity': severity,
  };
}

class SmsAnalysisResult {
  final int riskScore;
  final String classification;
  final String summary;
  final String explanation;
  final List<HighlightedWord> highlightedWords;
  final Map<String, dynamic> riskFactors;

  SmsAnalysisResult({
    required this.riskScore,
    required this.classification,
    required this.summary,
    required this.explanation,
    required this.highlightedWords,
    required this.riskFactors,
  });

  factory SmsAnalysisResult.fromJson(Map<String, dynamic> json) =>
      SmsAnalysisResult(
        riskScore: json['risk_score'] ?? 0,
        classification: json['classification'] ?? 'safe',
        summary: json['summary'] ?? '',
        explanation: json['explanation'] ?? '',
        highlightedWords: (json['highlighted_words'] as List? ?? [])
            .map((w) => HighlightedWord.fromJson(w))
            .toList(),
        riskFactors: json['risk_factors'] ?? {},
      );
}

class HighlightedWord {
  final String word;
  final int start;
  final int end;
  final String category;
  final String severity;

  HighlightedWord({
    required this.word,
    required this.start,
    required this.end,
    required this.category,
    required this.severity,
  });

  factory HighlightedWord.fromJson(Map<String, dynamic> json) =>
      HighlightedWord(
        word: json['word'] ?? '',
        start: json['start'] ?? 0,
        end: json['end'] ?? 0,
        category: json['category'] ?? '',
        severity: json['severity'] ?? 'low',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLOUD REVIEW RESULT — cloud LLM second-opinion on uncertain TinyBERT detections
// (Amazon Bedrock — gpt-oss-120b)
// ─────────────────────────────────────────────────────────────────────────────

class CloudReviewResult {
  /// Cloud model's overall fraud risk score, 0–100.
  final int riskScore;

  /// Detailed fraud category (e.g. 'otp_theft', 'phishing', 'safe').
  final String classification;

  /// Recommended intervention level: none | soft | strong | critical.
  final String interventionLevel;

  /// 2–3 sentence plain-English explanation of the key indicators.
  final String explanation;

  /// Concise list of specific fraud signals found in the message.
  final List<String> keyIndicators;

  /// The cloud model's self-reported confidence, 0.0–1.0.
  final double confidence;

  /// Which cloud model variant was used.
  final String modelUsed;

  const CloudReviewResult({
    required this.riskScore,
    required this.classification,
    required this.interventionLevel,
    required this.explanation,
    required this.keyIndicators,
    required this.confidence,
    this.modelUsed = 'bedrock-gpt-oss-120b',
  });

  factory CloudReviewResult.fromJson(Map<String, dynamic> json) =>
      CloudReviewResult(
        riskScore: (json['risk_score'] as num? ?? 0).toInt().clamp(0, 100),
        classification: (json['classification'] ?? 'safe').toString(),
        interventionLevel: (json['intervention_level'] ?? 'none').toString(),
        explanation: (json['explanation'] ?? '').toString(),
        keyIndicators: List<String>.from(json['key_indicators'] ?? const []),
        confidence: (json['confidence'] as num? ?? 0.0).toDouble().clamp(0.0, 1.0),
        modelUsed: (json['model_used'] ?? 'bedrock-gpt-oss-120b').toString(),
      );
}
