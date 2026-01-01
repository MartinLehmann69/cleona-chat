/// The route via the internet when both sides sit behind NAT — step
/// 4 of the ladder from `mycelium/berichte/P2-ablauf.md`.
///
/// Three packet kinds, assigned to this file alone:
///  - 0x40 how-do-I-look: to a neighbour reachable from outside.
///  - 0x41 this-is-how-you-look: the answer — the address as the neighbour
///    SAW it. The request carries no address field that a sender
///    could forge — only an identifier against which the answer is checked
///    (sender AND identifier must match, otherwise it is discarded).
///    The address stands in it TYPED (type byte + 4 or 16 B + port,
///    the same codec as in the card), i.e. 16 B for IPv4 and 28 B for
///    IPv6. Until S390 it was 15 B with four raw bytes without type, and an
///    IPv6 counterpart got no answer at all — see [_beiWieSeheIchAus].
///    There is no transition format: mycelium has not been shipped.
///  - 0x42 knock: simultaneous knocking of two neighbours behind NAT.
///
/// No foreign STUN packet — only this one exchange with a neighbour whom
/// one already knows from the own card anyway. Asking the OWN
/// router (NAT-PMP/PCP, then UPnP/IGD, §7.3) is not here: that
/// is taken over by the app seam (`lib/core/service/port_mapping.dart`), at
/// start and network change, independent of this neighbour exchange.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/wire.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/kinds.dart' as kinds;

const int kKindWhatIsMyAddress = kinds.kWhatIsMyAddress;
const int kKindYourAddressIs = kinds.kYourAddressIs;
const int kKindKnock = kinds.kKnock;

/// Binds a how-do-I-look request to its answer — 16 random bytes
/// (§7.3, table „`0x40` ask"; W10, S391: until then 8, the spec leads).
const int kIdentifierLength = 16;

const Duration kAnswerDeadlineStandard = Duration(seconds: 3); // waiting period for 0x41
const Duration kKeepAliveDeadlineStandard = Duration(seconds: 30); // see keep-alive sender
const int kKnockAtMostAttempts = 5; // after that the attempt counts as failed
const Duration kKnockInterval = Duration(milliseconds: 250);

final Random _random = Random.secure();
Uint8List _randomIdentifier() {
  final b = Uint8List(kIdentifierLength);
  for (var i = 0; i < kIdentifierLength; i++) {
    b[i] = _random.nextInt(256);
  }
  return b;
}

String _addressKey(InternetAddress address, int port) =>
    '${address.address}|$port';
String _identifierKey(Uint8List identifier) => identifier.join(',');

class _WaitingRequest {
  final InternetAddress neighbour;
  final int neighbourPort;
  final Completer<CardAddress> completed = Completer<CardAddress>();
  _WaitingRequest(this.neighbour, this.neighbourPort);
}

class _KnockAttempt {
  Timer? timer;
  final Completer<bool> completed = Completer<bool>();
}

/// Attaches itself to a [Wire] and serves its three packet kinds. The
/// wire stays the property of the caller, as with `Splitter`.
class OutsideRoute {
  /// Where the three packet kinds go. NO [Wire] any more, but a
  /// function — otherwise the outside route sends past the rest of the node.
  ///
  /// Measured on 14.09.2026: everything that leaves the socket of the node
  /// goes through `split.dart` and carries its 12-B header. A 0x40 sent out raw with
  /// `Wire.send` arrived at the other side in the
  /// `Splitter`, had no valid header and was dropped. The outside route
  /// was thus still mute even after wiring the kind allocation —
  /// two different routes out on the same socket are one too
  /// many.
  final void Function(Uint8List packet, InternetAddress target, int targetPort)
      _send;
  final Map<String, _WaitingRequest> _waitingRequests = {};
  final Map<String, _KnockAttempt> _waitingKnockAttempts = {};

  /// ONLY for observation/measurement, they do not change the behaviour itself:
  /// [onUnknownKnock] fires on 0x42 without a running [knock]
  /// attempt; [onAnswerSent] fires after 0x40 has been answered with 0x41,
  /// with the same address that stands in the answer.
  final void Function(InternetAddress from, int fromPort)? onUnknownKnock;
  final void Function(InternetAddress from, int fromPort)? onAnswerSent;

  /// The asked neighbour has answered 0x40 (0x41 with matching
  /// identifier, from the asked sender) — the confirmation from §11.8.
  void Function(InternetAddress from, int fromPort)? onAnswerReceived;

  /// A 0x40 was answered — with its identifier, for the echo of the
  /// keep-alive measurement (§8.1, `mapping_echo.dart`).
  void Function(Uint8List identifier, InternetAddress from, int fromPort)?
      onAsked;

  /// 0x45-0x47, the keep-alive measurement (§8.1) — `mapping_echo.dart`.
  void Function(Uint8List packet, InternetAddress from, int fromPort)? onProbe;

  /// 0x48-0x4A, the open check (§8.1) — `open_check_answer.dart`.
  void Function(Uint8List packet, InternetAddress from, int fromPort)?
      onOpenCheck;

  /// Alone on the wire — for probes and for anyone who does not otherwise use
  /// this socket. Here there is no splitter, hence no
  /// second route out.
  OutsideRoute(PacketRoute wire,
      {this.onUnknownKnock, this.onAnswerSent})
      : _send = ((p, target, targetPort) => wire.send(p, target, targetPort)) {
    wire.listen(_onPacket);
  }

  /// For the case that someone is already listening and sending on the same socket.
  ///
  /// Two reasons, both measured: (1) `RawDatagramSocket` is
  /// single-subscription, a second `listen` throws; (2) the [send] path
  /// of the node puts a header around every packet, one sent raw would not
  /// arrive over there. Whoever builds this way passes the same send path that the
  /// node otherwise uses, and feeds [receive] from its
  /// kind allocation — exactly that is what `node.dart` does.
  OutsideRoute.appended(
      void Function(Uint8List packet, InternetAddress target, int targetPort) send,
      {this.onUnknownKnock,
      this.onAnswerSent})
      : _send = send;

  /// Feed in a packet that someone else has taken from the wire.
  /// Foreign kinds are silently discarded — the allocation sits with the
  /// caller, not here.
  void receive(Uint8List packet, InternetAddress from, int fromPort) =>
      _onPacket(packet, from, fromPort);

  void _onPacket(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.isEmpty) return;
    final kind = packet[0];
    if (kinds.isMappingProbe(kind)) {
      onProbe?.call(packet, from, fromPort);
    } else if (kinds.isOpenCheck(kind)) {
      onOpenCheck?.call(packet, from, fromPort);
    } else if (kind == kKindWhatIsMyAddress) {
      _onWhatIsMyAddress(packet, from, fromPort);
    } else if (kind == kKindYourAddressIs) {
      _onYourAddressIs(packet, from, fromPort);
    } else if (kind == kKindKnock) {
      _onKnock(from, fromPort);
    }
  }

  /// (1) Learn the own public address. Sends 0x40 to
  /// [neighbour]:[neighbourPort], returns the address under which the neighbour
  /// SAW the packet — `null` on timeout.
  ///
  /// [identifier] instead of a random one: the keep-alive measurement
  /// (§8.1) needs it for its echo request, and a test reproduces with it a
  /// spoofing attempt with CORRECT identifier but WRONG sender address.
  Future<CardAddress?> whatIsMyAddress(
    InternetAddress neighbour,
    int neighbourPort, {
    Duration deadline = kAnswerDeadlineStandard,
    Uint8List? identifier,
  }) async {
    identifier ??= _randomIdentifier();
    final key = _identifierKey(identifier);
    final waiting = _WaitingRequest(neighbour, neighbourPort);
    _waitingRequests[key] = waiting;
    final request = Uint8List(1 + kIdentifierLength);
    request[0] = kKindWhatIsMyAddress;
    request.setRange(1, request.length, identifier);
    _send(request, neighbour, neighbourPort);
    try {
      return await waiting.completed.future.timeout(deadline);
    } on TimeoutException {
      return null;
    } finally {
      _waitingRequests.remove(key);
    }
  }

  void _onWhatIsMyAddress(Uint8List packet, InternetAddress from, int fromPort) {
    if (packet.length != 1 + kIdentifierLength) return; // broken, discard
    // S390: here stood `if (von.type != IPv4) return; // Karte kennt nur
    // IPv4`. The comment was wrong — the card has been able to do IPv6 since the
    // type byte (§15.2) —, and the line was the heaviest block in the whole
    // search space: a node that asked via IPv6 got NO answer,
    // not even a rejecting one. §11.4 makes this exchange the
    // ONLY route by which a node learns its own public address;
    // a node with only global IPv6 could therefore learn it by
    // no route.
    final b = BytesBuilder()
      ..addByte(kKindYourAddressIs)
      ..add(packet.sublist(1));
    addressWrite(
        b, CardAddress(Uint8List.fromList(from.rawAddress), fromPort));
    _send(b.toBytes(), from, fromPort);
    onAnswerSent?.call(from, fromPort);
    onAsked?.call(Uint8List.fromList(packet.sublist(1)), from, fromPort);
  }

  /// Sends [packet] on the route of this outside route — for the packets
  /// of the keep-alive measurement (§8.1), which belong to its range.
  void send(Uint8List packet, InternetAddress target, int targetPort) =>
      _send(packet, target, targetPort);

  void _onYourAddressIs(Uint8List packet, InternetAddress from, int fromPort) {
    // 1 + 8 + (1 + 4 + 2) = 16 B for IPv4, 28 B for IPv6. A fixed size
    // no longer exists; the shortest possible length is checked, and
    // at the end that no byte was left over (§15.2 „rejected as a whole").
    if (packet.length < 1 + kIdentifierLength + 1 + 4 + 2) return;
    final identifier = packet.sublist(1, 1 + kIdentifierLength);
    final key = _identifierKey(identifier);
    final waiting = _waitingRequests[key];
    if (waiting == null) return; // never asked (or already answered) -> gone
    if (waiting.neighbour.address != from.address ||
        waiting.neighbourPort != fromPort) {
      return; // identifier matches, but not from the asked neighbour -> gone
    }
    if (waiting.completed.isCompleted) return;
    var spot = 1 + kIdentifierLength;
    Uint8List take(int howMuch) {
      if (spot + howMuch > packet.length) {
        throw CardFormatError('0x41 truncated');
      }
      final chunk = packet.sublist(spot, spot + howMuch);
      spot += howMuch;
      return chunk;
    }

    final CardAddress where;
    try {
      where = addressRead(take, 'this-is-how-you-look');
    } on CardFormatError {
      return; // unknown address type or truncated -> discard
    }
    if (spot != packet.length) return; // surplus bytes -> discard
    waiting.completed.complete(where);
    // An answer to a packet that expected an answer: the neighbour
    // is confirmed under this address (§11.8, W8).
    onAnswerReceived?.call(from, fromPort);
  }

  /// (3) Knock simultaneously. Sends 0x42 to [target]:[targetPort],
  /// at most [atMostAttempts] times at interval [interval]. If within
  /// this time a 0x42 comes back from the same target,
  /// the route counts as open — immediately, without further attempts. Otherwise
  /// `false` after the last attempt: the caller learns of the failure
  /// and goes to the next step of the ladder (via a neighbour).
  Future<bool> knock(
    InternetAddress target,
    int targetPort, {
    int atMostAttempts = kKnockAtMostAttempts,
    Duration interval = kKnockInterval,
  }) async {
    final key = _addressKey(target, targetPort);
    final attempt = _KnockAttempt();
    _waitingKnockAttempts[key] = attempt;
    final packet = Uint8List.fromList(<int>[kKindKnock]);
    var count = 0;
    void sendAttempt() {
      count++;
      _send(packet, target, targetPort);
      if (count >= atMostAttempts) {
        attempt.timer?.cancel();
        if (!attempt.completed.isCompleted) {
          attempt.completed.complete(false);
        }
      }
    }

    sendAttempt(); // first attempt immediately, not only after a delay
    attempt.timer = Timer.periodic(interval, (_) => sendAttempt());
    try {
      return await attempt.completed.future;
    } finally {
      attempt.timer?.cancel();
      _waitingKnockAttempts.remove(key);
    }
  }

  void _onKnock(InternetAddress from, int fromPort) {
    final key = _addressKey(from, fromPort);
    final attempt = _waitingKnockAttempts[key];
    if (attempt == null) {
      onUnknownKnock?.call(from, fromPort);
      return; // nobody from our side is knocking -> ignore
    }
    attempt.timer?.cancel();
    if (!attempt.completed.isCompleted) {
      attempt.completed.complete(true);
    }
  }

  /// Ends running knock attempts; the [Wire] stays untouched.
  void close() {
    for (final v in _waitingKnockAttempts.values) {
      v.timer?.cancel();
    }
    _waitingRequests.clear();
    _waitingKnockAttempts.clear();
  }
}

/// ONLY FOR THE FIELD PROBE (`bin/outside_probe.dart`). The product path has been
/// `keep_alive.dart` since S391 (§8.1, E1): per address type a filler packet without
/// answer instead of an address question.
///
/// (2) Keep the hole open. Sends a 0x40 every [deadline] to EXACTLY ONE
/// neighbour — the same how-do-I-look request as
/// [OutsideRoute.whatIsMyAddress]; as a side effect the own
/// known address also stays current this way.
///
/// Why exactly one, not several: every additional neighbour would be an
/// additional permanent stream, which the design explicitly forbids
/// (`mycelium/berichte/P2-ablauf.md`: "that is the only permanent traffic that
/// the design knows — and it runs to ONE neighbour, not to all").
/// The one open route suffices: it is the same neighbour that stands as
/// `neighbourAddress` in the own card — only via him is one
/// reachable as long as the public address is worthless because of NAT/CGNAT.
class KeepAliveSender {
  final Timer _timer;
  KeepAliveSender._(this._timer);

  static KeepAliveSender start(
    OutsideRoute outsideRoute,
    InternetAddress neighbour,
    int neighbourPort, {
    Duration deadline = kKeepAliveDeadlineStandard,
  }) {
    final t = Timer.periodic(deadline, (_) {
      unawaited(outsideRoute.whatIsMyAddress(neighbour, neighbourPort));
    });
    return KeepAliveSender._(t);
  }

  void stop() => _timer.cancel();
}
