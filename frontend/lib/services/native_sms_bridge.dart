import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';

class NativeSmsDetectorStatus {
  final bool hasSmsPermissions;
  final bool modelAvailable;
  final bool vocabAvailable;
  final bool ruleEngineAvailable;
  final bool cloudConfigured;
  final bool ruleOnlyFallbackActive;
  final int pendingCloudEscalations;
  final int maxSeqLength;
  final int lastInboxSyncMillis;
  final List<String> configuredLabels;

  const NativeSmsDetectorStatus({
    required this.hasSmsPermissions,
    required this.modelAvailable,
    required this.vocabAvailable,
    required this.ruleEngineAvailable,
    required this.cloudConfigured,
    required this.ruleOnlyFallbackActive,
    required this.pendingCloudEscalations,
    required this.maxSeqLength,
    required this.lastInboxSyncMillis,
    required this.configuredLabels,
  });

  factory NativeSmsDetectorStatus.fromMap(Map<dynamic, dynamic> map) {
    return NativeSmsDetectorStatus(
      hasSmsPermissions: map['hasSmsPermissions'] == true,
      modelAvailable: map['modelAvailable'] == true,
      vocabAvailable: map['vocabAvailable'] == true,
      ruleEngineAvailable: map['ruleEngineAvailable'] != false,
      cloudConfigured: map['cloudConfigured'] == true,
      ruleOnlyFallbackActive: map['ruleOnlyFallbackActive'] == true,
      pendingCloudEscalations: ((map['pendingCloudEscalations'] ?? 0) as num).toInt(),
      maxSeqLength: ((map['maxSeqLength'] ?? 0) as num).toInt(),
      lastInboxSyncMillis: ((map['lastInboxSyncMillis'] ?? 0) as num).toInt(),
      configuredLabels: List<String>.from(map['configuredLabels'] ?? const []),
    );
  }
}

class NativeSmsBridge {
  static const MethodChannel _channel = MethodChannel('com.example.wallupi/sms_native');
  static const EventChannel _eventChannel = EventChannel('com.example.wallupi/sms_events');

  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stream of newly-analyzed SMS messages pushed from the Android side in real time.
  /// Emits whenever [SmsReceiver] processes an incoming SMS while the app is in foreground.
  static Stream<SmsMessage> get smsStream => _eventChannel
      .receiveBroadcastStream()
      .where((e) => e is Map<dynamic, dynamic>)
      .cast<Map<dynamic, dynamic>>()
      .map(SmsMessage.fromNativeMap);

  static Future<bool> hasSmsPermissions() async {
    if (!isSupported) return false;
    final granted = await _channel.invokeMethod<bool>('hasSmsPermissions');
    return granted ?? false;
  }

  static Future<bool> requestSmsPermissions() async {
    if (!isSupported) return false;
    final granted = await _channel.invokeMethod<bool>('requestSmsPermissions');
    return granted ?? false;
  }

  static Future<NativeSmsDetectorStatus?> getDetectorStatus() async {
    if (!isSupported) return null;
    final map = await _channel.invokeMapMethod<dynamic, dynamic>('getDetectorStatus');
    if (map == null) return null;
    return NativeSmsDetectorStatus.fromMap(map);
  }

  static Future<List<SmsMessage>> syncInbox({int limit = 120}) async {
    if (!isSupported) return const [];
    final list = await _channel.invokeMethod<List<dynamic>>('syncInbox', {'limit': limit});
    return _decodeMessages(list);
  }

  static Future<List<SmsMessage>> getProcessedSmsMessages({int limit = 120}) async {
    if (!isSupported) return const [];
    final list = await _channel.invokeMethod<List<dynamic>>(
      'getProcessedSmsMessages',
      {'limit': limit},
    );
    return _decodeMessages(list);
  }

  static Future<SmsMessage?> analyzeSmsLocally({
    required String sender,
    required String body,
    bool persist = true,
  }) async {
    if (!isSupported) return null;
    final map = await _channel.invokeMapMethod<dynamic, dynamic>(
      'analyzeSmsLocally',
      {
        'sender': sender,
        'body': body,
        'persist': persist,
      },
    );
    if (map == null) return null;
    return SmsMessage.fromNativeMap(map);
  }

  static List<SmsMessage> _decodeMessages(List<dynamic>? list) {
    if (list == null) return const [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(SmsMessage.fromNativeMap)
        .toList();
  }
}
