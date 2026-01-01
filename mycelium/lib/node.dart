import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/outside_route.dart' as aw;
import 'package:mycelium/readiness.dart';
import 'package:mycelium/code_registration.dart' show newDevicesCode;
import 'package:mycelium/device_records.dart' show DeviceRecords;
import 'package:mycelium/post_box_deposit.dart' as deposit;
import 'package:mycelium/wire.dart';
import 'package:mycelium/wire_target.dart' show asAddressKind;
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart';
import 'package:mycelium/node_step_four.dart';
import 'package:mycelium/node_codes.dart';
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node_helpers.dart';
import 'package:mycelium/node_call.dart';
import 'package:mycelium/node_cover.dart';
import 'package:mycelium/node_split.dart';
import 'package:mycelium/node_receipt.dart';
import 'package:mycelium/ladder.dart';
import 'package:mycelium/neighbours.dart' as nb;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/message.dart';
import 'package:mycelium/amendment.dart';
import 'package:mycelium/shell.dart';
import 'package:mycelium/cover_stream.dart' as cover;
import 'package:mycelium/split.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/forward.dart' as wr;

/// The node — the ONE thing that a daemon or a UI creates.
///
/// This file has no logic of its own. It owns the socket and wires up the
/// parts; everything domain-related stands in the modules that it brings
/// together. If a decision is made here that no other module could make, it
/// belongs there. It exists because without it every module stays an
/// island: built, checked, and entered by nothing.
class Node {
  /// All identities of this node — one socket, one port, all
  /// active at the same time. Changed only via [register]/[deregister].
  final List<Identity> identities = [];

  /// The first identity — default for calls without `forField:`. It carries
  /// no call any more (call D: the call names a node identifier without
  /// identity reference) and can be deregistered as long as another one remains.
  Identity get main => identities.first;

  /// Finds the right identity for an incoming packet.
  late final Dispatcher dispatcher = Dispatcher(identities);
  PostBox get me => main.postBox;
  final Wire _wire;
  /// The pairwise shell (§4.2, §5.5 rule 3) — EVERY packet goes through here.
  final Shell _shell;
  late final Splitter _splitter;
  nb.Neighbours? _neighbours;
  /// Step 3 via codes (§8.1, `node_codes.dart`).
  late final CodeRoute codeRoute;
  late final deposit.PostBoxDeposit _deposit;
  late final aw.OutsideRoute _outsideRoute;
  late final Ladder _ladder;

  /// The own address as a neighbour SEES it from outside — `null`
  /// as long as nobody has confirmed it. Nobody enters a guessed one.
  CardAddress? publicAddress;

  /// ALL known routes from the identity [from] to the peer [to] —
  /// THREE addresses, not one (§7.1, §6.3; until S390 exactly one, finding
  /// B-1). Set by the host, whose mailboxes hold the contacts; what is asked
  /// is the mailbox of the SENDING identity, not a shared store
  /// (`identity.dart`). Without routes the post box remains.
  Routes? Function(Address to, Address from)? routesTo;

  /// Receive sides that the host or the update sets — without them
  /// 0x50-0x5F (`host_media.dart`), 0x60/0x61 or 0x70-0x7F silently drop away.
  void Function(Uint8List packet, InternetAddress from, int fromPort)? mediaReception;
  void Function(Uint8List packet)? groupsReception;
  void Function(Uint8List packet, InternetAddress from, int fromPort)? updateReception;

  /// The own code of this DEVICE (§8.1, S392): 16 B, passed by the host from
  /// memory and thus restart-proof. Every registration piece
  /// carries it, and the fixed neighbour keeps its code table by it —
  /// so an address change takes the table entry along instead of locking it until
  /// expiry. Without memory (probes, smokes) it is a
  /// fresh one per run: ONE node is ONE device.
  final Uint8List devicesCode;
  final cover.CoverStream coverStream;

  /// Who waits for a receipt — message identifier (hex) to its shipment.
  final Map<String, Shipment> _shipments = {};
  /// Ends the shipment [hex] without receipt: superseded (N-1a, S398).
  void shipmentEnd(String hex) => _shipments.remove(hex)?.giveUp();
  /// The running shipment of the message [hex] — for its placing (§8.2).
  Shipment? shipmentOf(String hex) => _shipments[hex];

  /// Recipient and identifier of the message that is being built RIGHT NOW. The
  /// message layer calls its send callback synchronously from within [send];
  /// afterwards it is null again. An ANSWER, by contrast, names its
  /// recipient itself and expects no receipt.
  Address? _targetNow;
  Uint8List? _identifierNow;

  /// Remembered ones and what the call finds; cap and displacement: [Neighbourhood] (§11.8).
  final Neighbourhood neighbourhood = Neighbourhood();
  /// How many of them answer — §22.7.1, see `readiness.dart`.
  late final Readiness readiness = Readiness(neighbourhood)..report = report;

  /// The same, in the form the tree reads. READ ONLY.
  List<({InternetAddress address, int port})> get foundNeighbours =>
      neighbourhood.asEntries;

  final void Function(String) report;
  /// Every callback upwards carries the receiving identity —
  /// [Inbound.to], [OnRequest] `to`, the amendments their `to`.
  final void Function(Inbound) onMessage;
  final OnRequest onRequest;
  final void Function(Reaction)? onReaction;
  final void Function(Edit)? onEdit;
  final void Function(ReadMark)? onReadMark;

  Node._(this._wire, this._shell, this.coverStream, this.devicesCode,
      {required this.report,
      required this.onMessage,
      required this.onRequest,
      this.onReaction,
      this.onEdit,
      this.onReadMark});

  int get port => _wire.port;
  WireCounters get wireCounters => _wire.counters; // §25.5, read on looking
  bool linkLive(Neighbour n) => n.addresses.any((a) => stands(a.address, a.port)); // OP-23
  bool stands(InternetAddress a, int port) => _shell.stands(a, port); // a link to this address stands

  /// A socket for the address family of [a]? IPv4 always, IPv6 while the wire has one (§11.1, V1).
  bool speaks(InternetAddress a) =>
      asAddressKind(a).type == InternetAddressType.IPv4 || _wire.hasIpv6;

  /// Creates a node and wires up everything. [postBoxes] must not be
  /// empty: a node without an identity would have nobody to serve.
  static Future<Node> start({
    required List<PostBox> postBoxes,
    int port = 0,
    required void Function(String) report,
    required void Function(Inbound) onMessage,
    void Function(Reaction)? onReaction,
    void Function(Edit)? onEdit,
    void Function(ReadMark)? onReadMark,
    required OnRequest onRequest,
    /// Where what this node holds FOR OTHERS is written (in the app the
    /// device database). If it is missing, it holds only in working memory
    /// — and on restart loses what someone entrusted to it.
    DeviceRecords? records,
    /// Fires when the call has found a NEW neighbour, with its address — one
    /// of the edges at which an unreachable contact becomes reachable.
    void Function(InternetAddress address, int port)? onNewNeighbours,
    /// The own code of this device (§8.1) — see [Node.devicesCode].
    /// If it is missing, one is drawn randomly that survives only this run.
    Uint8List? devicesCode,
  }) async {
    if (postBoxes.isEmpty) {
      throw ArgumentError('a node needs at least one identity');
    }
    final (wire, shell, coverStream) =
        await socketBuild(port: port, report: report);
    final k = Node._(wire, shell, coverStream,
        devicesCode ?? newDevicesCode(),
        report: report,
        onMessage: onMessage,
        onRequest: onRequest,
        onReaction: onReaction,
        onEdit: onEdit,
        onReadMark: onReadMark);
    k._wireUp(records);
    postBoxes.forEach(k.register);
    k._neighbours = await neighbourSearchOpen(k,
        dataPort: wire.port,
        report: report,
        onNewNeighbours: onNewNeighbours);
    k.coverStream.start(); // §5.1: always, as long as the node runs (W3)
    return k;
  }

  /// Admits an identity — at start and at runtime the same path.
  /// Per identity a message layer of its own: the receipts go to
  /// its key, and what it sends carries IT as sender.
  Identity register(PostBox b) {
    final identifier = b.address.identifier;
    if (identities.any((i) => hexFrom(i.identifier) == hexFrom(identifier))) {
      throw StateError('Identity ${hexFrom(identifier).substring(0, 8)} '
          'is already registered');
    }
    // Two ways back: the RECEIPT takes the way its message came (§9.2,
    // `node_receipt.dart`); an AMENDMENT takes an address from the mailbox.
    void receiptBack(Uint8List p, Address to, CardAddress? w) =>
        _viaLadder(p, w, to: to, from: b.address, receipt: true);
    void answer(Uint8List p, Address to, CardAddress? w) =>
        _viaLadder(p, w, to: to, from: b.address);
    late final Identity id;
    final n = Messages(
      me: b,
      send: (p, w) => _viaLadder(p, w, from: b.address),
      back: receiptBack,
      onInbound: (e) {
        if (e.kind == null) id.author[hexFrom(e.identifier)] = (who: e.from, at: e.at);
        onMessage(e);
      },
      onReceipt: (out) => _shipments.remove(hexFrom(out.identifier))?.acknowledged(),
      report: report,
    );
    id = Identity(postBox: b, messages: receiptWays(n)); // §9.2, node_receipt.dart
    id.amendmentsWireUp(answer, report,
        onReaction: onReaction,
        onEdit: onEdit,
        onReadMark: onReadMark);
    identities.add(id);
    return id;
  }

  /// Gives up an identity. What still arrives for it fits nobody any more
  /// and is discarded; its running shipments run out.
  void deregister(Identity i) {
    if (identities.length == 1 && identical(i, main)) {
      throw StateError('the last identity stays — a node needs one');
    }
    if (!identities.remove(i)) return;
    dispatcher.identityForget(i);
  }

  void _wireUp(DeviceRecords? records) {
    neighbourhood.speaks = speaks; // V1: only own address families
    codeRoute = CodeRoute(this);

    _deposit = deposit.PostBoxDeposit(
      send: (p, target) => postBoxSend(_splitter, p, target), // node_split.dart
      records: records,
      onMute: readiness.mute, report: report, // O2: holders named in the log
      onNode: readiness.nodeLearn, // B1: count per node
      nodeIdentifier: nodeIdentifier, // the same as in the call (node_call.dart)
    );

    // `appended` and with the SPLITTER's path, measured: on the wire
    // the splitter is already listening, and a raw 0x40 sent without its 12 B header
    // drops away over there. Fed from the kind dispatch in [_inbound].
    _outsideRoute = aw.OutsideRoute.appended(
        (p, target, targetPort) => _splitter.send(p, target, targetPort));

    _ladder = Ladder(
      direct: (p, destination) =>
          _splitter.send(p, InternetAddress.fromRawAddress(destination.address), destination.port),
      // Under the code of the shipment, via the own fixed neighbour (§8.1).
      viaNeighbour: (p, destination, target) => codeRoute.stepThree(
          p, target.neighbours.isEmpty ? [destination] : target.neighbours, target.code),
      inPostBox: stepFour, // node_step_four.dart (OP-20)
      search: search, // extension in node_call.dart
      speaks: (c) => speaks(InternetAddress.fromRawAddress(c.address)),
      report: report,
    );

    // Above the cover switch, attached to the shell (`node_split.dart`).
    _splitter = nodeSplitter(this, _shell);
  }

  SplitFlow get flow => _splitter.flow; // D-41 flow per hop: counters for §25, read only

  /// Feed in a packet that did not come from the wire — from a probe or
  /// from a neighbour's post box. [from]/[fromPort] is WHERE it
  /// came from: for a collected piece the holder, not the sender.
  /// [underCode]: it came by step 3 (`node_codes.dart`) — see [feedingUnderCode].
  void feed(Uint8List data, InternetAddress from, int fromPort,
      {bool withoutReturnRoute = false, bool underCode = false}) {
    feedingUnderCode = underCode;
    try {
      _inbound(data, from, fromPort, withoutReturnRoute: withoutReturnRoute);
    } finally {
      feedingUnderCode = false;
    }
  }

  /// Whether the packet being fed right now came under an own code. [feed] is synchronous,
  /// so the mark covers exactly that packet — the acknowledgement reads it (§9.2).
  bool feedingUnderCode = false;

  /// The storage — public for `node_post_box.dart`.
  deposit.PostBoxDeposit get postBoxDeposit => _deposit;
  /// The forwarder — public for the same reason as
  /// [postBoxDeposit] and [outsideRoute]: since S390 the kind dispatch stands
  /// in `node_helpers.dart` and needs all three recipients.
  wr.Forwarder get forwarder => codeRoute.forwarder;

  void _inbound(Uint8List data, InternetAddress from, int fromPort,
          {bool withoutReturnRoute = false}) =>
      assign(data, from, fromPort, withoutReturnRoute: withoutReturnRoute);

  /// TWO questions, not one: WHO is the counterpart, and DO I EXPECT a
  /// receipt? Until S384 ONE bit decided over four cases, two of them
  /// wrong. Whoever calls with [to] sends an ANSWER (receipt, amendment):
  /// via the ladder, but without waiting for a receipt itself —
  /// otherwise there would be receipts to receipts. [from] is the SENDING
  /// identity; it travels as sender with the shipment. [receipt]: the
  /// acknowledgement of a message just fed — it takes that message's way
  /// (§9.2, [receiptTarget]).
  Shipment? _viaLadder(Uint8List packet, CardAddress? destination,
      {Address? to, required Address from, bool receipt = false}) {
    final target = to ?? _targetNow;
    final identifier = to != null ? null : _identifierNow;
    if (target == null) {
      if (destination != null) rawSend(packet, destination);
      return null;
    }
    // `destination` is the suggestion for step 1; the other addresses come
    // from the contact. If everything stays empty, the ladder has only the
    // post box — and exactly that is then right (§8.2). The code per pair,
    // direction and day (§8.1); the fixed neighbours from the pair (§9.2)
    // are more current than the card's.
    final three = routesTo?.call(target, from);
    final c = codeRoute.codeFor(target, from);
    final s = _ladder.send(
        packet,
        receipt
            ? receiptTarget(three, destination, c, target.identifier)
            : Target.outDueTo(three, lan: destination, neighbours: c?.neighbours ?? const [],
                code: c?.code, identifier: target.identifier));
    if (identifier != null) {
      _shipments[hexFrom(identifier)] = s;
      if (c != null) codeRoute.shipmentRemember(c.code, s, target, from);
    }
    return s;
  }

  /// An answer via the ladder whose end the caller reports itself —
  /// the acceptance (3) of first contact (ES-6, `node_invitation.dart`).
  Shipment answerViaLadder(Uint8List packet, CardAddress? destination, Address to, Address from) =>
      _viaLadder(packet, destination, to: to, from: from)!;

  /// A finished packet without a ladder — for layers that build their packets
  /// themselves and know their route (groups, media). [foreign]: others'
  /// transmission, bounded per target (§20.2) — the forwarder (§8.1).
  void rawSend(Uint8List packet, CardAddress destination, {bool foreign = false}) =>
      _splitter.send(packet, InternetAddress.fromRawAddress(destination.address),
          destination.port, foreign: foreign);

  /// Whether others' transmission of [bytes] to [a]:[port] is beyond the
  /// bound per target (§20.2) — then the forwarder answers `0x21` (§8.1).
  bool flowRefuses(InternetAddress a, int port, int bytes) => _splitter.refuses(a, port, bytes);

  /// Sends [content] to a contact — raw bytes (`message.dart`). [destination] may be `null`:
  /// §8.2 needs no address of the recipient. [under]: the identifier of a message sent again (§9.3).
  Outbound send(Uint8List content, Address to, CardAddress? destination,
      {Identity? forField, int? kind, Uint8List? under}) {
    final asValue = forField ?? main;
    final identifier = under ?? roll(8);
    _targetNow = to;
    _identifierNow = identifier;
    try {
      final out = asValue.messages.ship(content, to, destination, identifier: identifier, kind: kind);
      // Remember the own message (a pair notice, [kind], has no
      // author): without that `edit` does not know that it is the own one.
      if (kind == null) asValue.author[hexFrom(identifier)] = (who: asValue.postBox.address, at: DateTime.now());
      return out;
    } finally {
      _targetNow = null;
      _identifierNow = null;
    }
  }

  aw.OutsideRoute get outsideRoute => _outsideRoute; // for node_outside.dart

  /// The ladder — public for the same reason as [postBoxDeposit]
  /// and [forwarder]: since S390 FIRST CONTACT also enters it
  /// (`node_join.dart`), and it cannot use [_viaLadder] —
  /// that needs a CONTACT, and exactly that does not exist there yet. The
  /// routes come for it from the card (§15.2), not from the mailbox.
  Ladder get ladder => _ladder;

  Future<void> stop() async {
    readiness.reset();
    coverStream.stop();
    codeRoute.stop();
    _neighbours?.close();
    _deposit.close(); // open conversations and runs end: no timer stays (§20.3)
    // Begun transmissions leave whole first (R-1); then the socket closes.
    if (_splitter.sending) await _splitter.finish();
    _splitter.close();
    _shell.close();
    _wire.close();
  }

  /// Reads the network environment anew and updates the second socket (§11.1).
  /// The edge for it is the network change (`Host.networkChanged`), never a
  /// clock. A phone that drops from Wi-Fi into cellular loses
  /// its IPv6 in the process — or conversely only gets one there.
  Future<void> networkEnvironmentNewRead() async {
    await interfacesRead();
    await _wire.ipv6FollowUp(interfaces);
    neighbourhood.socketsChanged(); // V1: the socket may have come or gone
    await networkKindNewRead(); // cover rate per network type (§5.3, node_cover.dart)
    codeRoute.newRegister(); // registration with the fixed neighbour (§8.1)
  }
}
