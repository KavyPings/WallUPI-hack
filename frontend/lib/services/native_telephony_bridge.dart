import 'package:flutter/services.dart';

class CallStateEvent {
  final bool isOnCall;
  final bool isUnknownCaller;
  final String state; // idle, ringing, offhook

  const CallStateEvent({
    required this.isOnCall,
    required this.isUnknownCaller,
    required this.state,
  });
}

class NativeTelephonyBridge {
  static const _channel = MethodChannel('com.example.wallupi/sms_native');
  static const _eventChannel =
      EventChannel('com.example.wallupi/telephony_events');

  static Stream<CallStateEvent> get callStateStream => _eventChannel
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .cast<Map<dynamic, dynamic>>()
      .map((map) => CallStateEvent(
            isOnCall: map['isOnCall'] as bool? ?? false,
            isUnknownCaller: map['isUnknownCaller'] as bool? ?? false,
            state: map['state'] as String? ?? 'idle',
          ));

  /// Directly queries the current call state from TelephonyManager at call time.
  /// More reliable than the stream for detecting pre-existing calls.
  static Future<CallStateEvent> getCallState() async {
    try {
      final raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('getCallState');
      final map = raw ?? {};
      final isOnCall = map['isOnCall'] as bool? ?? false;
      return CallStateEvent(
        isOnCall: isOnCall,
        isUnknownCaller: map['isUnknownCaller'] as bool? ?? false,
        state: isOnCall ? 'offhook' : 'idle',
      );
    } catch (_) {
      return const CallStateEvent(
          isOnCall: false, isUnknownCaller: false, state: 'idle');
    }
  }

  static Future<bool> requestCallStatePermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestCallStatePermissions') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
