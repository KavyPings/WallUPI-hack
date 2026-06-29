import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Local storage service using SharedPreferences
class StorageService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // =============== USER PROFILE ===============

  static Future<void> saveUserProfile(UserProfile profile) async {
    await _prefs?.setString('user_profile', jsonEncode(profile.toJson()));
  }

  static UserProfile? getUserProfile() {
    final data = _prefs?.getString('user_profile');
    if (data != null) {
      return UserProfile.fromJson(jsonDecode(data));
    }
    return null;
  }

  // =============== TRANSACTIONS ===============

  static Future<void> saveTransactions(List<Transaction> transactions) async {
    final data = transactions.map((t) => t.toJson()).toList();
    await _prefs?.setString('transactions', jsonEncode(data));
  }

  static List<Transaction> getTransactions() {
    final data = _prefs?.getString('transactions');
    if (data != null) {
      final list = jsonDecode(data) as List;
      return list.map((t) => Transaction.fromJson(t)).toList();
    }
    return [];
  }

  static Future<void> addTransaction(Transaction transaction) async {
    final transactions = getTransactions();
    transactions.insert(0, transaction);
    await saveTransactions(transactions);
  }

  // =============== RECIPIENTS ===============

  static Future<void> saveRecipients(List<Recipient> recipients) async {
    final data = recipients.map((r) => r.toJson()).toList();
    await _prefs?.setString('recipients', jsonEncode(data));
  }

  static List<Recipient> getRecipients() {
    final data = _prefs?.getString('recipients');
    if (data != null) {
      final list = jsonDecode(data) as List;
      return list.map((r) => Recipient.fromJson(r)).toList();
    }
    return [];
  }

  static Recipient? getRecipientByUpiId(String upiId) {
    final recipients = getRecipients();
    try {
      return recipients.firstWhere((r) => r.upiId == upiId);
    } catch (_) {
      return null;
    }
  }

  // =============== SMS MESSAGES ===============

  static Future<void> saveSmsMessages(List<SmsMessage> messages) async {
    final data = messages.map((m) => m.toJson()).toList();
    await _prefs?.setString('sms_messages', jsonEncode(data));
  }

  static List<SmsMessage> getSmsMessages() {
    final data = _prefs?.getString('sms_messages');
    if (data != null) {
      final list = jsonDecode(data) as List;
      return list.map((m) => SmsMessage.fromJson(m)).toList();
    }
    return [];
  }

  static List<SmsMessage> getFlaggedSmsMessages() {
    return getSmsMessages().where((m) => m.isFlagged).toList();
  }

  static Future<void> addSmsMessage(SmsMessage message) async {
    final messages = getSmsMessages();
    messages.insert(0, message);
    await saveSmsMessages(messages);
  }

  // =============== SETTINGS ===============

  static Future<void> setLoggedIn(bool value) async {
    await _prefs?.setBool('is_logged_in', value);
  }

  static bool isLoggedIn() {
    return _prefs?.getBool('is_logged_in') ?? false;
  }

  static Future<void> setIsAdmin(bool value) async {
    await _prefs?.setBool('is_admin', value);
  }

  static bool getIsAdmin() {
    return _prefs?.getBool('is_admin') ?? false;
  }

  static Future<void> setRegisteredPhone(String phone) async {
    await _prefs?.setString('registered_phone', phone);
  }

  static String? getRegisteredPhone() {
    return _prefs?.getString('registered_phone');
  }

  static Future<void> setSimulateCallState(bool value) async {
    await _prefs?.setBool('simulate_call', value);
  }

  static bool getSimulateCallState() {
    return _prefs?.getBool('simulate_call') ?? false;
  }

  static Future<void> setSimulateUnknownCaller(bool value) async {
    await _prefs?.setBool('simulate_unknown_caller', value);
  }

  static bool getSimulateUnknownCaller() {
    return _prefs?.getBool('simulate_unknown_caller') ?? false;
  }

  static Future<void> setRegisteredUpiId(bool value) async {
    await _prefs?.setBool('registered_upi_id', value);
  }

  static bool getRegisteredUpiId() {
    return _prefs?.getBool('registered_upi_id') ?? false;
  }

  // =============== CLEAR ===============

  static Future<void> clearAll() async {
    await _prefs?.clear();
  }
}
