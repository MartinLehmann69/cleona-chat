/// What the wire itself has put on and taken off the data port — §25.5
/// "Bytes sent / received" and "Packets sent / received", link level.
///
/// Counted at the one place every packet passes ([Wire] in `wire.dart`):
/// a send is counted when the kernel accepted the whole packet, a receive
/// for every datagram read off a socket — before anything above decides
/// whether it is wanted. Bytes are UDP payload bytes; IP and UDP headers
/// are not the node's to see.
///
/// No clock, no traffic: the numbers only grow when a packet passes, and
/// whoever wants them reads them (the network statistics on looking,
/// S405 A-2). They run since the wire was opened and only upward.
class WireCounters {
  int bytesSent = 0;
  int packetsSent = 0;
  int bytesReceived = 0;
  int packetsReceived = 0;

  /// Every send the kernel did not accept whole, per family — not once per
  /// series like the log line of [SendFailures]; for the head of a log
  /// report (S422, §16.7).
  int sendFailures4 = 0;
  int sendFailures6 = 0;

  /// One send of the [kind] socket (`IPv4`/`IPv6`) the kernel did not accept.
  void failed(String kind) =>
      kind == 'IPv6' ? sendFailures6++ : sendFailures4++;

  /// One packet of [bytes] the kernel accepted.
  void sent(int bytes) {
    bytesSent += bytes;
    packetsSent++;
  }

  /// One datagram of [bytes] read off a socket.
  void received(int bytes) {
    bytesReceived += bytes;
    packetsReceived++;
  }
}

/// The send failures of ONE socket of the wire, said once per series (S420).
///
/// Until S420 a failed send left no trace: [Wire.send] returned `false`, and
/// the splitter above counts it without a line. Dart's `send` returns 0 for
/// a socket it holds as closed and for a native error, which it reports
/// later on the error stream (Dart SDK `socket_patch.dart`,
/// `_NativeSocket.send`: `if (isClosing || isClosed) return 0;` and the
/// `catch` that schedules `reportError` and returns 0). A descriptor the
/// operating system closed under the app (v4_2 §31.3, "Death of the file
/// descriptor") fails every packet — a line per packet would flood the log.
/// So: the FIRST failure of a series is said, then nothing until a send
/// succeeds again. The line names the socket (family, port) and what the
/// send returned or threw — never the target address. No clock, no traffic.
class SendFailures {
  /// Names the socket: family and port.
  final String Function() _which;
  final void Function(String) _say;
  bool _failing = false;

  /// Failure series said so far — for probes.
  int said = 0;

  /// Counts every failure of this socket into the wire's counters (S422).
  final void Function()? _count;

  SendFailures(this._which, this._say, [this._count]);

  /// Runs [send] for a packet of [length] bytes and returns what it
  /// returned. A short count or a throw is a failure; the throw goes on to
  /// the caller unchanged.
  int watch(int Function() send, int length) {
    final int n;
    try {
      n = send();
    } on Object catch (e) {
      _fail('threw ${e.runtimeType}');
      rethrow;
    }
    if (n == length) {
      _failing = false;
    } else {
      _fail('returned $n of $length B');
    }
    return n;
  }

  void _fail(String how) {
    _count?.call();
    if (_failing) return;
    _failing = true;
    said++;
    _say('wire: send on the ${_which()} failed ($how) — further failures '
        'stay silent until a send succeeds again (§31.3)');
  }
}
