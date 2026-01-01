import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:cleona/core/crypto/key_migration.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/mycelium_seam.dart';
import 'package:cleona/core/service/notification_content.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/android_badge.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:mycelium/host.dart';

/// What a wake-up needs from the app's RUNNING delivery (S420 IB-2,
/// variant B, owner decision 11.11.2026). `main.dart` sets it once its
/// services and its host stand ([IosBackgroundFetch.inProcess]) and clears
/// it when it stops the host.
///
/// Why: the wake-up runs in the SAME process as the app whenever iOS
/// resumes a suspended app for a `BGTask` — the app's services and host
/// are alive then. Until S420 the wake-up built a second `CleonaService` per
/// identity and a second host on the same port beside them; what that
/// second instance counted, the screen never saw (report
/// `S420-RCA-FELD-IPHONE-BADGE.md`, IB-2).
class IosFetchInProcess {
  /// The services of every identity in the app process; empty when the app
  /// has no host (then the wake-up takes the cold-start path).
  final List<CleonaService> Function() services;

  /// The data port of the app's host.
  final int Function() port;

  /// Binds the host's data port sockets afresh on the same port
  /// (`Host.socketsReopen`, §11.1, §31.3).
  final Future<({bool ipv4, bool? ipv6})> Function() socketsReopen;

  /// What rests goes again, then the post box is asked (§8.2) —
  /// `Host.applicationOpened`, the same edge the app's own return runs.
  final Future<void> Function() collect;

  const IosFetchInProcess({
    required this.services,
    required this.port,
    required this.socketsReopen,
    required this.collect,
  });
}

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

  /// Which of the two paths behind the gate a wake-up took (S420): through
  /// the app's running services, or the cold start that builds its own.
  @visibleForTesting
  static int inProcessRuns = 0;
  @visibleForTesting
  static int coldStartRuns = 0;

  /// The wait window instead of 20 s / 120 s — probes only.
  @visibleForTesting
  static Duration? windowForTest;

  /// The app's running delivery, or `null` (no app host in this process:
  /// cold start). Set and cleared by `main.dart` — see [IosFetchInProcess].
  static IosFetchInProcess? inProcess;

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
  /// Returns a map: {messageCount: int, badgeCount: int, senderNames:
  /// [String], previews: [String]} (`badgeCount` since S420, see [_result]).
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
    final window = windowForTest ?? Duration(seconds: waitSeconds);

    // ── THE APP LIVES IN THIS PROCESS: ITS SERVICES, NO SECOND ONE (S420) ──
    //
    // Variant B (IB-2): with the app's services and host alive, the wake-up
    // builds nothing of its own and stops nothing — they belong to the app.
    // Only without them (no app host in the process) the cold start below
    // runs as before.
    final live = inProcess;
    final liveServices = live?.services() ?? const <CleonaService>[];
    if (live != null && liveServices.isNotEmpty) {
      try {
        return await _fetchInProcess(live, liveServices, taskType, window);
      } finally {
        _isFetching = false;
        debugPrint('[ios-bg-fetch] Background fetch complete (in-process)');
      }
    }
    coldStartRuns++;

    final services = <CleonaService>[];
    // The ONE mycelium host of this wake-up (S387) — declared before the try,
    // so that the finally block can stop it. It holds the
    // wire and the state checker; a host not stopped would keep
    // the Dart VM alive, and iOS only ends the run when it reports.
    Host? host;
    // Conversations with new unread — for the wake-up line only; the
    // notifications come from the services (§22.8, D-124).
    var newConversations = 0;
    // The unread sum the icon shows (IB-1) and where the wake-up line goes.
    var badgeCount = 0;
    String? logDir;
    var failed = false;

    try {
      // Step 1: load identities and contexts
      final mgr = IdentityManager();
      final identities = mgr.loadIdentities();
      if (identities.isEmpty) {
        debugPrint('[ios-bg-fetch] No identities, aborting');
        return {'messageCount': 0, 'senderNames': <String>[], 'previews': <String>[]};
      }
      logDir = identities.first.profileDir;

      final masterSeed = mgr.loadMasterSeed();
      // `final firstId = identities.first;` was dropped with S374 — the
      // port now comes from the DEVICE (§11), not from the first
      // identity, and that was the only reader here.
      final baseDir = AppPaths.dataDir;

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
          reviewEnabled: id.reviewEnabled,
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
        // §22.8, D-124: the service forms and gates every notification of
        // this run itself — in the background (L5 open), behind quiet hours,
        // mute and L1–L4, the first collection as one batch — and hands it
        // to the system through the same channel as the running app.
        service.setAppResumed(false, triggerNodeHarvest: false);
        service.onPostNotificationIos = systemNotificationReceiver(service);
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
      final deviceKey = hostKey(baseDir, masterSeed);
      host = await hostStart(
        services: services,
        baseDir: baseDir,
        key: deviceKey,
        port: devicesPort,
        // Lane 3 (D-32): the SAME bulk cache as the app — it lies in the
        // same device folder, and its size is the user's tier read from
        // the same device database. With 0 the wake-up would not load the
        // held pieces and answer every 0x54 with "nothing here" (0x55),
        // which ends a recipient's collection although the pieces are on
        // disk; with a size other than the app's it would trim them.
        bulkCacheBytes: bulkCacheBytesConfigured(baseDir, deviceKey),
        bulkClass: bulkClassForPlatform(),
        bulkServeAllowed: bulkServeAllowedNow,
        askRouter: true, // §7.3: the host asks the router at its edges
        report: (m) => debugPrint('[ios-bg-fetch][mycelium] $m'),
        // No `traceReport`: this wake-up has no log file — every line, the
        // diagnosis included, goes to `debugPrint`, none into the
        // crash-report ring (S406).
      );
      debugPrint('[ios-bg-fetch] mycelium host on port ${host.port}');

      // The port mapping (task D, §7.3) is the host's own since S408 P15
      // (A-4): asked inside `hostStart`, laid down by `Host.stop` ([step 7]).

      // Record baseline unread counts per conversation
      final baselineUnread = _unreadBaseline(services);

      // Step 4: wait out the window. In V3 peers were
      // radioed here; in V4.1 there is nothing to do — the `SlotDriver` in the
      // node harvests on its own tick, and the effort lies
      // in giving it time.
      // BGAppRefreshTask: ~30 s window → 20 s. BGProcessingTask: minutes → 120 s.
      debugPrint('[ios-bg-fetch] Waiting for message retrieval (${waitSeconds}s)...');
      await Future<void>.delayed(window);

      // Step 5: the first collection ends with the window (iOS suspends the
      // process when the run reports): its batch notification goes now.
      // Then count the conversations with new unread for the line.
      for (final service in services) {
        service.endFirstCollection();
      }
      newConversations = _newUnreadSince(services, baselineUnread);
      badgeCount = AndroidBadge.of(services.map((s) => s.conversations)).count;

      debugPrint('[ios-bg-fetch] $newConversations conversation(s) with new unread');

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
      failed = true;
      debugPrint('[ios-bg-fetch] Error: $e\n$stack');
    } finally {
      // Step 7: stop the host FIRST, then the services. The other way round
      // the still running host would deliver to an already stopped service —
      // an acknowledged message that nobody stores any more. `stop`
      // saves the neighbours and closes the wire; an open wire
      // or state checker would keep the Dart VM alive, and iOS only ends
      // the run when it reports.
      // `Host.stop` lays the port mapping down first (S408 P15): its
      // renewal timer would otherwise keep the Dart VM alive.
      try {
        if (host != null) await hostStop(host); // lane 2 clocks, then the host
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
    await _wakeLine(logDir, taskType, 'cold start', newConversations,
        badgeCount, failed: failed);
    return _result(newConversations, badgeCount);
  }

  /// The wake-up through the app's running services (S420 IB-2, variant B).
  ///
  /// 1. Bind the data port's sockets afresh on the same port. iOS closes the
  ///    descriptors of a suspended app (§31.3 "Death of the file
  ///    descriptor"), and a closed one neither sends nor receives — without
  ///    this the wake-up would be deaf. Until S420 the second host of the
  ///    wake-up bound its own fresh sockets; this replaces that (§31.3
  ///    "Recovery": "bind fresh sockets and re-read the descriptor").
  /// 2. Baseline, then the edge of §8.2: what rests goes again, the post box
  ///    is asked (`Host.applicationOpened`) — the same that the second host
  ///    did at its start, so no traffic is added.
  /// 3. Wait out the window, collect what is new, save — and stop nothing:
  ///    services and host belong to the app.
  static Future<Map<String, dynamic>> _fetchInProcess(IosFetchInProcess live,
      List<CleonaService> services, String taskType, Duration window) async {
    inProcessRuns++;
    final logDir = services.first.profileDir;
    final log = CLogger.get('bg-fetch', profileDir: logDir);
    var newConversations = 0;
    var badgeCount = 0;
    var failed = false;
    try {
      final port = live.port();
      final r = await live.socketsReopen();
      String said(bool? fresh) =>
          fresh == null ? 'no socket' : (fresh ? 'bound afresh' : 'NOT bound afresh');
      log.info('bg-fetch: data port $port — IPv4 ${said(r.ipv4)}, '
          'IPv6 ${said(r.ipv6)} (§31.3)');
      final baseline = _unreadBaseline(services);
      unawaited(live.collect().catchError(
          (Object e) => log.warn('bg-fetch: collection failed: $e')));
      await Future<void>.delayed(window);
      // A start straight into the background (D-124): the first collection
      // of the app's services ends with the window, its batch goes now.
      // No-op for services whose first collection ended long ago.
      for (final service in services) {
        service.endFirstCollection();
      }
      newConversations = _newUnreadSince(services, baseline);
      badgeCount = AndroidBadge.of(services.map((s) => s.conversations)).count;
      // Saved as on the way into the background (`main.dart`, `paused`): iOS
      // may end the suspended process without a further word. One
      // identity's failure does not keep the others from saving.
      for (final service in services) {
        try {
          service.saveState();
        } catch (e) {
          log.warn('bg-fetch: saving an identity failed: $e');
        }
      }
    } catch (e, stack) {
      failed = true;
      debugPrint('[ios-bg-fetch] Error (in-process): $e\n$stack');
    }
    await _wakeLine(logDir, taskType, 'in-process', newConversations,
        badgeCount, failed: failed);
    // The running services notified each arrival themselves, behind the
    // gates of §22.8, through their iOS receiver (`main.dart`,
    // `onPostNotificationIos`); the native side only sets the badge (S422
    // N-4, D-124).
    return _result(newConversations, badgeCount);
  }

  /// The answer to the native side. `badgeCount` is the unread sum over
  /// every identity without the system channels — the number the app icon
  /// shows (IB-1, the same derivation as `main.dart` sends on every change).
  /// No titles, no texts: the services posted their notifications
  /// themselves (D-124); `messageCount` is the number of conversations with
  /// new unread, for the native log line.
  static Map<String, dynamic> _result(int newConversations, int badgeCount) =>
      {
        'messageCount': newConversations,
        'badgeCount': badgeCount,
      };

  /// ONE line per wake-up into the app log (S420): counts only — no name, no
  /// text, no address (§22.8: the text goes to the notification service and
  /// nowhere else). Until S420 a wake-up wrote only to `debugPrint`/`NSLog`,
  /// neither of which reaches `/Documents/logs/`. Flushed at once: iOS
  /// suspends the process as soon as the native side completes the task.
  static Future<void> _wakeLine(String? logDir, String taskType, String path,
      int conversations, int badge, {required bool failed}) async {
    if (logDir == null) return; // no identity: nothing was fetched
    CLogger.get('bg-fetch', profileDir: logDir).info(
        'bg-fetch: wake-up ($taskType, $path) — $conversations '
        'conversation(s) with new unread, badge $badge'
        '${failed ? ', ended with an error' : ''}');
    await CLogger.flushAll();
  }

  /// The unread count per conversation, per identity — before the window.
  static Map<String, Map<String, int>> _unreadBaseline(
          List<CleonaService> services) =>
      {
        for (final service in services)
          service.nodeIdHex: {
            for (final entry in service.conversations.entries)
              entry.key: entry.value.unreadCount,
          },
      };

  /// The number of conversations whose unread count grew since [baseline] —
  /// for the wake-up line only. Until S422 this formed the notifications
  /// Swift posted; since D-124 the services post them themselves.
  static int _newUnreadSince(List<CleonaService> services,
      Map<String, Map<String, int>> baselineUnread) {
    var grown = 0;
    for (final service in services) {
      final baseline = baselineUnread[service.nodeIdHex] ?? {};
      for (final entry in service.conversations.entries) {
        if (entry.value.unreadCount > (baseline[entry.key] ?? 0)) grown++;
      }
    }
    return grown;
  }

  /// The receiver of a service's system notification on iOS: title and text
  /// as the service formed them (`_postSystemNotification`), to
  /// UNUserNotificationCenter through `chat.cleona/notification`
  /// (`AppDelegate.swift`) — one per conversation. The ONE receiver for the
  /// running app (`main.dart`) and the cold start of the wake-up (D-124:
  /// the native side forms nothing and only sets the badge). `identity` is
  /// the posting identity, so a tap opens the conversation in it (§22.8,
  /// D-125 (3)). `soundName` is the `.caf` the notification rings with, or
  /// `null` for a silent one (§22.8, D-125: the system notification rings
  /// only while the app does not); a reminder or the batch carry no
  /// conversation and ring with the standard sound.
  static Future<void> Function(String title, String body, String id)
      systemNotificationReceiver(CleonaService service) =>
          (title, body, id) async {
            await _notificationChannel.invokeMethod('postNotification', {
              'title': title,
              'body': body,
              'conversationId': id,
              'identity': service.nodeIdHex,
              'soundName': iosNotificationSoundName(
                  bySystem: service.notificationSoundBySystem,
                  soundName:
                      service.conversations[id]?.notificationSoundName),
            });
          };

  static const _notificationChannel = MethodChannel('chat.cleona/notification');

  // ── `_routeInfraFrame` HAS BEEN REMOVED (CUT, 31.08.) ─────────────────
  //
  // It was a switch over four `MessageType` selectors
  // (FRAGMENT_RETRIEVE_RESPONSE, PEER_RETRIEVE_RESPONSE, FRAGMENT_STORE,
  // PEER_STORE) to four `CleonaService` handlers, all of which lay in
  // `cleona_service_v3_fragments.dart` or `_sf.dart`. Caller
  // (`host.wireReceive`) and callees have fallen together.

}
