/// On which channels a node actually calls — and how it says what
/// of it works.
///
/// ── WHY THIS IS A SEPARATE FILE ──────────────────────────────────────
///
/// `neighbours.dart` stood at the line budget (395 of 400) when S384 got the second
/// find source: an incoming CALL also teaches a neighbour,
/// no longer only the answer to one's own. The budget has no
/// exception mechanism — if it does not fit, the design is wrong, not the
/// limit.
///
/// The cut lies here because it carries: in THIS file stands what the
/// search can do at all (group, broadcast, both, none) and how it tells
/// operation. Over there stands HOW finding happens. Nothing here knows
/// a neighbour, a find or an identifier, and nothing here accesses
/// the state of `Neighbours` — therefore free functions and no
/// extension; an extension would not get at the private sockets over there
/// anyway.
///
/// `neighbours.dart` passes this file on via `export`, so that a
/// caller imports only one name as before.
library;

import 'dart:io';

/// What an instance of the neighbour search can actually do.
///
/// The group join (multicast) or the broadcast release (broadcast)
/// can fail — in a container, behind some VPNs, with some
/// Wi-Fi drivers. According to chapter 7.2 that is NOT an error case: the node
/// stays bound to the wildcard address and continues with what
/// works. What it can do stands here and is reported on opening.
enum CallRoute {
  /// Both — the normal case.
  groupAndBroadcastCall,

  /// Multicast only: the broadcast release was refused.
  onlyGroup,

  /// Broadcast only: the group join was refused.
  onlyBroadcastCall,

  /// Neither of the two. The node keeps running, but no longer finds
  /// anybody in the segment by itself and depends on the second neighbour source.
  none,
}

/// The group join as a separate handle, so that the probe can really trigger the error case
/// without needing an environment without multicast. The
/// default value is the real thing; the opening catches by itself.
typedef GroupJoin = void Function(
    RawDatagramSocket socket, InternetAddress group);

/// The same for the broadcast release.
typedef BroadcastRelease = void Function(RawDatagramSocket socket);

/// And the same for the listener itself. For the same reason as the two
/// above: an occupied port cannot be produced reliably in a probe
/// (`reusePort` makes a second bind succeed), and a
/// tolerance of which nobody can show that it takes effect is none.
typedef ListenerBinding = Future<RawDatagramSocket> Function(int port);

/// The real listener. Default value.
Future<RawDatagramSocket> realListenerBinding(int port) =>
    RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
        reuseAddress: true, reusePort: true);

/// The real group join. Default value.
void realGroupJoin(RawDatagramSocket socket, InternetAddress group) =>
    socket.joinMulticast(group);

/// The real broadcast permission. Default value.
void realBroadcastRelease(RawDatagramSocket socket) =>
    socket.broadcastEnabled = true;

/// Says what is used. In the normal case one line via [report]; if
/// something has failed and nobody is listening, to stderr — quietly being able to do less
/// is allowed, quietly being able to do less WITHOUT saying so is not.
void sayWhatGoes(CallRoute route, String? groupReason, String? broadcastCallReason,
    void Function(String)? report) {
  final text = switch (route) {
    CallRoute.groupAndBroadcastCall => 'Neighbour search: group and broadcast.',
    CallRoute.onlyGroup =>
      'Neighbour search: only group, no broadcast ($broadcastCallReason). '
          'Not an error — the search continues, restricted.',
    CallRoute.onlyBroadcastCall =>
      'Neighbour search: only broadcast, no group ($groupReason). '
          'Not an error — the search continues, restricted.',
    CallRoute.none =>
      'Neighbour search: neither group ($groupReason) nor broadcast '
          '($broadcastCallReason). In the segment nobody is found by itself '
          'any more; the second neighbour source remains.',
  };
  if (report != null) {
    report(text);
  } else if (route != CallRoute.groupAndBroadcastCall) {
    stderr.writeln(text);
  }
}
