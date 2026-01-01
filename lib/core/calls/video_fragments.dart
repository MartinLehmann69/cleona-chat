/// Video frames on Plane D: split on the sender, reassembled on the receiver
/// (§17.1, S399).
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────────
///
/// §17.1 carries video in the 1200 B class ("one video fragment … video is
/// fragmented anyway"). A D frame of that class carries at most
/// [DFrameClass.payloadCapacity] = 1200 − 43 = **1157 B** of payload
/// (`d_frame.dart`: cookie 8 + nonce 12 + tag 16 + inner header 7). One
/// serialized `VideoFrame` of the mock at preset `medium` is 3382 B, a
/// keyframe 16 715 B (S399-MESSUNG-V3-VIDEOGROESSE.md). Before this file
/// `CallTransportV41.sendMedia` refused every such frame as `tooLarge`:
/// 1:1 video carried nothing at all.
///
/// ── THE FORMAT ──────────────────────────────────────────────────────────
///
/// Each fragment is itself a `VideoFrame` proto (`app_payloads.proto`), so
/// there is one reader and no second format:
///
///   * `sequence_number` — the frame identifier, the same on every fragment
///     of a frame (the engine numbers frames, not fragments);
///   * `flags` — the frame's own flags (keyframe) on EVERY fragment, plus
///     [kVideoFlagIsFragment], and [kVideoFlagLastFragment] on the last;
///   * `fragment_index` / `fragment_total` — i of n;
///   * `encrypted_data` — the i-th slice of the frame's ciphertext;
///   * `nonce`, `width`, `height`, `timestamp_ms` — on fragment 0 only.
///     The ciphertext is useless without all fragments, so fragment 0 is
///     needed anyway; repeating 25 B of metadata on every fragment would
///     turn a medium delta frame (3349 B of ciphertext) into four D frames
///     instead of three.
///
/// A frame that fits into one D frame goes out unchanged — no fragment
/// fields, `fragment_total` 0 — and the receiver passes it straight through.
///
/// ── WHAT THE RECEIVER DOES WITH LOSS ────────────────────────────────────
///
/// This is real-time media, not a payload path: a lost fragment is **never
/// requested again** (§17.6: live media is never re-requested; the brief of
/// S399: no resend). A frame with a missing fragment is dropped, and the
/// decoder gets only whole frames. When a dropped frame was a keyframe, the
/// receiver asks the sender for a new one ([VideoFrameReassembler.onKeyframeLost])
/// — the same `CALL_KEYFRAME_REQUEST` the engine already sends when its
/// decoder cannot start (§17.5).
///
/// **No timer.** A frame is given up by ARRIVALS, never by a clock:
///
///   1. when a newer frame completes, every older open frame is dropped —
///      the decoder has moved past it, handing it over late would feed the
///      decoder out of order;
///   2. when more than [kVideoReassemblyOpenFrames] frames are open, the
///      oldest gives way.
///
/// So nothing runs while nothing arrives (Arbeitsregel 5), and the memory a
/// peer can pin is bounded: at most [kVideoReassemblyOpenFrames] frames of at
/// most [kVideoMaxFragments] fragments of at most 1157 B each — 8 × 256 ×
/// 1157 B ≈ 2.4 MB in the worst case, typically one or two open frames of a
/// few kB.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:cleona/core/calls/video_pipeline.dart' show kVideoFlagKeyframe;
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;

/// `app_payloads.proto`, `VideoFrame.flags`: "0x02 = last fragment of this
/// frame".
const int kVideoFlagLastFragment = 0x02;

/// `app_payloads.proto`, `VideoFrame.flags`: "0x04 = frame is a fragment".
const int kVideoFlagIsFragment = 0x04;

/// The most fragments one frame may have.
///
/// Sized against the encoder ceiling, not guessed: `kLiveMediaMaxFrameBytes`
/// (`live_media_frame_budget.dart`) lets the encoder emit up to 242 352 B,
/// and at ~1130 B of ciphertext per fragment that is 215 fragments. 256 covers
/// it; the receiver refuses anything above, so a peer cannot make it hold
/// more than this per frame.
const int kVideoMaxFragments = 256;

/// How many incomplete frames the receiver keeps at once.
///
/// 8 frames are 267 ms at 30 fps (preset `medium`) and 533 ms at 15 fps
/// (`tile`) — longer than any frame is worth showing late. A frame still
/// incomplete after that is lost in any practical sense.
const int kVideoReassemblyOpenFrames = 8;

/// How far a sequence number may fall behind the last delivered one before
/// the receiver takes it as a restarted sender (a new engine counts from 0)
/// or a wrapped `uint32`, not as a late frame. 1024 frames are 34 s at 30
/// fps — far beyond any reordering on one path.
const int kVideoSequenceRestartGap = 1024;

/// Varint length of a non-negative integer as protobuf writes it.
int _varintLength(int v) {
  var n = 1;
  while (v >= 0x80) {
    v >>= 7;
    n++;
  }
  return n;
}

/// Splits one serialized `VideoFrame` into pieces of at most [capacity]
/// bytes each.
///
/// Returns the frame itself (one element) when it fits, the fragments when it
/// does not, and an EMPTY list when it would need more than
/// [kVideoMaxFragments] fragments — the caller then has nothing to send and
/// must not count the frame as sent.
List<Uint8List> splitVideoFrame(Uint8List serialized, int capacity) {
  if (serialized.length <= capacity) return [serialized];

  final frame = proto.VideoFrame.fromBuffer(serialized);
  final data = frame.encryptedData;
  final baseFlags = frame.flags;

  // Header sizes with the worst-case fragment fields, so that the actual
  // (smaller or equal) values can never push a fragment over [capacity].
  final firstHeader = proto.VideoFrame()
    ..callId = frame.callId
    ..sequenceNumber = frame.sequenceNumber
    ..flags = baseFlags | kVideoFlagIsFragment | kVideoFlagLastFragment
    ..fragmentIndex = kVideoMaxFragments - 1
    ..fragmentTotal = kVideoMaxFragments
    ..width = frame.width
    ..height = frame.height
    ..nonce = frame.nonce
    ..timestampMs = frame.timestampMs;
  final restHeader = proto.VideoFrame()
    ..callId = frame.callId
    ..sequenceNumber = frame.sequenceNumber
    ..flags = baseFlags | kVideoFlagIsFragment | kVideoFlagLastFragment
    ..fragmentIndex = kVideoMaxFragments - 1
    ..fragmentTotal = kVideoMaxFragments;
  // Field 9 (`encrypted_data`): one tag byte plus the length varint.
  final dataFieldOverhead = 1 + _varintLength(capacity);
  final firstChunk =
      capacity - firstHeader.writeToBuffer().length - dataFieldOverhead;
  final restChunk =
      capacity - restHeader.writeToBuffer().length - dataFieldOverhead;
  if (firstChunk <= 0 || restChunk <= 0) return const [];

  final total = data.length <= firstChunk
      ? 1
      : 1 + ((data.length - firstChunk + restChunk - 1) ~/ restChunk);
  if (total > kVideoMaxFragments) return const [];

  final out = <Uint8List>[];
  var offset = 0;
  for (var i = 0; i < total; i++) {
    final take = i == 0 ? firstChunk : restChunk;
    final end = (offset + take) > data.length ? data.length : offset + take;
    final last = i == total - 1;
    final f = proto.VideoFrame()
      ..sequenceNumber = frame.sequenceNumber
      ..flags = baseFlags |
          kVideoFlagIsFragment |
          (last ? kVideoFlagLastFragment : 0)
      ..fragmentIndex = i
      ..fragmentTotal = total
      ..encryptedData = data.sublist(offset, end);
    if (frame.hasCallId()) f.callId = frame.callId;
    if (i == 0) {
      f
        ..width = frame.width
        ..height = frame.height
        ..nonce = frame.nonce
        ..timestampMs = frame.timestampMs;
    }
    final bytes = f.writeToBuffer();
    if (bytes.length > capacity) {
      // Cannot happen with the worst-case headers above; if it ever does,
      // it is a bug here and must be loud, not a silent `tooLarge` later.
      throw StateError('video fragment $i/$total is ${bytes.length} B '
          '> capacity $capacity B');
    }
    out.add(bytes);
    offset = end;
  }
  return out;
}

class _Partial {
  _Partial(this.total, this.isKeyframe) : parts = List.filled(total, null);
  final int total;
  final bool isKeyframe;
  final List<List<int>?> parts;
  proto.VideoFrame? head;
  int have = 0;
}

/// Puts fragments from [splitVideoFrame] back together, one instance per
/// call and direction. See the library comment for the rules.
class VideoFrameReassembler {
  /// A keyframe was dropped incomplete; the sender should send a new one.
  void Function()? onKeyframeLost;

  /// Whole frames handed out.
  int framesCompleted = 0;

  /// Frames given up with fragments missing.
  int framesDropped = 0;

  /// Fragments that were malformed, duplicate or late and therefore ignored.
  int fragmentsIgnored = 0;

  final SplayTreeMap<int, _Partial> _open = SplayTreeMap<int, _Partial>();
  int? _lastDelivered;

  /// Number of incomplete frames held right now.
  int get openFrames => _open.length;

  /// Feeds one D frame payload. Returns a whole serialized `VideoFrame` when
  /// [payload] completed one (or was one), otherwise null.
  Uint8List? add(Uint8List payload) {
    final proto.VideoFrame f;
    try {
      f = proto.VideoFrame.fromBuffer(payload);
    } catch (_) {
      fragmentsIgnored++;
      return null;
    }
    final seq = f.sequenceNumber;
    if (_isLate(seq)) {
      fragmentsIgnored++;
      return null;
    }

    final fragmented = (f.flags & kVideoFlagIsFragment) != 0;
    if (!fragmented && f.fragmentTotal <= 1) {
      _complete(seq,
          completedIsKeyframe: (f.flags & kVideoFlagKeyframe) != 0);
      return payload;
    }

    final total = f.fragmentTotal;
    final index = f.fragmentIndex;
    if (total < 1 || total > kVideoMaxFragments || index >= total) {
      fragmentsIgnored++;
      return null;
    }

    var partial = _open[seq];
    if (partial != null && partial.total != total) {
      // Two different claims about the same frame: neither can be trusted.
      _open.remove(seq);
      _drop(partial);
      fragmentsIgnored++;
      return null;
    }
    if (partial == null) {
      while (_open.length >= kVideoReassemblyOpenFrames) {
        final oldest = _open.firstKey()!;
        _drop(_open.remove(oldest)!);
      }
      partial = _Partial(total, (f.flags & kVideoFlagKeyframe) != 0);
      _open[seq] = partial;
    }
    if (partial.parts[index] != null) {
      fragmentsIgnored++;
      return null;
    }
    partial.parts[index] = f.encryptedData;
    partial.have++;
    if (index == 0) partial.head = f;
    if (partial.have < partial.total) return null;

    _open.remove(seq);
    final builder = BytesBuilder(copy: false);
    for (final p in partial.parts) {
      builder.add(p!);
    }
    final head = partial.head!;
    final whole = proto.VideoFrame()
      ..sequenceNumber = seq
      ..flags = head.flags & ~(kVideoFlagIsFragment | kVideoFlagLastFragment)
      ..width = head.width
      ..height = head.height
      ..nonce = head.nonce
      ..timestampMs = head.timestampMs
      ..encryptedData = builder.takeBytes();
    if (head.hasCallId()) whole.callId = head.callId;
    _complete(seq, completedIsKeyframe: partial.isKeyframe);
    return whole.writeToBuffer();
  }

  /// Forgets everything (call ended).
  void reset() {
    _open.clear();
    _lastDelivered = null;
  }

  bool _isLate(int seq) {
    final last = _lastDelivered;
    if (last == null || seq > last) return false;
    if (last - seq > kVideoSequenceRestartGap) {
      // A new sender engine (counts from 0) or a wrapped counter — start over
      // instead of refusing the whole rest of the call as "late".
      reset();
      return false;
    }
    return true;
  }

  /// [seq] was handed out: every older open frame is now too late.
  void _complete(int seq, {bool completedIsKeyframe = false}) {
    framesCompleted++;
    _lastDelivered = seq;
    var keyframeLost = false;
    while (_open.isNotEmpty && _open.firstKey()! < seq) {
      final old = _open.remove(_open.firstKey()!)!;
      framesDropped++;
      if (old.isKeyframe) keyframeLost = true;
    }
    // A newer keyframe that did arrive makes the lost one irrelevant.
    if (keyframeLost && !completedIsKeyframe) onKeyframeLost?.call();
  }

  void _drop(_Partial p) {
    framesDropped++;
    if (p.isKeyframe) onKeyframeLost?.call();
  }
}
