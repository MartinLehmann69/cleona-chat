/// The header of a GROUP media frame on Plane D (§17.1, §17.7).
///
/// One byte before the body, and that is the whole frame:
///
/// ```
/// index(1) ‖ body(n)
/// ```
///
/// The body is unchanged what the producing layer delivers —
/// for audio the packet from `audio_mixer.dart` (`seq(4) ‖ nonce(12) ‖
/// AES-256-GCM-Chiffrat`), for video the serialised video frame. This
/// file does not touch it; it answers exactly one question that the
/// receiver cannot otherwise answer: **from whom**.
///
/// ── WHY THE SENDER INDEX DOES NOT GO AWAY ───────────────────────────
///
/// The obvious saving would be to remove it: Plane D carries in
/// its 43 B overhead an 8 B cookie, and the cookie knows its
/// remote side. **But the cookie names the last HOP, not the
/// speaker.** Measured in this tree:
///
///  * `media_relay.dart:123-140` — `forwardFrame` passes the payload
///    unchanged to every child.
///  * `d_socket.dart:197` — every child gets it in a NEWLY sealed
///    D frame with the cookie and the sequence number of ITS session
///    (`seq: _sendSeq`, one counter per session).
///
/// From the first forwarder on, the frame thus carries the identifier of the
/// forwarder. Without this byte a grandchild node in the crystal (§17.7)
/// cannot decide with which `send_key` it must decrypt — and
/// §10.2.1 gives every speaker their own. The frame would not be
/// "somewhat imprecisely attributed", but undecryptable.
///
/// For the same reason the sequence number also stays in the body: the
/// `seq` in the inner D header is the counter of ONE session and starts from
/// scratch at every hop. The jitter buffer needs an order over the
/// whole path.
///
/// ── WHAT THE INDEX IS, AND WHAT IT DOES NOT WITHSTAND ──────────────────────
///
/// The sender's place in [GroupCallSession.rosterSorted]. Both sides
/// form the same list by the same rule from the same set. **The
/// set can diverge** — during a join one node already has
/// the new one in the list and another not yet, and then
/// all places behind it shift by one. For the tree assignment
/// a checksum catches this; at 50 frames/s there is no room for that.
///
/// The case nevertheless does not fall through silently: a wrongly attributed
/// frame is opened with the wrong `send_key`, the AEAD tag does not
/// match, and `AudioMixer._decryptFrame` discards it. **Misattribution
/// costs frames, it does not produce wrong playback.** That is the
/// promise of this format — no more.
///
/// ── WHAT DELIBERATELY DOES NOT STAND HERE ──────────────────────────────────────
///
/// **No level field.** §17.7 requires one ("The relay reads a speech-level
/// field to make its selection"), and there is nothing in this tree that
/// would read one: `MediaRelay.forwardFrame` forwards every frame to
/// every child and selects nothing. Introducing a byte that
/// nobody reads would be another case of "built, not entered" —
/// the finding belongs in the report, not on the wire.
///
/// **No call identifier.** It stood as `call_id` (18 B packed) in the old
/// `GroupCallAudio`. A node conducts exactly one group call
/// (`GroupCallManager._currentGroupCall` is a single field), and the
/// D session exists per remote side anyway. The identifier answered a
/// question nobody asks.
library;

import 'dart:typed_data';

/// Length of the header in bytes. One — and every change to it is a
/// wire change.
const int kGroupMediaHeaderSize = 1;

/// The index carried by a sender that we do not find in the list.
///
/// 255 and not 0, because 0 is a valid place. A frame with this
/// index is deliverable (it is forwarded), but not
/// decryptable — the receiver does not know which `send_key` applies.
const int kUnknownSender = 255;

/// The largest place this format can express.
///
/// 254, and the limit from §17.7 lies at 30 (crystal) or 6
/// (full mesh). The byte is thus not the limit and will not become
/// it either.
const int kMaxSenderIndex = 254;

/// Puts [senderIndex] in front of [body].
///
/// [senderIndex] may be [kUnknownSender]. A value outside
/// 0..[kMaxSenderIndex] is a programming error and throws — it would otherwise
/// silently be truncated to a different byte and attribute the frame to a FOREIGN
/// participant.
Uint8List packGroupMedia(int senderIndex, Uint8List body) {
  if (senderIndex != kUnknownSender &&
      (senderIndex < 0 || senderIndex > kMaxSenderIndex)) {
    throw ArgumentError.value(senderIndex, 'senderIndex',
        'outside 0..$kMaxSenderIndex (or $kUnknownSender)');
  }
  final out = Uint8List(kGroupMediaHeaderSize + body.length);
  out[0] = senderIndex;
  out.setRange(kGroupMediaHeaderSize, out.length, body);
  return out;
}

/// The counterpart to [packGroupMedia].
///
/// Returns `null` for a frame that does not even carry the header. An
/// empty body, on the other hand, is not an error of this layer — Opus delivers
/// frames of 1-3 B with DTX switched on, and the verdict on that is made by the
/// layer that understands the body.
GroupMediaFrame? unpackGroupMedia(Uint8List frame) {
  if (frame.length < kGroupMediaHeaderSize) return null;
  return GroupMediaFrame(
    senderIndex: frame[0],
    body: Uint8List.sublistView(frame, kGroupMediaHeaderSize),
  );
}

/// An unpacked group media frame.
final class GroupMediaFrame {
  /// The sender's place in `rosterSorted`, or [kUnknownSender].
  final int senderIndex;

  /// The unchanged body — a view onto the input frame, not a copy.
  final Uint8List body;

  const GroupMediaFrame({required this.senderIndex, required this.body});

  /// Whether the index names a place that can be looked up.
  bool get hasSender => senderIndex != kUnknownSender;
}
