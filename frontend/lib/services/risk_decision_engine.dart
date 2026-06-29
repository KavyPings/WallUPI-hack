import '../models/models.dart';

/// Single source of truth for all risk threshold values.
/// Changing a value here affects ALL routing decisions across the entire app.
class RiskThresholds {
  // Tier boundaries (inclusive lower, inclusive upper)
  static const int safeMax = 49; // 0–49 → safe
  static const int softMin = 50; // 50–79 → soft warning
  static const int softMax = 79;
  static const int strongMin = 80; // 80–94 → strong warning
  static const int strongMax = 94;
  static const int criticalMin = 95; // 95–100 → critical intervention

  // Critical delay countdown (seconds)
  static const int criticalDelaySeconds = 10;

  // Relationship intelligence — score REDUCTIONS applied to final score
  static const int frequentRecipientBonus = 15; // txnCount >= 10
  static const int familiarRecipientBonus = 8; // txnCount >= 3
  static const int verifiedMerchantBonus = 10; // isMerchant == true
  static const int highTrustBonus = 12; // trustScore >= 85
  static const int mediumTrustBonus = 6; // trustScore >= 70

  // Local fallback scoring weights
  static const int newRecipientPenalty = 25;
  static const int limitedHistoryPenalty = 10;  // 1–2 transactions (NOT zero — zero is "new recipient")
  static const int highAmountMultiplierThreshold = 3; // 3x avg = penalty
  static const int highAmountPenalty = 20;
  static const int verySuspiciousSmsPenalty = 30;
  static const int moderateSmsPenalty = 18;
  static const int unknownCallerPenalty = 30;
  static const int knownCallerPenalty = 20;
  static const int qrTriggerPenalty = 8;
  static const int lowTrustPenalty = 15; // trustScore < 30

  /// Score multiplier when the recipient is a Registered UPI Business (NPCI-verified).
  /// Applied to the final score AFTER trust reduction.
  /// 0.5 = halves the risk score — verified businesses carry inherent trust.
  static const double registeredUpiIdDampener = 0.5;
}

/// Centralized, deterministic risk routing engine.
///
/// All routing decisions flow through here. The UI only renders the result —
/// it never computes risk levels independently.
class RiskDecisionEngine {
  /// Classify a raw score (0–100) into a [RiskLevel] tier.
  static RiskLevel classifyScore(int score) {
    if (score >= RiskThresholds.criticalMin) return RiskLevel.critical;
    if (score >= RiskThresholds.strongMin) return RiskLevel.strong;
    if (score >= RiskThresholds.softMin) return RiskLevel.soft;
    return RiskLevel.safe;
  }

  /// Human-readable label for a risk level.
  static String levelLabel(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:
        return 'Safe';
      case RiskLevel.soft:
        return 'Caution';
      case RiskLevel.strong:
        return 'High Risk';
      case RiskLevel.critical:
        return 'Critical';
    }
  }

  /// Returns the short intervention message for a level.
  static String levelMessage(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:
        return 'Transaction appears safe';
      case RiskLevel.soft:
        return 'Some risk factors detected — please review before proceeding';
      case RiskLevel.strong:
        return 'High risk detected — confirmation required before proceeding';
      case RiskLevel.critical:
        return 'Critical fraud risk — transaction paused for your safety';
    }
  }

  /// Converts a [RiskLevel] to the string used by the backend/model.
  static String levelToString(RiskLevel level) {
    switch (level) {
      case RiskLevel.safe:
        return 'none';
      case RiskLevel.soft:
        return 'soft';
      case RiskLevel.strong:
        return 'strong';
      case RiskLevel.critical:
        return 'critical';
    }
  }

  /// Converts a backend intervention level string to a [RiskLevel].
  static RiskLevel levelFromString(String s) {
    switch (s) {
      case 'critical':
        return RiskLevel.critical;
      case 'strong':
        return RiskLevel.strong;
      case 'soft':
        return RiskLevel.soft;
      default:
        return RiskLevel.safe;
    }
  }

  /// Returns true when the recipient's relationship history qualifies for
  /// a score reduction (trusted/frequent recipient).
  static bool qualifiesForTrustReduction(Recipient recipient) {
    return recipient.transactionCount >= 3 || recipient.trustScore >= 70;
  }

  /// Computes how many points to subtract from the raw score for a trusted
  /// recipient. Returns 0 if no reduction applies.
  static int computeTrustReduction(Recipient recipient) {
    int reduction = 0;
    if (recipient.transactionCount >= 10) {
      reduction += RiskThresholds.frequentRecipientBonus;
    } else if (recipient.transactionCount >= 3) {
      reduction += RiskThresholds.familiarRecipientBonus;
    }
    if (recipient.isMerchant) {
      reduction += RiskThresholds.verifiedMerchantBonus;
    }
    if (recipient.trustScore >= 85) {
      reduction += RiskThresholds.highTrustBonus;
    } else if (recipient.trustScore >= 70) {
      reduction += RiskThresholds.mediumTrustBonus;
    }
    return reduction;
  }

  /// Returns the top contributing factors sorted by contribution descending,
  /// along with their percentage of total contribution for explainability.
  static List<Map<String, dynamic>> getTopFactorsWithPercentage(
    List<RiskFactor> factors,
  ) {
    if (factors.isEmpty) return [];
    final total = factors.fold(0, (sum, f) => sum + f.contribution);
    if (total == 0) return [];

    return factors.map((f) {
      final pct = ((f.contribution / total) * 100).round();
      return {
        'factor': f,
        'percentage': pct,
      };
    }).toList();
  }

  /// Builds a [RiskResult] using the local deterministic scorer.
  /// Used as fallback when the backend is unreachable.
  ///
  /// This mirrors the backend weighted logic so offline scores are consistent.
  static RiskResult buildLocalRiskResult({
    required double amount,
    required double userAvgAmount,
    required bool isNewRecipient,
    required bool hasSuspiciousSms,
    required int smsRiskScore, // 0–100
    required bool isOnCall,
    required bool isUnknownCaller,
    required bool triggeredByQr,
    String recipientUpiId = '',
    String recipientName = '',
    String smsBody = '',
    String smsSender = '',
    int transactionCountWithRecipient = 0,
    double usualAmountWithRecipient = 0,
    int recipientTrustScore = 50,
    bool isMerchant = false,
    int smsAgeMinutes = 0,
    bool isRegisteredUpiId = false,
  }) {
    int score = 0;
    final List<RiskFactor> factors = [];

    // ── 0. RELATIONSHIP TRUST TIER — scales ALL context signals ────────────────
    // Strangers trigger full alarm; established relationships dampen it.
    final String relTrustTier;
    if (isNewRecipient) {
      relTrustTier = 'none';
    } else if (transactionCountWithRecipient >= 10 && recipientTrustScore >= 85) {
      relTrustTier = 'high';
    } else if (transactionCountWithRecipient >= 3 && recipientTrustScore >= 70) {
      relTrustTier = 'medium';
    } else {
      relTrustTier = 'low';
    }
    const contextScaleMap = {'none': 1.0, 'low': 0.80, 'medium': 0.55, 'high': 0.30};
    final contextScale = contextScaleMap[relTrustTier]!;

    // ── 1. RECIPIENT PROFILE ────────────────────────────────────────────────
    if (isNewRecipient) {
      score += RiskThresholds.newRecipientPenalty;
      factors.add(RiskFactor(
        factor: 'New Recipient',
        description: 'You have never sent money to this person before',
        contribution: RiskThresholds.newRecipientPenalty,
        severity: 'high',
      ));
    }

    if (recipientTrustScore < 30) {
      score += RiskThresholds.lowTrustPenalty;
      factors.add(RiskFactor(
        factor: 'Low Trust Recipient',
        description: 'This recipient has a very low trust score',
        contribution: RiskThresholds.lowTrustPenalty,
        severity: 'high',
      ));
    }

    // ── 2. RELATIONSHIP HISTORY ─────────────────────────────────────────────
    // NOTE: transactionCount == 0 is already captured by "New Recipient" above.
    // Only add "Limited History" when recipient EXISTS but has few transactions.
    if (!isNewRecipient && transactionCountWithRecipient < 3) {
      score += RiskThresholds.limitedHistoryPenalty;
      factors.add(RiskFactor(
        factor: 'Limited History',
        description:
            'Only $transactionCountWithRecipient prior transaction(s) with this recipient',
        contribution: RiskThresholds.limitedHistoryPenalty,
        severity: 'medium',
      ));
    }

    // ── 3. AMOUNT ANOMALY ───────────────────────────────────────────────────
    if (userAvgAmount > 0) {
      final ratio = amount / userAvgAmount;
      if (ratio > 5) {
        score += RiskThresholds.highAmountPenalty;
        factors.add(RiskFactor(
          factor: 'Amount Anomaly',
          description:
              '₹${amount.toStringAsFixed(0)} is ${ratio.toStringAsFixed(1)}x your average',
          contribution: RiskThresholds.highAmountPenalty,
          severity: 'high',
        ));
      } else if (ratio > 3) {
        const contrib = 14;
        score += contrib;
        factors.add(RiskFactor(
          factor: 'High Amount',
          description:
              '₹${amount.toStringAsFixed(0)} is above your typical range',
          contribution: contrib,
          severity: 'medium',
        ));
      }
    }

    // ── 4. SUSPICIOUS SMS ───────────────────────────────────────────────────
    // Hoisted so sections 5 and 8 can reference correlation state
    bool smsCorrelated = false;
    bool senderMatch = false;

    if (hasSuspiciousSms) {

      final lowerInput = recipientUpiId.toLowerCase();
      final lowerSender = smsSender.toLowerCase().replaceAll(RegExp(r'[\s\-+]'), '');
      final lowerInputClean = lowerInput.replaceAll(RegExp(r'[\s\-+]'), '');

      // 1. SENDER MATCH — strongest: you are paying the exact number that sent the scam
      if (lowerSender.isNotEmpty && lowerInputClean.isNotEmpty) {
        if (lowerSender == lowerInputClean ||
            lowerSender.contains(lowerInputClean) ||
            lowerInputClean.contains(lowerSender)) {
          smsCorrelated = true;
          senderMatch = true;
        }
      }

      // 2. BODY MATCH — secondary: recipient appears in the SMS text
      if (!smsCorrelated && smsBody.isNotEmpty) {
        final lowerSms = smsBody.toLowerCase();
        final smsBodyClean = lowerSms.replaceAll(RegExp(r'[\s\-+]'), '');
        if ((lowerSms.contains(lowerInputClean) || smsBodyClean.contains(lowerInputClean)) && lowerInputClean.length >= 5) {
          smsCorrelated = true;
        }
        // UPI handle check
        if (!smsCorrelated && lowerInput.contains('@')) {
          final handle = lowerInput.split('@').first;
          if (handle.length > 2 && lowerSms.contains(handle)) {
            smsCorrelated = true;
          }
        }
        // Recipient name check
        if (!smsCorrelated && recipientName.isNotEmpty) {
          final nameParts = recipientName.toLowerCase().split(' ')
              .where((w) => w.length > 3);
          for (final part in nameParts) {
            if (lowerSms.contains(part)) { smsCorrelated = true; break; }
          }
        }
        // Amount check
        if (!smsCorrelated && lowerSms.contains(amount.toInt().toString())) {
          smsCorrelated = true;
        }
      }

      int smsContrib;
      if (smsCorrelated) {
        smsContrib = senderMatch
            ? (smsRiskScore * 0.55).round().clamp(0, 45)
            : (smsRiskScore * 0.45).round().clamp(0, 40);
      } else {
        smsContrib = (smsRiskScore * 0.08).round().clamp(0, 7);
      }

      // Decay stale SMS (older than 60 min) — only for unrelated
      if (!smsCorrelated && smsAgeMinutes > 60) {
        smsContrib = (smsContrib * 0.6).round();
      }

      if (smsContrib > 0) {
        score += smsContrib;
        final corrNote = senderMatch
            ? ' — sender matches this recipient!'
            : smsCorrelated
                ? ' — matches this transaction'
                : ' — unrelated to this recipient';
        factors.add(RiskFactor(
          factor: 'Suspicious SMS Detected',
          description:
              'A flagged SMS is active on your device (risk: $smsRiskScore%)$corrNote',
          contribution: smsContrib,
          severity: smsCorrelated ? 'high' : 'medium',
        ));
      }

      // QR + correlated SMS compound risk
      if (triggeredByQr && smsCorrelated) {
        const compoundContrib = 15;
        score += compoundContrib;
        factors.add(RiskFactor(
          factor: 'QR + Suspicious SMS',
          description:
              'QR payment initiated while a suspicious SMS targets this transaction',
          contribution: compoundContrib,
          severity: 'high',
        ));
      }
    }

    // ── 5. ACTIVE CALL ──────────────────────────────────────────────────────
    if (isOnCall) {
      final callContrib = ((isUnknownCaller
          ? RiskThresholds.unknownCallerPenalty
          : RiskThresholds.knownCallerPenalty) * contextScale).round();
      score += callContrib;
      factors.add(RiskFactor(
        factor: isUnknownCaller ? 'Unknown Caller on Line' : 'Active Phone Call',
        description: isUnknownCaller
            ? 'Paying while on a call with an unknown number — high scam risk'
            : 'You are currently on a phone call while making a payment',
        contribution: callContrib,
        severity: isUnknownCaller ? 'high' : 'medium',
      ));

      // Call + new recipient compound risk
      if (isNewRecipient) {
        final compoundContrib = (15 * contextScale).round();
        score += compoundContrib;
        factors.add(RiskFactor(
          factor: 'Call + New Recipient',
          description:
              'Paying a first-time recipient while on a call — elevated scam risk',
          contribution: compoundContrib,
          severity: 'high',
        ));
      }

      // Call + correlated SMS = classic social engineering pattern
      if (smsCorrelated) {
        if (senderMatch) {
          final callerSmsBoost = (35 * contextScale).round();
          score += callerSmsBoost;
          factors.add(RiskFactor(
            factor: 'Caller Sent Suspicious SMS',
            description: 'The number calling you also sent the suspicious SMS — active impersonation scam',
            contribution: callerSmsBoost,
            severity: 'high',
          ));
        } else {
          final callSmsBoost = ((isUnknownCaller ? 28 : 20) * contextScale).round();
          score += callSmsBoost;
          factors.add(RiskFactor(
            factor: 'Call + Linked Suspicious SMS',
            description: 'You are on a call while a suspicious SMS matches this payment — classic scam pattern',
            contribution: callSmsBoost,
            severity: 'high',
          ));
        }
      }
    }

    // ── 6. QR TRIGGER (standalone) ──────────────────────────────────────────
    if (triggeredByQr && !hasSuspiciousSms) {
      score += RiskThresholds.qrTriggerPenalty;
      factors.add(RiskFactor(
        factor: 'QR Code Trigger',
        description: 'Payment was initiated via QR code scan',
        contribution: RiskThresholds.qrTriggerPenalty,
        severity: 'low',
      ));
    }

    // ── 7. RELATIONSHIP TRUST REDUCTION ────────────────────────────────────
    // Apply AFTER all penalty additions — trusted recipients reduce final score
    int trustReduction = 0;
    if (!isNewRecipient) {
      if (transactionCountWithRecipient >= 10) {
        trustReduction += RiskThresholds.frequentRecipientBonus;
      } else if (transactionCountWithRecipient >= 3) {
        trustReduction += RiskThresholds.familiarRecipientBonus;
      }
      if (isMerchant) trustReduction += RiskThresholds.verifiedMerchantBonus;
      if (recipientTrustScore >= 85) {
        trustReduction += RiskThresholds.highTrustBonus;
      } else if (recipientTrustScore >= 70) {
        trustReduction += RiskThresholds.mediumTrustBonus;
      }
    }

    // Correlated SMS weakens the protective value of relationship trust.
    if (smsCorrelated) trustReduction = trustReduction ~/ 2;

    final rawScore = score;
    score = (score - trustReduction).clamp(0, 100);

    // ── 8. COMPOUND DANGER OVERRIDE — hard floors matching backend logic ─────
    // The additive local engine may underscore dangerous combinations because
    // it lacks the backend's section weighting. Apply the same floors here.
    if (isOnCall && smsCorrelated) {
      if (isNewRecipient) {
        final target = senderMatch ? 97 : 95;
        if (score < target) score = target;
      } else if (score < 82 && (relTrustTier == 'none' || relTrustTier == 'low')) {
        score = 82;
      }
    }

    // ── 8b. SMS-ONLY CORRELATED FLOOR — no active call needed ──────────────
    // Guarantees at minimum a SOFT warning when the suspicious SMS explicitly
    // names the recipient, regardless of relationship history.
    if (smsCorrelated && !isOnCall) {
      if (senderMatch && score < 72) {
        final boost = 72 - score;
        score = 72;
        factors.add(RiskFactor(
          factor: 'Recipient Sent Suspicious SMS',
          description: 'The person you are paying sent you a suspicious message — strong fraud signal',
          contribution: boost,
          severity: 'high',
        ));
      } else if (!senderMatch && score < 55) {
        final boost = 55 - score;
        score = 55;
        factors.add(RiskFactor(
          factor: 'Suspicious SMS Linked to Recipient',
          description: 'This recipient is explicitly mentioned in a suspicious message — review before paying',
          contribution: boost,
          severity: 'medium',
        ));
      }
    }

    // ── 9. REGISTERED UPI BUSINESS DAMPENER ────────────────────────────────
    // Applied LAST — verified NPCI-registered business IDs carry systemic trust
    // that reduces the impact of all other flags (new recipient, amount, etc.)
    int dampenerReduction = 0;
    if (isRegisteredUpiId) {
      final dampened = (score * RiskThresholds.registeredUpiIdDampener).round();
      dampenerReduction = score - dampened;
      score = dampened;
      factors.add(RiskFactor(
        factor: 'Registered UPI Business',
        description: 'This recipient is a verified NPCI-registered business — risk halved',
        contribution: -dampenerReduction, // negative = score reduction
        severity: 'low',
      ));
    }

    // Sort factors: positive contributions descending, dampener last
    factors.sort((a, b) {
      if (a.contribution < 0) return 1;
      if (b.contribution < 0) return -1;
      return b.contribution.compareTo(a.contribution);
    });

    final level = classifyScore(score);

    return RiskResult(
      score: score,
      interventionLevel: levelToString(level),
      interventionMessage: levelMessage(level),
      factors: factors,
      breakdown: {
        'raw_score': rawScore.toDouble(),
        'trust_reduction': trustReduction.toDouble(),
        'registered_upi_dampener': dampenerReduction.toDouble(),
        'final_score': score.toDouble(),
      },
    );
  }
}
