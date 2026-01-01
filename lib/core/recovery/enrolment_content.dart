// B-4b (D-39): the bytes of an enrolment — the request of a new device and
// the answer of an existing one (V4.2 §14.6.1, §14.6.2).
//
// ── THE REQUEST ─────────────────────────────────────────────────────────
//
// Laid under `value_E(i, d)` and sent as the enrolment call; sealed with
// `HKDF(recovery_key(i), "enrol-enc")` (`enrolKey`), AEAD like the bundle
// (§13.3.3). It carries what the existing device shows and needs to answer:
// name, platform, DeviceID, the device KEM public keys (the handover is
// sealed against them), the public reply keys for 7 days (the answer lies
// under their values, like the day keys of a first-contact request, §15.5)
// and the new device's addresses (direct answer while both are present).
//
// ── THE ANSWER ──────────────────────────────────────────────────────────
//
// A handover (§14.6.2) or a rejection, in pieces of at most 32 KB, each
// sealed on its own against the new device's KEM keys (hybrid X25519 +
// ML-KEM-768, `PerMessageKem`): a piece that arrives alone — directly or
// from a post box — opens alone, and a holder sees only opaque bytes.
//
// No compatibility: a new format number, nothing older is read (4.2 has no
// legacy enrolments).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/recovery/recovery_bundle_content.dart'
    show BundleNeighbour;
import 'package:cleona/core/recovery/recovery_keys.dart';

const List<int> _kRequestMagic = <int>[0x43, 0x45, 0x52, 0x00]; // "CER\0"
const List<int> _kAnswerMagic = <int>[0x43, 0x45, 0x41, 0x00]; // "CEA\0"
const int _kVersion = 1;

/// The window of an enrolment (§14.6.1: 24 hours).
const Duration kEnrolWindow = Duration(hours: 24);

/// Reply keys a request carries (§14.6.1: day keys for 7 days).
const int kEnrolReplyKeys = 7;

/// At most this many bytes per answer piece (proposal B-4b §3: ≤ 32 KB).
const int kEnrolPieceAtMost = 32 * 1024;

/// What a piece carries beside its chunk: magic, version, request id,
/// index, count, type, KEM header, AEAD tag.
const int _kPieceOverhead = 4 + 1 + 16 + 2 + 2 + 1 + _kHeaderLength + 16;
const int _kHeaderLength = 32 + OqsFFI.mlKemCiphertextLength + 12 + 1;

/// The chunk size that keeps a piece at [kEnrolPieceAtMost].
const int kEnrolChunk = kEnrolPieceAtMost - _kPieceOverhead;

/// The two answers.
enum EnrolAnswerType { handover, rejected }

/// The request of a new device, unsealed.
final class EnrolRequest {
  EnrolRequest({
    required this.requestId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.deviceX25519Pk,
    required this.deviceMlKemPk,
    required this.replyPks,
    required this.addresses,
    required this.holders,
    required this.atMs,
  });

  final Uint8List requestId;
  final Uint8List deviceId;
  final String deviceName;
  final String platform;
  final Uint8List deviceX25519Pk;
  final Uint8List deviceMlKemPk;

  /// Public reply keys, today first; the answer lies under their values.
  final List<Uint8List> replyPks;

  /// The new device's own addresses — the direct answer goes there.
  final List<BundleNeighbour> addresses;

  /// The holders the new device asks while it waits (§8.2: the sender
  /// chooses holders the recipient will ask) — the rest of the answer
  /// is laid there first.
  final List<BundleNeighbour> holders;
  final int atMs;

  String get requestIdHex => _hex(requestId);
  String get deviceIdHex => _hex(deviceId);

  Uint8List encode() {
    final b = BytesBuilder()
      ..add(_kRequestMagic)
      ..addByte(_kVersion)
      ..add(_fixed(requestId, 16))
      ..add(_fixed(deviceId, 16));
    _str(b, deviceName);
    _str(b, platform);
    b
      ..add(_fixed(deviceX25519Pk, 32))
      ..add(_fixed(deviceMlKemPk, OqsFFI.mlKemPublicKeyLength))
      ..addByte(replyPks.length);
    for (final p in replyPks) {
      b.add(_fixed(p, 32));
    }
    _list(b, addresses);
    _list(b, holders);
    b.add(_u64(atMs));
    return b.toBytes();
  }

  static void _list(BytesBuilder b, List<BundleNeighbour> l) {
    b.addByte(l.length);
    for (final a in l) {
      b
        ..addByte(a.ip.length)
        ..add(a.ip)
        ..add(_u16(a.port));
    }
  }

  static List<BundleNeighbour>? _readList(_Reader r) {
    final m = r.u8();
    if (m > 4) return null;
    final out = <BundleNeighbour>[];
    for (var i = 0; i < m; i++) {
      final l = r.u8();
      if (l != 4 && l != 16) return null;
      out.add((ip: r.raw(l), port: r.u16()));
    }
    return out;
  }

  /// Reads a request, or `null` if the bytes are not one. Does not throw.
  static EnrolRequest? read(Uint8List bytes) {
    try {
      final r = _Reader(bytes);
      if (!_same(r.raw(4), _kRequestMagic) || r.u8() != _kVersion) return null;
      final id = r.raw(16);
      final dev = r.raw(16);
      final name = r.str();
      final platform = r.str();
      final x = r.raw(32);
      final kem = r.raw(OqsFFI.mlKemPublicKeyLength);
      final n = r.u8();
      if (n < 1 || n > kEnrolReplyKeys) return null;
      final pks = [for (var i = 0; i < n; i++) r.raw(32)];
      final addresses = _readList(r);
      final holders = _readList(r);
      if (addresses == null || holders == null) return null;
      final at = r.u64();
      if (!r.atEnd || name.length > 64 || platform.length > 16) return null;
      return EnrolRequest(
          requestId: id,
          deviceId: dev,
          deviceName: name,
          platform: platform,
          deviceX25519Pk: x,
          deviceMlKemPk: kem,
          replyPks: pks,
          addresses: addresses,
          holders: holders,
          atMs: at);
    } catch (_) {
      return null;
    }
  }
}

/// Seals [q] with the enrol key of `recovery_key(i)` (§14.6.1).
Uint8List sealEnrolRequest(Uint8List recoveryKeyI, EnrolRequest q) =>
    sealBundle(enrolKey(recoveryKeyI),
        SodiumFFI().randomBytes(kBundleNonceBytes), q.encode());

/// Opens a sealed request, or `null` (other words, bent, not a request).
EnrolRequest? openEnrolRequest(Uint8List recoveryKeyI, Uint8List sealed) {
  final clear = openBundle(enrolKey(recoveryKeyI), sealed);
  return clear == null ? null : EnrolRequest.read(clear);
}

/// One opened answer piece.
typedef EnrolAnswerPiece = ({
  Uint8List requestId,
  int index,
  int count,
  EnrolAnswerType type,
  Uint8List chunk,
});

/// Cuts [body] into pieces of at most [kEnrolPieceAtMost], each sealed
/// against the new device's KEM keys.
List<Uint8List> sealEnrolAnswer({
  required Uint8List requestId,
  required EnrolAnswerType type,
  required Uint8List body,
  required Uint8List x25519Pk,
  required Uint8List mlKemPk,
}) {
  final count = body.isEmpty ? 1 : (body.length + kEnrolChunk - 1) ~/ kEnrolChunk;
  if (count > 0xffff) throw ArgumentError('answer of ${body.length} B');
  final out = <Uint8List>[];
  for (var i = 0; i < count; i++) {
    final end = (i + 1) * kEnrolChunk;
    final chunk = Uint8List.sublistView(
        body, i * kEnrolChunk, end > body.length ? body.length : end);
    final head = BytesBuilder()
      ..add(_kAnswerMagic)
      ..addByte(_kVersion)
      ..add(_fixed(requestId, 16))
      ..add(_u16(i))
      ..add(_u16(count))
      ..addByte(type.index);
    final (h, ct) = PerMessageKem.encrypt(
        plaintext: Uint8List.fromList(chunk),
        recipientX25519Pk: x25519Pk,
        recipientMlKemPk: mlKemPk);
    head
      ..add(h.ephemeralX25519Pk)
      ..add(h.mlKemCiphertext)
      ..add(h.aesNonce)
      ..addByte(h.version)
      ..add(ct);
    out.add(head.toBytes());
  }
  return out;
}

/// Opens one piece with the device KEM secret keys, or `null`.
EnrolAnswerPiece? openEnrolAnswer(
    Uint8List piece, Uint8List x25519Sk, Uint8List mlKemSk) {
  try {
    final r = _Reader(piece);
    if (!_same(r.raw(4), _kAnswerMagic) || r.u8() != _kVersion) return null;
    final id = r.raw(16);
    final index = r.u16();
    final count = r.u16();
    final t = r.u8();
    if (t >= EnrolAnswerType.values.length || index >= count) return null;
    final header = KemHeader(
        ephemeralX25519Pk: r.raw(32),
        mlKemCiphertext: r.raw(OqsFFI.mlKemCiphertextLength),
        aesNonce: r.raw(12),
        version: r.u8());
    final chunk = PerMessageKem.decrypt(
        kemHeader: header,
        ciphertext: r.rest(),
        ourX25519Sk: x25519Sk,
        ourMlKemSk: mlKemSk);
    return (
      requestId: id,
      index: index,
      count: count,
      type: EnrolAnswerType.values[t],
      chunk: chunk,
    );
  } catch (_) {
    return null;
  }
}

/// Puts the pieces of ONE answer together; a piece may come twice.
final class EnrolAnswerAssembly {
  EnrolAnswerAssembly(this.requestId);

  final Uint8List requestId;
  final Map<int, Uint8List> _chunks = {};
  int? _count;
  EnrolAnswerType? _type;

  /// Takes [p]; returns the complete answer once every piece is there.
  ({EnrolAnswerType type, Uint8List body})? add(EnrolAnswerPiece p) {
    if (!_same(p.requestId, requestId)) return null;
    if (_count != null && (p.count != _count || p.type != _type)) return null;
    _count = p.count;
    _type = p.type;
    _chunks[p.index] = p.chunk;
    if (_chunks.length < p.count) return null;
    final b = BytesBuilder();
    for (var i = 0; i < p.count; i++) {
      b.add(_chunks[i]!);
    }
    return (type: p.type, body: b.toBytes());
  }

  int get have => _chunks.length;
  int? get count => _count;
}

/// The body of a rejection (S398, lab B-4b finding B-2): WHEN the existing
/// device rejected, in ms on ITS clock — the same clock that stamps its
/// bundles (`RecoveryBundleContent.depositedAtMs`). Closing a window lays no
/// bundle (§13.3.4), so the bundle in the network names the old window's
/// end for up to 24 hours; the new device takes a window only from a bundle
/// laid after this time. Both times come from the existing device: the
/// comparison never involves the new device's clock.
Uint8List enrolRejectionBody(int rejectedAtMs) => _u64(rejectedAtMs);

/// The time a rejection body carries, or `null` when it carries none.
int? enrolRejectionAt(Uint8List body) =>
    body.length == 8 ? _Reader(body).u64() : null;

/// JSON body helpers — the handover is a JSON document (§14.6.2 list).
Uint8List enrolBodyOf(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));
Map<String, dynamic>? enrolBodyRead(Uint8List body) {
  try {
    final j = jsonDecode(utf8.decode(body));
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────

Uint8List _fixed(Uint8List v, int n) {
  if (v.length != n) throw ArgumentError('$n B expected, ${v.length} B given');
  return v;
}

void _str(BytesBuilder b, String s) {
  final e = utf8.encode(s);
  b
    ..add(_u16(e.length))
    ..add(e);
}

Uint8List _u16(int v) => Uint8List.fromList([(v >> 8) & 0xff, v & 0xff]);
Uint8List _u64(int v) => be64(v);

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

final class _Reader {
  _Reader(this._b);
  final Uint8List _b;
  int _o = 0;
  bool get atEnd => _o == _b.length;
  Uint8List raw(int n) {
    if (_o + n > _b.length) throw StateError('too short');
    final out = Uint8List.fromList(Uint8List.sublistView(_b, _o, _o + n));
    _o += n;
    return out;
  }

  Uint8List rest() => raw(_b.length - _o);
  int u8() => raw(1)[0];
  int u16() {
    final x = raw(2);
    return (x[0] << 8) | x[1];
  }

  int u64() {
    final x = raw(8);
    var v = 0;
    for (final y in x) {
      v = (v << 8) | y;
    }
    return v;
  }

  String str() => utf8.decode(raw(u16()));
}
