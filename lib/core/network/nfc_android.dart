import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';

// ---------------------------------------------------------------------------
// Android NFC Implementation
//
// Uses nfc_manager package for actual NFC hardware interaction.
// NDEF External Type record: "cleona.chat:contact"
// ---------------------------------------------------------------------------

/// Check if NFC is available on this Android device.
Future<bool> nfcIsAvailable() async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  try {
    return await NfcManager.instance.isAvailable();
  } catch (_) {
    return false;
  }
}

/// Active NFC session handle for cleanup.
bool _sessionActive = false;

/// Start an NFC session that simultaneously reads and writes NDEF records.
///
/// When a tag is discovered:
/// 1. Read the existing NDEF message (other phone's payload)
/// 2. Write our payload as an NDEF External Type record
/// 3. Call [onDiscovered] with the received payload bytes
///
/// This implements a symmetric exchange: both phones run the same code,
/// both read the other's record and write their own.
Future<void> nfcStartSession({
  required void Function(Uint8List data) onDiscovered,
  required Uint8List ourPayload,
  void Function(String error)? onError,
}) async {
  if (_sessionActive) {
    await nfcStopSession();
  }

  _sessionActive = true;

  await NfcManager.instance.startSession(
    onDiscovered: (NfcTag tag) async {
      try {
        final ndef = Ndef.from(tag);
        if (ndef == null) {
          onError?.call('NFC-Tag unterstützt kein NDEF');
          return;
        }

        // Step 1: Read existing NDEF message (other phone's data)
        Uint8List? receivedPayload;
        try {
          final message = await ndef.read();
          for (final record in message.records) {
            // Look for our custom external type "cleona.chat:contact"
            if (record.typeNameFormat == NdefTypeNameFormat.nfcExternal) {
              final typeStr = String.fromCharCodes(record.type);
              if (typeStr == 'cleona.chat:contact') {
                receivedPayload = Uint8List.fromList(record.payload);
                break;
              }
            }
          }
        } catch (_) {
          // First phone to tap might not find a record yet — that's OK
        }

        // Step 2: Write our payload
        if (ndef.isWritable) {
          try {
            final record = NdefRecord.createExternal(
              'cleona.chat',
              'contact',
              ourPayload,
            );
            await ndef.write(NdefMessage([record]));
          } catch (e) {
            onError?.call('NFC-Schreiben fehlgeschlagen: $e');
          }
        }

        // Step 3: Deliver received payload to caller
        if (receivedPayload != null && receivedPayload.isNotEmpty) {
          onDiscovered(receivedPayload);
        }
      } catch (e) {
        onError?.call('NFC-Fehler: $e');
      }
    },
    onError: (error) async {
      onError?.call('NFC Session-Fehler: $error');
    },
  );
}

/// Stop the active NFC session.
Future<void> nfcStopSession() async {
  if (!_sessionActive) return;
  _sessionActive = false;
  try {
    await NfcManager.instance.stopSession();
  } catch (_) {}
}
