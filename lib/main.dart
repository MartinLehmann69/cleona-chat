import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:cleona/ui/screens/calendar_screen.dart';
import 'package:cleona/ui/screens/poll_editor_screen.dart';
import 'package:cleona/ui/screens/home_screen.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_dialog.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_instructions_screen.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_router_select_screen.dart';
import 'package:cleona/core/network/router_db.dart';
import 'package:cleona/ui/screens/setup_screen.dart';
import 'package:cleona/ui/screens/settings_screen.dart';
import 'package:cleona/ui/screens/device_management_screen.dart';
import 'package:cleona/ui/screens/identity_detail_screen.dart';
import 'package:cleona/ui/screens/network_stats_screen.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/screens/call_screen.dart';
import 'package:cleona/ui/screens/chat_screen.dart';
import 'package:cleona/ui/screens/qr_contact_screen.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/platform/window_show.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:cleona/ui/theme/skin.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Single-Instance (Unix desktops — Linux + macOS; both have kill -0 and $HOME)
  if (Platform.isLinux || Platform.isMacOS) {
    if (_signalExistingInstance()) {
      exit(0);
    }
    _writeGuiLock();
  }

  // Android: Edge-to-Edge + Portrait lock.
  // Portrait lock prevents Activity recreation on rotation which would destroy
  // the in-process CleonaNode (port conflict, state corruption).
  if (Platform.isAndroid) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  SodiumFFI();
  OqsFFI().init();

  // Enable accessibility semantics so AT-SPI can inspect the widget tree
  // This is required for automated GUI testing via accessibility tools
  SemanticsBinding.instance.ensureSemantics();

  runApp(const CleonaApp());
}

/// Checks if another GUI instance is running. If so, write a trigger.
bool _signalExistingInstance() {
  final home = AppPaths.home;
  final lockFile = File('$home/.cleona/gui.lock');
  if (!lockFile.existsSync()) return false;

  try {
    final otherPid = int.parse(lockFile.readAsStringSync().trim());
    if (otherPid == pid) return false; // It's us
    if (Process.runSync('kill', ['-0', '$otherPid']).exitCode == 0) {
      // Other instance is alive — signal "show window"
      File('$home/.cleona/gui.show').writeAsStringSync('$pid');
      return true;
    }
  } catch (_) {}

  // Stale lock file
  try { lockFile.deleteSync(); } catch (_) {}
  return false;
}

void _writeGuiLock() {
  final home = AppPaths.home;
  final dir = Directory('$home/.cleona');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$home/.cleona/gui.lock').writeAsStringSync('$pid');
}

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class CleonaApp extends StatelessWidget {
  const CleonaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocale = AppLocale();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final state = CleonaAppState();
          state._appLocale = appLocale;
          state._boot();
          return state;
        }),
        ChangeNotifierProvider.value(value: appLocale..load()),
      ],
      child: Consumer2<CleonaAppState, AppLocale>(
        builder: (context, appState, locale, _) {
          final activeSkin = appState.activeSkin;
          final Widget home;
          if (appState.isInitialized) {
            home = const HomeScreen();
          } else if (appState.hasProfile) {
            home = const _LoadingScreen();
          } else {
            home = const SetupScreen();
          }
          return Directionality(
            textDirection: locale.textDirection,
            child: MaterialApp(
              key: ValueKey('app_${locale.currentLocale}'),
              navigatorKey: navigatorKey,
              title: NetworkSecret.channel == NetworkChannel.beta
                  ? 'Cleona Chat (Beta)' : 'Cleona Chat',
              debugShowCheckedModeBanner: false,
              theme: activeSkin.toLightTheme(),
              darkTheme: activeSkin.toDarkTheme(),
              themeMode: appState.themeMode,
              themeAnimationDuration: const Duration(milliseconds: 400),
              themeAnimationCurve: Curves.easeInOut,
              home: home,
            ),
          );
        },
      ),
    );
  }
}

/// Loading screen while daemon starts / IPC connects.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text('Cleona Chat',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Verbinde mit Dienst...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class CleonaAppState extends ChangeNotifier with WidgetsBindingObserver {
  ICleonaService? _service;
  IpcClient? _ipcClient;
  bool _isInitialized = false;
  bool _hasProfile = false;
  ThemeMode _themeMode = ThemeMode.system;
  Timer? _showTriggerTimer;
  AppLocale? _appLocale;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<ConnectivityResult> _connectivityResults = [];
  String _lastNotificationText = '';

  /// Current connectivity results from connectivity_plus.
  /// Used by HomeScreen to display connection status icon.
  List<ConnectivityResult> get connectivityResults => _connectivityResults;

  /// Number of peers with confirmed bidirectional UDP contact this session.
  /// Combines OS connectivity with actual P2P reachability for the status icon.
  int get confirmedPeerCount {
    // Android in-process: read directly from node
    if (_androidNode != null) return _androidNode!.confirmedPeerIds.length;
    // Desktop daemon: IPC client carries confirmedPeerCount
    if (_ipcClient != null) return _ipcClient!.confirmedPeerCount;
    return 0;
  }

  /// True when UPnP/PCP successfully opened an inbound port mapping — used by
  /// the connection-status icon to split "strong (Hulk)" from "good (normal man)".
  bool get hasPortMapping {
    if (_androidNode != null) return _androidNode!.natTraversal.hasPortMapping;
    if (_ipcClient != null) return _ipcClient!.hasPortMapping;
    return false;
  }

  /// Whether transport is using mobile fallback (WiFi broken, mobile works).
  /// When true, icon should show mobile even if OS reports WiFi.
  bool _mobileFallbackActive = false;
  bool get isMobileFallbackActive {
    // Android in-process: read from node's transport
    if (_androidNode != null) return _androidNode!.transport.isMobileFallbackActive;
    // Desktop daemon: IPC client carries the state
    if (_ipcClient != null) return _ipcClient!.mobileFallbackActive;
    return _mobileFallbackActive;
  }

  // Android in-process multi-identity state
  CleonaNode? _androidNode;
  final Map<String, CleonaService> _androidServices = {};
  final Map<String, IdentityContext> _androidContexts = {};
  final List<(dynamic, dynamic, int, IdentityContext?)> _androidEarlyMessages = [];
  bool _androidServicesReady = false;

  ICleonaService? get service => _service;
  IpcClient? get ipcClient => _ipcClient;

  /// Refreshes UI after identity changes.
  void refresh() => notifyListeners();

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (Platform.isAndroid) _updateAndroidNotification();
  }

  /// Updates the foreground service notification with current connection status.
  void _updateAndroidNotification() {
    final hasNetwork = _connectivityResults.isNotEmpty &&
        !_connectivityResults.contains(ConnectivityResult.none);
    final hasWifi = _connectivityResults.contains(ConnectivityResult.wifi) ||
        _connectivityResults.contains(ConnectivityResult.ethernet) ||
        _connectivityResults.contains(ConnectivityResult.vpn);
    final hasMobile = _connectivityResults.contains(ConnectivityResult.mobile);
    final peers = confirmedPeerCount;

    final String text;
    if (!hasNetwork) {
      text = 'Offline — kein Netzwerk';
    } else if (peers == 0) {
      text = 'Suche nach Peers\u2026';
    } else if (hasWifi && !isMobileFallbackActive) {
      text = 'Verbunden — $peers ${peers == 1 ? "Peer" : "Peers"}';
    } else if (hasMobile || isMobileFallbackActive) {
      text = 'Mobilfunk — $peers ${peers == 1 ? "Peer" : "Peers"}';
    } else {
      text = 'Verbunden — $peers ${peers == 1 ? "Peer" : "Peers"}';
    }

    if (text == _lastNotificationText) return;
    _lastNotificationText = text;

    const channel = MethodChannel('chat.cleona/service');
    channel.invokeMethod('updateServiceNotification', {
      'title': 'Cleona Chat',
      'text': text,
    });
  }

  /// Save state on pause, re-bootstrap on resume (§27 Doze resilience).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      for (final service in _androidServices.values) {
        service.saveState();
      }
      if (_service is CleonaService) {
        (_service as CleonaService).saveState();
      }
    } else if (state == AppLifecycleState.resumed) {
      // After Doze/background: network may have changed, re-discover peers.
      // Protected seed peers survived pruning — now ping them to reconnect.
      // Guard: node must be running (transport/natTraversal are late-initialized).
      if (_androidNode != null && _androidNode!.isRunning) {
        _androidNode!.onNetworkChanged();
        _queryPublicIp();
      }
    }
  }

  /// Discover own public IPv4 + IPv6 via ipify (§27 — Android has no daemon).
  void _queryPublicIp() {
    final node = _androidNode;
    if (node == null) return;
    // Delay 5s — let network stabilize after resume
    Timer(const Duration(seconds: 5), () async {
      if (!node.isRunning) return; // Node not started yet (late fields uninitialized)
      if (node.natTraversal.hasPublicIp) return;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        final ip = (await resp.transform(const SystemEncoding().decoder).join()).trim();
        client.close(force: true);
        if (ip.isNotEmpty && ip.contains('.')) {
          node.natTraversal.setExternalIpOnly(ip);
          node.probePublicPort(ip);
          node.broadcastAddressUpdate();
        }
      } catch (_) {}
      // IPv6
      try {
        final client6 = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        final req6 = await client6.getUrl(Uri.parse('https://api6.ipify.org'));
        final resp6 = await req6.close().timeout(const Duration(seconds: 10));
        final ipv6 = (await resp6.transform(const SystemEncoding().decoder).join()).trim();
        client6.close(force: true);
        if (ipv6.isNotEmpty && ipv6.contains(':')) {
          node.natTraversal.setPublicIpv6(ipv6);
          node.broadcastAddressUpdate();
        }
      } catch (_) {}
    });
  }

  /// Counter incremented by go_back to signal HomeScreen to reset to "Aktuell" tab.
  int _goBackCounter = 0;
  int get goBackCounter => _goBackCounter;

  /// Counter incremented by test-only `gui_action('reset_nat_wizard_latch')`
  /// AND by user-initiated re-triggers (connection-icon tap) to signal
  /// HomeScreen to clear its `_natWizardShown` one-shot latch so the next
  /// NAT-Wizard trigger fires again.
  int _natWizardResetCounter = 0;
  int get natWizardResetCounter => _natWizardResetCounter;

  /// Called from the connection-status icon tap handler before the service's
  /// `requestNatWizard()` so the GUI-side latch gives way to the new trigger.
  void bumpNatWizardResetCounter() {
    _natWizardResetCounter++;
    notifyListeners();
  }
  bool get isInitialized => _isInitialized;
  bool get hasProfile => _hasProfile;
  ThemeMode get themeMode => _themeMode;

  /// The active skin based on the current identity's skinId.
  Skin get activeSkin {
    final activeId = IdentityManager().getActiveIdentity();
    return Skins.byId(activeId?.skinId);
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    // Persist theme choice
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('cleona_theme_mode', mode.index);
    });
  }

  /// Restore persisted theme mode (call early, before first build).
  Future<void> _restoreThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('cleona_theme_mode');
    if (idx != null && idx >= 0 && idx < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[idx];
      notifyListeners();
    }
  }

  /// Boot: check profile SYNCHRONOUSLY, then connect async.
  void _boot() {
    WidgetsBinding.instance.addObserver(this);
    _restoreThemeMode();
    // Monitor show-trigger (Unix desktops — pairs with Single-Instance-Guard
    // in main() which writes $home/.cleona/gui.show on re-launch)
    if (Platform.isLinux || Platform.isMacOS) {
      _showTriggerTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _checkShowTrigger();
      });
    }

    final hasIdentities = IdentityManager().loadIdentities().isNotEmpty;
    if (hasIdentities) {
      _hasProfile = true;
      initialize();
    }
  }

  void _checkShowTrigger() {
    final home = AppPaths.home;
    final triggerFile = File('$home/.cleona/gui.show');
    if (triggerFile.existsSync()) {
      triggerFile.deleteSync();
      WindowShow.show();
    }
  }

  // ── Daemon lifecycle ──────────────────────────────────────────────

  String get _baseDir {
    final home = AppPaths.home;
    return '$home/.cleona';
  }

  /// Check if a process with the given PID is alive.
  bool _isProcessAlive(int p) {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('tasklist', ['/FI', 'PID eq $p', '/NH']);
        return result.stdout.toString().contains('$p');
      }
      return Process.runSync('kill', ['-0', '$p']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  bool _isDaemonServiceRunning() {
    final pidFile = File('$_baseDir/cleona.pid');
    if (!pidFile.existsSync()) return false;
    try {
      final p = int.parse(pidFile.readAsStringSync().trim());
      if (_isProcessAlive(p)) {
        // Windows: check port file (TCP loopback), Linux: check socket file
        if (Platform.isWindows) {
          return File('$_baseDir/cleona.port').existsSync();
        }
        return File('$_baseDir/cleona.sock').existsSync();
      }
    } catch (_) {}
    try { pidFile.deleteSync(); } catch (_) {}
    return false;
  }

  bool _isDaemonProcessAlive() {
    final lockFile = File('$_baseDir/cleona.lock');
    if (!lockFile.existsSync()) return false;
    try {
      final p = int.parse(lockFile.readAsStringSync().trim());
      return _isProcessAlive(p);
    } catch (_) {}
    try { lockFile.deleteSync(); } catch (_) {}
    return false;
  }

  Future<bool> _signalDaemonToStart() async {
    File('$_baseDir/cleona.start').writeAsStringSync('start');
    return _waitForSocketConnectable(maxWaitMs: 15000);
  }

  Future<bool> _ensureDaemonRunning() async {
    // Check if an existing daemon has a display (= tray-capable).
    // If it runs without a display (e.g. started from SSH), replace it.
    if (_isDaemonProcessAlive()) {
      if (!_daemonHasDisplay()) {
        _killExistingDaemon();
      } else if (_isDaemonServiceRunning()) {
        return true;
      } else {
        return _signalDaemonToStart();
      }
    }

    // No daemon process (or just killed) — start a new one
    final daemonBinary = _findDaemonBinary();
    if (daemonBinary == null) return false;

    // Use first identity's port if available
    final identities = IdentityManager().loadIdentities();
    final port = identities.isNotEmpty ? identities.first.port : 4443;

    final args = [
      '--base-dir', _baseDir,
      '--port', '$port',
    ];

    if (Platform.isLinux) {
      // Use setsid to create a new session — the daemon becomes session leader
      // and is fully detached. This avoids the zombie intermediate process that
      // Dart's ProcessStartMode.detached creates via double-fork.
      final proc = await Process.start('setsid', [daemonBinary, ...args]);
      // Drain stdio to prevent pipe-full blocking
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();
      // Reap the setsid child process to prevent zombie
      // ignore: unawaited_futures
      proc.exitCode.then((_) {});
    } else {
      await Process.start(daemonBinary, args, mode: ProcessStartMode.detached);
    }
    return _waitForSocketConnectable(maxWaitMs: 15000);
  }

  /// Check if the running daemon has DISPLAY (= tray icon possible).
  /// On Windows/macOS: always true — no headless SSH daemon story there, and
  /// macOS has no procfs for env inspection, so we'd otherwise falsely kill
  /// the running daemon on every GUI launch.
  bool _daemonHasDisplay() {
    if (Platform.isWindows || Platform.isMacOS) return true;
    final lockFile = File('$_baseDir/cleona.lock');
    if (!lockFile.existsSync()) return false;
    try {
      final p = int.parse(lockFile.readAsStringSync().trim());
      final env = File('/proc/$p/environ').readAsStringSync();
      return env.contains('DISPLAY=') || env.contains('WAYLAND_DISPLAY=');
    } catch (_) {
      return false;
    }
  }

  /// Kill existing daemon and clean up lock files.
  void _killExistingDaemon() {
    final lockFile = File('$_baseDir/cleona.lock');
    try {
      final p = int.parse(lockFile.readAsStringSync().trim());
      if (Platform.isWindows) {
        Process.runSync('taskkill', ['/PID', '$p', '/F']);
      } else {
        Process.runSync('kill', ['-TERM', '$p']);
        sleep(const Duration(seconds: 1));
        if (Process.runSync('kill', ['-0', '$p']).exitCode == 0) {
          Process.runSync('kill', ['-9', '$p']);
        }
      }
    } catch (_) {}
    try { lockFile.deleteSync(); } catch (_) {}
    try { File('$_baseDir/cleona.sock').deleteSync(); } catch (_) {}
    try { File('$_baseDir/cleona.port').deleteSync(); } catch (_) {}
    try { File('$_baseDir/cleona.pid').deleteSync(); } catch (_) {}
  }

  String? _findDaemonBinary() {
    final exePath = Platform.resolvedExecutable;
    final sep = Platform.pathSeparator;
    final bundleDir = exePath.substring(0, exePath.lastIndexOf(sep));
    final daemonName = Platform.isWindows ? 'cleona-daemon.exe' : 'cleona-daemon';
    for (final path in [
      '$bundleDir$sep$daemonName',
      '$bundleDir$sep..$sep$daemonName',
      '${Directory.current.path}${sep}build$sep$daemonName',
    ]) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<bool> _waitForSocketConnectable({int maxWaitMs = 15000}) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < maxWaitMs) {
      try {
        if (Platform.isWindows) {
          // Windows: TCP loopback — read port + auth token from file
          final portFile = File('$_baseDir/cleona.port');
          if (portFile.existsSync()) {
            final contents = portFile.readAsStringSync().trim();
            final parts = contents.split(':');
            final port = int.parse(parts[0]);
            final token = parts.length > 1 ? parts[1] : null;
            final sock = await Socket.connect(
              InternetAddress.loopbackIPv4, port,
            ).timeout(const Duration(seconds: 2));
            // Send auth token so daemon doesn't disconnect us
            if (token != null) {
              sock.write('{"type":"auth","token":"$token"}\n');
            }
            sock.destroy();
            return true;
          }
        } else {
          // Linux/macOS: Unix Domain Socket
          final socketPath = '$_baseDir/cleona.sock';
          if (File(socketPath).existsSync()) {
            final sock = await Socket.connect(
              InternetAddress(socketPath, type: InternetAddressType.unix),
              0,
            ).timeout(const Duration(seconds: 2));
            sock.destroy();
            return true;
          }
        }
      } catch (_) {
        // Not ready yet — keep waiting
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  // ── Retry daemon connection (for slow PQ keygen on VMs) ──────────

  Timer? _retryTimer;

  void _scheduleRetryConnect() {
    _retryTimer?.cancel();
    int attempt = 0;
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempt++;
      debugPrint('[main] Retry daemon connect attempt $attempt');
      final ok = await _waitForSocketConnectable(maxWaitMs: 3000);
      if (ok) {
        timer.cancel();
        debugPrint('[main] Daemon ready after retry — reconnecting');
        await initialize();
      } else if (attempt >= 24) {
        // Give up after 2 minutes of retries (24 x 5s)
        timer.cancel();
        debugPrint('[main] Daemon still not ready after ${attempt * 5}s — giving up');
      }
    });
  }

  // ── Connectivity monitoring (event-driven, no polling) ────────────

  void _startConnectivityMonitor() {
    _connectivitySub?.cancel();
    // Fetch initial connectivity state
    Connectivity().checkConnectivity().then((results) {
      _connectivityResults = results;
      notifyListeners();
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      debugPrint('[connectivity] Change: $results');
      _connectivityResults = results;
      notifyListeners();
      if (!_isInitialized) return;
      // Android multi-identity: notify node + ALL services
      if (_androidNode != null) {
        _androidNode!.onNetworkChanged();
        for (final service in _androidServices.values) {
          service.onNetworkChanged();
        }
      } else {
        _service?.onNetworkChanged();
      }
    });
  }

  // ── Initialize ────────────────────────────────────────────────────

  Future<void> initialize() async {
    _hasProfile = true;

    final daemonStarted = await _ensureDaemonRunning();

    if (daemonStarted) {
      final socketPath = '$_baseDir/cleona.sock';
      final ipcClient = IpcClient(socketPath: socketPath);
      final connected = await ipcClient.connect();

      if (connected) {
        _ipcClient = ipcClient;
        _service = ipcClient;

        ipcClient.onStateChanged = () => notifyListeners();
        ipcClient.onNewMessage = (convId, msg) => notifyListeners();
        ipcClient.onContactRequestReceived = (nodeId, name) => notifyListeners();
        ipcClient.onContactAccepted = (nodeId) => notifyListeners();
        ipcClient.onIncomingCall = (call) => _showIncomingCallScreen(call);
        ipcClient.onCallEnded = (_) => notifyListeners();
        ipcClient.onCallAccepted = (_) => notifyListeners();
        ipcClient.onCallRejected = (call, reason) => notifyListeners();
        ipcClient.onGuiAction = (data) => _handleGuiAction(data);
        ipcClient.onDaemonDied = () {
          // GUI and daemon act as one unit — if daemon dies, GUI exits.
          // Next GUI launch will start a fresh daemon via _ensureDaemonRunning().
          debugPrint('[main] Daemon connection lost — exiting GUI');
          exit(0);
        };

        // Sync active identity from IdentityManager to IPC
        final activeId = IdentityManager().getActiveIdentity();
        if (activeId != null && activeId.nodeIdHex != null) {
          await ipcClient.switchIdentity(activeId.nodeIdHex!);
        }

        _isInitialized = true;
        _startConnectivityMonitor();
        // Force Navigator rebuild when transitioning from loading to home
        navigatorKey = GlobalKey<NavigatorState>();
        notifyListeners();
        return;
      }
    }

    // Android: no daemon, start node in-process (the app IS the node).
    // Same multi-identity model as the Linux daemon: one node, all identities active.
    // IMPORTANT: Defer heavy work so the loading screen renders first.
    if (Platform.isAndroid) {
      // Signal that we have a profile (shows loading screen immediately)
      notifyListeners();
      // Schedule heavy init after the current frame completes
      Future(() => _initAndroidInProcess());
      return;
    }

    // Linux/Windows: daemon not reachable. Keys are pre-generated by
    // IdentityManager.createIdentity(), so the daemon should start in <2s.
    // If we still can't connect, schedule a brief retry (handles edge cases
    // like daemon starting from a cold binary cache).
    debugPrint('[main] Daemon not ready yet — scheduling background retry');
    _isInitialized = false;
    notifyListeners();
    _scheduleRetryConnect();
  }

  // ── Android in-process init (deferred from initialize()) ──────

  Future<void> _initAndroidInProcess() async {
    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    if (identities.isEmpty) return;

    final masterSeed = mgr.loadMasterSeed();
    final firstId = identities.first;

    // Create primary identity context
    final primaryCtx = IdentityContext(
      profileDir: firstId.profileDir,
      displayName: firstId.displayName,
      networkChannel: NetworkSecret.channel.name,
      hdIndex: firstId.hdIndex,
      masterSeed: masterSeed,
      createdAt: firstId.createdAt,
      isAdult: firstId.isAdult,
    );
    await primaryCtx.initKeys();
    firstId.nodeIdHex = primaryCtx.userIdHex;
    _androidContexts[primaryCtx.userIdHex] = primaryCtx;

    // Create contexts for ALL additional identities
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
      await ctx.initKeys();
      id.nodeIdHex = ctx.userIdHex;
      _androidContexts[ctx.userIdHex] = ctx;
    }

    // ONE shared node for all identities
    final node = CleonaNode(
      profileDir: _baseDir,
      port: firstId.port,
      networkChannel: NetworkSecret.channel.name,
    );
    node.primaryIdentity = primaryCtx;
    _androidNode = node;

    // Register ALL identities with the node
    for (final ctx in _androidContexts.values) {
      node.registerIdentity(ctx);
    }

    // Notify GUI when peer addresses change
    node.onPeersChanged = () {
      for (final service in _androidServices.values) {
        service.onStateChanged?.call();
      }
    };

    // Message routing (with early-message buffer)
    node.onMessageForIdentity = _androidOnMessageForIdentity;

    // Start node (UDP listener active → messages can arrive)
    await node.startQuick();

    // Mobile fallback state → icon update (AFTER startQuick — transport is late-initialized)
    node.transport.onMobileFallbackChanged = (active) {
      _mobileFallbackActive = active;
      notifyListeners();
    };

    // Create and start a CleonaService for EACH identity
    for (final ctx in _androidContexts.values) {
      final service = CleonaService(
        identity: ctx,
        node: node,
        displayName: ctx.displayName,
      );
      _wireServiceCallbacks(service);
      await service.startService();
      _androidServices[ctx.userIdHex] = service;
      debugPrint('[main] Service gestartet: ${ctx.displayName} (${ctx.userIdHex.substring(0, 16)}...)');
    }

    // Replay early messages
    _androidServicesReady = true;
    if (_androidEarlyMessages.isNotEmpty) {
      debugPrint('[main] Replaying ${_androidEarlyMessages.length} early messages');
      final buffered = List.of(_androidEarlyMessages);
      _androidEarlyMessages.clear();
      for (final (env, from, port, id) in buffered) {
        _androidOnMessageForIdentity(env, from, port, id);
      }
    }

    // Save updated nodeIdHex values
    mgr.saveIdentities(identities);

    // Set active service (based on IdentityManager selection)
    final activeId = IdentityManager().getActiveIdentity();
    final activeHex = activeId?.nodeIdHex ?? primaryCtx.userIdHex;
    _service = _androidServices[activeHex] ?? _androidServices.values.first;

    _isInitialized = true;
    _startConnectivityMonitor();
    _queryPublicIp(); // §27: discover own public IPv4/IPv6 for external reachability
    navigatorKey = GlobalKey<NavigatorState>();
    notifyListeners();
  }

  // ── Incoming Call ──────────────────────────────────────────────

  void _showIncomingCallScreen(CallInfo call) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // Determine display name from contacts
    final contact = _service?.getContact(call.peerNodeIdHex);
    final displayName = contact?.displayName ?? call.peerNodeIdHex.substring(0, 8);

    nav.push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: this,
          child: CallScreen(
            callInfo: call,
            peerDisplayName: displayName,
          ),
        ),
      ),
    );
  }

  // ── Multi-Identity ─────────────────────────────────────────────

  /// Switches to another identity — IMMEDIATELY via IPC or in-process.
  Future<void> switchIdentity(Identity identity) async {
    if (_ipcClient != null && identity.nodeIdHex != null) {
      // Linux: instant switch via IPC
      final ok = await _ipcClient!.switchIdentity(identity.nodeIdHex!);
      if (ok) {
        IdentityManager().setActiveIdentity(identity);
        notifyListeners();
        return;
      }
    }

    // Android in-process: switch to the right service
    if (_androidServices.isNotEmpty && identity.nodeIdHex != null) {
      final service = _androidServices[identity.nodeIdHex!];
      if (service != null) {
        _service = service;
        IdentityManager().setActiveIdentity(identity);
        notifyListeners();
        return;
      }
    }

    IdentityManager().setActiveIdentity(identity);
    notifyListeners();
  }

  /// Wires standard callbacks on a CleonaService (avoids duplication).
  void _wireServiceCallbacks(CleonaService service) {
    service.onStateChanged = () => notifyListeners();
    service.onNewMessage = (convId, msg) => notifyListeners();
    service.onContactRequestReceived = (nodeId, name) => notifyListeners();
    service.onContactAccepted = (nodeId) => notifyListeners();
    service.onIncomingCall = (call) => _showIncomingCallScreen(call);
    service.onCallEnded = (_) => notifyListeners();
    service.onCallAccepted = (_) => notifyListeners();
    service.onCallRejected = (call, reason) => notifyListeners();

    // Android: inject platform-specific callbacks
    if (Platform.isAndroid) {
      service.setPlatformAudioDecoder(_androidDecodeToWav);

      // Notification: post system notification for incoming messages
      service.onPostNotificationAndroid = (title, body, convId) async {
        const channel = MethodChannel('chat.cleona/notification');
        await channel.invokeMethod('postNotification', {
          'title': title,
          'body': body,
          'conversationId': convId,
        });
      };

      // Cancel notification when conversation is read
      service.onCancelNotificationAndroid = (convId) {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('cancelNotification', {'conversationId': convId});
      };

      // Badge count update
      service.onBadgeCountChanged = (count) {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('updateBadge', {'count': count});
      };

      // Sound playback via platform channel
      service.notificationSound.onPlaySoundAndroid = (filename) async {
        const channel = MethodChannel('chat.cleona/notification');
        await channel.invokeMethod('playSound', {'asset': 'assets/sounds/$filename'});
      };

      // Vibration via platform channel
      service.notificationSound.onVibrateAndroid = (durationMs) async {
        const channel = MethodChannel('chat.cleona/vibration');
        await channel.invokeMethod('vibrate', {'duration': durationMs});
      };
    }
  }

  /// Decode audio to WAV via Android MediaCodec MethodChannel.
  static Future<Uint8List?> _androidDecodeToWav(String inputPath, String outputPath) async {
    try {
      const channel = MethodChannel('chat.cleona/audio');
      debugPrint('[audio-decode] decodeToWav: $inputPath → $outputPath');
      final success = await channel.invokeMethod<bool>('decodeToWav', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
      if (success != true) {
        debugPrint('[audio-decode] MediaCodec returned false');
        return null;
      }
      final file = File(outputPath);
      if (!file.existsSync()) {
        debugPrint('[audio-decode] Output file does not exist: $outputPath');
        return null;
      }
      final bytes = await file.readAsBytes();
      debugPrint('[audio-decode] Success: ${bytes.length} bytes WAV');
      return bytes;
    } catch (e) {
      debugPrint('[audio-decode] Error: $e');
      return null;
    }
  }

  /// Routes messages to the correct service (Android in-process only).
  /// Same logic as _MultiServiceDaemon._onMessageForIdentity in service_daemon.dart.
  void _androidOnMessageForIdentity(
      dynamic envelope, dynamic from, int port, IdentityContext? identity) {
    if (!_androidServicesReady) {
      _androidEarlyMessages.add((envelope, from, port, identity));
      return;
    }

    if (identity != null) {
      _androidServices[identity.userIdHex]?.handleMessage(envelope, from, port);
      return;
    }

    // recipientId didn't match or empty — route by message type
    final env = envelope as proto.MessageEnvelope;
    final isFragment = env.messageType == proto.MessageType.FRAGMENT_STORE ||
        env.messageType == proto.MessageType.FRAGMENT_RETRIEVE ||
        env.messageType == proto.MessageType.FRAGMENT_STORE_ACK;

    if (isFragment) {
      for (final service in _androidServices.values) {
        service.handleMessage(envelope, from, port);
      }
    } else if (env.groupId.isNotEmpty) {
      final groupIdHex = bytesToHex(Uint8List.fromList(env.groupId));
      var routed = false;
      for (final service in _androidServices.values) {
        if (service.groups.containsKey(groupIdHex) ||
            service.channels.containsKey(groupIdHex)) {
          service.handleMessage(envelope, from, port);
          routed = true;
        }
      }
      if (!routed) {
        for (final service in _androidServices.values) {
          service.handleMessage(envelope, from, port);
        }
      }
    } else {
      for (final service in _androidServices.values) {
        service.handleMessage(envelope, from, port);
      }
    }
  }

  /// Removes an identity at runtime (Android in-process).
  Future<bool> deleteIdentityAndroid(String nodeIdHex) async {
    if (_androidServices.length <= 1) return false;

    final service = _androidServices.remove(nodeIdHex);
    if (service != null) {
      await service.stop();
    }
    _androidContexts.remove(nodeIdHex);
    _androidNode?.unregisterIdentity(nodeIdHex);

    // Switch _service if we just deleted the active one
    if (_service == service && _androidServices.isNotEmpty) {
      _service = _androidServices.values.first;
      final mgr = IdentityManager();
      final identities = mgr.loadIdentities();
      final firstId = identities.firstOrNull;
      if (firstId != null) {
        mgr.setActiveIdentity(firstId);
      }
    }

    notifyListeners();
    return true;
  }

  /// Deletes an identity — works on both Linux (IPC) and Android (in-process).
  /// Stops the running service, unregisters from node, deletes from disk.
  Future<bool> deleteIdentity(Identity identity) async {
    final nodeIdHex = identity.nodeIdHex;
    if (nodeIdHex == null) return false;

    // Linux: delegate to daemon via IPC
    if (_ipcClient != null) {
      final ok = await _ipcClient!.deleteIdentity(nodeIdHex);
      if (ok) {
        IdentityManager().deleteIdentity(identity.id);
        final remaining = IdentityManager().loadIdentities();
        if (remaining.isNotEmpty) {
          IdentityManager().setActiveIdentity(remaining.first);
        }
        notifyListeners();
        return true;
      }
      return false;
    }

    // Android: in-process
    if (_androidServices.isNotEmpty) {
      IdentityManager().deleteIdentity(identity.id);
      return deleteIdentityAndroid(nodeIdHex);
    }

    // Fallback (no daemon, no node): just delete from disk
    IdentityManager().deleteIdentity(identity.id);
    final remaining = IdentityManager().loadIdentities();
    if (remaining.isNotEmpty) {
      await switchIdentity(remaining.first);
    }
    return true;
  }

  void _handleGuiAction(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    if (action == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (action) {
      case 'open_identity_detail':
        final identity = IdentityManager().getActiveIdentity();
        if (identity != null && _service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: IdentityDetailScreen(service: _service!, identity: identity),
            ),
          ));
        }
        break;
      case 'open_settings':
        if (_service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: Scaffold(
                appBar: AppBar(title: const Text('Settings')),
                body: SafeArea(top: false, child: SettingsScreen(service: _service!)),
              ),
            ),
          ));
        }
        break;
      case 'open_calendar':
        if (_service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: const CalendarScreen(),
            ),
          ));
        }
        break;
      case 'open_network_stats':
        if (_service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: Scaffold(
                appBar: AppBar(title: const Text('Network Stats')),
                body: SafeArea(top: false, child: NetworkStatsScreen(service: _service!)),
              ),
            ),
          ));
        }
        break;
      case 'go_back':
        if (nav.canPop()) {
          nav.pop();
        }
        // Signal HomeScreen to reset to "Aktuell" tab (index 0)
        _goBackCounter++;
        notifyListeners();
        break;

      case 'open_archive_settings':
        nav.push(MaterialPageRoute(
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: this),
              if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
            ],
            child: ArchiveSettingsScreen(service: _service!),
          ),
        ));
        break;

      case 'open_transcription_settings':
        nav.push(MaterialPageRoute(
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: this),
              if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
            ],
            child: TranscriptionSettingsScreen(service: _service!),
          ),
        ));
        break;

      case 'open_device_management':
        if (_service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: DeviceManagementScreen(service: _service!),
            ),
          ));
        }
        break;

      case 'tap_archive_placeholder':
      case 'long_press_media_message':
      case 'open_chat_menu':
      case 'open_batch_retrieval':
        // Stub actions: will be wired up later with full UI integration
        break;

      case 'switch_language':
        final code = (data['code'] ?? data['language']) as String?;
        if (code != null && _appLocale != null) {
          _appLocale!.setLocale(code);
        }
        break;

      case 'open_chat':
        final convId = data['conversationId'] as String?;
        final targetIdentityId = data['identityId'] as String?;
        if (convId == null || _service == null) break;
        // `switch_active` on the IPC server is scoped to the caller's connection,
        // so an IPC client that switched identity cannot implicitly drive the GUI's
        // view. If `identityId` is supplied and differs from the GUI's active
        // identity, switch first so `_service.conversations[convId]` resolves.
        //
        // `targetIdentityId` may be either the identityId (UUID) or the
        // nodeIdHex — historically tests pass `bob.identityId` (the UUID
        // returned by listIdentities), but the lookup also has to support
        // nodeIdHex for callers that fetch via getState. Match against both.
        unawaited(() async {
          if (targetIdentityId != null) {
            final active = IdentityManager().getActiveIdentity();
            final activeMatches = active != null &&
                (active.nodeIdHex == targetIdentityId ||
                    active.id == targetIdentityId);
            if (!activeMatches) {
              final match = IdentityManager()
                  .loadIdentities()
                  .where((i) =>
                      i.nodeIdHex == targetIdentityId ||
                      i.id == targetIdentityId)
                  .toList();
              if (match.isNotEmpty) {
                await switchIdentity(match.first);
              }
            }
          }
          final conv = _service!.conversations[convId];
          if (conv == null) return;
          final navState = navigatorKey.currentState;
          if (navState == null) return;
          navState.push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: this,
              child: ChatScreen(
                conversationId: convId,
                displayName: conv.displayName,
                isGroup: conv.isGroup,
                isChannel: conv.isChannel,
              ),
            ),
          ));
        }());
        break;

      case 'open_poll_editor':
        final convId = data['conversationId'] as String?;
        if (convId == null || _service == null) break;
        final conv = _service!.conversations[convId];
        if (conv == null) break;
        nav.push(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: this,
            child: PollEditorScreen(
              conversationId: convId,
              isGroup: conv.isGroup,
              isChannel: conv.isChannel,
            ),
          ),
        ));
        break;

      case 'open_qr_show':
        if (_service != null) {
          nav.push(MaterialPageRoute(
            builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: this),
                if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
              ],
              child: QrShowScreen(service: _service!),
            ),
          ));
        }
        break;

      case 'select_skin':
        final skinId = data['skinId'] as String?;
        if (skinId != null) {
          final identity = IdentityManager().getActiveIdentity();
          if (identity != null) {
            IdentityManager().setSkinId(identity.id, skinId);
            notifyListeners();
          }
        }
        break;

      case 'show_seed_phrase':
        {
          final words = IdentityManager().loadSeedPhrase();
          if (words != null) {
            showDialog(
              context: nav.context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('Recovery Phrase'),
                content: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(child: Text('Niemals teilen!', style: TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(words.length, (i) {
                          return Chip(label: Text('${i + 1}. ${words[i]}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)));
                        }),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopieren'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: words.join(' ')));
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            );
          } else {
            showDialog(
              context: nav.context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('Recovery Phrase'),
                content: const Text('Keine Recovery-Phrase gespeichert.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
        break;

      case 'dismiss_dialog':
        // Pop the top-most route if it's a dialog/popup
        if (nav.canPop()) nav.pop();
        break;

      // ── NAT-Wizard test hooks (E2E gui-53, §27.9) ────────────────────
      case 'reset_nat_wizard_latch':
        // Test-only: bump the counter so HomeScreen clears its
        // `_natWizardShown` one-shot latch. Production code never emits
        // this action; it exists purely so gui-53 tests can re-trigger
        // the wizard after a prior run already showed it.
        _natWizardResetCounter++;
        notifyListeners();
        break;

      case 'user_request_nat_wizard':
        // Test-only (gui-55): exercises the full user-tap path —
        // service.requestNatWizard() → onNatWizardUserRequested →
        // HomeScreen._showNatWizardDialog → NatWizardDialog. Use this to
        // force the wizard dialog on AVM where `good` tier is never
        // reached naturally (emulator has 0 confirmed peers).
        _service?.requestNatWizard();
        break;

      case 'open_nat_wizard':
        {
          // Test-only: show Step 1 dialog directly with a stub port/IP, no
          // service-level plumbing required. Callbacks close the dialog —
          // dismissNatWizard() is NOT called here so the production dismiss
          // path can be tested separately via testForceNatWizardTrigger.
          final port = (data['port'] as num?)?.toInt() ?? _service?.port ?? 0;
          final ip = (data['localIp'] as String?) ??
              (_service?.localIps.isNotEmpty == true
                  ? _service!.localIps.first
                  : '127.0.0.1');
          showDialog<void>(
            context: nav.context,
            barrierDismissible: false,
            builder: (ctx) => NatWizardDialog(
              currentPort: port,
              localIp: ip,
              onShowInstructions: () => Navigator.of(ctx).pop(),
              onLater: () => Navigator.of(ctx).pop(),
              onNeverAgain: () => Navigator.of(ctx).pop(),
            ),
          );
        }
        break;

      case 'nat_wizard_dialog_action':
        {
          // Test-only (E2E gui-53 53.04/05/06): simulate a click on one of the
          // Step-1 dialog action buttons. Avoids the AlertDialog action-row
          // coordinate drift that broke OCR-locate-click in early gui-53 runs.
          // `which` values: 'instructions' (push Step 2), 'later' (dismiss 7d),
          // 'never' (dismiss forever). Param name is `which` (not `action`)
          // to avoid clash with the outer `data['action']` gui-action selector.
          final which = (data['which'] as String?) ?? '';
          final svc = _service;
          if (svc == null) break;
          // 1. Pop any open dialog (the Step-1 NatWizardDialog if shown).
          if (nav.canPop()) nav.pop();
          // 2. Apply the production-side effect identical to the click handler
          //    in home_screen.dart `_showNatWizardDialog`.
          switch (which) {
            case 'later':
              svc.dismissNatWizard(durationSeconds: 7 * 24 * 3600);
              break;
            case 'never':
              svc.dismissNatWizard(durationSeconds: 0);
              break;
            case 'instructions':
              // Push the Step-2 router-select screen (same chain as the
              // home_screen onShowInstructions callback). Re-fetch the
              // NavigatorState inside the async closure so a stale `nav`
              // (post-pop) doesn't trip over a disposed state.
              unawaited(() async {
                // ignore: avoid_print
                print('[nat-wizard-test] loading RouterDb...');
                final routerDb = await RouterDb.load();
                final navNow = navigatorKey.currentState;
                if (navNow == null || !navNow.mounted) {
                  // ignore: avoid_print
                  print('[nat-wizard-test] navigator state gone after RouterDb.load');
                  return;
                }
                final detectedInfo = svc.getNetworkStats().upnpRouterInfo;
                // ignore: avoid_print
                print('[nat-wizard-test] pushing NatWizardRouterSelectScreen');
                navNow.push(
                  MaterialPageRoute<void>(
                    builder: (_) => NatWizardRouterSelectScreen(
                      routerDb: routerDb,
                      detectedInfo: detectedInfo,
                      onEntrySelected: (entry) {
                        navigatorKey.currentState?.push(
                          MaterialPageRoute<void>(
                            builder: (_) => NatWizardInstructionsScreen(
                              entry: entry,
                              currentPort: svc.port,
                              localIp: svc.localIps.isNotEmpty
                                  ? svc.localIps.first
                                  : null,
                              onRecheck: () => svc.recheckNatWizard(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }());
              break;
          }
        }
        break;

      case 'open_nat_wizard_instructions':
        {
          // Test-only: skip Step 1+2, push Step 3 directly for a specific
          // RouterDb entry. Optional `fakeResult` controls what the
          // "Jetzt pruefen" button returns (default: true after 300ms).
          final entryId = (data['entryId'] as String?) ?? 'generic';
          final fakeResult = data['fakeResult'] as bool? ?? true;
          final port = (data['port'] as num?)?.toInt() ?? _service?.port ?? 0;
          final ip = (data['localIp'] as String?) ??
              (_service?.localIps.isNotEmpty == true
                  ? _service!.localIps.first
                  : '127.0.0.1');
          unawaited(() async {
            RouterDbEntry? entry;
            try {
              final db = await RouterDb.load();
              for (final e in db.entries) {
                if (e.id == entryId) {
                  entry = e;
                  break;
                }
              }
              // Fallback: generic if the requested id is unknown.
              entry ??= db.entries.firstWhere(
                (e) => e.manufacturerContains.isEmpty && e.modelContains.isEmpty,
                orElse: () => db.entries.isNotEmpty
                    ? db.entries.last
                    : const RouterDbEntry(
                        id: 'generic',
                        displayName: 'Router',
                        manufacturerContains: <String>[],
                        modelContains: <String>[],
                        adminUrlHints: <String>[],
                        deeplinkPath: null,
                        stepsI18nKey: 'nat_wizard_steps_generic',
                        notesI18nKey: 'nat_wizard_notes_generic',
                      ),
              );
            } catch (_) {
              entry = const RouterDbEntry(
                id: 'generic',
                displayName: 'Router',
                manufacturerContains: <String>[],
                modelContains: <String>[],
                adminUrlHints: <String>[],
                deeplinkPath: null,
                stepsI18nKey: 'nat_wizard_steps_generic',
                notesI18nKey: 'nat_wizard_notes_generic',
              );
            }
            final navState = navigatorKey.currentState;
            if (navState == null) return;
            navState.push(MaterialPageRoute(
              builder: (_) => MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: this),
                  if (_appLocale != null)
                    ChangeNotifierProvider.value(value: _appLocale!),
                ],
                child: NatWizardInstructionsScreen(
                  entry: entry!,
                  currentPort: port,
                  localIp: ip,
                  // 300ms delay so tests can observe the spinner briefly
                  // without meaningfully slowing E2E runs.
                  onRecheck: () async {
                    await Future<void>.delayed(
                        const Duration(milliseconds: 300));
                    return fakeResult;
                  },
                ),
              ),
            ));
          }());
        }
        break;
    }
  }

  /// Creates a new identity and switches to it.
  Future<void> createAndSwitchIdentity(String displayName) async {
    if (_ipcClient != null) {
      // Linux: daemon running — create + register identity via IPC
      final newNodeIdHex = await _ipcClient!.createIdentity(displayName);
      if (newNodeIdHex != null) {
        final identities = IdentityManager().loadIdentities();
        final newIdentity = identities.where((i) => i.nodeIdHex == newNodeIdHex).firstOrNull;
        if (newIdentity != null) {
          IdentityManager().setActiveIdentity(newIdentity);
        }
        notifyListeners();
        return;
      }
    }

    // Android in-process: create identity and register with running node
    if (_androidNode != null) {
      final mgr = IdentityManager();
      final identity = await mgr.createIdentity(displayName);
      final masterSeed = mgr.loadMasterSeed();
      final ctx = IdentityContext(
        profileDir: identity.profileDir,
        displayName: displayName,
        networkChannel: NetworkSecret.channel.name,
        hdIndex: identity.hdIndex,
        masterSeed: masterSeed,
        createdAt: identity.createdAt,
        isAdult: identity.isAdult,
      );
      await ctx.initKeys();
      identity.nodeIdHex = ctx.userIdHex;

      _androidContexts[ctx.userIdHex] = ctx;
      _androidNode!.registerIdentity(ctx);

      final service = CleonaService(
        identity: ctx,
        node: _androidNode!,
        displayName: displayName,
      );
      _wireServiceCallbacks(service);
      await service.startService();
      _androidServices[ctx.userIdHex] = service;

      // Save updated nodeIdHex
      final identities = mgr.loadIdentities();
      for (final id in identities) {
        if (id.id == identity.id) {
          id.nodeIdHex = ctx.userIdHex;
          break;
        }
      }
      mgr.saveIdentities(identities);

      _service = service;
      IdentityManager().setActiveIdentity(identity);
      notifyListeners();
      return;
    }

    // Fallback: create directly (no daemon, no running node)
    final identity = await IdentityManager().createIdentity(displayName);
    await switchIdentity(identity);
  }

  @override
  void dispose() {
    _showTriggerTimer?.cancel();
    _connectivitySub?.cancel();
    final home = AppPaths.home;
    try { File('$home/.cleona/gui.lock').deleteSync(); } catch (_) {}
    if (_ipcClient != null) {
      // Prevent onDaemonDied from firing during intentional GUI close
      _ipcClient!.onDaemonDied = null;
      _ipcClient!.disconnect();
    } else if (_androidServices.isNotEmpty) {
      // Android: stop all services and shared node
      for (final service in _androidServices.values) {
        service.stop();
      }
      _androidServices.clear();
      _androidContexts.clear();
      _androidNode?.stop();
      _androidNode = null;
    } else if (_service is CleonaService) {
      (_service as CleonaService).stop();
    }
    super.dispose();
  }
}
