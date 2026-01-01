import 'dart:typed_data';

import '../link/data_port.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'package:cleona/core/util/local_addresses.dart';

/// Step 2 of the entry cascade (§11): the way into the network via the local network.
///
/// WHY THIS IS NEEDED. Step 1 is the stored supply — it only helps
/// those who have run before. A freshly installed node knows
/// no one and cannot reach anyone on its own, because the
/// §2.6 handshake requires the static material of the other side. On
/// the same network segment this can be resolved without any infrastructure.
///
/// THE ANNOUNCEMENT DOES NOT CARRY THE POSITION — and that is the deliberate
/// difference from the V3 model, which puts the node ID into the broadcast frame. A
/// broadcast is a STANDING CALL: it repeats, and every device on the network
/// hears it passively. If the position were in it, on a foreign
/// WLAN everyone present would learn permanently which metric position sits here —
/// and exactly from that the relay responsibility is computed (§9.1). The
/// record contains the position anyway; so it comes on COLLECTION, and
/// that is a directed action instead of a standing call. The call only says
/// „here is a node, port X".
///
/// WHY THE RECORD MAY BE TAKEN FROM ANYONE. Since the position is the
/// hash over the static keys and the issuer signs with `E_node`,
/// a record is SELF-CERTIFYING: a substituted
/// address or a substituted key is noticed on checking.
/// Only this makes this step buildable at all — otherwise every
/// eavesdropper in the café WLAN would be an attacker.
///
/// NO SOCKET IN THIS FILE. As everywhere in the delivery layer, the
/// input and output are handed in. That keeps the rules testable without
/// a test needing a network — and in this session it already once caught
/// a bug that a network test would have hidden.
final class LanEntryService {
  /// Identifier of the V4.1 call sequence. Deliberately NOT the V3 „CLEO": the frame there
  /// carries a V3 node ID and is built by V3 modules; whoever
  /// mixes both has two meanings on one port.
  static const List<int> magic = [0x43, 0x4c, 0x45, 0x34]; // "CLE4"

  static const int version = 1;

  static const int opAnnounce = 0x01;
  static const int opRecordRequest = 0x02;
  static const int opRecordResponse = 0x03;

  /// Where in the call the capability byte sits (S373).
  ///
  /// ── WHY THE VERSION BYTE DID NOT HAVE TO MOVE ──────────────────────
  ///
  /// The call is `Uint8List(fixedSize)` and thus padded from byte 10 to 63
  /// with ZEROS — not with randomness. A node of the old state
  /// therefore already sends 0 at this position, and 0 is defined here as
  /// **„says nothing"**. An old call thus claims nothing instead of claiming
  /// something false, and an old receiver does not read the byte at
  /// all. The change is purely additive, in both directions.
  ///
  /// Raising the version byte would have been the more expensive AND the worse
  /// choice: [receive] discards the whole datagram on `data[4] != version`,
  /// so a change would split the segment into two halves
  /// that no longer find each other — and that for a field whose
  /// ABSENCE already carries the right meaning. The version byte
  /// stays reserved for a change that really breaks the parsing;
  /// using it up here would mean spending it on the first case
  /// that does not need it.
  static const int capsOffset = 10;

  /// „I get onto the internet." See `util/uplink_state.dart` — the
  /// claim rests on the outcome of the external rendezvous,
  /// not on a probe of its own.
  static const int capUplink = 0x01;

  /// „I forward." Set when this node runs at least one
  /// session over which a cell can travel on.
  ///
  /// ONLY BOTH BITS TOGETHER are the statement a LAN client
  /// needs: a neighbour with an internet leg that forwards nothing
  /// is of no use to it, and neither is one that forwards but cannot
  /// get out itself.
  static const int capForwards = 0x02;

  /// How long a neighbour's claim is valid.
  ///
  /// Three call intervals. The call repeats every [announceInterval] =
  /// 30 s; whoever is silent three times in a row is gone, and its claim
  /// is no longer a statement about the present. Shorter, a single
  /// lost datagram would already be an outage (multicast is
  /// unreliable, that is its nature); longer, a switched-off
  /// device would draw dialling attempts for minutes.
  static const Duration neighbourCapsFresh = Duration(seconds: 90);

  /// Fixed size of call and request.
  ///
  /// Padded so that the two cannot be told apart by length
  /// and a node does not get a size profile.
  static const int fixedSize = 64;

  /// How often calls are made.
  ///
  /// VERY SPARINGLY, and that is a lesson from S335: there the
  /// discovery produced about 810 probes per second and thereby blocked two
  /// work tracks. One call every 30 seconds is enough — whoever joins
  /// calls by itself, and the counter-call comes immediately.
  static const Duration announceInterval = Duration(seconds: 30);

  /// Sends the call into the segment (broadcast/multicast).
  final void Function(Uint8List data, String host, int port) sendBroadcast;

  /// Sends a directed datagram.
  ///
  /// SEPARATE FROM THE CALL, and that is not cosmetics. The call socket sits on
  /// a fixed port known to everyone; directed answers must come from
  /// a port of their own, ephemeral, otherwise the return path hangs on
  /// the same fixed port. On a machine running two nodes,
  /// with `SO_REUSEPORT` the kernel decides by hash which of the
  /// two sockets gets a unicast — the answer would then land
  /// at the wrong one with probability one half. Re-measured 2026-08-22.
  final void Function(Uint8List data, String host, int port) sendUnicast;

  /// The own record, as it is handed out on request.
  final EntryRecord Function() ownRecord;

  /// Called when checked foreign material arrives.
  final void Function(EntryRecord record) onRecord;

  /// The port on which the calls run.
  final int discoveryPort;

  /// The own data port that the call names.
  final int ownDataPort;

  /// The own entry port: directed requests go there.
  ///
  /// WHY NOT SIMPLY THE CALL PORT. That one is fixed and the same for everyone.
  /// If two nodes run on one machine, a request to that port cannot
  /// be assigned — the kernel hands it by hash to one of the
  /// two. An own ephemeral port per node makes every directed
  /// path unambiguous, in the segment as on a single machine.
  final int ownEntryPort;

  /// Who is heard at all.
  ///
  /// ── THE CALL IS THE OWN SEGMENT, AND ONLY THAT (S372) ───────────────
  ///
  /// Until S372 `startLanEntry` bound the call socket to
  /// `InternetAddress.anyIPv4` — unconditionally reachable from the whole
  /// internet — and `LanEntryService` answered an
  /// `opRecordRequest` from ANY source. Whoever got an answer on 41340
  /// thus knew: a Cleona node sits here. That is the
  /// presence disclosure for which BLE was rejected, only over the
  /// open internet.
  ///
  /// The binding is the first gate (see `lan_entry_wiring.dart`),
  /// this one the second: on no platform can the binding be
  /// restricted reliably, so the rule must not hang on it
  /// alone. Checked STATEMENT instead of proxy: not „which
  /// socket" but „which source address".
  ///
  /// The default test is [isSegmentSource]. It lets NON-globally
  /// routable IPv4 through and nothing else — deliberately not „same /24":
  /// the multicast channel intentionally crosses segment boundaries via IGMP
  /// within a house (measured 25.08.), and these neighbours carry
  /// a different private address. What it reliably excludes is every
  /// publicly routable source — and exactly that is the censor and the
  /// scanner.
  final bool Function(String host) sourceAllowed;

  /// What this node claims about itself in the call (S373).
  ///
  /// HANDED IN, like everything else here: this file knows nothing about the
  /// internet leg and nothing about the node's sessions, and it should
  /// not have to know. `null` means „claims nothing" — the same
  /// as a 0, and that is the right default: whoever builds the call without
  /// this input (every test, every lab program) should not accidentally
  /// announce a relay that does not exist.
  final int Function()? ownCaps;

  /// What the neighbours in the segment claim about themselves — per source address
  /// the last heard claim with its time.
  ///
  /// ── UNAUTHENTICATED, AND THAT IS FINE HERE ──────────────────────────
  ///
  /// The call carries no signature — it deliberately does not even carry the
  /// position (see module header: a standing call with position would be the
  /// disclosure of the metric location to everyone present). The claim
  /// is thus no more than a hint, and it must not be more
  /// either.
  ///
  /// It therefore decides nothing security-relevant: it
  /// influences the ORDER of dialling, not whether a session
  /// comes about — and the §2.6 handshake afterwards authenticates
  /// everything that matters anyway (the record is self-certifying).
  /// Whoever lies here draws a dialling attempt that goes
  /// nowhere, and nothing more. In particular he can NOT become a
  /// relay through it: that is decided by the responsibility computation (§9.1),
  /// and it does not know this claim.
  final Map<String, ({int caps, DateTime seen})> neighbourCaps =
      <String, ({int caps, DateTime seen})>{};

  /// Neighbours that claim an internet leg AND forwarding and whose
  /// claim is fresh ([neighbourCapsFresh]) — the relay candidates
  /// of a LAN client without an internet leg of its own.
  List<String> get uplinkNeighbours {
    final now = DateTime.now();
    const necessary = capUplink | capForwards;
    return <String>[
      for (final e in neighbourCaps.entries)
        if ((e.value.caps & necessary) == necessary &&
            now.difference(e.value.seen) <= neighbourCapsFresh)
          e.key
    ];
  }

  /// How many datagrams were discarded because the source is not in the
  /// local network. Counted and not concealed (E-83).
  int droppedForeignSource = 0;

  /// Endpoints whose record has already been requested. Prevents
  /// every repeated call from triggering a new request — the call repeats
  /// on purpose, after all.
  /// Whom we have already asked — WITH time, not just „whether".
  ///
  /// ── THE FINDING, MEASURED ON 09.09.2026 (S378) ──────────────────────
  ///
  /// Here stood a `Set<String>`: every neighbour was asked EXACTLY
  /// ONCE, and only [forgetAsked] emptied the set — that is meant for
  /// the NETWORK CHANGE, not for a missing answer.
  ///
  /// UDP loses. If the request or the answer got lost — most
  /// likely at start, when both sides come up at the same
  /// time —, then this neighbour was NEVER ASKED AGAIN. The
  /// node kept hearing it call every 30 s and still did not learn
  /// it.
  ///
  /// Measured on cleona1/cleona2: multicast demonstrably delivered in both
  /// directions (4 calls each in 45 s), `sourceAllowed` lets both through —
  /// and still only ONE session partner each. `ready` (>= 2 independent
  /// relays, §22.7.1) thus stayed unreachable, and everything
  /// else up to the QR code depended on it.
  ///
  /// Now the time of the last question is stored in it. After
  /// [fragAgainAfter] asking again is allowed — ONCE per call cycle,
  /// not faster: the neighbour calls every [announceInterval], and only
  /// then does [_ask] come by again at all. That is not polling
  /// (work rule 5) but a retry path for a lost
  /// handshake.
  final Map<String, DateTime> _asked = <String, DateTime>{};

  /// Period after which an unanswered neighbour is asked again.
  ///
  /// 90 s = three call cycles. Shorter would be traffic without gain (the
  /// answer may still be in transit); longer would leave the cold start
  /// hanging needlessly: after three missing answers the packet is
  /// lost and not slow.
  static const Duration fragAgainAfter = Duration(seconds: 90);

  /// How many answers per sender have already gone out in this period.
  final Map<String, int> _served = <String, int>{};

  /// Maximum number of answers per sender between two [resetRateLimit].
  static const int maxAnswersPerPeer = 4;

  int dropped = 0;

  /// Diagnostic callback, `null` = silent.
  ///
  /// ── WHY THIS LAYER HAS TO SPEAK AT ALL (S378) ──────────────────────
  ///
  /// Until 09.09.2026 this file had NOT A SINGLE log line. Whether the
  /// node calls, whether calls arrive, whether it asks, whether it learns or
  /// discards — none of that was in the log. On 09.09. the
  /// socket, the multicast table and a probe of its own had to be queried
  /// just to establish THAT the service runs; the actual
  /// finding (see [_ask]) was afterwards only reachable by reading
  /// code.
  ///
  /// For the layer that is supposed to carry the cold start without a boost, that
  /// is too little. The owner decided on 09.09.: logging in,
  /// **especially in the beta channel**; in the live version it may be dropped
  /// later. Hence a callback instead of a fixed `CLogger`: this
  /// file stays without dependency, and whoever wires it decides
  /// on the volume.
  final void Function(String line)? diag;

  LanEntryService({
    required this.sendBroadcast,
    required this.sendUnicast,
    required this.ownRecord,
    required this.onRecord,
    required this.ownDataPort,
    required this.ownEntryPort,
    this.discoveryPort = kLanEntryPort,
    this.ownCaps,
    this.diag,
    bool Function(String host)? sourceAllowed,
  }) : sourceAllowed = sourceAllowed ?? isSegmentSource;

  /// Builds the call:
  /// `magic(4) ‖ ver(1) ‖ op(1) ‖ dataport(2) ‖ entryport(2) ‖`
  /// `capabilities(1) ‖ padding`.
  ///
  /// The capability byte sits in the former padding and does not change
  /// the size — [fixedSize] stays, and with it the fact that
  /// call and request cannot be told apart by length. Why
  /// no version change was needed for it is explained at [capsOffset].
  Uint8List buildAnnounce() {
    final out = Uint8List(fixedSize);
    out.setRange(0, 4, magic);
    out[4] = version;
    out[5] = opAnnounce;
    out[6] = (ownDataPort >> 8) & 0xff;
    out[7] = ownDataPort & 0xff;
    out[8] = (ownEntryPort >> 8) & 0xff;
    out[9] = ownEntryPort & 0xff;
    out[capsOffset] = (ownCaps?.call() ?? 0) & 0xff;
    return out;
  }

  /// Builds the request for the record.
  Uint8List buildRecordRequest() {
    final out = Uint8List(fixedSize);
    out.setRange(0, 4, magic);
    out[4] = version;
    out[5] = opRecordRequest;
    return out;
  }

  /// Builds the answer: `magic(4) ‖ ver(1) ‖ op(1) ‖ length(2) ‖ record`.
  Uint8List buildRecordResponse(EntryRecord r) {
    final enc = r.encode();
    final out = Uint8List(8 + enc.length);
    out.setRange(0, 4, magic);
    out[4] = version;
    out[5] = opRecordResponse;
    out[6] = (enc.length >> 8) & 0xff;
    out[7] = enc.length & 0xff;
    out.setRange(8, out.length, enc);
    return out;
  }

  /// Calls into the local network. [targets] are broadcast and multicast addresses.
  void announce(List<String> targets) {
    final call = buildAnnounce();
    for (final z in targets) {
      sendBroadcast(call, z, discoveryPort);
    }
  }

  /// Accepts a datagram.
  ///
  /// Everything unfitting is silently discarded and counted (E-83) — on an
  /// open port every bit of nonsense the network otherwise carries arrives.
  void receive(Uint8List data, String fromHost, int fromPort) {
    // THE SOURCE FIRST, BEFORE ANY INTERPRETATION. An answer to a
    // public address would be the disclosure; a discard before it costs
    // one comparison.
    if (!sourceAllowed(fromHost)) {
      droppedForeignSource++;
      diag?.call('LAN: call from $fromHost discarded — no segment source');
      return;
    }
    if (data.length < 6 || data.length > 4096) {
      dropped++;
      return;
    }
    for (var i = 0; i < 4; i++) {
      if (data[i] != magic[i]) {
        dropped++;
        return;
      }
    }
    if (data[4] != version) {
      dropped++;
      return;
    }
    switch (data[5]) {
      case opAnnounce:
        if (data.length != fixedSize) {
          dropped++;
          return;
        }
        final dataPort = (data[6] << 8) | data[7];
        final entryPort = (data[8] << 8) | data[9];
        if (dataPort < 1 || entryPort < 1 || entryPort > 65535) {
          dropped++;
          return;
        }
        // Remember the neighbour's claim (S373). A call of the old
        // state carries 0 here and thus claims nothing — see
        // [capsOffset]. Overwritten instead of collected: what counts is what it
        // said LAST; a device that loses its internet leg
        // should not keep claiming it until the period expires.
        neighbourCaps[fromHost] =
            (caps: data[capsOffset], seen: DateTime.now());
        diag?.call('LAN: call from $fromHost heard '
            '(data port $dataPort, entry port $entryPort, '
            'caps 0x${data[capsOffset].toRadixString(16)})');
        _ask(fromHost, entryPort);
      case opRecordRequest:
        if (data.length != fixedSize) {
          dropped++;
          return;
        }
        // Answers are capped. The own record is public,
        // but a sender that asks in a loop should not be served in
        // a loop.
        final n = _served[fromHost] ?? 0;
        if (n >= maxAnswersPerPeer) {
          dropped++;
          return;
        }
        _served[fromHost] = n + 1;
        sendUnicast(buildRecordResponse(ownRecord()), fromHost, fromPort);
      case opRecordResponse:
        if (data.length < 8) {
          dropped++;
          return;
        }
        final len = (data[6] << 8) | data[7];
        if (len <= 0 || 8 + len > data.length) {
          dropped++;
          return;
        }
        final read = EntryRecord.decodeAt(
            Uint8List.sublistView(data, 8, 8 + len), 0);
        if (read == null) {
          // Position does not match the keys, or the signature
          // does not hold. Exactly here a lie is noticed.
          dropped++;
          return;
        }
        diag?.call('LAN: record read from $fromHost — passed on to the '
            'entry store');
        onRecord(read.record);
      default:
        dropped++;
    }
  }

  void _ask(String host, int port) {
    final k = '$host:$port';
    final last = _asked[k];
    if (last != null &&
        DateTime.now().difference(last) < fragAgainAfter) {
      // EXACTLY HERE the cold start ends when a packet gets lost:
      // every neighbour is asked ONCE, and `_gefragt` is only emptied by
      // `forgetAsked()` — that is meant for the NETWORK CHANGE, not
      // for a missing answer. UDP loses; the answer then never comes,
      // and still no one ever asks again.
      //
      // Measured on 09.09.2026: two nodes in the same segment, multicast
      // demonstrably delivered in both directions (4 calls each in 45 s), and
      // still only ONE session partner each. The fix is a separate
      // proposal; this line at least makes the state visible.
      diag?.call('LAN: $host:$port asked '
          '${DateTime.now().difference(last).inSeconds}s ago — '
          'period ${fragAgainAfter.inSeconds}s not yet over');
      return;
    }
    final again = last != null;
    _asked[k] = DateTime.now();
    diag?.call(again
        ? 'LAN: asking $host:$port AGAIN (no answer within '
            '${fragAgainAfter.inSeconds}s — lost packet)'
        : 'LAN: asking $host:$port for its entry record');
    sendUnicast(buildRecordRequest(), host, port);
  }

  /// Releases the caps again. The caller calls this in the call cycle.
  void resetRateLimit() {
    _served.clear();
  }

  /// Forgets whom one has already asked — needed when the network
  /// changes and the same addresses may belong to someone else.
  void forgetAsked() {
    _asked.clear();
    // AND THE CLAIMS. They hang on a SOURCE ADDRESS, and after
    // a network change the same address may belong to someone
    // else — a relay hint for `192.168.1.44` from the old network
    // would point to a stranger in the new one. For the same reason for which
    // `_gefragt` is emptied here.
    neighbourCaps.clear();
  }
}

/// Port of the V4.1 call sequence.
///
/// Own port, not the V3 41338: there a different meaning of
/// the same byte lives, and two meanings on one port are a
/// source of errors without benefit.
///
/// **SINCE 2026-09-08 (S376) THE VALUE LIVES IN `link/data_port.dart`.** It
/// is needed in two places: here, where it is bound, and in the
/// port draw, which must exclude it. The literal stood only here,
/// so the draw excluded the wrong port (41338, the V3 port,
/// which no one binds on this line any more) — a node could draw 41340
/// and thereby bound data port and entry listener to the same
/// port. This line is not a second definition but the name under
/// which the delivery layer reads the one value.
const int kLanEntryPort = DataPort.lanEntryPort;

/// The multicast group of the call (IPv4).
///
/// WHY NOT ONLY BROADCAST. `255.255.255.255` is the *limited*
/// broadcast — no router forwards it, and even the transition
/// between two bridges of the same /24 does not carry it. Measured on
/// 25.08.: two nodes on the same bridge found each other immediately, two
/// more nodes in the same /24 but behind a transition stayed
/// invisible — while the V3 layer saw them within two minutes.
/// The difference was the channel alone.
///
/// WHY THE SAME GROUP AS V3. `lan_discovery.dart:29` uses
/// `239.192.67.76` and records in the comment: „cross-subnet, requires
/// IGMP". In this network that is demonstrably the case — the group is
/// forwarded. A group of our own would be more cleanly separated but would have
/// to prove its deliverability first; here what counts is what measures.
/// Nothing can collide: the call lives on [kLanEntryPort], V3 on
/// its own. Channel separation is operational anyway and not a
/// security boundary (§11).
const String kLanEntryMulticastV4 = '239.192.67.76';

/// Reach of the call in hops. Four, as in V3 — enough for a house with
/// several segments, too little to run into the provider's network.
const int kLanEntryMulticastHops = 4;


/// Is this source address in the local network — i.e. NOT in the public
/// internet?
///
/// The call is step 2 of the cascade and thus by definition the own
/// network (§11.1 „The local network"). Everything that comes from a globally routable
/// address does not belong to it, and step 3 has run since S372 over
/// the data port (`entry_portal.dart`), no longer here.
///
/// WHAT IS LET THROUGH: RFC 1918 private ranges, link-local
/// (169.254/16), CGNAT (100.64/10), the DS-Lite CLAT addresses
/// (192.0.0.0/29) and loopback. The middle three are in
/// [isUndialableIpv4] — no one under them can be DIALLED from there, which
/// says nothing about whether someone may CALL from there; a guest WLAN with
/// CGNAT is a completely ordinary segment.
///
/// IPv6: the call is IPv4-only today (`vorratUnicastTargets` filters
/// for that reason, `lan_entry_wiring` binds IPv4 sockets). Should an
/// IPv6 source come, link-local (`fe80::`) and ULA (`fc00::/7`) would be the
/// local ones — both are covered here so that the test does not silently do
/// the wrong thing with a later IPv6 call.
bool isSegmentSource(String host) {
  final h = host.split('%').first.toLowerCase();
  if (h.isEmpty) return false;
  if (h.contains(':')) {
    if (h == '::1') return true;
    if (h.startsWith('fe80:')) return true;
    if (h.startsWith('fc') || h.startsWith('fd')) return true;
    return false;
  }
  if (h.startsWith('127.')) return true;
  if (isPrivateIpv4(h)) return true;
  if (isUndialableIpv4(h)) return true;
  return false;
}
