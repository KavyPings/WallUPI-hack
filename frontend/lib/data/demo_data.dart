import '../models/models.dart';

/// Pre-loaded demo data for hackathon demonstration
class DemoData {
  // Demo user
  static UserProfile get demoUser => UserProfile(
    name: 'Kavya',
    phone: '9876543210',
    upiId: 'kavya@wallupi',
    balance: 45250.00,
    avgTransactionAmount: 2000,
    maxTransactionAmount: 15000,
    typicalTransactionHour: 14,
    frequentRecipients: ['rahul@upi', 'amazon@merchant', 'priya@upi'],
  );

  // Known recipients (trusted) — includes rolling amount history
  static List<Recipient> get knownRecipients => [
    Recipient(
      name: 'Rahul Sharma',
      upiId: 'rahul@upi',
      phone: '9876501234',
      transactionCount: 15,
      usualAmount: 500,
      trustScore: 90,
      recentAmounts: [500, 500, 200, 500, 300],
      lastTransactionDate: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Recipient(
      name: 'Priya Patel',
      upiId: 'priya@upi',
      phone: '9876502345',
      transactionCount: 8,
      usualAmount: 1000,
      trustScore: 85,
      recentAmounts: [1500, 1000, 1000, 800, 1200],
      lastTransactionDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Recipient(
      name: 'Amazon Pay',
      upiId: 'amazon@merchant',
      isMerchant: true,
      transactionCount: 22,
      usualAmount: 1500,
      trustScore: 95,
      recentAmounts: [2499, 1500, 1200, 1800, 999],
      lastTransactionDate: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    ),
    Recipient(
      name: 'Swiggy',
      upiId: 'swiggy@merchant',
      isMerchant: true,
      transactionCount: 30,
      usualAmount: 350,
      trustScore: 95,
      recentAmounts: [289, 350, 420, 289, 315],
      lastTransactionDate: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  // Suspicious/unknown recipients for demo
  static List<Recipient> get suspiciousRecipients => [
    Recipient(
      name: 'Unknown User',
      upiId: 'random12345@upi',
      transactionCount: 0,
      usualAmount: 0,
      trustScore: 10,
    ),
    Recipient(
      name: 'KYC Helpdesk',
      upiId: 'kycupdate@upi',
      transactionCount: 0,
      usualAmount: 0,
      trustScore: 5,
    ),
    Recipient(
      name: 'Rewards Desk',
      upiId: 'claim@rewards',
      transactionCount: 0,
      usualAmount: 0,
      trustScore: 5,
    ),
  ];

  // Demo transaction history
  static List<Transaction> get demoTransactions => [
    Transaction(
      id: 'TXN001',
      recipientName: 'Swiggy',
      recipientUpiId: 'swiggy@merchant',
      amount: 289,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      status: 'success',
      riskScore: 5,
      note: 'Lunch order',
    ),
    Transaction(
      id: 'TXN002',
      recipientName: 'Rahul Sharma',
      recipientUpiId: 'rahul@upi',
      amount: 500,
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      status: 'success',
      riskScore: 12,
      note: 'Movie tickets split',
      isIncoming: false,
    ),
    Transaction(
      id: 'TXN003',
      recipientName: 'Priya Patel',
      recipientUpiId: 'priya@upi',
      amount: 1500,
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      status: 'success',
      riskScore: 8,
      note: 'Birthday gift',
      isIncoming: true,
    ),
    Transaction(
      id: 'TXN004',
      recipientName: 'Amazon Pay',
      recipientUpiId: 'amazon@merchant',
      amount: 2499,
      timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
      status: 'success',
      riskScore: 3,
      note: 'Headphones purchase',
    ),
    Transaction(
      id: 'TXN005',
      recipientName: 'Unknown User',
      recipientUpiId: 'random12345@upi',
      amount: 15000,
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
      status: 'cancelled',
      riskScore: 88,
      note: '',
    ),
    Transaction(
      id: 'TXN006',
      recipientName: 'Rahul Sharma',
      recipientUpiId: 'rahul@upi',
      amount: 200,
      timestamp: DateTime.now().subtract(const Duration(days: 3)),
      status: 'success',
      riskScore: 5,
      note: 'Chai money',
      isIncoming: true,
    ),
  ];

  // Demo SMS messages (for SMS analysis demo)
  static List<SmsMessage> get safeSmsMessages => [
    SmsMessage(
      id: 'SMS001',
      sender: 'SBIBNK',
      body: 'Your account XX1234 has been credited with Rs.1500.00 on 01-04-2026. Available balance: Rs.45,250.00.',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      localRiskScore: 0.05,
    ),
    SmsMessage(
      id: 'SMS002',
      sender: 'AMZNIN',
      body: 'Your Amazon order #123-456 has been delivered. Thank you for shopping!',
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      localRiskScore: 0.02,
    ),
  ];

  static List<SmsMessage> get suspiciousSmsMessages => [
    SmsMessage(
      id: 'SMS003',
      sender: '+91-9999888777',
      body: 'URGENT: Your bank account has been BLOCKED due to KYC verification expired. Update KYC immediately by clicking here: http://fake-bank.xyz/kyc. Send Rs.99 for instant verification.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
      localRiskScore: 0.92,
      isFlagged: true,
      classification: 'fake_kyc_verification',
      flags: ['urgency', 'kyc_verification', 'suspicious_url', 'payment_request'],
    ),
    SmsMessage(
      id: 'SMS004',
      sender: '+91-7777666555',
      body: 'Congratulations!!! You have WON a LOTTERY prize of Rs.50,00,000! To claim your reward, send Rs.5000 to UPI ID: claim@rewards. Hurry, offer expires TODAY!',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      localRiskScore: 0.96,
      isFlagged: true,
      classification: 'social_engineering_scam',
      flags: ['prize_scam', 'urgency', 'payment_request'],
    ),
    SmsMessage(
      id: 'SMS005',
      sender: '+91-8888777666',
      body: 'Dear Customer, Your SBI account will be suspended. Share your OTP and card details immediately to reactivate. Call: 9876543210',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      localRiskScore: 0.88,
      isFlagged: true,
      classification: 'otp_theft',
      flags: ['financial_threat', 'sensitive_data_request', 'urgency', 'impersonation'],
    ),
  ];

  // All SMS combined for demo
  static List<SmsMessage> get allSmsMessages => [
    ...suspiciousSmsMessages,
    ...safeSmsMessages,
  ];

  // Demo scenarios for presentation
  static Map<String, Map<String, dynamic>> get demoScenarios => {
    'safe_payment': {
      'title': 'Safe Payment',
      'description': 'Normal payment to a known contact',
      'recipient': 'rahul@upi',
      'amount': 500,
      'expectedRisk': 'low',
      'expectedScore': 12,
    },
    'medium_risk': {
      'title': 'Medium Risk Payment',
      'description': 'Payment to a new recipient after suspicious SMS',
      'recipient': 'random12345@upi',
      'amount': 5000,
      'expectedRisk': 'medium',
      'expectedScore': 65,
      'smsId': 'SMS003',
    },
    'high_risk': {
      'title': 'High Risk Payment',
      'description': 'Large payment to unknown recipient while on call',
      'recipient': 'kycupdate@upi',
      'amount': 15000,
      'expectedRisk': 'high',
      'expectedScore': 88,
      'smsId': 'SMS003',
      'onCall': true,
    },
    'critical_risk': {
      'title': 'Critical Risk Payment',
      'description': 'Very large payment to scammer after phishing SMS',
      'recipient': 'kycupdate@upi',
      'amount': 50000,
      'expectedRisk': 'critical',
      'expectedScore': 97,
      'smsId': 'SMS004',
      'onCall': true,
      'unknownCaller': true,
    },
  };
}
