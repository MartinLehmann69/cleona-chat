import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;
import 'package:cleona/core/ipc/ipc_server.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/rendezvous/infra_rendezvous_manager.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_manager.dart'
    show RendezvousAddress;
import 'package:cleona/core/network/transport.dart' show Transport;
import 'package:cleona/core/tray/native_tray.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/reminder_service.dart';
import 'package:cleona/core/calendar/sync/caldav_server.dart';
import 'package:cleona/core/service/notification_sound_service.dart' show VibrationType;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Holds the machine-global single-instance flock (§15.1) for the entire
/// process lifetime. Top-level so it is NEVER garbage-collected — a block- or
/// method-scoped RandomAccessFile would be finalized once out of scope, closing
/// the fd and silently releasing the lock (observed 2026-05-30: a second daemon
/// then slipped past Guard 2 to the IPC-socket check).
RandomAccessFile? _machineGlobalLockRaf;

/// Cleona service daemon — runs independently of the GUI.
/// One daemon, one port, one node — all identities active simultaneously.
void main(List<String> args) {
  runZonedGuarded(() async {
    final config = _parseArgs(args);
    final log = CLogger.get('daemon', profileDir: config.baseDir);

    log.info('Starting Cleona daemon...');
    log.info('Base dir: ${config.baseDir}');
    log.info('Port: ${config.port}');
    log.info('DISPLAY: ${Platform.environment['DISPLAY'] ?? 'NOT SET'}');
    log.info('WAYLAND_DISPLAY: ${Platform.environment['WAYLAND_DISPLAY'] ?? 'NOT SET'}');
    // Flush the startup banner immediately so a crash before the 2s periodic
    // flush-timer doesn't swallow the log. Critical for diagnosing gui-00
    // 0.06-style failures where the daemon log appears empty post-mortem.
    await CLogger.flushAll();

    // ── Single-Instance Guard ────────────────────────────────────────
    Directory(config.baseDir).createSync(recursive: true);

    // Guard 0 (defense-in-depth): PID-file alive check. Catches duplicates
    // even when cleona.lock was deleted externally (which defeats the flock
    // guard because the new file has a different inode).
    final pidPath = '${config.baseDir}/cleona.pid';
    try {
      final pidFile = File(pidPath);
      if (pidFile.existsSync()) {
        final otherPid = int.parse(pidFile.readAsStringSync().trim());
        if (otherPid != pid) {
          final result = Process.runSync('kill', ['-0', '$otherPid']);
          if (result.exitCode == 0) {
            stderr.writeln(
              'ERROR: Cleona daemon already running (PID $otherPid). '
              'Stop the running process first before starting a new one.');
            log.info('Daemon PID $otherPid is still alive — exiting.');
            await CLogger.flushAll();
            exit(1);
          }
        }
      }
    } catch (_) { /* stale/corrupt PID file — proceed to flock guard */ }

    // Guard 1 (primary): advisory exclusive file lock (LOCK_EX|LOCK_NB).
    // The lock is released automatically when the winning process exits (fd
    // closed by kernel). IMPORTANT: never delete cleona.lock externally — the
    // flock is inode-based; deleting the file lets a second process create a
    // new inode and acquire its own lock, defeating the guard.
    final lockFile = File('${config.baseDir}/cleona.lock');
    final lockRaf = lockFile.openSync(mode: FileMode.write);
    try {
      await lockRaf.lock(FileLock.exclusive);
      lockRaf.writeStringSync('$pid\n');
    } on FileSystemException {
      stderr.writeln(
        'ERROR: Another Cleona daemon holds the lock file. '
        'Stop the running process first before starting a new one.');
      log.info('Another Cleona daemon already holds the lock — exiting.');
      await CLogger.flushAll();
      lockRaf.closeSync();
      exit(1);
    }
    // lockRaf stays open: lock is held until this process exits.

    // Guard 2 (machine-global, V3.1.72, §15.1): a fixed, profile-independent
    // lock so a SECOND daemon with a different --base-dir/--profile cannot
    // start on the same machine. The per-baseDir lock above is blind across
    // data roots — that was the V3.1.72 split-brain (~/.cleona vs
    // ~/.cleona/Cleona2 both started, inbound + GUI/IPC state diverged).
    // Bypass only via --ignore-single-instance in BETA builds (lab/jury-swarm).
    if (config.ignoreSingleInstance &&
        NetworkSecret.channel == NetworkChannel.beta) {
      log.info('--ignore-single-instance (beta): machine-global guard skipped.');
    } else {
      // Path MUST be deterministic across launch contexts (start.sh, systemd,
      // ssh) — env vars like XDG_RUNTIME_DIR are not reliably set, so two
      // launches could pick different paths and defeat the guard. Use the
      // stable per-user home (AppPaths.home → USERPROFILE on Windows), as a
      // SIBLING of the profile dir so an E2E/profile wipe of ~/.cleona (which
      // deletes the inode-based cleona.lock and defeats Guard 0/1) does NOT
      // remove this lock.
      final globalLockPath = '${AppPaths.home}/.cleona-daemon.lock';
      final globalLock = File(globalLockPath);
      try {
        globalLock.parent.createSync(recursive: true);
      } catch (_) {}
      _machineGlobalLockRaf = globalLock.openSync(mode: FileMode.write);
      try {
        await _machineGlobalLockRaf!.lock(FileLock.exclusive);
        _machineGlobalLockRaf!.writeStringSync('$pid\n');
      } on FileSystemException {
        stderr.writeln(
          'ERROR: Another Cleona daemon is already running on this machine '
          '(machine-global lock $globalLockPath held). One daemon per machine; '
          'use --ignore-single-instance (beta only) for lab multi-instance.');
        log.info('Machine-global single-instance lock held — exiting.');
        await CLogger.flushAll();
        _machineGlobalLockRaf!.closeSync();
        _machineGlobalLockRaf = null;
        exit(1);
      }
      // _machineGlobalLockRaf is top-level → never GC'd → lock held for the
      // entire process lifetime.
    }

    // Write PID file early so Guard 0 can detect us before we finish init.
    File(pidPath).writeAsStringSync('$pid\n');

    // Guard 2: IPC endpoint is connectable (another daemon owns it)
    if (Platform.isWindows) {
      // Windows: TCP loopback — check port file (format: port:token)
      final portFile = File('${config.baseDir}/cleona.port');
      if (portFile.existsSync()) {
        try {
          final contents = portFile.readAsStringSync().trim();
          final port = int.parse(contents.split(':')[0]);
          final testSock = await Socket.connect(
            InternetAddress.loopbackIPv4, port,
          ).timeout(const Duration(seconds: 2));
          testSock.destroy();
          stderr.writeln(
            'ERROR: Another daemon is listening on TCP port $port. '
            'Stop the running process first.');
          log.info('Another daemon is listening on TCP port $port, exiting.');
          exit(1);
        } catch (_) {
          // Port file exists but not connectable — stale, remove it
          try { portFile.deleteSync(); } catch (_) {}
        }
      }
    } else {
      // Linux/macOS: Unix Domain Socket
      final socketFile = File('${config.baseDir}/cleona.sock');
      if (socketFile.existsSync()) {
        try {
          final testSock = await Socket.connect(
            InternetAddress('${config.baseDir}/cleona.sock', type: InternetAddressType.unix),
            0,
          );
          testSock.destroy();
          stderr.writeln(
            'ERROR: Another daemon is listening on IPC socket. '
            'Stop the running process first.');
          log.info('Another daemon is listening on socket, exiting.');
          exit(1);
        } catch (_) {
          // Socket exists but not connectable — stale, remove it
          try { socketFile.deleteSync(); } catch (_) {}
        }
      }
    }
    // Check 3: UDP port already bound (catches orphaned daemons whose
    // lock file was deleted but are still holding the port). If no --port
    // arg was passed, read the effective port from identities.json so the
    // guard catches zombies even when the parent command line is minimal —
    // Dart sets the process name to "dart:cleona-dae" (truncated to 15
    // chars), which makes pkill -x matching unreliable and leaves killed-by-
    // checksum but not actually-killed processes around across redeploys.
    int? probePort = config.port;
    if (probePort == null) {
      try {
        final idFile = File('${config.baseDir}/identities.json');
        if (idFile.existsSync()) {
          final json = jsonDecode(idFile.readAsStringSync()) as Map<String, dynamic>;
          final list = json['identities'] as List?;
          if (list != null && list.isNotEmpty) {
            final first = list.first as Map<String, dynamic>;
            probePort = first['port'] as int?;
          }
        }
      } catch (_) { /* identities.json malformed — skip port check */ }
    }
    if (probePort != null) {
      try {
        final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, probePort);
        probe.close();
        // Port was free — we can proceed
      } on SocketException {
        stderr.writeln(
          'ERROR: UDP port $probePort already in use. '
          'Stop the running process first.');
        log.info('Port $probePort already in use (orphaned daemon?), exiting.');
        exit(1);
      }
    }

    // Clear any stale ready-flag from a crashed previous instance. Ready-flag
    // is written only after ipcServer.start() succeeds (see `_startAllInner`).
    try {
      final readyFile = File('${config.baseDir}/cleona.ready');
      if (readyFile.existsSync()) readyFile.deleteSync();
    } catch (_) { /* non-fatal */ }

    // Init crypto
    SodiumFFI();
    OqsFFI().init();

    // ── Tray icon (FIRST, before anything else) ──────────────────────
    final isBeta = NetworkSecret.channel == NetworkChannel.beta;
    final trayTooltip = isBeta ? 'Cleona Beta' : 'Cleona Chat';
    final tray = NativeTray();
    final iconPath = config.iconPath ?? _findIconPath(beta: isBeta);
    if (iconPath != null) {
      final ok = tray.init(
        iconPath: iconPath,
        tooltip: trayTooltip,
        logger: (level, msg) {
          if (level == 'warn') { log.warn(msg); } else { log.info(msg); }
        },
      );
      log.info('Tray icon: ${ok ? "OK" : "FAILED"} (icon: $iconPath, channel: ${NetworkSecret.channel.name})');
    } else {
      log.warn('No tray icon found, running without tray');
    }

    // ── Multi-Service lifecycle management ───────────────────────────
    final lifecycle = _MultiServiceDaemon(config: config, log: log, tray: tray);
    await lifecycle.startAll();

    // ── Signal handling ───────────────────────────────────────────────
    // Windows only supports SIGINT (Ctrl+C), not SIGTERM/SIGHUP.
    // Log every signal — distinguishing "killed by signal" from "died spontaneously"
    // is the first forensic split when investigating a daemon crash (C-3).
    ProcessSignal.sigint.watch().listen((_) {
      log.warn('SIGINT received — initiating shutdown');
      lifecycle.shutdownAll();
    });
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) {
        log.warn('SIGTERM received — initiating shutdown');
        lifecycle.shutdownAll();
      });
      // Ignore SIGHUP — daemon must survive when parent (GUI) exits or session changes
      try {
        ProcessSignal.sighup.watch().listen((_) {
          log.info('SIGHUP received — ignoring (daemon stays alive)');
        });
      } catch (_) {}
    }

    log.info('Cleona daemon running.');
  }, (error, stack) async {
    // C-3 forensics: an uncaught async error here used to be logged into the
    // in-memory buffer only, with flush running on a 2s timer — if the daemon
    // died before that tick, the stack trace was lost (B-4 crash 2026-05-14
    // 13:36 had exactly this pattern). Now: synchronous stderr write (lands
    // in wrapper-captured log immediately), then await flushAll.
    // Survivable errors (TimeoutException, SocketException) are logged but do
    // NOT terminate the daemon — they occur routinely when peers are
    // temporarily unreachable. Only truly unexpected errors exit(99).
    final msg = 'UNHANDLED ASYNC ERROR: $error\nStack:\n$stack';
    try { stderr.writeln(msg); } catch (_) {}
    try {
      final log = CLogger.get('daemon');
      log.error(msg);
      await CLogger.flushAll();
    } catch (_) {}
    final isSurvivable = error is TimeoutException ||
        error is SocketException ||
        error is IOException ||
        (error is StateError && error.message.contains('DhtRpc disposed'));
    if (!isSurvivable) exit(99);
  });
}

/// Manages ONE CleonaNode with MULTIPLE CleonaServices (one per identity).
class _MultiServiceDaemon {
  final _DaemonConfig config;
  final CLogger log;
  final NativeTray tray;

  CleonaNode? _node;
  final Map<String, CleonaService> _services = {}; // nodeIdHex → service
  final Map<String, IdentityContext> _contexts = {}; // nodeIdHex → context
  IpcServer? _ipcServer;
  ReminderService? _reminderService;
  CalDAVServer? _caldavServer;
  Timer? _statusTimer;
  Timer? _networkPollTimer; // Windows-only: 30s poll fallback for network changes
  List<String> _lastPollIps = []; // Windows-only: IP snapshot for delta-check
  Process? _networkMonitor;
  Timer? _triggerTimer;
  Timer? _heartbeatTimer;
  Timer? _socketWatchdog;
  DateTime? _heartbeatLastAt;
  int _heartbeatTick = 0;
  bool _running = false;

  _MultiServiceDaemon({
    required this.config,
    required this.log,
    required this.tray,
  }) {
    tray.onShowWindow = () {
      log.info('Tray: Anzeigen');
      _launchGui();
    };
    tray.onStop = () => stopAll();
    tray.onStart = () => startAll();
    tray.onQuit = () => shutdownAll();

    // Periodically check if the GUI requests service start
    _triggerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkStartTrigger();
    });
  }

  void _checkStartTrigger() {
    final triggerFile = File('${config.baseDir}/cleona.start');
    if (triggerFile.existsSync()) {
      triggerFile.deleteSync();
      if (!_running) {
        log.info('Start-Trigger von GUI erkannt');
        startAll();
      }
    }
  }

  Future<void> startAll() async {
    if (_running) return;
    log.info('Dienst wird gestartet...');

    // §3.7: Initialize crypto subsystem (shared sequence — S106 fix)
    await IdentityContext.initCrypto(config.baseDir);

    // Load all identities
    final mgr = IdentityManager(baseDir: config.baseDir);
    var identities = mgr.loadIdentities();
    if (identities.isEmpty) {
      log.warn('Keine Identitäten gefunden — warte auf GUI-Setup (cleona.start trigger)');
      return;
    }

    try {
      await _startAllInner(identities, mgr);
    } catch (e, stack) {
      log.error('Dienst-Start fehlgeschlagen: $e');
      log.error('Stack: $stack');
      // Critical: exit on startup failure (e.g. port already in use).
      // Without this, the daemon stays alive as a zombie — holding the lock
      // file but without transport, socket, or any useful functionality.
      await shutdownAll();
    }
  }

  Future<void> _startAllInner(List<Identity> identities, IdentityManager mgr) async {

    // Use configured port, or first identity's port
    final nodePort = config.port ?? identities.first.port;

    // Routing table stored in base dir (shared across identities)
    final routingDir = config.baseDir;
    Directory(routingDir).createSync(recursive: true);

    // Create primary identity context (shared sequence — S106 fix)
    final primaryId = identities.first;
    final masterSeed = mgr.loadMasterSeed();

    final primaryCtx = await IdentityContext.createFromIdentity(
      identity: primaryId,
      baseDir: config.baseDir,
      masterSeed: masterSeed,
    );

    // Create ONE shared node
    final node = CleonaNode(
      profileDir: routingDir,
      port: nodePort,
      networkChannel: NetworkSecret.channel.name,
    );
    node.manualPublicIp = config.publicIp;
    node.primaryIdentity = primaryCtx;
    _node = node;

    // Register primary identity
    _contexts[primaryCtx.userIdHex] = primaryCtx;

    // Create contexts for all other identities (shared sequence — S106 fix).
    // initKeys() runs in isolates (PQ-Keygen 15-30s on fresh profiles) —
    // parallelize so total startup time does not scale linearly with identity count.
    final secondaryFutures = <Future<IdentityContext>>[];
    for (var i = 1; i < identities.length; i++) {
      secondaryFutures.add(IdentityContext.createFromIdentity(
        identity: identities[i],
        baseDir: config.baseDir,
        masterSeed: masterSeed,
      ));
    }
    final secondaryCtxs = await Future.wait(secondaryFutures);
    for (final ctx in secondaryCtxs) {
      _contexts[ctx.userIdHex] = ctx;
    }

    // Register all identities with the node (before start, so routing table rejects them)
    for (final ctx in _contexts.values) {
      node.registerIdentity(ctx);
    }

    // §2.4 receiver step [9] (Edit 2 — multi-identity KEM-Try-Loop): V3
    // ApplicationFrame dispatcher. Per §3.1 the deviceID is daemon-global,
    // so `nextHopDeviceId` cannot identify the owning identity any longer
    // (it identifies the daemon). The receive pipeline therefore tries each
    // hosted identity's User-KEM-SK in turn until one decapsulates
    // successfully (recently-active-first heuristic), or all fail.
    node.onApplicationFramePayload = (packet, from, port, snapshot) async {
      if (_services.isEmpty) {
        if (!_servicesReady) {
          log.debug('V3 APP drop during boot: services not ready');
          return;
        }
        log.warn('V3 APP drop: no services registered');
        return;
      }

      // Try-order: most-recently-delivered identity first (heuristic — the
      // active conversation partner is statistically the most likely
      // recipient for the next inbound frame). Fall back to insertion order
      // for ties / cold daemon start.
      final ordered = _orderedServicesByRecency();
      for (final service in ordered) {
        final outcome = await service.handleIncomingApplicationPacket(
            packet, from, port, snapshot);
        if (outcome == AppFrameDispatchOutcome.delivered) {
          _markServiceActive(service);
          return;
        }
        if (outcome == AppFrameDispatchOutcome.droppedAfterDecap) {
          // Decap succeeded under this identity's User-KEM-SK but a later
          // step failed (sig/parse/recipient-mismatch). Final drop — no
          // other identity could decap the same KEM-ciphertext.
          return;
        }
        // outcome == notForThisIdentity: continue to next service.
      }
      log.debug('V3 APP drop: KEM-decap failed under all '
          '${ordered.length} hosted identit${ordered.length == 1 ? "y" : "ies"} '
          '(frame not addressed to any UserID on this daemon)');
    };

    // Welle 5 §8.1.1: First-CR-Bootstrap arrives as InfrastructureFrame
    // with messageType=MTV3_CONTACT_REQUEST (selector exception). Route by
    // frame.recipientDeviceId — same lookup pattern as the application
    // path. Other infrastructure types that fall through to this hook
    // (post-Wave-1 cluster — e.g. routing/DHT chatter that the node hasn't
    // node-locally dispatched yet) get logged and dropped because their
    // service-side handlers don't exist yet.
    node.onInfrastructureFramePayload = (frame, senderDeviceId, from, port, snapshot) {
      // Service-routed Identity-Layer messageTypes (Welle 5 + 6): CR-Bootstrap,
      // RESTORE_BROADCAST, Emergency KEY_ROTATION_BROADCAST. Everything else
      // either lives in the node-local infra dispatch or has no handler yet.
      final mt = frame.messageType;
      final isServiceRouted =
          mt == proto.MessageTypeV3.MTV3_CONTACT_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_RESTORE_BROADCAST ||
          mt == proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_RESPONSE ||
          // Wave 2B.3 (§6 Reed-Solomon erasure + S&F mailbox):
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_STORE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_DELETE ||
          // §5.5 Store-and-Forward on mutual peers:
          mt == proto.MessageTypeV3.MTV3_PEER_STORE ||
          mt == proto.MessageTypeV3.MTV3_PEER_STORE_ACK ||
          mt == proto.MessageTypeV3.MTV3_PEER_RETRIEVE ||
          mt == proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE ||
          // Wave 2B.3 (§10.2): channel-index gossip
          mt == proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE ||
          // §8.1.1 rev3: Deferred Key Exchange (step 1b)
          mt == proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER ||
          // §11.4.8: Anonymous Vote Re-Broadcaster
          mt == proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT ||
          mt == proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT_ACK;
      if (!isServiceRouted) {
        log.debug('V3 INFRA hook drop: messageType=${mt.name} '
            'has no service-side handler');
        return;
      }
      // §3.1 C-1: all hosted identities share one daemon-global deviceNodeId.
      // Fan out to every identity on this device — each handler drops
      // internally if the frame is not relevant to that identity.
      final deviceIdBytes = Uint8List.fromList(frame.recipientDeviceId);
      final identities = node.identitiesForDevice(deviceIdBytes).toList();
      if (identities.isEmpty) {
        log.debug('V3 INFRA drop: recipientDeviceId '
            '${bytesToHex(deviceIdBytes).substring(0, 8)} '
            'is not local (mt=${mt.name})');
        return;
      }
      for (final id in identities) {
        final service = _services[id.userIdHex];
        if (service == null) continue;
        switch (mt) {
          case proto.MessageTypeV3.MTV3_CONTACT_REQUEST:
            service.handleIncomingFirstContactRequest(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_RESTORE_BROADCAST:
            service.handleIncomingRestoreBroadcastInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST:
            service.handleIncomingKeyRotationBroadcastInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE:
            service.handleIncomingGuardianShareStoreInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST:
            service.handleIncomingGuardianRestoreRequestInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_RESPONSE:
            service.handleIncomingGuardianRestoreResponseInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
            service.handleIncomingFragmentStoreInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE:
            service.handleIncomingFragmentRetrieveInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
            service.handleIncomingFragmentRetrieveResponseInfra(
                frame, senderDeviceId);
            break;
          case proto.MessageTypeV3.MTV3_FRAGMENT_DELETE:
            service.handleIncomingFragmentDeleteInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE:
            service.handleIncomingChannelIndexExchangeInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_PEER_STORE:
            service.handleIncomingPeerStoreInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_PEER_STORE_ACK:
            break;
          case proto.MessageTypeV3.MTV3_PEER_RETRIEVE:
            service.handleIncomingPeerRetrieveInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE:
            service.handleIncomingPeerRetrieveResponseInfra(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST:
            service.handleIncomingDeviceKemRequest(
                frame, senderDeviceId, from, port);
            break;
          case proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER:
            service.handleIncomingDeviceKemOffer(frame, senderDeviceId);
            break;
          case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT:
            service.handleIncomingPollAnonSubmit(
                frame, senderDeviceId, from, port, snapshot);
            break;
          case proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT_ACK:
            service.handleIncomingPollAnonSubmitAck(frame, senderDeviceId);
            break;
          default:
            break;
        }
      }
    };

    // Notify GUI when peer addresses change (e.g. bootstrap discovers public IP)
    node.onPeersChanged = () {
      for (final service in _services.values) {
        service.onStateChanged?.call();
      }
    };

    // Windows: ensure firewall allows inbound UDP for the daemon process.
    if (Platform.isWindows) {
      await _ensureWindowsFirewallRule(nodePort);
    }

    // Start the shared node
    await node.startQuick();
    log.info('Node gestartet auf Port $nodePort, ${_contexts.length} Identitäten');

    // §4.11.9 Infrastructure Rendezvous: publish this node's public addresses.
    final infraRv = InfraRendezvousManager(profileDir: config.baseDir);
    infraRv.init(
      networkSecret: NetworkSecret.secret,
      deviceId: _contexts.values.first.nodeId,
      addressProvider: () => node.currentSelfAddresses()
          .map((a) => RendezvousAddress(a.ip, a.port))
          .toList(),
    );
    node.infraRendezvousManager = infraRv;
    infraRv.startPeriodicRefresh();

    // Create and start a CleonaService for each identity
    for (final ctx in _contexts.values) {
      final service = CleonaService(
        identity: ctx,
        node: node,
        displayName: ctx.displayName,
      );
      // Wire badge count to tray icon
      service.onBadgeCountChanged = (count) => _updateTrayBadge();
      await service.startService();
      _services[ctx.userIdHex] = service;
      log.info('Service gestartet: ${ctx.displayName} (${ctx.userIdHex.substring(0, 16)}...)');
    }

    // Services ready — V3 ApplicationFrame/InfrastructureFrame hooks gate on this flag.
    _servicesReady = true;

    // Save updated nodeIdHex values
    mgr.saveIdentities(identities);

    // IPC socket — ONE socket for all identities
    final socketPath = '${config.baseDir}/cleona.sock';
    final ipcServer = IpcServer(
      services: _services,
      socketPath: socketPath,
      defaultIdentityId: primaryCtx.userIdHex,
    );
    ipcServer.onCreateIdentity = _createIdentityAtRuntime;
    ipcServer.onDeleteIdentity = _deleteIdentityAtRuntime;
    ipcServer.onCalDAVServerGetState = getCalDAVServerState;
    ipcServer.onCalDAVServerSetEnabled = setCalDAVServerEnabled;
    ipcServer.onCalDAVServerRegenerateToken = regenerateCalDAVServerToken;
    ipcServer.onCalDAVServerSetPort = setCalDAVServerPort;
    await ipcServer.start();
    _ipcServer = ipcServer;

    // PID file already written early (Guard 0 needs it before init completes).

    // Calendar reminder service (§23) — checks all identity calendars
    _startReminderService();

    // Calendar external sync (§23.8 — CalDAV + Google) per identity
    _startCalendarSyncServices();

    // Local CalDAV server (§23.8.7) — exposes each identity's calendar as
    // a CalDAV endpoint on 127.0.0.1 so desktop calendar apps (Thunderbird
    // / Outlook / Apple Calendar / Evolution) can sync directly against
    // the daemon without any external server. Opt-in; disabled by default.
    await _startLocalCalDAVServer();

    // Periodic timers
    _statusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_running) return;
      final svcNames = _services.values.map((s) => s.displayName).join(', ');
      log.info('Status: peers=${node.routingTable.peerCount}, identities=${_services.length} [$svcNames]');
    });

    // Heartbeat (5s) for main-event-loop liveness diagnostics. The 60s
    // status line above is too coarse to localize a hang — if the daemon
    // freezes between two status ticks, we know only "hang happened within
    // 60s of tick N", but not whether the main loop was already stalled at
    // 30s, 45s, or 59s. The 5s heartbeat narrows that window to ~5s and
    // logs the *observed* interval so drift (GC pauses, slow event handlers)
    // shows up as dt > 5500ms WARN before the full hang.
    //
    // Added 2026-04-24 after a daemon hung silently from 15:10:20 to
    // 19:44:53 (4h 34min) without a single log entry — the last entry was
    // a PeerListPush handler, and the next status tick never fired.
    // Without this heartbeat the ante-hang timeline was 60s-fuzzy; with it,
    // the next occurrence gives a 5s window + drift signal.
    _heartbeatLastAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_running) return;
      final now = DateTime.now();
      final last = _heartbeatLastAt;
      _heartbeatLastAt = now;
      _heartbeatTick++;
      final dtMs = last == null ? 0 : now.difference(last).inMilliseconds;
      // Expected dt ≈ 5000ms. Log every tick at debug for post-mortem
      // reconstruction; escalate to WARN on drift so live-tail greppers
      // see it, and log INFO once per minute as a heartbeat marker that
      // survives level-filtered viewers.
      if (dtMs > 6500) {
        log.warn('heartbeat tick=$_heartbeatTick dt=${dtMs}ms (DRIFT — main loop delayed ${dtMs - 5000}ms)');
      } else if (_heartbeatTick % 12 == 0) {
        // Every 60s: one info-level beat, sits alongside the 60s Status line.
        log.info('heartbeat tick=$_heartbeatTick dt=${dtMs}ms');
      } else {
        log.debug('heartbeat tick=$_heartbeatTick dt=${dtMs}ms');
      }
      _node?.transport.checkReceiveHealth();

      // Firewall blockade detection: after 60s of uptime, if zero external
      // packets were received, the local firewall is likely blocking inbound
      // UDP. Warn once per session so the user (or their log) can diagnose.
      final transport = _node?.transport;
      if (_heartbeatTick == 12 && transport != null &&
          !transport.firewallWarningEmitted &&
          transport.externalPacketsReceived == 0) {
        transport.firewallWarningEmitted = true;
        log.warn('FIREWALL? 60s uptime, 0 inbound external UDP packets. '
            'If connectivity fails, check that the OS firewall allows '
            'inbound UDP for this process.');
      }
    });

    _startNetworkMonitor();

    // Public IP discovery: PortMapper runs at node startup via NAT-PMP/UPnP.
    // If it fails (common — no IGD on many routers), fall back to ipify after 10s.
    // This is critical for Bootstrap nodes behind DNAT — without a known public IP,
    // mobile peers can't reach them from carrier networks.
    _queryPublicIpFallback(delay: const Duration(seconds: 10));

    // Re-query public IP on any network change (mass route-down, ip monitor, etc.).
    node.onNetworkChangeDetected = () {
      _queryPublicIpFallback(delay: const Duration(seconds: 3), force: true);
    };

    _running = true;
    tray.updateMenu(serviceRunning: true);
    log.info('Dienst gestartet. Socket: $socketPath');

    // Startup-readiness flag for external orchestrators (E2E tests, systemd,
    // restart scripts). Consumers poll for this file instead of guessing with
    // blind sleeps or racy IPC pings — Fix for gui-37.04 daemon-restart hang.
    try {
      File('${config.baseDir}/cleona.ready').writeAsStringSync('$pid');
    } catch (_) { /* non-fatal */ }

    // Socket watchdog: if the IPC socket inode is deleted externally (e.g. by
    // a test recovery script that rm's *.sock while the daemon holds the fd),
    // new IPC connections silently fail. Recreate the socket on the same path.
    if (!Platform.isWindows) {
      _socketWatchdog = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_running || _ipcServer == null) return;
        if (!File(socketPath).existsSync()) {
          log.warn('IPC socket deleted externally — recreating');
          _ipcServer!.rebindSocket();
        }
      });
    }
  }

  // Boot-window gate read by V3 ApplicationFrame / InfrastructureFrame hooks
  // to drop frames that arrive before per-identity services are constructed.
  // The sender retries via S&F (§3.3.7) + erasure (§6), so dropping is safe.
  bool _servicesReady = false;

  // Recently-active identity tracking for the §2.4 step [9] try-loop. The
  // most-recently-delivered identity is tried first on the next inbound
  // ApplicationFrame — the active conversation partner is statistically
  // the most likely recipient, which keeps the per-frame KEM-decap cost
  // at one attempt for the common case.
  final List<String> _serviceRecency = <String>[];

  /// Order [_services.values] most-recently-active first. Identities not
  /// yet in the recency list (cold start, fresh identity) are appended
  /// after the recency-sorted prefix in insertion order.
  Iterable<CleonaService> _orderedServicesByRecency() {
    final seen = <String>{};
    final out = <CleonaService>[];
    for (final id in _serviceRecency) {
      final s = _services[id];
      if (s != null && seen.add(id)) out.add(s);
    }
    for (final entry in _services.entries) {
      if (seen.add(entry.key)) out.add(entry.value);
    }
    return out;
  }

  /// Mark [service]'s identity as most-recently-active. Called after a
  /// successful ApplicationFrame delivery to that service.
  void _markServiceActive(CleonaService service) {
    final id = service.nodeIdHex;
    _serviceRecency.remove(id);
    _serviceRecency.insert(0, id);
  }

  /// Add a new identity at runtime.
  Future<CleonaService?> addIdentity(IdentityContext ctx) async {
    if (_node == null || !_running) return null;
    if (_services.containsKey(ctx.userIdHex)) return _services[ctx.userIdHex];

    _contexts[ctx.userIdHex] = ctx;
    _node!.registerIdentity(ctx);

    final service = CleonaService(
      identity: ctx,
      node: _node!,
      displayName: ctx.displayName,
    );
    await service.startService();
    _services[ctx.userIdHex] = service;

    // Update IPC server
    _ipcServer?.addService(ctx.userIdHex, service);

    // If the local CalDAV server is running, register the new identity
    // so desktop apps can immediately discover its calendar.
    _caldavServer?.registerIdentity(CalDAVServerIdentity(
      fullNodeId: ctx.userIdHex,
      displayName: ctx.displayName,
      calendar: service.calendarManager,
    ));

    log.info('Identität hinzugefügt: ${ctx.displayName}');
    return service;
  }

  /// Remove an identity at runtime.
  Future<void> removeIdentity(String nodeIdHex) async {
    final service = _services.remove(nodeIdHex);
    if (service != null) {
      await service.stop();
    }
    _contexts.remove(nodeIdHex);
    _node?.unregisterIdentity(nodeIdHex);
    _ipcServer?.removeService(nodeIdHex);
    _caldavServer?.unregisterIdentity(nodeIdHex);
    log.info('Identität entfernt: $nodeIdHex');
  }

  /// IPC callback: create a new identity at runtime.
  Future<String?> _createIdentityAtRuntime(String displayName) async {
    if (_node == null || !_running) return null;

    final mgr = IdentityManager(baseDir: config.baseDir);
    final identity = await mgr.createIdentity(displayName);

    final ctx = await IdentityContext.createFromIdentity(
      identity: identity,
      baseDir: config.baseDir,
      masterSeed: mgr.loadMasterSeed(),
    );
    // Update nodeIdHex in persisted identities list
    final identities = mgr.loadIdentities();
    for (final id in identities) {
      if (id.id == identity.id) {
        id.nodeIdHex = ctx.userIdHex;
        break;
      }
    }
    mgr.saveIdentities(identities);

    await addIdentity(ctx);
    return ctx.userIdHex;
  }

  /// IPC callback: delete an identity at runtime.
  Future<bool> _deleteIdentityAtRuntime(String nodeIdHex) async {
    if (_services.length <= 1) return false;

    // Send IDENTITY_DELETED notification to all contacts BEFORE removing
    final service = _services[nodeIdHex];
    if (service != null) {
      service.broadcastIdentityDeleted();
    }

    // Look up profileDir from context before removing (for fallback match)
    final ctx = _contexts[nodeIdHex];
    final profileDir = ctx?.profileDir;

    await removeIdentity(nodeIdHex);

    // Find and remove from IdentityManager
    final mgr = IdentityManager(baseDir: config.baseDir);
    final identities = mgr.loadIdentities();
    // Match by nodeIdHex first, then fallback to profileDir
    var match = identities.where((i) => i.nodeIdHex == nodeIdHex).toList();
    if (match.isEmpty && profileDir != null) {
      match = identities.where((i) => i.profileDir == profileDir).toList();
    }
    for (final id in match) {
      mgr.deleteIdentity(id.id);
    }

    return true;
  }

  Future<void> stopAll() async {
    if (!_running) return;
    log.info('Dienst wird gestoppt...');

    _running = false;

    _statusTimer?.cancel();
    _statusTimer = null;
    _networkPollTimer?.cancel();
    _networkPollTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reminderService?.dispose();
    _reminderService = null;
    await _stopLocalCalDAVServer();
    _networkMonitor?.kill();
    _networkMonitor = null;

    await _ipcServer?.stop();
    _ipcServer = null;

    for (final service in _services.values) {
      await service.stop();
    }
    _services.clear();
    _contexts.clear();

    await _node?.stop();
    _node = null;

    final pidFile = File('${config.baseDir}/cleona.pid');
    if (pidFile.existsSync()) pidFile.deleteSync();

    tray.updateMenu(serviceRunning: false);
    log.info('Dienst gestoppt (Tray bleibt aktiv)');
  }

  Future<void> shutdownAll() async {
    log.info('Daemon wird beendet...');
    _triggerTimer?.cancel();
    _socketWatchdog?.cancel();
    if (_running) await stopAll();
    // Do NOT delete cleona.lock — the flock is inode-based and released
    // automatically by the kernel when this process exits (fd closed).
    // Deleting the file would break the single-instance guarantee if
    // another daemon starts before this one fully exits (new inode = new
    // lock = two daemons with valid exclusive locks on different inodes).
    // The stale PID in the file is detected by the GUI via kill -0.
    tray.dispose();
    exit(0);
  }

  /// Windows: add an inbound UDP firewall rule for the daemon executable.
  /// Runs once per installation (marker file prevents re-running). Gracefully
  /// handles non-admin mode (netsh fails → log + continue).
  Future<void> _ensureWindowsFirewallRule(int port) async {
    final marker = File('${config.baseDir}/firewall_rule_added');
    if (marker.existsSync()) return;

    final exe = Platform.resolvedExecutable;
    log.info('Windows: adding inbound UDP firewall rule for $exe');
    try {
      final result = await Process.run('netsh', [
        'advfirewall', 'firewall', 'add', 'rule',
        'name=Cleona Messenger',
        'dir=in', 'action=allow', 'protocol=UDP',
        'program=$exe',
        'enable=yes',
      ]);
      if (result.exitCode == 0) {
        marker.writeAsStringSync('added');
        log.info('Windows: firewall rule added successfully');
      } else {
        log.warn('Windows: netsh firewall rule failed (exit ${result.exitCode}, '
            'likely non-admin): ${result.stderr}');
      }
    } catch (e) {
      log.warn('Windows: could not add firewall rule: $e');
    }
  }

  /// Event-driven network change detection.
  /// Start the ReminderService for all identity calendars.
  void _startReminderService() {
    final reminderService = ReminderService();
    // Build a live getter so identities added at runtime get reminders too.
    Map<String, CalendarManager> getCalendars() {
      final calendars = <String, CalendarManager>{};
      for (final entry in _services.entries) {
        calendars[entry.key] = entry.value.calendarManager;
      }
      return calendars;
    }

    reminderService.onReminderDue = (identityId, reminder) {
      log.info('Reminder due: ${reminder.title} (identity=$identityId, '
          '${reminder.minutesBefore}min before event)');
      final service = _services[identityId];
      if (service == null) return;

      // 1. IPC event → GUI (for in-app dialog / list highlight)
      service.onCalendarReminderDue?.call(
          reminder.eventId, reminder.title, reminder.minutesBefore);

      // 2. System notification (Android + desktop). Reuses the same
      //    MethodChannel bridge as incoming messages, so reminders fire even
      //    when the app is in the background or only the daemon is running.
      final body = reminder.minutesBefore > 0
          ? 'In ${reminder.minutesBefore} min'
          : 'Jetzt';
      final notificationId = 'reminder:${reminder.eventId}:${reminder.eventStart}';
      unawaited(service.onPostNotificationAndroid
              ?.call(reminder.title, body, notificationId) ??
          Future.value());

      // 3. Notification sound + short vibrate (daemon-local PipeWire / Android haptics).
      unawaited(service.notificationSound.playMessageSound());
      unawaited(service.notificationSound.vibrate(VibrationType.message));
    };
    final initialCalendars = getCalendars();
    reminderService.start(initialCalendars, calendarGetter: getCalendars);
    _reminderService = reminderService;
    log.info('Reminder service started for ${initialCalendars.length} identity calendars');
  }

  /// Start the CalendarSyncService for each identity. No-op if no provider
  /// is configured; the service wakes up when the user configures CalDAV or Google.
  void _startCalendarSyncServices() {
    for (final svc in _services.values) {
      svc.calendarSyncService.start();
    }
    log.info('Calendar sync service started for ${_services.length} identities');
  }

  // ── Local CalDAV server (§23.8.7) ───────────────────────────────────

  static const String _caldavConfigFilename = 'caldav_server.json';

  /// Config of the local CalDAV server. The daemon writes this back to
  /// disk whenever the user changes it.
  _CalDAVServerConfig? _caldavConfig;

  /// Read (or create) the local CalDAV server config.
  _CalDAVServerConfig _loadCalDAVServerConfig() {
    final path = '${config.baseDir}/$_caldavConfigFilename';
    final f = File(path);
    if (f.existsSync()) {
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return _CalDAVServerConfig(
          enabled: json['enabled'] as bool? ?? false,
          port: json['port'] as int? ?? CalDAVServer.defaultPort,
          token: json['token'] as String? ?? '',
        );
      } catch (e) {
        log.warn('Invalid $path, resetting: $e');
      }
    }
    return _CalDAVServerConfig(
      enabled: false,
      port: CalDAVServer.defaultPort,
      token: '',
    );
  }

  void _saveCalDAVServerConfig() {
    final cfg = _caldavConfig;
    if (cfg == null) return;
    final path = '${config.baseDir}/$_caldavConfigFilename';
    File(path).writeAsStringSync(jsonEncode({
      'enabled': cfg.enabled,
      'port': cfg.port,
      'token': cfg.token,
    }));
  }

  /// Generate a random 32-hex-char token (128 bits of entropy).
  String _generateCalDAVToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _startLocalCalDAVServer() async {
    _caldavConfig ??= _loadCalDAVServerConfig();
    final cfg = _caldavConfig!;
    if (!cfg.enabled) {
      log.info('Local CalDAV server: disabled');
      return;
    }
    if (cfg.token.isEmpty) {
      cfg.token = _generateCalDAVToken();
      _saveCalDAVServerConfig();
    }
    final server = CalDAVServer(port: cfg.port);
    server.setToken(cfg.token);
    for (final svc in _services.values) {
      server.registerIdentity(CalDAVServerIdentity(
        fullNodeId: svc.identity.userIdHex,
        displayName: svc.displayName,
        calendar: svc.calendarManager,
      ));
    }
    try {
      await server.start();
      _caldavServer = server;
      log.info('Local CalDAV server enabled on '
          '127.0.0.1:${server.boundPort} with ${_services.length} identities');
    } catch (e) {
      log.warn('Failed to start local CalDAV server on port ${cfg.port}: $e');
    }
  }

  Future<void> _stopLocalCalDAVServer() async {
    await _caldavServer?.stop();
    _caldavServer = null;
  }

  /// IPC-handler helper: current state (also used by UI to show the URL).
  Map<String, dynamic> getCalDAVServerState() {
    _caldavConfig ??= _loadCalDAVServerConfig();
    final cfg = _caldavConfig!;
    final running = _caldavServer?.isRunning ?? false;
    final port = _caldavServer?.boundPort ?? cfg.port;
    final identities = _caldavServer?.identities
            .map((i) => {
                  'shortId': i.shortId,
                  'displayName': i.displayName,
                  'calendarUrl':
                      'http://127.0.0.1:$port/dav/calendars/${i.shortId}/default/',
                })
            .toList() ??
        [];
    return {
      'enabled': cfg.enabled,
      'running': running,
      'port': port,
      'hasToken': cfg.token.isNotEmpty,
      'token': cfg.token, // daemon→UI handover; UI never leaves loopback
      'baseUrl': 'http://127.0.0.1:$port/',
      'identities': identities,
    };
  }

  /// IPC-handler: enable / disable the server.
  Future<Map<String, dynamic>> setCalDAVServerEnabled(bool enabled) async {
    _caldavConfig ??= _loadCalDAVServerConfig();
    final cfg = _caldavConfig!;
    cfg.enabled = enabled;
    if (enabled && cfg.token.isEmpty) {
      cfg.token = _generateCalDAVToken();
    }
    _saveCalDAVServerConfig();
    if (enabled) {
      await _stopLocalCalDAVServer();
      await _startLocalCalDAVServer();
    } else {
      await _stopLocalCalDAVServer();
    }
    return getCalDAVServerState();
  }

  Future<Map<String, dynamic>> regenerateCalDAVServerToken() async {
    _caldavConfig ??= _loadCalDAVServerConfig();
    final cfg = _caldavConfig!;
    cfg.token = _generateCalDAVToken();
    _saveCalDAVServerConfig();
    // If already running, swap token without restarting the server.
    _caldavServer?.setToken(cfg.token);
    return getCalDAVServerState();
  }

  Future<Map<String, dynamic>> setCalDAVServerPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('Port must be in 1024..65535');
    }
    _caldavConfig ??= _loadCalDAVServerConfig();
    _caldavConfig!.port = port;
    _saveCalDAVServerConfig();
    if (_caldavServer != null) {
      try {
        await _caldavServer!.setPort(port);
      } catch (e) {
        log.warn('Failed to rebind CalDAV server to port $port: $e');
      }
    }
    return getCalDAVServerState();
  }

  /// Linux: `ip monitor address` — fires on every IPv4/IPv6 address add/delete.
  /// Windows: polling fallback (no equivalent of ip monitor).
  void _startNetworkMonitor() async {
    if (Platform.isWindows) {
      // Windows: poll for network changes every 30s (no ip monitor equivalent).
      // The node-reset runs once for the whole daemon; per-service we only
      // trigger the service-side cleanup (mailbox poll, identity-publisher).
      _networkPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (!_running) return;
        final currentIps = await Transport.getAllLocalIps();
        final ipsKey = currentIps.join(',');
        final lastKey = _lastPollIps.join(',');
        if (ipsKey == lastKey && _lastPollIps.isNotEmpty) return;
        _lastPollIps = currentIps;
        log.info('Network change detected (poll) — IPs: $lastKey → $ipsKey');
        await _node?.onNetworkChanged();
        for (final service in _services.values) {
          service.onNetworkChanged(triggerNodeReset: false);
        }
        _queryPublicIpFallback(delay: const Duration(seconds: 10));
      });
      return;
    }

    try {
      // Kill orphaned `ip monitor address` from prior crashes (kill -9, segfault)
      await Process.run('pkill', ['-f', 'ip monitor address']);
      final proc = await Process.start('ip', ['monitor', 'address']);
      _networkMonitor = proc;
      // Debounce: network changes often come in bursts (multiple interfaces).
      Timer? debounce;
      proc.stdout.transform(const SystemEncoding().decoder).listen((line) {
        if (!_running) return;
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () async {
          log.info('Network change detected (ip monitor)');
          await _node?.onNetworkChanged();
          for (final service in _services.values) {
            service.onNetworkChanged(triggerNodeReset: false);
          }
          // Re-query public IP after network change (DNAT may have changed)
          _queryPublicIpFallback(delay: const Duration(seconds: 10));
        });
      });
      proc.exitCode.then((code) {
        log.debug('ip monitor exited with $code');
        _networkMonitor = null;
      });
    } catch (e) {
      log.warn('ip monitor not available: $e');
    }
  }

  /// ipify fallback — queries public IP from external service.
  /// [force]: re-query even if a public IP is already known (detects IP change).
  void _queryPublicIpFallback({Duration delay = Duration.zero, bool force = false}) {
    Timer(delay, () async {
      final node = _node;
      if (node == null || !_running) return;
      if (!force && node.natTraversal.hasPublicIp) {
        log.info('ipify fallback: skipped (public IP already known)');
        return;
      }

      log.info('ipify${force ? " recheck" : " fallback"}: querying public IP...');
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
        final response = await request.close().timeout(const Duration(seconds: 10));
        final ip = (await response.transform(const SystemEncoding().decoder).join()).trim();
        client.close(force: true);

        if (ip.isEmpty || !ip.contains('.')) {
          log.warn('ipify: empty or invalid response');
          return;
        }

        final oldIp = node.natTraversal.publicIp ?? node.manualPublicIp;
        if (force && oldIp != null && oldIp == ip) {
          log.info('ipify recheck: public IP unchanged ($ip)');
          return;
        }

        if (force && oldIp != null && oldIp != ip) {
          log.info('Public IP CHANGED: $oldIp → $ip — resetting NAT, broadcasting update');
          node.natTraversal.reset();
        }

        if (node.manualPublicIp != null) {
          // DNAT node (--public-ip): port is the listening port, no probe needed.
          log.info('Public IP via ipify: $ip — DNAT node, confirming $ip:${node.port}');
          node.natTraversal.confirmPublicAddress(ip, node.port);
          node.manualPublicIp = ip;
        } else {
          log.info('Public IP via ipify: $ip — starting port probe');
          node.natTraversal.setExternalIpOnly(ip);
          node.probePublicPort(ip);
        }
        node.broadcastAddressUpdate();
      } catch (e) {
        log.warn('ipify${force ? " recheck" : " fallback"} failed: $e');
      }

      // IPv6 public IP discovery (§27 — DS-Lite/CGNAT bypass)
      // Global IPv6 is directly routable — no port probe needed.
      try {
        final client6 = HttpClient();
        client6.connectionTimeout = const Duration(seconds: 10);
        final req6 = await client6.getUrl(Uri.parse('https://api6.ipify.org'));
        final resp6 = await req6.close().timeout(const Duration(seconds: 10));
        final ipv6 = (await resp6.transform(const SystemEncoding().decoder).join()).trim();
        client6.close(force: true);
        if (ipv6.isNotEmpty && ipv6.contains(':')) {
          log.info('Public IPv6 via ipify: $ipv6');
          node.natTraversal.setPublicIpv6(ipv6);
          node.broadcastAddressUpdate();
          // §4.7: one-shot inbound probe per join to detect carrier IPv6 filter.
          node.probeIpv6InboundIfNeeded();
        }
      } catch (e) {
        log.debug('ipify IPv6 query failed (expected if no IPv6): $e');
      }
    });
  }

  /// Update tray title with total unread count across all services.
  void _updateTrayBadge() {
    var total = 0;
    for (final service in _services.values) {
      total += service.conversations.values.fold<int>(0, (sum, c) => sum + c.unreadCount);
    }
    tray.updateMenu(serviceRunning: _running, unreadCount: total);
  }

  void _launchGui() {
    if (_ipcServer != null && _ipcServer!.hasClients) {
      final triggerFile = File('${config.baseDir}/gui.show');
      triggerFile.writeAsStringSync('${pid}');
      log.info('Tray: GUI already connected — wrote gui.show trigger');
      return;
    }
    final exePath = Platform.resolvedExecutable;
    final sep = Platform.pathSeparator;
    final dir = exePath.substring(0, exePath.lastIndexOf(sep));
    final guiName = Platform.isWindows ? 'cleona.exe' : 'cleona';
    for (final path in ['$dir$sep$guiName', '$dir$sep..$sep$guiName']) {
      if (File(path).existsSync()) {
        log.info('Launching GUI: $path');
        Process.start(path, [], mode: ProcessStartMode.detached);
        return;
      }
    }
    log.warn('GUI binary not found');
  }
}

String? _findIconPath({bool beta = false}) {
  final exePath = Platform.resolvedExecutable;
  final sep = Platform.pathSeparator;
  final dir = exePath.substring(0, exePath.lastIndexOf(sep));
  // Beta builds prefer _beta icon variants; fall back to standard if not found.
  final suffixes = beta ? ['_beta', ''] : [''];
  // Windows tray requires .ico format; search .ico first, then .png as fallback.
  final extensions = Platform.isWindows ? ['ico', 'png'] : ['png'];
  // Since c7ea816 moved daemon from ~/cleona-app/cleona-daemon to ~/cleona-daemon,
  // the binary no longer lives next to the Flutter bundle. Also search the sibling
  // cleona-app bundle under $HOME so the tray icon is still found on deployed VMs.
  final home = Platform.environment['HOME'];
  final homeBundleDir = home != null ? '$home${sep}cleona-app' : null;
  for (final suffix in suffixes) {
    for (final ext in extensions) {
      for (final path in [
        '$dir${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        '$dir${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
        '$dir$sep..${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        '$dir$sep..${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
        if (homeBundleDir != null)
          '$homeBundleDir${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        if (homeBundleDir != null)
          '$homeBundleDir${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
      ]) {
        if (File(path).existsSync()) return path;
      }
    }
  }
  return null;
}

class _CalDAVServerConfig {
  bool enabled;
  int port;
  String token;
  _CalDAVServerConfig({
    required this.enabled,
    required this.port,
    required this.token,
  });
}

class _DaemonConfig {
  final String baseDir; // ~/.cleona
  final int? port;
  final String? iconPath;
  final String? publicIp;
  /// Beta-only: skip the machine-global single-instance guard (§15.1).
  /// Used by lab tooling (jury-swarm) to run N daemons on one host.
  final bool ignoreSingleInstance;

  _DaemonConfig({
    required this.baseDir,
    this.port,
    this.iconPath,
    this.publicIp,
    this.ignoreSingleInstance = false,
  });
}

_DaemonConfig _parseArgs(List<String> args) {
  String? baseDir;
  int? port;
  String? iconPath;
  String? publicIp;
  bool ignoreSingleInstance = false;

  // Legacy: --profile and --name still accepted for compatibility
  String? legacyProfile;

  // Normalise `--key=value` forms (POSIX getopt-style) into separate
  // tokens so the per-flag matcher below can stay simple.
  final flat = <String>[];
  for (final a in args) {
    final eq = a.indexOf('=');
    if (a.startsWith('--') && eq > 2) {
      flat.add(a.substring(0, eq));
      flat.add(a.substring(eq + 1));
    } else {
      flat.add(a);
    }
  }

  for (var i = 0; i < flat.length; i++) {
    switch (flat[i]) {
      case '--base-dir':
        if (i + 1 < flat.length) baseDir = flat[++i];
        break;
      case '--profile':
        // Legacy: single-identity profile dir
        if (i + 1 < flat.length) legacyProfile = flat[++i];
        break;
      case '--port':
        if (i + 1 < flat.length) port = int.tryParse(flat[++i]);
        break;
      case '--name':
        // Legacy: ignored in multi-identity mode
        if (i + 1 < flat.length) i++;
        break;
      case '--icon':
        if (i + 1 < flat.length) iconPath = flat[++i];
        break;
      case '--public-ip':
        if (i + 1 < flat.length) publicIp = flat[++i];
        break;
      case '--ignore-single-instance':
        // Beta-only bypass of the machine-global single-instance guard
        // (lab/jury-swarm multi-instance). Honored only in beta builds.
        ignoreSingleInstance = true;
        break;
    }
  }

  // Determine base dir
  if (baseDir == null) {
    if (legacyProfile != null) {
      // Legacy: profile was e.g. ~/.cleona/identities/identity-1
      // Base dir is ~/.cleona
      final home = AppPaths.home;
      baseDir = '$home/.cleona';
    } else {
      final home = AppPaths.home;
      baseDir = '$home/.cleona';
    }
  }

  return _DaemonConfig(
    baseDir: baseDir,
    port: port,
    iconPath: iconPath,
    publicIp: publicIp,
    ignoreSingleInstance: ignoreSingleInstance,
  );
}
