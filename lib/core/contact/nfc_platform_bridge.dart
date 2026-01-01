import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/contact/nfc_android.dart' as nfc_hw;

// Conditional: nfc_manager only works on Android/iOS.
bool _isNfcPlatform() => Platform.isAndroid || Platform.isIOS;

// ---------------------------------------------------------------------------
// NFC Availability Check
// ---------------------------------------------------------------------------

/// Check if NFC hardware is present AND enabled at OS level.
/// Returns false on Linux/Desktop (no NFC hardware).
Future<bool> isNfcAvailable() async {
  if (!_isNfcPlatform()) return false;
  try {
    // Dynamic import via nfc_manager plugin
    final available = await _nfcManagerIsAvailable();
    return available;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// NFC Session Manager
// ---------------------------------------------------------------------------

/// State of the NFC exchange session.
enum NfcSessionState {
  /// Idle — no NFC session active.
  idle,

  /// Waiting for NFC tap — phone should be held against another.
  waitingForTap,

  /// Received payload, waiting for user confirmation.
  pendingConfirmation,

  /// Exchange completed successfully.
  completed,

  /// Exchange failed or was cancelled.
  failed,
}

/// Callback for NFC session state changes. [receivedPayload] are the raw
/// bytes of the other side — on V4.2 its packed invitation card (§15.2).
typedef NfcSessionCallback = void Function(
    NfcSessionState state, Uint8List? receivedPayload, String? error);

/// Manages NFC exchange sessions — a transport that exchanges the bytes of
/// both sides in ONE touch (§15.10 "A touch can carry both cards
/// in one operation").
///
/// ── WHAT STOOD HERE UNTIL S388 ────────────────────────────────────────────
///
/// The V3 exchange (`nfc_contact_exchange.dart`): a signed record with
/// keys, addresses and seed peers, from which the app immediately created
/// an `accepted` contact after a tap (`addNfcContact`) — without card,
/// without request, without answer, bypassing the first contact of V4.2.
/// Since S388-BAU-KONTAKT the touch carries the card that the screen
/// issues PERSONALLY for it; the issuer accepts the request that follows
/// without a second question (§15.5). Checking the bytes belongs to the
/// card reader, not to this transport.
///
/// Flow:
/// 1. [startSession] — takes the own bytes and waits for the touch
/// 2. On tap: sends the own bytes as NDEF, receives those of the other side
/// 3. [onSessionUpdate] with [NfcSessionState.pendingConfirmation] + bytes
/// 4. UI shows the card that was read → [confirm] or [cancelSession]
class NfcSessionManager {
  final NfcSessionCallback onSessionUpdate;

  /// Our payload (prepared at session start).
  Uint8List? _ourPayload;

  /// Received payload from the other party (after NFC tap).
  Uint8List? _receivedPayload;

  /// Current session state.
  NfcSessionState _state = NfcSessionState.idle;
  NfcSessionState get state => _state;

  NfcSessionManager({required this.onSessionUpdate});

  /// Start an NFC exchange session with [ourPayload] and the NFC
  /// reader/writer.
  Future<bool> startSession(Uint8List ourPayload) async {
    if (!await isNfcAvailable()) {
      _updateState(NfcSessionState.failed, error: 'NFC not available');
      return false;
    }
    _ourPayload = ourPayload;
    _updateState(NfcSessionState.waitingForTap);

    // Start NFC session via platform plugin
    try {
      await _startNfcSession();
      return true;
    } catch (e) {
      _updateState(NfcSessionState.failed, error: 'NFC start failed: $e');
      return false;
    }
  }

  /// Called when the user confirms the received payload. Returns the bytes,
  /// or `null` if nothing is pending confirmation.
  Uint8List? confirm() {
    final p = _receivedPayload;
    if (p == null || _state != NfcSessionState.pendingConfirmation) {
      return null;
    }
    _updateState(NfcSessionState.completed);
    _stopNfcSession();
    return p;
  }

  /// Cancel the NFC session.
  void cancelSession() {
    _receivedPayload = null;
    _ourPayload = null;
    _updateState(NfcSessionState.idle);
    _stopNfcSession();
  }

  void _updateState(NfcSessionState newState,
      {Uint8List? payload, String? error}) {
    _state = newState;
    _receivedPayload = payload ?? _receivedPayload;
    onSessionUpdate(newState, _receivedPayload, error);
  }

  /// Process received NDEF data from the other phone.
  void _onNdefReceived(Uint8List data) {
    if (data.isEmpty) {
      _updateState(NfcSessionState.failed, error: 'Invalid NFC data');
      return;
    }
    _updateState(NfcSessionState.pendingConfirmation, payload: data);
  }

  // ── Platform NFC Integration ─────────────────────────────────────

  Future<void> _startNfcSession() async {
    if (!_isNfcPlatform()) return;
    await _nfcManagerStartSession(
      onDiscovered: (Uint8List receivedData) {
        _onNdefReceived(receivedData);
      },
      ourPayload: _ourPayload!,
    );
  }

  void _stopNfcSession() {
    if (!_isNfcPlatform()) return;
    _nfcManagerStopSession();
  }
}

// ---------------------------------------------------------------------------
// nfc_manager Plugin Wrappers — delegate to nfc_android.dart
// ---------------------------------------------------------------------------

Future<bool> _nfcManagerIsAvailable() async {
  if (!_isNfcPlatform()) return false;
  return nfc_hw.nfcIsAvailable();
}

Future<void> _nfcManagerStartSession({
  required void Function(Uint8List data) onDiscovered,
  required Uint8List ourPayload,
}) async {
  if (!_isNfcPlatform()) return;
  await nfc_hw.nfcStartSession(
    onDiscovered: onDiscovered,
    ourPayload: ourPayload,
  );
}

void _nfcManagerStopSession() {
  if (!_isNfcPlatform()) return;
  nfc_hw.nfcStopSession();
}
