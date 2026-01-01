import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/network/nfc_contact_exchange.dart';
import 'package:cleona/core/network/nfc_android.dart' as nfc_hw;
import 'package:cleona/core/services/contact_manager.dart';

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

/// Callback for NFC session state changes.
typedef NfcSessionCallback = void Function(
    NfcSessionState state, NfcContactPayload? receivedPayload, String? error);

/// Manages NFC contact exchange sessions.
///
/// Flow:
/// 1. [startSession] — prepares our payload and starts listening for NFC tap
/// 2. On tap: sends our payload via NDEF, receives other party's payload
/// 3. Validates received payload (signature, timestamp, keys)
/// 4. Calls [onSessionUpdate] with [pendingConfirmation] + payload
/// 5. UI shows confirmation dialog → user calls [confirmContact] or [cancelSession]
/// 6. On confirm: contact is created with Verification Level 3 (Verified)
class NfcSessionManager {
  final NfcContactExchange exchange;
  final NfcSessionCallback onSessionUpdate;

  /// Our signed payload (prepared at session start).
  Uint8List? _ourPayload;

  /// Received payload from the other party (after NFC tap).
  NfcContactPayload? _receivedPayload;

  /// Current session state.
  NfcSessionState _state = NfcSessionState.idle;
  NfcSessionState get state => _state;

  NfcSessionManager({
    required this.exchange,
    required this.onSessionUpdate,
  });

  /// Start an NFC exchange session.
  ///
  /// Prepares our signed payload with the given identity data,
  /// then starts the NFC reader/writer.
  Future<bool> startSession({
    required String displayName,
    required Uint8List ed25519PublicKey,
    required Uint8List mlDsaPublicKey,
    required Uint8List x25519PublicKey,
    required Uint8List mlKemPublicKey,
    Uint8List? profilePicture,
    String? description,
    required List<String> addresses,
    required List<NfcPeerEntry> seedPeers,
  }) async {
    if (!await isNfcAvailable()) {
      _updateState(NfcSessionState.failed, error: 'NFC nicht verfügbar');
      return false;
    }

    // Create our signed payload
    _ourPayload = exchange.createPayload(
      displayName: displayName,
      ed25519PublicKey: ed25519PublicKey,
      mlDsaPublicKey: mlDsaPublicKey,
      x25519PublicKey: x25519PublicKey,
      mlKemPublicKey: mlKemPublicKey,
      profilePicture: profilePicture,
      description: description,
      addresses: addresses,
      seedPeers: seedPeers,
    );

    _updateState(NfcSessionState.waitingForTap);

    // Start NFC session via platform plugin
    try {
      await _startNfcSession();
      return true;
    } catch (e) {
      _updateState(NfcSessionState.failed, error: 'NFC Start fehlgeschlagen: $e');
      return false;
    }
  }

  /// Called when user confirms the received contact.
  /// Creates the contact with Verification Level 3 (Verified).
  Contact? confirmContact() {
    if (_receivedPayload == null || _state != NfcSessionState.pendingConfirmation) {
      return null;
    }

    final contact = exchange.contactFromPayload(_receivedPayload!);
    _updateState(NfcSessionState.completed);
    _stopNfcSession();
    return contact;
  }

  /// Cancel the NFC session.
  void cancelSession() {
    _receivedPayload = null;
    _ourPayload = null;
    _updateState(NfcSessionState.idle);
    _stopNfcSession();
  }

  void _updateState(NfcSessionState newState,
      {NfcContactPayload? payload, String? error}) {
    _state = newState;
    _receivedPayload = payload ?? _receivedPayload;
    onSessionUpdate(newState, _receivedPayload, error);
  }

  /// Process received NDEF data from the other phone.
  void _onNdefReceived(Uint8List data) {
    final (result, payload) = exchange.validatePayload(data);

    if (result != NfcValidationResult.ok || payload == null) {
      final errorMsg = switch (result) {
        NfcValidationResult.malformed => 'Ungültige NFC-Daten',
        NfcValidationResult.invalidSignature => 'Ungültige Signatur',
        NfcValidationResult.expired => 'NFC-Daten abgelaufen',
        NfcValidationResult.futureTimestamp => 'Ungültiger Zeitstempel',
        NfcValidationResult.invalidNodeId => 'Ungültige Node-ID',
        NfcValidationResult.invalidKeys => 'Ungültige Schlüssel',
        NfcValidationResult.emptyDisplayName => 'Kein Name angegeben',
        _ => 'Unbekannter Fehler',
      };
      _updateState(NfcSessionState.failed, error: errorMsg);
      return;
    }

    // Valid payload — show confirmation dialog
    _updateState(NfcSessionState.pendingConfirmation, payload: payload);
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
