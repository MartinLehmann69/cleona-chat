// How much this node can push UP — measured locally, on the bytes it
// sends anyway.
//
// ══ WHY THIS FILE EXISTS, ALTHOUGH THERE ALREADY IS AN ESTIMATOR ═══
//
// `bandwidth_estimator.dart` is called that, but measures something else: it
// derives a VIDEO RATE from RTT and packet loss — a recommendation of how
// finely this node should encode. It does not answer the question of how
// much this node can forward for OTHERS.
//
// That is the quantity by which the group call topology is to be weighted
// (`docs/v4-redesign/S368-VORLAGE-gruppenanruf-baum-bandbreite.md`
// §3.4, the owner's formula):
//
//     f_i = floor( usable_upload_i / (K x bitrate_per_stream) )
//
// Whoever carries a lot gets many rungs; whoever carries little becomes a
// leaf. This makes bandwidth selection and topology one thing, not two.
//
// ══ WHAT IS MEASURED HERE AND WHAT IS NOT — read before the first call ══
//
// **What is measured is the ACHIEVED throughput**, not the capacity. A
// call does not saturate a line: 50 voice frames per second at 176 B
// are 70.4 kbit/s, and a line that carries that can do 71 kbit/s or a
// thousand times as much. **The measured value is therefore exclusively a
// LOWER BOUND of the capacity** — "this line has carried at least this
// much".
//
// That is not a weakness of the method but its honest limit, and it
// points in the right direction: a lower bound of the capacity yields a
// lower bound of the affordable fan-out. Assuming too few children costs
// one hop of depth. Assuming too many breaks the audio for the whole
// subtree. Of the two errors only one is bearable, and the method makes
// exactly that one.
//
// **A real capacity measurement would need saturation** — a stream that
// deliberately fills the line until it jams. That would be unnecessary
// network traffic (work rule 5) and moreover audible during a running
// call. It is therefore not built, and an estimated capacity value is
// **not invented**: [UploadObservation.capacityBitsPerSecond] stays
// `null` as long as the line has not shown its limit by itself.
//
// ══ WHAT THE VALUE DOES NOT DO TODAY ═════════════════════════════════
//
// **It is not distributed.** A bandwidth report to the other participants
// would need a control channel, and §17.1 has none
// (`call_transport_v41.dart`, `sendSecuredToParticipant` -> `noCarrier`).
// Inventing one is explicitly not part of this file; the decision on it
// lies with the owner (S368 proposal §4, option A/B/C).
// Until then every node knows only its own value — which for the formula
// above is exactly the half one can have locally.
library;

import 'dart:math' as math;

/// How reliable an [UploadObservation] is.
///
/// Three levels, because they are three different things — and because an
/// outdated value and a never-measured one must NOT behave the same for
/// the caller: the one may be used with caution, the other not at all.
enum UploadConfidence {
  /// Freshly measured: the most recent full second lies within
  /// [UploadProbe.freshnessWindow]. The value describes the line on
  /// which this node is sending RIGHT NOW.
  measured,

  /// Measured, but old. The number stems from an earlier call or from a
  /// pause in sending; since then the node may have changed networks
  /// (Wi-Fi -> cellular is exactly the case in which the number becomes
  /// wrong by an order of magnitude). Usable as a guide, not as a promise.
  stale,

  /// Nothing measured. **The only honest value if this node has never
  /// sent media** — and the reason why [UploadObservation] delivers
  /// `null` here instead of a number. A default value would look weighted
  /// at this point and would not be; exactly the same facade that
  /// `CallTransportV41.routeCostTo` rejects for route costs.
  unknown,
}

/// The network form over which this node sends.
///
/// Stands here because "cheap is not fast" (S368 proposal §5, point 2):
/// a cellular participant with 100 Mbit/s should not become the root — he
/// pays for volume and hangs on a battery. Throughput alone is the
/// wrong criterion.
enum NetworkForm {
  /// Not determinable. **No fallback to "probably fixed line".**
  unknown,

  /// Kabelgebunden (Ethernet).
  wired,

  /// Wi-Fi. Treated like wired for forwarding — the volume and battery
  /// question does not arise here.
  wifi,

  /// Mobile network. Volume-limited.
  cellular,
}

/// Where this node currently draws power from.
enum PowerSource {
  /// Not determinable. **No fallback to "probably power supply".**
  unknown,

  /// Am Netzteil.
  mains,

  /// On battery.
  battery,
}

/// What [UploadProbe.observe] can say about this node.
///
/// A value object, not state: it describes a point in time and does not
/// age along. Whoever keeps it keeps a snapshot — which is why it carries
/// its own [confidence] with it.
final class UploadObservation {
  const UploadObservation({
    required this.observedBitsPerSecond,
    required this.capacityBitsPerSecond,
    required this.confidence,
    required this.form,
    required this.power,
  });

  /// What this node REALLY pushed up in its best full second, in bit/s
  /// — or `null` if nothing was ever measured.
  ///
  /// **A lower bound of the capacity, never the capacity.** See the
  /// header of this file.
  final int? observedBitsPerSecond;

  /// The actual upper limit of the line, in bit/s — **almost always
  /// `null`**, and that is the intention.
  ///
  /// It is only known when the line has shown its limit by itself, i.e.
  /// when [UploadProbe.recordCongestion] was called while sending was
  /// happening. Nobody saturates a call deliberately (work rule
  /// 5), which is why this field stays empty in ordinary operation.
  ///
  /// **Today `lib/` calls [UploadProbe.recordCongestion] nowhere**, and
  /// that is stated here instead of being missing: the level-D send side
  /// has no loss signal — `CallTransport.sendMedia` is fire-and-forget
  /// (§17.1), and there is no DELIVERY_RECEIPT for media. Whoever builds
  /// one finds the intake point here.
  final int? capacityBitsPerSecond;

  /// How reliable [observedBitsPerSecond] is.
  final UploadConfidence confidence;

  /// The network type, as far as known.
  final NetworkForm form;

  /// The energy source, as far as known.
  final PowerSource power;

  /// The share of the measured upload that a node may give up for FOREIGN
  /// streams.
  ///
  /// Half, and the other half is not a safety margin but occupied: the
  /// node sends its own stream, receives, acknowledges on other lanes and
  /// shares the line with everything else on the device. The same half
  /// underlies the table in §3.4 of the S368 proposal ("fan-out that a
  /// real connection carries with half of its upload").
  static const double usableShare = 0.5;

  /// The upload left over for foreign streams, in bit/s — `null` if
  /// nothing was measured.
  int? get usableBitsPerSecond {
    final observed = observedBitsPerSecond;
    if (observed == null) return null;
    return (observed * usableShare).floor();
  }

  /// `f_i` from the owner's formula: how many children this node can
  /// carry in the forwarding tree.
  ///
  /// [streamBitsPerSecond] is the rate of ONE forwarded stream (audio:
  /// 28000 per §17.5; video tile: 150000, the lowest rung of the ladder
  /// in `video_preset.dart`).
  /// [concurrentStreams] is `K`, the number of speakers passed through
  /// at the same time — in practice 3 to 4.
  ///
  /// ── THREE CASES IN WHICH THE RESULT IS 0, AND WHY ────────────
  ///
  /// 0 means "this node becomes a leaf", not "error". It happens:
  ///
  ///   1. **[confidence] is [UploadConfidence.unknown].** We know
  ///      nothing, so we promise nothing. A default value here would be
  ///      the facade this file is meant to avoid.
  ///   2. **[form] is [NetworkForm.cellular] or [power] is
  ///      [PowerSource.battery].** S368 proposal §5, point 2: a
  ///      cellular participant should not carry half the group, not even
  ///      with 100 Mbit/s — he pays for volume, and the battery is finite.
  ///      This is a rule, not an estimate: `unknown` does NOT trigger it,
  ///      because "not determinable" does not mean "cellular".
  ///   3. **The measured upload does not carry a single child.** According
  ///      to the table in §3.4 that is the normal case for video on DSL 16
  ///      and weak cellular.
  int fanOutFor({
    required int streamBitsPerSecond,
    required int concurrentStreams,
  }) {
    if (streamBitsPerSecond <= 0 || concurrentStreams <= 0) return 0;
    if (confidence == UploadConfidence.unknown) return 0;
    if (form == NetworkForm.cellular || power == PowerSource.battery) return 0;
    final usable = usableBitsPerSecond;
    if (usable == null) return 0;
    return usable ~/ (streamBitsPerSecond * concurrentStreams);
  }

  @override
  String toString() => 'UploadObservation(observed='
      '${observedBitsPerSecond ?? "—"} bit/s, usable='
      '${usableBitsPerSecond ?? "—"} bit/s, capacity='
      '${capacityBitsPerSecond ?? "unknown"}, ${confidence.name}, '
      '${form.name}, ${power.name})';
}

/// Measures the own upload on the media frames this node sends
/// anyway.
///
/// **No traffic of its own.** The probe does not generate a single
/// packet; it counts what the call pushes out anyway. That is the
/// condition under which it can exist without a control channel and
/// without violating work rule 5.
///
/// It is fed at the two places where a media frame leaves the service
/// — `CallService.sendLiveMediaFrame` (1:1) and
/// `GroupCallManager._sendGroupLiveMediaFrame` (group) — and only on
/// SUCCESS. A frame that the transport rejected with `noPath` was
/// never on the line and proves nothing about it.
class UploadProbe {
  UploadProbe({
    this.form = NetworkForm.unknown,
    this.power = PowerSource.unknown,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long a measurement counts as "fresh".
  ///
  /// 10 s: long enough that a short pause in speech does not immediately
  /// invalidate the value (Opus' speech-pause detection makes the stream
  /// thin during silence), short enough that a network change does not
  /// go unnoticed for minutes.
  static const Duration freshnessWindow = Duration(seconds: 10);

  /// How many full seconds are looked back.
  ///
  /// The maximum of these seconds is the measurement — not the average.
  /// The average over a call with speech pauses would describe the
  /// user's talkativeness, not the line.
  static const int bucketCount = 30;

  final DateTime Function() _clock;

  /// Full, completed seconds: second stamp -> bytes.
  final Map<int, int> _buckets = <int, int>{};

  DateTime? _lastRecord;
  int? _capacityBitsPerSecond;

  /// The network form, as far as the platform provides it.
  ///
  /// **Today `lib/` sets it nowhere**, and the default value is therefore
  /// [NetworkForm.unknown]. That is not a forgotten connection but the
  /// measured situation: `connectivity_plus` is in `pubspec.yaml`, but
  /// only the Flutter process can load it — under Linux and Windows the
  /// calls run in the DAEMON, which by the preflight rule
  /// "Daemon import graph Flutter-free" must not import `package:flutter`.
  /// A value from there would have to come down via IPC; that is a
  /// seam of its own and is not faked here.
  ///
  /// The same applies, more sharply, to the power source: `battery_plus`
  /// is not a dependency of this project at all. `unknown` is the truth.
  NetworkForm form;

  /// Where this node draws power from, as far as the platform provides it.
  ///
  /// See [form]: `battery_plus` is not a dependency of this project,
  /// so there is nothing to read here. [PowerSource.unknown] is not
  /// "not wired yet" but the truth.
  PowerSource power;

  /// A media frame REALLY went out.
  ///
  /// [wireBytes] is the length on the wire, i.e.
  /// `DFrameKind.frameClass.wireSize` (176 B voice, 1200 B stream) — not
  /// the payload length. §17.1 freezes the size classes: a
  /// 12-B Opus frame costs the same 176 B as a full one. Whoever counted
  /// the payload would underestimate the upload during every speech
  /// pause by a multiple.
  ///
  /// **IP and UDP headers are NOT included** (48 B per datagram over
  /// IPv6). That is a deliberate UNDERestimate: the measurement is a
  /// lower bound of the capacity, and a lower bound may be too low,
  /// never too high. Adding them here would mean guessing an address
  /// family that nobody knows at this point.
  void recordSent(int wireBytes) {
    if (wireBytes <= 0) return;
    final now = _clock();
    _lastRecord = now;
    final second = now.millisecondsSinceEpoch ~/ 1000;
    _buckets[second] = (_buckets[second] ?? 0) + wireBytes;
    _trim(second);
  }

  /// The line has shown its limit — sustained loss or backpressure
  /// while sending.
  ///
  /// Only this call turns a lower bound into a capacity: if something
  /// jams at X bit/s, X is the upper limit and no longer merely an
  /// achieved value.
  ///
  /// **Nobody in `lib/` calls this today** — see
  /// [UploadObservation.capacityBitsPerSecond]. The method stands here as
  /// a named intake point, not as a claim that it is served.
  void recordCongestion() {
    final observed = _peakBitsPerSecond();
    if (observed == null) return;
    final soFar = _capacityBitsPerSecond;
    // The SMALLEST observed jam limit applies: a line that already jammed
    // at 300 kbit/s does not get better through a later jam at 900
    // — the later one only says that more got through at that moment.
    _capacityBitsPerSecond =
        soFar == null ? observed : math.min(soFar, observed);
  }

  /// The finding. Generates no traffic and no system call.
  UploadObservation observe() {
    final observed = _peakBitsPerSecond();
    final UploadConfidence trust;
    if (observed == null || _lastRecord == null) {
      trust = UploadConfidence.unknown;
    } else if (_clock().difference(_lastRecord!) <= freshnessWindow) {
      trust = UploadConfidence.measured;
    } else {
      trust = UploadConfidence.stale;
    }
    return UploadObservation(
      observedBitsPerSecond: observed,
      capacityBitsPerSecond: _capacityBitsPerSecond,
      confidence: trust,
      form: form,
      power: power,
    );
  }

  /// Forget everything — after a network change, where the old number is
  /// not just old but wrong.
  void reset() {
    _buckets.clear();
    _lastRecord = null;
    _capacityBitsPerSecond = null;
  }

  /// The maximum of the FULL seconds, in bit/s.
  ///
  /// The running second is left out: it is not over yet and shows a
  /// value that is too small on every query. Counting a partial second
  /// would mean systematically underestimating the measured upload —
  /// all the more, the earlier in the second the question is asked.
  int? _peakBitsPerSecond() {
    if (_buckets.isEmpty) return null;
    final running = _clock().millisecondsSinceEpoch ~/ 1000;
    int? peak;
    for (final e in _buckets.entries) {
      if (e.key >= running) continue;
      final bits = e.value * 8;
      if (peak == null || bits > peak) peak = bits;
    }
    return peak;
  }

  void _trim(int currentSecond) {
    if (_buckets.length <= bucketCount) return;
    final limit = currentSecond - bucketCount;
    _buckets.removeWhere((second, _) => second < limit);
  }
}
