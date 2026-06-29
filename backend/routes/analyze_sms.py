"""
/analyze-sms — Cloud SMS Analysis Endpoint
Performs deep rule-based analysis on SMS text to detect fraud.
"""

from flask import Blueprint, request, jsonify
import re

sms_bp = Blueprint('sms', __name__)

# Fraud keyword categories with weights
FRAUD_KEYWORDS = {
    'urgency': {
        'words': ['urgent', 'immediately', 'expire', 'expiring', 'hurry', 'quick',
                  'fast', 'now', 'today only', 'last chance', 'deadline', 'asap'],
        'weight': 15,
        'label': 'Creates false urgency'
    },
    'financial_threat': {
        'words': ['blocked', 'suspended', 'deactivated', 'closed', 'frozen',
                  'limited', 'restricted', 'disabled', 'terminated', 'hold'],
        'weight': 20,
        'label': 'Threatens account action'
    },
    'kyc_scam': {
        'words': ['kyc', 'verify', 'verification', 'update kyc', 'pan card',
                  'aadhar', 'aadhaar', 'identity', 'document upload'],
        'weight': 18,
        'label': 'Fake KYC/verification request'
    },
    'money_request': {
        'words': ['send money', 'transfer', 'pay now', 'payment required',
                  'amount due', 'send rs', 'send ₹', 'deposit'],
        'weight': 22,
        'label': 'Requests money transfer'
    },
    'prize_scam': {
        'words': ['congratulations', 'winner', 'won', 'prize', 'lottery',
                  'reward', 'cashback', 'bonus', 'gift', 'lucky'],
        'weight': 18,
        'label': 'Fake prize/reward claim'
    },
    'phishing': {
        'words': ['click here', 'click link', 'tap here', 'visit link',
                  'login here', 'sign in', 'update now'],
        'weight': 16,
        'label': 'Phishing link attempt'
    },
    'impersonation': {
        'words': ['rbi', 'reserve bank', 'income tax', 'government',
                  'police', 'court', 'legal action', 'complaint filed'],
        'weight': 20,
        'label': 'Impersonates authority'
    },
    'otp_scam': {
        'words': ['otp', 'one time password', 'share otp', 'send otp',
                  'pin', 'cvv', 'card number', 'password'],
        'weight': 25,
        'label': 'Requests sensitive information'
    }
}

# Suspicious URL patterns
URL_PATTERN = re.compile(
    r'(https?://[^\s]+|bit\.ly/[^\s]+|tinyurl\.com/[^\s]+|'
    r'[a-zA-Z0-9.-]+\.(xyz|tk|ml|ga|cf|gq|top|club|online|site|website)/[^\s]*)',
    re.IGNORECASE
)

# Phone number pattern (Indian format)
PHONE_PATTERN = re.compile(r'\b[6-9]\d{9}\b')


def analyze_sms_text(sms_text):
    """Perform deep analysis on SMS text for fraud indicators."""
    text_lower = sms_text.lower()
    
    risk_score = 0
    highlighted_words = []
    risk_factors = {}
    explanations = []
    
    # Check each keyword category
    for category, data in FRAUD_KEYWORDS.items():
        found_words = []
        for word in data['words']:
            if word in text_lower:
                found_words.append(word)
                # Find positions for highlighting
                start = text_lower.find(word)
                if start != -1:
                    highlighted_words.append({
                        'word': sms_text[start:start + len(word)],
                        'start': start,
                        'end': start + len(word),
                        'category': category,
                        'severity': 'high' if data['weight'] >= 20 else 'medium'
                    })
        
        if found_words:
            category_score = min(data['weight'] * len(found_words), data['weight'] * 2)
            risk_score += category_score
            risk_factors[category] = {
                'score': category_score,
                'label': data['label'],
                'found_words': found_words,
                'max_possible': data['weight'] * 2
            }
            explanations.append(f"{data['label']}: found '{', '.join(found_words)}'")
    
    # Check for suspicious URLs
    urls = URL_PATTERN.findall(sms_text)
    if urls:
        url_score = 15
        risk_score += url_score
        risk_factors['suspicious_url'] = {
            'score': url_score,
            'label': 'Contains suspicious link',
            'found_words': [u if isinstance(u, str) else u[0] for u in urls],
            'max_possible': 15
        }
        explanations.append(f"Contains suspicious URL(s)")
        for url in urls:
            url_str = url if isinstance(url, str) else url[0]
            start = sms_text.find(url_str)
            if start != -1:
                highlighted_words.append({
                    'word': url_str,
                    'start': start,
                    'end': start + len(url_str),
                    'category': 'suspicious_url',
                    'severity': 'high'
                })
    
    # Check for excessive capitals (shouting)
    uppercase_ratio = sum(1 for c in sms_text if c.isupper()) / max(len(sms_text), 1)
    if uppercase_ratio > 0.4 and len(sms_text) > 20:
        risk_score += 8
        risk_factors['excessive_caps'] = {
            'score': 8,
            'label': 'Excessive use of CAPITALS (pressure tactic)',
            'found_words': [],
            'max_possible': 8
        }
        explanations.append("Uses excessive CAPITALS to create pressure")
    
    # Check for multiple exclamation/question marks
    if sms_text.count('!') >= 3 or sms_text.count('?') >= 3:
        risk_score += 5
        risk_factors['punctuation'] = {
            'score': 5,
            'label': 'Excessive punctuation (urgency signal)',
            'found_words': [],
            'max_possible': 5
        }
    
    # Grammar/spelling indicators (common in scam messages)
    grammar_indicators = ['dear customer', 'dear user', 'dear sir', 'respected',
                          'kindly', 'do the needful', 'revert back']
    found_grammar = [g for g in grammar_indicators if g in text_lower]
    if found_grammar:
        risk_score += 8
        risk_factors['scam_language'] = {
            'score': 8,
            'label': 'Uses common scam language patterns',
            'found_words': found_grammar,
            'max_possible': 8
        }
    
    # Cap at 100
    risk_score = min(risk_score, 100)
    
    # Determine classification
    if risk_score >= 70:
        classification = 'high_risk'
        summary = 'This message shows strong indicators of a financial scam.'
    elif risk_score >= 40:
        classification = 'suspicious'
        summary = 'This message contains some suspicious elements that may indicate fraud.'
    elif risk_score >= 15:
        classification = 'low_risk'
        summary = 'This message has minor suspicious elements but is likely safe.'
    else:
        classification = 'safe'
        summary = 'This message appears to be safe.'
    
    # Generate detailed explanation
    if explanations:
        detailed_explanation = f"{summary} Specifically: {'; '.join(explanations)}."
    else:
        detailed_explanation = summary
    
    return {
        'risk_score': risk_score,
        'classification': classification,
        'summary': summary,
        'explanation': detailed_explanation,
        'highlighted_words': highlighted_words,
        'risk_factors': risk_factors,
        'category_count': len(risk_factors)
    }


@sms_bp.route('/analyze-sms', methods=['POST'])
def analyze_sms():
    """Analyze SMS text for fraud indicators."""
    data = request.get_json()
    
    if not data or 'sms_text' not in data:
        return jsonify({'error': 'sms_text is required'}), 400
    
    sms_text = data['sms_text']
    
    if not sms_text or len(sms_text.strip()) == 0:
        return jsonify({'error': 'sms_text cannot be empty'}), 400
    
    result = analyze_sms_text(sms_text)
    return jsonify(result)
