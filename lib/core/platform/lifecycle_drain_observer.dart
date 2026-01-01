import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/platform/share_receiver.dart';
import 'package:cleona/core/platform/deep_link_receiver.dart';

/// Single [WidgetsBindingObserver] that drains pending shares and deep links
/// on [AppLifecycleState.resumed].
///
/// Replaces the per-receiver `SystemChannels.lifecycle.setMessageHandler`
/// pattern that caused handler hijacking (the setter overwrites the previous
/// handler, and also replaces the framework's own lifecycle handler so that
/// [WidgetsBinding.lifecycleState] freezes).
class LifecycleDrainObserver with WidgetsBindingObserver {
  final BuildContext Function() _contextProvider;
  final ICleonaService? Function() _serviceProvider;
  static bool _registered = false;

  /// Cold-start retry cadence. On cold start via share-sheet/deep-link the
  /// service (daemon connection) is practically never ready on the very
  /// first frame yet. `drainPending` no longer consumes the native stash
  /// when the service is null, so it's safe to retry — bounded so this is
  /// NOT unbounded polling (Arbeitsregel #5): 60 attempts * 500ms = 30s max,
  /// timer is guaranteed to cancel once a drain succeeds or the limit hits.
  static const _coldStartRetryInterval = Duration(milliseconds: 500);
  static const _coldStartMaxAttempts = 60;

  LifecycleDrainObserver._(this._contextProvider, this._serviceProvider);

  /// Wire up both share and deep-link draining.
  ///
  /// * Registers a [WidgetsBindingObserver] for resume events (Android + iOS).
  /// * Schedules a bounded, self-cancelling retry loop for cold-start intents
  ///   (the service may not be ready on the first post-frame callback).
  /// * Guarded by [_registered] — safe to call more than once.
  static void register({
    required BuildContext Function() contextProvider,
    required ICleonaService? Function() serviceProvider,
  }) {
    if (!(Platform.isAndroid || Platform.isIOS) || _registered) return;
    _registered = true;
    final obs = LifecycleDrainObserver._(contextProvider, serviceProvider);
    WidgetsBinding.instance.addObserver(obs);
    // Cold-start drain: the intent/share that launched the app is already
    // stashed on the native side — drain it once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      obs._drainColdStartWithRetry();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainAll();
    }
  }

  /// Cold-start entry point: attempts a drain immediately, and if the
  /// service wasn't ready yet, retries on a bounded timer until either a
  /// drain succeeds (service ready) or [_coldStartMaxAttempts] is reached.
  void _drainColdStartWithRetry() {
    var attempts = 0;
    Timer? timer;

    Future<void> attempt() async {
      attempts++;
      final ready = await _drainAll();
      if (ready || attempts >= _coldStartMaxAttempts) {
        timer?.cancel();
      }
    }

    attempt();
    timer = Timer.periodic(_coldStartRetryInterval, (_) => attempt());
  }

  /// Drains both share and deep-link payloads. Returns `true` once the
  /// service was ready for the attempt (regardless of whether a payload was
  /// actually pending), `false` if the service was still null (native
  /// stash left untouched for a later retry).
  Future<bool> _drainAll() async {
    final shareReady = await ShareReceiver.drainPending(_contextProvider, _serviceProvider);
    final deepLinkReady = await DeepLinkReceiver.drainPending(_contextProvider, _serviceProvider);
    return shareReady && deepLinkReady;
  }
}
