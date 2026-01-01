import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/card.dart';
import 'package:mycelium/node.dart';
import 'package:mycelium/node_helpers.dart';

/// The outside of the node: learning how one looks from outside,
/// and punching through a NAT.
///
/// Its own file for the same reason as `node_invitation.dart` — the
/// line budget of `node.dart` knows no exception. The cut follows
/// the question WHOM one asks: here someone who stands outside the own
/// segment, over there the own parts.
///
/// It gets by with the public side of [Node]: [Node
/// .outsideRoute], [Node.report] and [Node.publicAddress]; the router's
/// mapping it learns from the host network ([NodeOutside.mappedAddressFrom]).
extension NodeOutside on Node {

  /// Asks [neighbour] how the own address looks from there, and remembers
  /// it as [Node.publicAddress] — but only if it is not
  /// private.
  ///
  /// A neighbour in the own segment sees the LAN address. Writing it as
  /// "public" into a card would be worse than leaving the
  /// field empty: the counterpart would try for a whole
  /// ladder step an address under which it never finds anyone.
  /// This question is therefore only useful towards a counterpart
  /// OUTSIDE the own segment — and thus only once there is a
  /// second neighbour source (remembered neighbours, card, external entry).
  Future<CardAddress?> publicAddressLearn(
      InternetAddress neighbour, int neighbourPort) async {
    final seen = await outsideRoute.whatIsMyAddress(neighbour, neighbourPort);
    if (seen == null) {
      report('$neighbour:$neighbourPort did not say how I look');
      return null;
    }
    final asAddress = InternetAddress.fromRawAddress(seen.address);
    if (isPrivate(asAddress)) {
      report('seen from $neighbour: ${asAddress.address}:'
          '${seen.port} — private, not remembered as public address');
      return null;
    }
    // §11.9, §7.3 (S424 F-15): a granted router mapping is reachable from
    // every counterpart; the seen port behind the same outer address is only
    // the translator's outgoing port, reachable only for whom it asked.
    final mapped = mappedAddress;
    if (mapped != null &&
        _sameIp(mapped, seen) &&
        mapped.port != seen.port) {
      if (!(publicAddress?.equal(mapped) ?? false)) publicAddress = mapped;
      report('seen from $neighbour: ${asAddress.address}:${seen.port} — the '
          'granted mapping (port ${mapped.port}) stays the public address '
          '(§11.9)');
      return mapped;
    }
    publicAddress = seen;
    report('own public address: ${asAddress.address}:'
        '${seen.port}');
    return seen;
  }

  /// Knocks at [target] so that a NAT in front of it opens the return route.
  /// `true` as soon as the counterpart knocks in turn.
  Future<bool> knock(InternetAddress target, int targetPort) =>
      outsideRoute.knock(target, targetPort);

  /// The publisher key a card issued NOW carries (§15.2), or `null`: only
  /// while this node actually publishes its address record (§11.9). The
  /// outside source of the host answers it ([publisherKeyFrom]); a node
  /// without one publishes nothing and names no key.
  Uint8List? get publisherKey => _publisher[this]?.call();

  /// Wired by the outside source (`host_outside.dart`) at its construction.
  void publisherKeyFrom(Uint8List? Function() source) =>
      _publisher[this] = source;

  /// Whether this node's own reachability is evidenced (§11.8a) — the
  /// evidence byte of its `0x25` (§8.1, D-113): a fixed neighbour whose
  /// `0x25` says "not evidenced" holds no contact's place (§5.2). The host
  /// network answers it ([reachabilityEvidenceFrom], `reachableEvidenced`);
  /// a node without one has only its board's proof.
  bool get reachabilityEvidenced =>
      _evidence[this]?.call() ?? (board?.reachableProven ?? false);

  /// Wired by the host network (`host_network.dart`) at its construction.
  void reachabilityEvidenceFrom(bool Function() source) =>
      _evidence[this] = source;

  /// The outer IPv4 endpoint of a granted, unexpired router mapping (§7.3),
  /// or `null`. The host network answers it ([mappedAddressFrom]).
  CardAddress? get mappedAddress => _mapped[this]?.call();

  /// Wired by the host network (`host_network.dart`) at its construction.
  void mappedAddressFrom(CardAddress? Function() source) =>
      _mapped[this] = source;
}

bool _sameIp(CardAddress a, CardAddress b) =>
    a.equal(CardAddress(b.address, a.port));

final Expando<Uint8List? Function()> _publisher = Expando('publisher key');
final Expando<bool Function()> _evidence = Expando('own reachability evidence');
final Expando<CardAddress? Function()> _mapped = Expando('granted mapping');
