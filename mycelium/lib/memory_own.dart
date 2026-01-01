/// The own post box and its section in the file layout of the memory.
///
/// ── WHY THIS FILE EXISTS ─────────────────────────────────────────
///
/// S401 gives the section a second form (flag 2, below), and `memory.dart`
/// stood at its line budget. The cut is the one of `memory_contact.dart`:
/// here ONE section of the file layout with the types it carries;
/// `memory.dart` re-exports this file.
///
/// ── TWO FORMS, AND WHO WRITES WHICH (S401, inventory U-4) ────────────
///
/// The four secret keys of an identity have ONE place. With an app that is
/// the app's store (area `keys`); the app hands the identity over at every
/// start (`MailboxDetails.me`), and of the stored post box the delivery
/// layer then reads only the previous day-key seed. A second copy of the
/// keys in this file had no reader on that path — so it is not written
/// there any more (flag 2). A node WITHOUT an app (`bin/myceliumd.dart`,
/// probes) has no other place: for it this file IS where the identity lives
/// (flag 1), exactly as before.
///
/// ── FILE LAYOUT OF THE SECTION (version 17) ──────────────────────────
/// ```
/// flag (1 B): 0 none | 1 with secret keys | 2 without
/// flag 1: address + chain | ed25519Sk 64 | x25519Sk 32 | mlKemSk 2400
///         | mlDsaSk 4032 | previous: flag + (x25519Sk 32 | mlKemSk 2400)
///         | founding: flag + ed25519Sk 64 | day seed: flag + (32 | u64)
/// flag 2: address + chain | day seed: flag + (seed 32 | until u64)
/// ```
/// Flag 2 is new under the SAME version: both forms are read, no file is
/// lost to the enforcer, and a flag-1 file of an app is rewritten as flag 2
/// at its next start (`postBoxFetch` saves at every start).
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart' show cryptoSignSecretKeyBytes;
import 'package:mycelium/envelope.dart';
import 'package:mycelium/memory_contact.dart'
    show addressChainRead, addressChainWrite;
import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;

/// OPEN SEAM: a real `PostBox` (envelope.dart) cannot be serialised from
/// here — its three secret fields are
/// file-private. What is stored is therefore [OwnPostBox]: the same
/// four values as a standalone byte bundle (`berichte/P7-gedaechtnis.md`).
typedef OwnPostBox = ({
  Address address,
  Uint8List ed25519Sk,
  Uint8List x25519Sk,
  Uint8List mlKemSk,
  Uint8List mlDsaSk,
  // The previous KEM generation, as long as it is within the grace period (E1).
  PreviousParts? previous,
  // Since version 17 (S398, A): the founding Ed25519 secret key of a rotated
  // identity (`null` before any rotation) and the previous day-key seed
  // within its 7 days (§8.2).
  Uint8List? foundingEd25519Sk,
  PreviousDaySeed? previousDaySeed,
});

/// What memory keeps of the own post box when the CALLER holds the identity
/// (the app, S401): the address and the previous day-key seed — the
/// delivery layer's own state (§8.2). No key of the identity.
typedef OwnKept = ({Address address, PreviousDaySeed? previousDaySeed});

/// The ONE mapping of a [PostBox] onto what memory keeps of it.
OwnPostBox ownPostBoxOf(PostBox b) {
  final t = b.secretParts();
  return (
    address: b.address,
    ed25519Sk: t.ed25519Sk,
    x25519Sk: t.x25519Sk,
    mlKemSk: t.mlKemSk,
    mlDsaSk: t.mlDsaSk,
    previous: t.previous,
    foundingEd25519Sk: b.address.rotated ? t.foundingEd25519Sk : null,
    previousDaySeed: b.previousDaySeed,
  );
}

/// Counterpart to [ownPostBoxOf].
PostBox postBoxOutOwn(OwnPostBox own) => PostBox.outSplit(
      address: own.address,
      ed25519Sk: own.ed25519Sk,
      x25519Sk: own.x25519Sk,
      mlKemSk: own.mlKemSk,
      mlDsaSk: own.mlDsaSk,
      previous: own.previous,
      foundingEd25519Sk: own.foundingEd25519Sk,
      previousDaySeed: own.previousDaySeed,
    );

/// [OwnKept] of a full post box.
OwnKept ownKeptOf(OwnPostBox b) =>
    (address: b.address, previousDaySeed: b.previousDaySeed);

/// Checks the key lengths of [b] against the crypto library, instead of
/// only at the next round trip.
void ownPostBoxCheck(OwnPostBox b) {
  void length(String name, Uint8List key, int want) {
    if (key.length != want) {
      throw ArgumentError('$name must be $want B, was ${key.length}');
    }
  }

  length('ed25519Sk', b.ed25519Sk, cryptoSignSecretKeyBytes);
  length('x25519Sk', b.x25519Sk, 32);
  length('mlKemSk', b.mlKemSk, OqsFFI.mlKemSecretKeyLength);
  length('mlDsaSk', b.mlDsaSk, OqsFFI.mlDsaSecretKeyLength);
}

/// Writes the section: flag 1 with [full], else flag 2 with [kept], else 0.
/// [full] is passed only by a memory that is the one place of the keys.
void ownWrite(BytesBuilder b, OwnPostBox? full, OwnKept? kept) {
  final k = full == null ? kept : ownKeptOf(full);
  b.addByte(full != null ? 1 : (k != null ? 2 : 0));
  if (k == null) return;
  addressChainWrite(b, k.address);
  if (full != null) {
    b.add(full.ed25519Sk);
    b.add(full.x25519Sk);
    b.add(full.mlKemSk);
    b.add(full.mlDsaSk);
    final v = full.previous;
    b.addByte(v == null ? 0 : 1);
    if (v != null) {
      b.add(v.x25519Sk);
      b.add(v.mlKemSk);
    }
    final f = full.foundingEd25519Sk;
    b.addByte(f == null ? 0 : 1);
    if (f != null) b.add(f);
  }
  final d = k.previousDaySeed;
  b.addByte(d == null ? 0 : 1);
  if (d != null) {
    b.add(d.seed);
    b.add((ByteData(8)..setUint64(0, d.until, Endian.big)).buffer.asUint8List());
  }
}

/// Reads the section: the full post box when the file holds the keys, and
/// in every case what is kept of it.
(OwnPostBox?, OwnKept?) ownRead(Reader l) {
  PreviousDaySeed? daySeed() => switch (l.byte()) {
        0 => null,
        1 => (seed: l.bytes(32), until: l.u64()),
        final f => throw MemoryError('invalid day-seed flag $f'),
      };
  final flag = l.byte();
  if (flag == 0) return (null, null);
  if (flag == 2) {
    return (null, (address: addressChainRead(l), previousDaySeed: daySeed()));
  }
  if (flag != 1) throw MemoryError('invalid post box flag $flag');
  final OwnPostBox full = (
    address: addressChainRead(l),
    ed25519Sk: l.bytes(cryptoSignSecretKeyBytes),
    x25519Sk: l.bytes(32),
    mlKemSk: l.bytes(OqsFFI.mlKemSecretKeyLength),
    mlDsaSk: l.bytes(OqsFFI.mlDsaSecretKeyLength),
    previous: switch (l.byte()) {
      0 => null,
      1 => (
          x25519Sk: l.bytes(32),
          mlKemSk: l.bytes(OqsFFI.mlKemSecretKeyLength),
        ),
      final f => throw MemoryError('invalid previous flag $f'),
    },
    foundingEd25519Sk: switch (l.byte()) {
      0 => null,
      1 => l.bytes(cryptoSignSecretKeyBytes),
      final f => throw MemoryError('invalid founding flag $f'),
    },
    previousDaySeed: daySeed(),
  );
  return (full, ownKeptOf(full));
}
