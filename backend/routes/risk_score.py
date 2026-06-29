"""
/risk-score — Transaction Risk Scoring Endpoint
Computes a weighted suspicion score for a transaction based on multiple factors.

Threshold mapping (centralized):
  SAFE:     0  – 49  (no intervention)
  SOFT:     50 – 79  (lightweight warning, no friction)
  STRONG:   80 – 94  (full warning + checkbox required)
  CRITICAL: 95 – 100 (10-second delay + checkbox required)
"""

from flask import Blueprint, request, jsonify

risk_bp = Blueprint('risk', __name__)

# Community-intelligence models — imported lazily so the route file stays
# functional even before the DB is initialised on first import.
def _get_community_data(recipient_upi_id: str, user_upi_id: str):
    """Query spam flags, recipient profile, and relationship from SQLite.
    Returns (spam_count, recipient_profile, relationship_profile).
    All failures degrade gracefully to (0, None, None).
    """
    try:
        from models import SpamFlag, UserProfile, RelationshipProfile
        spam_count = 0
        recipient_profile = None
        relationship_profile = None
        if recipient_upi_id:
            spam_count = SpamFlag.query.filter(
                (SpamFlag.flagged_upi_id == recipient_upi_id) |
                (SpamFlag.flagged_phone == recipient_upi_id)
            ).count()
            recipient_profile = UserProfile.query.get(recipient_upi_id)
        if user_upi_id and recipient_upi_id:
            from models import RelationshipProfile
            relationship_profile = RelationshipProfile.query.filter_by(
                user_upi_id=user_upi_id,
                counterpart_upi_id=recipient_upi_id,
            ).first()
        return spam_count, recipient_profile, relationship_profile
    except Exception:
        return 0, None, None

# ==========================================================================
# CENTRALIZED THRESHOLD CONSTANTS
# ==========================================================================
THRESHOLD_SAFE_MAX = 49
THRESHOLD_SOFT_MIN = 50
THRESHOLD_SOFT_MAX = 79
THRESHOLD_STRONG_MIN = 80
THRESHOLD_STRONG_MAX = 94
THRESHOLD_CRITICAL_MIN = 95

CRITICAL_DELAY_SECONDS = 10


def classify_score(score):
    """Return the intervention level string for a given score."""
    if score >= THRESHOLD_CRITICAL_MIN:
        return 'critical'
    if score >= THRESHOLD_STRONG_MIN:
        return 'strong'
    if score >= THRESHOLD_SOFT_MIN:
        return 'soft'
    return 'none'


def intervention_message(level):
    messages = {
        'critical': 'Transaction paused for 10 seconds — critical fraud risk detected',
        'strong':   'High risk detected — confirmation required before proceeding',
        'soft':     'Some risk factors detected — please review before proceeding',
        'none':     'Transaction appears safe',
    }
    return messages.get(level, 'Transaction appears safe')


def compute_risk_score(data):
    """
    Compute transaction suspicion score (0–100) using weighted factors.

    Weight groups:
      User Profile:      25%  (transaction patterns, amount anomaly)
      Recipient Profile: 30%  (new vs existing, type, trust)
      Relationship:      20%  (history between user and recipient)
      Context:           25%  (QR, SMS, call state, navigation)

    SMS Correlation Intelligence:
      SMS penalty is scaled by how closely the SMS content relates to
      the current transaction (recipient UPI, name, amount). A generic
      KYC scam SMS that doesn't mention the recipient gets ~30% penalty;
      a correlated SMS gets the full penalty.

    Relationship Intelligence:
      After all penalties are summed, trusted recipients receive a score
      REDUCTION based on transaction history and trust score.

    Key design decisions:
      - "New Recipient" (recipient profile) already covers transactionCount==0.
        "No Transaction History" was removed as it was redundant.
        "Limited History" only fires for recipients with 1–2 transactions.
    """
    score = 0.0
    factors = []

    # Pull community data early so section 2b can use it
    recipient_upi_id_raw = data.get('recipient_upi_id', '')
    user_upi_id_raw = data.get('user_upi_id', '')
    spam_count, _backend_recipient, _backend_rel = _get_community_data(
        recipient_upi_id_raw.lower().strip(),
        user_upi_id_raw.lower().strip(),
    )

    # =========================================================================
    # 0. RELATIONSHIP TRUST TIER — scales ALL context signals proportionally.
    # Strangers trigger full alarm; established relationships dampen it.
    # =========================================================================
    _txn_count_pre = data.get('transaction_count_with_recipient', 0)
    _trust_pre     = data.get('recipient_trust_score', 50)
    _new_pre       = data.get('is_new_recipient', True)

    if _new_pre:
        _rel_trust_tier = 'none'
    elif _txn_count_pre >= 10 and _trust_pre >= 85:
        _rel_trust_tier = 'high'
    elif _txn_count_pre >= 3 and _trust_pre >= 70:
        _rel_trust_tier = 'medium'
    else:
        _rel_trust_tier = 'low'   # 1-2 txns or low trust score

    _context_scale = {'none': 1.0, 'low': 0.80, 'medium': 0.55, 'high': 0.30}[_rel_trust_tier]

    # =========================================================================
    # 1. USER PROFILE ANALYSIS (25% weight)
    # =========================================================================
    user_score = 0.0

    amount = data.get('amount', 0)
    user_avg_amount = data.get('user_avg_amount', 2000)
    typical_hour = data.get('typical_transaction_hour', 14)
    current_hour = data.get('current_hour', 12)

    # Amount deviation — separate if/elif so all tiers are reachable
    if user_avg_amount > 0:
        amount_ratio = amount / user_avg_amount
        if amount_ratio > 5:
            user_score += 25
            factors.append({
                'factor': 'Amount Anomaly',
                'description': f'₹{amount} is {amount_ratio:.1f}× your average of ₹{user_avg_amount}',
                'contribution': 25,
                'severity': 'high'
            })
        elif amount_ratio > 3:
            user_score += 18
            factors.append({
                'factor': 'Amount Deviation',
                'description': f'₹{amount} is {amount_ratio:.1f}× your average of ₹{user_avg_amount}',
                'contribution': 18,
                'severity': 'medium'
            })
        elif amount_ratio > 2:
            user_score += 10
            factors.append({
                'factor': 'Slightly High Amount',
                'description': f'₹{amount} is above your typical range',
                'contribution': 10,
                'severity': 'low'
            })

    # Large absolute amount — separate if/elif so >50k tier is reachable
    if amount > 50000:
        user_score += 15
        factors.append({
            'factor': 'Very Large Transaction',
            'description': f'₹{amount} is a very large amount',
            'contribution': 15,
            'severity': 'high'
        })
    elif amount > 25000:
        user_score += 8
        factors.append({
            'factor': 'Large Transaction',
            'description': f'₹{amount} is a significant amount',
            'contribution': 8,
            'severity': 'medium'
        })

    # Unusual time
    hour_diff = abs(current_hour - typical_hour)
    if hour_diff > 6 or current_hour < 6 or current_hour > 23:
        user_score += 10
        factors.append({
            'factor': 'Unusual Time',
            'description': f'Transaction at {current_hour}:00 — outside your typical hours',
            'contribution': 10,
            'severity': 'medium'
        })

    # =========================================================================
    # 2. RECIPIENT PROFILE (30% weight)
    # =========================================================================
    recipient_score = 0.0

    is_new_recipient = data.get('is_new_recipient', True)
    is_merchant = data.get('is_merchant', False)
    recipient_trust_score = data.get('recipient_trust_score', 50)

    if is_new_recipient:
        recipient_score += 25
        factors.append({
            'factor': 'New Recipient',
            'description': 'You have never sent money to this person before',
            'contribution': 25,
            'severity': 'high'
        })

    if not is_merchant and amount > 10000:
        recipient_score += 12
        factors.append({
            'factor': 'Individual (Not Merchant)',
            'description': 'Large payment to an individual, not a verified merchant',
            'contribution': 12,
            'severity': 'medium'
        })

    if recipient_trust_score < 30:
        recipient_score += 15
        factors.append({
            'factor': 'Low Trust Recipient',
            'description': f'This recipient has a low trust score ({recipient_trust_score}/100)',
            'contribution': 15,
            'severity': 'high'
        })

    # =========================================================================
    # 2b. COMMUNITY INTELLIGENCE — spam flags + backend profiles
    # =========================================================================

    if spam_count >= 5:
        recipient_score += 20
        factors.append({
            'factor': 'Highly Reported Recipient',
            'description': f'Flagged as spam/fraud by {spam_count} users',
            'contribution': 20,
            'severity': 'high',
        })
    elif spam_count >= 1:
        recipient_score += 10
        factors.append({
            'factor': 'Community Flagged',
            'description': f'Flagged by {spam_count} other user(s) as suspicious',
            'contribution': 10,
            'severity': 'medium',
        })

    if _backend_recipient and _backend_recipient.risk_tier == 'high':
        recipient_score += 15
        factors.append({
            'factor': 'High-Risk Recipient Profile',
            'description': 'This UPI ID has a history of high-risk transactions',
            'contribution': 15,
            'severity': 'high',
        })
    elif _backend_recipient and _backend_recipient.risk_tier == 'medium':
        recipient_score += 7
        factors.append({
            'factor': 'Elevated Risk Profile',
            'description': 'This UPI ID has shown some suspicious patterns',
            'contribution': 7,
            'severity': 'medium',
        })

    # =========================================================================
    # 3. RELATIONSHIP PROFILE (20% weight)
    # NOTE: "New Recipient" above covers transactionCount == 0.
    # "Limited History" only fires when recipient EXISTS but has few transactions.
    # =========================================================================
    relationship_score = 0.0

    transaction_count = data.get('transaction_count_with_recipient', 0)
    usual_amount = data.get('usual_amount_with_recipient', 0)

    if not is_new_recipient and transaction_count < 3:
        relationship_score += 10
        factors.append({
            'factor': 'Limited History',
            'description': f'Only {transaction_count} prior transaction(s) with this recipient',
            'contribution': 10,
            'severity': 'medium'
        })

    if usual_amount > 0 and amount > usual_amount * 3:
        relationship_score += 12
        factors.append({
            'factor': 'Unusual Amount for Recipient',
            'description': f'₹{amount} is much more than your usual ₹{usual_amount} to this person',
            'contribution': 12,
            'severity': 'medium'
        })

    if _backend_rel and _backend_rel.flagged_txn_count > 0:
        rel_flag_contrib = min(_backend_rel.flagged_txn_count * 8, 24)
        relationship_score += rel_flag_contrib
        factors.append({
            'factor': 'Flagged Transaction History',
            'description': f'{_backend_rel.flagged_txn_count} prior high-risk transaction(s) with this recipient',
            'contribution': rel_flag_contrib,
            'severity': 'high',
        })

    # =========================================================================
    # 4. CONTEXT (25% weight)
    # =========================================================================
    context_score = 0.0

    triggered_by_qr = data.get('triggered_by_qr', False)
    triggered_by_link = data.get('triggered_by_link', False)
    has_suspicious_sms = data.get('has_suspicious_sms', False)
    sms_risk_score = data.get('sms_risk_score', 0)
    sms_age_minutes = data.get('sms_age_minutes', 0)
    sms_body = data.get('sms_body', '').lower()
    sms_body_clean = sms_body.replace(' ', '').replace('-', '').replace('+', '')
    sms_sender = data.get('sms_sender', '').lower().replace(' ', '').replace('-', '').replace('+', '')
    is_on_call = data.get('is_on_call', False)
    is_unknown_caller = data.get('is_unknown_caller', False)
    is_registered_upi_id = data.get('is_registered_upi_id', False)
    sudden_navigation = data.get('sudden_navigation', False)

    # Recipient identifiers for SMS correlation check
    recipient_upi_id = data.get('recipient_upi_id', '').lower()
    recipient_name = data.get('recipient_name', '').lower()
    recipient_clean = recipient_upi_id.replace(' ', '').replace('-', '').replace('+', '')

    # ---- SMS Correlation Intelligence ----------------------------------------
    # Priority 1 — SENDER MATCH: paying the exact number that sent the scam SMS.
    #              This is the strongest possible fraud signal.
    # Priority 2 — BODY MATCH: recipient UPI/name/amount appears in SMS text.
    # No match    — ambient ambient risk only (generic KYC scam on device).
    sms_correlated = False
    sender_match = False

    if has_suspicious_sms:
        # 1. Sender match (normalize both to digits/letters only)
        if sms_sender and recipient_clean:
            if (sms_sender == recipient_clean or
                    sms_sender in recipient_clean or
                    recipient_clean in sms_sender):
                sms_correlated = True
                sender_match = True

        # 2. Body match
        if not sms_correlated and sms_body:
            if len(recipient_clean) >= 5 and (recipient_clean in sms_body or recipient_clean in sms_body_clean):
                sms_correlated = True
            if not sms_correlated:
                upi_parts = [p for p in recipient_upi_id.split('@') if len(p) > 2]
                for part in upi_parts:
                    if part in sms_body:
                        sms_correlated = True
                        break
            if not sms_correlated and recipient_name:
                name_parts = [w for w in recipient_name.split() if len(w) > 3]
                for part in name_parts:
                    if part in sms_body:
                        sms_correlated = True
                        break
            if not sms_correlated and str(int(amount)) in sms_body:
                sms_correlated = True

    if has_suspicious_sms:
        # Scoring tiers:
        #   sender_match  → pay the exact scam sender → very high (up to 40)
        #   body_match    → recipient mentioned in SMS → high (up to 35)
        #   unrelated     → ambient risk only          → low (up to 8)
        if sms_correlated:
            if sender_match:
                sms_contrib = min(int(sms_risk_score * 0.55), 45)
            else:
                sms_contrib = min(int(sms_risk_score * 0.45), 40)
        else:
            sms_contrib = min(int(sms_risk_score * 0.08), 7)
            # Decay stale unrelated SMS
            if sms_age_minutes > 60:
                sms_contrib = int(sms_contrib * 0.6)

        if sms_contrib > 0:
            context_score += sms_contrib
            corr_note = (
                ' — sender matches this recipient!' if sender_match
                else ' — matches this transaction' if sms_correlated
                else ' — unrelated to this recipient'
            )
            factors.append({
                'factor': 'Suspicious SMS Detected',
                'description': f'A suspicious SMS is active (risk: {sms_risk_score}%){corr_note}',
                'contribution': sms_contrib,
                'severity': 'high' if sms_correlated else 'medium'
            })

        # QR + correlated SMS = compound risk
        if triggered_by_qr and sms_correlated:
            context_score += 15
            factors.append({
                'factor': 'QR + Suspicious SMS',
                'description': 'QR payment while suspicious SMS targets this transaction',
                'contribution': 15,
                'severity': 'high'
            })


    elif triggered_by_qr:
        context_score += 8
        factors.append({
            'factor': 'QR Code Trigger',
            'description': 'Payment initiated via QR code scan',
            'contribution': 8,
            'severity': 'low'
        })

    if triggered_by_link:
        context_score += 15
        factors.append({
            'factor': 'External Link Trigger',
            'description': 'Payment initiated via external link',
            'contribution': 15,
            'severity': 'high'
        })

    if is_on_call:
        call_boost = int((30 if is_unknown_caller else 20) * _context_scale)
        context_score += call_boost
        factors.append({
            'factor': 'Active Phone Call',
            'description': 'You are on a phone call' +
                           (' with an unknown number' if is_unknown_caller else ''),
            'contribution': call_boost,
            'severity': 'high'
        })
        if is_new_recipient:
            call_new_boost = int(15 * _context_scale)
            context_score += call_new_boost
            factors.append({
                'factor': 'Call + New Recipient',
                'description': 'Paying a first-time recipient while on a call — high scam risk',
                'contribution': call_new_boost,
                'severity': 'high'
            })

    # Call + correlated SMS = textbook social engineering: caller guides payment,
    # suspicious SMS targets the same recipient. Model this explicitly.
    if is_on_call and sms_correlated:
        if sender_match:
            caller_sms_boost = int(35 * _context_scale)
            context_score += caller_sms_boost
            factors.append({
                'factor': 'Caller Sent Suspicious SMS',
                'description': 'The number calling you also sent the suspicious SMS — active impersonation scam',
                'contribution': caller_sms_boost,
                'severity': 'high'
            })
        else:
            call_sms_boost = int((28 if is_unknown_caller else 20) * _context_scale)
            context_score += call_sms_boost
            factors.append({
                'factor': 'Call + Linked Suspicious SMS',
                'description': 'You are on a call while a suspicious SMS matches this payment — classic scam pattern',
                'contribution': call_sms_boost,
                'severity': 'high'
            })

    if sudden_navigation:
        context_score += 5
        factors.append({
            'factor': 'Sudden Navigation',
            'description': 'Quick navigation to payment screen detected',
            'contribution': 5,
            'severity': 'low'
        })

    # =========================================================================
    # COMPUTE WEIGHTED SCORE
    # =========================================================================
    weighted_score = (
        user_score * 0.25 +
        recipient_score * 0.30 +
        relationship_score * 0.20 +
        context_score * 0.25
    )

    raw_score = min(int(weighted_score * 2.5), 100)

    # =========================================================================
    # RELATIONSHIP TRUST REDUCTION (applied after raw score)
    # =========================================================================
    trust_reduction = 0

    if not is_new_recipient:
        if transaction_count >= 10:
            trust_reduction += 15
        elif transaction_count >= 3:
            trust_reduction += 8
        if is_merchant:
            trust_reduction += 10
        if recipient_trust_score >= 85:
            trust_reduction += 12
        elif recipient_trust_score >= 70:
            trust_reduction += 6

    # Correlated SMS weakens the protective value of relationship trust:
    # you should still be warned even about a "known" recipient when a suspicious
    # SMS explicitly names them as the payment target.
    if sms_correlated:
        trust_reduction = trust_reduction // 2

    final_score = max(0, raw_score - trust_reduction)

    # =========================================================================
    # COMPOUND DANGER OVERRIDE — hard floors for unambiguous scam patterns.
    # The weighted formula cannot fully capture these combinations because
    # context is capped at 25% weight. Override directly when the evidence
    # is clear enough to warrant a specific intervention tier.
    # =========================================================================
    if is_on_call and sms_correlated and is_new_recipient:
        target = 97 if sender_match else 95
        if final_score < target:
            boost = target - final_score
            final_score = target
            label = 'Caller is SMS Scammer + New Recipient' if sender_match else 'Call + SMS + New Recipient'
            desc = (
                'Caller sent the suspicious SMS and is the payment recipient — highest fraud signal'
                if sender_match else
                'Active call, suspicious SMS linked to this payment, and first-time recipient — critical scam pattern'
            )
            factors.append({
                'factor': label,
                'description': desc,
                'contribution': boost,
                'severity': 'high',
            })
    elif is_on_call and sms_correlated and _rel_trust_tier in ('none', 'low') and final_score < 82:
        boost = 82 - final_score
        final_score = 82
        factors.append({
            'factor': 'Call + Linked SMS Override',
            'description': 'Active call with a suspicious SMS linked to this payment — elevated to strong warning',
            'contribution': boost,
            'severity': 'high',
        })

    # SMS-ONLY CORRELATED FLOOR — no active call needed.
    # The call + SMS block above already guarantees 82/95/97 when on a call.
    # This block ensures a minimum SOFT warning whenever a suspicious SMS
    # explicitly names the recipient — regardless of relationship history.
    if sms_correlated and not is_on_call:
        if sender_match and final_score < 72:
            boost = 72 - final_score
            final_score = 72
            factors.append({
                'factor': 'Recipient Sent Suspicious SMS',
                'description': 'The person you are paying sent you a suspicious message — strong fraud signal',
                'contribution': boost,
                'severity': 'high',
            })
        elif not sender_match and final_score < 55:
            boost = 55 - final_score
            final_score = 55
            factors.append({
                'factor': 'Suspicious SMS Linked to Recipient',
                'description': 'This recipient is explicitly mentioned in a suspicious message — review before paying',
                'contribution': boost,
                'severity': 'medium',
            })

    # =========================================================================
    # REGISTERED UPI BUSINESS DAMPENER (applied last)
    # An NPCI-registered business ID carries inherent systemic trust.
    # All other risk factors are halved — the business has accountability.
    # =========================================================================
    registered_upi_dampener = 0
    if is_registered_upi_id:
        dampened = int(final_score * 0.5)
        registered_upi_dampener = final_score - dampened
        final_score = dampened
        factors.append({
            'factor': 'Registered UPI Business',
            'description': 'Recipient is a verified NPCI-registered business — risk score halved',
            'contribution': -registered_upi_dampener,
            'severity': 'low'
        })

    # Sort: positive contributions descending, dampener (negative) last
    factors.sort(key=lambda x: (x['contribution'] < 0, -x['contribution']))

    level = classify_score(final_score)

    return {
        'score': final_score,
        'factors': factors,
        'intervention_level': level,
        'intervention_message': intervention_message(level),
        'breakdown': {
            'user_profile': round(user_score * 0.25, 1),
            'recipient_profile': round(recipient_score * 0.30, 1),
            'relationship': round(relationship_score * 0.20, 1),
            'context': round(context_score * 0.25, 1),
            'raw_score': raw_score,
            'trust_reduction': trust_reduction,
            'registered_upi_dampener': registered_upi_dampener,
            'sms_correlated': sms_correlated,
        }
    }


@risk_bp.route('/risk-score', methods=['POST'])
def get_risk_score():
    """Compute risk score for a transaction."""
    data = request.get_json()

    if not data:
        return jsonify({'error': 'Request body is required'}), 400

    if 'amount' not in data:
        return jsonify({'error': 'amount is required'}), 400

    result = compute_risk_score(data)
    return jsonify(result)
