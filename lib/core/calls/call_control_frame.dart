/// The content of a Plane D CONTROL FRAME (§17.1.1).
///
/// ══ WHAT THIS FILE IS ══════════════════════════════════════════════
///
/// §17.1.1 gives Plane D a fourth frame kind and says what it
/// carries: "speech level, readiness, presentation role, layout size,
/// spanning tree updates, and RTT probes". [DFrameKind.control] is the
/// kind; here is what lies INSIDE.
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
  readiness(0x05);

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
