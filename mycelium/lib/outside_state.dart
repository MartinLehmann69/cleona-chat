/// The restart-proof state of the OWN address entry (V4.2 §11.9): the
/// key under which this node publishes, and what it last
/// published.
///
/// ── WHY A STABLE KEY ─────────────────────────────────────────
///
/// §11.9 (version 16.09.2026), table row „publisher key": „a node with a
/// reachable address keeps ONE key for its records, so that a new record
/// replaces the old one and its standing is readable; a node without a
/// reachable address publishes nothing and therefore needs no key."
///
/// Until S390 a throwaway key was rolled per entry. It prevented
/// three things at once (S390-VORLAGE-NOSTR-AUFFRISCHUNG §3, V1):
///   1. REPLACING. An entry is `kind 30078` — a parameterized
///      replaceable event (NIP-01 „Replaceable Events", NIP-78). A relay
///      keeps only the newest of it per `(pubkey, kind, d)`. With a
///      fresh key per entry nothing is ever replaced; the relays
///      collect until expiry.
///   2. DELETING. A deletion (NIP-09) must be signed with THE SAME key
///      that published.
///   3. STANDING. It presupposes that the entries of a node can be
///      linked.
///
/// The price, named: the entries of a reachable node are linkable over
/// time. They were anyway — via the address that stands in
/// plaintext in the entry and by definition does not change. Whoever has NO
/// reachable address publishes nothing and therefore creates
/// no key either (see [OutsideState.open]: the key
/// arises at the first save, not at opening).
///
/// ── WHY THE LAST ENTRY LIES NEXT TO IT ────────────────────────────────
///
/// The refresh gate (§11.9: „the check suppresses the publish while
/// the addresses are byte-identical AND less than 80 % of the record's
/// lifetime has elapsed") needs two values: WHAT was last in it and
/// WHEN. Without them every restart would write an entry, although the old one
/// is still valid for almost a day — exactly the traffic the gate is supposed to
/// prevent. They belong to the key because without it they say nothing.
///
/// ── FILE LAYOUT ───────────────────────────────────────────────────────────
/// ```
/// version (1 B, 0x01)
/// secret key (32 B, secp256k1)
/// flag last entry (1 B, 0x00 none, 0x01 one)
///   created (u32 LE, Unix seconds)
///   number of addresses (1 B, 1..3)
///   per address: type (1 B, 4 or 6) | address (4/16 B) | port (u16 LE)
/// ```
/// No old format is read, no foreign version converted — there are
/// no old profiles. Unreadable data is DISCARDED instead of thrown: a
/// damaged state costs at most one additional entry, a
/// thrown error the whole start of the host.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart'
    show generateSecp256k1Keypair, secp256k1PubkeyFromSecret;
import 'package:mycelium/device_records.dart';
import 'package:mycelium/outside_address.dart' show addressesEqual;
import 'package:mycelium/outside_entry.dart'
    show kEntryAddressesAtMost, kEntryLifetime;
import 'package:mycelium/card.dart' show CardAddress, CardAddressType;
import 'package:mycelium/node_helpers.dart' show hexFrom;

const int _version = 1;

/// §11.9: "less than 80 % of the record's lifetime has elapsed" — as a fraction,
/// so that the computation stays integral and does not round.
const int kRefreshCounter = 4;
const int kRefreshDenominator = 5;

class OutsideState {
  /// Where the record lies ([kRecordOutside]) — in the app the device
  /// database; `null` for [OutsideState.ephemeral].
  final DeviceRecords? _records;

  /// The secret key (32 B) under which this node publishes.
  final Uint8List secret;

  /// The x-only public key as hex — the `pubkey` field of every
  /// event of this node and thus the comparison by which the own
  /// entry is recognised when reading (D2-6).
  final String publicHex;

  /// The x-only public key (32 B) — what an issued card carries as its
  /// publisher key (§15.2) while [publishedAt] holds.
  Uint8List get publicKey => secp256k1PubkeyFromSecret(secret);

  /// Does a record of this node stand at the relays at [now] (Unix
  /// seconds)? One was deposited, not withdrawn, and its day (§11.9
  /// "lifetime of a record: 1 day") is not over. Only then may a card name
  /// the key (§15.2): a key without a record points to nothing.
  bool publishedAt(int now) {
    final created = lastCreated;
    return created != null &&
        lastAddresses.isNotEmpty &&
        now - created < kEntryLifetime;
  }

  /// The refresh gate of §11.9, decided from this state alone: `null` =
  /// write [fresh] at [now] (Unix seconds); otherwise the reason why not —
  /// byte-identical to the last record AND under 80 % of its lifetime
  /// elapsed, BOTH must apply. It sits next to [publishedAt]: both answer
  /// from what was last deposited and when (`host_outside.dart` writes).
  String? refreshInhibit(List<CardAddress> fresh, int now) {
    final created = lastCreated;
    if (created == null) return null;
    if (!addressesEqual(fresh, lastAddresses)) return null;
    final elapsed = now - created;
    // A clock set backwards does not fall into the gate: otherwise the
    // entry would expire without ever being refreshed.
    if (elapsed < 0) return null;
    if (elapsed * kRefreshDenominator >= kRefreshCounter * kEntryLifetime) {
      return null;
    }
    return 'unchanged, ${elapsed}s of $kEntryLifetime s '
        'elapsed (< $kRefreshCounter/$kRefreshDenominator)';
  }

  /// The addresses of the last deposited entry, in the order in
  /// which they stood in it. Empty as long as none was ever deposited.
  List<CardAddress> lastAddresses = const [];

  /// `created_at` of the last deposited entry (Unix seconds), or
  /// `null`.
  int? lastCreated;

  OutsideState._(this._records, this.secret)
      : publicHex = hexFrom(secp256k1PubkeyFromSecret(secret));

  /// The state from [records], or a fresh key if none lies
  /// there. The fresh one is NOT saved immediately: a node behind CGNAT
  /// runs with it without ever creating a record (§11.9: „needs no key").
  /// Saving happens at the first [remember].
  static OutsideState open(DeviceRecords records) {
    final bytes = records.read(kRecordOutside);
    final g = bytes == null ? null : _read(records, bytes);
    return g ?? OutsideState._(records, generateSecp256k1Keypair().secretKey);
  }

  /// A state without storage — for probes and for a node without one.
  factory OutsideState.ephemeral() =>
      OutsideState._(null, generateSecp256k1Keypair().secretKey);

  /// Records what was just deposited, and saves it immediately. Immediately,
  /// because a crash in between would, at the next start, produce exactly the entry
  /// that the gate is supposed to prevent.
  void remember(List<CardAddress> addresses, int created) {
    lastAddresses = List.unmodifiable(addresses);
    lastCreated = created;
    save();
  }

  /// Forgets the last entry — after a deletion. The key
  /// stays: the same node keeps publishing under the same name,
  /// otherwise the standing would be gone with every departure.
  void forget() {
    lastAddresses = const [];
    lastCreated = null;
    save();
  }

  void save() => _records?.write(kRecordOutside, _encode());

  Uint8List _encode() {
    final b = BytesBuilder()
      ..addByte(_version)
      ..add(secret);
    final e = lastCreated;
    if (e == null || lastAddresses.isEmpty) {
      b.addByte(0);
      return b.toBytes();
    }
    b
      ..addByte(1)
      ..add((ByteData(4)..setUint32(0, e, Endian.little)).buffer.asUint8List())
      ..addByte(lastAddresses.length);
    for (final a in lastAddresses) {
      b
        ..addByte(a.kind.byteValue)
        ..add(a.address)
        ..add((ByteData(2)..setUint16(0, a.port, Endian.little))
            .buffer
            .asUint8List());
    }
    return b.toBytes();
  }

  static OutsideState? _read(DeviceRecords records, Uint8List b) {
    var i = 0;
    Uint8List take(int n) {
      if (i + n > b.length) throw const FormatException('too short');
      final s = Uint8List.fromList(b.sublist(i, i + n));
      i += n;
      return s;
    }

    try {
      if (take(1)[0] != _version) return null;
      final g = OutsideState._(records, take(32));
      if (take(1)[0] == 0) {
        if (i != b.length) return null;
        return g;
      }
      final created =
          ByteData.sublistView(take(4)).getUint32(0, Endian.little);
      final n = take(1)[0];
      if (n == 0 || n > kEntryAddressesAtMost) return null;
      final addresses = <CardAddress>[];
      for (var k = 0; k < n; k++) {
        final kind = CardAddressType.fromByte(take(1)[0]);
        if (kind == null) return null;
        final address = take(kind.addressLength);
        final port =
            ByteData.sublistView(take(2)).getUint16(0, Endian.little);
        if (port == 0) return null;
        addresses.add(CardAddress(address, port));
      }
      if (i != b.length) return null;
      g.lastAddresses = List.unmodifiable(addresses);
      g.lastCreated = created;
      return g;
    } on Object {
      return null;
    }
  }
}
