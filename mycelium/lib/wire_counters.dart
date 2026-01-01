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
