// lib/core/calls/peer_hearing.dart
//
// What a group-call receiver can say about ONE sender: how many of its
// voice frames arrived, how many arrived a second time, and which tone
// they carried. Read over `get_group_call_state` (a state read); the E2E
// case "group call with 7 participants" (D-81, §17.7) proves with it that
// everyone hears everyone exactly once.
//
// Counting only. Nothing here drops, reorders or delays a frame — the
// jitter buffer and the playback path stay exactly as they were.
import 'dart:typed_data';

/// How a sequence number relates to what was seen before.
enum SeqVerdict { fresh, duplicate, stale }

/// The anti-replay sliding window of RFC 4303 §3.4.3 (IPsec ESP), used to
/// COUNT duplicates, not to reject them: the highest number seen and a
/// bitmap of the [size] numbers below it.
///
/// A number far below the window (more than [restartGap] behind the top)
/// is a sender whose capture counter started again (`AudioMixer` begins at
/// 0 on every start); the window restarts there instead of calling every
/// later frame stale.
class SeqWindow {
  static const int size = 64;
  static const int restartGap = 1000;

  int? _top;
  int _mask = 0; // bit i = top - i seen

  SeqVerdict accept(int seq) {
    final top = _top;
    if (top == null || seq + restartGap < top) {
      _top = seq;
      _mask = 1;
      return SeqVerdict.fresh;
    }
    if (seq > top) {
      final shift = seq - top;
      // The VM's int is 64 bits wide: bits shifted past 63 fall off, which
      // is exactly the window moving on.
      _mask = shift >= size ? 1 : (_mask << shift) | 1;
      _top = seq;
      return SeqVerdict.fresh;
    }
    final back = top - seq;
    if (back >= size) return SeqVerdict.stale;
    final bit = 1 << back;
    if (_mask & bit != 0) return SeqVerdict.duplicate;
    _mask |= bit;
    return SeqVerdict.fresh;
  }
}

/// Per-sender hearing at one receiver.
class PeerHearing {
  /// Voice frames that opened under the sender's `send_key` with a sequence
  /// number not seen before.
  int framesHeard = 0;

  /// Frames whose sequence number was already seen — the same frame came a
  /// second time (two paths, or a forwarding loop).
  int framesDuplicate = 0;

  /// Dominant frequency of the decoded signal over the last full
  /// [toneWindowFrames] frames with signal; 0 until one window is full.
  double toneHz = 0;

  /// Frames of signal per tone estimate: 50 = one second at 20 ms.
  static const int toneWindowFrames = 50;

  /// Below this peak (of 32768) a frame counts as silence, not as tone.
  static const int silencePeak = 300;

  final SeqWindow _seq = SeqWindow();
  int _crossings = 0;
  int _samples = 0;
  int _frames = 0;
  int _lastSign = 0; // carried across frames, so no crossing is lost

  /// Counts one decrypted frame with sequence number [seq].
  SeqVerdict countFrame(int seq) {
    final v = _seq.accept(seq);
    switch (v) {
      case SeqVerdict.fresh:
        framesHeard++;
      case SeqVerdict.duplicate:
        framesDuplicate++;
      case SeqVerdict.stale:
        break;
    }
    return v;
  }

  /// Adds one decoded frame of mono PCM at [sampleRate] to the tone
  /// estimate (zero crossings: f = crossings * rate / (2 * samples)).
  void addPcm(Int16List pcm, int sampleRate) {
    var peak = 0;
    var crossings = 0;
    var last = _lastSign;
    for (var i = 0; i < pcm.length; i++) {
      final s = pcm[i];
      final a = s.abs();
      if (a > peak) peak = a;
      if (s == 0) continue;
      final sign = s > 0 ? 1 : -1;
      if (last != 0 && sign != last) crossings++;
      last = sign;
    }
    _lastSign = last;
    if (peak < silencePeak || sampleRate <= 0) return;
    _crossings += crossings;
    _samples += pcm.length;
    if (++_frames < toneWindowFrames) return;
    toneHz = _crossings * sampleRate / (2 * _samples);
    _crossings = 0;
    _samples = 0;
    _frames = 0;
  }
}
