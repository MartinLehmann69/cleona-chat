/// An IP address and port of a node — the address type of the update
/// paths that name a device (invitation link §26.6.3, physical handover
/// §26.6.6).
///
/// It lived in `rendezvous/rendezvous_provider.dart` while the binary
/// distribution announced itself over Nostr. That path is gone (owner
/// decision V9 A1, 08.10.2026; v4_2 §26.6.4 "no external rendezvous
/// channel"); the type stays because the handover and the invitation link
/// use it, and it moves here so that `lib/core/update/` does not depend on
/// the relay code. The JSON keys `i`/`p` are unchanged.
class EndpointAddress {
  final String ip;
  final int port;

  const EndpointAddress(this.ip, this.port);

  Map<String, dynamic> toJson() => {'i': ip, 'p': port};

  static EndpointAddress fromJson(Map<String, dynamic> j) =>
      EndpointAddress(j['i'] as String, j['p'] as int);
}
