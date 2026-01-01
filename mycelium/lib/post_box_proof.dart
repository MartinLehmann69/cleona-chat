import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/post_box_disk.dart' show kIdLength, kValueLength;
import 'package:mycelium/pair.dart' show deriveDayKey, dayValue, utcDay;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/envelope.dart' show PostBox;
import 'package:mycelium/update_manifest_compartment.dart' show isManifestValue;

/// The proof of the collector under day values (V4.2 §8.2, proposal M 5.4,
/// owner approval 17.09.2026).
///
/// Until S391 the collector named its identifier and proved it with the
/// bundle of its identity — every holder thus saw WHO collects. Now
/// a packet lies under a 16-B day value `dayValue(pk_d)`
/// (`pair.dart`); proof is given with the day pubkey `pk_d` and an
/// Ed25519 signature with the secret day key. A contact knows
/// `pk_d` and can deposit, but neither collect nor delete — it lacks
/// `sk_d`. The holder sees only day values and day pubkeys, both
/// randomness without `K_AB`.
///
/// ```
/// collector                                 holder
/// 0x32 count | 7 × value (114 B)       ──►
///                                      ◄──  0x35 random | node (33 B)  [30 s, once per value]
/// 0x36 value|random|pk_d|signature (129 B) ──►  per value; checks: task open,
///                                           same source, value asked,
///                                           dayValue(pk_d) == value,
///                                           Ed25519 over [proofData]
///                                      ◄──  0x33 value|id|… / 0x34 value   [only now]
/// 0x31 id|signature (73 B)             ──►  Ed25519 with pk_d over [deleteData] → delete
/// ```
///
/// **ONE task per request, not per value.** The request has a fixed 114 B
/// (unused places rolled — the number of values stands only in the
/// count byte), the task 33 B: the amplification stays closed, as since
/// S385. Seven tasks (343 B) for a forged source would be
/// three times the request. The proof stays per value: every day value is
/// proven individually with its own key, and per value the
/// task applies once.
///
/// **The public manifest compartment** (§26.5.4) is a fixed value
/// ([isManifestValue]) without key: the proof under it carries zeros
/// instead of `pk_d` and signature, and the holder there checks only the task
/// (return route of the source, against amplification), no proof.
///
/// Limit, named: the up to seven values of a request come from
/// the same source — a holder thus links the day values of ONE
/// identity across the days of a collection. It does not see a person.

const int kRandomLength = 16;
const int kSignatureLength = 64;
const int kDayPkLength = 32;

/// At most this many values are asked by a 0x32 — the retention (7 days).
const int kAtMostValues = 7;

/// 0x32 `Sorte | Anzahl | 7 × Wert` — always this length.
const int kCollectLength = 1 + 1 + kAtMostValues * kValueLength;

/// 0x31 as delete receipt: `Sorte | id | Zeichnung`. The deposited
/// receipt (holder to sender) is `Sorte | id | Knoten` — the length separates them.
const int kDeleteReceiptLength = 1 + kIdLength + kSignatureLength;

/// 0x36 has a fixed length: any other is discarded without parsing.
const int kProofLength =
    1 + kValueLength + kRandomLength + kDayPkLength + kSignatureLength;

/// A day key pair, as `tagesSchluessel` delivers it.
typedef DayPair = ({Uint8List pk, Uint8List sk});

/// What a collection asks: a value and the pair that proves it. Without
/// pair only under the public manifest compartment.
typedef Question = ({Uint8List value, DayPair? pair});

/// The own questions of [me]: the day keys of today (UTC) and
/// the six days before — the retention of §8.2.
List<Question> ownAsk(PostBox me, DateTime now) {
  final today = utcDay(now);
  return [
    for (var d = 0; d < kAtMostValues; d++)
      _question(deriveDayKey(me, today - d)),
  ];
}

Question _question(DayPair p) => (value: dayValue(p.pk), pair: p);

/// The question under the public manifest compartment (no proof).
Question compartmentQuestion(Uint8List value) => (value: value, pair: null);

final Uint8List _kCollect = utf8.encode('mycelium-fetch-2');
final Uint8List _kDelete = utf8.encode('mycelium-delete-2');

/// What the collector signs on the task — per value.
Uint8List proofData(Uint8List value, Uint8List random) => (BytesBuilder()
      ..add(_kCollect)
      ..add(value)
      ..add(random))
    .toBytes();

/// What the collector signs for deleting ONE entry. The random value
/// binds the signature to the collection in which the piece went out.
Uint8List deleteData(Uint8List value, Uint8List random, Uint8List id) =>
    (BytesBuilder()
          ..add(_kDelete)
          ..add(value)
          ..add(random)
          ..add(id))
        .toBytes();

/// 0x32 for [ask] (1–7). Free places are filled by [random].
Uint8List collectPacket(List<Question> ask, Uint8List random) {
  if (ask.isEmpty || ask.length > kAtMostValues) {
    throw ArgumentError('1 to $kAtMostValues values, not ${ask.length}');
  }
  final b = BytesBuilder()
    ..addByte(kinds.kCollect)
    ..addByte(ask.length);
  for (final f in ask) {
    if (f.value.length != kValueLength) {
      throw ArgumentError('Value must be $kValueLength B, was ${f.value.length}');
    }
    b.add(f.value);
  }
  final free = (kAtMostValues - ask.length) * kValueLength;
  if (free > 0) b.add(Uint8List.sublistView(random, 0, free));
  return b.toBytes();
}

/// The asked values of a 0x32, or `null`.
List<Uint8List>? collectValuesRead(Uint8List p) {
  if (p.length != kCollectLength || p[0] != kinds.kCollect) return null;
  final n = p[1];
  if (n < 1 || n > kAtMostValues) return null;
  return [
    for (var i = 0; i < n; i++)
      Uint8List.fromList(p.sublist(2 + i * kValueLength, 2 + (i + 1) * kValueLength)),
  ];
}

/// 0x35 `Sorte | Zufall 16 | Knotenkennung 16`. The node identifier of the
/// holder (B1, S388) is not signed; the proof binds only the random value.
Uint8List taskPacket(Uint8List random, Uint8List node) =>
    (BytesBuilder()
          ..addByte(kinds.kCollectTask)
          ..add(random)
          ..add(node))
        .toBytes();

/// The proof for [f] on [random]. Without pair (manifest compartment) zeros.
Uint8List proofPacket(Question f, Uint8List random) {
  final p = f.pair;
  return (BytesBuilder()
        ..addByte(kinds.kCollectProof)
        ..add(f.value)
        ..add(random)
        ..add(p?.pk ?? Uint8List(kDayPkLength))
        ..add(p == null
            ? Uint8List(kSignatureLength)
            : SodiumFFI().signEd25519(proofData(f.value, random), p.sk)))
      .toBytes();
}

/// 0x31 as delete receipt, signed with the day key [pair].
Uint8List deletePacket(
        DayPair pair, Uint8List value, Uint8List random, Uint8List id) =>
    (BytesBuilder()
          ..addByte(kinds.kDeposited)
          ..add(id)
          ..add(SodiumFFI().signEd25519(deleteData(value, random, id), pair.sk)))
        .toBytes();

typedef Proof = ({
  Uint8List value,
  Uint8List random,
  Uint8List pk,
  Uint8List signature,
});

/// Takes a 0x36 apart; `null` on wrong length.
Proof? proofRead(Uint8List p) {
  if (p.length != kProofLength || p[0] != kinds.kCollectProof) return null;
  var i = 1;
  Uint8List chunk(int n) => Uint8List.fromList(p.sublist(i, i += n));
  return (
    value: chunk(kValueLength),
    random: chunk(kRandomLength),
    pk: chunk(kDayPkLength),
    signature: chunk(kSignatureLength),
  );
}

/// Does the proof hold? Under the manifest compartment always (no proof, §26.5.4);
/// otherwise `dayValue(pk)` must yield the value and the signature with `pk`
/// must be over [proofData].
bool proofCarries(Proof b) =>
    isManifestValue(b.value) ||
    (equal(dayValue(b.pk), b.value) &&
        SodiumFFI().verifyEd25519(
            proofData(b.value, b.random), b.signature, b.pk));

/// Does the delete receipt [p] for [value] hold, signed with [pk] in the
/// collection with [random]?
bool deleteReceiptCarries(
    Uint8List p, Uint8List value, Uint8List random, Uint8List pk) {
  if (p.length != kDeleteReceiptLength) return false;
  final id = p.sublist(1, 1 + kIdLength);
  return SodiumFFI()
      .verifyEd25519(deleteData(value, random, id), p.sublist(1 + kIdLength), pk);
}

bool equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  var d = 0;
  for (var i = 0; i < x.length; i++) {
    d |= x[i] ^ y[i];
  }
  return d == 0;
}
