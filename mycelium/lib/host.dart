/// The host — ONE node, ONE port, N mailboxes (V4.2 §4.5.1: one daemon,
/// N identities, one stream). S385, cut F.
///
/// What lies here once: the node with wire, fixed port, neighbourhood,
/// cover stream, ladder and routes, the storage for third parties, the media reception
/// and the ONE state checker. What lies per identity stands in
/// [Mailbox]. Mailboxes can be registered and deregistered at runtime.
///
/// The host makes no decision about an identity. It passes
/// on, according to what the node names: [Inbound.to], the `to`
/// of the amendments, the `to` of a request. If no mailbox is found for it
/// (just deregistered), that is reported and nothing is guessed.
///
/// The call names no identity (call D, S385): a node identifier, new per
/// start. Therefore every mailbox can be deregistered as long as one remains.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart' show SodiumFFI;
import 'package:mycelium/readiness.dart';
import 'package:mycelium/memory.dart' show Memory;
import 'package:mycelium/group_read.dart';
import 'package:mycelium/identity.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_post_box.dart';
import 'package:mycelium/node_invitation.dart';
import 'package:mycelium/node_call.dart';
import 'package:mycelium/node_helpers.dart' show shortFrom, interfacesRead;
import 'package:mycelium/media.dart';
import 'package:mycelium/media_reception.dart';
import 'package:mycelium/message.dart' show Inbound;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_inbound.dart';
import 'package:mycelium/mailbox_outbound.dart';
import 'package:mycelium/mailbox_pair.dart';
import 'package:mycelium/mailbox_start.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/host_outside.dart';
import 'package:mycelium/host_codes.dart';
import 'package:mycelium/host_contact_seats.dart';
import 'package:mycelium/host_memory.dart';
import 'package:mycelium/host_network.dart';

class Host {
  final Node node;
  final HostMemory _memory;
  final void Function(String)? report;
  final Map<String, Mailbox> _mailboxes = {};
  final List<String> _relay;
  Timer? _stateChecker;
  late final OutsideSource _outside;

  /// Neighbourhood, cover stream, board and port mapping, connected (S391).
  late final HostNetwork network;

  /// The most recently triggered run of source 4 (§11.9) — for probes.
  Future<void>? outsideRun;

  /// The dispatch of large payloads. It chooses the lane itself by
  /// size (§9.4); a media object carries no sender, so it belongs
  /// to no mailbox.
  late final MediaSender media;

  Host._(this.node, this._memory, this.report, this._relay);

  int get port => node.port;

  /// The readiness state (V4.2 §22.7.1) — LIVE, not a flag. The
  /// names of the values are the ones that IPC and `waitForReady` carry.
  ReadinessState get readiness => node.readiness.state;

  /// The ONE number "responding neighbours" (owner decision E6).
  int get respondingNeighbours => node.readiness.respondingCount;

  /// Who learns of every change of [readiness] OR [respondingNeighbours]
  /// — synchronously at the edge, also on [stop]. Never on
  /// setting: whoever sets it reads the getters beforehand.
  OnReadiness? onReadiness;

  /// The edge "new neighbour" for the app (S388, §5.5 of the
  /// merge) — called after the host itself has remembered,
  /// re-dispatched and triggered its collection. Once per new
  /// neighbour (call, card address via [neighbourRemember]), never on
  /// setting, never on a clock. The host itself occupies `Node.onNewNeighbours`.
  void Function()? onNewNeighbours;

  /// The registered mailboxes, the first one first.
  List<Mailbox> get mailboxes => List.unmodifiable(_mailboxes.values);

  /// The mailbox of the identity with this address, or `null`.
  Mailbox? mailboxFor(Address a) => _mailboxes[identifierFrom(a)];

  /// Starts the host with its first mailbox.
  ///
  /// [directory] holds what belongs to the DEVICE: `wirt.enc` (port, neighbours)
  /// and `briefkasten.enc` (what this node holds for third parties). The
  /// mailboxes lie where their [MailboxDetails.directory] says.
  static Future<Host> start(
    Directory directory,
    Uint8List key, {
    required MailboxDetails first,
    int port = 0,
    void Function(String)? report,
    /// Once after the first collection attempt with a neighbour — cold-start gate
    /// of the rotation, set BEFORE the start collects.
    void Function()? onFirstCollection,
    /// Configured relays (§11.9) — before those from read cards
    /// ([relayRemember]); a configured neighbour does not exist.
    List<String> relay = const [],
    /// See [Host.onReadiness] — set here BEFORE the start asks.
    OnReadiness? onReadiness,
  }) async {
    final roundsStart = DateTime.now(); // before the first call (source 4)
    await interfacesRead();
    final wg = HostMemory.clearedOpen(directory, key, report: report);
    final (g1, b1) = mailboxPrepare(first, report);

    Host? ref;
    // What arrives while `Node.start` is still waiting for the call
    // has no mailbox yet. It is held and delivered right
    // afterwards — the receipt is already in transit at that point, a
    // discard here would be a confirmed but lost message.
    final early = <Inbound>[];
    // The port is FIXED and survives the restart; one assigned by the operating system
    // would devalue every issued card, every
    // learned way back and every remembered neighbour on every start. A named port
    // wins and is NOT remembered — it is an instruction, not a
    // property of the device.
    var chosen = port != 0 ? port : wg.portSet();
    Node? started;
    for (var attempt = 0; started == null; attempt++) {
      try {
        started = await Node.start(
          postBoxes: [b1],
          port: chosen, devicesCode: wg.devicesCodeSet(),
          // What this node holds FOR OTHERS belongs on disk:
          // otherwise a restart of the holder loses the message of a
          // third party, and nobody notices except the one waiting for it.
          directory: directory,
          key: key,
          report: report ?? (_) {},
          onMessage: (e) => ref == null ? early.add(e) : ref._inbound(e),
          onReaction: (r) => ref?.mailboxFor(r.to)?.onReaction?.call(r),
          onEdit: (b) =>
              ref?.mailboxFor(b.to)?.onEdit?.call(b),
          onReadMark: (l) =>
              ref?.mailboxFor(l.to)?.onReadMark?.call(l),
          // §12.5: the mailbox does not decide — `null` (later). The
          // recontact is answered by `onRecontact` (ES-11, S388), without
          // consuming the invitation. Without a mailbox: reject.
          onRequest: (to, who, origin) =>
              ref?.mailboxFor(to) == null ? false : null,
          // EDGE: a new neighbour can be the route to a contact
          // for whom something is resting — AND it can itself hold something.
          onNewNeighbours: () => ref?._newNeighbour(),
        );
      } on SocketException catch (e) {
        // The remembered port is held by a foreign program. Only
        // then is it redrawn; a named port is never replaced.
        if (port != 0 || attempt >= 3) rethrow;
        chosen = wg.portNewRoll();
        report?.call('Port taken ($e) — new fixed port $chosen');
      }
    }
    // Port and device code belong to the device: save immediately (§8.1).
    if (port == 0 || wg.devicesCodeFresh) wg.save();

    final w = Host._(started, wg, report, List.unmodifiable(relay))
      ..onReadiness = onReadiness;
    w._wireUp();
    w._relaySet();
    w._outside = OutsideSource(started,
        to: wg.outsideSourceOn, roundsStart: roundsStart, directory: directory,
        key: key, neighbourRemember: w.neighbourRemember, report: report);
    w.network = HostNetwork(started, w._outside, wg, w._newNeighbour,
        (l) => w.outsideRun = l, report);
    w.contactSeatsWireUp(); // §5.2 contact seats; §8.1 what the contacts learn
    w._admit(started.main, g1, first);
    ref = w;
    early.forEach(w._inbound);
    w._stateChecker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      for (final p in w._mailboxes.values) {
        p.stateCheck();
      }
    });
    for (final p in w._mailboxes.values) {
      p.giveUpAgain();
    }
    // At start the call is usually not yet answered and there is nothing
    // to collect here; without neighbours the call costs not a single packet.
    w.node.onFirstCollection = onFirstCollection;
    // Source 4 only when query AND call series of this round are through.
    w.outsideRun = w._outside.afterSources(
        Future.wait([w.node.collect(), w.node.callSeriesDone]));
    w.network.staleTry(); // §11.8: source 1, once per edge
    return w;
  }

  /// Registers another mailbox — at runtime, on the same port.
  /// Registering is an edge: what is resting for the new identity is
  /// collected and re-dispatched NOW.
  Mailbox register(MailboxDetails a) {
    final (g, b) = mailboxPrepare(a, report);
    if (_mailboxes.containsKey(identifierFrom(b.address))) {
      throw StateError('this mailbox is already registered');
    }
    final p = _admit(node.register(b), g, a);
    p.giveUpAgain();
    unawaited(node.collect());
    return p;
  }

  /// Deregisters a mailbox. What arrives for its identity afterwards
  /// fits nobody any more and is discarded; its files stay, a
  /// renewed [register] with the same directory brings everything back. The
  /// LAST mailbox stays (`StateError`) — a node needs an
  /// identity.
  void deregister(Mailbox p) {
    node.deregister(p.identity);
    if (_mailboxes.remove(p.ownIdentifier) != null) codesDeregistered();
  }

  /// Saves and shuts down.
  void stop() {
    _stateChecker?.cancel();
    _outside.stop(); // §11.9: only the clock; the own entry stays
    network.stop(); // §8.1: the keep-alive clock
    // Also on stopping, not only at the edge: during the run
    // the neighbourhood may have changed without a NEW neighbour
    // being added (a refreshed address, a displaced one).
    network.save();
    node.stop();
  }

  Mailbox _admit(Identity id, Memory g, MailboxDetails a) {
    final p = Mailbox(this, id, g, a);
    _mailboxes[p.ownIdentifier] = p;
    codesAdmit(p); // §8.1 code and registration, §8.2 day key
    return p;
  }

  /// Enters a neighbour that does not come from the call — the
  /// neighbour address of a card on joining (§11.8 source 3, step 1).
  /// If it is new, that is the same edge as one found by the call.
  void neighbourRemember(List<int> ip, int port) {
    if (neighbourAdd(node, ip, port)) _newNeighbour();
  }

  /// Remembers the relay list of a READ card (§11.9) — restart-proof,
  /// saved immediately, and from now on in the own card behind the
  /// configured ones. No packet.
  void relayRemember(List<String> outCard) {
    if (_memory.relayAdmit(
        outCard.where((r) => !_relay.contains(r)))) {
      _memory.save();
      _relaySet();
    }
  }

  void _relaySet() =>
      node.knownRelay = [..._relay, ..._memory.relaysFromCards];

  /// §11.9: source 4 on or off — by the user, restart-proof. Switching on is
  /// an edge; switching off withdraws the own entry ([move]).
  bool get outsideSourceOn => _outside.to;
  set outsideSourceOn(bool to) {
    if (_outside.to == to) return;
    _memory.outsideSourceOn = to;
    _memory.save();
    outsideRun = _outside.move(to);
  }

  /// Edge: the own public address was learned (§11.9).
  void addressLearned() => outsideRun = _outside.write();

  /// EDGE network change (§11.8, §8.2, §22.7.1) — called from outside when
  /// the platform reports a different connection, a new address or the
  /// return from sleep. mycelium does not detect this by itself;
  /// that would only be possible with a clock.
  ///
  /// All evidence expires IMMEDIATELY (state `searching`), the interfaces
  /// are read anew, then ONE call series and ONE query of the remembered
  /// neighbours, afterwards — only if both delivered nothing — source 4. None
  /// of it repeats. The future ends with the query.
  Future<void> networkChanged() async {
    node.readiness.reset();
    for (final p in List.of(_mailboxes.values)) {
      p.dayKeyDistribute(); // §8.2, edge network change
    }
    _outside.roundStarts();
    await node.networkEnvironmentNewRead();
    network.networkChanged(); // §8.1 measurement anew, §11.8 stale entries
    final row = node.call();
    final fetch = node.collect();
    outsideRun = _outside.afterSources(Future.wait([fetch, row]));
    await fetch;
  }

  /// Re-dispatch for [only] in [p] — the edge "a route has arisen".
  void giveUpAgainFor(Mailbox p, Address only) => p.giveUpAgain(only: only);

  void _inbound(Inbound e) {
    final p = mailboxFor(e.to);
    if (p == null) {
      report?.call('Inbound for no registered identity — discarded');
      return;
    }
    p.inboundAccept(e);
  }

  void _newNeighbour() {
    // Remembering happens IMMEDIATELY, not only on stopping: a crash in between
    // would otherwise cost exactly the source that makes the next start fast.
    network.save();
    for (final p in List.of(_mailboxes.values)) {
      p.giveUpAgain();
    }
    unawaited(node.collect());
    // Triggered AFTER the own collection: whoever asks here (the
    // manifest compartment, S388) lines up in the same queue behind it.
    onNewNeighbours?.call();
  }

  /// A find of the search call (call D): the identity [identifier] is reachable under [where].
  /// It REPLACES the previous route and dispatches what is resting for the
  /// contact; every mailbox that knows the contact gets it (the
  /// find is an observation about the network and does not leave the host).
  /// ONLY with a valid [signature] of the contact over [data] (S388, proposal
  /// C) — otherwise anyone in the segment could set a route; otherwise silently discarded.
  bool _find(
      String identifier, CardAddress where, Uint8List data, Uint8List signature) {
    var accepted = false;
    for (final p in List.of(_mailboxes.values)) {
      final k = p.contactOrNull(identifier);
      if (k == null ||
          !SodiumFFI().verifyEd25519(data, signature, k.address.ed25519Pk)) {
        continue;
      }
      accepted = true;
      p.contactRemember(k.address, ip: where.address, port: where.port);
      report?.call('Search call: ${shortFrom(identifier)} found at $where');
      giveUpAgainFor(p, k.address);
    }
    return accepted;
  }

  void _wireUp() {
    codesWireUp(); // §8.1 own codes, §8.2 daily value (host_codes.dart)
    node.onFind = _find;
    node.readiness.onChange = (z, n) => onReadiness?.call(z, n);
    node.onAccepted =
        (to, who, origin) => mailboxFor(to)?.requestAccepted(who, origin);
    node.onContactRequest =
        (to, a) => mailboxFor(to)?.contactRequestReported(a);
    node.onRecontact = (to, who, origin) =>
        mailboxFor(to)?.requestCheck(who, origin) == true;
    // For an ANSWER (delivery receipt, amendment) the ladder needs
    // a route to the sender. What is asked is the mailbox of the SENDING
    // identity — never a different one (`identity.dart`).
    node.routesTo = (to, from) => mailboxFor(from)?.routesToAddress(to);
    // A group packet does not name its group in plain text — the identifier
    // is inside the seal. It is OFFERED to every group of every mailbox until
    // one accepts it.
    node.groupsReception = (packet) {
      var number = 0;
      for (final p in _mailboxes.values) {
        for (final g in p.groups.values) {
          number++;
          try {
            if (g.receive(packet) != null) return;
          } on Object catch (_) {
            // not for this group — ask the next one
          }
        }
      }
      report?.call('Group packet for none of the $number groups');
    };
    media = MediaSender(
      out: (lane, packet) => report?.call(
          'Media: ${packet.length} B on lane ${lane.name} — '
          'without target; whoever sends passes the route with each shipment'),
    );
    node.mediaReception = MediaReception(
      onObject: (object, identifier, _) => report?.call(
          'media object ${_hex(identifier)} complete (${object.length} B)'),
      onFailure: (identifier, reason) =>
          report?.call('media object ${_hex(identifier)} failed: $reason'),
    );
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
