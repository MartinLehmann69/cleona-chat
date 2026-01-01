// The CONTENT of the recovery bundle (§13.3.2, "Content — Minimal Bundle
// (normative)").
//
// ── WHY AN OWN, SMALL ENCODING AND NO PROTOBUF ────────────
//
// The bundle has EXACTLY ONE reader: the same user, later, after a
// total loss. It does not travel to a peer, it knows no
// forward/backward compatibility between two parties, and §13.0
// weighs every byte hard: "an extra kilobyte in the recovery bundle
// weighs heavily, because every user pays it on every renewal."
//
// Protobuf would have three prices, all three of which would be uncovered here: a
// new `.proto` file including regeneration in the tree, field number overhead per
// entry (noticeable at ~105 B per contact), and a second place where
// the cut of the bundle is written. This encoding is instead
// length-prefixed, versioned and described in ONE place.
//
// ── WHAT THE DOCUMENT DEMANDS AND WHAT OF IT STANDS HERE ───────────────
//
// §13.3.2 lists eleven lines. Nine of them stand here. Two are missing, and
// NOT out of negligence:
//
//   * **"Shared Key (current)" and "per contact: the contact's
//     `inbox_key`".** Both rest on a MAILBOX LINE. The built
//     V4.1 has none: delivery lies per pair under
//     `secureTag(K_AB, …)` (`secure_mode.dart`), and §21.2 expressly denies the
//     quantity ("**No addressable storage location per
//     recipient**"). Rebuilding a second addressing next to `tag(K_AB)`
//     only so that a bundle field has a subject
//     would stand against §21.2 and against §15.6. The line is therefore NOT
//     built and has been presented to the owner (F-1 in
//     `docs/v4-redesign/S360-recovery-entwurf.md`, section 6.4/7).
//     Saving: 32 B per bundle plus 32 B per contact.
//   * **"prekey pool identifier (current state)".** §13.4.4 demands it,
//     and `prekey_pool.dart` keeps no `prekey_pool_epoch` — re-measured,
//     and named in `cleona_service.dart` (broadcast, §13.5.1) as an open
//     finding since S360. What exists is `PrekeyIndexSpace.issued`, a
//     monotonically growing issuance counter. It is NOT the identifier from
//     §13.4.4 (that is supposed to indicate a POOL BREAK) and is therefore
//     not output as such here either — [prekeysIssued] carries its
//     own name and its own meaning.
//
// ── WHAT THIS FILE DOES NOT DO ────────────────────────────────────────
//
// It seals nothing (that is done by `sealBundle` in `recovery_keys.dart`), it
// reads no contact list (the service does that) and it restores
// nothing. It is an encoding and its inverse, nothing else.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Identifier at the start of every bundle. It is the first check after
/// opening: a bundle whose AEAD carries but whose identifier does not
/// match is an error in the derivation and not a content problem.
const List<int> kBundleMagic = <int>[0x43, 0x52, 0x42, 0x00]; // "CRB\0"

/// Version of the bundle format.
///
/// 2 since S388 (`3f9d3b83`): every chain link carries `oldMlDsaPk`
/// (founding ML-DSA, v4.2 §4.1). A bundle of version 1 is discarded with
/// [BundleReadError.wrongVersion] — no conversion, there are
/// no legacy bundles.
///
/// 3 since S392: every chain link additionally carries `oldSignatureMlDsa`.
/// §4.5.4 lists the chain as a hybrid-signed proof; a chain that
/// only brings back the Ed25519 signature is no longer verifiable after recovery.
/// The same rule: version 2 is discarded.
const int kBundleFormatVersion = 3;

/// Why [RecoveryBundleContent.read] delivers no bundle — named, so that
/// "not mine" and "mine, but unusable" do not collapse into one `null`.
enum BundleReadError {
  /// No bundle identifier at the start — the bytes are not a bundle.
  noBundle,

  /// Bundle identifier matches, the version does not ([kBundleFormatVersion]).
  wrongVersion,

  /// Identifier and version match, the body does not fit (too short, remainder
  /// left over, unreadable text) — e.g. a chain link without `oldMlDsaPk`.
  broken,
}

/// The four verification levels from §15.7, as one byte.
///
/// The order is FROZEN — it is on the wire. The name-to-number
/// mapping lies here and not with the service, so that there is only one table.
const List<String> kVerificationLevels = <String>[
  'unverified',
  'seen',
  'verified',
  'trusted',
];

/// The three roles from §16 (Owner/Admin/Member), as one byte.
const List<String> kGroupRoles = <String>['owner', 'admin', 'member'];

/// A contact as the bundle carries it (§13.3.2, lines 4, 6, 7).
final class BundleContact {
  const BundleContact({
    required this.userId,
    required this.foundingEd25519Pk,
    required this.displayName,
    required this.verificationLevel,
    required this.deleted,
    required this.blocked,
  });

  /// The UserID (32 B). It is the identifier under which the service
  /// recreates the contact.
  final Uint8List userId;

  /// §13.3.2: "per contact: founding Ed25519 pubkey — `K_AB` derivation".
  /// THE load-bearing quantity of the whole bundle: without it no `K_AB`
  /// can be formed and thus not a single tag line (§15.2).
  final Uint8List foundingEd25519Pk;

  final String displayName;

  /// One of [kVerificationLevels].
  final String verificationLevel;

  /// §13.3.2: "deletion marker / block state — prevents deleted contacts
  /// from resurrecting via recovery (§15.9)". TWO bits, not one: in the
  /// build these are two different states (`_deletedContacts` versus
  /// `status == 'blocked'`), and merging them into one would mean
  /// guessing on recovery.
  final bool deleted;
  final bool blocked;
}

/// A member of a group, as the bundle carries it.
final class BundleGroupMember {
  const BundleGroupMember({required this.userId, required this.role});

  final Uint8List userId;

  /// One of [kGroupRoles].
  final String role;
}

/// A group or a channel (§13.3.2, last line: "group/channel
/// roster (IDs + member UserIDs) — rebuilding the sphere").
final class BundleGroup {
  const BundleGroup({
    required this.groupId,
    required this.name,
    required this.channel,
    required this.members,
  });

  final Uint8List groupId;
  final String name;

  /// `true` for a channel, `false` for a group. One bit instead of two
  /// lists — the way back is the same.
  final bool channel;

  final List<BundleGroupMember> members;
}

/// A link of the rotation chain (§13.3.2: "+ continuity chain … the chain
/// evidences founding -> current key").
final class BundleRotationLink {
  const BundleRotationLink({
    required this.oldEd25519Pk,
    required this.oldMlDsaPk,
    required this.newEd25519Pk,
    required this.newMlDsaPk,
    required this.oldSignatureEd25519,
    required this.oldSignatureMlDsa,
  });

  final Uint8List oldEd25519Pk;

  /// ML-DSA-65 before the rotation — carries in the first link the
  /// founding ML-DSA, without which the UserID (v4.2 §4.1) could not be
  /// recomputed after recovery (S388).
  final Uint8List oldMlDsaPk;
  final Uint8List newEd25519Pk;
  final Uint8List newMlDsaPk;
  final Uint8List oldSignatureEd25519;

  /// The ML-DSA-65 signature of the old pair over the same bytes (S392).
  /// §4.5.4 demands the chain hybrid-signed; if only the classic
  /// signature travelled in the bundle, the recovered chain would no longer be a
  /// hybrid proof and the author would not get back into the system channels
  /// (§16.7).
  final Uint8List oldSignatureMlDsa;
}

/// The recovery bundle of an identity, unsealed.
final class RecoveryBundleContent {
  const RecoveryBundleContent({
    required this.identityIndex,
    required this.displayName,
    required this.active,
    required this.ed25519SecretKey,
    required this.mlDsaSecretKey,
    required this.x25519SecretKey,
    required this.mlKemSecretKey,
    required this.rotationChain,
    required this.inviteGeneration,
    required this.inviteHighwater,
    required this.prekeysIssued,
    required this.contacts,
    required this.groups,
  });

  /// §13.3.2: „own `identity_index`, name + `active` flag".
  final int identityIndex;
  final String displayName;
  final bool active;

  /// §13.3.2: "current identity sig SKs (Ed25519 + ML-DSA-65)".
  ///
  /// WHY THEY TRAVEL ALONG AT ALL, although §13.1.1 says the 24 words
  /// yield "**all** key pairs deterministically": because after a
  /// ROTATION they are no longer the derived ones (§14.4). Without these lines
  /// the recovered identity is that of day 1, not that of
  /// today — and every peer that has seen the rotation would
  /// no longer recognise it.
  final Uint8List ed25519SecretKey;
  final Uint8List mlDsaSecretKey;

  /// §13.3.2: „current User-KEM-SK (X25519 + ML-KEM-768)".
  final Uint8List x25519SecretKey;
  final Uint8List mlKemSecretKey;

  final List<BundleRotationLink> rotationChain;

  /// §13.3.2: „`g_inv`, `Highwater` of the invite line — closes K-7".
  final int inviteGeneration;
  final int inviteHighwater;

  /// The issuance counter of the prekey pool (`PrekeyIndexSpace.issued`).
  ///
  /// **NOT the "prekey pool identifier" from §13.4.4** — see file header.
  /// It travels along because it is cheap (4 B per bundle) and because a
  /// recovered identity would otherwise continue issuing at 0 and thereby
  /// use indices twice that peers still hold.
  final int prekeysIssued;

  final List<BundleContact> contacts;
  final List<BundleGroup> groups;

  /// Encodes the bundle. Deterministic: the same inputs yield
  /// the same bytes — that is the prerequisite for a
  /// renewal without change being recognisable as such.
  Uint8List encode() {
    final w = _Writer();
    w.raw(kBundleMagic);
    w.u8(kBundleFormatVersion);
    w.u32(identityIndex);
    w.str(displayName);
    w.u8(active ? 1 : 0);
    w.blob(ed25519SecretKey);
    w.blob(mlDsaSecretKey);
    w.blob(x25519SecretKey);
    w.blob(mlKemSecretKey);
    w.u16(rotationChain.length);
    for (final l in rotationChain) {
      w.blob(l.oldEd25519Pk);
      w.blob(l.oldMlDsaPk);
      w.blob(l.newEd25519Pk);
      w.blob(l.newMlDsaPk);
      w.blob(l.oldSignatureEd25519);
      w.blob(l.oldSignatureMlDsa);
    }
    w.u32(inviteGeneration);
    // Highwater is -1 as long as no invitation has ever been issued
    // (`invite_ledger.dart`). Transmitted as unsigned 32 bits and
    // converted back on reading — an own sign byte would be one
    // byte for a single value.
    w.u32(inviteHighwater + 1);
    w.u32(prekeysIssued);
    w.u16(contacts.length);
    for (final c in contacts) {
      w.blob(c.userId);
      w.blob(c.foundingEd25519Pk);
      w.str(c.displayName);
      final step = kVerificationLevels.indexOf(c.verificationLevel);
      // An unknown level becomes `unverified`, not a throw:
      // a bundle that fails on a single odd contact
      // would be worse than one that classifies it cautiously.
      w.u8(step < 0 ? 0 : step);
      w.u8((c.deleted ? 1 : 0) | (c.blocked ? 2 : 0));
    }
    w.u16(groups.length);
    for (final g in groups) {
      w.blob(g.groupId);
      w.str(g.name);
      w.u8(g.channel ? 1 : 0);
      w.u16(g.members.length);
      for (final m in g.members) {
        w.blob(m.userId);
        final role = kGroupRoles.indexOf(m.role);
        w.u8(role < 0 ? 2 : role);
      }
    }
    return w.take();
  }

  /// Reads a bundle. Returns `null` if the bytes are not one —
  /// the reason is delivered by [read].
  static RecoveryBundleContent? decode(Uint8List bytes) => read(bytes).content;

  /// Reads a bundle: either `content` or a named `error`.
  ///
  /// NO THROW (§13.2.3): a recovery that crashes on a
  /// malformed bundle is worse than one that
  /// keeps searching. The caller distinguishes "nothing found" from
  /// "found, but unusable" — since S388 (K-4) with the reason from
  /// [BundleReadError] instead of from a bare `null`.
  static ({RecoveryBundleContent? content, BundleReadError? error}) read(
      Uint8List bytes) {
    if (bytes.length < kBundleMagic.length) {
      return (content: null, error: BundleReadError.noBundle);
    }
    try {
      final r = _Reader(bytes);
      final magic = r.raw(kBundleMagic.length);
      for (var i = 0; i < kBundleMagic.length; i++) {
        if (magic[i] != kBundleMagic[i]) {
          return (content: null, error: BundleReadError.noBundle);
        }
      }
      if (r.u8() != kBundleFormatVersion) {
        return (content: null, error: BundleReadError.wrongVersion);
      }
      final index = r.u32();
      final name = r.str();
      final isActive = r.u8() != 0;
      final edSk = r.blob();
      final dsaSk = r.blob();
      final xSk = r.blob();
      final kemSk = r.blob();
      final chain = <BundleRotationLink>[];
      final chainLength = r.u16();
      for (var i = 0; i < chainLength; i++) {
        chain.add(BundleRotationLink(
          oldEd25519Pk: r.blob(),
          oldMlDsaPk: r.blob(),
          newEd25519Pk: r.blob(),
          newMlDsaPk: r.blob(),
          oldSignatureEd25519: r.blob(),
          oldSignatureMlDsa: r.blob(),
        ));
      }
      final gen = r.u32();
      final high = r.u32() - 1;
      final assigned = r.u32();
      final contactList = <BundleContact>[];
      final contactNumber = r.u16();
      for (var i = 0; i < contactNumber; i++) {
        final userId = r.blob();
        final founding = r.blob();
        final display = r.str();
        final step = r.u8();
        final flags = r.u8();
        contactList.add(BundleContact(
          userId: userId,
          foundingEd25519Pk: founding,
          displayName: display,
          verificationLevel: step < kVerificationLevels.length
              ? kVerificationLevels[step]
              : kVerificationLevels[0],
          deleted: (flags & 1) != 0,
          blocked: (flags & 2) != 0,
        ));
      }
      final groupList = <BundleGroup>[];
      final groupsNumber = r.u16();
      for (var i = 0; i < groupsNumber; i++) {
        final id = r.blob();
        final gname = r.str();
        final channel = r.u8() != 0;
        final members = <BundleGroupMember>[];
        final mNumber = r.u16();
        for (var j = 0; j < mNumber; j++) {
          final mid = r.blob();
          final role = r.u8();
          members.add(BundleGroupMember(
              userId: mid,
              role: role < kGroupRoles.length
                  ? kGroupRoles[role]
                  : kGroupRoles[2]));
        }
        groupList.add(BundleGroup(
            groupId: id, name: gname, channel: channel, members: members));
      }
      if (!r.atEnd) {
        return (content: null, error: BundleReadError.broken);
      }
      final content = RecoveryBundleContent(
        identityIndex: index,
        displayName: name,
        active: isActive,
        ed25519SecretKey: edSk,
        mlDsaSecretKey: dsaSk,
        x25519SecretKey: xSk,
        mlKemSecretKey: kemSk,
        rotationChain: chain,
        inviteGeneration: gen,
        inviteHighwater: high,
        prekeysIssued: assigned,
        contacts: contactList,
        groups: groupList,
      );
      return (content: content, error: null);
    } catch (_) {
      return (content: null, error: BundleReadError.broken);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────

final class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void raw(List<int> v) => _b.add(v);

  void u8(int v) => _b.addByte(v & 0xff);

  void u16(int v) {
    if (v < 0 || v > 0xffff) throw ArgumentError('u16 out of range: $v');
    _b
      ..addByte((v >> 8) & 0xff)
      ..addByte(v & 0xff);
  }

  void u32(int v) {
    if (v < 0 || v > 0xffffffff) throw ArgumentError('u32 out of range: $v');
    _b
      ..addByte((v >> 24) & 0xff)
      ..addByte((v >> 16) & 0xff)
      ..addByte((v >> 8) & 0xff)
      ..addByte(v & 0xff);
  }

  void blob(Uint8List v) {
    u16(v.length);
    _b.add(v);
  }

  void str(String s) => blob(Uint8List.fromList(utf8.encode(s)));

  Uint8List take() => _b.takeBytes();
}

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

  int u8() {
    if (_o >= _b.length) throw StateError('too short');
    return _b[_o++];
  }

  int u16() => (u8() << 8) | u8();

  int u32() => (u16() << 16) | u16();

  Uint8List blob() => raw(u16());

  String str() => utf8.decode(blob());
}
