/// Plane D wire format — the frame the media of a call travels in (§17.1).
///
/// **This file freezes wire format.** Every constant below is part of what
/// Plane D puts on the wire; changing one after release creates a second
/// wire format. The freeze is guarded by `test/smoke/smoke_d_frame.dart`.
///
/// On-wire layout of one D-frame (exactly [DFrameClass.wireSize] bytes of
/// UDP payload — payload, not packet):
///
/// ```
/// cookie(8) ‖ nonce(12) ‖ AES-256-GCM ciphertext(n) ‖ tag(16)
///                         └ inner: kind(1) ‖ seq(4) ‖ len(2) ‖ body ‖ pad ┘
/// ```
///
/// **Why not a delivery cell.** §17.1: "Media does **not** run in delivery
/// cells: quantizing a media frame (orders of magnitude smaller than a cell)
/// to cell granularity is wasteful either way." So the 1,200 B of
/// `lib/core/link/cell.dart` is deliberately **not** taken over as the
/// universal measure — see [DFrameClass].
///
/// **What §17.1 fixes, quoted:**
///
/// - "**AES-256-GCM under `call_key`** — live-media frames carry **no**
///   ML-DSA signature and **no** zstd compression; the AEAD under `call_key`
///   provides per-frame authenticity. Rationale: […] a signature per frame
///   would cost ~3,500 B wire and ~600 µs CPU on top, and frame payloads are
///   already ciphertext, hence not compressible."
///   → this file signs nothing and compresses nothing. There is no hook for
///   either; adding one is a wire change.
/// - "**Uniform header, padding to fixed size classes.** On the wire, a
///   D-frame is indistinguishable from random bytes; the size classes dampen
///   bitrate fingerprinting."
///   → the header is `cookie ‖ nonce`, 20 B, both CSPRNG output; everything
///   with structure lives inside the AEAD. There is no magic byte, no
///   version field, no plaintext length — the same construction
///   `cell.dart` uses, and the same one TLS 1.3 (RFC 8446 §5.2/§5.4) and
///   QUIC (RFC 9000 §19.1) use to hide record type and padding.
///
/// **The two size classes, and why exactly two** (owner's decision,
/// 2026-08-31, with the arithmetic that produced it):
///
/// - **176 B for speech** (owner's decision, 2026-09-06; **160 B on
///   2026-09-05, 128 B until S369**). Opus runs at a 28 kbps target rate — measured in this tree,
///   `lib/core/calls/opus_ffi.dart:61`
///   (`const int _opusTargetBitrate = 28000;`, "the midpoint of the spec
///   range (24-32 kbps)") — at a 20 ms frame (`opus_ffi.dart:9`, "Mono,
///   20 ms frame duration"), i.e. 50 frames/s. 28,000 bit/s ÷ 50 = 560 bit
///   = **70 B of payload** per frame.
///
///   **The 60-80 B this used to quote is a mean, not a bound, and the
///   difference is what broke group audio.** Measured with the real
///   libopus at the configured rate with DTX and inband FEC enabled
///   (`OpusFFI._configureEncoder`), across 900 frames of four signal
///   shapes, back when the encoder still ran VBR: median **70-71 B**, 90th
///   percentile **76-80 B**, 99th percentile **82-92 B**, maximum
///   **95 B**. That maximum was then read as a bound in turn, and was not
///   one either — see below.
///
///   Plus this frame's own overhead of [kDFrameOverhead] = 43 B (cookie 8 +
///   nonce 12 + tag 16 + inner header 7) a speech frame measures **113 B
///   unpadded** at the median and **138 B at the measured worst case**. A
///   **group** frame adds the 16 B AEAD tag of the per-sender `send_key`
///   (§17.5) on top, because a shared group key cannot provide sender
///   authenticity — so 70 B of Opus is already **86 B of body** before a
///   single header field exists.
///
///   **Neither 128 nor 160 held for groups.** 128 carried 85 B of body:
///   0-2 % of 1:1 speech frames exceeded it, and **100 %** of group frames
///   did — group audio was refused at the sender with [DFrameClass]
///   overflow and never reached the wire at all. 160 carried 117 B and
///   closed the 1:1 case completely, but the group body is
///   `index(1) ‖ seq(4) ‖ nonce(12) ‖ Opus ‖ tag(16)` = **33 B + Opus**,
///   so it carried Opus only up to 84 B.
///
///   176 B carries **133 B**, i.e. Opus up to **100 B** in a group frame
///   and up to 133 B in a 1:1 frame. Against the S369 worst case of 95 B
///   that is 5 B of reserve in the group and 38 B in 1:1.
///
///   **A class size can only buy a probability; the bound had to come from
///   the codec.** Re-measured 2026-09-06 with the real libopus in this
///   tree, 1000 frames at 48 kHz and again at 16 kHz, four signal shapes,
///   every frame put through [sealDFrame] itself rather than compared
///   against a sum, while the encoder still ran VBR:
///
///   | class | 1:1 | group (48 kHz / 16 kHz) |
///   |---|---|---|
///   | 128 B | 9-12 % | 77-84 % |
///   | 160 B | 0.0 % | 11-13 % |
///   | **176 B** | **0.0 %** | **0.3-1.0 %** |
///   | 192 B | 0.0 % | 0.0 % |
///
///   The group column was not zero because "95 B" was never a bound — it
///   is the maximum of one sample, the same mistake as "60-80 B" one level
///   up. That population reached **110 B**, a later sweep at 48 kHz
///   reached **116 B**, and there was nothing in the encoder to stop the
///   next one going higher: a *target* bitrate has no hard ceiling short
///   of `opusMaxPacketSize`.
///
///   **Closed on 2026-09-06 at the codec, not at the class** (owner's
///   decision, variant C): `OPUS_SET_VBR = 0` in
///   `OpusFFI._configureEncoder`. Every Opus packet now measures exactly
///   `opusCbrFrameBytes` = **70 B** — measured, not quoted: one single
///   packet length over 4,000 frames at both rates and over 200
///   adversarial frames at each of the five sample rates
///   `OpusFFI.withFormat` admits. 70 + 33 B of group overhead = 103 B
///   against 133 B, so the group case now clears the class by **30 B, by
///   construction**. `OPUS_SET_VBR_CONSTRAINT` would not have done it: it
///   is already 1 out of the factory and setting it changed 0 of 4,000
///   frame lengths.
///
///   **The class size is unchanged by this.** 176 B was not too small; it
///   was resting on a statistic. It now rests on a bound.
///
///   **It stays ONE class for both**, and that is the load-bearing part:
///   a separate size for group audio would let an observer outside the
///   call tell a group call from a 1:1 call by frame size alone. On the
///   wire 176 × 50 = **8.8 kB/s = 70.4 kbps** per direction, a factor of
///   2.5 against the codec (8.0 kB/s at 160 B, 6.4 at 128 B).
/// - **1200 B for video fragments and the §17.6 media stream.** This class
///   is not invented here: appendix A already carries it — "Stream frame |
///   one fountain block per D-frame, size class **1200 B** (85.3 %
///   efficiency)" — and §17.6 says the same in words ("padded to a **1200 B
///   size class** — byte-uniform with the cell size"). Video is fragmented
///   in any case, so it fits the class rather than the class fitting it.
/// - **Rejected: one class of 1200 for everything.** Speech would then run
///   at 1200 × 50 = 60 kB/s = 480 kbps on the wire for a 28 kbps codec, a
///   factor of 17.1.
///
/// **The padding is part of that decision and is not optional.** Opus runs
/// with DTX switched on — `opus_ffi.dart:288`,
/// `ctl(_opusSetDtx, 1, 'OPUS_SET_DTX')`, and `opus_ffi.dart:10`, "DTX
/// enabled" — so in a speech pause a frame shrinks to 2-3 B. Without padding
/// that would be a saving (3.3 instead of 6.4 kB/s) **and** a leak: whoever
/// sees the frame sizes sees when somebody is speaking. That is precisely
/// the traffic analysis the size classes of §17.1 exist to close. The price
/// is counted: 3.1 kB/s per direction, about 22 MB per hour of conversation.
/// **A class that only sometimes holds is not a class** — which is why
/// [sealDFrame] pads unconditionally and there is no flag to turn it off.
///
/// **What is NOT in this file, deliberately.** No punch window, no address
/// candidates, no `call_key` negotiation. The key arrives here already
/// agreed (§17.2 signaling) and this module never derives, stores or
/// rotates it.
///
/// **Path migration: the FRAMES live here, the RULE does not.** Since S377
/// this file carries [DFrameKind.pathChallenge] and
/// [DFrameKind.pathResponse] plus [newPathChallenge] — the two wire kinds
/// RFC 9000 §8.2 needs. When a challenge is drawn, to which address it
/// goes, and what swings a path is decided in `d_socket.dart`, because only
/// there does a datagram have an origin. The sentence above said "no path
/// migration" before S377 and would now be false for the frames.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// The session cookie of §17.4, in bytes on the wire.
///
/// Eight bytes of CSPRNG output. Long enough that a delivery cell's first
/// eight bytes hit a live cookie with probability 2^-64 (the demux relies on
/// that — see `link_demux.dart`), short enough to keep the uniform header
/// inside the owner's arithmetic above.
const int kDCookieSize = 8;

/// AES-256-GCM nonce, drawn fresh from the CSPRNG for every frame — the same
/// rule `cell.dart` follows.
const int kDNonceSize = 12;

/// AES-256-GCM authentication tag.
const int kDTagSize = 16;

/// `kind(1) ‖ seq(4) ‖ len(2)`, inside the AEAD.
///
/// Inside, not in the header, and that is the load-bearing part: `seq` is a
/// counter, and a counter on the wire is the opposite of "indistinguishable
/// from random bytes". Everything with structure stays under the seal.
const int kDInnerHeaderSize = 7;

/// What one frame costs on top of its payload: 8 + 12 + 16 + 7 = 43 B.
const int kDFrameOverhead =
    kDCookieSize + kDNonceSize + kDTagSize + kDInnerHeaderSize;

/// The random bytes of a path challenge (§17.4 + RFC 9000 §8.2).
///
/// **Sixteen, and the number costs nothing.** RFC 9000 §19.17 gives
/// PATH_CHALLENGE eight bytes ("contains an unpredictable payload"), because
/// there every byte counts against the packet budget. Not here: a
/// challenge rides on [DFrameClass.voice] and then measures 176 B —
/// whether the body holds 8 or 16 bytes changes NOTHING on the wire, because the
/// rest is padding anyway (see [sealDFrame]). The additional eight
/// bytes are therefore free, and 128 bits of randomness make the question whether 64 bits
/// suffice against a guesser moot.
const int kDPathChallengeSize = 16;

/// Fresh random bytes for a path challenge, from the CSPRNG.
///
/// Lives here and not in `d_socket.dart`, so that the reach for crypto stays in
/// ONE place of this module — the same construction as
/// [DCookie.generate].
Uint8List newPathChallenge() => SodiumFFI().randomBytes(kDPathChallengeSize);

/// The two size classes of §17.1. There is no third, and no "unpadded".
enum DFrameClass {
  /// Speech (§17.1, owner 2026-08-31; **raised 128 → 160 on 2026-09-05,
  /// 160 → 176 on 2026-09-06**). Derivation in the library comment.
  ///
  /// **This is the ONLY place the number is written.** Until S369 it was
  /// written three times: here, and twice as a literal `85` in
  /// `call_control_frame.dart` (`kControlRecordMaxValue` and the `capacity`
  /// default of `packControlRecords`). Both of those now derive from this
  /// enum, because a size class that is second-written is a size class that
  /// silently disagrees with itself the first time it moves.
  ///
  /// **The derivation was then proved by moving it.** On 2026-09-06 the
  /// step 160 → 176 changed this line and nothing else in `lib/`: every
  /// consumer — `kControlRecordMaxValue`, the `capacity` default of
  /// `packControlRecords`, `CallTransportV41.sendMedia`, the upload probe's
  /// wire accounting — followed on its own. Only the freeze guards had to
  /// be pulled along, which is what a freeze guard is for.
  voice(176),

  /// Video fragments and the relayed media stream (§17.6, appendix A).
  stream(1200);

  const DFrameClass(this.wireSize);

  /// The frame's length on the wire — always exactly this, never less.
  final int wireSize;

  /// The plaintext the AEAD covers: 176 − 36 = 140, 1200 − 36 = 1164.
  int get plaintextSize => wireSize - kDCookieSize - kDNonceSize - kDTagSize;

  /// The largest body this class can carry: 140 − 7 = **133**,
  /// 1164 − 7 = 1157.
  ///
  /// **133 B against the 70 B a CBR Opus frame measures leaves 63 B in the
  /// 1:1 case.** In the group case the body carries 33 B of its own
  /// (`index(1) ‖ seq(4) ‖ nonce(12) ‖ … ‖ send_key tag(16)`, §17.5), so
  /// Opus may reach 100 B and uses 70 — 30 B of reserve.
  ///
  /// Both margins are **bounds, not percentiles**, since `OPUS_SET_VBR = 0`
  /// (2026-09-06): the encoder cannot emit a frame that overflows the
  /// class. Before that the group case lost 0.3-1.0 % of frames, and every
  /// number that was supposed to bound it — 80 B, 95 B, 110 B — was
  /// overtaken by the next measurement. See the library comment.
  ///
  /// The margin is deliberately measured rather than nominal: the 85 B of
  /// the first class was derived from a quoted codec range of 60-80 B that
  /// turned out to be the **mean**, and it silently cost 0-2 % of 1:1
  /// speech frames and 100 % of group frames.
  ///
  /// The margin is **checked**, not hoped for: [sealDFrame] throws when a
  /// body exceeds it rather than silently promoting the frame to the next
  /// class. A promotion would be a size difference on the wire, i.e.
  /// exactly the fingerprint the classes exist to remove.
  int get payloadCapacity => plaintextSize - kDInnerHeaderSize;

  /// The class a wire length belongs to, or `null` if it belongs to none.
  ///
  /// O(1) and free of crypto — this is the first thing the demux asks of an
  /// arriving datagram.
  static DFrameClass? ofWireSize(int length) {
    for (final c in DFrameClass.values) {
      if (c.wireSize == length) return c;
    }
    return null;
  }
}

/// What a frame carries. One byte, inside the AEAD.
enum DFrameKind {
  /// One Opus frame, 20 ms. Rides [DFrameClass.voice] and nothing else.
  voice(0x01),

  /// One video fragment. Rides [DFrameClass.stream].
  video(0x02),

  /// One fountain block of the relayed media stream (§17.6). Rides
  /// [DFrameClass.stream].
  stream(0x03),

  /// A probe of the punch window (§17.3). Carries no payload and
  /// rides on [DFrameClass.voice].
  ///
  /// ── WHY A SEPARATE KIND AND NOT AN EMPTY VOICE FRAME ────────
  ///
  /// A voice frame with an empty payload would be, for the layer above,
  /// an Opus frame of length 0 — the JitterBuffer (§17.5) accepts it
  /// and the decoder gets to hear padding. The
  /// distinction has to be made anyway; it belongs in the
  /// one byte that exists exactly for that.
  ///
  /// ── NOTHING NEW APPEARS ON THE WIRE ──────────────────────
  ///
  /// §17.1 freezes the size classes, not the number of kinds: the
  /// `kind` byte lies INSIDE the AEAD ("inner: kind ‖ seq ‖ len ‖
  /// body"), and the frame measures the same 176 B as every voice frame.
  /// An observer cannot tell a probe apart from a voice
  /// frame — which, for a probe that runs before the conversation,
  /// is exactly the right property.
  punch(0x04),

  /// A path challenge (§17.4 + RFC 9000 §8.2). Carries
  /// [kDPathChallengeSize] fresh random bytes and rides on
  /// [DFrameClass.voice].
  ///
  /// ── WHAT IT IS FOR, IN ONE SENTENCE ─────────────────────────────────
  ///
  /// Since S377 an authenticated frame from a NEW address no longer swings
  /// the media stream there immediately; it triggers this
  /// challenge to exactly that address. Only the response with
  /// these very bytes ([pathResponse]) swings.
  ///
  /// ── WHY `highestSeqSeen` IS NOT ENOUGH FOR THIS ────────────────────
  ///
  /// The sequence-number condition (RFC 9000 §9.3, see
  /// `DSession.highestSeqSeen`) defeats the REPLAY of a
  /// captured frame: the original has already arrived and has
  /// raised the number. It does NOT defeat the attacker who
  /// SUPPRESSES the original and delivers his duplicate first — his
  /// frame is the first with this number, and it redirects the stream
  /// without possessing the `call_key`. Exactly this gap is the reason
  /// for RFC 9000 §8.2 ("An endpoint MUST NOT send a non-probing frame
  /// on a new path until it has validated that path"), and exactly this gap
  /// is closed by this pair of frames.
  ///
  /// ── NOTHING NEW APPEARS ON THE WIRE ────────────────────────────
  ///
  /// §17.1 freezes the SIZE CLASSES, not the number of kinds — the
  /// justification is given in full at [punch] and applies here verbatim:
  /// the `kind` byte lies inside the AEAD, and the frame measures
  /// the same 128 B as every voice frame.
  pathChallenge(0x05),

  /// The response to a [pathChallenge]: the same random bytes back,
  /// sealed under the same `call_key`, to the origin of the
  /// challenge. Also rides on [DFrameClass.voice].
  ///
  /// An attacker cannot build it: the bytes lie INSIDE the
  /// AEAD, so he does not see them, and without `call_key` he cannot
  /// seal anything either. The response is therefore the proof that §17.4 demands for
  /// a swing.
  pathResponse(0x06),

  /// A CONTROL FRAME of the group call (§17.1.1). Rides on
  /// [DFrameClass.voice] and never carries media.
  ///
  /// ── §17.1.1 VERBATIM, AND WHY THIS KIND HAS EXISTED SINCE S368 ───────
  ///
  /// "A fourth `kind` on Plane D carries what a group call needs to
  /// organize itself: speech level, readiness, presentation role, layout
  /// size, spanning tree updates, and RTT probes. It is **not** a media
  /// frame — it carries no media and is never handed to a codec."
  ///
  /// Until S368 it did not exist, and exactly that was the reason why
  /// `CallTransportV41.sendSecuredToParticipant` returned `noCarrier` for EVERY
  /// frame type: the blueprint of the forwarding tree
  /// (CALL_TREE_UPDATE) reached no participant, so nobody except
  /// the initiator entered the tree, and the upper limit of 30 was a
  /// promise without backing. The comment there prescribed its own successor
  /// — "Whoever builds the carrier (fourth frame kind in §17.1)
  /// changes both places together"; exactly that has happened here.
  ///
  /// ── SAME CLASS, SAME KEY, SAME PADDING ────────────────
  ///
  /// §17.1.1: "A control frame is an AES-256-GCM frame under `call_key` in
  /// the 128 B class, indistinguishable on the wire from a voice frame.
  /// This is not a convenience."
  ///
  /// **The number in the quote is outdated, the statement is not.** The
  /// voice class has measured 176 B since 06.09.2026; the control frame still
  /// shares it, and that is exactly what matters. The quote stands
  /// unchanged because it is a quote — the sentence in §17.1.1 is updated by the
  /// owner, not rewritten here.
  ///
  /// Who speaks when is something the participants NEED
  /// — the choice of the forwarder depends on it (§17.7) and
  /// the UI draws the frame around the speaker. An observer
  /// OUTSIDE the call must not be handed the same signal for free,
  /// and a separate size class would have given it to him: control traffic
  /// peaks exactly when someone starts to speak.
  ///
  /// That is why the voice class stands here and not 1200, although 1200
  /// would be more convenient —
  /// a blueprint would then not have to be chunked. The convenience
  /// would be a size difference on the wire, i.e. exactly the
  /// fingerprint that §17.1 closes with the classes.
  control(0x07);

  const DFrameKind(this.code);

  final int code;

  /// The class this kind is allowed on — the "a speech frame is never 1200"
  /// invariant, as a value rather than a comment.
  ///
  /// A `switch` WITHOUT `default`: a FURTHER kind forces a
  /// decision here, instead of silently falling to `stream` and thereby producing a
  /// 1200 B frame where 128 was meant. It did exactly
  /// that when S377 added [DFrameKind.pathChallenge] and
  /// [DFrameKind.pathResponse] — the compiler named the
  /// two missing branches instead of silently promoting them to 1200.
  /// The same construction
  /// with which S360 repaired the mode guard.
  DFrameClass get frameClass => switch (this) {
        DFrameKind.voice => DFrameClass.voice,
        DFrameKind.punch => DFrameClass.voice,
        DFrameKind.pathChallenge => DFrameClass.voice,
        DFrameKind.pathResponse => DFrameClass.voice,
        // §17.1.1: "in the […] class, indistinguishable on the wire from
        // a voice frame" — the class measures 176 B today, not the 128 named
        // in the document. Not `stream`; justification at
        // [DFrameKind.control].
        DFrameKind.control => DFrameClass.voice,
        DFrameKind.video => DFrameClass.stream,
        DFrameKind.stream => DFrameClass.stream,
      };

  static DFrameKind? ofCode(int code) {
    for (final k in DFrameKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// One D-frame's contents, after the seal came off.
final class DFrame {
  final DFrameKind kind;

  /// Per-direction frame counter. Ordering and loss detection above the
  /// Plane D API (§17.5) read it; this module only carries it.
  final int seq;

  final Uint8List payload;

  /// The class the frame arrived in. Kept so a caller can tell a 1200 B
  /// stream frame from a 176 B speech frame without measuring again.
  final DFrameClass frameClass;

  const DFrame({
    required this.kind,
    required this.seq,
    required this.payload,
    required this.frameClass,
  });
}

/// A session cookie (§17.4), together with the 64-bit integer the demux
/// looks it up under.
///
/// **Why an `int` key and not a hex string.** The cookie lookup runs on
/// every arriving datagram, before any crypto (see `link_demux.dart` for the
/// order and its derivation). A hex string would allocate per datagram; the
/// eight bytes fit a Dart native `int` exactly, so the lookup key is a
/// primitive and the map is an `int`-keyed hash map.
final class DCookie {
  final Uint8List bytes;

  /// The same eight bytes as one unsigned 64-bit integer, big-endian.
  final int key;

  DCookie._(this.bytes, this.key);

  /// Draws a fresh cookie from the CSPRNG.
  factory DCookie.generate() =>
      DCookie.of(SodiumFFI().randomBytes(kDCookieSize));

  /// Wraps eight given bytes — the form signaling hands the peer's cookie
  /// over in (§17.6: "the volunteer hands out two session cookies").
  factory DCookie.of(Uint8List bytes) {
    if (bytes.length != kDCookieSize) {
      throw ArgumentError(
          'DCookie: cookie must be exactly $kDCookieSize bytes, '
          'got ${bytes.length}');
    }
    final copy = Uint8List.fromList(bytes);
    return DCookie._(copy, _readKey(copy, 0));
  }

  /// The cookie a datagram claims to carry, without copying it.
  ///
  /// Reads the first [kDCookieSize] bytes as the lookup key. It does not
  /// validate anything — there is nothing to validate about eight random
  /// bytes; the AEAD decides whether they were the right ones.
  static int keyOf(Uint8List datagram) {
    if (datagram.length < kDCookieSize) return 0;
    return _readKey(datagram, 0);
  }

  static int _readKey(Uint8List src, int offset) =>
      ByteData.view(src.buffer, src.offsetInBytes + offset, kDCookieSize)
          .getUint64(0, Endian.big);

  @override
  String toString() => 'DCookie(${key.toRadixString(16)})';
}

/// Seals one D-frame and returns exactly `frameClass.wireSize` bytes, ready
/// to hand to the transport as one UDP payload.
///
/// [cookie] is the cookie the **receiver** hands out for this direction: it
/// travels in the clear (the receiver must find the session before it has a
/// key to try) and is bound into the AEAD as additional data, so a frame
/// cannot be re-stamped with a different cookie without breaking the tag.
///
/// Throws [ArgumentError] when [payload] does not fit the class, or when
/// [kind] and the class disagree. Both are refusals rather than repairs: the
/// repair would be a size change on the wire, and a size change is the
/// fingerprint §17.1 pays to remove.
Uint8List sealDFrame({
  required DCookie cookie,
  required Uint8List callKey,
  required DFrameKind kind,
  required int seq,
  required Uint8List payload,
  DFrameClass? frameClass,
}) {
  final cls = frameClass ?? kind.frameClass;
  if (cls != kind.frameClass) {
    throw ArgumentError(
        'sealDFrame: ${kind.name} rides ${kind.frameClass.name} '
        '(${kind.frameClass.wireSize} B), not ${cls.name} '
        '(${cls.wireSize} B) — §17.1 size classes');
  }
  if (payload.length > cls.payloadCapacity) {
    throw ArgumentError(
        'sealDFrame: ${payload.length} B payload exceeds the '
        '${cls.name} class capacity of ${cls.payloadCapacity} B. Promoting '
        'the frame to the next class would be a size difference on the wire '
        '(§17.1); the codec configuration is what has to change.');
  }
  if (seq < 0 || seq > 0xFFFFFFFF) {
    throw ArgumentError('sealDFrame: seq out of the 32-bit range: $seq');
  }

  // The inner plaintext is ALWAYS the full class size. The tail past the
  // body stays zero — under AES-GCM it is indistinguishable from any other
  // ciphertext, so there is nothing to gain from filling it with randomness
  // and one CSPRNG call per frame to lose.
  final inner = Uint8List(cls.plaintextSize);
  final view = ByteData.view(inner.buffer, inner.offsetInBytes);
  view.setUint8(0, kind.code);
  view.setUint32(1, seq, Endian.big);
  view.setUint16(5, payload.length, Endian.big);
  inner.setRange(kDInnerHeaderSize, kDInnerHeaderSize + payload.length,
      payload);

  final sodium = SodiumFFI();
  final nonce = sodium.generateNonce();
  final ct = sodium.aesGcmEncrypt(inner, callKey, nonce, ad: cookie.bytes);

  final frame = Uint8List(cls.wireSize);
  frame.setRange(0, kDCookieSize, cookie.bytes);
  frame.setRange(kDCookieSize, kDCookieSize + kDNonceSize, nonce);
  frame.setRange(kDCookieSize + kDNonceSize, cls.wireSize, ct);
  return frame;
}

/// Opens one D-frame under [callKey], or returns `null`.
///
/// **`null`, never a throw, and never a log line.** §2.6/§17.4 posture: a
/// frame that does not authenticate carries no information, and the socket
/// "responds exclusively to packets with a valid AEAD under `call_key` plus
/// a session cookie". A log line here would be an observable difference
/// between a forgery and a genuine frame, which is the same class of leak
/// the silence exists to close.
///
/// [expect] is the cookie this session hands out. It is compared before the
/// AEAD runs — the comparison is what the demux already did to find the
/// session, repeated here so a direct caller cannot skip it — and it goes
/// into the AEAD as additional data, so it is checked twice by two different
/// mechanisms.
DFrame? openDFrame(Uint8List frame, Uint8List callKey, DCookie expect) {
  final cls = DFrameClass.ofWireSize(frame.length);
  if (cls == null) return null;
  if (DCookie.keyOf(frame) != expect.key) return null;

  final Uint8List inner;
  try {
    inner = SodiumFFI().aesGcmDecrypt(
      Uint8List.sublistView(frame, kDCookieSize + kDNonceSize),
      callKey,
      Uint8List.sublistView(frame, kDCookieSize, kDCookieSize + kDNonceSize),
      ad: expect.bytes,
    );
  } catch (_) {
    return null;
  }
  if (inner.length != cls.plaintextSize) return null;

  final view = ByteData.view(inner.buffer, inner.offsetInBytes);
  final kind = DFrameKind.ofCode(view.getUint8(0));
  if (kind == null) return null;
  // A speech frame is never 1200, and a stream frame is never 176 — checked
  // on the way in as well as on the way out. An authenticated peer that got
  // this wrong is a bug on its side, and a bug that arrives silently is one
  // nobody finds.
  if (kind.frameClass != cls) return null;

  final len = view.getUint16(5, Endian.big);
  if (len > cls.payloadCapacity) return null;

  return DFrame(
    kind: kind,
    seq: view.getUint32(1, Endian.big),
    payload: Uint8List.sublistView(
        inner, kDInnerHeaderSize, kDInnerHeaderSize + len),
    frameClass: cls,
  );
}
