/// Lane 3 of §9.4 — the wire forms, the transfer key and the seal.
///
/// A piece of the bulk lane is a Reed-Solomon piece from `media.dart`
/// ([stripeForm]), sealed under `HKDF(K_T, "bulk/seal")` and held under the
/// identifier `HKDF(K_T, "bulk/tag")`. `K_T` is drawn fresh per transfer and
/// travels only in the announcement, an ordinary sealed message (§4.3) —
/// the holder never learns it and cannot read what it holds.
///
/// This file knows no socket, no holder and no clock. The holder
/// (`bulk_hold.dart`), the sender (`bulk_place.dart`) and the recipient
/// (`bulk_collect.dart`) build and read their packets here, so that each
/// layout stands in exactly one place.
///
/// ## Packet layouts (each fits ONE part: `kMaxPayload` = 1158 B, `split.dart`)
/// | Kind | Form | Layout | Length |
/// |---|---|---|---|
/// | 0x52 | open | kind, 0x00, tag 16, count u16 BE, total u32 BE, proof 16 | 40 |
/// | 0x52 | piece | kind, 0x01, tag 16, stripe u16 BE, no u8, sealed 1040 | 1061 |
/// | 0x53 | held | kind, tag 16, count u16 BE, class u8 | 20 |
/// | 0x54 | collect | kind, tag 16 [, from stripe u32 BE] | 17 or 21 |
/// | 0x51 | piece | kind, tag 16, stripe u16 BE, no u8, sealed 1040 | 1060 |
/// | 0x55 | nothing here | kind, tag 16 | 17 |
/// | 0x55 | end of pass | kind, tag 16, sent u32 BE | 21 |
///
/// `count` in an open is the number of pieces announced for THIS holder;
/// `total` is the object length (the holder does not need it, the probes
/// read it). The proof is the form of `post_box_proof_of_work.dart`:
/// random value 8 ‖ counter u64 LE, difficulty `D_box` = 18, code
/// `SHA-256("mycelium-bulk-hold-2" ‖ tag ‖ count u16 BE ‖ holder)[0:16]`,
/// current and previous 10-minute window — paid once per transfer AND
/// holder (§9.4, D-30). `holder` is the address the sender writes to, in
/// the ONE address codec of the card (`addressWrite`: type byte ‖ address
/// 4|16 ‖ port). Without it one proof
/// would open every holder of the network for the same tag and count.
///
/// `from stripe` in a `0x54` (S398-W1): the recipient already holds every
/// stripe below it (opened pieces kept across a restart, `bulk_collect.dart`)
/// and the holder hands out only pieces from that stripe on. Absent or 0 =
/// everything. Pieces above it of stripes already complete still come and
/// are dropped unopened.
///
/// The END OF A PASS (S398-W1) is a `0x55` with a count: the holder has
/// handed out every piece it holds from `from stripe` on and says how many
/// it sent. It is the event on which the recipient asks again for what is
/// still open (§11.3 pattern) — no clock. The same kind as "nothing here"
/// (no new packet sort, `kinds.dart` unchanged): the plain 17 B form says
/// "I hold nothing under this tag", the 21 B form "I held something and am
/// done" — a holder whose `from stripe` filter left nothing sends the
/// 21 B form with 0, which is not "nothing here".
///
/// `class` in a `0x53` is the holder's [BulkClass] (§9.4: "a holder states
/// its class in `0x53`"): 1 desktop, 2 phone. Every `0x53` carries it, a
/// refusal too, so a sender learns which candidates are phones.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/card_address.dart' show CardAddress, addressWrite;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/media.dart' show kBlock;
import 'package:mycelium/post_box_proof_of_work.dart'
    show kDifficultyDeposit, kProofOfWorkLength;
import 'package:mycelium/proof_of_work.dart';

/// `K_T` — 32 random bytes per transfer (§9.4 "The transfer key").
const int kTransferKeyLength = 32;

/// The identifier under which a holder keeps and hands out pieces.
const int kTagLength = 16;

/// AES-256-GCM appends a 16 B tag: 1024 B block -> 1040 B sealed.
const int kSealedLength = kBlock + 16;

/// `R_bulk` (§9.4): 32 cells per second, one transfer at a time.
const int kRBulk = 32;

/// `TTL_media` (§9.4 "Holding time"): the retention of the post box.
const Duration kTtlMedia = Duration(days: 7);

/// The quiet after which a holder reports what it really holds — the
/// quiet period of §11.3, not a clock of its own.
const Duration kHeldQuiet = Duration(milliseconds: 300);

/// At most this many holders per transfer: one per piece of a stripe.
const int kHoldersAtMost = 11;

const int kOpenLength = 1 + 1 + kTagLength + 2 + 4 + kProofOfWorkLength; // 40
const int kHoldPieceLength = 1 + 1 + kTagLength + 3 + kSealedLength; // 1061
const int kPieceLength = 1 + kTagLength + 3 + kSealedLength; // 1060
const int kHeldLength = 1 + kTagLength + 2 + 1; // 20
const int kTagPacketLength = 1 + kTagLength; // 17

const int _formOpen = 0;
const int _formPiece = 1;

final _sodium = SodiumFFI();
final Uint8List _infoTag = utf8.encode('bulk/tag');
final Uint8List _infoSeal = utf8.encode('bulk/seal');
final Uint8List _proofDomain = utf8.encode('mycelium-bulk-hold-2');

/// A fresh `K_T`.
Uint8List transferKeyDraw() => _sodium.randomBytes(kTransferKeyLength);

/// `HKDF(K_T, "bulk/tag")`, 16 B.
Uint8List bulkTag(Uint8List transferKey) =>
    _sodium.hkdfSha256(transferKey, info: _infoTag, length: kTagLength);

/// `HKDF(K_T, "bulk/seal")`, 32 B.
Uint8List bulkSealKey(Uint8List transferKey) =>
    _sodium.hkdfSha256(transferKey, info: _infoSeal, length: 32);

/// The tag as a map key and for reports.
String tagHex(Uint8List tag) =>
    tag.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The nonce is DETERMINISTIC: stripe u16 BE ‖ piece number ‖ nine zero
/// bytes. That is sound only because the key is new per transfer
/// ([transferKeyDraw]) and every (stripe, number) occurs once per transfer:
/// no (key, nonce) pair ever seals two different plaintexts. A group
/// transfer seals once and places once (§9.4), so a repetition seals the
/// same plaintext to the same bytes. A random nonce would cost 12 B per
/// piece and buy nothing here.
Uint8List _nonce(int stripe, int no) => Uint8List(12)
  ..[0] = stripe >> 8
  ..[1] = stripe & 0xFF
  ..[2] = no;

/// Associated data: tag ‖ stripe ‖ number — a piece cannot be moved to
/// another position or another transfer without failing to open.
Uint8List _ad(Uint8List tag, int stripe, int no) => Uint8List(kTagLength + 3)
  ..setRange(0, kTagLength, tag)
  ..[kTagLength] = stripe >> 8
  ..[kTagLength + 1] = stripe & 0xFF
  ..[kTagLength + 2] = no;

/// Seals one 1024 B block.
Uint8List pieceSeal(
        Uint8List sealKey, Uint8List tag, int stripe, int no, Uint8List block) =>
    _sodium.aesGcmEncrypt(block, sealKey, _nonce(stripe, no),
        ad: _ad(tag, stripe, no));

/// Opens a sealed piece; `null` if it was altered, moved or is foreign.
Uint8List? pieceOpen(
    Uint8List sealKey, Uint8List tag, int stripe, int no, Uint8List sealed) {
  if (sealed.length != kSealedLength) return null;
  try {
    return _sodium.aesGcmDecrypt(sealed, sealKey, _nonce(stripe, no),
        ad: _ad(tag, stripe, no));
  } on Object {
    return null;
  }
}

/// The class a holder states in `0x53` (§9.4, D-30): among candidates of
/// equal rank desktops go first. The wire byte is the index; [unknown]
/// (0) is never sent — it is what a sender knows of a candidate that has
/// not answered yet, and ranks between desktop and phone ([order]).
enum BulkClass {
  unknown,
  desktop,
  phone;

  /// Sort key within a rank: desktop 0, unknown 1, phone 2.
  int get order => switch (this) {
        BulkClass.desktop => 0,
        BulkClass.unknown => 1,
        BulkClass.phone => 2,
      };
}

// ── Packets ───────────────────────────────────────────────────────────────

typedef BulkOpen = ({Uint8List tag, int count, int total, Uint8List proof});
typedef BulkPiece = ({Uint8List tag, int stripe, int no, Uint8List sealed});

Uint8List openPacket(Uint8List tag, int count, int total, Uint8List proof) {
  final p = Uint8List(kOpenLength)
    ..[0] = kinds.kBulkHold
    ..[1] = _formOpen
    ..setRange(2, 2 + kTagLength, tag);
  ByteData.sublistView(p)
    ..setUint16(18, count, Endian.big)
    ..setUint32(20, total, Endian.big);
  return p..setRange(24, kOpenLength, proof);
}

BulkOpen? readOpen(Uint8List p) {
  if (p.length != kOpenLength || p[0] != kinds.kBulkHold || p[1] != _formOpen) {
    return null;
  }
  final b = ByteData.sublistView(p);
  return (
    tag: Uint8List.fromList(p.sublist(2, 18)),
    count: b.getUint16(18, Endian.big),
    total: b.getUint32(20, Endian.big),
    proof: Uint8List.fromList(p.sublist(24, kOpenLength)),
  );
}

Uint8List _piece(int kind, int? form, BulkPiece x) {
  final at = form == null ? 1 : 2;
  final p = Uint8List(at + kTagLength + 3 + kSealedLength)..[0] = kind;
  if (form != null) p[1] = form;
  p.setRange(at, at + kTagLength, x.tag);
  ByteData.sublistView(p).setUint16(at + kTagLength, x.stripe, Endian.big);
  p[at + kTagLength + 2] = x.no;
  return p..setRange(at + kTagLength + 3, p.length, x.sealed);
}

BulkPiece? _readPiece(Uint8List p, int at) {
  final b = ByteData.sublistView(p);
  return (
    tag: Uint8List.fromList(p.sublist(at, at + kTagLength)),
    stripe: b.getUint16(at + kTagLength, Endian.big),
    no: p[at + kTagLength + 2],
    sealed: Uint8List.fromList(p.sublist(at + kTagLength + 3)),
  );
}

/// 0x52, form "piece" — sender to holder.
Uint8List holdPiecePacket(BulkPiece x) => _piece(kinds.kBulkHold, _formPiece, x);

BulkPiece? readHoldPiece(Uint8List p) =>
    p.length == kHoldPieceLength && p[0] == kinds.kBulkHold && p[1] == _formPiece
        ? _readPiece(p, 2)
        : null;

/// 0x51 — holder to collector.
Uint8List piecePacket(BulkPiece x) => _piece(kinds.kMediaPiece, null, x);

BulkPiece? readPiece(Uint8List p) =>
    p.length == kPieceLength && p[0] == kinds.kMediaPiece ? _readPiece(p, 1) : null;

Uint8List heldPacket(Uint8List tag, int count, BulkClass cls) {
  if (cls == BulkClass.unknown) throw ArgumentError('a holder knows its class');
  final p = Uint8List(kHeldLength)
    ..[0] = kinds.kBulkHeld
    ..setRange(1, 1 + kTagLength, tag)
    ..[kHeldLength - 1] = cls.index;
  ByteData.sublistView(p).setUint16(1 + kTagLength, count, Endian.big);
  return p;
}

/// `null` for a wrong length, kind or a class byte other than 1 or 2.
({Uint8List tag, int count, BulkClass cls})? readHeld(Uint8List p) {
  if (p.length != kHeldLength || p[0] != kinds.kBulkHeld) return null;
  final c = p[kHeldLength - 1];
  if (c != BulkClass.desktop.index && c != BulkClass.phone.index) return null;
  return (
    tag: Uint8List.fromList(p.sublist(1, 1 + kTagLength)),
    count: ByteData.sublistView(p).getUint16(1 + kTagLength, Endian.big),
    cls: BulkClass.values[c],
  );
}

/// 0x54 collect and 0x55 nothing here — kind and tag.
Uint8List tagPacket(int kind, Uint8List tag) =>
    Uint8List(kTagPacketLength)
      ..[0] = kind
      ..setRange(1, kTagPacketLength, tag);

Uint8List? readTagPacket(Uint8List p, int kind) =>
    p.length == kTagPacketLength && p[0] == kind
        ? Uint8List.fromList(p.sublist(1))
        : null;

/// 0x54 with the low-water mark [fromStripe]; 0 is the plain form.
Uint8List collectPacket(Uint8List tag, int fromStripe) {
  if (fromStripe <= 0) return tagPacket(kinds.kBulkCollect, tag);
  final p = Uint8List(kTagPacketLength + 4)
    ..[0] = kinds.kBulkCollect
    ..setRange(1, kTagPacketLength, tag);
  ByteData.sublistView(p).setUint32(kTagPacketLength, fromStripe, Endian.big);
  return p;
}

/// 0x55 as the end of a pass: [sent] pieces went out.
Uint8List passEndPacket(Uint8List tag, int sent) {
  final p = Uint8List(kTagPacketLength + 4)
    ..[0] = kinds.kBulkNothingHere
    ..setRange(1, kTagPacketLength, tag);
  ByteData.sublistView(p).setUint32(kTagPacketLength, sent, Endian.big);
  return p;
}

/// A 0x55 in either form: [ended] false = nothing here, true = end of a
/// pass with [sent] pieces. `null` for another kind or length.
({Uint8List tag, bool ended, int sent})? readNothingHere(Uint8List p) {
  final plain = readTagPacket(p, kinds.kBulkNothingHere);
  if (plain != null) return (tag: plain, ended: false, sent: 0);
  if (p.length != kTagPacketLength + 4 || p[0] != kinds.kBulkNothingHere) {
    return null;
  }
  return (
    tag: Uint8List.fromList(p.sublist(1, kTagPacketLength)),
    ended: true,
    sent: ByteData.sublistView(p).getUint32(kTagPacketLength, Endian.big),
  );
}

/// A 0x54 in either form; `null` for another kind or length.
({Uint8List tag, int from})? readCollect(Uint8List p) {
  final plain = readTagPacket(p, kinds.kBulkCollect);
  if (plain != null) return (tag: plain, from: 0);
  if (p.length != kTagPacketLength + 4 || p[0] != kinds.kBulkCollect) {
    return null;
  }
  return (
    tag: Uint8List.fromList(p.sublist(1, kTagPacketLength)),
    from: ByteData.sublistView(p).getUint32(kTagPacketLength, Endian.big),
  );
}

// ── Proof of work, once per transfer and holder ──────────────────────────

Uint8List _code(Uint8List tag, int count, CardAddress holder) {
  final input = BytesBuilder()
    ..add(_proofDomain)
    ..add(tag)
    ..add([count >> 8, count & 0xFF]);
  addressWrite(input, holder);
  return Uint8List.fromList(
      _sodium.sha256(input.toBytes()).sublist(0, ProofOfWork.codeLength));
}

/// Computes the 16 B proof for an open to [holder]. In an isolate of its
/// own, like `depositProofOfWork`: the event loop carries the cover stream
/// and the ladder, and a computation of a few hundred milliseconds would
/// stop them.
Future<Uint8List> holdProof(Uint8List tag, int count, CardAddress holder) async {
  final code = _code(tag, count, holder);
  (Uint8List, int) r;
  try {
    r = await Isolate.run(() {
      SodiumFFI();
      return ProofOfWork.generate(code, kDifficultyDeposit);
    });
  } on Object catch (e) {
    if (e is ProofOfWorkAborted) rethrow;
    r = ProofOfWork.generate(code, kDifficultyDeposit);
  }
  final proof = Uint8List(kProofOfWorkLength)
    ..setRange(0, ProofOfWork.randomValueLength, r.$1);
  ByteData.sublistView(proof)
      .setUint64(ProofOfWork.randomValueLength, r.$2, Endian.little);
  return proof;
}

/// Does [proof] carry an open for [tag] and [count] addressed to [holder]?
/// At most two hashes.
bool holdProofCarries(
    Uint8List tag, int count, CardAddress holder, Uint8List proof) {
  if (proof.length != kProofOfWorkLength) return false;
  final code = _code(tag, count, holder);
  final random = proof.sublist(0, ProofOfWork.randomValueLength);
  final counter = ByteData.sublistView(proof)
      .getUint64(ProofOfWork.randomValueLength, Endian.little);
  final now = ProofOfWork.windowNow();
  return ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now) ||
      ProofOfWork.check(code, random, counter, kDifficultyDeposit,
          timeWindow: now - 1);
}

// ── Rate ─────────────────────────────────────────────────────────────────

/// `R_bulk` for one node: every outgoing piece — placed or handed out —
/// waits for its turn here. A turn is taken synchronously before the
/// `await`, so concurrent callers queue in call order. It is a clock only
/// while pieces are going out; in idle nothing runs (§5.4).
class BulkPace {
  /// Pieces per second.
  int rate;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);

  BulkPace([this.rate = kRBulk]);

  Future<void> turn() {
    final now = DateTime.now();
    final at = _next.isAfter(now) ? _next : now;
    _next = at.add(Duration(microseconds: 1000000 ~/ max(1, rate)));
    final wait = at.difference(now);
    return wait <= Duration.zero ? Future.value() : Future.delayed(wait);
  }
}
