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

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/secp256k1_schnorr.dart'
    show generateSecp256k1Keypair, secp256k1PubkeyFromSecret;
import 'package:mycelium/outside_entry.dart' show kEntryAddressesAtMost;
import 'package:mycelium/card.dart' show CardAddress, CardAddressType;
import 'package:mycelium/node_helpers.dart' show hexFrom;

/// [FileEncryption] appends `.enc` itself: on disk `aussen.enc`.
const String _fileName = 'outside';
const int _version = 1;

class OutsideState {
  final FileEncryption? _enc;
  final String? _path;

  /// The secret key (32 B) under which this node publishes.
  final Uint8List secret;

  /// The x-only public key as hex — the `pubkey` field of every
  /// event of this node and thus the comparison by which the own
  /// entry is recognised when reading (D2-6).
  final String publicHex;

  /// The addresses of the last deposited entry, in the order in
  /// which they stood in it. Empty as long as none was ever deposited.
  List<CardAddress> lastAddresses = const [];

  /// `created_at` of the last deposited entry (Unix seconds), or
  /// `null`.
  int? lastCreated;

  OutsideState._(this._enc, this._path, this.secret)
      : publicHex = hexFrom(secp256k1PubkeyFromSecret(secret));

  /// The state from [directory], or a fresh key if none lies
  /// there. The fresh one is NOT saved immediately: a node behind CGNAT
  /// runs with it without ever creating a file (§11.9: „needs no key").
  /// Saving happens at the first [remember].
  static OutsideState open(Directory directory, Uint8List key) {
    directory.createSync(recursive: true);
    final path = '${directory.path}/$_fileName';
    final enc = FileEncryption(baseDir: directory.path, key: key);
    if (File('$path.enc').existsSync()) {
      final bytes = enc.readBinaryFile(path);
      final g = bytes == null ? null : _read(enc, path, bytes);
      if (g != null) return g;
    }
    return OutsideState._(enc, path, generateSecp256k1Keypair().secretKey);
  }

  /// A state without disk — for probes and for a node without a folder.
  factory OutsideState.ephemeral() =>
      OutsideState._(null, null, generateSecp256k1Keypair().secretKey);

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

  void save() {
    final enc = _enc;
    final path = _path;
    if (enc == null || path == null) return;
    enc.writeBinaryFile(path, _encode());
  }

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

  static OutsideState? _read(FileEncryption enc, String path, Uint8List b) {
    var i = 0;
    Uint8List take(int n) {
      if (i + n > b.length) throw const FormatException('too short');
      final s = Uint8List.fromList(b.sublist(i, i + n));
      i += n;
      return s;
    }

    try {
      if (take(1)[0] != _version) return null;
      final g = OutsideState._(enc, path, take(32));
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
