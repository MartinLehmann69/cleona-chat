import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart' show cryptoSignSecretKeyBytes;
import 'package:mycelium/memory_invitation.dart';
import 'package:mycelium/memory_contact.dart';
import 'package:mycelium/envelope.dart';

/// [MemoryError], [Reader] and [RememberedInvitation] stand in
/// `memory_invitation.dart` (reasoning for the cut in its header) and
/// are re-exported from here: every existing caller
/// still imports only `package:mycelium/memory.dart`.
export 'package:mycelium/memory_invitation.dart';

/// [Contact] and its file section have stood since S391 (proposal M) in
/// `memory_contact.dart` — likewise re-exported.
export 'package:mycelium/memory_contact.dart';

/// What a MAILBOX remembers restart-proof: the own post box, the
/// contacts and the issued invitations — everything that belongs to exactly one
/// identity. Port and neighbours belong to the device and have stood
/// since S385 (cut F) in `host_memory.dart`.
///
/// Encryption is done by [FileEncryption] (atomic write path via
/// `.enc.tmp` + rename) — this file only supplies format+mapping.
///
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
});

/// [FileEncryption] itself appends `.enc`; on disk therefore lies
/// `gedaechtnis.enc` (briefly during writing: `.enc.tmp`).
const String kFileMailbox = 'memory';

/// Version 6: version byte, optionally the post box, the contacts, then —
/// with a u32 length in front — the section of the issued invitations from
/// `memory_invitation.dart`. No JSON — the secret keys are
/// bytes, not text. Version 4 also carried port and neighbours; they lie
/// with the host now. Version 6 (S385, E1): addresses 3208 B with their own
/// X25519 and `state`, the post box carries `x25519Sk` and — with a flag —
/// the previous KEM generation (32 + 2400 B). Version 7 (S388, ES-12): every
/// invitation entry additionally carries the marker `inPerson`. Version 8
/// (S388-BAU-KONTAKT): the hint byte `ohneErstkontakt` per contact
/// goes away — an inbound no longer makes anybody a contact. Version 9
/// (S389, E-1): every invitation entry carries the requests waiting for the
/// user's decision (`memory_invitation.dart`).
/// Version 10 (S390): every invitation entry carries the label
/// (§15.3 "Attribution").
/// Version 11 (S390, B-1): every contact carries the THREE addresses of its
/// card (§15.2, §7.1) — each optional, in the codec of `card_address.dart`
/// (flag byte, type byte, address, port), thus also IPv6.
/// Version 12 (S390, E2-3): the OBSERVED address in the same codec. Until then
/// it lay there as flag byte + 4 raw bytes + port — the card's claim
/// was allowed to be IPv6, the own evidence was not (§6.3 lists both
/// as equal in rank). One field instead of two, and thus the same encoding as
/// three fields further on.
/// Version 13 (S390): `karteLan` and `karteOeffentlich` become ONE
/// list [Contact.cardsAddresses] (count byte 0-4 + entries) — since §15.2 the card
/// carries no roles any more, and with them the
/// CLASSIFICATION falls out of memory. It was a second truth there: whether
/// an address lies in the own segment depends on the own segment, and
/// that changes without a single byte of the contact changing. Classification
/// now happens on every access (`address_class.dart`). The neighbour address
/// stays a separate field — it belongs to a third party.
/// Version 14 (S391, proposal M): every contact carries `s_AB`, the
/// day keys of the contact and the point in time of the last own
/// shipment of them; every waiting request carries neighbour and answer code of the
/// requester (`memory_contact.dart`, `memory_request.dart`).
/// Legacy data is cleared by `memory_enforcer.dart`.
/// Version 15 (S394, V6): every invitation carries the neighbour address its
/// card named (`memory_invitation.dart`).
/// Version 16 (2026-09, contacts as fixed neighbours, §5.2/§8.1): every
/// contact carries a LIST of up to three fixed neighbours instead of one,
/// and the mark "never a fixed neighbour" (`memory_contact.dart`).
///
/// **Why 11 and not 10**, although both changes arose in the same session:
/// version 10 really existed — it lay between two
/// commits in the main tree, and whoever wrote a profile in this window
/// would have a file with label, but without the three addresses.
/// A version number that denotes two different file formats is
/// worse than none at all.
///
/// Older versions are NOT read. There are no legacy profiles —
/// mycelium has not shipped, and a migration for a state that
/// nobody has would be code that nobody ever checks.
const int kVersionMailbox = 16;

/// What a mailbox remembers restart-proof: the own [OwnPostBox],
/// the [Contact]s and the invitations. Encrypted via
/// [FileEncryption] with a key passed by the caller — this
/// class derives none.
class Memory {
  final FileEncryption _enc;
  final String _path;
  OwnPostBox? _postBox;
  final Map<String, Contact> _contacts = {};

  Memory._(this._enc, this._path);

  /// Loads what lies in the directory, or creates an empty [Memory].
  /// If something lies there that cannot be read with [key]
  /// (wrong key, truncated, bent), this method throws
  /// [MemoryError] instead of a half instance.
  ///
  /// [now] is the clock in Unix seconds against which expired
  /// invitations are sorted out on loading (default: the system clock).
  /// It stands here and not in a field, so that a probe can check the expiry
  /// without adjusting the system time.
  static Memory open(Directory directory, Uint8List key,
      {int? now}) {
    directory.createSync(recursive: true);
    final path = '${directory.path}/$kFileMailbox';
    final enc = FileEncryption(baseDir: directory.path, key: key);
    final g = Memory._(enc, path);

    if (File('$path.enc').existsSync()) {
      final bytes = enc.readBinaryFile(path);
      if (bytes == null) {
        throw MemoryError(
            '$path.enc exists, but cannot be read — '
            'wrong key or damaged file');
      }
      g._decode(
          bytes, now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);
    }
    return g;
  }

  /// The own post box, or `null` as long as none is set.
  OwnPostBox? get ownPostBox => _postBox;
  /// Sets the own post box. Checks the three key lengths
  /// against the crypto library, instead of only at the next round trip.
  set ownPostBox(OwnPostBox? b) {
    if (b != null) {
      if (b.ed25519Sk.length != cryptoSignSecretKeyBytes) {
        throw ArgumentError('ed25519Sk must be $cryptoSignSecretKeyBytes B, '
            'was ${b.ed25519Sk.length}');
      }
      if (b.x25519Sk.length != 32) {
        throw ArgumentError('x25519Sk must be 32 B, was ${b.x25519Sk.length}');
      }
      if (b.mlKemSk.length != OqsFFI.mlKemSecretKeyLength) {
        throw ArgumentError('mlKemSk must be ${OqsFFI.mlKemSecretKeyLength} B, '
            'was ${b.mlKemSk.length}');
      }
      if (b.mlDsaSk.length != OqsFFI.mlDsaSecretKeyLength) {
        throw ArgumentError('mlDsaSk must be ${OqsFFI.mlDsaSecretKeyLength} B, '
            'was ${b.mlDsaSk.length}');
      }
    }
    _postBox = b;
  }

  /// The invitations that this identity has issued (`ch15.md:315`).
  ///
  /// They MUST survive the restart: the card is the only way
  /// by which a first contact comes about, and a card passed on
  /// yesterday would otherwise be dead today. What does not come back on loading
  /// — expired including grace period, used up — stands in
  /// [invitationsDecode].
  final List<RememberedInvitation> rememberedInvitations = [];

  /// All remembered contacts.
  List<Contact> get contacts => List.unmodifiable(_contacts.values);

  /// Remembers [k] — new, or as a replacement for the contact with the same
  /// IDENTIFIER. Name, route and `since` apply as passed; the ADDRESS goes
  /// via the adoption rule ([Address.adopt]): only a higher
  /// state replaces it, a straggler or a replay does not.
  /// The ONE place for every path that writes an address. Says whether
  /// the remembered address has changed.
  bool contactRemember(Contact k) {
    final key = _keyFor(k.address);
    final soFar = _contacts[key];
    final fresh =
        soFar == null || Address.adopt(soFar.address, k.address);
    _contacts[key] = fresh
        ? k
        : k.withAddress(soFar.address);
    return soFar != null && fresh;
  }

  /// Removes the contact with this address; no error if there was none.
  void contactForget(Address a) => _contacts.remove(_keyFor(a));

  /// Writes the state encrypted and atomically (`FileEncryption.
  /// writeBinaryFile` / `atomicReplace`: first `.enc.tmp`, then renamed).
  /// A crash between the two steps leaves the previous
  /// `gedaechtnis.enc` intact — there is never an intermediate version under
  /// the canonical name.
  void save() => _enc.writeBinaryFile(_path, _encode());

  Uint8List _encode() {
    final b = BytesBuilder();
    b.addByte(kVersionMailbox);
    final bk = _postBox;
    b.addByte(bk == null ? 0 : 1);
    if (bk != null) {
      b.add(bk.address.toBytes());
      b.add(bk.ed25519Sk);
      b.add(bk.x25519Sk);
      b.add(bk.mlKemSk);
      b.add(bk.mlDsaSk);
      final v = bk.previous;
      b.addByte(v == null ? 0 : 1);
      if (v != null) {
        b.add(v.x25519Sk);
        b.add(v.mlKemSk);
      }
    }
    final list = _contacts.values.toList();
    b.add(_u32(list.length));
    for (final k in list) {
      contactWrite(b, k); // structure: `memory_contact.dart`
    }
    // The invitations as ONE block with its own length in front: thus
    // their layout stays completely in `memory_invitation.dart`, and this
    // file need neither know it nor count along.
    final invitationBlock = invitationsEncode(rememberedInvitations);
    b.add(_u32(invitationBlock.length));
    b.add(invitationBlock);
    return b.toBytes();
  }

  void _decode(Uint8List bytes, int now) {
    try {
      final l = Reader(bytes);
      final version = l.byte();
      if (version != kVersionMailbox) {
        throw MemoryError('unknown version $version');
      }
      final hasBk = l.byte();
      OwnPostBox? bk;
      if (hasBk == 1) {
        bk = (
          address: Address.outBytes(l.bytes(Address.length)),
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
        );
      } else if (hasBk != 0) {
        throw MemoryError('invalid post box flag $hasBk');
      }
      final count = l.u32();
      final contacts = <String, Contact>{};
      for (var i = 0; i < count; i++) {
        final k = contactRead(l);
        contacts[_keyFor(k.address)] = k;
      }
      final invitations =
          invitationsDecode(l.bytes(l.u32()), now: now);
      l.done();
      _postBox = bk;
      _contacts
        ..clear()
        ..addAll(contacts);
      rememberedInvitations
        ..clear()
        ..addAll(invitations);
    } on MemoryError {
      rethrow;
    } catch (e) {
      throw MemoryError('Content damaged: $e');
    }
  }
}

/// Addresses carry no `==`/`hashCode` — the map key is the
/// hex text of their IDENTIFIER: a contact stays the same entry across every KEM rotation
/// (S385, E1).
String _keyFor(Address a) {
  final buf = StringBuffer();
  for (final byte in a.identifier) {
    buf.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.big)).buffer.asUint8List();
