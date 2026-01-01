/// The broker of a group call in the mesh (§17.7, D-69) — choice and
/// bookkeeping, kept apart from `group_call_manager.dart`.
///
/// ══ THE RULE ═══════════════════════════════════════════════════════
///
/// §17.7: "A media pair — an address pair of §17.3 — exists only between
/// two participants that are contacts with call consent […], and two
/// participants that hold one always use it: in the mesh their media never
/// pass through a third, the caller included. Only for a pair without one
/// — not contacts, or contacts whose address pair does not carry — a
/// participant that holds a media pair with both, the pair's *broker*,
/// forwards between them: one broker per pair, both directions, one hop,
/// and only what it received from the pair's members themselves."
///
/// D-69 (owner, 21.10.2026): a broker only in need — two contacts never
/// through a third, not even through the one who started the call — and
/// the load spread over several brokers where possible.
///
/// ══ WHO DOES WHAT ═══════════════════════════════════════════════════
///
/// Member side (both members of a pair without a media pair):
///   1. ask the own media pairs: `relayAsk` (which of these do you hold a
///      media pair with?) — answered by `relayHave` (whom, and how much
///      room is left);
///   2. the member with the SMALLER identifier binds the candidate with
///      the most free capacity, ties by the §17.7 ranking, then rendezvous
///      hashing over pair and candidate: `relayBind`;
///   3. the broker confirms to both (`relayBound`, with or without video)
///      or refuses to both (`relayRefuse`); after a refusal the binder
///      takes the next candidate.
/// The larger member binds nothing; it waits for the broker's word — an
/// event, not a clock.
///
/// Broker side: answers asks, checks its capacity when it is BOUND (not
/// when it answers), and forwards only what a member of a bound pair sent
/// it itself.
///
/// Every record that expects an answer goes through
/// `CallTransport.requestControl`: the transport repeats it as §11.3a says
/// and reports answered or failed. Nothing here repeats, counts or times.
///
/// ══ WHEN IT IS DECIDED AGAIN ════════════════════════════════════════
///
/// Only at an edge (§17.7: "Joining, leaving, the end of a media pair
/// (§17.4) and a broker's limit are the only edges"): a media pair begins
/// to carry or turns out not to ([setPairState]), a participant leaves
/// ([participantLeft]), a broker refuses or drops, the line shows its limit
/// in the receivers' loss reports ([limitShown], §17.1.1). A binding that
/// carries is not moved; a pair that gains a media pair of its own drops its
/// broker.
///
/// ══ WHAT P6 (THE CRYSTAL FROM 7) TAKES FROM HERE ═════════════════════
///
/// [mediaPairs] — the participants this device holds a carrying media pair
/// with — and [brokeredPairs] — the pairs this device carries as a broker.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/calls/upload_probe.dart';
import 'package:cleona/core/service/service_types.dart' show GroupPeerReach;

/// The media pair with one participant, as far as this device knows.
enum MediaPairState {
  /// Not decided yet: material exchanged or awaited, punch window running.
  pending,

  /// The punch window carried — media run directly (§17.3).
  carrying,

  /// There is none: not a contact with consent on one of the two sides, or
  /// the address pair did not carry.
  none,
}

/// What a broker may still take, from §17.7's fill order: "a broker fills
/// its capacity with its own voice, then forwarded voice, then its own
/// video, then forwarded video".
final class BrokerCapacity {
  const BrokerCapacity({required this.usableBps, required this.sendsVideo});

  /// The upload this node may fill, in bit/s — `null` while no limit is
  /// known (see [fromProbe]).
  final int? usableBps;

  /// Whether this node sends video of its own.
  final bool sendsVideo;

  /// One voice stream on the wire: the 176-B class at 50 frames/s (§17.1).
  static const int voiceStreamBps = 176 * 50 * 8;

  /// One video stream on the wire: a 500-kbit/s tile (§17.7) in the 1200-B
  /// class with 1157 B of payload (§17.1) — the larger of the two tile
  /// rates §17.7 names, so that a broker refuses early rather than drops.
  static const int videoStreamBps = 500000 * 1200 ~/ 1157;

  /// The capacity from the upload probe.
  ///
  /// ── WHY NOT THE OBSERVED UPLOAD ──────────────────────────────────
  ///
  /// `UploadProbe` measures what this node REALLY pushed up — "exclusively
  /// a LOWER BOUND of the capacity" (its file header). Used as a ceiling it
  /// would lock itself: at the start of a call nothing is measured, so no
  /// broker could take a pair, and a broker that takes nothing never
  /// measures more. A limit is therefore only what the line has SHOWN
  /// ([UploadObservation.capacityBitsPerSecond], set by a congestion), of
  /// which [UploadObservation.usableShare] may be filled. Without it there
  /// is no known limit, and the load spreads by what each broker already
  /// carries ([RelayHave.load]).
  static BrokerCapacity fromProbe(UploadObservation o,
      {required bool sendsVideo}) {
    final cap = o.capacityBitsPerSecond;
    return BrokerCapacity(
      usableBps:
          cap == null ? null : (cap * UploadObservation.usableShare).floor(),
      sendsVideo: sendsVideo,
    );
  }
}

/// The ranking byte of `relayHave` (§17.7 "link type … power source"):
/// bits 0–1 network form, bits 2–3 power source.
int rankByte(NetworkForm form, PowerSource power) =>
    (form.index & 0x3) | ((power.index & 0x3) << 2);

/// Wired/WLAN before unknown before cellular (§17.7: "wired/WLAN before
/// cellular"; "not determinable" is neither).
int _linkScore(int rank) => switch (NetworkForm.values[rank & 0x3]) {
      NetworkForm.wired || NetworkForm.wifi => 2,
      NetworkForm.unknown => 1,
      NetworkForm.cellular => 0,
    };

/// Mains before unknown before battery (§17.7: "mains before battery").
int _powerScore(int rank) {
  final i = (rank >> 2) & 0x3;
  if (i >= PowerSource.values.length) return 1;
  return switch (PowerSource.values[i]) {
    PowerSource.mains => 2,
    PowerSource.unknown => 1,
    PowerSource.battery => 0,
  };
}

/// What a candidate said in its last `relayHave`.
final class _Have {
  _Have(this.held, this.pending, this.freeVoice, this.load, this.rank);
  final Set<String> held;

  /// Whom it may yet hold a media pair with — it says so again once known.
  final Set<String> pending;
  final int freeVoice;
  final int load;
  final int rank;

  /// "Most free capacity": the free voice streams where a limit is known;
  /// where none is, the less loaded broker has more room.
  int get room => freeVoice == kRelayNoKnownLimit ? 1000 - load : freeVoice;
}

/// A binding of one of our pairs to its broker.
final class BrokerBinding {
  const BrokerBinding(this.brokerHex, {required this.video});
  final String brokerHex;
  final bool video;
}

/// Choice and bookkeeping of the brokers of one group call.
class GroupCallBroker {
  GroupCallBroker({
    required this.ownHex,
    required this.roster,
    required this.isJoined,
    required this.send,
    required this.request,
    required this.capacity,
    required this.ownRank,
    this.rttOf,
    this.wantVideo,
    this.onBinding,
    this.onChanged,
    this.log,
  });

  final String ownHex;

  /// The sorted participant list every index points into.
  final List<String> Function() roster;
  final bool Function(String hex) isJoined;

  /// A record that answers (no answer expected).
  final void Function(String toHex, ControlRecord record) send;

  /// A record that expects an answer — `CallTransport.requestControl`.
  final void Function(String toHex, ControlRecord record,
      bool Function(ControlRecord) answeredBy, void Function() onFailed) request;

  final BrokerCapacity Function() capacity;
  final int Function() ownRank;

  /// Measured RTT to a participant (§17.1.1), the last tie-break.
  final int? Function(String hex)? rttOf;

  /// Whether this device wants video carried for its pairs.
  final bool Function()? wantVideo;

  /// A pair of ours got ([brokerHex] set) or lost (`null`) its broker —
  /// the receive side binds its admission to it (§17.5).
  final void Function(String peerHex, String? brokerHex)? onBinding;

  /// The display of a participant may have changed.
  final void Function()? onChanged;
  final void Function(String line)? log;

  final Map<String, MediaPairState> _state = <String, MediaPairState>{};

  // ── member side ──
  final Map<String, Set<String>> _askedOf = <String, Set<String>>{};
  final Set<String> _askOpen = <String>{};
  final Set<String> _askFailed = <String>{};
  final Map<String, _Have> _haveOf = <String, _Have>{};
  final Map<String, BrokerBinding> _binding = <String, BrokerBinding>{};
  final Map<String, String> _bindOpen = <String, String>{};
  final Map<String, Set<String>> _refused = <String, Set<String>>{};

  // ── broker side ──
  /// Pairs this device carries: "lo|hi" → video carried.
  final Map<String, bool> _carried = <String, bool>{};

  /// Carried pairs whose binder asked for video.
  final Set<String> _wantsVideo = <String>{};
  final Map<String, Set<String>> _askers = <String, Set<String>>{};

  bool _suspended = false;

  // ── read side ──────────────────────────────────────────────────────

  MediaPairState pairState(String hex) =>
      _state[hex] ?? MediaPairState.pending;

  /// The participants this device holds a carrying media pair with.
  Set<String> get mediaPairs => <String>{
        for (final e in _state.entries)
          if (e.value == MediaPairState.carrying && isJoined(e.key)) e.key,
      };

  /// The pairs this device carries as a broker, each as its two members.
  List<(String, String)> get brokeredPairs => [
        for (final k in _carried.keys) (k.split('|')[0], k.split('|')[1]),
      ];

  /// The broker of our pair with [peerHex], or `null`. Our own frames need
  /// no extra send to it: a broker is a media pair of ours, and every own
  /// frame goes to every media pair anyway; it passes it on.
  BrokerBinding? bindingOf(String peerHex) => _binding[peerHex];

  /// Broker side: whom a frame that [fromHex] sent us ITSELF goes on to —
  /// the other member of every pair we carry for it ("only what it
  /// received from the pair's members themselves").
  List<String> forwardTargets(String fromHex, {required bool video}) {
    if (_suspended) return const <String>[];
    final out = <String>[];
    for (final MapEntry(key: k, value: v) in _carried.entries) {
      if (video && !v) continue;
      final ab = k.split('|');
      if (ab[0] == fromHex) out.add(ab[1]);
      if (ab[1] == fromHex) out.add(ab[0]);
    }
    return out;
  }

  /// How [peerHex] is heard, for the participant's tile (§17.7; the
  /// display does not say through whom, D-69 F-4 = B).
  GroupPeerReach reachOf(String peerHex) {
    if (_suspended || peerHex == ownHex) return GroupPeerReach.direct;
    final s = pairState(peerHex);
    if (s == MediaPairState.carrying) return GroupPeerReach.direct;
    if (s == MediaPairState.pending) return GroupPeerReach.pending;
    final b = _binding[peerHex];
    if (b != null) {
      return b.video || !(wantVideo?.call() ?? false)
          ? GroupPeerReach.brokered
          : GroupPeerReach.voiceOnly;
    }
    if (_bindOpen.containsKey(peerHex) ||
        _askOpen.isNotEmpty ||
        _waitingOn(peerHex) ||
        _state.entries.any((e) =>
            e.key != peerHex &&
            e.value == MediaPairState.pending &&
            isJoined(e.key))) {
      return GroupPeerReach.pending;
    }
    final cands = _candidatesFor(peerHex);
    if (cands.isEmpty) return GroupPeerReach.noCommonContact;
    final refused = _refused[peerHex] ?? const <String>{};
    if (cands.every(refused.contains)) return GroupPeerReach.noFreeForwarding;
    return GroupPeerReach.pending;
  }

  // ── edges ──────────────────────────────────────────────────────────

  /// The media pair with [peerHex] is decided — an edge (§17.7).
  void setPairState(String peerHex, MediaPairState s) {
    if (peerHex == ownHex) return;
    final before = pairState(peerHex);
    if (before == s) return;
    // A carrying pair never falls back to pending; "none" after carrying
    // is the end of the media pair (§17.4).
    if (before == MediaPairState.carrying && s == MediaPairState.pending) {
      return;
    }
    _state[peerHex] = s;
    _log('media pair ${_s(peerHex)}: ${before.name} -> ${s.name}');
    if (s == MediaPairState.carrying) {
      // "a pair that gains a media pair of its own drops its broker".
      final b = _binding.remove(peerHex);
      if (b != null) {
        onBinding?.call(peerHex, null);
        _requestDrop(b.brokerHex, peerHex);
      }
      _bindOpen.remove(peerHex);
    } else if (before == MediaPairState.carrying) {
      _mediaPairEnded(peerHex);
    }
    // Decided either way: whoever asked us about it and heard "not yet"
    // hears the answer now, and we may ask a new media pair.
    _haveAgainFor(peerHex);
    _reconsider();
  }

  /// [peerHex] left the call — an edge (§17.7).
  void participantLeft(String peerHex) {
    final wasPair = pairState(peerHex) == MediaPairState.carrying;
    _state.remove(peerHex);
    if (wasPair) _mediaPairEnded(peerHex);
    if (_binding.remove(peerHex) != null) onBinding?.call(peerHex, null);
    _bindOpen.remove(peerHex);
    _refused.remove(peerHex);
    _askers.remove(peerHex);
    _askedOf.remove(peerHex);
    _askOpen.remove(peerHex);
    _haveOf.remove(peerHex);
    _reconsider();
  }

  /// The call left the mesh for the tree (from 7, §17.7): no broker
  /// forwards any more and no pair is bound — the tree carries.
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    for (final peer in _binding.keys.toList()) {
      onBinding?.call(peer, null);
    }
    _binding.clear();
    _bindOpen.clear();
    _carried.clear();
    _wantsVideo.clear();
    onChanged?.call();
  }

  bool get suspended => _suspended;

  void clear() {
    _state.clear();
    _askedOf.clear();
    _askOpen.clear();
    _askFailed.clear();
    _haveOf.clear();
    _binding.clear();
    _bindOpen.clear();
    _refused.clear();
    _carried.clear();
    _wantsVideo.clear();
    _askers.clear();
  }

  // ── records ────────────────────────────────────────────────────────

  /// A broker record from [fromHex]. Records for another participant list
  /// are dropped (the same rule as the tree records).
  void handle(String fromHex, ControlRecord r) {
    if (_suspended) return;
    final list = roster();
    final hash = rosterHash(list);
    switch (r.type) {
      case ControlRecordType.relayAsk:
        final ask = readRelayAsk(r, list.length);
        if (ask == null || ask.roster != hash) return _drop(fromHex, r);
        _askers[fromHex] = {for (final i in ask.asked) list[i]};
        _sendHave(fromHex);
      case ControlRecordType.relayHave:
        final have = readRelayHave(r, list.length);
        if (have == null || have.roster != hash) return _drop(fromHex, r);
        _haveOf[fromHex] = _Have(
            {for (final i in have.held) list[i]},
            {for (final i in have.pending) list[i]},
            have.freeVoice,
            have.load,
            have.rank);
        _askOpen.remove(fromHex);
        _reconsider();
      case ControlRecordType.relayBind:
        final bind = readRelayBind(r, list.length);
        if (bind == null || bind.roster != hash) return _drop(fromHex, r);
        _onBind(fromHex, list[bind.peer], bind.wantVideo);
      case ControlRecordType.relayRefuse:
      case ControlRecordType.relayBound:
      case ControlRecordType.relayDrop:
        final p = readRelayPair(r, list.length);
        if (p == null || p.roster != hash) return _drop(fromHex, r);
        if (p.ack) return; // ended the request it answers (transport)
        send(fromHex, buildRelayPair(
            type: r.type, roster: hash, a: p.a, b: p.b,
            flags: p.flags | kRelayFlagAck));
        _onPairRecord(fromHex, p.type, list[p.a], list[p.b], p.video);
      case ControlRecordType.treeAssignment:
      case ControlRecordType.treeSubtree:
      case ControlRecordType.rttPing:
      case ControlRecordType.rttPong:
      case ControlRecordType.speechLevel:
      case ControlRecordType.readiness:
      case ControlRecordType.lossReport:
      case ControlRecordType.lifeSign:
      case ControlRecordType.treeOffer:
      case ControlRecordType.treeJoin:
      case ControlRecordType.treeAccept:
        return; // not a broker record
    }
  }

  void _drop(String fromHex, ControlRecord r) => _log(
      '${r.type.name} from ${_s(fromHex)} dropped — not well-formed or for '
      'another participant list');

  // ── member side ────────────────────────────────────────────────────

  Set<String> _candidatesFor(String peerHex) => <String>{
        for (final m in mediaPairs)
          if (m != peerHex && (_haveOf[m]?.held.contains(peerHex) ?? false)) m,
      };

  /// Whether a media pair of ours said it may yet hold one with [peerHex].
  bool _waitingOn(String peerHex) => mediaPairs.any(
      (m) => m != peerHex && (_haveOf[m]?.pending.contains(peerHex) ?? false));

  /// The pairs of ours without a media pair and without a broker.
  List<String> _unserved() => [
        for (final hex in roster())
          if (hex != ownHex &&
              isJoined(hex) &&
              pairState(hex) == MediaPairState.none &&
              !_binding.containsKey(hex))
            hex,
      ];

  void _reconsider() {
    if (_suspended) {
      onChanged?.call();
      return;
    }
    final unserved = _unserved();
    final list = roster();
    final hash = rosterHash(list);
    // 1. Ask every media pair about every unserved participant it has not
    //    been asked about yet — both members ask (§17.7).
    for (final m in mediaPairs) {
      if (_askOpen.contains(m) || _askFailed.contains(m)) continue;
      final already = _askedOf[m] ?? const <String>{};
      final todo = unserved.where((p) => p != m && !already.contains(p));
      if (todo.isEmpty) continue;
      final asked = <String>{...already, ...unserved.where((p) => p != m)};
      _askedOf[m] = asked;
      _askOpen.add(m);
      request(
        m,
        buildRelayAsk(
            roster: hash,
            rosterLength: list.length,
            asked: asked.map(list.indexOf).where((i) => i >= 0)),
        (a) => a.type == ControlRecordType.relayHave,
        () {
          _askOpen.remove(m);
          _askFailed.add(m);
          _log('relayAsk to ${_s(m)} unanswered (§11.3a) — not a candidate');
          _reconsider();
        },
      );
    }
    // 2. Only the member with the smaller identifier binds. The streams of
    //    our own binds that no `relayHave` reflects yet count against their
    //    broker, so that two pairs of ours chosen at one edge spread.
    final pendingOf = <String, int>{};
    for (final b in _bindOpen.values) {
      pendingOf[b] = (pendingOf[b] ?? 0) + 2;
    }
    for (final p in unserved) {
      if (ownHex.compareTo(p) >= 0 || _bindOpen.containsKey(p)) continue;
      // "binds the one with the most free capacity" — of all it asked:
      // while an ask about [p] is open, the first answer is no choice.
      if (_askOpen.any((m) => _askedOf[m]?.contains(p) ?? false)) continue;
      // Nor while one of them may yet hold a media pair with [p]: the
      // participant whose windows started first (the one who started the
      // call) would win every pair only for being first (D-69).
      if (_waitingOn(p)) continue;
      final refused = _refused[p] ?? const <String>{};
      final cands =
          _candidatesFor(p).where((m) => !refused.contains(m)).toList();
      if (cands.isEmpty) continue;
      cands.sort((x, y) => _better(x, y, pendingOf, p));
      _bind(cands.first, p, list, hash);
      pendingOf[cands.first] = (pendingOf[cands.first] ?? 0) + 2;
    }
    onChanged?.call();
  }

  /// Most free capacity, then the §17.7 ranking (link type → power source
  /// → RTT; the upload is the capacity itself), then rendezvous hashing over
  /// the pair and the candidate.
  ///
  /// ── THE LAST STEP (S407-GALOSS, P5-6) ─────────────────────────────────
  ///
  /// Until then it was "the smaller identifier" (build plan A.3.4, not the
  /// norm: §17.7 ends the ranking at "RTT as a tie-break"). Members that
  /// choose in the same tick choose on the same information, and the smaller
  /// identifier is the same broker for all of them — the pairs piled up
  /// (measured: 4/2 in 400 of 400 participant lists, never 3/3).
  /// Rendezvous hashing (highest random weight, Thaler/Ravishankar 1998;
  /// RFC 2991 §4) gives every pair its own order of the candidates, still
  /// deterministic, so simultaneous pairs spread ("relaying is spread over
  /// several participants where possible", D-69).
  int _better(
      String x, String y, Map<String, int> pendingOf, String peerHex) {
    final hx = _haveOf[x]!, hy = _haveOf[y]!;
    var c = (hy.room - (pendingOf[y] ?? 0))
        .compareTo(hx.room - (pendingOf[x] ?? 0));
    if (c != 0) return c;
    c = _linkScore(hy.rank).compareTo(_linkScore(hx.rank));
    if (c != 0) return c;
    c = _powerScore(hy.rank).compareTo(_powerScore(hx.rank));
    if (c != 0) return c;
    final rx = rttOf?.call(x), ry = rttOf?.call(y);
    if (rx != null && ry != null && rx != ry) return rx.compareTo(ry);
    c = _weight(peerHex, y).compareTo(_weight(peerHex, x));
    if (c != 0) return c;
    return x.compareTo(y);
  }

  /// The rendezvous weight of [candidate] for our pair with [peerHex]: the
  /// first 6 bytes of SHA-256 over the pair (smaller identifier first) and
  /// the candidate.
  int _weight(String peerHex, String candidate) {
    final lo = ownHex.compareTo(peerHex) < 0 ? ownHex : peerHex;
    final hi = identical(lo, ownHex) ? peerHex : ownHex;
    final d = SodiumFFI()
        .sha256(Uint8List.fromList(utf8.encode('$lo|$hi|$candidate')));
    var w = 0;
    for (var i = 0; i < 6; i++) {
      w = (w << 8) | d[i];
    }
    return w;
  }

  void _bind(String brokerHex, String peerHex, List<String> list, int hash) {
    final peerIdx = list.indexOf(peerHex);
    final ownIdx = list.indexOf(ownHex);
    if (peerIdx < 0 || ownIdx < 0) return;
    _bindOpen[peerHex] = brokerHex;
    final lo = ownIdx < peerIdx ? ownIdx : peerIdx;
    final hi = ownIdx < peerIdx ? peerIdx : ownIdx;
    _log('binding ${_s(brokerHex)} as broker for ${_s(peerHex)}');
    request(
      brokerHex,
      buildRelayBind(
          roster: hash, peer: peerIdx, wantVideo: wantVideo?.call() ?? false),
      (a) {
        if (a.type != ControlRecordType.relayBound &&
            a.type != ControlRecordType.relayRefuse) {
          return false;
        }
        final p = readRelayPair(a, list.length);
        return p != null && !p.ack && p.a == lo && p.b == hi;
      },
      () {
        if (_bindOpen[peerHex] != brokerHex) return;
        _bindOpen.remove(peerHex);
        (_refused[peerHex] ??= <String>{}).add(brokerHex);
        _log('relayBind to ${_s(brokerHex)} unanswered (§11.3a)');
        _reconsider();
      },
    );
  }

  void _onPairRecord(String fromHex, ControlRecordType type, String a,
      String b, bool video) {
    if (a == ownHex || b == ownHex) {
      final peer = a == ownHex ? b : a;
      switch (type) {
        case ControlRecordType.relayBound:
          if (_bindOpen[peer] == fromHex) _bindOpen.remove(peer);
          final current = _binding[peer];
          if (pairState(peer) == MediaPairState.carrying ||
              (current != null && current.brokerHex != fromHex)) {
            // Stale: the pair has its own media pair, or another broker.
            _requestDrop(fromHex, peer);
            return;
          }
          _binding[peer] = BrokerBinding(fromHex, video: video);
          _log('${_s(fromHex)} carries our pair with ${_s(peer)}'
              '${video ? "" : " — voice only"}');
          onBinding?.call(peer, fromHex);
          onChanged?.call();
        case ControlRecordType.relayRefuse:
          if (_bindOpen[peer] == fromHex) _bindOpen.remove(peer);
          (_refused[peer] ??= <String>{}).add(fromHex);
          _reconsider();
        case ControlRecordType.relayDrop:
          // The broker leaves the pair (its limit, or the other member's
          // media pair with it ended): the pair needs another.
          if (_binding[peer]?.brokerHex == fromHex) {
            _binding.remove(peer);
            onBinding?.call(peer, null);
            _reconsider();
          }
        default:
          return;
      }
      return;
    }
    // Not our pair: a member drops the pair we carry.
    if (type == ControlRecordType.relayDrop &&
        _carried.remove(_key(a, b)) != null) {
      _wantsVideo.remove(_key(a, b));
      _log('pair ${_s(a)}–${_s(b)} released by ${_s(fromHex)}');
      _upgradeVideo();
    }
  }

  void _requestDrop(String toHex, String peerHex) {
    final list = roster();
    final i = list.indexOf(ownHex), j = list.indexOf(peerHex);
    if (i < 0 || j < 0) return;
    _requestPair(toHex, ControlRecordType.relayDrop, i, j, 0, list);
  }

  void _requestPair(String toHex, ControlRecordType type, int a, int b,
      int flags, List<String> list) {
    final hash = rosterHash(list);
    final lo = a < b ? a : b, hi = a < b ? b : a;
    request(
      toHex,
      buildRelayPair(type: type, roster: hash, a: a, b: b, flags: flags),
      (r) {
        if (r.type != type) return false;
        final p = readRelayPair(r, list.length);
        return p != null && p.ack && p.a == lo && p.b == hi;
      },
      () => _log('${type.name} to ${_s(toHex)} unacknowledged (§11.3a)'),
    );
  }

  void _mediaPairEnded(String peerHex) {
    // As a member: every pair this broker carried for us needs another.
    for (final e in _binding.entries.toList()) {
      if (e.value.brokerHex != peerHex) continue;
      _binding.remove(e.key);
      onBinding?.call(e.key, null);
    }
    for (final e in _bindOpen.entries.toList()) {
      if (e.value == peerHex) _bindOpen.remove(e.key);
    }
    _haveOf.remove(peerHex);
    _askedOf.remove(peerHex);
    _askOpen.remove(peerHex);
    // As a broker: the pairs with it end; the other member learns it.
    final list = roster();
    for (final k in _carried.keys.toList()) {
      final ab = k.split('|');
      if (!ab.contains(peerHex)) continue;
      _carried.remove(k);
      _wantsVideo.remove(k);
      final other = ab[0] == peerHex ? ab[1] : ab[0];
      final i = list.indexOf(ab[0]), j = list.indexOf(ab[1]);
      if (i >= 0 && j >= 0 && isJoined(other)) {
        _requestPair(other, ControlRecordType.relayDrop, i, j, 0, list);
      }
    }
    _upgradeVideo();
  }

  // ── broker side ────────────────────────────────────────────────────

  String _key(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  int get _fwdVoice => 2 * _carried.length;
  int get _fwdVideo => 2 * _carried.values.where((v) => v).length;

  /// Free voice and video streams under the fill order of §17.7, with
  /// [extraVoice]/[extraVideo] forwarded streams more.
  ({int voice, int video}) _free(
      {int extraVoice = 0, int extraVideo = 0}) {
    final c = capacity();
    final usable = c.usableBps;
    if (usable == null) {
      return (voice: kRelayNoKnownLimit, video: kRelayNoKnownLimit);
    }
    final own = mediaPairs.length;
    final voiceUsed =
        (own + _fwdVoice + extraVoice) * BrokerCapacity.voiceStreamBps;
    final videoUsed =
        ((c.sendsVideo ? own : 0) + _fwdVideo + extraVideo) *
            BrokerCapacity.videoStreamBps;
    final v = (usable - voiceUsed) ~/ BrokerCapacity.voiceStreamBps;
    final w = (usable - voiceUsed - videoUsed) ~/ BrokerCapacity.videoStreamBps;
    return (voice: v.clamp(0, 254), video: w.clamp(0, 254));
  }

  /// Whether what this broker sends now — own voice, forwarded voice, own
  /// video, forwarded video — exceeds the usable upload (§17.7 fill order).
  bool _videoOverLimit() {
    final c = capacity();
    final usable = c.usableBps;
    if (usable == null) return false;
    final own = mediaPairs.length;
    final used = (own + _fwdVoice) * BrokerCapacity.voiceStreamBps +
        ((c.sendsVideo ? own : 0) + _fwdVideo) * BrokerCapacity.videoStreamBps;
    return used > usable;
  }

  /// The line has shown its limit (§17.1.1 loss reports) — an edge (§17.7:
  /// "a broker's limit [is one of] the only edges at which this is decided
  /// again").
  ///
  /// D-69: "A relay at its upload limit keeps voice and drops video for that
  /// pair, shown in the app". So: forwarded video falls, pair by pair, until
  /// what is sent fits — the last in the fill order goes first; the voice of
  /// every bound pair stays ("a binding that carries is not moved"), and new
  /// pairs meet the lower capacity when they bind. Both members of a pair
  /// that lost its video hear it (`relayBound` without the video flag) and
  /// show "No video … at capacity". Whoever asked us hears our room again.
  ///
  /// The room growing back is NOT an edge: video returns at the next one
  /// (a pair leaves, a member leaves, a media pair ends — [_upgradeVideo]).
  void limitShown() {
    if (_suspended) return;
    final list = roster();
    var dropped = 0;
    for (final k in _carried.keys.toList().reversed) {
      if (!_videoOverLimit()) break;
      if (!_carried[k]!) continue;
      _carried[k] = false;
      dropped++;
      final ab = k.split('|');
      final i = list.indexOf(ab[0]), j = list.indexOf(ab[1]);
      if (i < 0 || j < 0) continue;
      _requestPair(ab[0], ControlRecordType.relayBound, i, j, 0, list);
      _requestPair(ab[1], ControlRecordType.relayBound, i, j, 0, list);
    }
    _log('limit shown — usable ${capacity().usableBps} bit/s, '
        '$dropped forwarded video pair(s) fall to voice');
    if (dropped > 0 || _free().voice != _announcedFree) _haveAgainToAll();
    onChanged?.call();
  }

  /// The free voice streams this broker last told anyone ([_sendHave]).
  int? _announcedFree;

  bool _fitsVoice() {
    final f = _free();
    return f.voice == kRelayNoKnownLimit || f.voice >= 2;
  }

  bool _fitsVideo({required bool newPair}) {
    final f = _free(extraVoice: newPair ? 2 : 0);
    return f.video == kRelayNoKnownLimit || f.video >= 2;
  }

  void _sendHave(String askerHex) {
    final asked = _askers[askerHex];
    if (asked == null) return;
    final list = roster();
    final pairs = mediaPairs;
    final f = _free();
    _announcedFree = f.voice;
    send(
      askerHex,
      buildRelayHave(
        roster: rosterHash(list),
        rosterLength: list.length,
        held: [
          for (final p in asked)
            if (p != askerHex && pairs.contains(p) && list.contains(p))
              list.indexOf(p),
        ],
        // Not decided yet — also when we have not yet learnt that it joined:
        // the asker knows it did, and we decide once we learn it (both are
        // edges that answer again, [_haveAgainFor]).
        pending: [
          for (final p in asked)
            if (p != askerHex &&
                p != ownHex &&
                pairState(p) == MediaPairState.pending &&
                list.contains(p))
              list.indexOf(p),
        ],
        freeVoice: f.voice,
        load: _fwdVoice,
        rank: ownRank(),
      ),
    );
  }

  /// A new media pair with [peerHex]: whoever asked about it hears again.
  void _haveAgainFor(String peerHex) {
    for (final e in _askers.entries) {
      if (e.key != peerHex && e.value.contains(peerHex)) _sendHave(e.key);
    }
  }

  /// Our load changed (a pair bound or released): whoever asked us hears
  /// our room again — the next choice sees it (§17.7: "so that the pairs
  /// spread over the brokers there are").
  void _haveAgainToAll() {
    for (final asker in _askers.keys.toList()) {
      if (isJoined(asker)) _sendHave(asker);
    }
  }

  void _onBind(String binderHex, String peerHex, bool wantVideo) {
    final list = roster();
    final i = list.indexOf(binderHex), j = list.indexOf(peerHex);
    if (i < 0 || j < 0) return;
    final pairs = mediaPairs;
    final key = _key(binderHex, peerHex);
    void both(ControlRecordType type, int flags) {
      _requestPair(binderHex, type, i, j, flags, list);
      _requestPair(peerHex, type, i, j, flags, list);
    }

    if (!pairs.contains(binderHex) ||
        !pairs.contains(peerHex) ||
        binderHex.compareTo(peerHex) >= 0) {
      // Not a pair we hold media pairs with both of, or not bound by its
      // smaller member: refused to the binder only.
      _requestPair(binderHex, ControlRecordType.relayRefuse, i, j, 0, list);
      return;
    }
    final known = _carried[key];
    if (known != null) {
      // Bound again (the confirmation went astray): the same answer.
      both(ControlRecordType.relayBound, known ? kRelayFlagVideo : 0);
      return;
    }
    // "A broker checks its capacity when it is bound and refuses when full."
    if (!_fitsVoice()) {
      _log('pair ${_s(binderHex)}–${_s(peerHex)} refused — no voice left');
      both(ControlRecordType.relayRefuse, 0);
      return;
    }
    final video = wantVideo && _fitsVideo(newPair: true);
    _carried[key] = video;
    if (wantVideo) _wantsVideo.add(key);
    _log('carrying pair ${_s(binderHex)}–${_s(peerHex)}'
        '${video ? " with video" : " — voice only"}');
    both(ControlRecordType.relayBound, video ? kRelayFlagVideo : 0);
    _haveAgainToAll();
    onChanged?.call();
  }

  /// Room freed (a pair left, a member left): a voice-only pair gets its
  /// video back where it now fits — the binding stays where it is — and
  /// whoever asked us hears our room again.
  void _upgradeVideo() {
    final list = roster();
    for (final k in _carried.keys.toList()) {
      if (_carried[k]! || !_wantsVideo.contains(k)) continue;
      if (!_fitsVideo(newPair: false)) continue;
      _carried[k] = true;
      final ab = k.split('|');
      final i = list.indexOf(ab[0]), j = list.indexOf(ab[1]);
      if (i < 0 || j < 0) continue;
      _requestPair(ab[0], ControlRecordType.relayBound, i, j,
          kRelayFlagVideo, list);
      _requestPair(ab[1], ControlRecordType.relayBound, i, j,
          kRelayFlagVideo, list);
    }
    _haveAgainToAll();
  }

  void _log(String line) => log?.call(line);

  static String _s(String hex) =>
      hex.length >= 8 ? hex.substring(0, 8) : hex;
}
