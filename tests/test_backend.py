import unittest
import json
import os
import sys
from unittest.mock import MagicMock, patch

# Add backend directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../backend')))

# Import flask app and db
from app import app
from database import db
from models import UserProfile, RelationshipProfile, SpamFlag, TransactionLog

class BackendAPITestCase(unittest.TestCase):
    def setUp(self):
        # Configure app for testing
        app.config['TESTING'] = True
        app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
        app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
        
        self.app = app.test_client()
        self.ctx = app.app_context()
        self.ctx.push()
        
        db.create_all()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.ctx.pop()

    def test_health_check(self):
        """Test the health check endpoint returns 200 and correct status"""
        response = self.app.get('/')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'ok')
        self.assertIn('endpoints', data)

    def test_api_status(self):
        """Test /status endpoint returns backend ok status"""
        response = self.app.get('/status')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['backend'], 'ok')
        self.assertIn('cloud_configured', data)
        self.assertIn('gemini_configured', data)  # backward-compat alias

    def test_analyze_sms_safe(self):
        """Test SMS analyzer with a safe message"""
        response = self.app.post('/analyze-sms', json={
            'sms_text': 'Hey, are we still meeting up for lunch today at 1 PM?'
        })
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['classification'], 'safe')
        self.assertEqual(data['risk_score'], 0)

    def test_analyze_sms_suspicious(self):
        """Test SMS analyzer with a clear phishing/scam message"""
        response = self.app.post('/analyze-sms', json={
            'sms_text': 'URGENT: Your bank account is BLOCKED. Click here to verify your KYC immediately: https://fake-bank.xyz/login'
        })
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn(data['classification'], ['suspicious', 'high_risk'])
        self.assertTrue(data['risk_score'] >= 40)
        self.assertTrue(any(w['word'] == 'URGENT' for w in data['highlighted_words']))

    def test_log_transaction_and_profiles(self):
        """Test transaction logging updates UserProfile and RelationshipProfile"""
        # Log a low-risk transaction
        response = self.app.post('/profile/transaction', json={
            'user_upi_id': 'sender@wallupi',
            'recipient_upi_id': 'receiver@wallupi',
            'amount': 250.0,
            'risk_score': 10,
            'intervention_level': 'none',
            'is_merchant': False
        })
        self.assertEqual(response.status_code, 201)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'ok')

        # Verify receiver user profile
        response = self.app.get('/profile/user/receiver@wallupi')
        self.assertEqual(response.status_code, 200)
        user_data = json.loads(response.data)
        self.assertEqual(user_data['upi_id'], 'receiver@wallupi')
        self.assertEqual(user_data['total_txn_count'], 1)
        self.assertEqual(user_data['high_risk_txn_count'], 0)
        self.assertEqual(user_data['risk_tier'], 'low')

        # Verify relationship profile
        response = self.app.get('/profile/relationship?user_upi=sender@wallupi&counterpart_upi=receiver@wallupi')
        self.assertEqual(response.status_code, 200)
        rel_data = json.loads(response.data)
        self.assertEqual(rel_data['txn_count'], 1)
        self.assertEqual(rel_data['total_amount'], 250.0)
        self.assertEqual(rel_data['avg_amount'], 250.0)
        self.assertTrue(rel_data['trust_score'] > 50) # got payment bonus

    def test_spam_flagging_and_check(self):
        """Test reporting a spam recipient and checking their flags"""
        # Flag recipient
        response = self.app.post('/spam/flag', json={
            'reporter_upi_id': 'reporter@wallupi',
            'flagged_upi_id': 'spammer@wallupi',
            'reason': 'scam',
            'note': 'sent phishing KYC message'
        })
        self.assertEqual(response.status_code, 201)
        self.assertEqual(json.loads(response.data)['status'], 'flagged')

        # Duplicate flagging within 7 days should yield already_flagged
        response = self.app.post('/spam/flag', json={
            'reporter_upi_id': 'reporter@wallupi',
            'flagged_upi_id': 'spammer@wallupi',
            'reason': 'scam',
            'note': 'another flag'
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(json.loads(response.data)['status'], 'already_flagged')

        # Check flags
        response = self.app.get('/spam/check?upi_id=spammer@wallupi')
        self.assertEqual(response.status_code, 200)
        check_data = json.loads(response.data)
        self.assertEqual(check_data['flag_count'], 1)
        self.assertTrue(check_data['is_flagged'])
        self.assertIn('scam', check_data['reasons'])

        # Verify risk tier escalated on recipient's UserProfile
        response = self.app.get('/profile/user/spammer@wallupi')
        self.assertEqual(response.status_code, 200)
        user_data = json.loads(response.data)
        self.assertEqual(user_data['flagged_by_others_count'], 1)

    def test_risk_scoring(self):
        """Test the risk scoring engine endpoint"""
        response = self.app.post('/risk-score', json={
            'amount': 5000.0,
            'is_new_recipient': True,
            'user_upi_id': 'user@wallupi',
            'recipient_upi_id': 'new_contact@wallupi',
            'recipient_name': 'New User',
            'is_merchant': False,
            'recipient_trust_score': 50,
            'transaction_count_with_recipient': 0,
            'usual_amount_with_recipient': 0.0,
            'user_avg_amount': 1000.0,
            'triggered_by_qr': False,
            'triggered_by_link': True,
            'has_suspicious_sms': False,
            'sms_risk_score': 0,
            'sms_age_minutes': 0,
            'sms_body': '',
            'sms_sender': '',
            'is_on_call': True,
            'is_unknown_caller': True,
            'is_registered_upi_id': False
        })
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('score', data)
        self.assertIn('intervention_level', data)
        self.assertIn('factors', data)
        self.assertTrue(data['score'] > 20) # should trigger call/link penalties

    def test_explain_risk(self):
        """Test explain risk explanation output"""
        response = self.app.post('/explain-risk', json={
            'score': 85,
            'intervention_level': 'strong',
            'sms_text': 'Your bank card is blocked. Call 9999999999',
            'factors': [
                {'factor': 'New Recipient', 'description': 'First transaction', 'contribution': 25, 'severity': 'medium'},
                {'factor': 'Suspicious SMS Detected', 'description': 'Flagged SMS references recipient', 'contribution': 35, 'severity': 'high'}
            ]
        })
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['score'], 85)
        self.assertEqual(data['intervention_level'], 'strong')
        self.assertIn('narrative', data)
        self.assertTrue(len(data['detailed_explanations']) >= 2)

    @patch('routes.cloud_sms_review.bedrock_ready')
    @patch('routes.cloud_sms_review._invoke_model')
    def test_cloud_sms_review_mocked(self, mock_invoke, mock_ready):
        """Test cloud review escalation when the Bedrock model is mocked"""
        mock_ready.return_value = True

        # Stub the Bedrock model's raw text response
        mock_invoke.return_value = json.dumps({
            "risk_score": 90,
            "classification": "fake_kyc_verification",
            "intervention_level": "critical",
            "explanation": "Scam attempting to steal credentials under fake verification.",
            "key_indicators": ["blocked", "kyc"],
            "confidence": 0.95
        })

        response = self.app.post('/cloud-review', json={
            'sanitized_body': 'Bank alert: update KYC within 24h to avoid blocking.',
            'local_risk_score': 0.65,
            'classification': 'uncertain',
            'sender': 'AD-SBI',
            'flags': ['kyc', 'blocked'],
            'escalation_reason': 'Model score near threshold'
        })
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['risk_score'], 90)
        self.assertEqual(data['classification'], 'fake_kyc_verification')
        self.assertEqual(data['intervention_level'], 'critical')
        self.assertEqual(data['confidence'], 0.95)

if __name__ == '__main__':
    unittest.main()
