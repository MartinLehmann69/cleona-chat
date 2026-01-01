/// Checking fetched address records OFF the event loop (§11.9, S409).
///
/// ── THE FINDING ──────────────────────────────────────────────────────
///
/// Source 4 (`host_outside.dart` `_read`) and the publisher lookup
/// (`publisher_lookup.dart`) fetched up to three relays' records and checked
/// every one with [eventCheck] in a row on the node's event loop. The
/// signature check is secp256k1 Schnorr in pure Dart
/// (`lib/core/crypto/secp256k1_schnorr.dart`); records that several relays
/// return alike were checked once per relay. Measured on Node1, 28.10.2026:
/// every one of the four `heartbeat … DRIFT` lines (2.1–6.3 s main loop
/// delay) stands right after "Source 4: … relay(s) read" — in those seconds
/// the node answered nothing, an IPC ping of the E2E run included
/// (report S409-STILLSTAND-START.md). The same code and pattern in 4.2.3.
///
/// ── WHAT CHANGES ─────────────────────────────────────────────────────
///
/// 1. Identical records are checked ONCE. "Identical" is the whole record,
///    not its `id` field: a relay that returned a doctored record under a
///    genuine `id` first must not decide the result of the genuine one.
/// 2. The check runs in an isolate of its own, like the deposit proof of
///    work (`post_box_proof_of_work.dart`); if the isolate fails, it runs
///    here, so the result never depends on it.
/// The result per record is exactly that of [eventCheck] — same order as
/// the input, same `null` for every rejection. Nothing on the wire changes.
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/outside_entry.dart';

/// [eventCheck] for every record of [events], in an isolate; one result per
/// record, in the order of [events]. Identical records are checked once.
Future<List<AddressRecord?>> eventsCheck(
    List<Map<String, dynamic>> events, int channel) async {
  if (events.isEmpty) return const [];
  final position = <String, int>{};
  final unique = <Map<String, dynamic>>[];
  final index = <int>[];
  for (final ev in events) {
    String? key;
    try {
      key = jsonEncode(ev);
    } on Object {
      key = null; // not encodable: checked on its own (and rejected there)
    }
    final at = key == null ? null : position[key];
    if (at != null) {
      index.add(at);
      continue;
    }
    if (key != null) position[key] = unique.length;
    index.add(unique.length);
    unique.add(ev);
  }
  // One clock for all records, taken here — the isolate starts later.
  final now = nowSeconds();
  List<AddressRecord?> checkHere() =>
      [for (final ev in unique) eventCheck(ev, channel, now: now)];
  List<AddressRecord?> checked;
  try {
    checked = await Isolate.run(() {
      SodiumFFI(); // the record id is SHA-256 through libsodium (hashFrom)
      return checkHere();
    });
  } on Object {
    checked = checkHere();
  }
  return [for (final i in index) checked[i]];
}
