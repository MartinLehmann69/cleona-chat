/// How often a receiver may ask its peer for a keyframe (§17.2).
///
/// §17.2: a signal of a running call goes once and ends with its
/// acknowledgement or its call; for the sender key the norm adds "asks once,
/// asks again only after a key has arrived". Both triggers of a keyframe
/// request — the video engine before its first keyframe
/// (`VideoEngine.processReceivedFrame`) and the fragment reassembler on a lost
/// keyframe (`VideoFrameReassembler.onKeyframeLost`) — fire per RECEIVED
/// frame. S422-RCA-E2E-LAUF-4.2.8 R-16a: without a gap an Android device sent
/// up to 64 requests per second, each a whole message on ladder steps 1 and 3
/// (about 4.6 KB per step), and the peer forced a keyframe for every one of
/// them (working rule 5).
///
/// One request per [gap] and call still asks again when a request or the
/// keyframe it asked for was lost; the gap is far above a round trip in the
/// lab or the field, so a keyframe that was asked for arrives inside it.
library;

class KeyframeRequestGate {
  KeyframeRequestGate({this.gap = kKeyframeRequestGap});

  /// At most one keyframe request per call within this gap.
  static const Duration kKeyframeRequestGap = Duration(seconds: 1);

  final Duration gap;
  DateTime? _at;
  String? _call;

  /// Whether a request for [callIdHex] may go out at [now]; records it if so.
  /// A new call opens the gate at once.
  bool allow(String callIdHex, DateTime now) {
    final last = _at;
    if (_call == callIdHex && last != null && now.difference(last) < gap) {
      return false;
    }
    _at = now;
    _call = callIdHex;
    return true;
  }
}
