/// The content of a Plane D CONTROL FRAME (§17.1.1).
///
/// ══ WHAT THIS FILE IS ══════════════════════════════════════════════
///
/// §17.1.1 gives Plane D a fourth frame kind and says what it
/// carries: "speech level, readiness, presentation role, layout size,
/// spanning tree updates, broker requests, RTT probes, and loss reports".
/// [DFrameKind.control] is the kind; here is what lies INSIDE.
///
/// ══ THE ONE NUMBER FROM WHICH EVERYTHING FOLLOWS: THE CLASS PAYLOAD ══════════
///
/// A control frame rides on `DFrameClass.voice` and thus carries its
/// payload — **since 06.09.2026 133 B; 117 B on 05.09., before that 85 B**
/// (`d_frame.dart`,
/// `payloadCapacity`). Not 1200 — §17.1.1 explicitly requires the voice class,
/// "indistinguishable on the wire from a voice frame", because
/// a class of its own would reveal to an observer OUTSIDE the call
/// when someone starts to speak.
///
/// **The number is no longer written here but fetched.** Until S369
/// it stood twice as a literal in this file (`kControlRecordMaxValue`
/// and the `capacity` default of [packControlRecords]); on the
/// enlargement both would have stayed and would have left 32 B of the class
/// unused, without anything failing.
///
/// It is the reason for every design decision here. Measured on
/// 05.09.2026 against this tree, against the 85 B of that time:
///
///     CallTreeUpdate (proto) with  6 nodes = 270 B  ->  4 control frames
///     CallTreeUpdate (proto) with 30 nodes = 1134 B -> 14 control frames
///
/// A plan that trickles in in 14 pieces is already outdated at the first
/// change — at 2 Hz after seven seconds, at
/// the **1 Hz rate** in force since 05.09.2026 after fourteen. Therefore
/// the tree is NOT sent as a node list here. With 133 B it would
/// be 9 instead of 14 frames — the order of magnitude stays, and with it the
/// design decision; the slower rate makes it even more compelling.
///
/// ══ PARTICIPANT INDEX INSTEAD OF NODE IDENTIFIER ══════════════════════════════
///
/// A participant needs only two pieces of information from the plan: **who is my
/// parent** and **who are my children**. Both are written as a one-byte
/// index into the call's participant list instead of as a 32 B
/// node identifier. A complete tree assignment thus measures
/// `6 + number of children` bytes and fits into ONE frame at EVERY group size.
///
/// **That is not invented but the document's own technique.**
/// §17.1.1 describes exactly the same compaction for the star above 25 participants:
/// "a readiness **bitmap** and the tree version —
/// 32 B at 25, 35 B at 50, 41 B at 100". A readiness bitmap
/// addresses participants via their POSITION, not via their identifier.
///
/// ══ THE LIST MUST BE THE SAME ON BOTH SIDES ═══════════════════
///
/// An index is only as good as the list it points into. Therefore
/// every tree assignment carries a **2 B checksum over the list**
/// ([rosterHash]). If it does not match at the receiver, the assignment is
/// DISCARDED and reported — not evaluated "as well as possible". A
/// plan that points to the wrong list makes a participant the
/// child of a stranger; that is worse than no plan.
///
/// ══ WHAT DOES NOT BELONG IN HERE ═════════════════════════════════════
///
/// §17.1.1, verbatim: "What a control frame must never carry: media
/// payload, key material beyond the session's own tree bookkeeping, or
/// anything that would make it worth relaying by a node that is not a
/// call participant." There is therefore no record kind for
/// key distribution here — that stays on signaling (§17.2).
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/link_io/d_frame.dart';

/// The record kinds of a control frame. One byte, inside the AEAD.
///
/// A `switch` over this enumeration without `default` forces a decision
/// for a sixth kind — the same construction with which
/// `DFrameKind.frameClass` prevents something from silently falling into the wrong
/// size class.
enum ControlRecordType {
  /// The tree assignment for EXACTLY THE RECEIVER (§17.7). No global
  /// plan — see the file header.
  treeAssignment(0x01),

  /// RTT probe (§17.1.1: "RTT probes").
  ///
  /// **It must run over Plane D and not over the delivery layer.**
  /// §17.1.1, reason 2: on the delivery layer the measured value would be the
  /// harvest cadence and not the run time, and an RTT-weighted
  /// spanning tree on top of it would be a random tree.
  rttPing(0x02),

  /// The answer to [rttPing], with the same marker.
  rttPong(0x03),

  /// The sender's speech level (§17.1.1 "speech level").
  ///
  /// **Not a leak** (§17.7): "Who speaks when is knowledge inside the call,
  /// and it is needed there." The forwarder selects by it, the
  /// UI draws the frame around the speaker, and every
  /// forwarder in the crystal IS a participant. What is protected is the
  /// observer OUTSIDE — the size class takes care of that, not an
  /// obfuscation towards one's own participants.
  speechLevel(0x04),

  /// The sender's readiness (§17.1.1 "readiness").
  readiness(0x05),

  /// Which participants lie behind each down-link of the receiver
  /// (S407-GA-P4, §17.5 edge binding).
  ///
  /// [treeAssignment] names a participant's parent and children only.
  /// That suffices to forward (§17.7) but not to take: §17.5 has a
  /// receiver take a sender's frames only "over its tree link towards
  /// that sender", and for a sender two levels down the receiver cannot
  /// tell from its children alone which link that is. This record tells
  /// it, per down-link, as a bitmap over the sorted participant list —
  /// the compaction §17.1.1 itself uses for the readiness bitmap.
  ///
  /// A peer that does not know the code skips it (`readControlRecords`),
  /// so a v4.2.3 participant keeps applying [treeAssignment] as before.
  treeSubtree(0x06),

  // ── The broker of the mesh (§17.7, S407-GA-P5) ─────────────────────
  //
  // "Both members ask their media pairs in the call which of them hold a
  // media pair with the other and how much they can still take; the member
  // with the smaller identifier binds the one with the most free capacity
  // under `f_i`, ties by the ranking below, and the broker confirms to
  // both." Six records carry exactly that; in the mesh (up to 6, bitmaps of
  // 1 B) each is at most 7 B, with a group list of 25 at most 13 B (two
  // bitmaps of 4 B in `relayHave`). A peer that does not know a code skips
  // it (`readControlRecords`) — a v4.2.3 participant never answers, and
  // its silence ends the request as §11.3a says.

  /// "Which of these participants do you hold a media pair with?" —
  /// a bitmap over the sorted participant list ([buildRelayAsk]).
  relayAsk(0x07),

  /// The answer to [relayAsk]: the asked participants the answerer holds
  /// a media pair with, and its free capacity ([buildRelayHave]).
  relayHave(0x08),

  /// The smaller member of a pair binds the answerer as the pair's broker
  /// ([buildRelayBind]).
  relayBind(0x09),

  /// The broker cannot carry the pair's voice — to both members
  /// ([buildRelayPair]).
  relayRefuse(0x0A),

  /// The broker carries the pair, with or without video — to both members
  /// ([buildRelayPair]).
  relayBound(0x0B),

  /// The binding ends: from a member (the pair gained a media pair of its
  /// own) or from the broker (it leaves or reached its limit)
  /// ([buildRelayPair]).
  relayDrop(0x0C),

  /// The loss report (§17.1.1, D-69/D-75; S407-GALOSS): "a receiver tells
  /// the participant it receives from how many frames of a second went
  /// missing, sent only in a second with loss". Built, read and answered in
  /// `loss_report.dart` — it is the transport's business (like RTCP's
  /// receiver report, RFC 3550 §6.4.1) and never reaches the call managers.
  /// A v4.2.3 reader skips it ([readControlRecords]).
  lossReport(0x0D),

  /// The life sign of a group media pair (§17.4, D-74), no value: "a
  /// participant that sends no voice — muted, or unable to capture — sends
  /// one control frame per second on each of its media pairs (§17.1.1)
  /// instead of silence". Sent once when a media pair starts as well — the
  /// sign that the 10 s rule holds toward the sender. A v4.2.3 peer skips the
  /// code (`readControlRecords`) and never sends it, so the rule never holds
  /// toward it. 0x0D is the broker's loss report (S407-GALOSS).
  lifeSign(0x0E),

  /// The crystal of §17.7 from 7 participants on, built over media pairs
  /// only and by the participants themselves (S408, P6;
  /// `group_call_crystal.dart`): the root a participant believes in, its
  /// rank, the room it has and its path to the root. Replaces the central
  /// [treeAssignment], which no build sends any more. A v4.2.3 reader skips
  /// the code ([readControlRecords]).
  treeOffer(0x0F),

  /// Asking a media pair for a place below it, leaving it, or telling it
  /// what lies below (`group_call_crystal.dart`).
  treeJoin(0x10),

  /// The answer to [treeOffer] and [treeJoin] (`group_call_crystal.dart`).
  treeAccept(0x11);

  const ControlRecordType(this.code);

  final int code;

  static ControlRecordType? ofCode(int code) {
    for (final t in ControlRecordType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// A single record in a control frame: `art(1) ‖ laenge(1) ‖ wert`.
///
/// The length is in the record and not in the frame, because a frame carries SEVERAL
/// records (§17.1.1: "All pending messages of one tick travel in one
/// frame"). Without a length per record a reader could not find the
/// second one.
final class ControlRecord {
  const ControlRecord(this.type, this.value);

  final ControlRecordType type;
  final Uint8List value;

  /// What this record costs in the frame: header plus value.
  int get wireLength => 2 + value.length;

  @override
  String toString() => 'ControlRecord(${type.name}, ${value.length} B)';
}

/// The largest value a single record can carry.
///
/// The payload of the voice class minus 2 B record header. A value above that is
/// not control frame content; it is rejected when building instead of
/// chunked. **Chunking would be the wrong answer here**: everything that
/// §17.1.1 enumerates is small, and what is not small belongs on
/// signaling (§17.2).
///
/// **HERE `85 - 2` STOOD AS A NUMBER (until S369).** That was a
/// second writing of the size class: when it grew from 128 to
/// 160 B on 05.09.2026, this value would have stayed at 83 and the codec
/// would not have used 32 B of its class — without anything
/// failing. Exactly the kind of error that goes unnoticed.
/// Now derived; the number only stands in `DFrameClass.voice`.
///
/// **And the derivation held the next step.** On
/// 06.09.2026 the class grew to 176 B; this value went from 115 to
/// 131 without a single character having to change here.
///
/// The length of a record value is written as ONE byte
/// ([packControlRecords]), so the value can never go above 255. With
/// 133 B class payload it is 131 — the gate stays the class.
final int kControlRecordMaxValue =
    DFrameKind.control.frameClass.payloadCapacity - 2;

/// The checksum over the participant list — 2 B, from SHA-256.
///
/// Two bytes, because it is not meant to keep out an attacker (the frame lies
/// under the AEAD of the `call_key`, a stranger cannot build it at all),
/// but a MIX-UP: two participants whose lists differ by one
/// late join. Against that 16 bits are plenty.
int rosterHash(List<String> sortedParticipantHex) {
  final joined = sortedParticipantHex.join(',');
  final digest = SodiumFFI().sha256(Uint8List.fromList(joined.codeUnits));
  return (digest[0] << 8) | digest[1];
}

/// Builds the record "this is YOUR place in the tree" (§17.7).
///
/// Form: `version(2) ‖ rosterHash(2) ‖ elter(1) ‖ kinderzahl(1) ‖ kind[…]`
///
/// [parentIndex] is [kNoParent] for the root. All indices point into
/// the SORTED participant list over which [rosterHash] was formed.
ControlRecord buildTreeAssignment({
  required int treeVersion,
  required int roster,
  required int parentIndex,
  required List<int> childIndices,
}) {
  if (childIndices.length > 255) {
    throw ArgumentError('A node with ${childIndices.length} children — '
        'the fan-out from §17.7 lies orders of magnitude below that.');
  }
  final v = Uint8List(6 + childIndices.length);
  v[0] = (treeVersion >> 8) & 0xFF;
  v[1] = treeVersion & 0xFF;
  v[2] = (roster >> 8) & 0xFF;
  v[3] = roster & 0xFF;
  v[4] = parentIndex & 0xFF;
  v[5] = childIndices.length;
  for (var i = 0; i < childIndices.length; i++) {
    v[6 + i] = childIndices[i] & 0xFF;
  }
  return ControlRecord(ControlRecordType.treeAssignment, v);
}

/// The parent index of a root. 0xFF, because according to §17.7 a call has at most
/// 30 participants and the value is thus never a real index.
const int kNoParent = 0xFF;

/// Die ausgelesene Baumzuweisung.
final class TreeAssignment {
  const TreeAssignment({
    required this.treeVersion,
    required this.roster,
    required this.parentIndex,
    required this.childIndices,
  });

  final int treeVersion;
  final int roster;

  /// [kNoParent] if the receiver is the root.
  final int parentIndex;
  final List<int> childIndices;

  bool get isRoot => parentIndex == kNoParent;

  @override
  String toString() => 'TreeAssignment(v$treeVersion, roster '
      '0x${roster.toRadixString(16)}, parent '
      '${isRoot ? "—" : parentIndex}, children $childIndices)';
}

/// Reads a tree assignment. `null` if the record is not well-formed.
///
/// **A record that is too short is not half an assignment.** Whoever guesses on here
/// builds a tree from foreign remainder — the same rule that the
/// candidate list in `address_candidates.dart` follows.
TreeAssignment? readTreeAssignment(ControlRecord record) {
  if (record.type != ControlRecordType.treeAssignment) return null;
  final v = record.value;
  if (v.length < 6) return null;
  final count = v[5];
  if (v.length != 6 + count) return null;
  return TreeAssignment(
    treeVersion: (v[0] << 8) | v[1],
    roster: (v[2] << 8) | v[3],
    parentIndex: v[4],
    childIndices: List<int>.unmodifiable(v.sublist(6, 6 + count)),
  );
}

/// The bytes of a participant bitmap over a list of [rosterLength].
int subtreeBitmapBytes(int rosterLength) => (rosterLength + 7) >> 3;

/// Builds the record "behind each of your down-links lie these
/// participants" ([ControlRecordType.treeSubtree]).
///
/// Form: `version(2) ‖ rosterHash(2) ‖ count(1) ‖ [link(1) ‖ bitmap(B)]*`
/// with `B = subtreeBitmapBytes(rosterLength)`; bit `i` (byte `i >> 3`,
/// bit `i & 7`) stands for index `i` of the SORTED participant list. The
/// version and the checksum are those of the matching [treeAssignment]:
/// a subtree record never stands for a tree other than its assignment's.
ControlRecord buildTreeSubtree({
  required int treeVersion,
  required int roster,
  required int rosterLength,
  required Map<int, Set<int>> subtreeOfLink,
}) {
  if (subtreeOfLink.length > 255) {
    throw ArgumentError('${subtreeOfLink.length} down-links — §17.7 lies '
        'orders of magnitude below that.');
  }
  final bytes = subtreeBitmapBytes(rosterLength);
  final v = Uint8List(5 + subtreeOfLink.length * (1 + bytes));
  v[0] = (treeVersion >> 8) & 0xFF;
  v[1] = treeVersion & 0xFF;
  v[2] = (roster >> 8) & 0xFF;
  v[3] = roster & 0xFF;
  v[4] = subtreeOfLink.length;
  var o = 5;
  for (final MapEntry(key: link, value: members) in subtreeOfLink.entries) {
    v[o] = link & 0xFF;
    for (final m in members) {
      if (m < 0 || m >= rosterLength) {
        throw ArgumentError('index $m outside the list ($rosterLength)');
      }
      v[o + 1 + (m >> 3)] |= 1 << (m & 7);
    }
    o += 1 + bytes;
  }
  return ControlRecord(ControlRecordType.treeSubtree, v);
}

/// The read subtree record.
final class TreeSubtree {
  const TreeSubtree({
    required this.treeVersion,
    required this.roster,
    required this.subtreeOfLink,
  });

  final int treeVersion;
  final int roster;

  /// down-link index → the participant indices behind it.
  final Map<int, Set<int>> subtreeOfLink;
}

/// Reads a subtree record against a list of [rosterLength]. `null` if it
/// is not well-formed — a record whose length does not match the list is
/// not half an answer (the same rule as [readTreeAssignment]).
TreeSubtree? readTreeSubtree(ControlRecord record, int rosterLength) {
  if (record.type != ControlRecordType.treeSubtree) return null;
  final v = record.value;
  if (v.length < 5) return null;
  final count = v[4];
  final bytes = subtreeBitmapBytes(rosterLength);
  if (v.length != 5 + count * (1 + bytes)) return null;
  final out = <int, Set<int>>{};
  var o = 5;
  for (var c = 0; c < count; c++) {
    final members = <int>{};
    for (var i = 0; i < rosterLength; i++) {
      if (v[o + 1 + (i >> 3)] & (1 << (i & 7)) != 0) members.add(i);
    }
    out[v[o]] = members;
    o += 1 + bytes;
  }
  return TreeSubtree(
    treeVersion: (v[0] << 8) | v[1],
    roster: (v[2] << 8) | v[3],
    subtreeOfLink: out,
  );
}

// ── The broker records (§17.7, S407-GA-P5) ─────────────────────────────
//
// Every record starts with the 2 B checksum of the sorted participant list
// ([rosterHash]) and names participants by their index in it — the same
// compaction as the tree records. A record for another list is not half an
// answer: the reader returns `null` and the record is dropped.

/// Free capacity that is not bounded by any known limit (§17.7 `f_i`
/// unknown, see `group_call_broker.dart`).
const int kRelayNoKnownLimit = 0xFF;

/// Flag of [RelayPair.flags]: the pair's video is carried.
const int kRelayFlagVideo = 0x01;

/// Flag of [RelayPair.flags]: this record acknowledges one of the same
/// kind and pair (§11.3a: the request that expects it ends with it).
const int kRelayFlagAck = 0x02;

Uint8List _rosterBitmap(int rosterLength, Iterable<int> members) {
  final b = Uint8List(subtreeBitmapBytes(rosterLength));
  for (final m in members) {
    if (m < 0 || m >= rosterLength) {
      throw ArgumentError('index $m outside the list ($rosterLength)');
    }
    b[m >> 3] |= 1 << (m & 7);
  }
  return b;
}

Set<int> _readBitmap(Uint8List v, int offset, int rosterLength) => <int>{
      for (var i = 0; i < rosterLength; i++)
        if (v[offset + (i >> 3)] & (1 << (i & 7)) != 0) i,
    };

/// A read [ControlRecordType.relayAsk].
final class RelayAsk {
  const RelayAsk({required this.roster, required this.asked});
  final int roster;

  /// The participant indices the asker holds no media pair with.
  final Set<int> asked;
}

/// `roster(2) ‖ bitmap(B)`.
ControlRecord buildRelayAsk({
  required int roster,
  required int rosterLength,
  required Iterable<int> asked,
}) {
  final bm = _rosterBitmap(rosterLength, asked);
  final v = Uint8List(2 + bm.length)
    ..[0] = (roster >> 8) & 0xFF
    ..[1] = roster & 0xFF
    ..setRange(2, 2 + bm.length, bm);
  return ControlRecord(ControlRecordType.relayAsk, v);
}

RelayAsk? readRelayAsk(ControlRecord record, int rosterLength) {
  if (record.type != ControlRecordType.relayAsk) return null;
  final v = record.value;
  if (v.length != 2 + subtreeBitmapBytes(rosterLength)) return null;
  return RelayAsk(
    roster: (v[0] << 8) | v[1],
    asked: _readBitmap(v, 2, rosterLength),
  );
}

/// A read [ControlRecordType.relayHave].
final class RelayHave {
  const RelayHave({
    required this.roster,
    required this.held,
    required this.pending,
    required this.freeVoice,
    required this.load,
    required this.rank,
  });
  final int roster;

  /// Of the asked participants, those the answerer holds a media pair with.
  final Set<int> held;

  /// Of the asked participants, those whose media pair with the answerer is
  /// not decided yet (its punch window runs). The answerer says it again
  /// once it is — an asker waits for that instead of choosing without it.
  final Set<int> pending;

  /// Voice streams it can still take; [kRelayNoKnownLimit] = no known limit.
  final int freeVoice;

  /// Voice streams it forwards already (the comparison where no limit is
  /// known: the less loaded has more room).
  final int load;

  /// Link type and power source for the §17.7 ranking
  /// (`group_call_broker.dart`, [rankByte]).
  final int rank;
}

/// `roster(2) ‖ held(B) ‖ pending(B) ‖ freeVoice(1) ‖ load(1) ‖ rank(1)`.
ControlRecord buildRelayHave({
  required int roster,
  required int rosterLength,
  required Iterable<int> held,
  Iterable<int> pending = const <int>[],
  required int freeVoice,
  required int load,
  required int rank,
}) {
  final h = _rosterBitmap(rosterLength, held);
  final p = _rosterBitmap(rosterLength, pending);
  final v = Uint8List(2 + 2 * h.length + 3)
    ..[0] = (roster >> 8) & 0xFF
    ..[1] = roster & 0xFF
    ..setRange(2, 2 + h.length, h)
    ..setRange(2 + h.length, 2 + 2 * h.length, p);
  final o = 2 + 2 * h.length;
  v[o] = freeVoice.clamp(0, 0xFF);
  v[o + 1] = load.clamp(0, 0xFF);
  v[o + 2] = rank & 0xFF;
  return ControlRecord(ControlRecordType.relayHave, v);
}

RelayHave? readRelayHave(ControlRecord record, int rosterLength) {
  if (record.type != ControlRecordType.relayHave) return null;
  final v = record.value;
  final b = subtreeBitmapBytes(rosterLength);
  if (v.length != 2 + 2 * b + 3) return null;
  return RelayHave(
    roster: (v[0] << 8) | v[1],
    held: _readBitmap(v, 2, rosterLength),
    pending: _readBitmap(v, 2 + b, rosterLength),
    freeVoice: v[2 + 2 * b],
    load: v[3 + 2 * b],
    rank: v[4 + 2 * b],
  );
}

/// A read [ControlRecordType.relayBind].
final class RelayBind {
  const RelayBind({
    required this.roster,
    required this.peer,
    required this.wantVideo,
  });
  final int roster;

  /// The other member of the pair (the binder is the sender).
  final int peer;
  final bool wantVideo;
}

/// `roster(2) ‖ peer(1) ‖ flags(1)`.
ControlRecord buildRelayBind({
  required int roster,
  required int peer,
  required bool wantVideo,
}) =>
    ControlRecord(
        ControlRecordType.relayBind,
        Uint8List.fromList([
          (roster >> 8) & 0xFF,
          roster & 0xFF,
          peer & 0xFF,
          wantVideo ? kRelayFlagVideo : 0,
        ]));

RelayBind? readRelayBind(ControlRecord record, int rosterLength) {
  if (record.type != ControlRecordType.relayBind) return null;
  final v = record.value;
  if (v.length != 4 || v[2] >= rosterLength) return null;
  return RelayBind(
    roster: (v[0] << 8) | v[1],
    peer: v[2],
    wantVideo: v[3] & kRelayFlagVideo != 0,
  );
}

/// A read [ControlRecordType.relayRefuse], [ControlRecordType.relayBound]
/// or [ControlRecordType.relayDrop] — the three records that name a pair.
final class RelayPair {
  const RelayPair({
    required this.type,
    required this.roster,
    required this.a,
    required this.b,
    required this.flags,
  });
  final ControlRecordType type;
  final int roster;

  /// The pair, the smaller index first.
  final int a;
  final int b;
  final int flags;

  bool get video => flags & kRelayFlagVideo != 0;
  bool get ack => flags & kRelayFlagAck != 0;
}

/// `roster(2) ‖ a(1) ‖ b(1) ‖ flags(1)` for [ControlRecordType.relayRefuse],
/// [ControlRecordType.relayBound] and [ControlRecordType.relayDrop].
ControlRecord buildRelayPair({
  required ControlRecordType type,
  required int roster,
  required int a,
  required int b,
  int flags = 0,
}) {
  if (type != ControlRecordType.relayRefuse &&
      type != ControlRecordType.relayBound &&
      type != ControlRecordType.relayDrop) {
    throw ArgumentError('${type.name} does not name a pair');
  }
  final lo = a < b ? a : b;
  final hi = a < b ? b : a;
  return ControlRecord(
      type,
      Uint8List.fromList(
          [(roster >> 8) & 0xFF, roster & 0xFF, lo & 0xFF, hi & 0xFF, flags]));
}

RelayPair? readRelayPair(ControlRecord record, int rosterLength) {
  if (record.type != ControlRecordType.relayRefuse &&
      record.type != ControlRecordType.relayBound &&
      record.type != ControlRecordType.relayDrop) {
    return null;
  }
  final v = record.value;
  if (v.length != 5 || v[2] >= rosterLength || v[3] >= rosterLength) {
    return null;
  }
  return RelayPair(
    type: record.type,
    roster: (v[0] << 8) | v[1],
    a: v[2],
    b: v[3],
    flags: v[4],
  );
}

/// Packs records into ONE frame until the class is full.
///
/// Returns what fitted in and leaves the rest with the caller —
/// it takes it along into the next tick. **No frame is
/// exceeded**: the class boundary is the whole reason why this
/// function exists (§17.1: a promotion into the next class
/// would be a size difference on the wire).
Uint8List packControlRecords(
  List<ControlRecord> pending, {
  int? capacity,
}) {
  // The fallback value is fetched HERE and does not stand as a number in the
  // head of the signature: a default parameter must be
  // constant in Dart, and a constant would again be a second writing
  // of the size class. See [kControlRecordMaxValue].
  capacity ??= DFrameKind.control.frameClass.payloadCapacity;
  final out = BytesBuilder(copy: false);
  var used = 0;
  while (pending.isNotEmpty) {
    final r = pending.first;
    if (used + r.wireLength > capacity) break;
    out.addByte(r.type.code);
    out.addByte(r.value.length);
    out.add(r.value);
    used += r.wireLength;
    pending.removeAt(0);
  }
  return out.takeBytes();
}

/// Reads all records of a control frame.
///
/// An unknown record code does NOT end the reading — its length is
/// in the header, so it can be skipped. That is the difference from
/// the address candidates, where an unknown family determines how many bytes
/// follow, and the reading therefore MUST end. Here the reader knows it, and
/// a later build may add records without breaking older ones.
List<ControlRecord> readControlRecords(Uint8List body) {
  final out = <ControlRecord>[];
  var i = 0;
  while (i + 2 <= body.length) {
    final code = body[i];
    final len = body[i + 1];
    if (i + 2 + len > body.length) break; // truncated — do not guess
    final type = ControlRecordType.ofCode(code);
    if (type != null) {
      out.add(ControlRecord(
          type, Uint8List.sublistView(body, i + 2, i + 2 + len)));
    }
    i += 2 + len;
  }
  return out;
}
