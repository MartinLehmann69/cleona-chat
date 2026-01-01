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
import 'package:cleona/core/tray/native_tray.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/reminder_service.dart';
import 'package:cleona/core/calendar/sync/caldav_server.dart';
import 'package:cleona/core/service/notification_sound_service.dart' show VibrationType;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

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
    // Check 1: Lock file with living PID
    final lockFile = File('${config.baseDir}/cleona.lock');
    if (lockFile.existsSync()) {
      try {
        final existingPid = int.parse(lockFile.readAsStringSync().trim());
        if (existingPid != pid && _isProcessAlive(existingPid)) {
          log.info('Daemon already running (PID $existingPid), exiting.');
          exit(0);
        }
      } catch (_) {}
      try { lockFile.deleteSync(); } catch (_) {}
    }
    // Check 2: IPC endpoint is connectable (another daemon owns it)
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
          log.info('Another daemon is listening on TCP port $port, exiting.');
          exit(0);
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
          log.info('Another daemon is listening on socket, exiting.');
          exit(0);
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
        log.info('Port $probePort already in use (orphaned daemon?), exiting.');
        exit(0);
      }
    }

    // Write our lock immediately to prevent races
    Directory(config.baseDir).createSync(recursive: true);
    lockFile.writeAsStringSync('$pid');

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
    ProcessSignal.sigint.watch().listen((_) => lifecycle.shutdownAll());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => lifecycle.shutdownAll());
      // Ignore SIGHUP — daemon must survive when parent (GUI) exits or session changes
      try {
        ProcessSignal.sighup.watch().listen((_) {
          log.info('SIGHUP received — ignoring (daemon stays alive)');
        });
      } catch (_) {}
    }

    log.info('Cleona daemon running.');
  }, (error, stack) {
    final log = CLogger.get('daemon');
    log.error('Unhandled error: $error');
    log.error('Stack: $stack');
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
  Process? _networkMonitor;
  Timer? _triggerTimer;
  Timer? _heartbeatTimer;
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

    // Load all identities
    final mgr = IdentityManager(baseDir: config.baseDir);
    var identities = mgr.loadIdentities();
    if (identities.isEmpty) {
      log.warn('Keine Identitäten gefunden');
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

    // Create primary identity context (first identity)
    final primaryId = identities.first;
    // Load master seed if available (for HD-Wallet key derivation)
    final masterSeed = mgr.loadMasterSeed();

    final primaryCtx = IdentityContext(
      profileDir: primaryId.profileDir,
      displayName: primaryId.displayName,
      networkChannel: NetworkSecret.channel.name,
      hdIndex: primaryId.hdIndex,
      masterSeed: masterSeed,
      createdAt: primaryId.createdAt,
      isAdult: primaryId.isAdult,
    );
    await primaryCtx.initKeys();
    primaryId.nodeIdHex = primaryCtx.userIdHex;

    // Create ONE shared node
    final node = CleonaNode(
      profileDir: routingDir,
      port: nodePort,
      networkChannel: NetworkSecret.channel.name,
    );
    node.primaryIdentity = primaryCtx;
    _node = node;

    // Register primary identity
    _contexts[primaryCtx.userIdHex] = primaryCtx;

    // Create contexts for all other identities. initKeys() runs in isolates
    // (PQ-Keygen 15-30s on fresh profiles) — parallelize so total startup
    // time does not scale linearly with identity count.
    final secondaryPairs = <({Identity id, IdentityContext ctx})>[];
    for (var i = 1; i < identities.length; i++) {
      final id = identities[i];
      final ctx = IdentityContext(
        profileDir: id.profileDir,
        displayName: id.displayName,
        networkChannel: NetworkSecret.channel.name,
        hdIndex: id.hdIndex,
        masterSeed: masterSeed,
        createdAt: id.createdAt,
        isAdult: id.isAdult,
      );
      secondaryPairs.add((id: id, ctx: ctx));
    }
    await Future.wait(secondaryPairs.map((p) => p.ctx.initKeys()));
    for (final p in secondaryPairs) {
      p.id.nodeIdHex = p.ctx.userIdHex;
      _contexts[p.ctx.userIdHex] = p.ctx;
    }

    // Register all identities with the node (before start, so routing table rejects them)
    for (final ctx in _contexts.values) {
      node.registerIdentity(ctx);
    }

    // Route incoming messages to the correct service
    node.onMessageForIdentity = _onMessageForIdentity;

    // Notify GUI when peer addresses change (e.g. bootstrap discovers public IP)
    node.onPeersChanged = () {
      for (final service in _services.values) {
        service.onStateChanged?.call();
      }
    };

    // Start the shared node
    await node.startQuick(bootstrapPeers: config.bootstrapPeers);
    log.info('Node gestartet auf Port $nodePort, ${_contexts.length} Identitäten');

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

    // Services ready — replay any messages that arrived during startup
    _replayEarlyMessages();

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

    // PID file (lock file already written in main())
    final pidFile = File('${config.baseDir}/cleona.pid');
    pidFile.writeAsStringSync('$pid');

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
    // Added 2026-04-24 after Alice's daemon hung silently from 15:10:20 to
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
  }

  // Buffer for messages that arrive before services are ready.
  final _earlyMessages = <(dynamic, dynamic, int, IdentityContext?)>[];
  bool _servicesReady = false;

  /// Replay buffered messages after services are created.
  void _replayEarlyMessages() {
    _servicesReady = true;
    if (_earlyMessages.isEmpty) return;
    log.info('Replaying ${_earlyMessages.length} early messages');
    final buffered = List.of(_earlyMessages);
    _earlyMessages.clear();
    for (final (env, from, port, id) in buffered) {
      _onMessageForIdentity(env, from, port, id);
    }
  }

  void _onMessageForIdentity(dynamic envelope, dynamic from, int port, IdentityContext? identity) {
    // Buffer messages that arrive before services are ready
    if (!_servicesReady) {
      _earlyMessages.add((envelope, from, port, identity));
      return;
    }

    if (identity != null) {
      final service = _services[identity.userIdHex];
      if (service == null) {
        final env = envelope as proto.MessageEnvelope;
        log.warn('No service for identity ${identity.userIdHex.substring(0, 8)} '
            '(type=${env.messageType}, services=${_services.keys.map((k) => k.substring(0, 8)).toList()})');
      }
      service?.handleMessage(envelope, from, port);
    } else {
      // recipientId didn't match or empty — route by message type
      final env = envelope as proto.MessageEnvelope;
      final isFragment = env.messageType == proto.MessageType.FRAGMENT_STORE ||
          env.messageType == proto.MessageType.FRAGMENT_RETRIEVE ||
          env.messageType == proto.MessageType.FRAGMENT_STORE_ACK;

      if (isFragment) {
        // Fragments: let each service check mailbox ownership
        for (final service in _services.values) {
          service.handleMessage(envelope, from, port);
        }
      } else if (env.groupId.isNotEmpty) {
        // Group messages: route only to services that are members of this group
        final groupIdHex = bytesToHex(Uint8List.fromList(env.groupId));
        var routed = false;
        for (final service in _services.values) {
          if (service.groups.containsKey(groupIdHex) ||
              service.channels.containsKey(groupIdHex)) {
            service.handleMessage(envelope, from, port);
            routed = true;
          }
        }
        if (!routed) {
          // Fallback: try all services (may be a new group invite)
          for (final service in _services.values) {
            service.handleMessage(envelope, from, port);
          }
        }
      } else {
        // Unknown routing: try all services
        for (final service in _services.values) {
          service.handleMessage(envelope, from, port);
        }
      }
    }
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

    final ctx = IdentityContext(
      profileDir: identity.profileDir,
      displayName: displayName,
      networkChannel: NetworkSecret.channel.name,
      hdIndex: identity.hdIndex,
      masterSeed: mgr.loadMasterSeed(),
      createdAt: identity.createdAt,
      isAdult: identity.isAdult,
    );
    await ctx.initKeys();
    identity.nodeIdHex = ctx.userIdHex;
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
    if (_running) await stopAll();
    final lockFile = File('${config.baseDir}/cleona.lock');
    if (lockFile.existsSync()) lockFile.deleteSync();
    tray.dispose();
    exit(0);
  }

  /// Event-driven network change detection.
  /// Start the ReminderService for all identity calendars.
  void _startReminderService() {
    final reminderService = ReminderService();
    final calendars = <String, CalendarManager>{};
    for (final entry in _services.entries) {
      calendars[entry.key] = entry.value.calendarManager;
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
    reminderService.start(calendars);
    _reminderService = reminderService;
    log.info('Reminder service started for ${calendars.length} identity calendars');
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
      // Windows: poll for network changes every 30s (no ip monitor equivalent)
      _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (!_running) return;
        await _node?.onNetworkChanged();
        for (final service in _services.values) {
          service.onNetworkChanged();
        }
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
            service.onNetworkChanged();
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

        final oldIp = node.natTraversal.publicIp;
        if (force && oldIp != null && oldIp == ip) {
          log.info('ipify recheck: public IP unchanged ($ip)');
          return;
        }

        if (force && oldIp != null && oldIp != ip) {
          log.info('Public IP CHANGED: $oldIp → $ip — resetting NAT, broadcasting update');
          node.natTraversal.reset();
        }

        log.info('Public IP via ipify: $ip — starting port probe');
        node.natTraversal.setExternalIpOnly(ip);
        node.probePublicPort(ip);
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

/// Check if a process with the given PID is alive.
bool _isProcessAlive(int pidToCheck) {
  try {
    if (Platform.isWindows) {
      final result = Process.runSync('tasklist', ['/FI', 'PID eq $pidToCheck', '/NH']);
      return result.stdout.toString().contains('$pidToCheck');
    } else {
      return Process.runSync('kill', ['-0', '$pidToCheck']).exitCode == 0;
    }
  } catch (_) {
    return false;
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
  final List<String> bootstrapPeers;
  final String? iconPath;

  _DaemonConfig({
    required this.baseDir,
    this.port,
    this.bootstrapPeers = const [],
    this.iconPath,
  });
}

_DaemonConfig _parseArgs(List<String> args) {
  String? baseDir;
  int? port;
  final bootstrapPeers = <String>[];
  String? iconPath;

  // Legacy: --profile and --name still accepted for compatibility
  String? legacyProfile;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--base-dir':
        if (i + 1 < args.length) baseDir = args[++i];
        break;
      case '--profile':
        // Legacy: single-identity profile dir
        if (i + 1 < args.length) legacyProfile = args[++i];
        break;
      case '--port':
        if (i + 1 < args.length) port = int.tryParse(args[++i]);
        break;
      case '--name':
        // Legacy: ignored in multi-identity mode
        if (i + 1 < args.length) i++;
        break;
      case '--bootstrap-peer':
        if (i + 1 < args.length) bootstrapPeers.add(args[++i]);
        break;
      case '--icon':
        if (i + 1 < args.length) iconPath = args[++i];
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
    bootstrapPeers: bootstrapPeers,
    iconPath: iconPath,
  );
}
