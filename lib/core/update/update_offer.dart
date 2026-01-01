import 'dart:async';

import 'package:cleona/core/update/binary_update_manager.dart'
    show BinaryUpdateState;
import 'package:cleona/core/update/update_manifest.dart';

/// The offer of a FINISHED update — separate from collecting.
///
/// ── THE DECISION (owner, 14.09.2026) ─────────────────────────────────
///
/// v4_2 §26.5.4 and §26.6.1 steps 4-6, reminder
/// `project_android_update_flow_v145.md`:
///
/// ```
/// Manifest known → collect + store pieces (automatic, invisible)
///                → complete → assemble → SHA-256 + signature
///                → banner "Update vX.Y.Z bereit" ["Installieren"] [X]
///                → click → installation
/// ```
///
/// ── WHY THIS CLASS EXISTS ─────────────────────────────────────────
///
/// Until S387 `BinaryUpdateState.ready` meant two things: "checked, lies
/// ready" AND — because `ready` only came after the download click — "the user
/// has consented". The daemon therefore installed immediately on `ready`
/// (`service_daemon.dart:946` in `95626215`), the in-process branch likewise
/// (`main.dart:3044`). As soon as collecting runs automatically,
/// the same `ready` would be an installation without consent.
///
/// Here the two halves lie separately: [onState] accepts EVERY
/// state and NEVER installs; installing only happens from [consent],
/// and that is called solely by the click on "Installieren" (daemon: IPC
/// `apply_update`; in-process: `CleonaAppState.applyUpdate`). The probe
/// `test/smoke/smoke_update_angebot.dart` pins both down.
///
/// ── ONE COLLECTOR PER PROCESS ─────────────────────────────────────────────
///
/// A daemon carries N identities, and each has its own service with
/// its own update manager. All read the same manifest. Without selection
/// every identity would collect the same binary — N-fold traffic for one
/// file (working rule 5). Collecting therefore only happens at the [source]
/// that FIRST reports with an in-network-distributed manifest; the
/// states of other sources are not read.
class UpdateOffer<Q extends Object> {
  /// Triggers the automatic collecting for [target]. Returns when
  /// the pass ends — successfully or not; the outcome comes via
  /// [onState].
  final Future<void> Function(Q source, UpdateManifest target) assemble;

  /// Installs the checked, ready update. `true` means: the
  /// installation has been carried out (desktop: the process ends anyway).
  final Future<bool> Function(Q source) install;

  /// Version comparison — `UpdateChecker.isNewer`, passed in, so that
  /// this class needs no logger and no data directory.
  final bool Function(String a, String b) isNew;

  final void Function(String)? report;

  /// `true` as long as fetching is blocked — metered connection
  /// (mobile, metered WLAN). Owner decision 15.09.2026: the update
  /// is not fetched over a metered connection (v4_2 §24.4.2,
  /// §26.6.1 "suspends the fetch path over metered connections"). Synchronous:
  /// the caller holds the last read value and reports every change
  /// via [networkKindChanged]. `null` = never blocked (desktop).
  final bool Function()? fetchLocked;

  Q? _source;
  UpdateManifest? _target;
  BinaryUpdateState _state = BinaryUpdateState.idle;
  bool _collects = false;
  bool _installed = false;
  bool _waitsOnNetwork = false;

  UpdateOffer({
    required this.assemble,
    required this.install,
    required this.isNew,
    this.report,
    this.fetchLocked,
  });

  /// Whether a collection did not begin only because of a metered connection.
  bool get waitsOnNetwork => _waitsOnNetwork;

  /// The EDGE "network kind changed" (S388). If a collection was waiting for an
  /// unmetered connection and it is now there, it begins here — exactly
  /// once. Otherwise nothing happens; no tick, no renewed asking.
  void networkKindChanged() {
    final q = _source;
    final z = _target;
    if (!_waitsOnNetwork || q == null || z == null) return;
    if (fetchLocked?.call() == true) return;
    onManifest(q, z, true);
  }

  /// The EDGE "moment according to M1+" — start, network change, new neighbour, app
  /// opened (v4_2 §8.2 "When the recipient asks", §26.5.4 "Manifest
  /// freshness", §26.6.1 "asks again at the next such moment").
  ///
  /// ── WHAT THIS CLOSES (E-9, owner decision 10 = A of 15.09.2026) ──
  ///
  /// If a collection run ended without a result, until here there was **no
  /// occasion any more to try again**: collecting only happened when a
  /// NEWER manifest came in (`update_manifest_fach.dart` only reports
  /// `folge > vorher`, and `_manifesteVerarbeiten` aborts for the same
  /// version with the same sequence). Until the next restart nobody
  /// collected — measured and described in `S388-BAU-UPDATE.md`,
  /// section 9.
  ///
  /// The occasion is now the edge itself, and **only** it: no timer,
  /// no repetition interval, no deadline. This class contains
  /// no clock, and the guard
  /// `test/smoke/smoke_update_erneut.dart` pins that down.
  ///
  /// **When collecting happens is decided by [onManifest] — no second
  /// version of the same rules stands here.** Without a known target nothing
  /// happens; otherwise the same target is presented once more, and the
  /// conditions there ("the same target, and the last pass ended
  /// without a result") decide. If the update lies `ready` or a
  /// collection is running, nothing goes out.
  ///
  /// That the rules stand only ONCE is measured and not
  /// taste: the first version repeated them here, and the
  /// mutation probe N2 (state check removed) stayed GREEN — the
  /// guard measured the copy, not the rule.
  void againTry() {
    final q = _source;
    final z = _target;
    if (q == null || z == null) return;
    onManifest(q, z, true);
  }

  Q? get source => _source;
  UpdateManifest? get target => _target;
  BinaryUpdateState get state => _state;

  /// Checked and assembled, waiting for the click.
  bool get ready => _state == BinaryUpdateState.ready && _target != null;

  /// Consent is given, the installation is running.
  bool get installedCurrently => _installed;

  /// Whether the banner is visible. One rule for every surface —
  /// daemon GUI and in-process read the same function.
  ///
  /// `switch` without `default`: a new state forces a
  /// decision here, instead of silently slipping through as "invisible" or "visible".
  static bool bannerVisible({
    required BinaryUpdateState state,
    required bool dismissed,
    required bool installedCurrently,
  }) {
    if (installedCurrently) return true;
    if (dismissed) return false;
    switch (state) {
      case BinaryUpdateState.ready:
        return true;
      case BinaryUpdateState.idle:
      case BinaryUpdateState.checking:
      case BinaryUpdateState.downloading:
      case BinaryUpdateState.assembling:
      case BinaryUpdateState.verifying:
      case BinaryUpdateState.failed:
        return false;
    }
  }

  /// A checked manifest has become known. If it is distributed in-network,
  /// collecting begins — without user action.
  ///
  /// * **Newer than the previous target** (Z1, §26.6.1 "A newer manifest
  ///   while collecting"): switch over immediately. If the old target already lay
  ///   ready, it is no longer offered.
  /// * **The same target**, and the last pass ended without a result
  ///   (`idle`/`failed`): collect again. That is "asks again at the next
  ///   such moment" — the manifest comes at exactly these moments.
  /// * **Older**, or the same target is running/lies ready: nothing.
  void onManifest(Q source, UpdateManifest manifest, bool inNetworkDistributed) {
    if (!inNetworkDistributed) return;
    final q = _source ??= source;
    if (!identical(q, source)) return;
    final old = _target;
    final newer = old == null ||
        isNew(manifest.version, old.version) ||
        (!isNew(old.version, manifest.version) &&
            (manifest.minMonotoneSeq ?? 0) > (old.minMonotoneSeq ?? 0));
    if (newer) {
      if (old != null) {
        report?.call('Update: newer manifest v${manifest.version} — '
            'v${old.version} is no longer collected/offered (Z1)');
      }
      _target = manifest;
      _state = BinaryUpdateState.idle;
    } else {
      final equal = !isNew(old.version, manifest.version);
      final withoutResult = _state == BinaryUpdateState.idle ||
          _state == BinaryUpdateState.failed;
      if (!equal || !withoutResult || _collects) return;
    }
    if (fetchLocked?.call() == true) {
      if (!_waitsOnNetwork) {
        report?.call('Update: metered connection — v${_target!.version} is '
            'fetched only over an unmetered one');
      }
      _waitsOnNetwork = true;
      return;
    }
    _waitsOnNetwork = false;
    _collects = true;
    final target = _target!;
    unawaited(Future<void>.sync(() => assemble(q, target)).catchError((Object e) {
      report?.call('Update: collecting v${target.version} aborted: $e');
    }).whenComplete(() {
      if (identical(_target, target)) _collects = false;
    }));
  }

  /// The state of the collection. NEVER installs — not even on `ready`.
  void onState(Q source, BinaryUpdateState state) {
    if (!identical(_source, source)) return;
    _state = state;
  }

  /// The click on "Installieren". Without a checked, ready update,
  /// or while an installation is already running, nothing happens.
  Future<bool> consent() async {
    final q = _source;
    if (q == null || !ready || _installed) {
      report?.call('Update: consent without an update ready '
          '(state ${_state.name}) — nothing installed');
      return false;
    }
    _installed = true;
    try {
      return await install(q);
    } finally {
      _installed = false;
    }
  }
}
