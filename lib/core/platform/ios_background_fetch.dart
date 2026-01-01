import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:cleona/core/crypto/key_migration.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/mycelium_seam.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:mycelium/host.dart';

/// iOS Background Fetch integration via BGTaskScheduler (Architecture S12.5).
///
/// Communicates with the native Swift `BackgroundFetchHandler` via
/// `MethodChannel('cleona/background_fetch')`. The Dart side handles the
/// heavy P2P work (node startup, peer contact, message retrieval, decryption),
/// while the Swift side manages OS task lifecycle and local notifications.
///
/// NO APNs, NO Firebase, NO push -- pure OS-controlled pull.
class IosBackgroundFetch {
  static const _channel = MethodChannel('cleona/background_fetch');

  /// Whether a background fetch is currently in progress.
  static bool _isFetching = false;

  /// Public accessor so _initInProcess can wait for a running fetch to finish.
  static bool get isFetching => _isFetching;

  // -- THE FOREGROUND LOCK (F-8, S370) -------------------------------
  //
  // WHAT IT PROTECTS AGAINST, measured: foreground (`main.dart:_initInProcess`)
  // and wake-up (below) BOTH call `startV41Node` on THE SAME port
  // (`firstId.port` — until S374 `firstId.port + 1`, the offset was dropped on
  // both paths together). Without the lock
  // two nodes bind the same UDP port. `UdpSocketSet.open` leaves
  // `reuseAddress` at Dart's default `true` (`link_io/udp_sockets.dart:166`,
  // expressly justified there as load-bearing) -- the second bind thus does
  // not necessarily fail, but can succeed, and then
  // two receivers share one port. The lock is thus justified.
  //
  // WHAT WAS WRONG ABOUT IT: it was a bare `static bool`, set to `true` by
  // `main.dart` from outside and 121 lines later to `false` from
  // outside -- without `finally`. Between the two lines lay three
  // throw paths. If one throws, the lock stands for the ENTIRE
  // process lifetime, the wake-up leaves every run immediately with
  // `messageCount: 0`, Swift acknowledges `success: true` and reschedules: a
  // chain that runs, acknowledges and reschedules, but fetches nothing.
  //
  // HENCE TWO CHANGES, not one:
  //
  //  (1) The hold is only taken via [guardForegroundInit]. The
  //      release stands there in a `finally` and thus falls on EVERY
  //      exit -- throw, early return, regular end.
  //
  //  (2) The hold carries a DEADLINE. A `finally` covers throw and
  //      return, but structurally NOT the third case: a
  //      HANG in the held section (`startV41Node`,
  //      `service.startService()` -- both network I/O). Without a deadline a
  //      single hang would again be permanent silence. With a deadline it costs the
  //      wake-ups within the deadline and no more.
  //
  // ERROR DIRECTION: the lock deliberately fails OPEN. If the hold expires
  // or a concurrent second foreground run releases it too early,
  // a wake-up may start; if its bind fails, the
  // `catch` below catches that and the run ends with 0 messages. That is ONE
  // lost wake-up. If on the other hand it fails closed, ALL
  // wake-ups are lost, and invisibly so. The lock protects a
  // port, not a security statement -- that is why open is the right
  // direction. (This is not a silent mode change in the sense of the
  // secure/speed rule: nothing is sealed more weakly in secret here,
  // but a port conflict is risked.)
  //
  // NOT MEASURED, because there is no Apple machine here: whether a second
  // bind on the same port succeeds under iOS (BSD usually requires for unicast
  // `SO_REUSEPORT`, not `SO_REUSEADDR`) or ends with
  // EADDRINUSE. Both outcomes are silent, both are prevented by this
  // lock; which one it is only a device run will clarify.
  static DateTime? _foregroundInitSince;

  /// The deadline after which a hold lapses by itself.
  ///
  /// 180 s. The justification is a calculation, not a round number: the
  /// longest BOUNDED path in the held section is the wait loop
  /// for a running wake-up (60 x 500 ms = 30 s, `main.dart`)
  /// plus three start attempts of the node with a 2 s pause each (4 s). Everything
  /// above that is not a slow but a hanging run. 180 s lies
  /// far above the healthy case and far below "process lifetime".
  @visibleForTesting
  static Duration foregroundInitLease = const Duration(seconds: 180);

  /// How often the gate grip in `_performBackgroundFetch` rejected a wake-up,
  /// and how often one got past it.
  ///
  /// These two counters stand in the production code because a guard that
  /// only sets and reads back the state switch measures a STAND-IN:
  /// it does not prove that the background path is actually
  /// run through. `test/smoke/smoke_ios_background_fetch_guard.dart`
  /// drives the real MethodChannel handler and reads off here on which
  /// side of the gate it came out.
  @visibleForTesting
  static int gateSkipCount = 0;
  @visibleForTesting
  static int pastGateCount = 0;

  /// Whether a foreground run is currently holding the hold.
  ///
  /// READ-ONLY. The hold is taken exclusively via [guardForegroundInit]
  /// -- a field settable from outside was exactly the finding. The
  /// access also checks the deadline and clears an expired hold in the process,
  /// so that a hang does not block permanently.
  static bool get foregroundInitInProgress {
    final since = _foregroundInitSince;
    if (since == null) return false;
    if (DateTime.now().difference(since) >= foregroundInitLease) {
      _foregroundInitSince = null;
      debugPrint('[ios-bg-fetch] foreground hold expired (deadline of '
          '${foregroundInitLease.inSeconds}s exceeded) -- the '
          'wake-up run may run again');
      return false;
    }
    return true;
  }

  /// Executes [body] under the foreground lock and releases it on EVERY
  /// exit.
  ///
  /// The `finally` is the core of this fix: `main.dart:_initInProcess`
  /// had not a single one across 349 lines, and the release stood as an
  /// ordinary assignment in the middle of the flow.
  ///
  /// The hold is SIMPLE, not counted: if a second
  /// foreground setup starts concurrently, its end also releases the hold of the first.
  /// That is deliberate -- two concurrent `_initInProcess`
  /// are not a viable state anyway (both bind the same port),
  /// and the error direction "open" is justified above.
  static Future<T> guardForegroundInit<T>(Future<T> Function() body) async {
    _foregroundInitSince = DateTime.now();
    try {
      return await body();
    } finally {
      _foregroundInitSince = null;
    }
  }

  /// Releases the hold before [guardForegroundInit] returns.
  ///
  /// The foreground setup may allow the wake-up again as soon as
  /// the V4.1 node has its port -- the service loop afterwards binds
  /// nothing more. The `finally` wrapper releases the same hold again later;
  /// that is a no-op and expressly desired, because a
  /// NOT released hold is the expensive state.
  static void releaseForegroundInitEarly() {
    _foregroundInitSince = null;
  }

  /// Initialize the MethodChannel handler. Called once during app startup
  /// from `_initInProcessBody()` in `main.dart` (Android, iOS and macOS
  /// share the path; only iOS registers). Sets up the
  /// handler for incoming `performBackgroundFetch` calls from the native side.
  static void init() {
    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[ios-bg-fetch] MethodChannel handler registered');
  }

  /// Schedule the next background fetch via the native side.
  /// Called when the app transitions to background (AppLifecycleState.paused).
  static Future<void> scheduleBackgroundFetch() async {
    try {
      await _channel.invokeMethod('scheduleBackgroundFetch');
      debugPrint('[ios-bg-fetch] Scheduled background fetch');
    } catch (e) {
      debugPrint('[ios-bg-fetch] Failed to schedule: $e');
    }
  }

  // -- `cancelBackgroundFetch` HAS BEEN REMOVED (F-8, S370) -----------------
  //
  // It had zero callers (already listed in `S367-verdrahtung-und-luecken.md`
  // as `own=0 test=0`), and with it
  // `AppDelegate.handleMethodCall case "cancelBackgroundFetch"` and
  // `BackgroundFetchHandler.cancelPendingTasks()` have fallen -- caller and
  // callee together. The channel message `cancelBackgroundFetch`
  // thus no longer exists on either side.
  //
  // ACCORDING TO THE OWNER RULE ("no caller and still needed ->
  // wiring gap; really dead -> clear away; only if NO code
  // is missing may uncalled code go") it first had to be measured whether
  // code is missing. None is:
  //
  //  * Architecture v3_0 §12.5 describes an enqueue CHAIN (register,
  //    enqueue at start, re-enqueue after every task, enqueue on the
  //    switch into the background) and NO cancellation. A
  //    pending task is exactly what is wanted in healthy operation.
  //  * The one state in which a cancellation would make sense -- no
  //    identity left --, is not reachable at all on iOS:
  //    `deleteIdentityAndroid` (`main.dart:2883`, on iOS the same
  //    in-process branch) expressly rejects deleting the LAST identity
  //    (`if (_inProcessServices.length <= 1) return
  //    false;`). An identity-less app does not exist after setup.
  //  * And even then the damage would be small: a wake-up without
  //    identity turns back immediately (below, "No identities, aborting"), even
  //    before any node start and before the time window.
  //
  // WHAT WOULD BRING IT BACK: if the last identity becomes deletable,
  // or if `FirstStartWipe.wipeBeforeRecovery` demonstrably collides with
  // a running wake-up. Neither is the case today;
  // the second is also not measurable on this machine.

  /// Handle incoming method calls from the native Swift side.
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'performBackgroundFetch':
        final args = call.arguments as Map<Object?, Object?>?;
        final taskType = (args?['taskType'] as String?) ?? 'refresh';
        return _performBackgroundFetch(taskType: taskType);
      default:
        throw MissingPluginException('Unknown method: ${call.method}');
    }
  }

  /// Execute the background fetch: start a minimal node, contact known peers,
  /// retrieve pending messages, and return results to the native side.
  ///
  /// [taskType] is "refresh" (BGAppRefreshTask, ~30s window, peer budget 3)
  /// or "processing" (BGProcessingTask, minutes-long window, peer budget 10).
  ///
  /// Returns a map: {messageCount: int, senderNames: [String], previews: [String]}
  ///
  /// ── THE WAKE-UP CHAIN, SWITCHED TO V4.1 (CUT, 31.08.) ───────────────
  ///
  /// The old chain had nine stages and was V3: load stored routing state,
  /// `CleonaNode.startQuick()`, radio a BUDGETED number of known
  /// peers, collect store-and-forward, collect Reed-Solomon fragments,
  /// decrypt, `saveNetworkState()`, close socket.
  ///
  /// THIS PATH HAD NEVER SEEN V4.1 — re-measured: neither
  /// `startV41Node` nor `attachV41` occurred in this file. It started
  /// a pure V3 node until the very end. With the CUT it has a network
  /// at all for the first time.
  ///
  /// The new chain is shorter, because V4.1 does not know collecting as a
  /// step: the `SlotDriver` in the `V41Node` harvests on its own tick as soon as
  /// the node stands. There is nothing to radio and no peer budget —
  /// the number `peerContactBudget` has therefore been dropped without replacement
  /// and not reinterpreted to some V4.1 term.
  ///
  ///  1. Load identities + contexts
  ///  2. Start V4.1 node (`startV41Node` — entry store from the
  ///     disk, LAN call, external rendezvous)
  ///  3. Per identity build a service and `attachV41`
  ///  4. Wait out the time window — the harvest runs by itself
  ///  5. Collect newly added unread messages
  ///  6. Save state
  ///  7. Shut down node (including LAN entry and debounce timer)
  ///  8. Result to the native side (which schedules the next run)
  static Future<Map<String, dynamic>> _performBackgroundFetch({
    String taskType = 'refresh',
  }) async {
    if (_isFetching || foregroundInitInProgress) {
      gateSkipCount++;
      debugPrint('[ios-bg-fetch] Skipping: _isFetching=$_isFetching, '
          'foregroundInit=$foregroundInitInProgress');
      return {'messageCount': 0, 'senderNames': <String>[], 'previews': <String>[]};
    }
    // From here the wake-up is ENTERED, not just built. The guard
    // `smoke_ios_background_fetch_guard.dart` reads exactly this boundary --
    // a test that only sets and reads `foregroundInitInProgress` would
    // never cross it and would measure a stand-in.
    pastGateCount++;

    final isProcessing = taskType == 'processing';
    // BGProcessingTask gives minutes; BGAppRefreshTask ~30s (20s effective).
    final waitSeconds = isProcessing ? 120 : 20;

    _isFetching = true;
    debugPrint('[ios-bg-fetch] Starting background fetch '
        '(type=$taskType, wait=${waitSeconds}s)...');

    final services = <CleonaService>[];
    // The ONE mycelium host of this wake-up (S387) — declared before the try,
    // so that the finally block can stop it. It holds the
    // wire and the state checker; a host not stopped would keep
    // the Dart VM alive, and iOS only ends the run when it reports.
    Host? host;
    final newMessages = <_FetchedMessage>[];

    try {
      // Step 1: load identities and contexts
      final mgr = IdentityManager();
      final identities = mgr.loadIdentities();
      if (identities.isEmpty) {
        debugPrint('[ios-bg-fetch] No identities, aborting');
        return {'messageCount': 0, 'senderNames': <String>[], 'previews': <String>[]};
      }

      final masterSeed = mgr.loadMasterSeed();
      // `final firstId = identities.first;` was dropped with S374 — the
      // port now comes from the DEVICE (§11), not from the first
      // identity, and that was the only reader here.
      final baseDir = '${AppPaths.home}/.cleona';

      // ── THE MIGRATION HERE TOO (S362) ──────────────────────────
      //
      // This wake-up does NOT call `IdentityContext.initCrypto` —
      // it builds the contexts directly. The device-wide stores
      // (`node_keys`, `v41_entries.json`, `v41_ages.json`) lay until
      // S362 under the legacy `db.key`; without this call the
      // derived key below would not open the store. The node
      // would start (`NodeKeys` heals itself), but would begin
      // EVERY wake-up at stage 2 of the cascade — in a
      // 20-second window on mobile data regularly a failure,
      // exactly what the stored store was built against.
      // Repeatable and a no-op as soon as the files have migrated.
      KeyMigration.migrateDeviceScopedFiles(baseDir);

      // Create identity contexts for all identities
      final contexts = <String, IdentityContext>{};
      for (final id in identities) {
        final ctx = IdentityContext(
          profileDir: id.profileDir,
          displayName: id.displayName,
          networkChannel: activeNetworkChannel.name,
          hdIndex: id.hdIndex,
          masterSeed: masterSeed,
          createdAt: id.createdAt,
          isAdult: id.isAdult,
        );
        await ctx.initKeys();
        id.nodeIdHex = ctx.userIdHex;
        contexts[ctx.userIdHex] = ctx;
      }

      // Step 2: one service per identity, started.
      //
      // THE PORT IS THE SAME AS IN THE FOREGROUND (`main.dart`): the port
      // of the DEVICE (S374, §11), with 4443 as substitute for one not yet
      // assigned. `_isFetching` and `foregroundInitInProgress` above
      // prevent parallel operation exactly for that reason — both paths bind
      // the same port.
      final gp = IdentityManager().deviceDataPort;
      final devicesPort = gp <= 0 ? 4443 : gp;
      for (final ctx in contexts.values) {
        final service = CleonaService(
          identity: ctx,
          displayName: ctx.displayName,
          port: devicesPort,
        );
        await service.startService();
        services.add(service);
      }

      // Step 3: the ONE mycelium host with one mailbox per identity
      // (S387, replaces `startV41Node` + `attachV41` per identity). The
      // services stand BEFORE: the host collects immediately on start, and
      // an arrival at a service without loaded conversations would be an
      // acknowledged but lost message. If one forgot this
      // step, the wake-up would run through and report zero messages
      // — the most expensive outcome this function can have.
      host = await hostStart(
        services: services,
        baseDir: baseDir,
        key: hostKey(baseDir, masterSeed),
        port: devicesPort,
        report: (m) => debugPrint('[ios-bg-fetch][mycelium] $m'),
      );
      debugPrint('[ios-bg-fetch] mycelium host on port ${host.port}');

      // The port mapping (task D, §7.3): triggered, NOT
      // awaited — the 20/120 s window of this wake-up is far
      // shorter than the worst RFC 6886 backoff (eight and a half
      // minutes); [step 7] tears it down below nonetheless.
      unawaited(() async {
        try {
          await portMappingToEdge(
            host!,
            baseDir: baseDir,
            key: hostKey(baseDir, masterSeed),
            report: (m) => debugPrint('[ios-bg-fetch][mycelium] $m'),
          );
        } catch (e) {
          debugPrint('[ios-bg-fetch] port mapping: $e');
        }
      }());

      // Record baseline unread counts per conversation
      final baselineUnread = <String, Map<String, int>>{};
      for (final service in services) {
        final counts = <String, int>{};
        for (final entry in service.conversations.entries) {
          counts[entry.key] = entry.value.unreadCount;
        }
        baselineUnread[service.nodeIdHex] = counts;
      }

      // Step 4: wait out the window. In V3 peers were
      // radioed here; in V4.1 there is nothing to do — the `SlotDriver` in the
      // node harvests on its own tick, and the effort lies
      // in giving it time.
      // BGAppRefreshTask: ~30 s window → 20 s. BGProcessingTask: minutes → 120 s.
      debugPrint('[ios-bg-fetch] Waiting for message retrieval (${waitSeconds}s)...');
      await Future<void>.delayed(Duration(seconds: waitSeconds));

      // Step 5: collect the newly added unread ones
      for (final service in services) {
        final baseline = baselineUnread[service.nodeIdHex] ?? {};
        for (final entry in service.conversations.entries) {
          final convId = entry.key;
          final conv = entry.value;
          final previousUnread = baseline[convId] ?? 0;
          final newCount = conv.unreadCount - previousUnread;
          if (newCount > 0) {
            // S366, stage B: without this call `conv.messages` carries
            // only the youngest message. If that is outgoing,
            // `incomingMsgs` would be EMPTY — although `newCount > 0` just says
            // that unread messages have been added. The user would then get
            // no notification and would not know why.
            service.ensureLoaded(convId);
            // Get the latest incoming messages
            final incomingMsgs = conv.messages
                .where((m) => !m.isOutgoing)
                .toList();
            if (incomingMsgs.isNotEmpty) {
              final latest = incomingMsgs.last;
              newMessages.add(_FetchedMessage(
                senderName: conv.displayName,
                preview: _messagePreview(latest),
              ));
            }
          }
        }
      }

      debugPrint('[ios-bg-fetch] Found ${newMessages.length} new message(s)');

      // Step 6: save state.
      //
      // `host.saveNetworkState()` (the V3 routing table) has been dropped.
      // The V4.1 counterpart — the entry store and the age of the
      // peers — is saved by `startV41Node` itself, debounced via the
      // `entryPersist` timer; there is nothing to catch up here.
      for (final service in services) {
        service.saveState();
      }

    } catch (e, stack) {
      debugPrint('[ios-bg-fetch] Error: $e\n$stack');
    } finally {
      // Step 7: stop the host FIRST, then the services. The other way round
      // the still running host would deliver to an already stopped service —
      // an acknowledged message that nobody stores any more. `stop`
      // saves the neighbours and closes the wire; an open wire
      // or state checker would keep the Dart VM alive, and iOS only ends
      // the run when it reports.
      // The port mapping torn down FIRST (task D): its own
      // renewal timer otherwise keeps the Dart VM alive, independently
      // of the wire that `stop()` closes right away — the same
      // consideration as for the wire itself, two lines below.
      final hostBeforeTheStop = host;
      if (hostBeforeTheStop != null) {
        try {
          await portMappingLayDown(hostBeforeTheStop);
        } catch (_) {}
      }
      try {
        host?.stop();
      } on SocketException catch (_) {}
      for (final service in services) {
        try {
          await service.stop();
        } catch (_) {}
      }
      _isFetching = false;
      debugPrint('[ios-bg-fetch] Background fetch complete');
    }

    // Step 8: result to the native side (which schedules the next
    // run and posts the notifications)
    final totalCount = newMessages.length;
    return {
      'messageCount': totalCount,
      'senderNames': newMessages.map((m) => m.senderName).toList(),
      'previews': newMessages.map((m) => m.preview).toList(),
    };
  }

  // ── `_routeInfraFrame` HAS BEEN REMOVED (CUT, 31.08.) ─────────────────
  //
  // It was a switch over four `MessageTypeV3` selectors
  // (FRAGMENT_RETRIEVE_RESPONSE, PEER_RETRIEVE_RESPONSE, FRAGMENT_STORE,
  // PEER_STORE) to four `CleonaService` handlers, all of which lay in
  // `cleona_service_v3_fragments.dart` or `_sf.dart`. Caller
  // (`host.wireReceive`) and callees have fallen together.

  /// Generate a short preview string from a message.
  static String _messagePreview(dynamic msg) {
    try {
      final text = msg.text as String?;
      if (text != null && text.isNotEmpty) {
        return text.length > 100 ? '${text.substring(0, 100)}...' : text;
      }
      // Fallback for media messages
      if (msg.mediaPath != null) return '[Media]';
      if (msg.isVoiceMessage == true) return '[Sprachnachricht]';
      return '[Nachricht]';
    } catch (_) {
      return '[Nachricht]';
    }
  }
}

/// Internal helper to collect fetched message info for notification posting.
class _FetchedMessage {
  final String senderName;
  final String preview;

  _FetchedMessage({required this.senderName, required this.preview});
}
