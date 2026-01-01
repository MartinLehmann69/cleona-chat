// Call arbitration with several devices of one identity.
//
// ── WHY THIS FILE EXISTS ──────────────────────────────────────────
//
// Product decision of the owner (28.08.2026): "All devices with the
// addressed UserID must ring. We cannot know which one the
// called user is sitting at. If one of them picks up, the
// ringing on the others must of course stop."
//
// The architecture already makes the same statement normatively. §14.2: "One
// delivery serves all devices. All devices share the `inbox_key` -> they
// harvest **the same tag line**. The delivery path has **no device level**."
// And §17.2, paragraph "Multi-device (§14)": "an INVITE is **one** cell — all
// of the callee's devices harvest the same tag line and ring. `RING_ACK`
// carries the `deviceId`; the first `ANSWER` binds the session to one
// device, `CANCEL_OTHERS` (TTL 120 s) ends the ringing of the others."
//
// Ringing on all devices thus costs NOTHING — it falls out of the
// delivery layer as soon as the INVITE goes to the UserID instead of to a device.
// What was missing was the reverse direction: ending the ringing on the
// remaining devices. Two building blocks stand here for that.
//
// ── BUILDING BLOCK 1: [CancelOthers] ──────────────────────────────────────────
//
// Who tells the other devices that someone picked up? The CALLER, not
// the device picking up. The rationale is a property of the
// delivery layer, not a question of taste:
//
//   * A device's ANSWER goes to the CALLER's tag. The
//     sibling devices do not harvest the caller's tag — they thus NEVER see
//     their sibling's ANSWER. No device can know on its own
//     that another one has picked up.
//   * Only the caller sees all ANSWERs. Only there does an
//     order exist, and only it can decide "the first one wins" at all.
//     §17.2 says exactly that: "the first ANSWER binds the
//     session to one device."
//   * The caller does not need to know the devices for this (§14.1: the DeviceID
//     is "a **subject**, not a **signpost**"). It addresses the UserID;
//     the one cell reaches all remaining devices. One delivery,
//     not N — working rule 5.
//
// The counter-design — the picking-up device reports it via twin sync (§14.7)
// to its siblings — fails on three points: (a) §14.7 lists 17
// content types, none of which fits, and "Detailed call history" is
// explicitly on the list of what is NOT synced; (b) it
// costs a SECOND delivery (to the own `K_own` tag) in addition
// to the ANSWER; (c) it does not resolve the race — if two devices pick up
// at the same time, each claims to have won, and the
// two messages cross in transit. An arbiter must be ONE.
//
// ## How the winning device recognises itself
//
// Via the identity's tag, CANCEL_OTHERS also reaches the device that
// has just picked up. It must thus recognise itself, otherwise it hangs up
// its own call. A state comparison ("I am already in a
// call, so I am meant") does not hold: in the race BOTH
// picking-up devices are in the call state before the first CANCEL_OTHERS
// arrives.
//
// The recognition value is therefore the **ephemeral X25519 key
// of the callee** from the ANSWER that bound the session:
//
//   * It is freshly drawn per call AND per device
//     (`CallManager.acceptCall`), so a different one for each device.
//   * It is already on the line (`CallAnswer.callee_eph_x25519_pk`) —
//     the caller has it, the picking-up device has it locally.
//   * It is NOT a device identifier. §14.1 does allow the DeviceID for
//     attribution, but using it here would mean writing it into a message
//     to a CONTACT; the ephemeral key says
//     the same and reveals nothing that the contact does not already know from the
//     ANSWER.
//   * A device that is still ringing has none at all — it can never
//     wrongly pass as the winner.
//
// ## The carrier on the line
//
// CANCEL_OTHERS has its OWN message type:
// `MTV3_CALL_CANCEL_OTHERS` (88, `proto/transport_v3.proto`) with the
// payload `CallCancelOthers { bytes call_id = 1; bytes bound_answer_key
// = 2; }` (`proto/app_payloads.proto`). §17.2 lists CANCEL_OTHERS
// explicitly as a signaling kind of its own next to INVITE, RING_ACK,
// ANSWER, REJECT and HANGUP.
//
// Before, the arbitration piggybacked on `MTV3_CALL_REJECT` and put the
// binding key as `answered_elsewhere:<hex>` into `CallReject.reason`.
// That was the deliberate interim form as long as the work package cut
// did not include `proto/*.proto`. Why it had to go although it
// worked:
//
//   * **A rejection and an arbitration are two events with
//     different outcomes.** The rejection ends the call for the whole
//     identity; the arbitration spares exactly one device. That a
//     receiver tells the two apart depended on a prefix in
//     a free-text field — and `reason` is a field into which a peer
//     can write whatever it wants.
//   * **The receive path had to treat both cases the same before the
//     branch.** `call_service.handleCallRejectV3` stops ringtone and
//     vibration and clears the Android notification BEFORE
//     delegating — also on the winning device that is currently in the
//     call. With its own type, the arbitration has its own
//     entry point that clears nothing it should not clear.
//   * **The binding key is a 32-byte point, not text.** As hex
//     in `reason` it cost 51 characters instead of 32 bytes and had to be
//     checked against length and character set on every receipt.
//
// ## Backward compatibility: the old piggyback path is still UNDERSTOOD
//
// Only the own type is sent now. On RECEIPT the piggyback path
// stays: [CancelOthers.tryDecode] is still called in `handleCallRejectV3`,
// so that a device with the old state — a second own
// device that has not been updated yet — can still pronounce the arbitration
// and we end its ringing. The path is
// asymmetric and is meant to be: it costs a
// prefix check on receipt and disappears as soon as no device is old anymore.
//
// **Effect on the frozen 3.2 line: none.** The V4.1 delivery
// and the V3 network layer share no line — `docs/
// MIGRATION_V3_TO_V4_1.md` §2 lists "no wire backward compat" as a
// non-goal that remains valid. It was measured nevertheless: if one
// presented a 3.2 receiver with a signed frame with `message_type = 88`,
// the unknown enum value landed in `unknownFields`, and the
// re-serialisation in `v3_frame_codec.dart:521-527` would push it to the end
// of the buffer — the signature check fails and the frame is
// discarded before the dispatch sees it. It is thus NOT misinterpreted as
// `MTV3_TEXT` (enum value 0, the protobuf default), which would have happened without
// the signature over the field order.
//
// ── BUILDING BLOCK 2: [TerminatedCallLedger] ──────────────────────────────────
//
// §17.2: "completed `callId`s are remembered for 24 h (late duplicates are
// no-ops)." Without this memory a device rings for a call that ended long
// ago — and not just theoretically:
//
//   * The caller repeats its INVITE every 3 s (`_scheduleInviteRetry`,
//     19 repetitions). A device that has just processed CANCEL_OTHERS
//     gets the next repetition fractions of a second later and
//     would ring again.
//   * On the harvest tag, INVITE and CANCEL_OTHERS lie side by side. A
//     device that was offline harvests both — in any order.
//     If CANCEL_OTHERS comes first, the INVITE afterwards must no longer
//     trigger anything. §17.2: "terminal types (`REJECT`, `HANGUP`) dominate any
//     later out-of-order arrival."
//
// The memory is purely local and needs no line.
//
// **Deadline against the ancient.** The 120 s deadline from §17.2 ("an INVITE cannot ring
// days later") is a property of the delivery layer — the cell expires
// at the relays. A second, receiver-side latch already exists:
// `call_service.handleCallInviteV3` discards an INVITE whose claimed
// timestamp is older than 60 s. Both latches lie outside this
// work package and are stricter than §17.2 requires; therefore
// no third age limit is introduced here. What was missing here and now exists
// is the memory for ENDED calls — which no age limit
// can replace and which replaces none.

import 'dart:typed_data';

import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/util/hex.dart';

/// CANCEL_OTHERS (§17.2): the comparison by which the winning device
/// recognises itself — plus the OLD piggyback path in the `CallReject.reason` field.
///
/// [namesUs] and [boundKeyLength] apply to both carriers. [encode] and
/// [tryDecode] concern exclusively the old piggyback path: it is no longer
/// sent (that is done by `MTV3_CALL_CANCEL_OTHERS`), but still understood — see
/// the file header, section "Backward compatibility".
class CancelOthers {
  /// Prefix in the `reason` field of the OLD piggyback path. Collides with no
  /// rejection reason generated in code.
  static const String reasonPrefix = 'answered_elsewhere:';

  /// Length of the binding key: an X25519 point.
  static const int boundKeyLength = 32;

  static final RegExp _hex = RegExp(r'^[0-9a-f]+$');

  /// Builds the `reason` value of the OLD piggyback path.
  ///
  /// **Is no longer sent.** The send path is
  /// `MTV3_CALL_CANCEL_OTHERS` with `CallCancelOthers`. This method stays
  /// because [tryDecode] would not be testable without its counterpart and because a
  /// test must be able to emulate an old sender.
  ///
  /// [boundAnswerKey] is the ephemeral X25519 key of the callee
  /// from the ANSWER that bound the session.
  static String encode(Uint8List boundAnswerKey) {
    if (boundAnswerKey.length != boundKeyLength) {
      throw ArgumentError(
          'boundAnswerKey must be $boundKeyLength bytes long, is '
          '${boundAnswerKey.length}');
    }
    return '$reasonPrefix${bytesToHex(boundAnswerKey)}';
  }

  /// Reads the binding key from a `reason` value of the OLD
  /// piggyback path, or `null` if it is an ordinary rejection.
  ///
  /// Stays in the receive path so that an own device not yet updated
  /// can still pronounce the arbitration.
  ///
  /// Strict: prefix, exact length and character set are checked.
  /// Anything that does not fit exactly is NOT a CANCEL_OTHERS — the caller
  /// then treats it as a normal rejection and hangs up. That is the safe
  /// direction: a malformed value ends a call instead of leaving a
  /// ringing device standing.
  static Uint8List? tryDecode(String reason) {
    if (!reason.startsWith(reasonPrefix)) return null;
    final hex = reason.substring(reasonPrefix.length);
    if (hex.length != boundKeyLength * 2) return null;
    if (!_hex.hasMatch(hex)) return null;
    return hexToBytes(hex);
  }

  /// Is [candidate] the key that [boundAnswerKey] names?
  ///
  /// Constant run time: the comparison decides whether a device keeps its
  /// own call, and the value comes from a message from
  /// outside.
  static bool namesUs(Uint8List? candidate, Uint8List boundAnswerKey) {
    if (candidate == null) return false;
    if (candidate.length != boundAnswerKey.length) return false;
    return constantTimeEquals(candidate, boundAnswerKey);
  }
}

/// Memory for ended calls (§17.2: 24 h).
///
/// Deliberately NO timer: the entry expires on the next access, not
/// at a point in time. A call memory that ticks in the background would be
/// an alarm clock for nothing (working rule 5 applies analogously to
/// wake-ups on the device too).
class TerminatedCallLedger {
  /// §17.2: „completed `callId`s are remembered for 24 h".
  static const Duration retention = Duration(hours: 24);

  /// Upper bound against unbounded growth. It is only reached if a
  /// contact ends more than [maxEntries] different calls within 24 h —
  /// then the oldest entry drops out, and the corresponding call has
  /// long ceased to be a repetition candidate.
  static const int maxEntries = 512;

  final DateTime Function() _now;
  final Map<String, DateTime> _entries = <String, DateTime>{};

  /// [clock] exists for testing the expiry limit; production
  /// leaves it out.
  TerminatedCallLedger({DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  int get length => _entries.length;

  /// Mark this call as ended. Marking multiple times renews the
  /// time — rightly so: the deadline runs from the last event that
  /// confirmed the termination.
  void record(Uint8List callId) {
    if (callId.isEmpty) return;
    _prune();
    _entries[bytesToHex(callId)] = _now();
    if (_entries.length > maxEntries) {
      final oldest = _entries.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _entries.remove(oldest);
    }
  }

  /// Was this call ended within the deadline?
  bool isTerminated(Uint8List callId) {
    if (callId.isEmpty) return false;
    final at = _entries[bytesToHex(callId)];
    if (at == null) return false;
    if (_now().difference(at) > retention) {
      _entries.remove(bytesToHex(callId));
      return false;
    }
    return true;
  }

  void clear() => _entries.clear();

  void _prune() {
    final now = _now();
    _entries.removeWhere((_, at) => now.difference(at) > retention);
  }
}
