/// The directed entry via the DATA PORT (§11.1 step 2/§11.3 row C).
///
/// ── WHAT THIS FILE FIXES, AND WHY IT IS NECESSARY FOR THAT (S372) ─────
///
/// Until S372 the directed entry — the path §11.3 calls "the
/// normal way in" — ran on the same fixed port as the
/// LAN call: `requestRecordFrom(host)` sent an `opRecordRequest` to
/// `host:41340`, and the call socket of the counterpart was therefore bound to
/// `InternetAddress.anyIPv4`, i.e. reachable from the whole internet.
/// That is a SECOND fixed point next to the one that
/// B-24 knowingly accepts, and it has two consequences:
///
///  1. A censor who blocks UDP/41340 kills step 3 EVERYWHERE
///     at once. The constant stands in every shipped
///     binary. RL-14 names exactly this property as what V4.1
///     must not have: "no well-known port, no designated relay".
///  2. Whoever answers a record request on 41340 is a
///     Cleona node. That is the presence disclosure because of which BLE
///     was rejected — only over the open internet.
///
/// The port under which a counterpart REALLY listens lay in the hint
/// all the time (`ip:port` from the ContactSeed) and was merely
/// thrown away. Since S372 [EntryHint] keeps it, and this portal
/// exchange is the receiving side for it: the record request arrives on
/// the data port, via the same socket over which handshake
/// and cells also run.
///
/// ── WHY THIS MAKES NOTHING NEW DISTINGUISHABLE ON THE WIRE ────────────
///
/// §5.1 demands that at the egress nothing separates one unit from another.
/// On the data port today EVERY unit is 1200 B and
/// uniformly distributed ciphertext (`udp_sockets.dart`: "kCellSize =
/// kHandshakeFlightSize = 1200 for every unit on the wire"). A
/// plaintext probe with the marker "CLE4" would be immediately visible there and
/// would be the same error one level deeper. Therefore:
///
///  * **Fixed size.** Every portal unit is exactly [kEntryUnitSize] =
///    1200 B, like cell and handshake flight.
///  * **Sealed.** `nonce(12) ‖ AES-GCM(K_entry, klartext)`, i.e.
///    uniformly distributed bytes without a marker, without a plaintext field.
///  * **The key comes from the channel constant and the hour.**
///    The same construction that §11.3 stage A already uses for the external
///    rendezvous (`external_entry.dart`, `ExternalTag`) —
///    there with a day epoch, here with an hour epoch like the handshake MAC
///    (E-78). That does NOT protect against someone with the app; the
///    channel constant is shipped with it and channel separation is
///    explicitly operational (§11). It protects against the observer on the
///    wire and against the scanner who without the constant cannot even
///    ask.
///  * **Fragmented.** An `EntryRecord` is about 1.4 KB — §11.1 says that
///    itself ("it does **not** fit in a cell … and is therefore
///    fragmented"). The answer is thus two 1200 B units, not a
///    single one of deviating length.
///
/// ── WHAT IT DOES NOT ACHIEVE, explicitly ──────────────────────────────
///
/// Whoever has the channel constant (i.e. the app) can query an arbitrary
/// `ip:port` and recognise from it whether a Cleona node
/// sits there. That is the same membership disclosure that §11 already lists for the
/// link handshake as a declared price — with the
/// difference that the port here is random per node and a
/// scanner would first have to find it (55 000 values per host instead of one).
///
/// ── AMPLIFICATION, MEASURED ───────────────────────────────────────────
///
/// A service that sends a large answer to a small request
/// is a reflector for forged sender addresses. The old path was
/// one, and not a small one (measured 06.09.2026):
///
///     LAN request datagram            64 B
///     LAN answer datagram           1379 B   -> factor 21,5
///
/// — and it was reachable from the whole internet via the wildcard binding.
/// Here the request is padded to the same 1200 B as
/// the answer units:
///
///     Portal request           1 x 1200 B
///     Portal answer            2 x 1200 B   -> factor 2
///
/// Plus two caps (S376, see the block at [maxAnswersPerPeer]):
/// [maxAnswersPerPeer] = 8 answers per sender address and
/// [maxAnswersPerWindow] = 256 answers in total, per [rateWindow] = 30 s
/// — at most 19.2 kB per address and 614 kB in total in the window. The
/// window rolls on the clock of THIS class, not on the call clock of another
/// file. The caps limit the QUANTITY; the factor 2 is limited by
/// the padding of the request, and no number here brings that back.
///
/// NO SOCKET IN THIS FILE, as everywhere in the delivery layer: the
/// input and output are passed in so that the rules stay checkable
/// without a network.
library;

import 'dart:typed_data';

import '../config/network_channel.dart';
import '../crypto/sodium_ffi.dart';
import 'package:cleona/core/sync/entry_record.dart';
import 'entry_sources.dart';

/// Size of every portal unit on the wire — the same as cell and
/// handshake flight (§4.3). Not imported from `link/cell.dart`, because the
/// delivery layer does not import the link layer; the guard
/// [kEntryUnitSize] == `kCellSize` is in the smoke.
const int kEntryUnitSize = 1200;

/// `nonce(12) ‖ ciphertext(rest)`; AES-GCM appends a 16 B tag.
const int _nonceLen = 12;
const int _tagLen = 16;

/// What fits into a unit in plaintext.
const int _plainLen = kEntryUnitSize - _nonceLen - _tagLen; // 1172

/// `op(1) ‖ anfrage(4) ‖ teil(1) ‖ teile(1) ‖ laenge(2)`
const int _headerLen = 9;

/// Payload per unit.
const int kEntryPortalPayload = _plainLen - _headerLen; // 1163

/// The key of the portal: from the channel constant and the hour.
///
/// HOUR, not day: the same epoch as the handshake MAC (E-78, "one
/// hour, acceptance ±1"). A recorded unit is thus replayable for at most
/// two hours instead of up to 48.
abstract final class EntryPortalKey {
  static const Duration epoch = Duration(hours: 1);

  static int hourOf(DateTime t) =>
      t.toUtc().millisecondsSinceEpoch ~/ epoch.inMilliseconds;

  static Uint8List forHour(String channel, int hour) => SodiumFFI().hkdfSha256(
        Uint8List.fromList(channel.codeUnits),
        salt: Uint8List.fromList('cleona-entry-portal/v1'.codeUnits),
        info: Uint8List.fromList('key/$hour'.codeUnits),
        length: 32,
      );
}

/// The roles of a unit.
abstract final class EntryPortalOp {
  /// „Gib mir deinen Eintrittsdatensatz."
  static const int request = 0x01;

  /// "Here it is" — fragmented.
  static const int response = 0x02;
}

/// The directed entry via the data port, without a socket.
final class EntryPortal {
  /// Sends ONE finished 1200-B unit.
  final void Function(Uint8List unit, String host, int port) sendUnit;

  /// The own record as it is handed out on request.
  final EntryRecord Function() ownRecord;

  /// Is called when a verified foreign material is complete.
  final void Function(EntryRecord record) onRecord;

  /// Die Kanalkonstante. Test-Einspeisung; produktiv [kNetworkChannel].
  final String channel;

  /// Die Uhr. Test-Einspeisung.
  final DateTime Function() now;

  /// What has already been tried per hint. See the block at
  /// [retryAfterTicks] — at most TWO requests, not one per tick
  /// (work rule #5).
  final Map<String, _HintAttempt> _asked = <String, _HintAttempt>{};

  /// The call clock, counted. It is moved from outside ([tick]) — the
  /// portal has no timer and is not supposed to get one.
  int _tick = 0;

  /// How many answers per sender address in the current window.
  final Map<String, int> _served = <String, int>{};

  /// Start of the current window. `null` = none opened yet.
  DateTime? _windowStart;

  /// Answers in the current window, across ALL senders.
  int _servedTotal = 0;

  // ── THE RATE LIMIT, AND WHAT IT GAINED ON 2026-09-08 (S376) ─────────
  //
  // UNTIL S376 only [maxAnswersPerPeer] stood here, and the
  // table was cleared solely from outside: `lan_entry_wiring.call()` called
  // [resetRateLimit] on the call clock. Two gaps, both measured:
  //
  //  1. **The table had no cap.** It got one entry per
  //     DIFFERENT sender address; the cap per sender
  //     did not prevent that, it only counted WITHIN an entry.
  //     Measured on 08.09.2026 with ONE recorded, valid
  //     request datagram and forged source addresses: 300 000
  //     sources -> 300 000 entries, 600 000 answer units,
  //     720 MB out. The neighbouring table `_construct` has always had a cap against exactly this
  //     class ([maxPendingReassemblies]) and
  //     justifies it in the body: "Without a cap a flood of half
  //     answers would be a memory leak from outside." For `_served`
  //     the same sentence applied and was missing.
  //  2. **The window belonged to another file.** How long "per
  //     sender four" applies was decided by `intervalSeconds` in
  //     `lan_entry_wiring.dart` — a value chosen for a completely different
  //     reason (call clock). Whoever changes it changes
  //     a security limit unnoticed. And if the clock ever does
  //     not run, the limit never expires.
  //
  // Since then the window rolls HERE, on the portal's clock, and there is
  // a second cap across all senders. [resetRateLimit] stays —
  // the call clock may additionally reset, it just no longer has to.
  //
  // ── THE NUMBERS, COMPUTED ───────────────────────────────────────────
  //
  // An answer is two units = 2400 B; a request is ONE
  // unit = 1200 B (§5.1 pads it to the same size). The
  // amplification factor is thus 2 and depends on none of these numbers —
  // the caps limit not the factor, but the ABSOLUTE quantity
  // and the memory.
  //
  //   per sender   8 answers / 30 s = 19,2 kB / 30 s =  640 B/s
  //   in total   256 answers / 30 s =  614 kB / 30 s = 20,5 kB/s
  //   table      at most 256 entries — every entry costs
  //              at least one answer, so the total cap also caps
  //              the table. An entry is an address string
  //              (<= 45 characters for IPv6) plus an `int`; with the
  //              Dart map overhead about 150 B, together under 40 kB.
  //
  // ── WHY 8 AND NO LONGER 4 (this LOOSENS an S372 value) ───────────────
  //
  // An honest requester needs EXACTLY ONE answer per hint: [ask]
  // sends exactly once per hint ([_asked]) and NEVER repeats. A
  // rejected request is therefore not "again later", but
  // final — the hint never resolves. Exactly therefore the cap
  // per address must not sit tight as soon as several people share ONE
  // source address (carrier-grade NAT). In the LAN, the normal case of the
  // portal, every computer has its own address and 4 would have
  // sufficed; from outside arbitrarily many share one. 8 doubles
  // the margin for 9.6 kB more per address and window and leaves the
  // factor 2 untouched. It still takes >= 32 different
  // addresses to exhaust the total cap.
  //
  // ── WHAT THIS LIMIT IS NOT ──────────────────────────────────────────
  //
  // It is the INTERIM MEASURE approved by the owner. The
  // final solution is V-3 = B: bind the portal key to the `L_node` of the
  // host, so that only whoever has the hint can ask. Until then
  // it holds: whoever has the channel constant can ask; whoever has recorded ONE unit
  // can replay it for up to two hours from arbitrary
  // forged addresses. A total cap turns that into
  // a bounded load instead of a memory leak — it turns it into
  // NO access control.

  /// Length of the window over which both caps count.
  static const Duration rateWindow = Duration(seconds: 30);

  /// Maximum number of answers per sender address in the window.
  static const int maxAnswersPerPeer = 8;

  /// Maximum number of answers across ALL senders in the window. At the same
  /// time caps the size of [_served].
  static const int maxAnswersPerWindow = 256;

  /// How many sender addresses are kept in the current window.
  /// Never larger than [maxAnswersPerWindow].
  int get trackedSources => _served.length;

  /// Requests that were rejected at the cap PER SENDER.
  int rejectedSource = 0;

  /// Requests rejected at the TOTAL cap. If this number is
  /// high, a flood is running — and honest first contacts fail with it.
  int rejectedWindow = 0;

  /// Partial pieces waiting for their siblings.
  final Map<String, _PartialBuild> _construct = <String, _PartialBuild>{};

  /// Maximum number of simultaneously open reassemblies. Without a cap
  /// a flood of half answers would be a memory leak from outside.
  static const int maxPendingReassemblies = 32;

  /// How long a half-finished assembly lives.
  static const Duration reassemblyLifetime = Duration(seconds: 20);

  int dropped = 0;

  // ── THE RECEIVING SIDE WAS MUTE (S382) ──────────────────────────────
  //
  // Measured in the lab on 12.09.2026: Alice asks the Windows VM directly
  // for its entry record, the Windows VM asks Alice — and
  // NEITHER side answers. Both logs show only the own
  // question and then "N Hinweis(e) … ein zweites und letztes Mal gefragt
  // (N verstummt)". What happened on the receiving side could not be told apart from outside
  // from "the packet never arrived": `receive` has
  // not a single log line, and the most frequent failure — the unit
  // cannot be opened — was not even COUNTED
  // (`if (clear == null) return false;` without `dropped++`).
  //
  // These three counters change nothing in the behaviour. They only make the
  // difference visible between "never arrived", "arrived and could not be
  // opened" (wrong channel, wrong hour, foreign datagram) and
  // "arrived, was readable, was discarded for a named reason".
  // Without this difference the next attempt is guessing again.

  /// Units that arrived in [receive] at all — regardless of
  /// the outcome. The reference quantity for everything else.
  int receiveIncoming = 0;

  /// Arrived, but could not be opened under any of the three hour keys.
  ///
  /// That is the EXPECTED outcome for every foreign datagram that lands on
  /// the data port — the `unclaimed` branch of the demux also sees
  /// noise. A number without a counterpart thus says nothing here; only
  /// together with [receiveIncoming] and [answered] does it become a statement.
  int notOpened = 0;

  /// Arrived, opened, recognised as a request and answered.
  int answered = 0;

  int _requestCounter = 0;

  EntryPortal({
    required this.sendUnit,
    required this.ownRecord,
    required this.onRecord,
    String? channel,
    DateTime Function()? now,
  })  : channel = channel ?? kNetworkChannel,
        now = now ?? DateTime.now;

  // ── THE SECOND ATTEMPT, AND WHY IT EXISTS (V-14, S377) ──────────────
  //
  // UNTIL S377 the first line in [ask] was `if (!_asked.add(hint.key))
  // return false;` — a hint cost EXACTLY ONE request, forever.
  // That was meant as thrift (work rule #5) and was too thrifty
  // at one place: the carrier is a single UDP datagram, and
  // UDP loses. If the request gets lost or the answer, that means
  // "this hint NEVER resolves" — and the only countermeasure in the
  // whole program was that the human fetches a new ContactSeed.
  // The comment at [maxAnswersPerPeer] already names exactly this property
  // as the reason not to set the cap per address tight: "a
  // rejected request is therefore not ‚again later', but
  // final".
  //
  // What is built is therefore EXACTLY ONE second attempt, no retry clock.
  // The difference is the whole point: "follow up until it works" would be
  // polling and thus the same error that S372 removed from `call()`
  // (there: one datagram per target every 30 s, unlimited).
  //
  // ── WHERE THE NUMBER FOLLOWS FROM ──────────────────────────────────
  //
  // A "tick" is one run of `lan_entry_wiring.call()`, i.e.
  // `intervalSeconds` — default 30 s (`lan_entry_wiring.dart`,
  // parameter `intervalSeconds = 30`; `bin/cleona_v41_node.dart` reads
  // `--lan-interval`, likewise default 30). [retryAfterTicks] = 2 thus means
  // in normal operation: the second attempt goes 60 s after the first.
  //
  // LOWER BOUND — the second attempt must not overtake the answer,
  // otherwise it doubles the traffic without gain. What the program ITSELF
  // keeps as the answer time of a directed entry is in
  // `entry_sources.dart`: `DirectedEntrySource.window = 6 s` is the
  // whole time the cold-start step "human" waits for the FIRST answer,
  // `collectWindow = 2,5 s` the collecting afterwards. 60 s is
  // ten times these 6 s. An answer that came later would not be waited for by the
  // cascade anyway.
  //
  // UPPER BOUND — the second attempt must still lie within the lifetime
  // of the hint. The binding limit is the portal key:
  // [EntryPortalKey.epoch] = 1 h with acceptance ±1, so a unit can be opened
  // for at least an hour. 60 s is a sixtieth
  // of that. (`EntryHintStore` itself knows NO time limit — a hint
  // only drops out when 16 more move up, `max = 16`.)
  //
  // WHY NOT 1. At a 30 s tick even one tick would already be five times
  // the 6 s. But `intervalSeconds` is configurable per node, and the
  // lower bound should not depend on the default: with TWO ticks
  // it holds down to a 4 s tick (2 x 4 s = 8 s >
  // 6 s), with one tick it would already need 7 s.
  //
  // WHY NOT 3 OR MORE. 90 s and more lie outside the span
  // in which a human still connects the second attempt with the scanned
  // QR code; whoever has seen nothing after a minute and a half
  // has abandoned the process. The attempt would then be
  // traffic for a flow that nobody follows anymore.
  //
  // ── THE PRICE, COMPUTED ────────────────────────────────────────────
  //
  //   per hint  2 attempts x 1 unit x 1200 B = 2400 B, ONCE.
  //
  // Not per tick, not per window: over the whole lifetime of the
  // hint. If the answer comes on the first attempt, it is 1200 B.

  /// Call ticks between the first and the second attempt.
  static const int retryAfterTicks = 2;

  /// Attempts per hint — hard, then silence.
  static const int maxAttemptsPerHint = 2;

  /// Maximum number of tracked hints.
  ///
  /// The state per hint must be capped like [_construct] and [_served];
  /// until S377 [_asked] was a set WITHOUT a cap. The only source in
  /// `lib/` is `personEntryHints` with `EntryHintStore.max = 16`
  /// (`entry_sources.dart`), so 64 is four times what
  /// regular operation ever produces — room for several seeds in a row without
  /// the displacement applying at all in the normal case. An entry
  /// costs an address string (<= 45 characters for IPv6) and three
  /// small fields, together under 10 kB.
  static const int maxTrackedHints = 64;

  /// How many second attempts have gone out so far.
  int repeated = 0;

  /// Hints that were NOT asked because [maxTrackedHints] was full
  /// and no entry was finished. Counted and not concealed (E-83):
  /// if the number is above zero, someone has handed in more than 64 hints
  /// at once, and some of them remained without a request.
  int rejectedTable = 0;

  /// How many hints are tracked.
  int get trackedHints => _asked.length;

  /// Hints that remained without an answer after [maxAttemptsPerHint] attempts.
  /// If this number is high, the way in is closed, not tight.
  int get wentSilent => _asked.values
      .where((v) => !v.answered && v.attempts >= maxAttemptsPerHint)
      .length;

  /// Moves the call tick on by one.
  ///
  /// Separate from [resetRateLimit], although both come from `call()`: the
  /// rate window has rolled on its own clock since S376 and should not need to be
  /// touched from outside at all; the attempt tick, on the other hand, is
  /// exactly what the caller dictates. Two subjects, two
  /// inputs.
  void tick() => _tick = (_tick + 1) & 0x3fffffff;

  /// Asks ONE hint for its record.
  ///
  /// The first call sends the request. Every further one sends nothing —
  /// unless [retryAfterTicks] call ticks have passed since the first attempt
  /// without an answer arriving; then the SECOND and
  /// last attempt goes out.
  ///
  /// Returns `true` if a request went out.
  bool ask(EntryHint hint) {
    final state = _asked[hint.key];
    if (state == null) {
      if (!_placeMakeRoom()) {
        rejectedTable++;
        return false;
      }
      final fresh = _HintAttempt(_tick);
      _asked[hint.key] = fresh;
      _requests(hint, fresh);
      return true;
    }
    // THREE reasons to stay silent, and all three are final: the
    // hint has answered, it has used up its two attempts,
    // or the second is not yet due.
    if (state.answered) return false;
    if (state.attempts >= maxAttemptsPerHint) return false;
    if (_tick - state.firstTick < retryAfterTicks) return false;
    repeated++;
    _requests(hint, state);
    return true;
  }

  void _requests(EntryHint hint, _HintAttempt state) {
    state.attempts++;
    _requestCounter = (_requestCounter + 1) & 0xffffffff;
    final units = _build(EntryPortalOp.request, _requestCounter,
        Uint8List(0), _key());
    for (final e in units) {
      sendUnit(e, hint.host, hint.port);
    }
  }

  /// Makes room BEFORE a new hint is added. `false` means: no
  /// room, and it is NOT asked.
  ///
  /// ── WHY THE OLDEST DOES NOT GIVE WAY HERE (measured, S377) ─────────
  ///
  /// The first version threw out the oldest entry when the cap was full,
  /// as [_construct] does. The guard in the smoke turned that red immediately:
  /// 500 hints in six rounds against a cap of 64
  /// yielded **6 requests to the same target** instead of at most two. The
  /// reason is that the two tables hold different things. [_construct]
  /// holds a half reassembly — whoever loses it loses an
  /// answer. [_asked] holds the USED-UP QUANTITY of a hint;
  /// whoever loses it releases it, and the next [ask] on
  /// the same key starts at attempt 1 again. A
  /// displacement is a memory cap there, here it would be a leak in
  /// the promise "at most 2400 B per hint".
  ///
  /// Therefore only whoever is FINISHED gives way (answered or used up their two
  /// attempts) — for those there is nothing left to release. If
  /// nobody is finished, the new hint is not asked and is counted in
  /// [rejectedTable].
  ///
  /// That is no data loss, but a postponement: an open
  /// entry becomes finished at the latest [retryAfterTicks] ticks after its first
  /// attempt and thus displaceable. And the only producer in
  /// `lib/` holds at most `EntryHintStore.max` = 16 hints, a
  /// quarter of the cap — in regular operation this place is never
  /// reached.
  bool _placeMakeRoom() {
    if (_asked.length < maxTrackedHints) return true;
    for (final e in _asked.entries) {
      if (e.value.answered || e.value.attempts >= maxAttemptsPerHint) {
        _asked.remove(e.key);
        return true;
      }
    }
    return false;
  }

  /// Records that a hint is resolved — no second attempt
  /// anymore.
  ///
  /// Called from [receive] as soon as a complete and GENUINE record
  /// comes in, and from the wiring when the same node came in via the
  /// LAN call ("resolved otherwise"). A hint whose
  /// host one already has must not cost a second request.
  ///
  /// An UNKNOWN key is NOT created. Otherwise every
  /// incoming record would be an entry in this table, and the
  /// table would again be fillable from outside — exactly what
  /// [maxTrackedHints] stands against.
  bool markResolved(String key) {
    final state = _asked[key];
    if (state == null || state.answered) return false;
    state.answered = true;
    return true;
  }

  /// How a hint is written — the same rule as
  /// `EntryHint.key` and `EntryAddress.toString()`.
  static String hintKey(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// Forgets whom one has already asked — necessary when the network
  /// changes and the same addresses can belong to someone else.
  ///
  /// Thereby also resets the attempt count, and that is intended: after
  /// a network change the counterpart has never seen our new source address,
  /// the old attempt is worthless. Two attempts apply per
  /// hint AND network, not per hint and lifetime of the process.
  void forgetAsked() => _asked.clear();

  /// Resets both caps and opens a new window.
  ///
  /// The call clock may do this; since S376 it is no longer necessary —
  /// [_windowCheck] rolls the window on its own clock.
  void resetRateLimit() {
    _served.clear();
    _servedTotal = 0;
    _windowStart = now();
  }

  /// Rolls the window when [rateWindow] is over.
  ///
  /// `t.isBefore(start)` catches a clock that jumps back (time zone,
  /// NTP correction, waking from sleep). Without this
  /// branch the window would stand still until the clock reaches the old value
  /// again — and the limit would be a block for that long.
  void _windowCheck() {
    final t = now();
    final start = _windowStart;
    if (start == null || t.isBefore(start) || t.difference(start) >= rateWindow) {
      _served.clear();
      _servedTotal = 0;
      _windowStart = t;
    }
  }

  /// Accepts a unit from the data port.
  ///
  /// Returns `true` if it belonged to this portal. Everything else
  /// is a `false` WITHOUT side effect — the caller (`LinkDemux`) then
  /// still has other branches, and a datagram that nobody claims
  /// disappears silently (E-83).
  bool receive(Uint8List unit, String fromHost, int fromPort) {
    if (unit.length != kEntryUnitSize) return false;
    receiveIncoming++;
    final clear = _open(unit);
    if (clear == null) {
      notOpened++;
      return false;
    }

    final op = clear[0];
    final request = (clear[1] << 24) | (clear[2] << 16) | (clear[3] << 8) | clear[4];
    final chunk = clear[5];
    final parts = clear[6];
    final length = (clear[7] << 8) | clear[8];
    if (parts < 1 || chunk >= parts || length > kEntryPortalPayload) {
      dropped++;
      return true;
    }

    switch (op) {
      case EntryPortalOp.request:
        // Two caps. The own record is public, but a
        // sender that asks in a loop should not be served in a
        // loop — and MANY senders should not let the
        // table grow arbitrarily.
        _windowCheck();
        // The total cap FIRST: it is the one that limits the table.
        // If it stood behind the cap per sender, every new
        // address would get an entry beforehand.
        if (_servedTotal >= maxAnswersPerWindow) {
          rejectedWindow++;
          dropped++;
          return true;
        }
        final n = _served[fromHost] ?? 0;
        if (n >= maxAnswersPerPeer) {
          rejectedSource++;
          dropped++;
          return true;
        }
        _served[fromHost] = n + 1;
        _servedTotal++;
        // ── WHAT THROWS HERE KILLS THE PROCESS ──────────────────────
        //
        // This function runs from a socket callback (`LinkDemux`
        // from the stream of `UdpSocketSet`); there is no caller that
        // could catch anything. `V41Node.ownEntry` demonstrably THROWS —
        // on 28.08. a phone with eight address families threw exactly there
        // `Invalid argument(s): hoechstens vier Adressen` and took
        // the entry handler down with it. A node that cannot issue its
        // own record right now does not answer
        // — it does not die.
        try {
          final answer = _build(EntryPortalOp.response, request,
              ownRecord().encode(), _key());
          for (final e in answer) {
            sendUnit(e, fromHost, fromPort);
          }
          answered++;
        } catch (_) {
          dropped++;
        }
        return true;

      case EntryPortalOp.response:
        _cleanUp();
        final k = '$fromHost:$fromPort/$request';
        var build = _construct[k];
        if (build == null) {
          // The oldest gives way. A cap that does nothing when reached
          // is none. NOT in a `putIfAbsent` factory: changing the
          // map during `putIfAbsent` is in Dart a
          // `ConcurrentModificationError`.
          if (_construct.length >= maxPendingReassemblies) {
            _construct.remove(_construct.keys.first);
          }
          build = _PartialBuild(parts, now());
          _construct[k] = build;
        }
        if (build.parts != parts) {
          dropped++;
          return true;
        }
        build.assign(chunk, Uint8List.sublistView(clear, _headerLen, _headerLen + length));
        final whole = build.done();
        if (whole == null) return true;
        _construct.remove(k);
        final read = EntryRecord.decodeAt(whole, 0);
        if (read == null) {
          // Position does not match the keys, or the signature
          // does not hold. Exactly here a lie gets noticed.
          dropped++;
          return true;
        }
        // THE HINT IS RESOLVED — no second attempt anymore.
        // After the authenticity check, not before: a datagram that
        // cannot be read as a valid record must not kill the
        // retry attempt (otherwise junk to the right source address
        // would suffice for a disruptor).
        markResolved(hintKey(fromHost, fromPort));
        for (final a in read.record.addresses) {
          markResolved(hintKey(a.host, a.port));
        }
        onRecord(read.record);
        return true;

      default:
        dropped++;
        return true;
    }
  }

  void _cleanUp() {
    final current = now();
    _construct.removeWhere(
        (_, b) => current.difference(b.started) > reassemblyLifetime);
  }

  Uint8List _key() =>
      EntryPortalKey.forHour(channel, EntryPortalKey.hourOf(now()));

  /// Opens a unit under the current hour and its two
  /// neighbours.
  ///
  /// ALL THREE ALWAYS, without early exit — the same rule as
  /// `LinkMac.verifyInitMac`: a loop that returns at the first hit
  /// takes a different time depending on the epoch hit,
  /// and the difference is measurable from outside.
  Uint8List? _open(Uint8List unit) {
    final h = EntryPortalKey.hourOf(now());
    final nonce = Uint8List.sublistView(unit, 0, _nonceLen);
    final ct = Uint8List.sublistView(unit, _nonceLen);
    Uint8List? hit;
    for (var d = -1; d <= 1; d++) {
      final key = EntryPortalKey.forHour(channel, h + d);
      Uint8List? clear;
      try {
        clear = SodiumFFI().aesGcmDecrypt(ct, key, nonce);
      } catch (_) {
        clear = null;
      }
      if (clear != null && clear.length == _plainLen && hit == null) {
        hit = clear;
      }
    }
    return hit;
  }

  /// Builds the units into a payload. Always at least one.
  static List<Uint8List> _build(
      int op, int request, Uint8List payload, Uint8List key) {
    final parts = payload.isEmpty
        ? 1
        : (payload.length + kEntryPortalPayload - 1) ~/ kEntryPortalPayload;
    final out = <Uint8List>[];
    for (var i = 0; i < parts; i++) {
      final from = i * kEntryPortalPayload;
      final until = (from + kEntryPortalPayload) > payload.length
          ? payload.length
          : from + kEntryPortalPayload;
      final len = until - from;
      // Plaintext ALWAYS full length — the padding is the reason
      // why all units are the same size.
      final clear = Uint8List(_plainLen);
      clear[0] = op;
      clear[1] = (request >> 24) & 0xff;
      clear[2] = (request >> 16) & 0xff;
      clear[3] = (request >> 8) & 0xff;
      clear[4] = request & 0xff;
      clear[5] = i;
      clear[6] = parts;
      clear[7] = (len >> 8) & 0xff;
      clear[8] = len & 0xff;
      if (len > 0) {
        clear.setRange(_headerLen, _headerLen + len, payload, from);
      }
      // RANDOM PADDING, not zeros. It lies under the seal,
      // so it cannot be seen on the wire anyway; it costs nothing and
      // keeps the plaintext without structure even if the seal
      // ever falls.
      //
      // `randomBytes(0)` throws (`SodiumException: length must be > 0`), and
      // a full unit has exactly zero padding — that is the
      // normal case, not the edge case: the first of two fragments of a
      // 1.4 KB record is always full.
      final padLen = _plainLen - _headerLen - len;
      if (padLen > 0) {
        clear.setRange(
            _headerLen + len, _plainLen, SodiumFFI().randomBytes(padLen));
      }
      final nonce = SodiumFFI().randomBytes(_nonceLen);
      final ct = SodiumFFI().aesGcmEncrypt(clear, key, nonce);
      final unit = Uint8List(kEntryUnitSize);
      unit.setRange(0, _nonceLen, nonce);
      unit.setRange(_nonceLen, kEntryUnitSize, ct);
      out.add(unit);
    }
    return out;
  }

}

/// What is remembered about ONE hint. Three fields, fixed size — the
/// state grows with the number of hints (capped by
/// [EntryPortal.maxTrackedHints]) and not with the running time.
final class _HintAttempt {
  _HintAttempt(this.firstTick);

  /// The call tick in which the first attempt went out.
  final int firstTick;

  /// How many requests have already gone out for this hint.
  int attempts = 0;

  /// Whether a genuine record for this hint has arrived.
  bool answered = false;
}

final class _PartialBuild {
  _PartialBuild(this.parts, this.started) : _pieces = List<Uint8List?>.filled(parts, null);

  final int parts;
  final DateTime started;
  final List<Uint8List?> _pieces;

  void assign(int i, Uint8List data) {
    if (i < 0 || i >= parts) return;
    _pieces[i] = Uint8List.fromList(data);
  }

  Uint8List? done() {
    var length = 0;
    for (final s in _pieces) {
      if (s == null) return null;
      length += s.length;
    }
    final out = Uint8List(length);
    var o = 0;
    for (final s in _pieces) {
      out.setRange(o, o + s!.length, s);
      o += s.length;
    }
    return out;
  }
}
