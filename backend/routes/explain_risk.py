"""
/explain-risk — Risk Explanation Endpoint
Generates human-readable explanations of why a transaction was flagged.
"""

from flask import Blueprint, request, jsonify

explain_bp = Blueprint('explain', __name__)


# Explanation templates
TEMPLATES = {
    'new_recipient': {
        'title': 'First-time Recipient',
        'icon': '👤',
        'explanation': 'You are sending money to someone you have never transacted with before. '
                      'Scammers often pose as unknown contacts to trick users into sending money.',
        'advice': 'Verify the recipient\'s identity through a trusted channel before proceeding.'
    },
    'high_amount': {
        'title': 'Unusually Large Amount',
        'icon': '💰',
        'explanation': 'This transaction amount is significantly higher than your usual spending pattern. '
                      'Large, unexpected payments are a common target for fraud.',
        'advice': 'Double-check the amount and confirm it matches what you intended to send.'
    },
    'suspicious_sms': {
        'title': 'Suspicious SMS Detected',
        'icon': '📩',
        'explanation': 'A recent SMS on your device was flagged as potentially fraudulent. '
                      'This transaction may be connected to that message.',
        'advice': 'Do NOT click any links or follow instructions from suspicious messages. '
                 'Verify the request directly with your bank.'
    },
    'active_call': {
        'title': 'Active Phone Call',
        'icon': '📞',
        'explanation': 'You are making this payment while on a phone call. '
                      'Scammers often stay on the line to guide victims through payments.',
        'advice': 'If someone on the phone is asking you to make a payment, hang up and verify independently.'
    },
    'unknown_caller': {
        'title': 'Unknown Caller on Line',
        'icon': '🚨',
        'explanation': 'You are paying while on a call with an unknown number. '
                      'This is a very common pattern in phone scams where the caller pressures '
                      'the victim to send money immediately.',
        'advice': 'Hang up immediately. No legitimate organization will ask you to make payments over the phone.'
    },
    'qr_trigger': {
        'title': 'QR Code Payment',
        'icon': '📷',
        'explanation': 'This payment was initiated by scanning a QR code. '
                      'Fraudulent QR codes can redirect payments to scammer accounts.',
        'advice': 'Verify the recipient details shown on screen match who you intend to pay.'
    },
    'link_trigger': {
        'title': 'External Link Payment',
        'icon': '🔗',
        'explanation': 'This payment was initiated from an external link. '
                      'Phishing links often disguise themselves as legitimate payment requests.',
        'advice': 'Never make payments through links received via SMS, email, or messaging apps.'
    },
    'unusual_time': {
        'title': 'Unusual Transaction Time',
        'icon': '🕐',
        'explanation': 'You are making this transaction outside your usual hours. '
                      'Scammers often target victims late at night or early morning when judgment may be impaired.',
        'advice': 'Consider waiting until your regular hours to make this payment.'
    },
    'no_history': {
        'title': 'No Transaction History',
        'icon': '📋',
        'explanation': 'There is no transaction history with this recipient. '
                      'First-time payments to unknown parties carry higher risk.',
        'advice': 'Start with a smaller test amount to verify the recipient.'
    },
    'individual_large': {
        'title': 'Large Payment to Individual',
        'icon': '⚠️',
        'explanation': 'You are sending a large amount to an individual (not a verified merchant). '
                      'Verified businesses have additional fraud protections.',
        'advice': 'Confirm the individual\'s identity and the purpose of this payment.'
    }
}

# Risk level summaries
RISK_SUMMARIES = {
    'critical': {
        'title': '🔴 CRITICAL RISK — Transaction Paused',
        'message': 'Multiple high-risk factors have been detected. This transaction has been '
                  'paused for 10 seconds for your safety. Please carefully review the risk factors below.',
        'color': '#FF4D4F'
    },
    'strong': {
        'title': '🟠 HIGH RISK — Proceed with Caution',
        'message': 'This transaction shows significant risk indicators. '
                  'You must acknowledge the risks before proceeding.',
        'color': '#FF8C00'
    },
    'soft': {
        'title': '🟡 MEDIUM RISK — Review Recommended',
        'message': 'Some risk factors have been detected. Please review before proceeding.',
        'color': '#FFD700'
    },
    'none': {
        'title': '🟢 LOW RISK',
        'message': 'This transaction appears safe.',
        'color': '#00C2A8'
    }
}


def generate_explanation(data):
    """Generate detailed, human-readable risk explanation."""
    score = data.get('score', 0)
    factors = data.get('factors', [])
    sms_text = data.get('sms_text', '')
    intervention_level = data.get('intervention_level', 'none')
    
    # Get risk summary
    summary = RISK_SUMMARIES.get(intervention_level, RISK_SUMMARIES['none'])
    
    # Map factors to explanations
    detailed_explanations = []
    for factor in factors:
        factor_name = factor.get('factor', '').lower().replace(' ', '_')
        
        # Try to match with templates
        template = None
        if 'new_recipient' in factor_name or 'no_transaction' in factor_name:
            template = TEMPLATES['new_recipient']
        elif 'amount' in factor_name and ('high' in factor_name or 'anomaly' in factor_name or 'large' in factor_name):
            template = TEMPLATES['high_amount']
        elif 'sms' in factor_name:
            template = TEMPLATES['suspicious_sms']
        elif 'call' in factor_name and 'unknown' in factor.get('description', '').lower():
            template = TEMPLATES['unknown_caller']
        elif 'call' in factor_name:
            template = TEMPLATES['active_call']
        elif 'qr' in factor_name:
            template = TEMPLATES['qr_trigger']
        elif 'link' in factor_name:
            template = TEMPLATES['link_trigger']
        elif 'time' in factor_name:
            template = TEMPLATES['unusual_time']
        elif 'history' in factor_name:
            template = TEMPLATES['no_history']
        elif 'individual' in factor_name:
            template = TEMPLATES['individual_large']
        
        if template:
            detailed_explanations.append({
                'title': template['title'],
                'icon': template['icon'],
                'explanation': template['explanation'],
                'advice': template['advice'],
                'contribution': factor.get('contribution', 0),
                'severity': factor.get('severity', 'low')
            })
        else:
            # Fallback: use factor data directly
            detailed_explanations.append({
                'title': factor.get('factor', 'Risk Factor'),
                'icon': '⚠️',
                'explanation': factor.get('description', 'A risk factor was detected.'),
                'advice': 'Please review this transaction carefully.',
                'contribution': factor.get('contribution', 0),
                'severity': factor.get('severity', 'low')
            })
    
    # SMS-specific highlighting
    highlighted_phrases = []
    if sms_text:
        from routes.analyze_sms import analyze_sms_text
        sms_analysis = analyze_sms_text(sms_text)
        highlighted_phrases = sms_analysis.get('highlighted_words', [])
    
    # Build overall narrative
    factor_names = [e['title'] for e in detailed_explanations[:3]]
    if factor_names:
        narrative = (f"This transaction was flagged because of: {', '.join(factor_names)}. "
                    f"Your overall risk score is {score}/100.")
    else:
        narrative = f"Risk score: {score}/100. No significant risk factors detected."
    
    return {
        'score': score,
        'summary': summary,
        'narrative': narrative,
        'detailed_explanations': detailed_explanations,
        'highlighted_phrases': highlighted_phrases,
        'recommendation': 'Cancel this transaction' if score >= 80 else 
                         'Proceed with caution' if score >= 50 else 
                         'Transaction appears safe',
        'intervention_level': intervention_level
    }


@explain_bp.route('/explain-risk', methods=['POST'])
def explain_risk():
    """Generate human-readable risk explanation."""
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'Request body is required'}), 400
    
    result = generate_explanation(data)
    return jsonify(result)
