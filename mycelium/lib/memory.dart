import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/memory_invitation.dart';
import 'package:mycelium/memory_contact.dart';
import 'package:mycelium/memory_own.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/trace.dart' show traceNote;

/// [MemoryError], [Reader] and [RememberedInvitation] stand in
/// `memory_invitation.dart` (reasoning for the cut in its header) and
/// are re-exported from here: every existing caller
/// still imports only `package:mycelium/memory.dart`.
export 'package:mycelium/memory_invitation.dart';

/// [Contact] and its file section have stood since S391 (proposal M) in
/// `memory_contact.dart` — likewise re-exported.
export 'package:mycelium/memory_contact.dart';

/// The own post box and its file section (S401) — likewise re-exported.
export 'package:mycelium/memory_own.dart';

/// What a MAILBOX remembers restart-proof: the own post box, the
/// contacts and the issued invitations — everything that belongs to exactly one
/// identity. Port and neighbours belong to the device and have stood
/// since S385 (cut F) in `host_memory.dart`.
///
/// Encryption is done by [FileEncryption] (atomic write path via
/// `.enc.tmp` + rename) — this file only supplies format+mapping.
/// The own post box — [OwnPostBox], [OwnKept], their mapping and their
/// file section — has stood since S401 in `memory_own.dart`.

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
/// Version 17 (S398, proposal A, D-33): every address carries the identifier
/// (3240 B) and is followed by its rotation chain; every contact carries
/// whether it acknowledged the own chain; the post box carries — with flags —
/// the founding secret key and the previous day-key seed. PRICE, named: a
/// device updating from version 16 loses this file (`memory_enforcer.dart`)
/// — contacts' `s_AB`, day keys, routes, invitations; 4.2.1 is not
/// compatible with 4.2.0 (owner decision).
/// STILL version 17 (S401): the post box flag takes a second value, 2 — the
/// address and the day-seed section WITHOUT the four secret keys, the
/// previous KEM generation and the founding key ([OwnKept]). That is what a
/// memory writes whose caller holds the identity; flag 1 stays the layout of
/// a node without an app. Both are read; no file is lost, and a flag-1 file
/// of the app is rewritten as flag 2 at its next start.
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
const int kVersionMailbox = 17;

/// What a mailbox remembers restart-proof: the own [OwnPostBox],
/// the [Contact]s and the invitations. Encrypted via
/// [FileEncryption] with a key passed by the caller — this
/// class derives none.
class Memory {
  final FileEncryption _enc;
  final String _path;

  /// The bytes as they last lay on disk — `null` until this instance has
  /// written or read the file. [save] compares against it, so the file is
  /// not rewritten when no content changed (S403, finding 5).
  Uint8List? _written;

  /// Whether this memory WRITES the secret keys of the own post box. Only
  /// for a node without an app (`myceliumd`, probes), for which this file is
  /// the one place its identity lives. With an app the keys stand in the
  /// app's store and come in at every start (`MailboxDetails.me`); a second
  /// copy here had no reader (S401, U-4).
  final bool secretKeys;
  OwnPostBox? _postBox;
  OwnKept? _kept;
  final Map<String, Contact> _contacts = {};

  Memory._(this._enc, this._path, this.secretKeys);

  /// Loads what lies in the directory, or creates an empty [Memory].
  /// If something lies there that cannot be read with [key]
  /// (wrong key, truncated, bent), this method throws
  /// [MemoryError] instead of a half instance.
  ///
  /// [now] is the clock in Unix seconds against which expired
  /// invitations are sorted out on loading (default: the system clock).
  /// It stands here and not in a field, so that a probe can check the expiry
  /// without adjusting the system time. [secretKeys]: see the field.
  static Memory open(Directory directory, Uint8List key,
      {int? now, bool secretKeys = false}) {
    directory.createSync(recursive: true);
    final path = '${directory.path}/$kFileMailbox';
    final enc = FileEncryption(baseDir: directory.path, key: key);
    final g = Memory._(enc, path, secretKeys);

    if (File('$path.enc').existsSync()) {
      final bytes = enc.readBinaryFile(path);
      if (bytes == null) {
        throw MemoryError(
            '$path.enc exists, but cannot be read — '
            'wrong key or damaged file');
      }
      g._decode(
          bytes, now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000);
      // What lies on disk — the comparison basis for [save]. A file that
      // does not re-encode identically (flag 1 instead of 2, expired
      // invitations, dropped introduction fields) is rewritten at its
      // next save, as before.
      g._written = bytes;
    }
    return g;
  }

  /// The own post box WITH its secret keys — what a file of a node without
  /// an app holds; `null` when none is set or the file holds no keys.
  OwnPostBox? get ownPostBox => _postBox;

  /// Address and previous day-key seed of the own post box — in every file.
  OwnKept? get ownKept => _kept;

  /// Sets the own post box. Checks the three key lengths
  /// against the crypto library, instead of only at the next round trip.
  /// Without [secretKeys] only [ownKept] is taken from it.
  set ownPostBox(OwnPostBox? b) {
    if (b != null) ownPostBoxCheck(b);
    _postBox = secretKeys ? b : null;
    _kept = b == null ? null : ownKeptOf(b);
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
    // S405 (proposal D): every change of the last observed address.
    final was = soFar?.lastSeen, seen = k.lastSeen;
    if (seen == null ? was != null : !(was?.equal(seen) ?? false)) {
      traceNote('contact $key: last observed address ${was ?? "none"} -> ${seen ?? "none"}');
    }
    return soFar != null && fresh;
  }

  /// Removes the contact with this address; no error if there was none.
  void contactForget(Address a) {
    if (_contacts.remove(_keyFor(a)) != null) traceNote('contact ${_keyFor(a)}: forgotten');
  }

  /// Writes the state encrypted and atomically (`FileEncryption.
  /// writeBinaryFile` / `atomicReplace`: first `.enc.tmp`, then renamed).
  /// A crash between the two steps leaves the previous
  /// `gedaechtnis.enc` intact — there is never an intermediate version under
  /// the canonical name.
  ///
  /// NOTHING NEW ON DISK WITHOUT A CONTENT CHANGE (S403, finding 5): every
  /// inbound delivery of a contact reached `contactRemember` and with it
  /// this save — although the adoption rule adopts most addresses not at
  /// all, and a pure re-delivery changes no byte. Identical bytes ARE
  /// identical content (the encoding is deterministic), so the write is
  /// skipped when it would reproduce what lies on disk.
  void save() {
    final bytes = _encode();
    final before = _written;
    if (before != null && before.length == bytes.length) {
      var same = true;
      for (var i = 0; i < bytes.length; i++) {
        if (before[i] != bytes[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _enc.writeBinaryFile(_path, bytes);
    _written = bytes;
  }

  Uint8List _encode() {
    final b = BytesBuilder();
    b.addByte(kVersionMailbox);
    // The secret keys only where this file is their one place ([secretKeys]);
    // a file read WITH keys is written without them otherwise (S401).
    ownWrite(b, secretKeys ? _postBox : null, _kept);
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
      final (bk, kept) = ownRead(l); // section: `memory_own.dart`
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
      _kept = kept;
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
