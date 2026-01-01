/// What first contact through the post box (proposal E) remembers across a
/// restart — in a store file of its OWN, next to the mailbox memory.
///
/// ── WHY A SEPARATE FILE ─────────────────────────────────────────────────
///
/// The mailbox memory (`memory.dart`, version 16) is the layout 4.2.0-beta
/// wrote. A new version would make `memory_enforcer.dart` delete it on every
/// installed device — contacts, `s_AB`, day keys, routes, invitations
/// (owner decision 28.09.2026: no version change, no reading of an old
/// format). A device that ran 4.2.0-beta simply has no such file yet, and
/// an empty store is the correct state for it.
///
/// ── WHAT IT HOLDS ───────────────────────────────────────────────────────
///
///  * per WAITING request (issuer side): the requester's 31 day keys and
///    whether it came out of a post box — the decision can fall days later
///    (§12.5), and without them the answer has no way to its sender;
///  * per OPEN join (requester side): the card, the issuer's address, the
///    one-time answer code and the request's time window — the requester is
///    typically a phone whose process is killed; without them the answer it
///    collects later belongs to no join and is discarded;
///  * per invitation that still accepts (issuer side): its own sealing key
///    pair, drawn at random when issued (owner decision R-b) — written only
///    while the record accepts, so a revocation or expiry + 7 d takes the
///    secret out of this file at the next save.
///
/// ```
/// version (1 B) = 3
/// requests: count (u16) | per request: key length (1) + key (UTF-8)
///                       | collected (1 B) | first UTC day (u32)
///                       | 31 × 32 B day keys
/// joins:    count (u16) | per join: card length (u16) + card
///                       | issuer address (Address.length) + its chain
///                       | answer code 16 B | time window (u32)
///                       | pk_inv: flag (1) [+ 32 B]
///                       | request not yet placed: flag (1) [+ length (u32) + bytes]
/// keys:     count (u16) | per invitation: code 16 B | X25519 pk 32 | sk 32
///                       | ML-KEM-768 pk 1184 | sk 2400
///                       | box pk_inv 32 | sk_inv 64
/// ```
///
/// Version 2 (S398, proposal A): the address carries the identifier and its
/// rotation chain (§4.5.4), and every invitation its random box key pair
/// (§15.1, E-A4) — until then `pk_inv` was derived from the signing key.
///
/// Version 3 (S405 F-1, owner decision 06.10.2026): an out-of-band join keeps
/// its invitation box key `pk_inv` and, until the post box took it, the
/// request (2) itself — so it goes out again, unchanged, at the next edge
/// after a restart (D-44, §9.3); a join without them is a QR/NFC one.
///
/// Encrypted and written atomically like the memory ([FileEncryption]).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart'
    show cryptoSignSecretKeyBytes;
import 'package:mycelium/envelope.dart' show Address, KemParts;
import 'package:mycelium/card.dart';
import 'package:mycelium/memory_contact.dart'
    show addressChainRead, addressChainWrite;
import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;
import 'package:mycelium/pair.dart' show kCodeLength, kDayKeyDays;

/// The file name — [FileEncryption] appends `.enc`.
const String kFileFirstContact = 'first-contact';

/// The layout version of this store — its own, independent of the memory.
const int kVersionFirstContact = 3;

/// An invitation's own secrets: its sealing keys (R-b) and its box key pair
/// (E-A4) — both random, kept together, dropped together.
typedef InvitationSecrets = ({
  KemParts kem,
  ({Uint8List pk, Uint8List sk}) box,
});

/// What a waiting request carries beyond the memory (proposal E).
typedef RequestExtras = ({bool collected, Map<int, Uint8List> dayKeys});

/// An open join as it goes to disk.
typedef RememberedJoin = ({
  Card card,
  Address counterpart,
  Uint8List answerCode,
  int window,
  Uint8List? pkInv,
  Uint8List? request,
});

class FirstContactStore {
  final FileEncryption _enc;
  final String _path;

  /// Key: [requestKey] of invitation code and requester.
  final Map<String, RequestExtras> requests = {};
  final List<RememberedJoin> joins = [];

  /// Key: invitation code (hex) — the invitation's own secrets.
  final Map<String, InvitationSecrets> invitationKeys = {};

  FirstContactStore._(this._enc, this._path);

  /// The key of an invitation's sealing keys.
  static String codeKey(Uint8List code) => _hex(code);

  /// The key of a waiting request: its invitation's code and its requester.
  static String requestKey(Uint8List code, Address who) =>
      '${_hex(code)}:${_hex(who.identifier)}';

  /// Loads the store in [directory], or an empty one if there is none.
  /// Throws [MemoryError] if one lies there that cannot be read.
  static FirstContactStore open(Directory directory, Uint8List key) {
    directory.createSync(recursive: true);
    final path = '${directory.path}/$kFileFirstContact';
    final enc = FileEncryption(baseDir: directory.path, key: key);
    final s = FirstContactStore._(enc, path);
    if (File('$path.enc').existsSync()) {
      final bytes = enc.readBinaryFile(path);
      if (bytes == null) {
        throw MemoryError('$path.enc exists, but cannot be read');
      }
      s._decode(bytes);
    }
    return s;
  }

  /// An empty store in [directory] — it replaces an unreadable one at the
  /// next [save].
  static FirstContactStore empty(Directory directory, Uint8List key) =>
      FirstContactStore._(FileEncryption(baseDir: directory.path, key: key),
          '${directory.path}/$kFileFirstContact');

  void save() => _enc.writeBinaryFile(_path, _encode());

  Uint8List _encode() {
    final b = BytesBuilder()..addByte(kVersionFirstContact);
    b.add(_u16(requests.length));
    for (final e in requests.entries) {
      final k = utf8.encode(e.key);
      final days = e.value.dayKeys.keys.toList()..sort();
      if (days.length != kDayKeyDays ||
          days.last - days.first != kDayKeyDays - 1) {
        throw ArgumentError('${days.length} day keys, expected $kDayKeyDays '
            'consecutive ones');
      }
      b
        ..addByte(k.length)
        ..add(k)
        ..addByte(e.value.collected ? 1 : 0)
        ..add(_u32(days.first));
      for (final d in days) {
        b.add(e.value.dayKeys[d]!);
      }
    }
    b.add(_u16(joins.length));
    for (final j in joins) {
      final c = j.card.pack();
      b
        ..add(_u16(c.length))
        ..add(c);
      addressChainWrite(b, j.counterpart);
      b
        ..add(j.answerCode)
        ..add(_u32(j.window));
      final pk = j.pkInv, r = j.request;
      pk == null ? b.addByte(0) : (b..addByte(1)..add(pk));
      r == null ? b.addByte(0) : (b..addByte(1)..add(_u32(r.length))..add(r));
    }
    b.add(_u16(invitationKeys.length));
    for (final e in invitationKeys.entries) {
      final k = utf8.encode(e.key);
      final kem = e.value.kem;
      b
        ..addByte(k.length)
        ..add(k)
        ..add(kem.x25519Pk)
        ..add(kem.x25519Sk)
        ..add(kem.mlKemPk)
        ..add(kem.mlKemSk)
        ..add(e.value.box.pk)
        ..add(e.value.box.sk);
    }
    return b.toBytes();
  }

  void _decode(Uint8List bytes) {
    try {
      final l = Reader(bytes);
      final version = l.byte();
      if (version != kVersionFirstContact) {
        throw MemoryError('first-contact store: unknown version $version');
      }
      for (var n = l.u16(); n > 0; n--) {
        final key = utf8.decode(l.bytes(l.byte()));
        final collected = switch (l.byte()) {
          0 => false,
          1 => true,
          final f => throw MemoryError('invalid collected flag $f'),
        };
        final first = l.u32();
        requests[key] = (
          collected: collected,
          dayKeys: {
            for (var d = first; d < first + kDayKeyDays; d++) d: l.bytes(32),
          },
        );
      }
      for (var n = l.u16(); n > 0; n--) {
        final c = l.bytes(l.u16());
        joins.add((
          card: Card.unpack(c, expectedChannel: c.length > 1 ? c[1] : 0),
          counterpart: addressChainRead(l),
          answerCode: l.bytes(kCodeLength),
          window: l.u32(),
          pkInv: _flag(l) ? l.bytes(32) : null,
          request: _flag(l) ? l.bytes(l.u32()) : null,
        ));
      }
      for (var n = l.u16(); n > 0; n--) {
        invitationKeys[utf8.decode(l.bytes(l.byte()))] = (
          kem: (
            x25519Pk: l.bytes(32),
            x25519Sk: l.bytes(32),
            mlKemPk: l.bytes(OqsFFI.mlKemPublicKeyLength),
            mlKemSk: l.bytes(OqsFFI.mlKemSecretKeyLength),
          ),
          box: (pk: l.bytes(32), sk: l.bytes(cryptoSignSecretKeyBytes)),
        );
      }
      l.done();
    } on MemoryError {
      rethrow;
    } catch (e) {
      throw MemoryError('first-contact store damaged: $e');
    }
  }
}

bool _flag(Reader l) => switch (l.byte()) {
      0 => false,
      1 => true,
      final f => throw MemoryError('invalid flag $f'),
    };

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
