/// `MethodChannelCallIntegration` — the Flutter-side implementation of
/// [CallIntegration] (architecture §10.4 stage 7, work package V3.2).
///
/// Kept in its own file because it imports `package:flutter/services.dart`,
/// which pulls in `dart:ui`. `call_service.dart` must stay daemon-safe, so it
/// only ever sees the Flutter-free contract in `call_integration.dart`; this
/// class is constructed in a Flutter-context caller (`main.dart`) and injected.
/// The same split the video engine already uses.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../network/clogger.dart';
import 'call_integration.dart';

class MethodChannelCallIntegration implements CallIntegration {
  MethodChannelCallIntegration({MethodChannel? channel, CLogger? log})
      : _channel = channel ?? const MethodChannel(kCallIntegrationChannel),
        _log = log ?? CLogger('CallIntegration') {
    if (isSupportedPlatform) {
      _channel.setMethodCallHandler(_onPlatformCall);
    }
  }

  final MethodChannel _channel;
  final CLogger _log;

  @override
  void Function(String callId)? onAnswerCall;
  @override
  void Function(String callId)? onEndCall;
  @override
  void Function(String callId, bool muted)? onSetMuted;
  @override
  void Function()? onAudioSessionActivated;
  @override
  void Function()? onAudioSessionDeactivated;

  /// Linux, Windows and macOS have no system telephony integration to talk to.
  /// Checked once here rather than at every call site.
  static bool get isSupportedPlatform => Platform.isIOS || Platform.isAndroid;

  @override
  Future<bool> reportIncomingCall(
          {required String callId,
          required String displayName,
          required bool hasVideo}) =>
      _invoke('reportIncomingCall', {
        'callId': callId,
        'displayName': displayName,
        'hasVideo': hasVideo,
      });

  @override
  Future<bool> reportOutgoingCall(
          {required String callId,
          required String displayName,
          required bool hasVideo}) =>
      _invoke('reportOutgoingCall', {
        'callId': callId,
        'displayName': displayName,
        'hasVideo': hasVideo,
      });

  @override
  Future<bool> reportCallConnected(String callId) =>
      _invoke('reportCallConnected', {'callId': callId});

  @override
  Future<bool> endCall(String callId) => _invoke('endCall', {'callId': callId});

  @override
  Future<bool> setMuted(String callId, bool muted) =>
      _invoke('setMuted', {'callId': callId, 'muted': muted});

  Future<bool> _invoke(String method, Map<String, Object?> args) async {
    if (!isSupportedPlatform) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(method, args);
      return ok ?? false;
    } on PlatformException catch (e) {
      // Expected and non-fatal: TELECOM_DENIED / TELECOM_FAILED /
      // CALLKIT_ERROR / UNKNOWN_CALL, and `false` from Android below API 26.
      _log.warn('$method failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      // The platform half is not registered in this build. Not an error — it
      // is the state every desktop build is in.
      return false;
    } catch (e) {
      _log.warn('$method failed: $e');
      return false;
    }
  }

  Future<Object?> _onPlatformCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    final callId = args['callId'] as String? ?? '';
    switch (call.method) {
      case 'onAnswerCall':
        if (callId.isNotEmpty) onAnswerCall?.call(callId);
        return true;
      case 'onEndCall':
        if (callId.isNotEmpty) onEndCall?.call(callId);
        return true;
      case 'onSetMuted':
        if (callId.isNotEmpty) {
          onSetMuted?.call(callId, args['muted'] as bool? ?? false);
        }
        return true;
      case 'onAudioSessionActivated':
        onAudioSessionActivated?.call();
        return true;
      case 'onAudioSessionDeactivated':
        onAudioSessionDeactivated?.call();
        return true;
      default:
        _log.warn('unhandled platform call: ${call.method}');
        return null;
    }
  }

  @override
  void dispose() {
    if (isSupportedPlatform) _channel.setMethodCallHandler(null);
  }
}
