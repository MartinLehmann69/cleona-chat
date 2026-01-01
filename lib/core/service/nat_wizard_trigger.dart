// ignore_for_file: public_member_api_docs
/// NAT-Troubleshooting-Wizard trigger state machine (§27.9.1).
///
/// Evaluated on a 1-minute tick from CleonaService. The wizard event fires
/// once per daemon process when ALL five conditions hold simultaneously for
/// ≥10 minutes of continuous uptime:
///
/// 1. `NetworkStats.directConnections == 0` while `activePeerCount > 0`
/// 2. `NetworkStats.upnpStatus ∈ {unavailable, rejected}`
/// 3. `NetworkStats.pcpStatus == failed`
/// 4. Not behind CGNAT (external IPv4 not in `100.64.0.0/10` or `192.0.0.0/24`)
/// 5. Not dismissed: `now >= nat_wizard_dismissed_until`
///
/// The 10-minute window tracks *continuous* satisfaction. If any condition
/// drops even for one tick, the anchor resets to null and the window restarts
/// as soon as all five are true again.
///
/// The trigger is disabled (`_alreadyFired = true`) after the first fire so
/// oscillating signals never re-show the dialog within the same process.
///
/// Dismissal persistence is intentionally kept out of this class — the owning
/// service reads `nat_wizard_dismissed_until` from its settings file and
/// provides the `dismissedUntilMs` signal. This keeps the trigger class pure
/// and trivial to unit-test.
library;

import 'dart:async';

import 'package:cleona/core/network/network_stats.dart';

/// Snapshot of all signals the trigger needs on every tick. Pass-by-value so
/// the trigger is stateless w.r.t. I/O and trivially testable — tests just
/// construct synthetic snapshots.
class NatWizardSignals {
  /// Live network stats (provides direct/UPnP/PCP signals).
  final NetworkStats stats;

  /// Current external IPv4 (from ipify / UPnP GetExternalIPAddress). Null if
  /// unknown. If null, we cannot prove CGNAT → trigger conservatively assumes
  /// non-CGNAT (so the wizard can still fire; CGNAT check is about *avoiding*
  /// a pointless wizard, not about gating the check).
  final String? externalIpv4;

  /// Unix-ms until which the wizard is suppressed. 0 (or past) = not dismissed.
  /// `double.maxFinite` style = forever.
  final int dismissedUntilMs;

  /// Current process uptime in seconds. The trigger fires only once overall
  /// uptime is >= 10 minutes AND the window anchor has held for 10 minutes —
  /// this prevents false positives during boot-up when UPnP discovery is
  /// still in progress.
  final int uptimeSeconds;

  const NatWizardSignals({
    required this.stats,
    required this.externalIpv4,
    required this.dismissedUntilMs,
    required this.uptimeSeconds,
  });
}

/// Pure state-machine. Driven by an external tick (the real service uses
/// `Timer.periodic(Duration(minutes: 1), ...)`).
class NatWizardTrigger {
  /// How long all conditions must hold continuously before the event fires.
  /// Default is 10 min per §27.9.1 — overridable for tests.
  final Duration holdWindow;

  /// Pulls the current signals on each tick. Kept as a callback so the owning
  /// service can assemble stats+externalIp+dismissedUntil+uptime atomically.
  final NatWizardSignals Function() getSignals;

  /// Fired once when all conditions have held for the full window. Replaces
  /// the `onNatWizardTriggered` callback exposed on the service interface.
  final void Function() onTrigger;

  /// True after the first fire. Stays true for the rest of the process —
  /// per §27.9.1 the dialog must not re-show itself on oscillating signals.
  bool _alreadyFired = false;
  bool get hasFired => _alreadyFired;

  /// First tick on which the conditions were all true in a row. Null while
  /// any condition is violated.
  int? _anchorUptimeSeconds;
  int? get anchorUptimeSecondsForTesting => _anchorUptimeSeconds;

  Timer? _timer;

  NatWizardTrigger({
    required this.getSignals,
    required this.onTrigger,
    this.holdWindow = const Duration(minutes: 10),
  });

  /// Start the 1-minute periodic tick. Safe to call repeatedly (no-op if
  /// already started). The trigger does not auto-evaluate on the zeroth tick;
  /// the first evaluation happens after the first timer interval.
  void start({Duration tickInterval = const Duration(minutes: 1)}) {
    if (_timer != null) return;
    _timer = Timer.periodic(tickInterval, (_) => evaluate());
  }

  /// Stop the tick. Safe to call multiple times. The [_alreadyFired] latch is
  /// intentionally preserved — restarting an evaluator that already fired
  /// still won't re-fire.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Evaluate once synchronously. Public for tests — they can drive the
  /// trigger by repeatedly calling evaluate() with advancing uptime values
  /// instead of waiting for wall-clock timers.
  void evaluate() {
    if (_alreadyFired) return;

    final signals = getSignals();

    // Condition 5: dismissed?
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (signals.dismissedUntilMs > nowMs) {
      _anchorUptimeSeconds = null;
      return;
    }

    final stats = signals.stats;

    // Condition 1: 0 direct connections while we DO have active peers
    // (otherwise we are simply offline — not a NAT problem).
    final cond1 = stats.directConnections == 0 && stats.activePeerCount > 0;

    // Condition 2: UPnP state is unavailable or rejected (not ok, not unknown)
    final cond2 = stats.upnpStatus == UpnpStatus.unavailable ||
        stats.upnpStatus == UpnpStatus.rejected;

    // Condition 3: PCP explicitly failed (not ok, not unknown)
    final cond3 = stats.pcpStatus == PcpStatus.failed;

    // Condition 4: not behind CGNAT. If externalIpv4 is null we conservatively
    // assume non-CGNAT so the wizard can still fire. The downstream wizard UI
    // re-checks CGNAT before showing manual-forwarding instructions anyway.
    final cond4 = !_isCgnat(signals.externalIpv4);

    final allTrue = cond1 && cond2 && cond3 && cond4;
    if (!allTrue) {
      _anchorUptimeSeconds = null;
      return;
    }

    // All conditions true — start/continue the hold window.
    _anchorUptimeSeconds ??= signals.uptimeSeconds;

    final held = signals.uptimeSeconds - _anchorUptimeSeconds!;
    if (held >= holdWindow.inSeconds) {
      _alreadyFired = true;
      // Invoke outside the state update so an exception from onTrigger does
      // not leave us in an inconsistent state (we have already latched).
      onTrigger();
    }
  }

  /// `100.64.0.0/10` or `192.0.0.0/24` → CGNAT. Keep local so this file has
  /// no dependency on network-layer internals (the private helper in
  /// peer_info.dart is not exported). Covers the same ranges — verified
  /// against §27.9.1 item 4 and the existing peer_info `_isCgnat`.
  static bool _isCgnat(String? ip) {
    if (ip == null || ip.isEmpty) return false;
    if (ip.startsWith('100.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 64 && second <= 127) return true;
      }
    }
    if (ip.startsWith('192.0.0.')) return true;
    return false;
  }
}
