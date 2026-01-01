/// The edge "network change" (§11.8.2) — the one place that decides it.
///
/// §11.8.2 names one edge: "network change — another interface, a new or
/// lost own address, a return from sleep, or the user's 'reconnect'
/// (§25.7)". Until S407-LB-P14 the decision stood above the delivery layer,
/// three times: the daemon's 30-s poll and its `ip monitor` branch, and the
/// app's `connectivity_plus` branch each kept their own last address list,
/// their own settling delay and their own "is it a change?", and the return
/// from sleep sat in the app seam. Each started with an EMPTY list, and an
/// empty list counted as a change — so the first report after the start ran
/// the whole edge for nothing (every neighbour an acquaintance, `searching`,
/// the router asked again): 30 s after the start on Windows and macOS, at
/// the first router advertisement on Linux, at the first connectivity event
/// on a phone (finding A-1).
///
/// What stays outside: the EVENT. A node has no clock for this (`host.dart`,
/// `Host.networkChanged`); the platform tells it that something may have
/// changed — the poll of Windows and macOS, `ip monitor` on Linux,
/// `connectivity_plus` in the app, the heartbeats' wall-clock gap, the
/// user's "reconnect" — and hands in the one entry it runs ([EdgeSteps]).
/// What lies here: the own addresses at the start (the first report is no
/// change), the settling of a burst, the comparison, the return from sleep,
/// and that edges do not overlap — one runs, at most one follows.
library;

import 'dart:async';

import 'package:cleona/core/util/local_addresses.dart'
    show dialableLocalAddresses;

/// The steps of the edge, handed in by whoever owns their consequences
/// (the app seam: the host part, every identity as subscriber, the router,
/// the update moment).
typedef EdgeSteps = Future<void> Function();

/// A burst of address events is one event: the second address of a new
/// network comes a moment after the first (taken over from the daemon's and
/// the app's own delay, S380/P4 — one timer per burst, never periodic).
const Duration kSettle = Duration(seconds: 2);

class NetworkWatch {
  /// The shortest keep-alive interval in force (§8.1), for the return from
  /// sleep ([heartbeat]).
  final Duration Function() _keepAliveInterval;
  final void Function(String)? _report;

  /// The own addresses under which a partner can dial this node — the same
  /// list the node announces (`dialableLocalAddresses`): addresses, no
  /// lifetimes, so a router advertisement that only renews them is no change.
  Future<List<String>> Function() read = dialableLocalAddresses;
  Duration settle = kSettle;

  NetworkWatch(this._keepAliveInterval, {void Function(String)? report})
      : _report = report;

  Future<void>? _baseline;
  List<String> _last = const [];
  Timer? _settleTimer;
  Completer<bool>? _settled;
  EdgeSteps? _settledSteps;
  String _settledReason = '';
  Future<void>? _running;
  EdgeSteps? _follow;
  Completer<void>? _followDone;
  bool _stopped = false;

  /// The addresses this node last acted on.
  List<String> get last => List.unmodifiable(_last);

  /// Whether an edge runs now.
  bool get running => _running != null;

  /// The edge "start": the own addresses as they are, read once (again, if
  /// [read] was replaced). The first report after it compares with them —
  /// it is no change unless the addresses differ.
  Future<void> begin() => _baseline = read().then<void>((a) {
        _last = a;
      }, onError: (Object _) {/* none known: the first event decides */});

  /// A platform event ([reason] for the log): something may have changed.
  /// After [settle] without a further event the addresses are read; differ
  /// they from [last], the edge runs through [steps] ([run]). Completes with
  /// whether it did; every event of the same burst gets the same answer.
  Future<bool> nudge(String reason, EdgeSteps steps) {
    if (_stopped) return Future.value(false);
    final done = _settled ??= Completer<bool>();
    _settledSteps = steps;
    _settledReason = reason;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, _decide);
    return done.future;
  }

  Future<void> _decide() async {
    final done = _settled!;
    final steps = _settledSteps!;
    final reason = _settledReason;
    _settled = null;
    _settledSteps = null;
    _settleTimer = null;
    await _baseline;
    List<String> now;
    try {
      now = await read();
    } catch (_) {
      now = _last; // an enumeration during the change itself — no decision
    }
    if (_stopped || _same(now, _last)) {
      done.complete(false);
      return;
    }
    _report?.call('Network change detected ($reason) — addresses: '
        '${_last.join(',')} → ${now.join(',')}');
    _last = now;
    unawaited(run(reason, steps));
    done.complete(true);
  }

  /// The heartbeat's question (daemon and in-process app, every [period]):
  /// the wall clock moved [gap] since the last tick. Away (`gap - period`)
  /// longer than the keep-alive interval, the process returned from sleep
  /// (S407-LB-P13): the edge runs through [steps]. Returns whether it did.
  /// The heartbeat ran before; no clock is added here.
  bool heartbeat(
      {required Duration gap,
      required Duration period,
      required EdgeSteps steps}) {
    final keepAlive = _keepAliveInterval();
    if (_stopped || !isReturnFromSleep(
        gap: gap, period: period, keepAlive: keepAlive)) {
      return false;
    }
    _report?.call('Return from sleep — away ${(gap - period).inSeconds} s, '
        'longer than the keep-alive interval ${keepAlive.inSeconds} s (§8.1)');
    unawaited(run('return from sleep', steps));
    return true;
  }

  /// Runs the edge through [steps] ([reason] for the log) — at once if none
  /// runs; otherwise ONE edge follows the running one, and every request
  /// that comes before it starts is folded into it. The running edge read
  /// the interfaces at its start (§11.8.2); what changed after that needs
  /// exactly one more run, not one per request. Completes when the edge
  /// that covers this request has ended.
  Future<void> run(String reason, EdgeSteps steps) {
    if (_stopped) return Future.value();
    if (_running == null) return _running = _loop(reason, steps);
    final pending = _followDone;
    if (pending != null) {
      _report?.call('Network change ($reason) folded into the following one');
      return pending.future;
    }
    _report?.call('Network change ($reason) follows the running one');
    _follow = steps;
    return (_followDone = Completer<void>()).future;
  }

  Future<void> _loop(String reason, EdgeSteps first) async {
    EdgeSteps? steps = first;
    Completer<void>? done;
    while (steps != null && !_stopped) {
      try {
        _last = await read();
      } catch (_) {/* the edge itself reads them again */}
      try {
        await steps();
      } catch (e) {
        _report?.call('Network change failed: $e');
      }
      done?.complete();
      steps = _follow;
      done = _followDone;
      _follow = null;
      _followDone = null;
    }
    done?.complete();
    _running = null;
  }

  /// On stopping the host: a settling event is dropped, nothing new starts.
  void stop() {
    _stopped = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    _settled?.complete(false);
    _settled = null;
    _followDone?.complete();
    _follow = null;
    _followDone = null;
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && a.join(',') == b.join(',');
}

/// Whether a heartbeat that ticks every [period] and found [gap] on the
/// wall clock since its last tick saw a return from sleep: the process was
/// away (`gap - period`) longer than [keepAlive] (S407-LB-P13).
///
/// The wall clock, because it counts a suspend on every platform; the
/// monotonic clock behind Dart's timers stops during suspend on
/// Linux/Android/macOS/iOS. A wall clock set back gives a negative gap and
/// is no sleep. The threshold is the keep-alive interval (§8.1): away
/// longer, the paths it holds open are no longer guaranteed, which is the
/// premise of the edge ("every neighbour becomes an acquaintance"); a GC
/// pause or a short stall stays below.
bool isReturnFromSleep(
        {required Duration gap,
        required Duration period,
        required Duration keepAlive}) =>
    gap - period > keepAlive;
