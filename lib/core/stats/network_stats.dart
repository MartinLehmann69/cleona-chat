import 'dart:io';

/// A set of snapshots of the V4.1 node (§25.4/§25.5).
///
/// ── WHY ONE SET AND NOT TWENTY PARAMETERS ───────────────────────────
///
/// These twenty numbers all arise at the same place (the node), at the
/// same time (when someone looks) and with the same reading
/// (state, not increment). Read as a set they cannot
/// diverge; passed through individually each of them would be an
/// opportunity to forget one — and a forgotten number then stands
/// at 0 and looks like a measurement.
///
/// ── WHY IT IS A RECORD AND NOT A CLASS ──────────────────────────────
///
/// Records in Dart are STRUCTURAL. `attachV41` (`lib/core/tagline/`)
/// can build this set without importing this file — and exactly
/// that is the constraint: the delivery layer gets no import edge
/// onto the display layer. The same reasoning as for the bare
/// callbacks on `V41Node.start`, and `smoke_link_io_milestone`
/// (section 5) guards it.
typedef V41NodeGauges = ({
  // ── Connection ────────────────────────────────────────────────────
  /// Known entry records (`EntryCache.size`).
  int entryRecords,

  // ── Delivery ──────────────────────────────────────────────────────
  /// Cover ticks that were sent (`SlotDriver.slotsEmitted`).
  int slotsEmitted,

  /// Ticks that elapsed without anything being sent.
  int slotsSkipped,

  /// Ticks that failed on an error. > 0 is a finding.
  int slotsFailed,

  /// Harvest runs since node start (`V41Node.harvestRuns`).
  int harvestRuns,

  /// Responsibility lookups since node start (`V41Node.lookupRuns`).
  int lookupRuns,

  /// Fully assembled payloads.
  int payloadsAssembled,

  /// Of which those that a sink could open.
  int payloadsOpened,

  /// Transfers that still lack pieces.
  int openTransfers,

  /// Pieces the assemblers have thrown away.
  int piecesDiscarded,

  // ── Disturbances ──────────────────────────────────────────────────
  /// Waiting control frames in the cover stream.
  int controlQueueDepth,

  /// The highest level ever reached by the same queue.
  int controlQueueMax,

  /// Control frames that the cap discarded.
  int droppedControl,

  /// Ephemeral frames (typing indicators) that were discarded.
  int droppedEphemeral,

  /// Control frames that the delivery layer could not process.
  int controlFailures,

  // ── Contribution for others ───────────────────────────────────────
  /// Foreign cells this node currently keeps.
  int storedCells,

  /// Kept cells that were displaced under quota pressure (§21.3.3).
  int storedEvicted,

  /// Blind placements this node holds for a closer neighbour.
  int blindHeld,

  /// Blind deposits that were displaced under total pressure (§21.3.3).
  int blindEvicted,

  /// Blind placements rejected at a partial quota.
  int blindRefused,
});

/// The zero set — as long as no node is attached.
///
/// NO DUMMY. Without a node there is no cover tick, no harvest and
/// no placement; `0` is the truth here and not a substitute value.
const V41NodeGauges kNoNodeGauges = (
  entryRecords: 0,
  slotsEmitted: 0,
  slotsSkipped: 0,
  slotsFailed: 0,
  harvestRuns: 0,
  lookupRuns: 0,
  payloadsAssembled: 0,
  payloadsOpened: 0,
  openTransfers: 0,
  piecesDiscarded: 0,
  controlQueueDepth: 0,
  controlQueueMax: 0,
  droppedControl: 0,
  droppedEphemeral: 0,
  controlFailures: 0,
  storedCells: 0,
  storedEvicted: 0,
  blindHeld: 0,
  blindEvicted: 0,
  blindRefused: 0,
);

/// The IPC keys that once existed and that must NOT BE REUSED.
///
/// ── WHAT THIS LIST IS FOR ───────────────────────────────────────────
///
/// `toJson`/`fromJson` cross the boundary between two separately
/// SHIPPED artefacts (GUI and daemon). A dropped key
/// is harmless: an old GUI reads it with its default value and shows
/// 0 — exactly what it showed since the CUT anyway, because the writer
/// was gone.
///
/// REUSE IS DANGEROUS. If a future field again carries the name
/// `directConnections`, but a different meaning, then
/// an old GUI reads the new number as the old one — and shows a
/// measurement that measures something other than its label says. That
/// cannot be noticed by reading, because both sides are consistent
/// on their own.
///
/// `smoke_network_stats` checks that none of these names reappears in `toJson`.
const List<String> kRetiredStatsJsonKeys = <String>[
  'activePeerCount',
  'totalKnownPeers',
  'idPowVerifiedPeers',
  'idPowNoncePeers',
  'idSelfVerifyOk',
  'idSelfVerifyMiss',
  'poolDropsRate',
  'poolDropsRelay',
  'natType',
  'publicIp',
  'publicPort',
  'dhtMaintenanceBytes',
  'fragmentsStored',
  'storageUsedBytes',
  'directConnections',
  'relayBytes',
  'routingTableSize',
  'avgLatencyMs',
  'minLatencyMs',
  'maxLatencyMs',
  'peerLatencies',
  'kBucketStats',
  'upnpStatus',
  'pcpStatus',
  'upnpRouterInfo',
];

/// The network statistics as the UI shows them.
///
/// ── WHAT DISAPPEARED ON 01.09.2026 (S360) AND WHY ───────────────────
///
/// Until here this was a V3 DATA STRUCTURE with a V4.1 node
/// behind it: of 36 fields six had a productive writer,
/// four more came with S357/S360, and the remaining 26 stood
/// permanently at their default value. They stood there not because something
/// was broken, but because their SOURCES were deleted with the CUT of 31.08.
/// — Kademlia ring, distance-vector table, NAT traversal,
/// Reed-Solomon fragment store, 2D DHT auth manifest.
///
/// The owner on 01.09.: "Remove everything that delivers numbers about V 3 and
/// replace it with correspondingly meaningful information about v4."
///
/// A ZERO THAT LOOKS LIKE A MEASUREMENT IS WORSE THAN A
/// MISSING NUMBER. Therefore the fields were not left at 0,
/// but removed; and what takes their place has a named
/// writer in the delivery layer (see [V41NodeGauges]).
///
/// The structure now follows the three questions of a user — "am I
/// connected", "does my mail arrive", "what is the cause if not" — and
/// no longer the order in which four V3 components delivered their numbers.
/// Design: `docs/v4-redesign/S360-netzstatistik-v41.md`.
class NetworkStats {
  // ── Section 1: Connection ──────────────────────────────────────────
  final Duration uptime;
  final bool isRunning;

  /// Known entry records (§11). If it is at 0, the
  /// entry cascade has nothing to start with.
  final int entryRecords;

  // ── Section 2: Delivery ────────────────────────────────────────────
  final int slotsEmitted;
  final int slotsSkipped;
  final int slotsFailed;
  final int harvestRuns;
  final int lookupRuns;
  final int payloadsAssembled;
  final int payloadsOpened;
  final int openTransfers;
  final int piecesDiscarded;

  // ── Section 3: Faults ──────────────────────────────────────────────
  final int controlQueueDepth;
  final int controlQueueMax;
  final int droppedControl;
  final int droppedEphemeral;
  final int controlFailures;

  // ── Section 4: Data usage ──────────────────────────────────────────
  final int bytesSentTotal;
  final int bytesReceivedTotal;
  final int bytesSentToday;
  final int bytesReceivedToday;
  final int messagesSent;
  final int messagesReceived;

  // ── Section 5: contribution for others ─────────────────────────────
  final int messagesRelayed;
  final int relayDataVolume;

  /// Foreign cells this node currently keeps for others.
  /// The V4.1 counterpart of `fragmentsStored` (Reed-Solomon, dropped).
  final int storedCells;
  final int storedEvicted;
  final int blindHeld;
  final int blindEvicted;
  final int blindRefused;

  final int dbSizeBytes;

  const NetworkStats({
    this.uptime = Duration.zero,
    this.isRunning = false,
    this.entryRecords = 0,
    this.slotsEmitted = 0,
    this.slotsSkipped = 0,
    this.slotsFailed = 0,
    this.harvestRuns = 0,
    this.lookupRuns = 0,
    this.payloadsAssembled = 0,
    this.payloadsOpened = 0,
    this.openTransfers = 0,
    this.piecesDiscarded = 0,
    this.controlQueueDepth = 0,
    this.controlQueueMax = 0,
    this.droppedControl = 0,
    this.droppedEphemeral = 0,
    this.controlFailures = 0,
    this.bytesSentTotal = 0,
    this.bytesReceivedTotal = 0,
    this.bytesSentToday = 0,
    this.bytesReceivedToday = 0,
    this.messagesSent = 0,
    this.messagesReceived = 0,
    this.messagesRelayed = 0,
    this.relayDataVolume = 0,
    this.storedCells = 0,
    this.storedEvicted = 0,
    this.blindHeld = 0,
    this.blindEvicted = 0,
    this.blindRefused = 0,
    this.dbSizeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
        'uptimeSeconds': uptime.inSeconds,
        'isRunning': isRunning,
        'entryRecords': entryRecords,
        'slotsEmitted': slotsEmitted,
        'slotsSkipped': slotsSkipped,
        'slotsFailed': slotsFailed,
        'harvestRuns': harvestRuns,
        'lookupRuns': lookupRuns,
        'payloadsAssembled': payloadsAssembled,
        'payloadsOpened': payloadsOpened,
        'openTransfers': openTransfers,
        'piecesDiscarded': piecesDiscarded,
        'controlQueueDepth': controlQueueDepth,
        'controlQueueMax': controlQueueMax,
        'droppedControl': droppedControl,
        'droppedEphemeral': droppedEphemeral,
        'controlFailures': controlFailures,
        'bytesSentTotal': bytesSentTotal,
        'bytesReceivedTotal': bytesReceivedTotal,
        'bytesSentToday': bytesSentToday,
        'bytesReceivedToday': bytesReceivedToday,
        'messagesSent': messagesSent,
        'messagesReceived': messagesReceived,
        'messagesRelayed': messagesRelayed,
        'relayDataVolume': relayDataVolume,
        'storedCells': storedCells,
        'storedEvicted': storedEvicted,
        'blindHeld': blindHeld,
        'blindEvicted': blindEvicted,
        'blindRefused': blindRefused,
        'dbSizeBytes': dbSizeBytes,
      };

  /// ── WHY EVERY FIELD HAS A DEFAULT VALUE AND THERE IS NO VERSION
  ///    FIELD ───────────────────────────────────────────────────────────
  ///
  /// GUI and daemon are separately shipped artefacts. Both
  /// mixed cases are covered here, and without anyone having to
  /// compare a version:
  ///
  /// * **Old GUI, new daemon** — the dropped keys are missing; the
  ///   old `fromJson` reads them with `?? 0` and shows 0. That is exactly
  ///   what it showed since the CUT anyway.
  /// * **New GUI, old daemon** — the new keys are missing; this
  ///   `fromJson` reads them with `?? 0`. A 0 for "sent ticks" is
  ///   the state that a stalled node would also have; a version field
  ///   would not make the number better, but only allow an
  ///   error message, for which the mandatory update path (§8.2/T11)
  ///   already provides a carrier of its own.
  ///
  /// Both halves moreover come from the SAME release
  /// (`release-build.sh` builds them from one tree). The mixed case is a
  /// half-applied update, not a permanent state.
  ///
  /// What follows from this is at [kRetiredStatsJsonKeys]: the dropped
  /// NAMES are burnt.
  static NetworkStats fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.toInt() ?? 0;
    return NetworkStats(
      uptime: Duration(seconds: i('uptimeSeconds')),
      isRunning: json['isRunning'] as bool? ?? false,
      entryRecords: i('entryRecords'),
      slotsEmitted: i('slotsEmitted'),
      slotsSkipped: i('slotsSkipped'),
      slotsFailed: i('slotsFailed'),
      harvestRuns: i('harvestRuns'),
      lookupRuns: i('lookupRuns'),
      payloadsAssembled: i('payloadsAssembled'),
      payloadsOpened: i('payloadsOpened'),
      openTransfers: i('openTransfers'),
      piecesDiscarded: i('piecesDiscarded'),
      controlQueueDepth: i('controlQueueDepth'),
      controlQueueMax: i('controlQueueMax'),
      droppedControl: i('droppedControl'),
      droppedEphemeral: i('droppedEphemeral'),
      controlFailures: i('controlFailures'),
      bytesSentTotal: i('bytesSentTotal'),
      bytesReceivedTotal: i('bytesReceivedTotal'),
      bytesSentToday: i('bytesSentToday'),
      bytesReceivedToday: i('bytesReceivedToday'),
      messagesSent: i('messagesSent'),
      messagesReceived: i('messagesReceived'),
      messagesRelayed: i('messagesRelayed'),
      relayDataVolume: i('relayDataVolume'),
      storedCells: i('storedCells'),
      storedEvicted: i('storedEvicted'),
      blindHeld: i('blindHeld'),
      blindEvicted: i('blindEvicted'),
      blindRefused: i('blindRefused'),
      dbSizeBytes: i('dbSizeBytes'),
    );
  }
}

/// Collects the numbers of the network statistics.
///
/// TWO KINDS OF NUMBER, TWO TREATMENTS — and the distinction is
/// not a formality:
///
/// * **Booked** (wire bytes, relay bytes, relay cells, messages): the
///   collector keeps two periods, "total" and "today". It therefore gets
///   the DIFFERENCE to the last look, not the absolute value
///   (see [noteNodeCounters]).
/// * **Passed through** (everything in [V41NodeGauges]): states, not
///   increments. "Waiting for pieces" is not a quantity one
///   adds up; a difference calculation would simply be wrong here. They
///   are remembered and handed out unchanged ([noteNodeGauges]).
class NetworkStatsCollector {
  DateTime? _startTime;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _bytesSentToday = 0;
  int _bytesReceivedToday = 0;
  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _relayBytes = 0;
  int _messagesRelayed = 0;
  DateTime? _lastDayReset;

  void markStarted() {
    _startTime = DateTime.now();
    _lastDayReset = DateTime.now();
  }

  Duration get uptime => _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  void addBytesSent(int bytes) {
    _bytesSent += bytes;
    _bytesSentToday += bytes;
  }

  void addBytesReceived(int bytes) {
    _bytesReceived += bytes;
    _bytesReceivedToday += bytes;
  }

  void addMessageSent() => _messagesSent++;
  void addMessageReceived() => _messagesReceived++;
  // `addDhtBytes` REMOVED ON 2026-08-31 (CUT): "DHT maintenance traffic" is
  // a V3 quantity (Kademlia pings, bucket refresh). V4.1 has no
  // Kademlia ring; the base traffic of the tagline is cover traffic (§5) and
  // is booked as wire bytes, not as maintenance. Producers in the tree: zero.
  // On 01.09.2026 (S360) the FIELD `dhtMaintenanceBytes` fell too.

  // ── THE NUMBERS OF THE V4.1 NODE, AS A DIFFERENCE (§25.5) ──────────
  //
  // The node counts itself, at the place of the action (`UdpSocketSet`
  // for the wire, `DeliveryNode` for forwarding). Its numbers
  // run since NODE START and only upward. This collector on the other hand
  // keeps two periods (total and today) and belongs to an
  // IDENTITY, while the node belongs to the process.
  //
  // WHY DIFFERENCE AND NOT TAKEOVER. If the absolute value were
  // set here, "today" would equal "total" — on a daemon that runs for weeks,
  // a number that looks like a daily measurement and is none.
  // The difference since the last look, by contrast, goes through the same
  // adders as every other booking, and both periods are right.
  //
  // WHY NOT BOOKED BY CALLBACK. The node starts ONCE per
  // process, the services arise afterwards and individually; a callback at
  // node start would have booked into the still empty service list. Instead it is
  // read when someone looks — which is at the same time the
  // only point in time at which the number is needed.
  //
  // A RESTART OF THE NODE resets its counters to 0. A
  // difference would then be negative; in that case the new absolute value
  // counts as increment. That is the only right reading: the bytes since the
  // restart were incurred, those before are already booked.
  int _lastWireOut = 0;
  int _lastWireIn = 0;
  int _lastRelayBytes = 0;
  int _lastRelayCells = 0;

  void noteNodeCounters({
    required int wireSent,
    required int wireReceived,
    required int relayBytes,
    required int relayCells,
  }) {
    int growth(int now, int before) => now >= before ? now - before : now;

    addBytesSent(growth(wireSent, _lastWireOut));
    addBytesReceived(growth(wireReceived, _lastWireIn));
    _relayBytes += growth(relayBytes, _lastRelayBytes);
    _messagesRelayed += growth(relayCells, _lastRelayCells);

    _lastWireOut = wireSent;
    _lastWireIn = wireReceived;
    _lastRelayBytes = relayBytes;
    _lastRelayCells = relayCells;
  }

  // ── THE SNAPSHOTS OF THE NODE (§25.4, G-10, CLOSED) ────────────────
  //
  // UNTIL S361 THIS SAID "gap G-2". That was a WRONG NUMBER: G-2 is
  // the distribution of the two system channels (Bug Log, Feature
  // Requests, `cleona_service_pure.dart:793`) and has nothing to do with the
  // network statistics. The display metrics are G-10,
  // and G-10 has been CLOSED since S360 — the chain is completely
  // in production: `v41_attach.dart` sets `service.v41NodeGauges`,
  // `cleona_service.dart` fetches them in `getNetworkStats` and passes
  // them on to [noteNodeGauges].
  //
  // WHY THEY DO NOT GO THROUGH `noteNodeCounters`. There things are booked,
  // and booking means: form a difference, add, keep over two periods.
  // Applied to a quantity like "waiting for pieces" the result would be
  // nonsense — the state also falls again, and a sum over
  // states is no quantity.
  //
  // WHY THEY ARE REMEMBERED AT ALL, instead of being read directly from the
  // node in `collect`: `collect` does not know the node and is not supposed to
  // know it. The service passes the set in when it has it;
  // if no node is currently attached, the last state stays instead of jumping to
  // 0. A jump to 0 would look like "the cover stream has
  // stalled", but would only be "nobody is looking right now".
  V41NodeGauges _gauges = kNoNodeGauges;

  void noteNodeGauges(V41NodeGauges g) => _gauges = g;

  /// Periodic callback: nothing left to do. Historically this held
  /// `recordPeerCount` for the time series of the peer number. It
  /// fell on 01.09.2026 (S360) — the quantity itself ("how many peers
  /// do I know") has no counterpart in V4.1, and §22.7.3 forbids concluding
  /// deliverability from a partner count. The time series
  /// moreover never had a display consumer.

  /// Reset daily counters if calendar date changed (day, month, or year).
  void _checkDayReset() {
    final now = DateTime.now();
    if (_lastDayReset == null ||
        now.day != _lastDayReset!.day ||
        now.month != _lastDayReset!.month ||
        now.year != _lastDayReset!.year) {
      _bytesSentToday = 0;
      _bytesReceivedToday = 0;
      _lastDayReset = now;
    }
  }

  /// Builds the snapshot for the network statistics.
  ///
  /// EVERY FIELD HERE HAS A NAMED WRITER. That was not so until
  /// 01.09.2026: of 36 fields ten were set, the
  /// rest fell to their default values and looked in the UI
  /// like measured zeros. Whoever adds a field here without
  /// setting it restores exactly this state —
  /// `smoke_network_stats` therefore checks for every tile that it
  /// CAN move.
  NetworkStats collect({
    required bool isRunning,
    String? profileDir,
  }) {
    _checkDayReset();

    return NetworkStats(
      uptime: uptime,
      isRunning: isRunning,
      entryRecords: _gauges.entryRecords,
      slotsEmitted: _gauges.slotsEmitted,
      slotsSkipped: _gauges.slotsSkipped,
      slotsFailed: _gauges.slotsFailed,
      harvestRuns: _gauges.harvestRuns,
      lookupRuns: _gauges.lookupRuns,
      payloadsAssembled: _gauges.payloadsAssembled,
      payloadsOpened: _gauges.payloadsOpened,
      openTransfers: _gauges.openTransfers,
      piecesDiscarded: _gauges.piecesDiscarded,
      controlQueueDepth: _gauges.controlQueueDepth,
      controlQueueMax: _gauges.controlQueueMax,
      droppedControl: _gauges.droppedControl,
      droppedEphemeral: _gauges.droppedEphemeral,
      controlFailures: _gauges.controlFailures,
      bytesSentTotal: _bytesSent,
      bytesReceivedTotal: _bytesReceived,
      bytesSentToday: _bytesSentToday,
      bytesReceivedToday: _bytesReceivedToday,
      messagesSent: _messagesSent,
      messagesReceived: _messagesReceived,
      messagesRelayed: _messagesRelayed,
      relayDataVolume: _relayBytes,
      storedCells: _gauges.storedCells,
      storedEvicted: _gauges.storedEvicted,
      blindHeld: _gauges.blindHeld,
      blindEvicted: _gauges.blindEvicted,
      blindRefused: _gauges.blindRefused,
      dbSizeBytes: _measureDbSize(profileDir),
    );
  }

  /// Measure total size of encrypted database files in profile dir.
  static int _measureDbSize(String? profileDir) {
    if (profileDir == null) return 0;
    try {
      var total = 0;
      final dir = Directory(profileDir);
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync()) {
        if (entity is File && (entity.path.endsWith('.enc') || entity.path.endsWith('.json'))) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
