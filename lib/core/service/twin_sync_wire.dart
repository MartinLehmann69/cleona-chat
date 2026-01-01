// The wire of twin synchronisation — ONE derivation site.
//
// ── WHY THIS IS A FILE OF ITS OWN ───────────────────────────────────────
//
// The `TwinSyncEnvelope` was assembled by hand in two places in `cleona_service.dart`
// (`_sendTwinSync` and `_sendTwinAnnounce`), and
// the question "is this type unknown?" would have had to be answered in a third one with a
// typed-in field number. Both are private
// places of a 13 000-line class and thus not checkable from outside —
// the same reasoning with which `shortPairLabel` was pulled out of `v41_routing.dart`:
// "a private method of `CleonaService` would
// not be checkable — and this line was wrong because nobody checked
// it."
library;

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;

/// Die Feldnummer von `TwinSyncEnvelope.sync_type` (`app_payloads.proto`).
const int kTwinSyncTypeFieldNumber = 4;

/// Builds the twin envelope. Only derivation site.
Uint8List buildTwinSyncEnvelope({
  required Uint8List syncId,
  required Uint8List deviceId,
  required int timestampMs,
  required proto.TwinSyncType syncType,
  required Uint8List payload,
}) =>
    Uint8List.fromList((proto.TwinSyncEnvelope()
          ..syncId = syncId
          ..deviceId = deviceId
          ..timestamp = Int64(timestampMs)
          ..syncType = syncType
          ..payload = payload)
        .writeToBuffer());

/// Did the envelope carry a type that THIS version does not know?
///
/// ── MEASURED, NOT ASSUMED (2026-08-30) ──────────────────────────────────
///
/// protobuf 4.2.0 puts an unknown enum value into `unknownFields` and
/// leaves the FIELD UNSET (`lib/src/protobuf/coded_buffer.dart:74-83`).
/// The generated getter then returns the zero value of the enum — and that is
/// `CONTACT_ADDED` here. Probe against a hand-built envelope with
/// `sync_type = 17`:
///
///     syncType (getter)        = CONTACT_ADDED
///     syncType.value           = 0
///     hasSyncType()            = false
///     unknownFields[4] varints = [17]
///
/// A `switch` over `syncType` therefore interprets an unknown type as
/// CONTACT_ADDED and reads its payload as contact JSON. That does
/// not crash, but "not crashing" is not "skipping".
///
/// `hasSyncType()` is NOT usable as a distinction: proto3 does not serialise the
/// zero value at all, a real `CONTACT_ADDED` likewise arrives with
/// `hasSyncType() == false` (shown in the same probe). The only
/// place where the unknown value still stands is `unknownFields`.
bool twinSyncTypeIsUnknown(proto.TwinSyncEnvelope envelope) =>
    envelope.unknownFields.hasField(kTwinSyncTypeFieldNumber);

/// The raw, unknown type value — for the log, so that an operator
/// sees WHAT was skipped, not only THAT.
String? rawUnknownTwinSyncType(proto.TwinSyncEnvelope envelope) => envelope
    .unknownFields
    .getField(kTwinSyncTypeFieldNumber)
    ?.varints
    .join(',');
