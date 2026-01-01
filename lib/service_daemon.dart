import 'package:cleona/core/service/mycelium_seam.dart';
import 'package:cleona/core/update/data_port_http.dart';
import 'package:cleona/core/util/host_interfaces.dart';
import 'package:mycelium/host.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity/identity_remote_deletion.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/ipc/ipc_probe.dart';
import 'package:cleona/core/ipc/ipc_server.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/log/log_redaction.dart';
import 'package:cleona/core/util/local_addresses.dart'
    show dialableLocalAddresses, isRealNetworkChange;
import 'package:cleona/core/tray/native_tray.dart';
import 'package:cleona/core/tray/tray_status.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/reminder_service.dart';
import 'package:cleona/core/calendar/sync/caldav_server.dart';
import 'package:cleona/core/service/notification_sound_service.dart' show VibrationType;
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/update_offer.dart';
import 'package:cleona/core/update/update_manifest.dart' show UpdateChecker;
import 'package:cleona/core/contact/contact_seed.dart';

/// Holds the machine-global single-instance flock (§15.1) for the entire
/// process lifetime. Top-level so it is NEVER garbage-collected — a block- or
/// method-scoped RandomAccessFile would be finalized once out of scope, closing
/// the fd and silently releasing the lock (observed 2026-05-30: a second daemon
/// then slipped past Guard 2 to the IPC-socket check).
RandomAccessFile? _machineGlobalLockRaf;

/// The marker with the UDP port that THIS run actually bound.
///
/// Purely for process coordination, like `cleona.pid` / `cleona.lock` /
/// `cleona.ready` / `cleona.sock` — it carries a port number and nothing
/// else. Written as soon as the V4.1 node is up; deleted on an orderly
/// stop and also by Guard 3 as soon as the recorded port is demonstrably
/// free (then the marker was the corpse of a run that no longer
/// exists).
///
/// It replaces reading `identities.json` in Guard 3 — see the
/// reasoning there (the port probed until S368 was bound by no
/// daemon).
const String _udpPortFilename = 'cleona.udp';

/// Process name behind [targetPid], or `null` when the process does not exist
/// or cannot be queried.
///
/// Used by Guard 0 to decide whether a PID from `cleona.pid` still belongs to a
/// daemon. Two properties matter and neither is optional:
///
///  * **Platform-correct.** The previous implementation called `kill -0` on
///    every platform. Windows has no `kill` (verified on the test VM: `where
///    kill` finds nothing), so `Process.runSync` threw `ProcessException` —
///    swallowed by a `catch (_)` meant for corrupt PID files, which made
///    Guard 0 a silent no-op there. Guard 1/2 still covered Windows (§15.1
///    names the machine-global lock as the authority), but the defence-in-depth
///    layer was missing.
///  * **Name-checked, not just alive-checked.** PIDs are recycled. A stale
///    `cleona.pid` whose number now belongs to an unrelated process would
///    otherwise block every future start. Callers compare against their OWN
///    process name rather than a hardcoded string, which stays correct for both
///    the AOT binary (`cleona-daemon`) and `dart run lib/service_daemon.dart`
///    in development.
String? _processNameOf(int targetPid) {
  try {
    if (Platform.isWindows) {
      // tasklist exits 0 even when nothing matches and reports the miss as
      // localized prose ("INFORMATION: Es konnten keine ..." on the German
      // test VM), so the text is useless as a signal. The CSV row is not:
      //   "cleona-daemon.exe","4840","Console","1","123.456 K"
      // Field 0 is the image name, field 1 the quoted PID.
      final r = Process.runSync(
          'tasklist', ['/FI', 'PID eq $targetPid', '/NH', '/FO', 'CSV']);
      if (r.exitCode != 0) return null;
      final line = (r.stdout as String)
          .split('\n')
          .firstWhere((l) => l.contains('"$targetPid"'), orElse: () => '');
      if (line.isEmpty) return null;
      final name = line.split('","').first.replaceAll('"', '').trim();
      return name.isEmpty ? null : name;
    }
    // Linux/macOS: `ps` exits non-zero when the PID is gone. `comm` is the
    // executable name without arguments, capped at 15 chars on Linux —
    // "cleona-daemon" (13) fits, and self-comparison makes the cap harmless
    // even if it did not.
    final r = Process.runSync('ps', ['-p', '$targetPid', '-o', 'comm=']);
    if (r.exitCode != 0) return null;
    final name = (r.stdout as String).trim();
    return name.isEmpty ? null : name;
  } on ProcessException {
    return null; // query tool unavailable — treat as "cannot confirm alive"
  }
}

/// Cleona service daemon — runs independently of the GUI.
/// One daemon, one port, one node — all identities active simultaneously.
void main(List<String> args) {
  // Captured for the zone error handler: CLogger.get without profileDir
  // buffers NOTHING (key `daemon:null`, no file sink) — an uncaught error
  // logged that way is lost when the GUI drains the daemon's stderr
  // (S122: exit(99) left zero trace in any log).
  String? zoneLogBaseDir;
  runZonedGuarded(() async {
    final config = _parseArgs(args);

    if (config.exportContactSeed) {
      await _exportContactSeed(config);
      return;
    }

    zoneLogBaseDir = config.baseDir;
    final log = CLogger.get('daemon', profileDir: config.baseDir);

    log.info('Starting Cleona daemon...');
    log.info('Base dir: ${config.baseDir}');
    log.info('Port: ${config.port ?? "(auto — from identity)"}');
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
          // Guard 0 may only fire when the PID still belongs to a daemon of
          // OUR kind. Comparing against our own process name covers both the
          // compiled binary and `dart run` without hardcoding either, and it
          // keeps a recycled PID in a stale cleona.pid from locking us out.
          final otherName = _processNameOf(otherPid);
          final ownName = _processNameOf(pid);
          if (otherName != null && ownName != null && otherName == ownName) {
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
    // openSync gets its OWN try. Two reasons, both measured:
    //  1. It really can throw — a non-writable baseDir yields
    //     PathAccessException (EACCES), and `Directory.createSync` above is a
    //     no-op on an existing-but-unwritable dir, so it does not shield us.
    //  2. An escaping FileSystemException does NOT crash the daemon: the zone
    //     handler treats `is IOException` as survivable (see isSurvivable
    //     below), so there is no exit — and CLogger's 2s flush timer keeps the
    //     event loop alive. The result is a half-initialised zombie with no
    //     IPC and no port file. Same failure shape as W-1: not a clean death,
    //     but a wrong survival.
    // The catch below must stay separate from the lock() catch: an open error
    // is NOT "another daemon holds the lock", and reporting it as such sends
    // whoever reads the log hunting for a process that does not exist.
    final RandomAccessFile lockRaf;
    try {
      lockRaf = lockFile.openSync(mode: FileMode.write);
    } on FileSystemException catch (e) {
      stderr.writeln('ERROR: Cannot open lock file ${lockFile.path}: '
          '${e.osError?.message ?? e.message}');
      log.info('Lock file open failed: $e — exiting.');
      await CLogger.flushAll();
      exit(1);
    }
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
      // Same split as Guard 1, and here it matters more: at this point we
      // ALREADY hold the Guard-1 flock on cleona.lock. A zombie surviving an
      // open error would keep holding it, so every later start would fail with
      // "Another Cleona daemon holds the lock file" while no daemon is running
      // — a self-inflicted permanent lockout with a misleading message.
      try {
        _machineGlobalLockRaf = globalLock.openSync(mode: FileMode.write);
      } on FileSystemException catch (e) {
        stderr.writeln('ERROR: Cannot open machine-global lock $globalLockPath: '
            '${e.osError?.message ?? e.message}');
        log.info('Machine-global lock open failed: $e — exiting.');
        await CLogger.flushAll();
        exit(1);
      }
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

    // Guard 2: the IPC endpoint belongs to another CLEONA daemon.
    //
    // ── "IS SOMETHING LISTENING" WAS A PROXY (finding 3, S370) ────
    //
    // Until S370 a bare `Socket.connect` stood here: if it succeeds, the
    // endpoint counts as taken. On Windows the port number is EPHEMERAL
    // (49152-65535) and sits in a file that survives a hard abort —
    // some other program gets it. Reproduced on 06.09.2026 on the build
    // VM with a plain PowerShell TcpListener: the daemon no longer
    // started, reported "Another daemon is listening on TCP port 49999"
    // (there was none) and did NOT DELETE the port file, because the
    // deletion lay in the `catch` branch. Permanent lock-out.
    //
    // Now the endpoint is QUERIED: authenticated `ping` with the token
    // from the same port file, the answer must be `{'pong': true}`
    // (`cleonaIpcEndpointAnswers`). A foreign listener does not answer.
    // Why no PID check: Guard 0 above already leaves the process when a
    // live PID with the same process name exists, the conjunction would
    // be dead code — and the job of Guard 2 is precisely the daemon that
    // Guard 0 and 1 have lost (`cleona.lock` AND `cleona.pid` deleted
    // from outside). There the endpoint is the only witness.
    //
    // An unconfirmed endpoint now ALWAYS clears away the port file
    // — even if something is listening there. That is the direction in
    // which this third bolt may fall: Guard 0 and Guard 1 carry the
    // single-instance promise (both proven in a run on Windows on 06.09.),
    // and a false "taken" locks the user out permanently.
    if (Platform.isWindows) {
      // Windows: TCP loopback — check port file (format: port:token)
      final portFile = File('${config.baseDir}/cleona.port');
      if (portFile.existsSync()) {
        String? content;
        try {
          content = portFile.readAsStringSync();
        } catch (_) {
          content = null;
        }
        final endpoint = parseCleonaPortFile(content);
        final proven = endpoint == null
            ? false
            : await cleonaIpcEndpointAnswers(
                port: endpoint.port, token: endpoint.token);
        if (proven) {
          stderr.writeln(
            'ERROR: Another Cleona daemon owns the IPC endpoint on TCP port '
            '${endpoint.port}. Stop the running process first.');
          log.info('Cleona daemon answered ping on TCP port '
              '${endpoint.port}, exiting.');
          await CLogger.flushAll();
          exit(1);
        }
        log.info('Stale cleona.port (${endpoint == null ? 'unreadable' : 'Port '
            '${endpoint.port}'}) — no Cleona daemon answered; removing it.');
        try { portFile.deleteSync(); } catch (_) {}
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
    // lock file was deleted but are still holding the port). Dart sets the
    // process name to "dart:cleona-dae" (truncated to 15 chars), which makes
    // pkill -x matching unreliable and leaves killed-by-checksum but not
    // actually-killed processes around across redeploys.
    //
    // ── UNTIL S368 THIS CHECK MEASURED A PORT THAT NOBODY HOLDS ────
    //
    // It read the port from `identities.json` (`identities.first.port`) —
    // and exactly this port was **not** bound by the daemon between the CUT
    // and S374. `_startAllInner` computed `v41Port = nodePort + 1` back then
    // and passed ONLY that one to `startV41Node`; `nodePort` itself stayed
    // free. Re-measured on 05.09.2026 on a running daemon (profile
    // with `port: 34260`):
    //
    //     "[daemon] V4.1-Knoten gestartet auf Port 34261, 1 Identitäten"
    //     $ ss -lunap | grep pid=174331
    //     UNCONN 0 0  0.0.0.0:34261 ... fd=22
    //     UNCONN 0 0  0.0.0.0:41340 ... fd=26   (LAN entry)
    //     UNCONN 0 0  0.0.0.0:57123 ... fd=27
    //
    // 34260 appears on no line. So the check could not find a zombie
    // — and conversely would have fired on the next start if some
    // FOREIGN process happened to sit on 34260. A proxy that is wrong in
    // both directions.
    //
    // ── WHAT IT MEASURES NOW ──────────────────────────────────────────
    //
    // The port that a running daemon ACTUALLY bound. The daemon
    // writes it to `cleona.udp` on start-up (see
    // `_startAllInner`, next to `cleona.ready`) and clears it away on an
    // orderly stop. That is the same rank as `cleona.pid`,
    // `cleona.lock`, `cleona.ready`, `cleona.sock` — pure
    // process coordination, no identity knowledge.
    //
    // ── AND WHY NO LONGER FROM `identities.json` ──────────────────────
    //
    // In addition to the measurement error: since S368 the file is stored
    // encrypted (`identities.json.enc`, device-wide key from the
    // master seed). Here — before `IdentityContext.initCrypto` — there is
    // no keyring yet, hence no seed, hence no key. Pulling the keyring
    // forward is NOT an option: `initCrypto` explicitly requires that
    // `FirstStartWipe` is its first line, and `KeyringService.init` creates
    // `.keyring_salt`. The port therefore belongs where it originates —
    // to the run, not to the identity.
    int? probePort;
    try {
      final portFile = File('${config.baseDir}/$_udpPortFilename');
      if (portFile.existsSync()) {
        probePort = int.tryParse(portFile.readAsStringSync().trim());
      }
    } catch (_) { /* unreadable — then no port check */ }
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

    // The same for the port marker: if we got this far, the port recorded
    // there was free — so the marker stems from a run that no longer
    // exists. Deleting it here keeps it self-healing; otherwise a value
    // would remain that at some point belongs to a foreign process and
    // rejects the next start for no reason.
    try {
      final portFile = File('${config.baseDir}/$_udpPortFilename');
      if (portFile.existsSync()) portFile.deleteSync();
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
    // A failed console write arrives here as an unhandled async error (Dart's
    // stdout/stderr flush asynchronously, so the exception escapes the
    // try/catch at the call site). Reporting it through stderr/CLogger below
    // would write to the same dead sink and generate the next error — the
    // feedback loop that killed the Windows daemon before it ever wrote
    // cleona.port. Shut the console down first, then report to file only.
    if (error is FileSystemException && CLogger.consoleEnabled) {
      CLogger.disableConsole('zone');
    }
    if (CLogger.consoleEnabled) {
      try { stderr.writeln(msg); } catch (_) { CLogger.disableConsole('zone'); }
    }
    try {
      final log = CLogger.get('daemon', profileDir: zoneLogBaseDir);
      log.error(msg);
      await CLogger.flushAll();
    } catch (_) {}
    // Sync fallback sink — survives even if CLogger's buffer/flush path is
    // the thing that broke: append directly next to the regular logs.
    try {
      if (zoneLogBaseDir != null) {
        // This sink bypasses CLogger's BUFFERING, not its
        // REDACTION. `LogRedaction.apply` is a pure function without
        // state in CLogger — it holds even when exactly the
        // flush path is what is broken. Measured on 06.09.2026, otherwise
        // a home path lay here in plain text.
        File('$zoneLogBaseDir/daemon-crash.log').writeAsStringSync(
            '${DateTime.now().toIso8601String()} ${LogRedaction.apply(msg)}\n',
            mode: FileMode.append, flush: true);
      }
    } catch (_) {}
    final isSurvivable = error is TimeoutException ||
        error is SocketException ||
        error is IOException ||
        (error is StateError && error.message.contains('DhtRpc disposed'));
    if (!isSurvivable) exit(99);
  });
}

/// Runs ONE V4.1 node with SEVERAL CleonaServices (one per identity).
class _MultiServiceDaemon {
  final _DaemonConfig config;
  final CLogger log;
  final NativeTray tray;

  /// Carries readiness and connection level to the tray (§22.9).
  ///
  /// EVENT-DRIVEN, no timer: [_bindIdentityToTray] hooks itself
  /// onto `service.onStateChanged` — the same edge the IPC server
  /// already uses. No network traffic arises (working rule 5), and
  /// the binder only passes on what has changed.
  late final TrayStatusBinder _trayStatus =
      TrayStatusBinder(sink: tray.updateStatus);

  /// The ONE mycelium host of this process (S387, V4.2 §4.5.1): one node,
  /// one port, one mailbox per identity. Replaces `V41Runtime` +
  /// `V41Host` per identity.
  ///
  /// It holds the wire and the state checker — `shutdownAll()` MUST
  /// stop it, otherwise a timer keeps the Dart VM alive.
  Host? _host;

  /// The same key as `_host`'s (`hostKey`, set on
  /// start) — held for the port mapping (task D): its edge
  /// network change lies in `_startNetworkMonitor`, a separate method
  /// without the start method's local `masterSeedForHost`.
  Uint8List? _masterSeedForHost;

  /// The HTTP delivery at the host port (§26.6.5, S386 part A).
  DataPortHttp? _delivery;
  final Map<String, CleonaService> _services = {}; // nodeIdHex → service

  /// The one update offer of this daemon (§26.5.4: one node, one
  /// offer across all identities). It originates in [_startAllInner] and
  /// is bound there to the services' callbacks; it is held here
  /// because [_updateManifestAsk] must reach it at the edges (E-9,
  /// package 10 = A). Before the first start it is `null` — then there is
  /// also nothing to repeat.
  UpdateOffer<CleonaService>? _updateOffer;
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
        log.info('Start trigger from GUI detected');
        startAll();
      }
    }
  }

  Future<void> startAll() async {
    if (_running) return;
    _running = true;
    log.info('Service is starting...');

    // §3.7: Initialize crypto subsystem (shared sequence — S106 fix)
    await IdentityContext.initCrypto(config.baseDir);

    // Load all identities
    final mgr = IdentityManager(baseDir: config.baseDir);
    var identities = mgr.loadIdentities();
    if (identities.isEmpty) {
      log.warn('No identities found — waiting for GUI setup (cleona.start trigger)');
      _running = false;
      return;
    }

    try {
      await _startAllInner(identities, mgr);
    } catch (e, stack) {
      log.error('Service start failed: $e');
      log.error('Stack: $stack');
      // Critical: exit on startup failure (e.g. port already in use).
      // Without this, the daemon stays alive as a zombie — holding the lock
      // file but without transport, socket, or any useful functionality.
      await shutdownAll();
    }
  }

  Future<void> _startAllInner(List<Identity> identities, IdentityManager mgr) async {

    // Use configured port, or first identity's port
    // THE DEVICE'S PORT, not that of the first identity (S374, §11).
    // `identities.first.port` stood here until S374 and made a
    // LIST POSITION the decisive quantity: deleting the first
    // identity silently changed the bound port of the whole device,
    // along with firewall exception, port mapping and every published
    // entry hint.
    final nodePort = config.port ?? mgr.deviceDataPort;

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

    // The directory is now only needed for the entry pool and the
    // node keys; the V3 routing table for which it was originally
    // created no longer exists.
    if (routingDir.isEmpty) throw StateError('routingDir leer');

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

    // ── THE ASSERTION FROM `NodeHost.adoptIdentities` (carried over, CUT) ─
    //
    // `NodeHost.adoptIdentities` threw if the passed view was empty
    // or did not contain the primary identity. The reason was a
    // field finding: `_contexts.values` is a LIVE view on a map
    // that the caller has yet to fill. If the call stood one line too
    // early, the node registered NOTHING, but started up completely —
    // and afterwards discarded every service-routed frame. Between
    // 8b387931 and S348 exactly that was in the field: no contact came
    // about. A quiet nothing was the most expensive outcome.
    //
    // The registration itself went away with `CleonaNode` — V4.1
    // hangs on the service per identity via `attachV41`, there is no
    // identity table at the node any more. THE CHECK STAYS, because the
    // error class stays: the loop further below that calls
    // `attachV41` runs over the same live view, and if it runs zero times,
    // the delivery layer hangs on nothing. The outcome would be the same:
    // daemon up, everything silent.
    if (_contexts.isEmpty) {
      throw StateError('Identity collection is empty — the V4.1 delivery '
          'would hang on nothing, and the daemon would start up mute. Called too '
          'early?');
    }
    if (!_contexts.values.any((ctx) => identical(ctx, primaryCtx))) {
      throw StateError('The primary identity is missing from the collection '
          '(primary=${primaryCtx.displayName}, all=${_contexts.length}).');
    }

    // ── THE V3 RECEIVE SIDE IS GONE (CUT, 31.08.) ────────────────────
    //
    // 216 lines stood here: `host.wireReceive(...)` with the
    // ApplicationFrame dispatcher (KEM try loop over all hosted
    // identities) and the infrastructure switch with 24 `MessageTypeV3`
    // selectors (CONTACT_REQUEST, FRAGMENT_*, PEER_*, SYSCHAN_*,
    // DEVICE_KEM_*, POLL_ANON_*, GUARDIAN_*), plus
    // `host.wireEvents(onPeersChanged:)`.
    //
    // IT IS A PURE SELECTOR LIST OVER A WIRE THAT NO LONGER
    // EXISTS. `InfrastructureFrameV3`/`NetworkPacketV3` originated in
    // `CleonaNode`; without the node nobody calls the hooks, and no
    // frame of this kind reaches this process. The handlers on the
    // service side fell with the ten `cleona_service_v3_*.dart`.
    //
    // V4.1 receives at a different place: `attachV41` (further below)
    // hooks in the read side per identity — `V41Host.accept`,
    // `MessageSealer.open`, `Aggregate.unpack`. There is nothing here to
    // carry over, only to take away.
    //
    // OPEN AND REPORTED: `onPeersChanged` was the signal with which the
    // UI learned about address changes via `service.onStateChanged`.
    // V4.1 today has no producer for it.

    // Windows: ensure firewall allows inbound UDP for the daemon process.
    if (Platform.isWindows) {
      await _ensureWindowsFirewallRule();
    }

    // ── THE V4.1 NODE IS NOW THE START PATH (CUT, 31.08.) ─────────
    //
    // Up to here stood `await host.start()` — the V3 node —, and the
    // V4.1 delivery was hung alongside 90 lines further below.
    // The other way round does not work: `CleonaService` gets its `port` from
    // this node, so it must stand BEFORE the service loop.
    //
    // §4.11.9 Infrastructure Rendezvous went away with it and is
    // NOT replaced: its only consumer in `lib/` was
    // `CleonaNode.infraRendezvousManager` (re-measured over `lib/` and
    // `bin/` — otherwise only comments and `smoke_rendezvous_secret_
    // rotation.dart`). V4.1's external rendezvous is a different
    // thing and already lies IN `startV41Node`: step 3 of the
    // entry cascade via `ExternalEntrySource` + `NostrRendezvous`
    // (`v41_attach.dart:384-397`). Running two rendezvous systems
    // side by side would be the duplication that this cut
    // removes.
    // ── THE ENVELOPE FOR `node_keys.enc` AND THE POOL (S362) ───────
    //
    // Until S362 `FileEncryption(baseDir: …)` stood here WITHOUT a key —
    // the legacy path from `file_encryption.dart:23`, which loads
    // OR CREATES `db.key`: 32 random bytes in the SAME directory as the
    // ciphertext. Against a second local user that holds (`0600`), against
    // a stolen device, a disk image or a backup it does not.
    //
    // The right key is the DEVICE-WIDE, seed-derived one:
    // `node_keys.enc` and the entry pool are per NODE, not per
    // identity (§2.6 "per-node", §3.5.2 "node-level, identity-free"),
    // and lie at the profile root directory — the same class as
    // `device_keys.bin`, which already lies under `deriveSharedFileEncKey`
    // (`identity_context.dart:407-409`). `deriveFileEncKey(seed, hdIndex)`
    // would be wrong here: it would give one envelope PER IDENTITY for a
    // file of which there is exactly one.
    //
    // The existing files migrate in `KeyMigration.migrateDeviceScopedFiles`
    // (called in `IdentityContext.initCrypto`) from the old key to this
    // one — BEFORE this call, because `NodeKeys.loadOrCreate` is
    // fail-loud and would turn a container that did not migrate along into
    // a start error instead of silently regenerating it.
    //
    // `null` means "no master seed" (linked device, §7.6.2) and
    // deliberately falls back to the legacy path: there is nothing to derive
    // there, and a node without `node_keys.enc` would not be reachable.
    //
    // S387: `node_keys.enc` no longer has a reader with the V4.1 node. The
    // key stays — it now protects `mycelium/host.enc` and
    // `mycelium/post_box.enc` (`hostKey`), the same class.
    final masterSeedForHost = masterSeed;
    // Held for the network-change edge of the port mapping (task D),
    // which lies in a separate method (`_startNetworkMonitor`).
    _masterSeedForHost = masterSeedForHost;

    // ── THE PORT IS THE ONE PASSED IN. THE `+1` OFFSET IS GONE (S374) ─
    //
    // `nodePort + 1` stood here. The `+1` was the COEXISTENCE OFFSET from
    // the time when V3 and V4.1 ran on the same host: introduced
    // with the CUT commit `62151c46` (31.08.2026), whose prior state
    // started both nodes side by side —
    //
    //     port: nodePort,        // V3
    //     port: nodePort + 1,    // V4.1 alongside
    //
    // With the cut V3 fell. The offset stayed and thereby went from
    // fallback port to the ONLY port: nobody has bound `nodePort`
    // since.
    //
    // For a node with a randomly drawn port that is invisible. For
    // the bootstrap it is deadly, because its port is not a free
    // choice but nailed down externally — the firewall opens 8081 for
    // beta (live 8080). Measured on 07.09.2026 on the bootstrap:
    // started with `--port=8081`, logged `Port: 8081`, but bound
    // and announced 8082; `ss -ulnp` showed 8081 on no line.
    // So the port forwarding pointed to a port without a listener,
    // and the announced address to a port without forwarding.
    //
    // The reasoning for keeping it that formerly stood here
    // (neighbours would have `nodePort + 1` in still valid
    // entry records) does not hold: V4.1 knows no
    // legacy-data compatibility, and a special case only for the
    // bootstrap would be exactly what the owner decision from S372
    // rules out — "only the bootstrap may have a fixed port,
    // announced in the ContactSeed, WITHOUT a special case in code".
    //
    // Side effect that is healed along with it: `DataPort.drawDataPort()`
    // excludes `lanDiscoveryPort` (41338) and `browserUnsafePort`
    // (10080). With the offset this exclusion protected the
    // wrong value — a draw of 41337 bound 41338, one of 10079
    // bound 10080, and 41339 bound `kLanEntryPort` (41340), which is not
    // on the list at all. Without the offset the exclusion again applies
    // to the port that is also bound.
    //
    // The same cut at the two other start paths:
    // `lib/main.dart` (GUI in-process) and
    // `lib/core/platform/ios_background_fetch.dart`.
    //
    // S387: the port is now bound by the mycelium host — and it starts
    // AFTER the service loop (see there, `hostStart`). The services
    // get the device port in advance; `serviceRegister` sets it on
    // attachment to the one actually bound.

    // ── THE UPDATE IS OFFERED, NOT INSTALLED (S387) ─────────────
    //
    // Owner decision 14.09.2026 (v4_2 §26.5.4, §26.6.1 steps 4-6):
    // collect automatically, only offer what is finished, install ONLY
    // after the click. Here stood "Auto-download + auto-install for daemon
    // (no GUI to click)" — the daemon installed immediately on `ready`. That
    // was right as long as `ready` only came after the download click; since
    // collecting runs automatically, it would be an installation without
    // consent. The click comes as IPC `apply_update` from the GUI
    // (`ipcServer.onApplyUpdate` below).
    //
    // Collecting happens at ONE identity — the first one that reports an
    // in-network distributed manifest; all read the same (`UpdateOffer`).
    final updateOffer = _updateOffer = UpdateOffer<CleonaService>(
      assemble: (svc, manifest) => svc.startInNetworkUpdate(manifest),
      install: (svc) async {
        final mgr = svc.binaryUpdateManager;
        if (mgr == null) {
          log.warn('apply_update: no binaryUpdateManager');
          return false;
        }
        log.info('apply_update: user agreed — installing '
            'v${mgr.targetVersion}');
        return _applyAndRestart(mgr, log, shutdownAll);
      },
      isNew: (a, b) => UpdateChecker(log: log).isNewer(a, b),
      report: log.info,
    );

    // Create and start a CleonaService for each identity
    for (final ctx in _contexts.values) {
      final service = CleonaService(
        identity: ctx,
        displayName: ctx.displayName,
        // The device port in advance; the host binds it after this loop,
        // and `serviceRegister` sets the one actually bound (S387).
        port: nodePort,
      );
      // S388: here a `--bootstrap` mode accepted every contact request
      // AUTOMATICALLY. V4.2 §12.5: "A contact exists only after an explicit
      // acceptance" — and §11.7: no node has a special role. Removed.
      // Wire badge count to tray icon
      service.onBadgeCountChanged = (count) => _updateTrayBadge();
      // §22.9: readiness and connection level to the tray. MUST stand
      // here and not later — `IpcServer` chains the existing
      // `onStateChanged` at construction (ipc_server.dart:203). Whoever
      // registers afterwards displaces the IPC broadcast; whoever registers
      // before is called along by it.
      _bindIdentityToTray(ctx.userIdHex, service);
      _bindRemoteDeletion(ctx.userIdHex, service);
      // Update callbacks BEFORE startService(): the start reports a
      // cached manifest itself. Sequence (S387): manifest →
      // collect automatically → `ready` → banner in the GUI → click →
      // `apply_update` → installation. A state never installs.
      service.onUpdateAvailable = (manifest, inNetworkAvailable) {
        log.info('Update available: v${manifest.version} (inNetwork=$inNetworkAvailable)');
        updateOffer.onManifest(service, manifest, inNetworkAvailable);
      };
      service.onUpdateStateChanged = (state, progress) {
        updateOffer.onState(service, state);
        if (state == BinaryUpdateState.failed) {
          log.warn('Update: collecting without result — the next occasion '
              'tries again');
        }
        if (state == BinaryUpdateState.ready &&
            identical(updateOffer.source, service)) {
          log.info('Update v${service.binaryUpdateManager?.targetVersion} '
              'checked and ready — waiting for the click');
        }
      };
      await service.startService();
      _services[ctx.userIdHex] = service;
      // ── S369: THE NAME MOVED FROM `info` TO `debug` ───────
      //
      // Owner decision of 02.09.2026 ("display names only on
      // debug", recorded in `smoke_log_kein_nutzerinhalt_guard.dart`).
      // This line did not keep it — and the guard still reported
      // green, because it only read `_log.` and the daemon calls its logger
      // `log` (`:481`, `final CLogger log;`). Measured 06.09.2026: the
      // narrow rule saw 1237 calls, a rule without underscore sees
      // 1342 — 105 calls via `debug` were never checked, and among them
      // lay exactly these three.
      //
      // The damage is the same as the one closed by S368, only under
      // a different file name: the line wrote the display name
      // NEXT TO the user ID into `identities/<id>/logs/cleona_*.log` — in
      // plain text, retained 3 days (live) or 7 days (beta), and sendable
      // to third parties via the bug log channel (§9.5).
      //
      // The IDENTIFIER stays on `info`: it is the routing quantity that
      // is on the wire anyway, and `cleona_service.dart:1631`
      // has always logged it likewise.
      log.info('Service started: ${ctx.userIdHex.substring(0, 16)}...');
      log.debug('Service started — displayName="${ctx.displayName}"');
    }

    // ── THE ONE HOST, ONE MAILBOX PER IDENTITY (S387) ─────────────
    //
    // Replaces `startV41Node` (before the loop) and `attachV41` per
    // identity. AFTER the service loop, because the host collects and
    // delivers immediately on start — an incoming message to a service that
    // has not yet loaded its conversations would be receipted and lost.
    // What `startService` sends beforehand lies in the outbox and goes
    // to the mailbox on attachment (`serviceRegister`).
    //
    // `attachV41` also set `binaerQuellenAusEintritt` and the
    // cover filling (`naechsterTarnfuellungsBlock`/`nimmTarnfuellungsBlock`)
    // here. Neither has a carrier at the mycelium host; since S388 the update
    // goes via `attachUpdateToService` (manifest slot + fetch path, §26.5.4/§26.6.1).
    final host = await hostStart(
      services: _services.values.toList(),
      baseDir: config.baseDir,
      key: hostKey(config.baseDir, masterSeedForHost),
      port: nodePort,
      report: log.info,
    );
    _host = host;
    // The moment "start" (S388): ONE service per process carries the update.
    attachUpdateToService(host, _services.values.first, report: log.info);
    log.info('mycelium host started on port ${host.port}, '
        '${host.mailboxes.length} mailbox(es)');

    // The port mapping (task D, §7.3): asked at this edge, NOT
    // awaited — the RFC 6886 backoff takes eight and a half minutes in the
    // worst case, and the node start must not wait for it.
    unawaited(() async {
      try {
        await portMappingToEdge(
          host,
          baseDir: config.baseDir,
          key: hostKey(config.baseDir, masterSeedForHost),
          report: log.info,
        );
      } catch (e) {
        log.warn('Port mapping: $e');
      }
    }());

    // The port marker for Guard 3 of the NEXT start — here, because the
    // port is demonstrably bound from here on (`hostStart` has
    // returned); `cleona.ready` only falls after the IPC server.
    try {
      File('${config.baseDir}/$_udpPortFilename')
          .writeAsStringSync('${host.port}');
    } catch (_) { /* non-fatal — then Guard 3 is skipped on the next start */ }

    // The HTTP delivery at the host port (§26.6.5, S386 part A): LAN link
    // and invitation link depend on it, delivery does not.
    _delivery = await deliveryForServices(host, _services.values,
        report: log.info);

    // (The boot-window gate `_servicesReady` stood here. It held back the
    // V3 receive hooks during start-up and afterwards had
    // no reader any more — gone together with the hooks.)

    // Save updated nodeIdHex values
    mgr.saveIdentities(identities);

    // IPC socket — ONE socket for all identities
    final socketPath = '${config.baseDir}/cleona.sock';
    final ipcServer = IpcServer(
      services: _services,
      socketPath: socketPath,
      defaultIdentityId: primaryCtx.userIdHex,
      profileDir: config.baseDir,
    );
    ipcServer.onCreateIdentity = _createIdentityAtRuntime;
    ipcServer.onDeleteIdentity = _deleteIdentityAtRuntime;
    ipcServer.onRecoveredIdentity = _startRecoveredIdentity;
    ipcServer.onCalDAVServerGetState = getCalDAVServerState;
    ipcServer.onCalDAVServerSetEnabled = setCalDAVServerEnabled;
    ipcServer.onCalDAVServerRegenerateToken = regenerateCalDAVServerToken;
    ipcServer.onCalDAVServerSetPort = setCalDAVServerPort;
    // The click on [Install] — the ONLY way to installation.
    // Formerly this place asked the manager of the PRIMARY service; since
    // S387 whoever reports first collects, and exactly that one installs.
    ipcServer.onApplyUpdate = () async {
      final ok = await updateOffer.consent();
      if (!ok) {
        log.warn('apply_update: not installed '
            '(state ${updateOffer.state.name}, '
            'running=${updateOffer.installedCurrently})');
      }
    };
    ipcServer.onCommandDispatched = (cmd) {
      log.info('IPC cmd: $cmd');
    };
    // ── THE TRAY'S LANGUAGE COMES FROM THE GUI (V-10-a = b) ───────────
    //
    // Without this edge the tray status text showed the language of the
    // OPERATING SYSTEM, not the one chosen in the GUI. The code travels as a
    // field on an IPC request that is made anyway — no round trip of its own,
    // no timer, no network traffic.
    ipcServer.onUiLocale = (code) {
      log.info('Tray language from the GUI: $code');
      tray.setLocale(code);
    };
    await ipcServer.start();
    _ipcServer = ipcServer;
    log.info('IPC server started — port file written, profileDir=${config.baseDir}');

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

    // §19.6: check for crashed update at startup, mark healthy after 30s.
    final pending = BinaryUpdateManager.checkUpdatePending(config.baseDir);
    if (pending != null) {
      final pendingVer = pending['version'] as String?;
      log.info('[update] Previous update marker found: v$pendingVer');
    }
    Timer(const Duration(seconds: 30), () {
      BinaryUpdateManager.markUpdateHealthy(config.baseDir);
    });

    // (§19.6 auto-download + auto-install callbacks are wired in the
    // service creation loop above, before startService().)

    // Periodic timers
    _statusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_running) return;
      final svcNames = _services.values.map((s) => s.displayName).join(', ');
      // `host.peerCount` were Kademlia peers of the V3 routing table.
      // The V4.1 replacement is NOT the same quantity and is therefore also
      // not named so: `V41Node.status` names slots, sessions by
      // direction and the readiness — evidence instead of acquaintance
      // (§22.7).
      final w = _host;
      log.info('Status: ${w == null ? "no mycelium host" : "mycelium port=${w.port} "
          // S394 V4: a neighbour is a NODE; the addresses are counted apart.
          "neighbours=${w.node.neighbourhood.count} "
          "(addresses ${w.node.neighbourhood.all.fold<int>(0, (s, n) => s + n.addresses.length)}) "
          "mailboxes=${w.mailboxes.length}"}, '
          'identities=${_services.length} [$svcNames]');
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
      // GONE WITH V3 (CUT, 31.08.): `_nodeHost.checkReceiveHealth()`
      // and the firewall blockage warning. Both read state from
      // `CleonaNode.transport` (`externalPacketsReceived`,
      // `firewallWarningEmitted`) — the socket no longer exists.
      //
      // REPORTED GAP, not silently replaced: the
      // firewall detection was the only place where a user
      // learned that their operating system blocks incoming UDP. The
      // equivalent quantity in V4.1 would be "zero incoming datagrams
      // after 60 s" at the `UdpSocketSet`; there it is today only counted, not
      // evaluated.
    });

    _startNetworkMonitor();

    // ── THE V3 ADDRESS MODEL IS GONE (CUT, 31.08.) ─────────────────────
    //
    // Here stood the ipify fallback and its repetition on
    // network change. Both lived in `service_daemon_v3_address.dart`, and
    // its header said so itself: "V4 ch. 4 knows neither hole punching
    // nor port prediction nor a public address that one would have to
    // ask for. Caller AND callee disappear
    // together." The file is deleted.
    //
    // V4.1 determines its announceable addresses itself and without a
    // foreign service: `dialableLocalAddresses()` in `startV41Node`, filtered
    // against DS-Lite/464XLAT, CGNAT and link-local (B-26). What no longer
    // arises in the process is the public address CONFIRMED by NAT probe
    // of a node behind symmetric NAT — that is a
    // reported gap, not a finished task.
    //
    // With them `--public-ip` also goes away: the switch set
    // `CleonaNode.manualPublicIp`. It is still parsed, but has no effect
    // anywhere any more.

    _running = true;
    _trayStatus.setServiceRunning(true);
    log.info('Service started. Socket: $socketPath');

    // Startup-readiness flag for external orchestrators (E2E tests, systemd,
    // restart scripts). Consumers poll for this file instead of guessing with
    // blind sleeps or racy IPC pings — Fix for gui-37.04 daemon-restart hang.
    try {
      File('${config.baseDir}/cleona.ready').writeAsStringSync('$pid');
    } catch (_) { /* non-fatal */ }

    // Socket + profile watchdog: periodic integrity check for critical files.
    // (1) IPC socket: if deleted externally (e.g. by a test script), new IPC
    //     connections silently fail. Recreate on the same path.
    // (2) identities.json + master_seed keyring: if the profile directory is
    //     rm'd while the daemon is running (e.g. E2E cleanup racing against
    //     systemd Restart=always), the daemon continues from RAM but loses all
    //     on-disk identity data. On next restart → "Keine Identitaeten". The
    //     watchdog re-persists from RAM before that restart can happen.
    _socketWatchdog = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_running) return;
      // (1) Socket watchdog
      if (!Platform.isWindows && _ipcServer != null) {
        if (!File(socketPath).existsSync()) {
          log.warn('IPC socket deleted externally — recreating');
          _ipcServer!.rebindSocket();
        }
      }
      // (2) Profile watchdog — only when services are loaded
      if (_services.isNotEmpty) {
        _checkProfileIntegrity(mgr, identities);
      }
    });
  }

  // ── GONE WITH THE V3 RECEIVE SIDE (CUT, 31.08.) ──────────────
  //
  // Here stood `_servicesReady` (boot-window gate of the V3 hooks),
  // `_serviceRecency`, `_orderedServicesByRecency()` and
  // `_markServiceActive()` — together the KEM try-loop heuristic apparatus
  // from §2.4 step [9]: try the most recently supplied identity
  // first, so that an incoming `ApplicationFrameV3` is normally
  // assigned with ONE decap probe.
  //
  // V4.1 does not need it, and for a structural reason: the
  // assignment no longer happens by trying. The pair key
  // `K_AB` is pairwise, `V41Host.accept` knows from the session who
  // is speaking, and `attachV41` hangs exactly one identity on exactly one
  // host. There is no list that one could sort.

  /// Add a new identity at runtime.
  Future<CleonaService?> addIdentity(IdentityContext ctx) async {
    final host = _host;
    if (host == null || !_running) return null;
    if (_services.containsKey(ctx.userIdHex)) return _services[ctx.userIdHex];

    _contexts[ctx.userIdHex] = ctx;

    final service = CleonaService(
      identity: ctx,
      displayName: ctx.displayName,
      port: host.port,
    );
    await service.startService();
    _services[ctx.userIdHex] = service;

    // CATCH UP THE MAILBOX (S387) — the same host, the same port. First
    // the service, then the attachment: the attachment collects immediately.
    // Without it an identity created at runtime would be mute, without
    // an error appearing anywhere.
    serviceRegister(host, service);

    // §22.9: BEFORE `addService`, otherwise the IPC server does not chain our
    // edge — see the reasoning in `_bindIdentityToTray`.
    _bindIdentityToTray(ctx.userIdHex, service);
    _bindRemoteDeletion(ctx.userIdHex, service);

    // Update IPC server
    _ipcServer?.addService(ctx.userIdHex, service);

    // If the local CalDAV server is running, register the new identity
    // so desktop apps can immediately discover its calendar.
    _caldavServer?.registerIdentity(CalDAVServerIdentity(
      fullNodeId: ctx.userIdHex,
      displayName: ctx.displayName,
      calendar: service.calendarManager,
    ));

    // S369: name on `debug`, identifier on `info` — reasoning at
    // "Service started" in `_startAllInner`.
    log.info('Identity added: ${ctx.userIdHex.substring(0, 16)}...');
    log.debug('Identity added — displayName="${ctx.displayName}"');
    return service;
  }

  /// Remove an identity at runtime.
  Future<void> removeIdentity(String nodeIdHex) async {
    final service = _services.remove(nodeIdHex);
    if (service != null) {
      await service.stop();
    }
    _contexts.remove(nodeIdHex);
    // DEREGISTER THIS IDENTITY'S MAILBOX (S387). Without this line
    // the host kept delivering to a stopped service. The last
    // mailbox stays at the node until `stopAll` (`serviceDeregister`).
    final host = _host;
    if (host != null && service != null) {
      serviceDeregister(host, service, report: log.info);
    }
    // And the display (S376, P8): the tray aggregates across all identities
    // — readiness as minimum, partners as maximum. If the removed
    // identity stayed in the aggregate, its last state would pull the
    // display down permanently.
    _trayStatus.unregisterIdentity(nodeIdHex);
    _ipcServer?.removeService(nodeIdHex);
    _caldavServer?.unregisterIdentity(nodeIdHex);
    log.info('Identity removed: $nodeIdHex');
  }

  /// IPC callback: create a new identity at runtime.
  Future<String?> _createIdentityAtRuntime(String displayName) async {
    if (_host == null || !_running) return null;

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

  /// IPC callback: start a recovered identity (from DHT registry).
  /// The Identity record already exists on disk (created by
  /// recoverIdentitiesFromRegistry), just needs an IdentityContext + service.
  Future<void> _startRecoveredIdentity(Identity identity) async {
    if (_host == null || !_running) return;
    final mgr = IdentityManager(baseDir: config.baseDir);
    final ctx = await IdentityContext.createFromIdentity(
      identity: identity,
      baseDir: config.baseDir,
      masterSeed: mgr.loadMasterSeed(),
    );
    final identities = mgr.loadIdentities();
    for (final id in identities) {
      if (id.id == identity.id) {
        id.nodeIdHex = ctx.userIdHex;
        break;
      }
    }
    mgr.saveIdentities(identities);
    await addIdentity(ctx);
    // S369: name on `debug` — reasoning at "Service started".
    log.info('Recovered identity started: '
        '${ctx.userIdHex.substring(0, 16)}... (hdIndex=${identity.hdIndex})');
    log.debug('Recovered identity started — '
        'displayName="${identity.displayName}"');
  }

  // ── P-12: REMOTE DELETION NEEDS A LISTENER ──────────────────
  //
  // `CleonaService.onIdentityDeletedRemotely` had NO assigner in `lib/`
  // until today — declaration `cleona_service.dart:611`, call
  // `cleona_service_identity_deletion.dart:85`, only assignment in
  // a smoke test. In operation the callback was always `null`. The
  // service cleared away its data on the message TWIN_IDENTITY_DELETED
  // and reported upwards, where nobody stood: the identity stayed
  // registered in the running daemon and stayed in `identities.json`
  // — an empty shell. (Gap book P-12, open since S361.)
  //
  // HERE the host hooks in.
  void _bindRemoteDeletion(String nodeIdHex, CleonaService service) {
    service.onIdentityDeletedRemotely = (id) {
      // NOT in the stack of the frame that brought the message.
      // `onIdentityDeletedRemotely` is called synchronously from within
      // `_handleTwinIdentityDeleted`; `removeIdentity` stops exactly the
      // service whose receive path is still on the stack. `Future(…)`
      // puts the work at the END of the event queue (not
      // `Future.microtask`, which would still run into the ongoing
      // continuation), so that the frame is processed to the end first.
      unawaited(Future(() => _identityFernDeleted(id)));
    };
  }

  /// The host part of remote deletion. Body and reasoning are in
  /// `identity_remote_deletion.dart`; here stands only what belongs to THIS
  /// host: the running service and the state of the process.
  Future<void> _identityFernDeleted(String nodeIdHex) async {
    try {
      // Remember the directory BEFORE `removeIdentity` — afterwards the
      // context is removed and the fallback path via `profileDir`
      // (for an entry without `nodeIdHex`) would have no source any more.
      final profileDir = _contexts[nodeIdHex]?.profileDir;

      // First deregister and stop, then delete. The other way round the
      // still running service would have re-created `messages.db` (and
      // `-wal`/`-shm`) in the just deleted directory.
      await removeIdentity(nodeIdHex);

      final remaining = remoteDeletionRemoveEntry(
        nodeIdHex: nodeIdHex,
        mgr: IdentityManager(baseDir: config.baseDir),
        profileDir: profileDir,
        log: log.info,
      );

      // ── THE TRANSITION INTO "ZERO IDENTITIES" (owner decision (b)) ──
      //
      // This state already exists, and it is used daily on first
      // start: `startAll()` finds no identities, reports
      // "Keine Identitaeten gefunden — warte auf GUI-Setup (cleona.start
      // trigger)" and sets `_running = false`. The daemon lives on,
      // the tray stays, `_triggerTimer` listens for `cleona.start`.
      //
      // `stopAll()` leads exactly there: services, IPC server, V4.1 node
      // and all clocks are cleanly torn down, `_running` falls, the
      // tray state goes to "stopped", and `_triggerTimer` keeps
      // running (it is only cancelled in `shutdownAll()`). If the
      // UI then creates a new identity, it writes
      // `cleona.start` (`main.dart::_signalDaemonToStart`) and the daemon
      // starts up again by itself.
      //
      // NO process end. `_exportContactSeed` (same file) exits
      // with `exit(1)` on zero identities — that is the CLI path
      // `--export-contact-seed` and is never entered from here.
      if (remaining == 0) {
        log.warn('The last identity of this device was deleted on '
            'another own device — services are being stopped, '
            'the daemon waits for GUI setup (cleona.start trigger)');
        await stopAll();
      }
    } catch (e, stack) {
      // The error MUST be visible: this is a deletion path, and a
      // deletion that silently does not delete is the error.
      log.error('Remote deletion of the host failed for '
          '${nodeIdHex.length >= 16 ? nodeIdHex.substring(0, 16) : nodeIdHex}'
          '...: $e');
      log.error('Stack: $stack');
    }
  }

  /// IPC callback: delete an identity at runtime.
  Future<bool> _deleteIdentityAtRuntime(String nodeIdHex) async {
    // THIS GATE STAYS — and it applies ONLY to this path (the
    // user deletes themselves, via the UI). Here it is
    // right: it prevents someone from locking themselves out of
    // their own device with a slip. It does not apply to the TWIN MESSAGE
    // — there the user deliberately triggered the deletion on another
    // own device, and the promise reads "on
    // all my devices" (owner decision (b) of 09.09.2026, P-12).
    // The twin path therefore runs via `_identityFernDeleted`
    // and not through this function. The same applies to the
    // identically worded gate in `ipc_server.dart` (`delete_identity`).
    if (_services.length <= 1) return false;

    // Send IDENTITY_DELETED to all contacts + hang up active calls BEFORE removing.
    // Bounded timeout: contacts may be offline → sequential sendToUser can block.
    final service = _services[nodeIdHex];
    if (service != null) {
      try {
        await service.broadcastIdentityDeleted().timeout(const Duration(seconds: 15));
      } catch (_) {
        log.warn('broadcastIdentityDeleted timed out for $nodeIdHex, proceeding with deletion');
      }
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

  // ── GAP G-5: THE IDENTITY REGISTRY HAS NO STORAGE PLACE ────────
  //
  // Here stood `_publishIdentityRegistry()` — two callers
  // (`_createIdentityAtRuntime`, `_deleteIdentityAtRuntime`), one
  // callee: `CleonaService.storeRegistryInDht`. That lay in
  // `cleona_service_v3_delivery.dart:525` and stored the multi-identity
  // registry reed-solomon-encoded in the Kademlia DHT
  // (`node.routingTable.findClosestPeers` + `MTV3_FRAGMENT_STORE` at ten
  // replicators). Both are deleted.
  //
  // WHAT IS MISSING, AND SINCE WHEN ALSO THE CONSTRUCTION: until 08.09.2026
  // it said here that `identity/identity_dht_registry.dart` and the
  // Reed-Solomon codec lived on — construction, encryption and fragmentation
  // of the registry were unchanged in place. THE FILE HAS BEEN DELETED SINCE
  // S376 (owner decision V-11 = A, 08.09.2026). It had
  // zero callers in `lib/` and built fragments for a storage place that
  // does not exist: V4.1 has no pollable third-party storage (§4.3 is
  // replaced in V4.1, not renumbered — liveness is pairwise). The
  // secure storage on the tagline is addressed to a RECIPIENT; the
  // registry has none.
  //
  // THE GAP STAYS OPEN, it has not become smaller with the deletion
  // — only more honestly booked: there is now also no half
  // component lying around that looks like a solution. The REPLACEMENT is
  // outstanding and normatively sketched: v4_1 §13.7 demands derivation
  // instead of directory ("derivation instead of a directory"). As long as
  // nobody builds it, the consequence below applies unchanged.
  //
  // CONSEQUENCE, explicitly logged: multi-identity recovery via the
  // registry is dead until §14 gets a V4.1 carrier. Whoever loses their
  // device does NOT get their secondary identities back via the seed phrase
  // — only the primary identity. NOTHING is
  // faked here: there is no dummy that logs "successful".

  void _checkProfileIntegrity(IdentityManager mgr, List<Identity> identities) {
    // S368: the name on disk is `identities.json.enc` — the same
    // file, one suffix more. If the plain-text name still stood here,
    // the guard would fire every 30 s, see "deleted" and rewrite
    // the file every time. Not harmful, but a check that
    // is never right is no check.
    final idFile = File('${config.baseDir}/identities.json.enc');
    if (!idFile.existsSync()) {
      log.warn('PROFILE WATCHDOG: identities.json.enc deleted externally — '
          're-persisting ${identities.length} identities from RAM');
      try {
        Directory(config.baseDir).createSync(recursive: true);
        mgr.saveIdentities(identities);
        log.info('PROFILE WATCHDOG: identities.json.enc restored');
      } catch (e) {
        log.error('PROFILE WATCHDOG: failed to restore identities.json.enc: $e');
      }
    }

    if (KeyringService.isInitialized) {
      final firstCtx = _contexts.values.firstOrNull;
      if (firstCtx != null && firstCtx.masterSeed != null) {
        final ks = KeyringService.instance;
        if (ks.load('master_seed') == null) {
          log.warn('PROFILE WATCHDOG: master_seed keyring deleted externally — '
              're-persisting from RAM');
          try {
            ks.store('master_seed', firstCtx.masterSeed!);
            log.info('PROFILE WATCHDOG: master_seed keyring restored');
          } catch (e) {
            log.error('PROFILE WATCHDOG: failed to restore master_seed: $e');
          }
        }
      }
    }
  }

  Future<void> stopAll() async {
    if (!_running) return;
    log.info('Service is stopping...');

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

    // THE HOST FIRST (S387), then the services. The other way round the still
    // running host delivered to an already stopped service — a receipted
    // message that nobody stores any more. `stop` saves the neighbours
    // and closes wire and state checker; an open timer would keep the
    // Dart VM alive, and the daemon would not exit after `stopAll()`.
    await _delivery?.close();
    _delivery = null;
    // The port mapping laid down FIRST (task D): its own
    // renewal timer otherwise keeps the Dart VM alive, independently of the
    // wire that `stop()` closes right after.
    if (_host != null) await portMappingLayDown(_host!);
    _host?.stop();
    _host = null;

    for (final service in _services.values) {
      await service.stop();
    }
    _services.clear();
    _contexts.clear();

    final pidFile = File('${config.baseDir}/cleona.pid');
    if (pidFile.existsSync()) pidFile.deleteSync();

    // The port marker falls with the node that held the port.
    // If it is left lying (crash, SIGKILL, power failure), that is no
    // damage: Guard 3 of the next start probes the port, finds it
    // free and clears the marker away itself.
    try {
      final portFile = File('${config.baseDir}/$_udpPortFilename');
      if (portFile.existsSync()) portFile.deleteSync();
    } catch (_) { /* non-fatal */ }

    _trayStatus.setServiceRunning(false);
    log.info('Service stopped (tray stays active)');
  }

  Future<void> shutdownAll() async {
    log.info('Daemon is shutting down...');
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
    // THE LAST FLUSH, and it was MISSING until 01.09.2026. Seven other
    // exit points of this file (`:113 :139 :172 :184 :222 :236 :403`)
    // call it, of all things the orderly shutdown did not — `exit`
    // asks no timer, so on EVERY clean exit up to 2 s of
    // log were lost, exactly at the forensically most interesting edge (C-3, B-4).
    await CLogger.flushAll();
    exit(0);
  }

  /// Windows: ensure inbound firewall rules (UDP + TCP) for the daemon exe.
  /// Program-based rules — port-independent, set once per installation.
  /// Non-admin: netsh fails gracefully (rules should be set by installer).
  /// The parameter `port` went away (CUT, 31.08.) — it was already
  /// unused before: the rule is PROGRAM-BOUND (`program=$exe`,
  /// no `localport=`), so it allows every port of this process. Without
  /// this note the port change from `nodePort` to
  /// `nodePort + 1` would have looked like an error on the next reading. It is
  /// none, and demonstrably so: `port` does not occur in the body.
  Future<void> _ensureWindowsFirewallRule() async {
    final marker = File('${config.baseDir}/firewall_rule_added');
    if (marker.existsSync()) return;

    final exe = Platform.resolvedExecutable;
    log.info('Windows: checking/adding firewall rules for $exe');

    // Check if rules already exist (e.g. set by installer)
    try {
      final check = await Process.run('netsh', [
        'advfirewall', 'firewall', 'show', 'rule',
        'name=Cleona Messenger UDP',
      ]);
      if (check.exitCode == 0 && check.stdout.toString().contains('Cleona')) {
        log.info('Windows: firewall rules already present (set by installer)');
        marker.writeAsStringSync('installer');
        return;
      }
    } catch (_) {}

    var allOk = true;
    for (final proto in ['UDP', 'TCP']) {
      try {
        final result = await Process.run('netsh', [
          'advfirewall', 'firewall', 'add', 'rule',
          'name=Cleona Messenger $proto',
          'dir=in', 'action=allow', 'protocol=$proto',
          'program=$exe',
          'enable=yes',
        ]);
        if (result.exitCode == 0) {
          log.info('Windows: firewall rule $proto added');
        } else {
          allOk = false;
          log.warn('Windows: firewall rule $proto needs admin rights — '
              'should be set by installer (netsh exit ${result.exitCode})');
        }
      } catch (e) {
        allOk = false;
        log.warn('Windows: firewall rule $proto: $e');
      }
    }
    if (allOk) marker.writeAsStringSync('daemon');
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
  /// Windows **and macOS**: 30-s poll (no `ip monitor` available).
  ///
  /// ── macOS HAD NO EDGE AT ALL UNTIL S376 (P5 finding 4) ────────────
  ///
  /// This method knew two cases: `Platform.isWindows` and "otherwise".
  /// "Otherwise" meant `Process.start('ip', ['monitor', 'address'])` — that
  /// is Linux `iproute2`. On macOS there is no `ip`; the start throws,
  /// the `catch` writes a warning line and ends **without replacement**.
  /// `Platform.isMacOS` had zero occurrences in this file.
  ///
  /// The macOS daemon thus learned nothing of a network change: no
  /// new announce addresses, no dropped sessions, no
  /// `announceOwnEntry(vorrangig: true)`, no catch-up harvest. On every
  /// Wi-Fi change of a notebook — office, home, waking from
  /// sleep — an entry record stood in the network that points to the
  /// old address, until the daemon restarts. §22.6.
  ///
  /// THE DEVICE WAS NOT MEASURED. There is no running macOS daemon from
  /// the V4.1 tree in this project (S370: iOS/macOS have never been
  /// built from this line). What is proven is the CODE path — which
  /// branch macOS takes and that it ends without replacement. What is NOT
  /// proven: the exact error message of `Process.start` on macOS.
  /// It is irrelevant to the correctness of the fix: the poll is
  /// now chosen BEFORE the `ip monitor` attempt, so macOS no longer reaches
  /// the throwing call at all.
  ///
  /// WHY THE POLL AND NOT `SCNetworkReachability`. The poll is
  /// built, measured (Windows has run with it since S370) and needs no
  /// second native bridge. An event path would be more economical; it is a
  /// separate task and not a prerequisite for macOS getting an edge
  /// at all.
  void _startNetworkMonitor() async {
    // ONE condition for both platforms, no second branch with
    // the same body: the Windows version is the version, and macOS
    // falls into it.
    //
    // VIA [networkChangeDetectionFor] and not via a `Platform.is…`
    // at this place: a guard cannot set `Platform.isMacOS`, but
    // can query this function for every platform. The
    // detailed reasoning is there.
    final detection = networkChangeDetectionFor(
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
    );
    if (detection == NetworkChangeDetection.poll) {
      // Poll for network changes every 30s (no ip monitor equivalent).
      // The node-reset runs once for the whole daemon; per-service we only
      // trigger the service-side cleanup (mailbox poll, identity-publisher).
      _networkPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (!_running) return;
        final currentIps = await dialableLocalAddresses();
        final ipsKey = currentIps.join(',');
        final lastKey = _lastPollIps.join(',');
        // SINCE S380 THE PROBE STANDS ONCE, in `isRealNetworkChange` —
        // the `ip monitor` branch below needs the same, and two copies
        // would be two places where "change" diverges. That
        // was exactly the state before S380: a comparison here, none there.
        if (!isRealNetworkChange(before: _lastPollIps, after: currentIps)) {
          return;
        }
        _lastPollIps = currentIps;
        log.info('Network change detected (poll) — IPs: $lastKey → $ipsKey');
        // ── WHAT THESE THREE LINES TRIGGER ──────────────────────────
        //
        // `service.onNetworkChanged` is not a mere cleanup call. It calls
        // the seam `v41OnNetworkChanged` (`cleona_service.dart`, "final
        // knotenNaht = v41OnNetworkChanged"), and that does three things in
        // this order: it determines the dialable addresses anew,
        // resets the announcement with them (`setAnnounceAddresses` in
        // `v41_attach.dart` — exactly for that S360 pulled the function out of
        // the body of `startV41Node`), and only afterwards lets
        // `V41Node.onNetworkChanged` drop the sessions. The
        // rendezvous loop sees a different address fingerprint on its next
        // pass, `AblageMarke.verlangtAblage`
        // fires, and the own entry record is stored anew with reason
        // `Adresswechsel`.
        //
        // DETECTION: here by 30-s poll via `dialableLocalAddresses`
        // (neither Windows nor macOS have `ip monitor`); in-process and
        // under Linux event-driven, see below.
        //
        // ── UNTIL S373 THE PRIOR STATE STOOD HERE ───────────────────────
        //
        // Verbatim: "`_nodeHost.onNetworkChanged()` and the
        // ipify fallback went away with V3 and are NOT
        // replaced in V4.1: the node binds its socket once and announces the
        // address determined at start. An address change makes the
        // own entry record silently wrong — reported gap."
        //
        // That was wrong since S360 — the gap was closed there,
        // the comment stayed. On 07.09.2026 it
        // misled someone. It stands here explicitly once
        // more so that nobody revives the old reading: whoever
        // checks the chain finds it complete.
        //
        // ── THE ONE EDGE THIS POLL DOES NOT SEE ──────────────
        //
        // It compares LOCAL addresses. If only the OUTER one changes —
        // the provider assigns a new WAN IP, the forced disconnect —,
        // the local IPs stay the same and the poll stays silent. This
        // edge is covered by the observed address from §17.3: `onAgreedChanged`
        // carries the announcement forward (package `s373-beobachtete-adresse`,
        // `8e3ea26c`). Without it exactly this one case would stay open — and
        // only this one.
        // ── THE NODE PART ONCE (S376, P5 finding 5) ───────────────
        //
        // There is ONE node in this process: one socket, one
        // session set, one entry record, one LAN call. The
        // loop below, by contrast, runs per identity — until S376
        // the node part thus also ran N times, because `triggerNodeReset`
        // was ignored. With three identities that was three
        // session teardowns, three priority announcements and three
        // LAN calls for ONE event; the second and third pass
        // tore down sessions that the partner selection had just rebuilt
        // after the first.
        // ── THE NODE PART ONCE (S376 P5 finding 5; S387 mycelium) ─────
        //
        // `Host.networkChanged` (§11.8, §22.7.1): all evidence expires
        // immediately, interfaces anew, ONE call series, ONE query of the
        // remembered neighbours — once per event for the whole process,
        // the services below only with `triggerNodeReset: false`.
        final w = _host;
        if (w != null) {
          // The manifest slot AFTER the end of the network change (S388, M1+):
          // before that the old neighbourhood still applies.
          unawaited(w.networkChanged().catchError((Object e) {
            log.warn('mycelium network change failed: $e');
          }).then((_) => _updateManifestAsk()));
          // The port mapping at the same edge (§7.3) — NOT awaited,
          // for the same reason as at start (RFC 6886 backoff).
          unawaited(() async {
            try {
              await portMappingToEdge(
                w,
                baseDir: config.baseDir,
                key:
                    hostKey(config.baseDir, _masterSeedForHost),
                report: log.info,
              );
            } catch (e) {
              log.warn('Port mapping (network change): $e');
            }
          }());
        }
        for (final service in _services.values) {
          service.onNetworkChanged(triggerNodeReset: false);
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
          // ── AN EVENT IS NOT YET A CHANGE (S380) ──────────────
          //
          // Until S380 only the log line stood here: EVERY netlink event
          // counted as a network change and dropped all sessions. A
          // router advertisement refreshes the lifetimes of an existing
          // address and is such an event — measured on the bootstrap
          // six in 40 minutes, each with three dropped
          // sessions, while the address set stayed unchanged.
          // Reasoning and measurement log at `isRealNetworkChange`.
          //
          // And the message now names the addresses. Six messages
          // without a single "what then" kept exactly this finding invisible
          // for two sessions.
          final currentIps = await dialableLocalAddresses();
          final lastKey = _lastPollIps.join(',');
          final ipsKey = currentIps.join(',');
          if (!isRealNetworkChange(
              before: _lastPollIps, after: currentIps)) {
            log.debug('Address event without address change — discarded '
                '(ip monitor, IPs: $ipsKey)');
            return;
          }
          _lastPollIps = currentIps;
          log.info(
              'Network change detected (ip monitor) — IPs: $lastKey → $ipsKey');
          // ── THE PRIOR STATE STILL STOOD HERE (S376) ────────────────
          //
          // Verbatim: "As in the Windows branch above: the node part of the
          // network change went away with V3 and is not replaced in V4.1."
          // S373 corrected the Windows branch and left THIS sentence
          // standing — so it referred to a correction and at the same
          // time claimed its opposite. Re-measured on 08.09.2026: the same
          // applies here as above: the full node part runs — since
          // S376 via `v41NodeNetworkChange`, ONCE per event, and
          // the service loop below only carries the service part
          // (P5 finding 5).
          // The node part ONCE per event — as in the poll branch above
          // (`Host.networkChanged`, S387).
          final w = _host;
          if (w != null) {
            unawaited(w.networkChanged().catchError((Object e) {
              log.warn('mycelium network change failed: $e');
            }).then((_) => _updateManifestAsk()));
            // The port mapping at the same edge (§7.3) — NOT
            // awaited, for the same reason as at start
            // (RFC 6886 backoff).
            unawaited(() async {
              try {
                await portMappingToEdge(
                  w,
                  baseDir: config.baseDir,
                  key:
                      hostKey(config.baseDir, _masterSeedForHost),
                  report: log.info,
                );
              } catch (e) {
                log.warn('Port mapping (network change): $e');
              }
            }());
          }
          for (final service in _services.values) {
            service.onNetworkChanged(triggerNodeReset: false);
          }
        });
      });
      proc.exitCode.then((code) {
        log.debug('ip monitor exited with $code');
        _networkMonitor = null;
      });
    } catch (e) {
      // ── AND HERE IT ENDS WITHOUT REPLACEMENT (S376, P5 finding 4) ─────────
      //
      // That is intentional and no longer a gap: the two platforms
      // without `ip monitor` — Windows and macOS — take the poll above and
      // do not reach this line. Whoever lands here is a
      // Linux-like system WITHOUT `iproute2`. Building a third
      // detection for it would be a path without a known user.
      //
      // BUT IT REMAINS A FINDING AND NOT OPERATING NOISE: without a
      // network-change edge the own entry record stands silently wrong in the
      // network after an address change. `warn` is therefore right,
      // and the line now says WHAT fails instead of only what is missing.
      log.warn('ip monitor not available: $e — this daemon has no '
          'network-change edge any more: an address change stays '
          'unnoticed until the restart (§22.6)');
    }
  }


  /// Since S376 the unread count is only ONE of the quantities that
  /// the tray shows — it travels in the same [TrayStatus] as the
  /// readiness state. The sum arises in
  /// [TrayStatusBinder.refresh] from the counters reported per
  /// identity; here only the trigger remains.
  void _updateTrayBadge() => _trayStatus.refresh();

  /// A moment after M1+ (S388). Only the service with an update carrier asks
  /// (`attachUpdateToService`); for the others the call is empty — no packet.
  Future<void> _updateManifestAsk() async {
    for (final s in _services.values) {
      await s.updateManifestAsk();
    }
    // E-9 (package 10 = A, S389): the same retry as in `main.dart`,
    // at the same edges. No timer, no deadline (§1.2, working rule 5);
    // whether collecting happens is decided by `onManifest`.
    _updateOffer?.againTry();
  }

  /// Registers an identity with the tray state (§22.9).
  ///
  /// ── WHAT THE DAEMON KNOWS ABOUT THE STATE ─────────────────────────
  ///
  /// The daemon reads `readinessState` directly from the service — the same
  /// getter that `ipc_server.dart` sends across the IPC boundary. The tray
  /// thus gets NO second calculation, but the same quantity one
  /// layer earlier.
  ///
  /// S388 (owner decision E3 = A, V4.2 §22.9 version A2): here also stood
  /// `syncPartnersOutbound`, `syncPartnersInbound`,
  /// `hasPortMapping` and `hasNetwork` — the inputs of the five-level
  /// connection display and the reachability marker. Both have
  /// gone; the tray shows ONE indicator, the readiness state.
  /// This also makes moot the named gap from S376 that the
  /// daemon does not know the connection type and could never show
  /// the level `medium`.
  void _bindIdentityToTray(String identityId, CleonaService service) {
    _trayStatus.registerIdentity(
      identityId,
      () => IdentityStatus(
        readiness: service.readinessState,
        // V-10-c = b (09.09.2026): the tray no longer aggregates by the
        // weakest, but shows "Ready 2/3" and lists the
        // identities individually in the menu. For that the
        // aggregate needs the name — it did not have it until S377.
        displayName: service.displayName,
        unreadCount: service.conversations.values
            .fold<int>(0, (sum, c) => sum + c.unreadCount),
      ),
      (onChange) {
        // CHAIN, do not overwrite — `onStateChanged` is a field,
        // not a stream. Exactly this construction is used by `IpcServer`
        // (ipc_server.dart:203); whoever breaks it here takes from the GUI
        // its state report.
        final before = service.onStateChanged;
        service.onStateChanged = () {
          before?.call();
          onChange();
        };
      },
    );
  }

  void _launchGui() {
    if (_ipcServer != null && _ipcServer!.hasClients) {
      final triggerFile = File('${config.baseDir}/gui.show');
      triggerFile.writeAsStringSync('$pid');
      log.info('Tray: GUI already connected — wrote gui.show trigger');
      return;
    }
    // `AppPaths.bundleDir` instead of the own directory (S367): since the
    // rebuild the daemon lies in `<bundleDir>/bin/`, the GUI in the
    // bundle root. `$dir$sep$guiName` would be from here
    // `…/bin/cleona` and hit nothing; only the
    // `..` entry would still have carried, and that is a lucky hit, not a path.
    final sep = Platform.pathSeparator;
    final dir = AppPaths.bundleDir;
    final guiName = AppPaths.guiBinaryName;
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

/// Candidate paths for the tray icon, in search order.
///
/// Extracted from [_findIconPath] so that the order can be checked WITHOUT
/// a file system — `test/smoke/
/// smoke_windows_heimatpfad_guard.dart` measures on this function that the
/// fallback to the shipped `cleona-app` bundle is in the list
/// and the home part comes from [AppPaths.home].
///
/// ── WHY `AppPaths.home` AND NOT `Platform.environment['HOME']` ────
///
/// Until S370 `Platform.environment['HOME']` stood here, and the fallback
/// was thus DEAD on Windows — i.e. exactly where the comment below
/// promises it ("so the tray icon is still found on deployed VMs"). Measured
/// on 06.09.2026 on the Windows build VM (`192.168.10.74`):
///
///   PS> [Environment]::GetEnvironmentVariable("HOME","User")     -> empty
///   PS> [Environment]::GetEnvironmentVariable("HOME","Machine")  -> empty
///   cmd(via sshd)> echo %HOME%                 -> C:\Users\Cleona
///
/// `HOME` is not a Windows variable. It exists there ONLY inside an
/// sshd session, because the OpenSSH service sets it for its session. On
/// start via Explorer, shortcut, the `Run` registry key or
/// the task scheduler — i.e. in every end-user case and in every
/// autostart — `home` was null and the two `cleona-app` candidates
/// fell out of the list. [AppPaths.home] resolves `USERPROFILE` on Windows
/// and returns `$HOME` unchanged under Linux/macOS.
List<String> trayIconCandidatePaths({
  required String exeDir,
  required String sep,
  required bool beta,
  required bool windowsIcons,
}) {
  // Beta builds prefer _beta icon variants; fall back to standard if not found.
  final suffixes = beta ? ['_beta', ''] : [''];
  // Windows tray requires .ico format; search .ico first, then .png as fallback.
  final extensions = windowsIcons ? ['ico', 'png'] : ['png'];
  // Since c7ea816 moved daemon from ~/cleona-app/cleona-daemon to ~/cleona-daemon,
  // the binary no longer lives next to the Flutter bundle. Also search the sibling
  // cleona-app bundle under the user's home so the tray icon is still found on
  // deployed VMs.
  final homeBundleDir = '${AppPaths.home}${sep}cleona-app';
  final out = <String>[];
  for (final suffix in suffixes) {
    for (final ext in extensions) {
      out.addAll([
        '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        '$exeDir${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
        '$exeDir$sep..${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        '$exeDir$sep..${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
        '$homeBundleDir${sep}data${sep}flutter_assets${sep}assets${sep}tray_icon$suffix.$ext',
        '$homeBundleDir${sep}data${sep}flutter_assets${sep}assets${sep}app_icon$suffix.$ext',
      ]);
    }
  }
  return out;
}

String? _findIconPath({bool beta = false}) {
  // `AppPaths.bundleDir` instead of the own directory (S367) — the
  // Flutter assets lie under `<bundleDir>/data/`, but the daemon in
  // `<bundleDir>/bin/`. Without this change, of the six
  // candidates below only the `$home/cleona-app` fallback would hit, which does
  // not exist on a normal installation: the tray service would have
  // lost its icon.
  final sep = Platform.pathSeparator;
  // MERGE S370: the candidate list now stands as a separate,
  // checkable function `trayIconCandidatePaths` (it also fixes
  // the `HOME` finding under Windows) — and it gets as root the
  // BUNDLE ROOT, not the directory of the executable. Both
  // are necessary: with `exePath`'s directory the root for the
  // daemon would be at `<bundleDir>/bin`, and exactly that is what the
  // paragraph above warns about. The parameter is called `exeDir` because for
  // the UI it is both at once; here it is the bundle root.
  for (final path in trayIconCandidatePaths(
    exeDir: AppPaths.bundleDir,
    sep: sep,
    beta: beta,
    windowsIcons: Platform.isWindows,
  )) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

Future<bool> _applyAndRestart(BinaryUpdateManager mgr, CLogger log, Future<void> Function() shutdownAll) async {
  try {
    final path = await mgr.getVerifiedBinaryPath(
        Platform.operatingSystem, mgr.targetVersion ?? '');
    if (path == null) {
      log.warn('getVerifiedBinaryPath returned null');
      return false;
    }
    final ok = await mgr.applyDesktopUpdate(Platform.resolvedExecutable);
    if (ok) {
      log.info('Update applied: v${mgr.targetVersion} — spawning restart helper');
      await CLogger.flushAll();
      if (Platform.isLinux) {
        final cmdlineBytes = File('/proc/self/cmdline').readAsBytesSync();
        final cmdParts = String.fromCharCodes(cmdlineBytes)
            .split('\x00')
            .where((s) => s.isNotEmpty)
            .toList();
        // Swap argv[0] for the canonical place in the NEW bundle
        // (S367). The update has just replaced the whole bundle; if
        // the daemon previously lay in the root and now lies in `bin/`,
        // the own command line points to a file that no longer
        // exists — the restart would run into nothing, and quietly, because
        // `Process.start` is detached. The arguments stay
        // unchanged; only the path is updated, and that also only
        // if a file really lies there.
        if (cmdParts.isNotEmpty) {
          final fresh = AppPaths.daemonPathIn(
              AppPaths.bundleDirOf(Platform.resolvedExecutable));
          if (File(fresh).existsSync()) {
            log.info('Restart via $fresh (was: ${cmdParts.first})');
            cmdParts[0] = fresh;
          }
        }
        final quotedCmd = cmdParts.map((p) => "'${p.replaceAll("'", r"'\''")}'").join(' ');
        await Process.start('/bin/bash', [
          '-c',
          'sleep 2 && exec $quotedCmd',
        ], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        final batPath = mgr.windowsUpdateBatPath;
        if (batPath != null) {
          final winPath = batPath.replaceAll('/', '\\');
          log.info('Spawning update-apply.bat: $winPath');
          await Process.start('cmd.exe', ['/c', 'start', '/MIN', '', winPath],
              mode: ProcessStartMode.detached);
        }
      }
      log.info('Shutting down daemon before exit...');
      await shutdownAll();
      return true;
    } else {
      log.warn('applyDesktopUpdate returned false');
      return false;
    }
  } catch (e) {
    log.error('Apply error: $e');
    return false;
  }
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
  final bool exportContactSeed;
  final String? identitySelector;
  final String? name;

  _DaemonConfig({
    required this.baseDir,
    this.port,
    this.iconPath,
    this.publicIp,
    this.ignoreSingleInstance = false,
    this.exportContactSeed = false,
    this.identitySelector,
    this.name,
  });
}

_DaemonConfig _parseArgs(List<String> args) {
  String? baseDir;
  int? port;
  String? iconPath;
  String? publicIp;
  bool ignoreSingleInstance = false;
  bool exportContactSeed = false;
  String? identitySelector;
  String? name;

  // S368: here additionally stood `String? legacyProfile` for `--profile`.
  // The branch it controlled was WITHOUT EFFECT: both arms of the
  // case distinction below set `baseDir` to `$home/.cleona`.
  //
  // `--name` does NOT fall with it — the removal plan named both together, but
  // measured, `--name` has two live consumers (`overrideDisplayName`
  // and `displayName` further below) and two live callers
  // (`scripts/install-desktop.sh`, `scripts/update-bootstrap-seed.sh`).

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
      case '--port':
        if (i + 1 < flat.length) port = int.tryParse(flat[++i]);
        break;
      case '--name':
        if (i + 1 < flat.length) name = flat[++i];
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
      // `--bootstrap` stood here until S388 (V4.2 §11.7: no node has a
      // special role). It now falls into `default` and ends the start.
      case '--export-contact-seed':
        exportContactSeed = true;
        break;
      case '--identity':
        if (i + 1 < flat.length) identitySelector = flat[++i];
        break;
      default:
        // D-2 (S372, owner decision E-2 = A): unknown switches are
        // NO LONGER silently discarded. `--profile` fell in S368,
        // but `scripts/cleona.service` still passed it through unchanged
        // — the daemon accepted it, discarded it without effect, and an
        // E2E run on 05.09. started with it on a throwaway path, while
        // the daemon itself worked on the real profile and deleted 9.5 GB.
        // Fail closed instead of fail silent, BEFORE any resource creation (lock,
        // log, directory) — `_parseArgs` runs at the very beginning of
        // `main()`.
        stderr.writeln(
            'FATAL: unknown switch "${flat[i]}" — daemon does NOT '
            'start.\n'
            'Supported: --base-dir --port --name --icon --public-ip '
            '--identity --export-contact-seed '
            '--ignore-single-instance');
        exit(64);
    }
  }

  // Determine base dir
  //
  // S368: here stood a case distinction on `legacyProfile`, whose
  // BOTH arms set the same value — the branch never did anything other
  // than the rest.
  baseDir ??= '${AppPaths.home}/.cleona';

  return _DaemonConfig(
    baseDir: baseDir,
    port: port,
    iconPath: iconPath,
    publicIp: publicIp,
    ignoreSingleInstance: ignoreSingleInstance,
    exportContactSeed: exportContactSeed,
    identitySelector: identitySelector,
    name: name,
  );
}

Future<void> _exportContactSeed(_DaemonConfig config) async {
  SodiumFFI();
  OqsFFI().init();

  await IdentityContext.initCrypto(config.baseDir);
  final mgr = IdentityManager(baseDir: config.baseDir);
  final identities = mgr.loadIdentities();
  if (identities.isEmpty) {
    stderr.writeln('ERROR: No identities found in ${config.baseDir}');
    exit(1);
  }
  final Identity activeId;
  if (config.identitySelector != null) {
    final sel = config.identitySelector!.toLowerCase();
    final match = identities.where((id) =>
        id.displayName.toLowerCase() == sel ||
        (id.nodeIdHex != null && id.nodeIdHex!.toLowerCase().startsWith(sel)));
    if (match.isEmpty) {
      stderr.writeln('ERROR: No identity matching "${config.identitySelector}"');
      exit(1);
    }
    activeId = match.first;
  } else {
    activeId = identities.first;
  }
  final identity = await IdentityContext.createFromIdentity(
    identity: activeId,
    baseDir: config.baseDir,
    masterSeed: mgr.loadMasterSeed(),
    overrideDisplayName: config.name,
  );

  final interfaces = await NetworkInterface.list();
  final localIps = <String>[];
  for (final iface in interfaces) {
    // S376 (P2-4): THE SAME CLASS AS B-4, only in the ContactSeed export.
    // `ownAddrs` below takes the FIRST TWO of these addresses and writes
    // them into the emitted ContactSeed. On a machine with libvirt
    // or Docker the virtual bridge often stands first in the operating
    // system's order — the exported seed then named
    // `192.168.122.1`, and every reader dialled into nothing. Exactly that
    // was measured on 07.09.2026 on the wire (four unanswered SYNs).
    if (!interfaceLeadsAfterOutside(iface.name)) continue;
    for (final addr in iface.addresses) {
      if (addr.isLoopback || addr.isLinkLocal) continue;
      localIps.add(addr.address);
    }
  }

  final ownAddrs = localIps.take(2).map((ip) => '$ip:${config.port}').toList();

  var publicIp = config.publicIp;
  if (publicIp == null) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final ip = (await resp.transform(const SystemEncoding().decoder).join()).trim();
      client.close(force: true);
      if (ip.isNotEmpty && ip.contains('.')) publicIp = ip;
    } catch (_) {}
  }
  if (publicIp != null) {
    ownAddrs.add('$publicIp:${config.port}');
  }

  final seed = ContactSeed(
    nodeIdHex: identity.userIdHex,
    displayName: config.name ?? activeId.displayName,
    ownAddresses: ownAddrs,
    seedPeers: const [],
    channelTag: NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l',
    deviceIdHex: identity.deviceNodeIdHex,
    userEd25519Pk: identity.ed25519PublicKey,
    // S368: the FOUNDING key must go along, otherwise the exported
    // seed of a ROTATED identity cannot be recomputed. The UserID
    // falls out of `foundingEd25519Pk` (§4.1 / `IdentityContext.userId`),
    // `ed25519PublicKey` is the CURRENT one — after a rotation these are
    // two different values, and `verifyIntegrity()` would have computed against the
    // wrong one. For a never-rotated identity both are
    // equal, and `toUri()` then omits `fp` itself
    // (`contact_seed.dart:279-282`, "only for rotated identities") —
    // so the normal case does not change.
    foundingEd25519Pk: identity.foundingEd25519Pk,
    createdAtMs: DateTime.now().millisecondsSinceEpoch,
  );

  stdout.writeln(seed.toUri());
  exit(0);
}

// The addresses that the V4.1 entry calls in addition to the broadcast
// (B-27, S349) came from `node.routingTable.allPeers` here until S351 — the
// V3 node. That was exactly the grip against which `smoke_seam_node_member_
// guard` (AP-1 step 7) stands: the V4.1 entry cascade talked past the V3
// transport instead of replacing it as planned. Since the
// persistent entry pool (`95b2b104`) the same purpose gives the same
// information without V3 — moved to `lib/core/tagline/v41_attach.dart`
// (`vorratUnicastTargets`), source now `v41.entries.dialCandidates()`.


// ══════════════════════════════════════════════════════════════════════
// WHICH NETWORK-CHANGE DETECTION A PLATFORM GETS (S376, P5 fnd. 4)
// ══════════════════════════════════════════════════════════════════════
//
// ── WHY THIS IS A SEPARATE FUNCTION ──────────────────────────────
//
// The decision stood as `if (Platform.isWindows)` in the body of
// `_startNetworkMonitor` and was thus checkable only on the platform
// one happens to be running on. Exactly so the error arose and
// stayed for years: `Platform.isMacOS` had zero occurrences in this
// file, macOS fell into the Linux branch, there
// `Process.start('ip', …)` throws, and the `catch` ended without replacement — a
// daemon entirely without a network-change edge (§22.6).
//
// A guard cannot set `Platform.isMacOS`. But it can query this
// function for EVERY platform, and that is the whole
// purpose: the statement "macOS gets a detection" becomes checkable
// without owning a macOS device.
//
// WHAT IS NOT MEASURED THEREBY: whether the poll also WORKS on macOS. It
// calls `dialableLocalAddresses()`, and that is `NetworkInterface.list` —
// present on macOS, but never run on a device in this project
// (S370: iOS/macOS have never been built from the V4.1 tree).
// What is proven is the code path, not the device.
enum NetworkChangeDetection {
  /// 30-s comparison of the local addresses (`dialableLocalAddresses`).
  poll,

  /// `ip monitor address` from iproute2 — event-driven, Linux.
  ipMonitor,
}

/// Which detection this platform gets.
///
/// The condition is "does the system have `ip monitor`", not "is it
/// Windows". Windows and macOS do not have it, Linux has it. A system
/// without both does not exist in the supported set; if the
/// `ip monitor` start fails anyway, the warning line in the `catch` says what
/// fails.
NetworkChangeDetection networkChangeDetectionFor({
  required bool isWindows,
  required bool isMacOS,
}) =>
    (isWindows || isMacOS)
        ? NetworkChangeDetection.poll
        : NetworkChangeDetection.ipMonitor;
