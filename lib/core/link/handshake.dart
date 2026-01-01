/// The V4 link handshake — AP-3a stage 2 (architecture v4 §2.6, E-78 to E-84).
///
/// This file assembles the three building blocks that each stand on their
/// own: [LinkMac] (epoch and MAC, E-78/E-80), [LinkReplayBuffer] (E-79) and
/// [NodeKeys] (E-81/E-82). What it contributes is the **order** — and that
/// is the security-relevant part.
///
/// **The sequence (§2.6, E-82).** From the responder's entry record the
/// initiator knows: `L_node` (32 B), `N_x25519_pub` (32 B), `N_mlkem_pub`
/// (1184 B).
///
/// ```
/// Flight 1  (initiator -> responder), exactly 1200 B:
///   E2(eph_pub)                          32 B   offset    0
///   MAC(L_node, E2(eph_pub) || epoch)    16 B   offset   32
///   AEAD_{k_prov}( mlkem_ct || PAD )   1152 B   offset   48
///
/// Flight 2  (responder -> initiator), exactly 1200 B:
///   E2(resp_eph_pub)                     32 B   offset    0
///   AEAD_{k_prov}( confirm || PAD )    1168 B   offset   32
/// ```
///
/// Both flights are **the same size**. That is not cosmetics: a 1184-B
/// answer to a 48-B `init` would be an amplification lever of ~25x
/// against a sender who only knows `L_node`. V3 already rejected the same
/// trade at 4-5x (`BUGFIX_CURRENT.md:3888`).
///
/// **The responder's check order is normative, not taste:**
///
/// 1. MAC in constant time (§2.6). Only after that is anything computed.
/// 2. Ring buffer (E-79). A hit behaves **exactly** like a MAC failure —
///    the same `null`, the same path, no branch of its own and no log
///    entry. A distinguishable behaviour would be exactly the measurable
///    difference that §2.6 excludes.
/// 3. Only now Elligator decoding, X25519 and AEAD opening.
/// 4. Only now the ML-KEM decapsulation.
///
/// Whoever pulls 3 or 4 ahead of 1 makes the node a computing drudge for
/// everyone who knows the address — exactly what the `L_node` binding
/// prevents (E-58).
///
/// **Failure is always `null`.** No result type of this file distinguishes
/// "MAC wrong" from "already seen" from "AEAD broken". The caller has
/// nothing by which he could distinguish, and therefore cannot break the
/// guarantee by accident.
///
/// **The rotation overlap and the constant time interlock**
/// (E-81 against E-78, not yet reconciled in the document — see
/// [_verifyInitMacAcrossKeys]).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link/elligator_ffi.dart';
import 'package:cleona/core/link/link_kdf.dart';
import 'package:cleona/core/link/link_mac.dart';
import 'package:cleona/core/link/node_keys.dart';
import 'package:cleona/core/link/replay_buffer.dart';

/// Size of every handshake flight — the same as a cell (§4d.11).
const int kHandshakeFlightSize = 1200;

/// Offsets and lengths in flight 1.
const int kE2Length = 32;
const int kMacOffset = 32;
const int kAeadOffset1 = 48;
const int kAeadLength1 = kHandshakeFlightSize - kAeadOffset1; // 1152

/// Offsets and lengths in flight 2.
const int kAeadOffset2 = 32;
const int kAeadLength2 = kHandshakeFlightSize - kAeadOffset2; // 1168

/// AES-256-GCM: 12 B nonce in front, 16 B tag at the back.
const int kAeadNonceLength = 12;
const int kAeadTagLength = 16;

/// Plaintext capacity of the two AEAD blocks.
const int kAeadPlaintext1 = kAeadLength1 - kAeadNonceLength - kAeadTagLength;

/// Where in the plaintext of flight 1 the caller names his position
/// (decision C, 2026-08-22).
///
/// It lies BEHIND the ML-KEM ciphertext, in the remainder that used to be
/// padding — flight 1 has exactly 36 free bytes there, and the statement
/// needs 32. Thus the caller's authentication costs not a single
/// additional packet and no second round trip.
///
/// It stands INSIDE the AEAD. An eavesdropper does not see it; only
/// whoever holds the callee's static X25519 key can read it, because only
/// from that does `k_prov` arise.
const int kClaimOffset1 = OqsFFI.mlKemCiphertextLength;
const int kClaimLength = 32;

/// Where in the plaintext of flight 2 the answer to the position statement
/// stands.
///
/// WHY THIS BYTE IS NEEDED. The callee only mixes in the static-static
/// secret if he KNOWS the caller. If the caller did not know that, he
/// would, in case of doubt, derive a different key than the callee, and
/// the connection would silently fail — precisely when meeting for the
/// first time. The byte is covered by the AEAD and cannot be flipped in
/// transit.
const int kAuthFlagOffset2 = 32;
const int kAeadPlaintext2 = kAeadLength2 - kAeadNonceLength - kAeadTagLength;

/// Where in the plaintext of flight 2 the mirror of the observed sender
/// address stands (§17.3, owner decision 2026-08-31).
///
/// WHY FLIGHT 2 AND NOT FLIGHT 1. The mirror can only be written by whoever
/// has already SEEN the sender's datagram — that is the responder. And in
/// flight 1 there is no room anyway: appendix A measures its free budget at
/// 36 B (1124 B plaintext minus 1088 B ML-KEM ciphertext), and since 22.08.
/// those are completely assigned to [kClaimOffset1].
///
/// IT STANDS INSIDE THE AEAD, for the same reason as [kAuthFlagOffset2]:
/// covered by the AEAD and not flippable in transit. A mirror outside
/// would be a field that every forwarder can bend to an address of his
/// choice — and the reader afterwards takes the result for his own
/// address.
///
/// FIXED LENGTH, ALWAYS 19 B. A length-dependent encoding (4 B for IPv4,
/// 16 B for IPv6) would be a size difference on a line on which both
/// flights are deliberately exactly the same size (file header, E-82). It
/// does not stand out here, because the remainder is padding — but a field
/// whose length depends on the content is exactly the construction that
/// later lets a size show through.
///
/// ```
///   +0    address family     1 B   0 = not specified, 4 = IPv4, 6 = IPv6
///   +1    address           16 B   IPv4: the 4 B in front, the 12 B behind zero
///                                  IPv6: the full 16 B
///   +17   port               2 B   big endian
/// ```
///
/// WHY A FAMILY BYTE AND NOT IPv4-MAPPED. Writing an IPv4 address as
/// `::ffff:a.b.c.d` in 16 B encodes the family a SECOND time — once in the
/// prefix, once in the byte in front. Two sources for one fact means: a
/// reader who believes the prefix and one who believes the byte can
/// differ. Plus the practical side: `local_addresses.dart` explicitly
/// throws away `::ffff:` addresses (`isTunnelIpv6`, WIN-2), because nobody
/// arrives under them. A mirror that returns such an address delivers a
/// candidate that the other side subsequently sorts out — i.e. nothing.
///
/// The values 4 and 6 instead of 0 and 1, because 0 is needed: **0 means
/// "nothing said"**. An older writer that does not know this field leaves
/// the padding at zero; exactly then [ObservedAddress.decode] reads
/// `null` and the reader has NO observation instead of a wrong one. 4 and
/// 6 moreover read in a hexdump as what they are.
const int kObservedOffset2 = kAuthFlagOffset2 + 1;
const int kObservedLength = 19;

/// The address under which a partner has seen this node arrive
/// (§17.3 "observed address" instead of STUN).
///
/// **What it is, and what it is not.** It is the statement of EXACTLY ONE
/// partner. It is not a measured value that one takes once and afterwards
/// considers true: the partner can be mistaken (he sees the address of his
/// own NAT path) and he can lie. That is why `ObservedAddressBook`
/// (`lib/core/link_io/link_host.dart`) exists — it holds the statements
/// SIDE BY SIDE and reports contradiction as a finding instead of
/// declaring one of them the truth. Two partners naming different ports
/// are the textbook picture of a symmetric NAT (§17.3) and not an error.
final class ObservedAddress {
  /// IPv6 if true; otherwise IPv4. No `null` case: an observation without
  /// a family does not exist, it is not built in the first place.
  final bool isIpv6;

  /// 4 B for IPv4, 16 B for IPv6 — in network order, as
  /// `InternetAddress.rawAddress` delivers them.
  final Uint8List rawAddress;

  /// The observed source port, 1..65535.
  final int port;

  ObservedAddress._(this.isIpv6, this.rawAddress, this.port);

  /// Builds an observation from raw address bytes.
  ///
  /// Throws [ArgumentError] for everything that is not an address — the
  /// caller is the receive path and has the bytes from the operating
  /// system, where a wrong length is a programming error and not a network
  /// event.
  ///
  /// **IPv4-mapped is unpacked.** Both families bind the same port
  /// (`udp_sockets.dart`), and with `bindv6only=0` an IPv4 sender can
  /// appear at the IPv6 socket as `::ffff:a.b.c.d`. Mirrored back
  /// unpacked, that would be an IPv6 candidate under which nobody is
  /// reachable — exactly the address class that `local_addresses.dart`
  /// throws away on the local half (WIN-2). It is therefore reduced to its
  /// four bytes here, at the one place.
  factory ObservedAddress.fromRaw(Uint8List rawAddress, int port) {
    if (port < 1 || port > 65535) {
      throw ArgumentError('Port outside 1..65535: $port');
    }
    if (rawAddress.length == 4) {
      return ObservedAddress._(false, Uint8List.fromList(rawAddress), port);
    }
    if (rawAddress.length != 16) {
      throw ArgumentError(
          'Address must be 4 or 16 B, not ${rawAddress.length}');
    }
    if (_isV4Mapped(rawAddress)) {
      return ObservedAddress._(
          false, Uint8List.fromList(rawAddress.sublist(12, 16)), port);
    }
    return ObservedAddress._(true, Uint8List.fromList(rawAddress), port);
  }

  static bool _isV4Mapped(Uint8List a) {
    for (var i = 0; i < 10; i++) {
      if (a[i] != 0) return false;
    }
    return a[10] == 0xff && a[11] == 0xff;
  }

  /// The 19 B of the field.
  Uint8List encode() {
    final out = Uint8List(kObservedLength);
    out[0] = isIpv6 ? 6 : 4;
    out.setRange(1, 1 + rawAddress.length, rawAddress);
    // The rest of the 16 B stays zero for IPv4 — and the reader insists on it.
    out[17] = (port >> 8) & 0xff;
    out[18] = port & 0xff;
    return out;
  }

  /// Reads the field from [offset]. `null` means **no observation**, and
  /// for ANY reason: zero padding of an old writer, unknown family, port 0,
  /// set bytes behind an IPv4.
  ///
  /// **Why strict.** A reader that still assembles an address from a
  /// half-filled field delivers to its caller a candidate at which nobody
  /// listens — and the caller cannot distinguish it from a real one.
  /// `null` he can distinguish. Exactly that is the guarantee for the old
  /// writer: zeros yield NO address, never `0.0.0.0:0`.
  static ObservedAddress? decode(Uint8List field, [int offset = 0]) {
    if (field.length < offset + kObservedLength) return null;
    final family = field[offset];
    if (family != 4 && family != 6) return null; // 0 = old writer
    final port = (field[offset + 17] << 8) | field[offset + 18];
    if (port == 0) return null; // no datagram has source port 0
    if (family == 4) {
      for (var i = offset + 5; i < offset + 17; i++) {
        if (field[i] != 0) return null; // IPv4 with garbage in the rest
      }
      return ObservedAddress._(
          false, Uint8List.fromList(field.sublist(offset + 1, offset + 5)),
          port);
    }
    return ObservedAddress._(
        true, Uint8List.fromList(field.sublist(offset + 1, offset + 17)), port);
  }

  /// The address in the text form that `LinkEndpoint.host` carries
  /// (`lib/core/link/connect.dart`) — so that a candidate becomes a dial
  /// target without a detour.
  String get host {
    if (!isIpv6) return rawAddress.join('.');
    final parts = <String>[];
    for (var i = 0; i < 16; i += 2) {
      parts.add(((rawAddress[i] << 8) | rawAddress[i + 1]).toRadixString(16));
    }
    return parts.join(':');
  }

  @override
  bool operator ==(Object other) =>
      other is ObservedAddress &&
      other.isIpv6 == isIpv6 &&
      other.port == port &&
      _sameBytes(other.rawAddress, rawAddress);

  @override
  int get hashCode => Object.hash(isIpv6, port, Object.hashAll(rawAddress));

  @override
  String toString() => isIpv6 ? '[$host]:$port' : '$host:$port';

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Info label of the provisional key derivation (§2.6, E-82).
const String kProvInfoLabel = 'link/prov/v1';

/// Domain label of the response confirmation.
///
/// **Not specified in §2.6.** The section writes for flight 2
/// `AEAD_{k_prov}(confirmation || padding)` and leaves `confirmation` open.
/// That is not cosmetics: `k_prov` depends on X25519 alone, opening the
/// AEAD thus only proves that the other side possesses `N_x25519_sk` —
/// **not** that it has decapsulated. Without binding to `mlkem_ss`,
/// flight 2 does not confirm the PQ part of the handshake. Built here as
/// `HMAC(mlkem_ss, label || E2(eph_pub) || E2(resp_eph_pub))`, full 32 B;
/// submitted as a documentation follow-up to §2.6.
const String kRespConfirmLabel = 'link/resp-confirm/v1';

/// Result of a successful handshake — from the point of view of **this** side.
///
/// **No consumer ever chooses a direction (Z-1).** The two cell keys are
/// called [sendKey] and [recvKey], not `cellKeyInit` and `cellKeyResp`.
/// Exactly two places know the role — [LinkHandshake
/// .openFlight2] on the initiator side and [LinkHandshake.handleFlight1] on
/// the responder side —, and only they fill the fields. Whoever seals a
/// cell afterwards takes [sendKey]; whoever opens one takes [recvKey].
///
/// The rejected form held both raw keys under their derivation names and
/// left the mapping to the caller. It was weaker for two reasons: the role
/// was gone as soon as the session lay in a variable, and an additional
/// role field would have reintroduced it as **settable data** — wrongly
/// fillable at the same place where today the mapping is structurally
/// fixed. Raw fields therefore do not stand next to them; a second path to
/// the same key would be exactly the confusion this form rules out.
///
/// The derivation labels stay `cell/init` and `cell/resp` (§4d.11): the
/// wire format is untouched, the change is purely on the API side.
class LinkSession {
  /// 32-B root key per §2.6 point 3.
  ///
  /// Remains visible as a named root, because future derivations need it
  /// (`link_kdf.dart`); it is not a cell key.
  final Uint8List linkKey;

  /// Cell key for cells that **this** side sends (§4d.11).
  final Uint8List sendKey;

  /// Cell key for cells that **this** side receives (§4d.11).
  final Uint8List recvKey;

  /// The position of the other end — set if it identified itself AND we
  /// knew it (decision C).
  ///
  /// WHAT IT MEANS, and what not. The authentication is IMPLICIT: here
  /// stands the position against which the key was formed. If the other
  /// end lied, it has a different key and can open nothing we send. That
  /// is why it is harmless to use the attribution immediately: forwarded to
  /// an impostor means discarded, not betrayed.
  final Uint8List? peerPosition;

  /// The own address as the partner observed it (§17.3).
  ///
  /// **Only ever set on the initiator side**, and that is not a gap but
  /// the direction of the field: the mirror is written by whoever saw the
  /// datagram (the responder), and it stands in flight 2 — so it is read
  /// by whoever receives flight 2. A node consequently learns its outer
  /// address from the links it opens ITSELF. Since §4.3 runs the sync in
  /// both directions, every node is initiator on part of its links;
  /// whoever is only called learns nothing here and stays without an
  /// observation — visible as `null`, not as a wrong address.
  ///
  /// `null` also means: the partner mirrored nothing (old state, or a
  /// caller of [handleFlight1] that does not know the source address —
  /// the stream transport, for example).
  final ObservedAddress? observedSelf;

  const LinkSession({
    required this.linkKey,
    required this.sendKey,
    required this.recvKey,
    this.peerPosition,
    this.observedSelf,
  });
}

/// State of the initiator between flight 1 and flight 2.
class InitiatorPending {
  final Uint8List flight1;
  final Uint8List e2EphPub;
  final Uint8List _ephSecret;
  final Uint8List _kProv;
  final Uint8List _mlkemSs;

  /// The static-static secret — only set if the caller identified
  /// himself.
  final Uint8List? _staticSs;

  /// The position that was called.
  ///
  /// The caller ALWAYS knows it — he picked the entry record from which he
  /// dials. And the handshake proves it to him: only whoever holds the
  /// associated static secrets can form `k_prov` and decapsulate. The
  /// direction callee->caller was thus always authenticated; decision C
  /// adds the opposite direction.
  final Uint8List _dialedPosition;

  const InitiatorPending._({
    required this.flight1,
    required this.e2EphPub,
    required Uint8List ephSecret,
    required Uint8List kProv,
    required Uint8List mlkemSs,
    Uint8List? staticSs,
    required Uint8List dialedPosition,
    // ignore: prefer_initializing_formals
  })  : _staticSs = staticSs,
        // ignore: prefer_initializing_formals
        _dialedPosition = dialedPosition,
        // ignore: prefer_initializing_formals
        _ephSecret = ephSecret,
        // ignore: prefer_initializing_formals
        _kProv = kProv,
        // ignore: prefer_initializing_formals
        _mlkemSs = mlkemSs;
}

/// Result of the responder side: the flight 2 to be sent plus the session.
class ResponderResult {
  final Uint8List flight2;
  final LinkSession session;

  const ResponderResult(this.flight2, this.session);
}

/// Delivers the static X25519 key for a position, if the node knows it.
///
/// Deliberately a callback and not a type from the delivery layer: the
/// link layer should not have to know the entry stock. It only asks "do I
/// know that one?" and gets the one number it needs.
typedef StaticKeyLookup = Uint8List? Function(Uint8List position);

abstract final class LinkHandshake {
  static final SodiumFFI _sodium = SodiumFFI();
  static final OqsFFI _oqs = OqsFFI()..init();

  // ── Initiator ────────────────────────────────────────────────────────

  /// Builds flight 1 against the static node keys from the entry record.
  ///
  /// [seed] are 32 B of randomness; the buffer is wiped by
  /// [ElligatorFFI.keyPair] and must not be reused afterwards.
  static InitiatorPending buildFlight1({
    required Uint8List lNode,
    required Uint8List nX25519Pub,
    required Uint8List nMlKemPub,
    required Uint8List seed,
    DateTime? now,
    String? channel,
    Uint8List? claimPosition,
    Uint8List? ownStaticX25519Secret,
  }) {
    final kp = ElligatorFFI().keyPair(seed);
    final e2 = kp.hidden;
    final ephSk = kp.secretKey;

    final mac = LinkMac.computeInitMac(
        lNode, e2, LinkMac.currentLinkEpoch(now: now));

    // k_prov depends on the responder's STATIC X25519 key — that is why the
    // initiator can already form it for flight 1, and that is why the
    // handshake costs only one round trip (E-82).
    final provSs = _sodium.x25519ScalarMult(ephSk, nX25519Pub);
    final kProv = _deriveKProv(provSs, channel);

    final enc = _oqs.mlKemEncapsulate(nMlKemPub);
    final inner = Uint8List(kAeadPlaintext1)
      ..setRange(0, enc.ciphertext.length, enc.ciphertext);

    // Decision C: the caller names his position in the free bytes and forms
    // the same static-static secret that the callee can form from his
    // stock. Whoever names nothing stays anonymous — the slot then stays
    // zero and cannot be distinguished from padding in the ciphertext.
    Uint8List? staticSs;
    if (claimPosition != null && ownStaticX25519Secret != null) {
      if (claimPosition.length != kClaimLength) {
        throw ArgumentError('Position claim must be $kClaimLength B');
      }
      inner.setRange(
          kClaimOffset1, kClaimOffset1 + kClaimLength, claimPosition);
      staticSs = _sodium.x25519ScalarMult(ownStaticX25519Secret, nX25519Pub);
    }
    // The rest stays zero — the padding lies in the ciphertext, on the
    // line it cannot be distinguished from payload.

    final flight = Uint8List(kHandshakeFlightSize)
      ..setRange(0, kE2Length, e2)
      ..setRange(kMacOffset, kAeadOffset1, mac)
      ..setRange(kAeadOffset1, kHandshakeFlightSize, _seal(inner, kProv));

    return InitiatorPending._(
      flight1: flight,
      staticSs: staticSs,
      dialedPosition: Uint8List.fromList(lNode),
      e2EphPub: e2,
      ephSecret: ephSk,
      kProv: kProv,
      mlkemSs: enc.sharedSecret,
    );
  }

  /// Processes flight 2. `null` = failure, without a distinguishable reason.
  static LinkSession? openFlight2(InitiatorPending pending, Uint8List flight2,
      {String? channel}) {
    if (flight2.length != kHandshakeFlightSize) return null;

    final e2Resp = Uint8List.sublistView(flight2, 0, kE2Length);
    final inner = _open(
        Uint8List.sublistView(flight2, kAeadOffset2), pending._kProv);
    if (inner == null) return null;

    final expected = _confirmTag(pending._mlkemSs, pending.e2EphPub, e2Resp);
    final got = Uint8List.sublistView(inner, 0, expected.length);
    if (!_constantTimeEquals(expected, got)) return null;

    // Did the callee recognise us? If the byte is 1, the static-static
    // secret must go in as well — otherwise the two sides would arrive at
    // different keys.
    final authenticated = inner[kAuthFlagOffset2] == 1;
    if (authenticated && pending._staticSs == null) return null;

    // The mirror (§17.3). It stands in the padding: a state without this
    // field writes zeros there, and `decode` then yields `null` — NO
    // observation, not `0.0.0.0:0`. The handshake depends on it in no
    // branch; it succeeds with and without a mirror alike.
    final observed = ObservedAddress.decode(inner, kObservedOffset2);

    final respPub = ElligatorFFI().map(Uint8List.fromList(e2Resp));
    final x25519Ss = _sodium.x25519ScalarMult(pending._ephSecret, respPub);
    return _session(x25519Ss, pending._mlkemSs, channel,
        asInitiator: true,
        staticSs: authenticated ? pending._staticSs : null,
        peerPosition: pending._dialedPosition,
        observedSelf: observed);
  }

  // ── Responder ────────────────────────────────────────────────────────

  /// Processes flight 1 and builds flight 2. `null` = silence.
  ///
  /// The order in the body is the one from the file header and must not
  /// be rearranged.
  static ResponderResult? handleFlight1({
    required NodeKeys keys,
    required LinkReplayBuffer replay,
    required Uint8List flight1,
    required Uint8List respSeed,
    DateTime? now,
    String? channel,
    StaticKeyLookup? lookupStatic,
    ObservedAddress? observed,
  }) {
    if (flight1.length != kHandshakeFlightSize) return null;

    final e2 = Uint8List.fromList(
        Uint8List.sublistView(flight1, 0, kE2Length));
    final mac = Uint8List.fromList(
        Uint8List.sublistView(flight1, kMacOffset, kAeadOffset1));

    // 1. MAC — vor jeder Rechnung.
    if (!_verifyInitMacAcrossKeys(keys, e2, mac, now)) return null;

    // 2. Ring buffer — the same return value as a MAC failure.
    if (replay.isReplay(e2, now: now)) return null;

    // 3. Only now the expensive work.
    //
    // TWO KEY SETS, and why. Since the rotation renews ALL static node keys
    // (§4.5), a peer who holds an entry record from before the rotation
    // addresses the old keys — he cannot know better, his stock is simply
    // older. The 30-day overlap previously covered only `L_node` and would
    // thus have become worthless: the MAC would have matched and the
    // decapsulation would have failed. So the old set is tried as well as
    // long as the window is open. After that the node stays silent, as it
    // also stays silent on a MAC failure.
    final ephPub = ElligatorFFI().map(e2);
    final current = _tryKeySet(
        x25519Secret: keys.nX25519Secret,
        mlKemSecret: keys.nMlKemSecret,
        flight1: flight1,
        e2: e2,
        ephPub: ephPub,
        respSeed: respSeed,
        channel: channel,
        lookupStatic: lookupStatic,
        observed: observed);
    if (current != null) return current;

    if (!keys.previousStaticUsable(now: now)) return null;
    return _tryKeySet(
        x25519Secret: keys.previousNX25519Secret!,
        mlKemSecret: keys.previousNMlKemSecret!,
        flight1: flight1,
        e2: e2,
        ephPub: ephPub,
        respSeed: respSeed,
        channel: channel,
        lookupStatic: lookupStatic,
        observed: observed);
  }

  /// One attempt with ONE static key set.
  static ResponderResult? _tryKeySet({
    required Uint8List x25519Secret,
    required Uint8List mlKemSecret,
    required Uint8List flight1,
    required Uint8List e2,
    required Uint8List ephPub,
    required Uint8List respSeed,
    String? channel,
    StaticKeyLookup? lookupStatic,
    ObservedAddress? observed,
  }) {
    final provSs = _sodium.x25519ScalarMult(x25519Secret, ephPub);
    final kProv = _deriveKProv(provSs, channel);

    final inner = _open(Uint8List.sublistView(flight1, kAeadOffset1), kProv);
    if (inner == null) return null;

    final ct = Uint8List.sublistView(inner, 0, OqsFFI.mlKemCiphertextLength);
    final Uint8List mlkemSs;
    try {
      mlkemSs = _oqs.mlKemDecapsulate(Uint8List.fromList(ct), mlKemSecret);
    } catch (_) {
      return null;
    }

    // Decision C: if the caller named a position AND we know it, the
    // static-static secret goes into the key. Whoever merely claims the
    // position cannot form it — he gets a different key and afterwards
    // cannot open a single cell. There is no rejection, and that is
    // intentional: a rejection would be an oracle about whom this node
    // knows.
    final claim = Uint8List.fromList(
        Uint8List.sublistView(inner, kClaimOffset1, kClaimOffset1 + kClaimLength));
    Uint8List? staticSs;
    Uint8List? peerPosition;
    if (lookupStatic != null && !_isZero(claim)) {
      final peerStatic = lookupStatic(claim);
      if (peerStatic != null) {
        staticSs = _sodium.x25519ScalarMult(x25519Secret, peerStatic);
        peerPosition = claim;
      }
    }

    final kp = ElligatorFFI().keyPair(respSeed);
    final confirm = _confirmTag(mlkemSs, e2, kp.hidden);
    final innerOut = Uint8List(kAeadPlaintext2)
      ..setRange(0, confirm.length, confirm)
      ..[kAuthFlagOffset2] = staticSs != null ? 1 : 0;

    // The mirror (§17.3). If the caller does not know the source address,
    // the field stays zero — the same picture as with an older state, and
    // the reader over there turns it into "no observation". The size of
    // the flight does not change: the field lies in the padding that is
    // sent along anyway.
    if (observed != null) {
      innerOut.setRange(kObservedOffset2, kObservedOffset2 + kObservedLength,
          observed.encode());
    }

    final flight2 = Uint8List(kHandshakeFlightSize)
      ..setRange(0, kE2Length, kp.hidden)
      ..setRange(kAeadOffset2, kHandshakeFlightSize, _seal(innerOut, kProv));

    final x25519Ss = _sodium.x25519ScalarMult(kp.secretKey, ephPub);
    return ResponderResult(
        flight2,
        _session(x25519Ss, mlkemSs, channel,
            asInitiator: false, staticSs: staticSs, peerPosition: peerPosition));
  }

  /// Constant time — whether a position was named must not be readable
  /// from the timing behaviour.
  static bool _isZero(Uint8List b) {
    var acc = 0;
    for (final x in b) {
      acc |= x;
    }
    return acc == 0;
  }

  /// Does [datagram] carry this node's `init` MAC?
  ///
  /// **Why the demux must ask this separately (E-104/E-111).**
  /// [handleFlight1] returns the same `null` on a MAC failure AND on a
  /// replay hit — indistinguishable from outside, as E-79 wants it. But the
  /// demux needs the distinction **internally**: a replayed `init` must not
  /// fall through into the session search, otherwise it costs MORE work than
  /// a forgery, and exactly this difference would be measurable from
  /// outside. With this question asked in advance: MAC matches → responder
  /// path, and what that returns stays silence; MAC does not match →
  /// session search.
  ///
  /// The computation itself stays here, next to [LinkMac.verifyInitMac], so
  /// that it stands under the constant-time guard: in the open rotation
  /// window both `L_node` are computed unconditionally and only then ORed
  /// (E-87).
  ///
  /// A wrong length is not an `init`, but also no reason to compute.
  static bool acceptsInitMac(NodeKeys keys, Uint8List datagram,
      {DateTime? now}) {
    if (datagram.length != kHandshakeFlightSize) return false;
    return acceptsInitMacPrefix(keys, datagram, now: now);
  }

  /// Like [acceptsInitMac], but already on the first **48 B**.
  ///
  /// **Why this version exists, and why it is not the only one.**
  /// On **UDP** the length check of [acceptsInitMac] is part of the
  /// statement: a datagram of the wrong size is not a flight, and the check
  /// costs nothing there, because the whole datagram is there anyway.
  /// On a **stream** it is a trap — there the flight arrives in pieces, and
  /// whoever waits until 1 200 B to check the MAC holds a file descriptor
  /// **25 times longer than necessary**.
  ///
  /// The MAC fields lie completely in the prefix: `E2(eph_pub)` 32 B from
  /// offset 0, `MAC(L_node, E2 ‖ epoch)` 16 B from offset 32, and only from
  /// 48 does the AEAD begin. Measured, the abort after a failed MAC costs
  /// **~5.7 µs**, the full responder path **0.310 ms** — ratio
  /// **54 : 1**. Exactly these 48 are also named by E-83 when it forbids an
  /// immediate teardown "after exactly 48 bytes read" as a **signature**.
  ///
  /// Constant time stays untouched: it is the same path, the same six
  /// HMACs with an open rotation window (E-78, E-81, E-87).
  static bool acceptsInitMacPrefix(NodeKeys keys, Uint8List prefix,
      {DateTime? now}) {
    if (prefix.length < kAeadOffset1) return false;
    final e2 = Uint8List.fromList(
        Uint8List.sublistView(prefix, 0, kE2Length));
    final mac = Uint8List.fromList(
        Uint8List.sublistView(prefix, kMacOffset, kAeadOffset1));
    return _verifyInitMacAcrossKeys(keys, e2, mac, now);
  }

  // ── Innere Bausteine ─────────────────────────────────────────────────

  /// Checks the MAC against the current and — in the open overlap window —
  /// the previous `L_node`.
  ///
  /// **Here two decisions interlock that the document made separately.**
  /// E-78 requires constant time; E-81 permits two values for 30 days
  /// after a rotation. A pass that aborts on the first key's hit leaks via
  /// the running time **which one** matched — from outside it would thus be
  /// measurable whether a node has recently rotated. That is why, with an
  /// open window, the check is **always** against both keys, i.e. six HMACs
  /// instead of three, regardless of the result.
  ///
  /// That an observer could see the transition "window open" -> "window
  /// closed" over 30 days is accepted: it is not controllable per
  /// connection and carries no secret.
  static bool _verifyInitMacAcrossKeys(
      NodeKeys keys, Uint8List e2, Uint8List mac, DateTime? now) {
    final current = LinkMac.verifyInitMac(keys.lNode, e2, mac, now: now);

    final prev = keys.previousLNode;
    final until = keys.previousLNodeValidUntil;
    final windowOpen = prev != null &&
        until != null &&
        (now ?? DateTime.now()).isBefore(until);
    if (!windowOpen) return current;

    // Deliberately into a local variable BEFORE ORing: `||` would
    // short-circuit and produce exactly the timing leak this block avoids.
    final previous = LinkMac.verifyInitMac(prev, e2, mac, now: now);
    return current || previous;
  }

  static Uint8List _deriveKProv(Uint8List provSs, String? channel) {
    final label = (channel ?? kNetworkChannel) + kProvInfoLabel;
    return _sodium.hkdfSha256(
      provSs,
      salt: LinkKdf.salt,
      info: Uint8List.fromList(utf8.encode(label)),
      length: 32,
    );
  }

  static Uint8List _confirmTag(
      Uint8List mlkemSs, Uint8List e2Init, Uint8List e2Resp) {
    final label = utf8.encode(kRespConfirmLabel);
    final data = Uint8List(label.length + kE2Length * 2)
      ..setRange(0, label.length, label)
      ..setRange(label.length, label.length + kE2Length, e2Init)
      ..setRange(label.length + kE2Length, label.length + kE2Length * 2, e2Resp);
    return _sodium.hmacSha256(mlkemSs, data);
  }

  /// Builds the session for the own role.
  ///
  /// [asInitiator] is the **only** place at which the direction is
  /// assigned; both call sites know their role from the control flow and
  /// not from a data field.
  static LinkSession _session(
      Uint8List x25519Ss, Uint8List mlkemSs, String? channel,
      {required bool asInitiator,
      Uint8List? staticSs,
      Uint8List? peerPosition,
      ObservedAddress? observedSelf}) {
    final linkKey = LinkKdf.deriveLinkKey(
        x25519Ss: x25519Ss,
        mlkemSs: mlkemSs,
        staticSs: staticSs,
        channel: channel);
    final fromInitiator = LinkKdf.deriveCellKeyInit(linkKey);
    final fromResponder = LinkKdf.deriveCellKeyResp(linkKey);
    return LinkSession(
      linkKey: linkKey,
      sendKey: asInitiator ? fromInitiator : fromResponder,
      recvKey: asInitiator ? fromResponder : fromInitiator,
      peerPosition: peerPosition,
      observedSelf: observedSelf,
    );
  }

  static Uint8List _seal(Uint8List plaintext, Uint8List key) {
    final nonce = _sodium.generateNonce();
    final ct = _sodium.aesGcmEncrypt(plaintext, key, nonce);
    return Uint8List(kAeadNonceLength + ct.length)
      ..setRange(0, kAeadNonceLength, nonce)
      ..setRange(kAeadNonceLength, kAeadNonceLength + ct.length, ct);
  }

  static Uint8List? _open(Uint8List blob, Uint8List key) {
    if (blob.length <= kAeadNonceLength + kAeadTagLength) return null;
    final nonce = Uint8List.fromList(
        Uint8List.sublistView(blob, 0, kAeadNonceLength));
    final ct = Uint8List.fromList(Uint8List.sublistView(blob, kAeadNonceLength));
    try {
      return _sodium.aesGcmDecrypt(ct, key, nonce);
    } catch (_) {
      return null;
    }
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
