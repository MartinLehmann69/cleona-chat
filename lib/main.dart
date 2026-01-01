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
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/keyring_mobile.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/screens/call_screen.dart';
import 'package:cleona/ui/screens/chat_screen.dart';
import 'package:cleona/ui/screens/group_call_screen.dart';
import 'package:cleona/ui/screens/qr_contact_screen.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'dart:ui' as ui;
import 'package:cleona/core/calls/video_engine.dart';
import 'package:cleona/core/calls/video_capture_android.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/platform/window_show.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/platform/share_receiver.dart';
import 'package:cleona/core/platform/ios_background_fetch.dart';
import 'package:cleona/ui/theme/skin.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/ui/screens/update_required_screen.dart';
import 'package:cleona/core/channels/system_channels.dart' as sys_ch;
import 'package:cleona/ui/components/connection_sheet.dart';
import 'package:cleona/ui/components/crash_report_dialog.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart' as pp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // §16.2 (V3.1.117): stamp the Dart heartbeat as early as possible — before
  // FFI/keyring init, which can be slow or crash. The Kotlin watchdog must
  // see a fresh stamp from THIS run, not judge the app by a stale file or a
  // late first stamp after full boot.
  if (Platform.isAndroid) {
    try {
      final dir = Directory('${AppPaths.home}/.cleona');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('${dir.path}/.dart-heartbeat')
          .writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
  }

  // iOS: resolve writable data container via path_provider BEFORE anything
  // touches AppPaths.home. On iOS, HOME is '/tmp' (sandbox) and the bundle
  // path is read-only — only path_provider gives the correct writable
  // Application Support directory inside the data container.
  if (Platform.isIOS) {
    try {
      final appSupport = await pp.getApplicationSupportDirectory();
      AppPaths.setHome(appSupport.path);
      debugPrint('[main] iOS home set via path_provider: ${appSupport.path}');
      // Mirror ALL CLogger output to Documents/ — the only directory
      // accessible via AFC/iTunes for debug log retrieval on iOS 18+
      // (idevicesyslog no longer shows app-level logs).
      final docs = await pp.getApplicationDocumentsDirectory();
      CLogger.iosMirrorPath = docs.path;
      debugPrint('[main] iOS log mirror: ${docs.path}/logs/');
    } catch (e) {
      debugPrint('[main] path_provider failed: $e — falling back to AppPaths default');
    }
  }

  // Single-Instance (Unix desktops — Linux + macOS; both have kill -0 and $HOME)
  if (Platform.isLinux || Platform.isMacOS) {
    if (_signalExistingInstance()) {
      exit(0);
    }
    _writeGuiLock();
  }

  // Mobile: Portrait lock prevents Activity/Scene recreation on rotation
  // which would destroy the in-process CleonaNode (port conflict, state corruption).
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  // Android-only: Edge-to-Edge transparent system bars.
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  // iOS startup diagnostics: catch FFI init failures that would otherwise
  // silently prevent runApp() from being reached (→ white screen).
  String? startupError;
  try {
    debugPrint('[main] Platform: ${Platform.operatingSystem}, home: ${AppPaths.home}, dataDir: ${AppPaths.dataDir}');
    debugPrint('[main] Initializing SodiumFFI...');
    SodiumFFI();
    debugPrint('[main] SodiumFFI OK. Initializing OqsFFI...');
    OqsFFI().init();
    debugPrint('[main] OqsFFI OK.');
    // §3.7: Initialize OS keyring + migrate (shared sequence — S106 fix)
    debugPrint('[main] Initializing KeyringService...');
    if (Platform.isAndroid || Platform.isIOS) {
      await MobileKeyringService.init(AppPaths.dataDir);
    }
    await IdentityContext.initCrypto(AppPaths.dataDir);
    debugPrint('[main] KeyringService OK (hw=${KeyringService.instance.isHardwareProtected}).');
  } catch (e, stack) {
    startupError = 'FFI init failed on ${Platform.operatingSystem}\n'
        'home=${AppPaths.home}\ndataDir=${AppPaths.dataDir}\n\n$e\n$stack';
    debugPrint('[main] FATAL: $startupError');
    _logCrash('main-ffi-init', e, stack);
  }

  // Enable accessibility semantics so AT-SPI can inspect the widget tree
  // This is required for automated GUI testing via accessibility tools
  SemanticsBinding.instance.ensureSemantics();

  // H7 (#U17): Globale Error-Handler — uncaught exceptions crashen sonst
  // Android stillschweigend. Mirror des Patterns aus headless.dart:20.
  FlutterError.onError = (details) {
    _logCrash('FlutterError', details.exception, details.stack);
    if (details.stack != null) {
      CleonaAppState._instance?.handleCrash(details.exception, details.stack!);
    }
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logCrash('PlatformDispatcher', error, stack);
    CleonaAppState._instance?.handleCrash(error, stack);
    return true;
  };

  // If FFI init failed, show error on screen instead of white screen.
  if (startupError != null) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Cleona Startup Error:\n\n$startupError',
              style: const TextStyle(color: Colors.white, fontSize: 12,
                fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ));
    return;
  }

  // Sec H-5 (V3.1.72) / T13: Hard-block check at startup.
  // Reads the cached, signature-verified update manifest written by the
  // previous session's 6h DHT-poll (`CleonaService._checkForUpdates`).
  // If the manifest specifies `minRequiredVersion` and the running app
  // is older, we route to [UpdateRequiredScreen] before any service is
  // constructed. Fail-safe: any IO/parse/signature problem leaves the
  // user on the normal path. On a fresh install no cache exists, so the
  // splash only kicks in once a manifest has been observed at least once.
  UpdateManifest? blockManifest;
  bool hardBlocked = false;
  try {
    final cachedJson = _readCachedManifestSync();
    if (cachedJson != null) {
      final manifest = UpdateChecker().verifyManifest(cachedJson);
      if (manifest != null &&
          UpdateChecker().isHardBlocked(manifest, CleonaService.kCurrentAppVersion)) {
        blockManifest = manifest;
        hardBlocked = true;
      }
    }
  } catch (_) {/* never crash startup on cache IO */}

  // §16.2 (V3.1.117): no runZonedGuarded — runApp in a custom zone competes
  // with the root-zone binding, and PlatformDispatcher.onError (above) is the
  // single global sink for uncaught async errors (+ FlutterError.onError for
  // framework errors).
  runApp(CleonaApp(
    hardBlocked: hardBlocked,
    blockManifest: blockManifest,
  ));
}

/// Reads the manifest cache written by [CleonaService._checkForUpdates].
/// Synchronous to keep startup-before-runApp simple — file is small (<2 KB).
/// Returns null if the file does not exist or is unreadable.
String? _readCachedManifestSync() {
  try {
    final file = File('${AppPaths.dataDir}${Platform.pathSeparator}update_manifest_cache.json');
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  } catch (_) {
    return null;
  }
}

/// Appends a crash entry to `~/.cleona/crash.log`. Swallows all IO errors
/// so the handler itself never crashes.
void _logCrash(String source, Object error, StackTrace? stack) {
  final entry = '${DateTime.now().toIso8601String()} [$source] $error\n$stack\n\n';
  try {
    final dir = Directory('${AppPaths.home}/.cleona');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/crash.log').writeAsStringSync(
      entry, mode: FileMode.append, flush: true);
  } catch (_) {/* never crash the crash handler */}
  if (Platform.isIOS) {
    // Write to CLogger's iOS mirror path (Documents/, AFC-accessible).
    // Falls back to bundle-derived paths if mirror isn't set yet (early crash).
    final candidates = <String>[
      if (CLogger.iosMirrorPath != null)
        '${CLogger.iosMirrorPath}/crash.log',
      if (Platform.environment['HOME'] != null)
        '${Platform.environment['HOME']}/Documents/crash.log',
      '/tmp/crash.log',
    ];
    for (final path in candidates) {
      try {
        final dir = Directory(path).parent;
        if (!dir.existsSync()) dir.createSync(recursive: true);
        File(path).writeAsStringSync(entry, mode: FileMode.append, flush: true);
        break;
      } catch (_) {}
    }
  }
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

class CleonaApp extends StatefulWidget {
  /// Sec H-5 (V3.1.72) / T13: when true, render [UpdateRequiredScreen] as
  /// the initial route. Determined synchronously in [main] from the cached
  /// signed update manifest.
  final bool hardBlocked;
  final UpdateManifest? blockManifest;

  const CleonaApp({
    super.key,
    this.hardBlocked = false,
    this.blockManifest,
  });

  @override
  State<CleonaApp> createState() => _CleonaAppState();
}

class _CleonaAppState extends State<CleonaApp> {
  late bool _showHardBlock = widget.hardBlocked && widget.blockManifest != null;

  // B-30: ONE stable AppLocale for the whole app lifetime. Previously a fresh
  // AppLocale() was created on every build() and handed to
  // ChangeNotifierProvider.value, so Consumer2 watched the newest instance while
  // CleonaAppState._appLocale (assigned once in the create-lambda) stayed pinned
  // to the first instance — IPC switch_language then notified an orphaned object
  // and the UI never rebuilt. Calling load() once in initState also restores a
  // persisted locale on startup (it was needlessly re-run on every rebuild before).
  final AppLocale _appLocale = AppLocale();

  @override
  void initState() {
    super.initState();
    _appLocale.load();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final state = CleonaAppState();
          state._appLocale = _appLocale;
          // Sec H-5 / T13: if the user already chose "skip into limited" on
          // this session before the appState was constructed (impossible in
          // the current flow — appState is created the first build — but
          // guards against future reordering), re-apply.
          if (!_showHardBlock && widget.hardBlocked) {
            state._sessionReducedMode = true;
          }
          state._boot();
          // Bug #U16: Android Share-Sheet-Empfang. Kontext + Service werden
          // lazy beim Share-Event ausgewertet (Identity-Wechsel andert Service).
          ShareReceiver.init(
            contextProvider: () => navigatorKey.currentContext!,
            serviceProvider: () => state.service,
          );
          return state;
        }),
        ChangeNotifierProvider.value(value: _appLocale),
      ],
      child: Consumer2<CleonaAppState, AppLocale>(
        builder: (context, appState, locale, _) {
          final activeSkin = appState.activeSkin;
          final Widget home;
          if (_showHardBlock && widget.blockManifest != null) {
            // Sec H-5 / T13 splash. Skipping flips the flag locally and
            // marks reducedMode on every per-identity service via appState.
            home = UpdateRequiredScreen(
              downloadUrl: widget.blockManifest!.downloadUrl,
              reasonI18nKey: widget.blockManifest!.minRequiredReason
                  ?? 'update_required_kem_v2',
              onSkipLimited: () {
                appState.setReducedModeSession(true);
                setState(() {
                  _showHardBlock = false;
                });
              },
            );
          } else if (appState.isInitialized) {
            home = const HomeScreen();
          } else if (appState.hasProfile) {
            home = _LoadingScreen(error: appState._initError);
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
              actions: <Type, Action<Intent>>{
                ...WidgetsApp.defaultActions,
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    navigatorKey.currentState?.maybePop();
                    return null;
                  },
                ),
              },
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
  const _LoadingScreen({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                error != null ? Icons.error_outline : Icons.lock_outline,
                size: 64,
                color: error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('Cleona Chat',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 16),
              if (error == null) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SelectableText(
                    'Init failed:\n$error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error),
                  ),
                )
              else
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
  static CleonaAppState? _instance;

  ICleonaService? _service;
  IpcClient? _ipcClient;
  bool _isInitialized = false;
  bool _hasProfile = false;
  String? _initError;

  /// § F-B: 1:1 video call frame delivery. Registered by the active
  /// [CallScreen] (didChangeDependencies/dispose) rather than routed through
  /// [notifyListeners] — frames arrive at ~15-30fps and a full ChangeNotifier
  /// rebuild of the whole widget tree per frame would be wasteful. Only
  /// wired for in-process platforms (Android/iOS/macOS-no-daemon); Linux/
  /// Windows run the daemon in a separate process with no frame-streaming
  /// IPC (out of scope for this pass — see CleonaAppState._wireServiceCallbacks).
  void Function(ui.Image image)? onRemoteVideoFrame;
  void Function(ui.Image image)? onLocalVideoFrame;

  /// Non-null while a second (or later) identity is being created.
  /// Set before PQ keygen starts so the IdentityTabBar can show
  /// a "creating..." placeholder chip with a spinner immediately.
  String? _creatingIdentityName;
  String? get creatingIdentityName => _creatingIdentityName;
  /// Sec H-5 (V3.1.72) / T13: true after the user clicked "open anyway
  /// (limited)" on the [UpdateRequiredScreen]. Per-session, not persisted.
  /// Propagated to every concrete [CleonaService] (in-process) and,
  /// on Desktop, pushed to the daemon via [IpcClient.setReducedModeSession]
  /// (Folge-Task 2026-04-26). See sec-h5 §8.2.
  bool _sessionReducedMode = false;

  /// Toggle reducedMode for this GUI session. Sets the flag on every
  /// concrete [CleonaService] currently known to this state (in-process
  /// multi-identity), pushes it to the daemon over IPC (Desktop), and
  /// stores the value so future services created via [_boot] /
  /// identity-add inherit it.
  void setReducedModeSession(bool v) {
    _sessionReducedMode = v;
    for (final service in _inProcessServices.values) {
      service.reducedMode = v;
    }
    if (_service is CleonaService) {
      (_service as CleonaService).reducedMode = v;
    }
    // Desktop IPC path: push to daemon (sets all per-identity services
    // there) and refresh listeners again once the wire round-trip lands so
    // the [ReducedModeBanner] reflects the daemon's mirrored flag.
    final ipc = _ipcClient;
    if (ipc != null) {
      ipc.setReducedModeSession(v).then((_) => notifyListeners());
    }
    notifyListeners();
  }
  ThemeMode _themeMode = ThemeMode.system;
  Timer? _showTriggerTimer;
  Timer? _heartbeatTimer;
  DateTime? _heartbeatLastAt;
  int _heartbeatTick = 0;
  AppLocale? _appLocale;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<ConnectivityResult> _connectivityResults = [];
  String _lastNotificationText = '';

  /// Buffered incoming 1:1/group call when the Navigator is not yet attached.
  /// Drained via [WidgetsBinding.instance.addPostFrameCallback] once the
  /// [MaterialApp] has rendered its first frame and [navigatorKey.currentState]
  /// is non-null. Fixes the Linux-Desktop race where an early `incoming_call`
  /// event arrived before `runApp` finished building.
  CallInfo? _pendingIncomingCall;
  GroupCallInfo? _pendingIncomingGroupCall;

  /// Current connectivity results from connectivity_plus.
  /// Used by HomeScreen to display connection status icon.
  List<ConnectivityResult> get connectivityResults => _connectivityResults;

  /// Number of peers with confirmed bidirectional UDP contact this session.
  /// Combines OS connectivity with actual P2P reachability for the status icon.
  int get confirmedPeerCount {
    // In-process: read directly from node
    if (_inProcessNode != null) return _inProcessNode!.confirmedPeerIds.length;
    // Desktop daemon: IPC client carries confirmedPeerCount
    if (_ipcClient != null) return _ipcClient!.confirmedPeerCount;
    return 0;
  }

  /// True when UPnP/PCP successfully opened an inbound port mapping — used by
  /// the connection-status icon to split "strong (Hulk)" from "good (normal man)".
  bool get hasPortMapping {
    if (_inProcessNode != null) return _inProcessNode!.natTraversal.hasPortMapping;
    if (_ipcClient != null) return _ipcClient!.hasPortMapping;
    return false;
  }

  /// Whether transport is using mobile fallback (WiFi broken, mobile works).
  /// When true, icon should show mobile even if OS reports WiFi.
  bool _mobileFallbackActive = false;
  bool get isMobileFallbackActive {
    // In-process: read from node's transport
    if (_inProcessNode != null) return _inProcessNode!.transport.isMobileFallbackActive;
    // Desktop daemon: IPC client carries the state
    if (_ipcClient != null) return _ipcClient!.mobileFallbackActive;
    return _mobileFallbackActive;
  }

  // System channel crash reporting (§9.5)
  final List<(Object, StackTrace)> _pendingCrashes = [];
  bool _crashDialogShowing = false;

  // In-process multi-identity state (Android, iOS, macOS-no-daemon)
  CleonaNode? _inProcessNode;
  final Map<String, CleonaService> _inProcessServices = {};
  final Map<String, IdentityContext> _inProcessContexts = {};

  ICleonaService? get service => _service;
  IpcClient? get ipcClient => _ipcClient;

  /// Refreshes UI after identity changes.
  void refresh() => notifyListeners();

  /// Called from the global error handlers to queue a crash for reporting.
  /// If a CleonaService is available and the UI is ready, shows the dialog
  /// immediately; otherwise queues it for later processing.
  void handleCrash(Object error, StackTrace stack) {
    final service = _activeCleonaService;
    if (service == null) {
      _pendingCrashes.add((error, stack));
      return;
    }
    _scheduleCrashDialog(service, error, stack);
  }

  CleonaService? get _activeCleonaService {
    if (_inProcessServices.isNotEmpty) {
      return _inProcessServices.values.first;
    }
    return null;
  }

  void _processPendingCrashes() {
    if (_pendingCrashes.isEmpty) return;
    final service = _activeCleonaService;
    if (service == null) return;
    final pending = List<(Object, StackTrace)>.from(_pendingCrashes);
    _pendingCrashes.clear();
    for (final (error, stack) in pending) {
      _scheduleCrashDialog(service, error, stack);
    }
  }

  void _scheduleCrashDialog(CleonaService service, Object error, StackTrace stack) {
    if (_crashDialogShowing) return;
    final reporter = service.crashReporter;
    final report = reporter.buildReport(error, stack);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      _crashDialogShowing = true;
      showCrashReportDialog(
        context: ctx,
        reporter: reporter,
        report: report,
      ).then((result) async {
        _crashDialogShowing = false;
        switch (result.action) {
          case CrashDialogResult.publish:
            await reporter.publishReport(report);
          case CrashDialogResult.dismissKnown:
            await reporter.publishDuplicate(report);
          case CrashDialogResult.navigateToReport:
            await reporter.publishDuplicate(report);
            if (result.existingPostId != null && navigatorKey.currentContext != null) {
              // Navigate to the Bug Log channel
              _navigateToChannel(
                  navigatorKey.currentContext!, result.existingPostId!);
            }
          case CrashDialogResult.discard:
          case CrashDialogResult.rateLimitAck:
            break;
        }
      });
    });
  }

  void _navigateToChannel(BuildContext context, String postId) {
    final channelIdHex = sys_ch.SystemChannels.bugLogChannelIdHex;
    final service = _activeCleonaService;
    if (service != null && service.conversations.containsKey(channelIdHex)) {
      final conv = service.conversations[channelIdHex]!;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: channelIdHex,
            displayName: conv.displayName,
            isChannel: true,
          ),
        ),
      );
    }
  }

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
    final isResumed = state == AppLifecycleState.resumed;
    // Propagate foreground state to every per-identity service so that
    // _shouldSuppressForegroundNotification can gate sound/vibrate/banner
    // for the conversation that ChatScreen has registered as active.
    for (final service in _inProcessServices.values) {
      service.setAppResumed(isResumed);
    }
    _service?.setAppResumed(isResumed);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      for (final service in _inProcessServices.values) {
        service.saveState();
      }
      if (_service is CleonaService) {
        (_service as CleonaService).saveState();
      }
      if (_inProcessNode != null && _inProcessNode!.isRunning) {
        _inProcessNode!.saveNetworkState();
      }
      // S12.5: Schedule iOS background fetch when going to background.
      // The BGTaskScheduler will wake the app periodically (earliest 15 min)
      // to retrieve pending P2P messages.
      if (Platform.isIOS) {
        IosBackgroundFetch.scheduleBackgroundFetch();
      }
    } else if (isResumed) {
      // After Doze/background: network may have changed, re-discover peers.
      // Protected seed peers survived pruning — now ping them to reconnect.
      // Guard: node must be running (transport/natTraversal are late-initialized).
      if (_inProcessNode != null && _inProcessNode!.isRunning) {
        _inProcessNode!.onNetworkChanged();
        _queryPublicIp();
      }
    }
  }

  /// Discover own public IPv4 + IPv6 via ipify (§27 — Android has no daemon).
  /// [force]: skip the hasPublicIp guard (network change — IP may have rotated).
  void _queryPublicIp({bool force = false}) {
    final node = _inProcessNode;
    if (node == null) return;
    // Delay: 3s for network-change (fast re-query), 5s for app-resume (stabilize)
    final delay = force ? 3 : 5;
    Timer(Duration(seconds: delay), () async {
      if (!node.isRunning) return;
      if (!force && node.natTraversal.hasPublicIp) return;
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
          // §4.7: one-shot inbound probe per join to detect carrier IPv6 filter.
          node.probeIpv6InboundIfNeeded();
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
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    _restoreThemeMode();
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
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
    } catch (_) {
      // Do NOT delete the lock file here — the daemon holds an flock on
      // the inode. Deleting it would break the single-instance guarantee.
      // A temporarily unreadable lock file is not evidence that no daemon
      // is running. On Windows the live daemon holds cleona.lock with a
      // MANDATORY exclusive lock (LockFileEx) that also blocks READS, so
      // readAsStringSync throws for the ENTIRE daemon lifetime (on Linux
      // flock is advisory → the read succeeds). Returning false here made
      // the GUI think no daemon exists → it spawned a SECOND daemon that
      // then died on the machine-global lock, leaving no cleona.port and
      // the GUI stuck on "Verbinde mit Dienst". Fall back to the readable
      // cleona.pid (same source _isDaemonServiceRunning uses); if that is
      // unreadable too, an existing-but-locked lock file is itself proof a
      // daemon owns it → report alive so the GUI SIGNALS it (cleona.start)
      // instead of spawning a duplicate.
      try {
        final pidFile = File('$_baseDir/cleona.pid');
        if (pidFile.existsSync()) {
          return _isProcessAlive(int.parse(pidFile.readAsStringSync().trim()));
        }
      } catch (_) {}
      return true;
    }
  }

  Future<bool> _signalDaemonToStart() async {
    File('$_baseDir/cleona.start').writeAsStringSync('start');
    return _waitForSocketConnectable(maxWaitMs: 15000);
  }

  Future<bool> _ensureDaemonRunning() async {
    // iOS: always in-process, never a daemon. Skip all Process.runSync
    // calls (kill, tasklist) which throw UnsupportedError in the iOS sandbox.
    if (Platform.isIOS) return false;

    // Tray contract: daemon MUST have DISPLAY so tray icon is visible.
    // If a daemon is alive but has no DISPLAY → replace it so the tray works.
    if (_isDaemonProcessAlive()) {
      if (_isDaemonServiceRunning() && _daemonHasDisplay()) {
        return true;
      }
      if (_isDaemonServiceRunning() && !_daemonHasDisplay()) {
        _killExistingDaemon();
        // Fall through to spawn a new daemon with GUI's DISPLAY
      } else if (_daemonHasDisplay()) {
        return _signalDaemonToStart();
      } else {
        _killExistingDaemon();
      }
    }

    // No daemon process (or just killed) — clean up stale IPC artifacts
    // from a crashed/killed daemon before spawning. The daemon's own guards
    // handle this too, but cleaning here avoids races where the GUI's
    // _waitForSocketConnectable sees the stale socket and tries to connect
    // before the daemon replaces it.
    try { File('$_baseDir/cleona.sock').deleteSync(); } catch (_) {}
    try { File('$_baseDir/cleona.port').deleteSync(); } catch (_) {}
    try { File('$_baseDir/cleona.pid').deleteSync(); } catch (_) {}

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

  /// Kill existing daemon and wait for it to exit.
  /// IMPORTANT: Do NOT delete cleona.lock — the flock is inode-based.
  /// Deleting the file creates a new inode, breaking the single-instance
  /// guarantee: the old daemon still holds the lock on the deleted inode
  /// while a new daemon locks the newly-created file. This race condition
  /// allowed multiple daemon instances (observed 2026-05-16).
  void _killExistingDaemon() {
    final lockFile = File('$_baseDir/cleona.lock');
    try {
      final p = int.parse(lockFile.readAsStringSync().trim());
      if (Platform.isWindows) {
        Process.runSync('taskkill', ['/PID', '$p', '/F']);
      } else {
        Process.runSync('kill', ['-TERM', '$p']);
        // Wait up to 3s for graceful shutdown before SIGKILL
        for (var i = 0; i < 6; i++) {
          sleep(const Duration(milliseconds: 500));
          if (Process.runSync('kill', ['-0', '$p']).exitCode != 0) break;
        }
        if (Process.runSync('kill', ['-0', '$p']).exitCode == 0) {
          Process.runSync('kill', ['-9', '$p']);
          sleep(const Duration(milliseconds: 200));
        }
      }
    } catch (_) {}
    // Clean up IPC artifacts (socket/port/pid) but NOT the lock file.
    // The lock file is released by the kernel when the daemon's fd closes
    // (process exit), making it safe for the next daemon to acquire.
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
      // In-process multi-identity: notify node ONCE + service-side cleanup per
      // identity (mailbox poll, identity-publisher). Avoid the N+1 node-reset
      // multiplication — node-reset is global, not per-service.
      if (_inProcessNode != null) {
        _inProcessNode!.onNetworkChanged();
        for (final service in _inProcessServices.values) {
          service.onNetworkChanged(triggerNodeReset: false);
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
        ipcClient.onIncomingGroupCall = (call) => _showIncomingGroupCallScreen(call);
        ipcClient.onGroupCallStarted = (_) => notifyListeners();
        ipcClient.onGroupCallEnded = (_) => notifyListeners();
        ipcClient.onGuiAction = (data) => _handleGuiAction(data);
        ipcClient.onDaemonDied = () {
          // GUI and daemon act as one unit — if daemon truly dies (lock file
          // missing or PID gone), GUI exits. Next GUI launch will start a
          // fresh daemon via _ensureDaemonRunning().
          debugPrint('[main] Daemon process gone — exiting GUI');
          exit(0);
        };
        ipcClient.onIpcStalled = () {
          // Daemon process is still alive but IPC retries (3× short backoff)
          // were exhausted — typically a daemon mid-restart or PQ keygen
          // taking longer than 3.5 s. Don't exit. Tear the dead client down
          // and re-arm the longer-window connect retry; the next successful
          // connect will rebuild the IPC bridge in place.
          debugPrint('[main] IPC stalled (daemon alive) — re-arming retry');
          _ipcClient = null;
          _service = null;
          _isInitialized = false;
          notifyListeners();
          _scheduleRetryConnect();
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
        // Precache the active skin's hero image after the first home-screen frame.
        final activeIdForPrecache = IdentityManager().getActiveIdentity();
        _scheduleSkinPrecache(activeIdForPrecache?.skinId);
        return;
      }
    }

    // Linux/Windows desktop: daemon spawn failed or IPC connect failed.
    // Don't silently hang — re-arm the retry loop so the GUI recovers
    // when the daemon comes up (e.g. after slow PQ keygen or a transient
    // startup crash).
    if (Platform.isLinux || Platform.isWindows) {
      debugPrint('[main] Daemon not reachable — scheduling retry connect');
      _scheduleRetryConnect();
      return;
    }

    // Mobile + macOS-no-daemon: start node in-process (the app IS the node).
    // On Android/iOS this is always the case. On macOS it happens when no
    // daemon binary is found (CI integration test, dev without daemon build).
    // Same multi-identity model as the Linux daemon: one node, all identities active.
    // IMPORTANT: Defer heavy work so the loading screen renders first.
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      // Signal that we have a profile (shows loading screen immediately)
      notifyListeners();
      // Schedule heavy init after the current frame completes
      Future(() async {
        try {
          await _initInProcess();
        } catch (e, stack) {
          debugPrint('[main] _initInProcess FAILED: $e\n$stack');
          _logCrash('initInProcess', e, stack);
          _initError = '$e\n\nbaseDir: $_baseDir\n\n$stack';
          notifyListeners();
        }
      });
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

  // ── In-process init (Android, iOS, macOS — deferred from initialize()) ──

  Future<void> _initInProcess() async {
    // Ensure base directory exists (iOS: path_provider container may not
    // have .cleona/ yet on first post-install run).
    final baseDirObj = Directory(_baseDir);
    if (!baseDirObj.existsSync()) {
      baseDirObj.createSync(recursive: true);
    }

    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    if (identities.isEmpty) return;

    // iOS: the data container path is stable across reinstalls, but the
    // profileDir stored in identities.json is an absolute path. If the
    // app's base dir was relocated (e.g. after an AppPaths fix deployment),
    // rebase all profileDirs to the current _baseDir.
    if (Platform.isIOS || Platform.isAndroid) {
      var needsSave = false;
      for (final id in identities) {
        if (!Directory(id.profileDir).existsSync()) {
          final relative = id.profileDir.split('/.cleona/').last;
          final rebased = '$_baseDir/$relative';
          if (Directory(rebased).existsSync()) {
            debugPrint('[main] Rebasing profileDir: ${id.profileDir} -> $rebased');
            id.profileDir = rebased;
            needsSave = true;
          } else {
            debugPrint('[main] profileDir missing, recreating: $rebased');
            Directory(rebased).createSync(recursive: true);
            id.profileDir = rebased;
            needsSave = true;
          }
        }
      }
      if (needsSave) mgr.saveIdentities(identities);
    }

    // Create identity contexts (shared sequence — S106 fix)
    final masterSeed = mgr.loadMasterSeed();
    final firstId = identities.first;

    final primaryCtx = await IdentityContext.createFromIdentity(
      identity: firstId,
      baseDir: _baseDir,
      masterSeed: masterSeed,
    );
    _inProcessContexts[primaryCtx.userIdHex] = primaryCtx;

    for (var i = 1; i < identities.length; i++) {
      final ctx = await IdentityContext.createFromIdentity(
        identity: identities[i],
        baseDir: _baseDir,
        masterSeed: masterSeed,
      );
      _inProcessContexts[ctx.userIdHex] = ctx;
    }

    // ONE shared node for all identities
    final node = CleonaNode(
      profileDir: _baseDir,
      port: firstId.port,
      networkChannel: NetworkSecret.channel.name,
    );
    node.primaryIdentity = primaryCtx;
    _inProcessNode = node;

    // Re-query public IP on any network change (Android has no daemon-side
    // ip-monitor — connectivity_plus fires onNetworkChanged but the ipify
    // re-query was missing, so Mobilfunk/CGNAT IP changes went unnoticed).
    node.onNetworkChangeDetected = () {
      _queryPublicIp(force: true);
    };

    // Register ALL identities with the node
    for (final ctx in _inProcessContexts.values) {
      node.registerIdentity(ctx);
    }

    // Notify GUI when peer addresses change
    node.onPeersChanged = () {
      for (final service in _inProcessServices.values) {
        service.onStateChanged?.call();
      }
    };

    // S12.5: Initialize iOS background fetch MethodChannel handler.
    // Must happen before startQuick so the native side can call into Dart
    // during background wakeups.
    if (Platform.isIOS) {
      IosBackgroundFetch.init();
    }

    // Start node (UDP listener active → messages can arrive)
    await node.startQuick();

    // Mobile fallback state → icon update (AFTER startQuick — transport is late-initialized)
    node.transport.onMobileFallbackChanged = (active) {
      _mobileFallbackActive = active;
      notifyListeners();
    };

    // Create and start a CleonaService for EACH identity
    for (final ctx in _inProcessContexts.values) {
      final service = CleonaService(
        identity: ctx,
        node: node,
        displayName: ctx.displayName,
      );
      // Sec H-5 / T13: inherit splash decision.
      if (_sessionReducedMode) service.reducedMode = true;
      _wireServiceCallbacks(service);
      await service.startService();
      _inProcessServices[ctx.userIdHex] = service;
      debugPrint('[main] Service gestartet: ${ctx.displayName} (${ctx.userIdHex.substring(0, 16)}...)');
    }

    // Process any crashes that occurred before services were ready (§9.5)
    _processPendingCrashes();

    // §2.4 receiver step [9] — multi-identity KEM-Try-Loop for in-process
    // mode (Android/iOS/macOS). Mirrors service_daemon.dart wiring.
    final serviceRecency = <String>[];
    node.onApplicationFramePayload = (packet, from, port, snapshot) async {
      if (_inProcessServices.isEmpty) return;
      final seen = <String>{};
      final ordered = <CleonaService>[];
      for (final id in serviceRecency) {
        final s = _inProcessServices[id];
        if (s != null && seen.add(id)) ordered.add(s);
      }
      for (final entry in _inProcessServices.entries) {
        if (seen.add(entry.key)) ordered.add(entry.value);
      }
      for (final service in ordered) {
        final outcome = await service.handleIncomingApplicationPacket(
            packet, from, port, snapshot);
        if (outcome == AppFrameDispatchOutcome.delivered) {
          serviceRecency.remove(service.nodeIdHex);
          serviceRecency.insert(0, service.nodeIdHex);
          return;
        }
        if (outcome == AppFrameDispatchOutcome.droppedAfterDecap) return;
      }
    };

    node.onInfrastructureFramePayload = (frame, senderDeviceId, from, port, snapshot) {
      final mt = frame.messageType;
      final isServiceRouted =
          mt == proto.MessageTypeV3.MTV3_CONTACT_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_RESTORE_BROADCAST ||
          mt == proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_SHARE_STORE ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_GUARDIAN_RESTORE_RESPONSE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_STORE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_DELETE ||
          mt == proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK ||
          mt == proto.MessageTypeV3.MTV3_PEER_STORE ||
          mt == proto.MessageTypeV3.MTV3_PEER_STORE_ACK ||
          mt == proto.MessageTypeV3.MTV3_PEER_RETRIEVE ||
          mt == proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE ||
          mt == proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE ||
          // §8.1.1 rev3: Deferred Key Exchange (step 1b)
          mt == proto.MessageTypeV3.MTV3_DEVICE_KEM_REQUEST ||
          mt == proto.MessageTypeV3.MTV3_DEVICE_KEM_OFFER ||
          // §9.5.7 (S119 D1): system-channel record gossip
          mt == proto.MessageTypeV3.MTV3_SYSCHAN_DIGEST ||
          mt == proto.MessageTypeV3.MTV3_SYSCHAN_SUMMARY ||
          mt == proto.MessageTypeV3.MTV3_SYSCHAN_WANT ||
          mt == proto.MessageTypeV3.MTV3_SYSCHAN_PUSH;
      if (!isServiceRouted) return;
      final deviceIdBytes = Uint8List.fromList(frame.recipientDeviceId);
      final identities = node.identitiesForDevice(deviceIdBytes).toList();
      if (identities.isEmpty) return;
      for (final id in identities) {
        final service = _inProcessServices[id.userIdHex];
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
          case proto.MessageTypeV3.MTV3_FRAGMENT_STORE_ACK:
            // S123 Erasure-F1: resolve the sender-side per-fragment-index
            // ACK wait (see CleonaService._distributeErasureFragments) and
            // drive the proactive-push retry-cancel path.
            service.handleIncomingFragmentStoreAckInfra(frame, senderDeviceId);
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
            // §5.5 (S121 F1): resolve the sender-side ACK wait — the ACK
            // carries accepted=false when the storage peer rejected the
            // store (recipient not its contact, budget, rate limit).
            service.handleIncomingPeerStoreAckInfra(frame, senderDeviceId);
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
          case proto.MessageTypeV3.MTV3_SYSCHAN_DIGEST:
            service.handleIncomingSysChanDigestInfra(frame, senderDeviceId);
            break;
          case proto.MessageTypeV3.MTV3_SYSCHAN_SUMMARY:
            service.handleIncomingSysChanSummaryInfra(frame, senderDeviceId);
            break;
          case proto.MessageTypeV3.MTV3_SYSCHAN_WANT:
            service.handleIncomingSysChanWantInfra(frame, senderDeviceId);
            break;
          case proto.MessageTypeV3.MTV3_SYSCHAN_PUSH:
            service.handleIncomingSysChanPushInfra(frame, senderDeviceId);
            break;
          default:
            break;
        }
      }
    };

    // Save updated nodeIdHex values
    mgr.saveIdentities(identities);

    // Set active service (based on IdentityManager selection)
    final activeId = IdentityManager().getActiveIdentity();
    final activeHex = activeId?.nodeIdHex ?? primaryCtx.userIdHex;
    _service = _inProcessServices[activeHex] ?? _inProcessServices.values.first;

    _isInitialized = true;
    _startConnectivityMonitor();
    _queryPublicIp(); // §27: discover own public IPv4/IPv6 for external reachability
    navigatorKey = GlobalKey<NavigatorState>();
    notifyListeners();
    // Precache the active skin's hero image after the first home-screen frame.
    _scheduleSkinPrecache(activeId?.skinId);

    // In-process heartbeat — liveness diagnostics for the main Dart
    // isolate. On Linux/Windows the equivalent lives in
    // lib/service_daemon.dart (commit a13b490); on mobile/macOS the node runs
    // in-process in the UI isolate, so we add the same Timer.periodic(5s)
    // drift-detector here. Logs to `[heartbeat]` via the primary service's
    // CLogger so entries land in the identity's tages-log AND in logcat
    // (INFO level not filtered). Relevant for #U17 Hotel-WLAN-Crashes and
    // any future ANR — the last heartbeat-tick timestamp narrows the
    // freeze-window from 60s status-beacon to ~5s.
    _heartbeatLastAt = DateTime.now();
    if (Platform.isAndroid) {
      try { File('$_baseDir/.dart-heartbeat').writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}'); } catch (_) {}
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      // §16.2 (V3.1.117): stamp unconditionally on every tick — the file
      // attests that the Dart isolate is alive, not that a service is
      // running. The former isRunning guard starved the Kotlin watchdog
      // during degraded states and fed the kill loop (Problem 10).
      if (Platform.isAndroid) {
        try { File('$_baseDir/.dart-heartbeat').writeAsStringSync('${now.millisecondsSinceEpoch}'); } catch (_) {}
      }
      final last = _heartbeatLastAt;
      _heartbeatLastAt = now;
      _heartbeatTick++;
      final dtMs = last == null ? 0 : now.difference(last).inMilliseconds;
      // Expected dt ≈ 5000ms; anything >6500ms indicates main-loop drift
      // (GC pause, blocking FFI call, expensive async-gap on the isolate).
      final msg = 'tick=$_heartbeatTick dt=${dtMs}ms';
      if (dtMs > 6500) {
        debugPrint('[heartbeat] $msg (DRIFT — main loop delayed ${dtMs - 5000}ms)');
      } else if (_heartbeatTick % 12 == 0) {
        // Every 60s: an INFO-level beat marker so filtered log viewers
        // still see the app is alive.
        debugPrint('[heartbeat] $msg');
      }
    });
  }

  // ── Incoming Call ──────────────────────────────────────────────

  void _showIncomingCallScreen(CallInfo call) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      // Navigator not attached yet (early event before first frame). Buffer
      // the call and retry after the post-frame callback, matching the
      // [_scheduleSkinPrecache] pattern.
      _pendingIncomingCall = call;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingIncomingCall;
        if (pending != null) {
          _pendingIncomingCall = null;
          _showIncomingCallScreen(pending);
        }
      });
      return;
    }
    _pendingIncomingCall = null;

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

  /// Shows the incoming/outgoing group call screen. Buffers like the 1:1 path
  /// so a `group_call_started` event that races with the first frame is not lost.
  void _showIncomingGroupCallScreen(GroupCallInfo call) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pendingIncomingGroupCall = call;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingIncomingGroupCall;
        if (pending != null) {
          _pendingIncomingGroupCall = null;
          _showIncomingGroupCallScreen(pending);
        }
      });
      return;
    }
    _pendingIncomingGroupCall = null;

    final groupName = _service?.groups[call.groupIdHex]?.name ??
        (call.groupIdHex.length >= 8
            ? call.groupIdHex.substring(0, 8)
            : call.groupIdHex);

    nav.push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: this,
          child: GroupCallScreen(
            callInfo: call,
            groupName: groupName,
          ),
        ),
      ),
    );
  }

  // ── Multi-Identity ─────────────────────────────────────────────

  /// Switches to another identity — IMMEDIATELY via IPC or in-process.
  Future<void> switchIdentity(Identity identity) async {
    debugPrint('[switchIdentity] → ${identity.displayName} '
        'nodeIdHex=${identity.nodeIdHex?.substring(0, 8) ?? "NULL"}');
    if (_ipcClient != null && identity.nodeIdHex != null) {
      final ok = await _ipcClient!.switchIdentity(identity.nodeIdHex!);
      debugPrint('[switchIdentity] IPC result=$ok '
          'service.nodeIdHex=${_ipcClient!.nodeIdHex.substring(0, 8)}');
      if (ok) {
        IdentityManager().setActiveIdentity(identity);
        notifyListeners();
        _scheduleSkinPrecache(identity.skinId);
        return;
      }
      debugPrint('[switchIdentity] WARNING: IPC switch FAILED for '
          '${identity.displayName} — service stays on previous identity!');
    }

    // In-process: switch to the right service
    if (_inProcessServices.isNotEmpty && identity.nodeIdHex != null) {
      final service = _inProcessServices[identity.nodeIdHex!];
      if (service != null) {
        _service = service;
        debugPrint('[switchIdentity] in-process OK: ${identity.displayName}');
        IdentityManager().setActiveIdentity(identity);
        notifyListeners();
        _scheduleSkinPrecache(identity.skinId);
        return;
      }
      debugPrint('[switchIdentity] WARNING: in-process switch FAILED — '
          'nodeIdHex ${identity.nodeIdHex!.substring(0, 8)} not in '
          '[${_inProcessServices.keys.map((k) => k.substring(0, 8)).join(", ")}]');
    }

    debugPrint('[switchIdentity] FALLTHROUGH: setActiveIdentity without '
        'service switch — ContactSeed will use WRONG identity keys!');
    IdentityManager().setActiveIdentity(identity);
    notifyListeners();
    _scheduleSkinPrecache(identity.skinId);
  }

  /// Schedules a [precacheImage] call for the hero asset of the skin identified
  /// by [skinId] after the current frame completes.  Using a post-frame callback
  /// ensures that [navigatorKey.currentContext] is attached (the Navigator is
  /// part of [MaterialApp] which rebuilds after [notifyListeners]).
  void _scheduleSkinPrecache(String? skinId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      _precacheSkinHero(ctx, Skins.byId(skinId));
    });
  }

  /// Preloads the hero [AssetImage] for [skin] into Flutter's image cache so
  /// that the first paint after a skin switch does not stall on I/O.
  /// Failures are non-fatal — the [SkinBackgroundImage] fallback gradient
  /// renders correctly without the cached asset.
  Future<void> _precacheSkinHero(BuildContext context, Skin skin) async {
    final path = skin.heroAssetPath;
    if (path == null) return;
    try {
      await precacheImage(AssetImage(path), context);
    } catch (e) {
      debugPrint('[skin] precacheImage failed for $path: $e');
    }
  }

  /// Sum of unreadCount across every in-process identity service. Drives the
  /// system Launcher-Badge (#U3 — single counter for a multi-identity daemon).
  void _updateAndroidBadge() {
    if (!Platform.isAndroid) return;
    var total = 0;
    for (final svc in _inProcessServices.values) {
      for (final conv in svc.conversations.values) {
        total += conv.unreadCount;
      }
    }
    const channel = MethodChannel('chat.cleona/notification');
    channel.invokeMethod('updateBadge', {'count': total});
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
    service.onIncomingGroupCall = (call) => _showIncomingGroupCallScreen(call);
    service.onGroupCallStarted = (_) => notifyListeners();
    service.onGroupCallEnded = (_) => notifyListeners();

    // § F-B: 1:1 + group video engine factory. Only wired here — for
    // in-process services (Android/iOS/macOS-no-daemon) — because it needs
    // dart:ui (VideoEngine) and, on Android, package:flutter/services.dart
    // (VideoCaptureAndroid MethodChannel), neither of which call_service.dart
    // may import (it's part of the headless daemon's dependency graph via
    // CleonaService — see service_daemon.dart / headless.dart). Linux/
    // Windows run CleonaService inside the separate daemon process, which
    // never calls _wireServiceCallbacks, so createVideoEngine stays null
    // there — CallService already degrades to audio-only when it is.
    service.createVideoEngine = (sharedSecret, onFrame) =>
        _createVideoEngine(sharedSecret, onFrame);

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

      // Badge count: sum across ALL identities, not just the one that fired.
      // The system Launcher-Badge is a single number per app, so the last-
      // writer-wins per-identity callback (#U3) showed only the firing
      // identity's count and lost the others.
      service.onBadgeCountChanged = (_) => _updateAndroidBadge();

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

      service.onPostCallNotificationAndroid = (callerName, callId) {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('showIncomingCall', {
          'callerName': callerName,
          'callId': callId,
        });
      };
      service.onCancelCallNotificationAndroid = () {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('cancelIncomingCall');
      };
    }
  }

  /// § F-B: constructs the [VideoEngine] behind [CleonaService.createVideoEngine]
  /// (used for both 1:1 and group calls — the factory signature is shared).
  /// Capture strategy per platform:
  /// - Android + iOS: no isolate. [VideoCaptureAndroid] (platform-neutral
  ///   `chat.cleona/camera` MethodChannel — CameraXHandler.kt on Android,
  ///   CameraHandler.swift on iOS; see the [VideoCaptureIOS] alias) feeds
  ///   I420 frames into the engine via [VideoEngine.feedExternalFrame]
  ///   on the main isolate.
  /// - Linux/macOS (in-process fallback): the existing isolate-based V4L2
  ///   capture stub (synthetic gray frames — not fixed in this pass).
  /// Any VpxFFI/native-lib failure degrades to audio-only (VideoEngine.start
  /// returns false; onFrame/onDecodedFrame simply never fire) — never crashes.
  dynamic _createVideoEngine(
      Uint8List sharedSecret, void Function(Uint8List) onFrame) {
    final useIsolate = !(Platform.isAndroid || Platform.isIOS);
    final engine = VideoEngine(
      sharedSecret: sharedSecret,
      useIsolateCapture: useIsolate,
    );
    engine.onVideoFrame = onFrame;
    // Ownership: whichever CallScreen is currently registered via
    // [onRemoteVideoFrame] owns disposal of the image it receives (it
    // already disposes-before-replace and disposes-on-unmount — see
    // call_screen.dart updateRemoteFrame/dispose). If no CallScreen is
    // registered (race at call start, or the user navigated away without
    // hanging up), dispose immediately here instead of leaking a GPU
    // texture per decoded frame.
    engine.onDecodedFrame = (image) {
      final cb = onRemoteVideoFrame;
      if (cb != null) {
        cb(image);
      } else {
        image.dispose();
      }
    };

    unawaited(engine.start().then((ok) {
      if (!ok) {
        debugPrint('[video] VideoEngine.start() failed (codec/native lib '
            'unavailable) — this call continues audio-only');
      }
    }));

    if (Platform.isAndroid || Platform.isIOS) {
      // Same Dart wrapper for both: the `chat.cleona/camera` MethodChannel
      // contract is identical (CameraXHandler.kt / CameraHandler.swift).
      final cam = VideoCaptureAndroid();
      cam.onFrame = (i420, w, h, rotation) {
        final (rotated, rw, rh) = VideoEngine.rotateI420(i420, w, h, rotation);
        engine.feedExternalFrame(rotated, rw, rh);
        final mirrored = VideoEngine.mirrorI420Horizontal(rotated, rw, rh);
        _updateLocalVideoPreview(mirrored, rw, rh);
      };
      engine.onSwitchCameraRequested = () => cam.switchCamera();
      engine.onCaptureStop = () {
        unawaited(cam.stop());
        cam.dispose();
      };
      unawaited(() async {
        final granted = await cam.requestPermission();
        if (!granted) {
          debugPrint('[video] CAMERA permission denied — this call sends '
              'no outgoing video (still receives/decodes the peer\'s)');
          return;
        }
        final started = await cam.start(
          width: engine.preset.width,
          height: engine.preset.height,
        );
        if (!started) {
          debugPrint('[video] Camera capture failed to start');
        }
      }());
    }

    return engine;
  }

  /// Converts a raw captured I420 frame (local preview, pre-encode) to a
  /// [ui.Image] and forwards it to the active [CallScreen] via
  /// [onLocalVideoFrame]. Mirrors [VideoEngine]'s own I420→RGBA conversion
  /// (group video / remote decode) for consistency. Same single-owner
  /// disposal contract as [_createVideoEngine]'s onDecodedFrame above.
  void _updateLocalVideoPreview(Uint8List i420, int width, int height) {
    final rgba = VideoEngine.i420ToRgba(i420, width, height);
    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888,
        (ui.Image image) {
      final cb = onLocalVideoFrame;
      if (cb != null) {
        cb(image);
      } else {
        image.dispose();
      }
    });
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

  /// Removes an identity at runtime (Android in-process).
  Future<bool> deleteIdentityAndroid(String nodeIdHex) async {
    if (_inProcessServices.length <= 1) return false;

    final service = _inProcessServices.remove(nodeIdHex);
    if (service != null) {
      await service.stop();
    }
    _inProcessContexts.remove(nodeIdHex);
    _inProcessNode?.unregisterIdentity(nodeIdHex);

    // Switch _service if we just deleted the active one
    if (_service == service && _inProcessServices.isNotEmpty) {
      _service = _inProcessServices.values.first;
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
    if (_inProcessServices.isNotEmpty) {
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

  Future<void> _handleGuiAction(Map<String, dynamic> data) async {
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
              child: SettingsScreen(service: _service!),
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
      case 'open_connection_sheet':
        if (_service != null) {
          showConnectionSheet(nav.context, _service!);
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
        // nodeIdHex — historically tests pass the identity UUID (returned
        // by listIdentities), but the lookup also has to support nodeIdHex
        // for callers that fetch via getState. Match against both.
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
          // B-33: the conversation may not be in the GUI's IpcClient cache yet
          // (a just-arrived message whose new_message event hasn't landed, or a
          // debounced refreshState). Kick an immediate refresh and poll briefly
          // rather than silently giving up — otherwise ChatScreen never opens
          // and the receiver "sees nothing".
          var conv = _service!.conversations[convId];
          if (conv == null) {
            unawaited(_ipcClient?.refreshState() ?? Future<void>.value());
            final deadline = DateTime.now().add(const Duration(seconds: 3));
            while (conv == null && DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              conv = _service?.conversations[convId];
            }
          }
          final resolved = conv;
          if (resolved == null) return;
          final navState = navigatorKey.currentState;
          if (navState == null) return;
          navState.push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: this,
              child: ChatScreen(
                conversationId: convId,
                displayName: resolved.displayName,
                isGroup: resolved.isGroup,
                isChannel: resolved.isChannel,
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

      case 'reset_donation_banner':
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('donation_banner_dismissed_until');
        notifyListeners();
        break;

      // ── NAT-Wizard test hooks (E2E gui-53, §27.9) ────────────────────
      case 'reset_nat_wizard_latch':
        // Test-only: bump the counter so HomeScreen clears its
        // `_natWizardShown` one-shot latch. Production code never emits
        // this action; it exists purely so gui-53 tests can re-trigger
        // the wizard after a prior run already showed it.
        //
        // B-34: `notifyListeners()` only *schedules* a rebuild — HomeScreen's
        // `build()` (which sets `_natWizardShown = false`) runs on the NEXT
        // frame. A following `test_force_nat_wizard_trigger` could otherwise
        // fire while the latch is still set, so the wizard would not re-show
        // (gui-53 53.01). Await the end of the next frame so that by the time
        // this handler completes, the latch has been cleared.
        _natWizardResetCounter++;
        notifyListeners();
        await WidgetsBinding.instance.endOfFrame;
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
    _creatingIdentityName = displayName;
    notifyListeners();

    try {
      if (_ipcClient != null) {
        // Linux: daemon running — create + register identity via IPC
        final newNodeIdHex = await _ipcClient!.createIdentity(displayName);
        if (newNodeIdHex != null) {
          final identities = IdentityManager().loadIdentities();
          final newIdentity = identities.where((i) => i.nodeIdHex == newNodeIdHex).firstOrNull;
          if (newIdentity != null) {
            IdentityManager().setActiveIdentity(newIdentity);
          }
          _creatingIdentityName = null;
          notifyListeners();
          return;
        }
      }

      // Android in-process: create identity and register with running node
      if (_inProcessNode != null) {
        final mgr = IdentityManager();
        final identity = await mgr.createIdentity(displayName);
        final ctx = await IdentityContext.createFromIdentity(
          identity: identity,
          baseDir: _baseDir,
          masterSeed: mgr.loadMasterSeed(),
        );

        _inProcessContexts[ctx.userIdHex] = ctx;
        _inProcessNode!.registerIdentity(ctx);

        final service = CleonaService(
          identity: ctx,
          node: _inProcessNode!,
          displayName: displayName,
        );
        // Sec H-5 / T13: inherit splash decision for newly added identities.
        if (_sessionReducedMode) service.reducedMode = true;
        _wireServiceCallbacks(service);
        await service.startService();
        _inProcessServices[ctx.userIdHex] = service;

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
        _creatingIdentityName = null;
        notifyListeners();
        return;
      }

      // Fallback: create directly (no daemon, no running node)
      final identity = await IdentityManager().createIdentity(displayName);
      _creatingIdentityName = null;
      await switchIdentity(identity);
    } catch (e) {
      _creatingIdentityName = null;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _showTriggerTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectivitySub?.cancel();
    final home = AppPaths.home;
    try { File('$home/.cleona/gui.lock').deleteSync(); } catch (_) {}
    if (_ipcClient != null) {
      // Prevent onDaemonDied from firing during intentional GUI close
      _ipcClient!.onDaemonDied = null;
      _ipcClient!.disconnect();
    } else if (_inProcessServices.isNotEmpty) {
      // In-process: stop all services and shared node
      for (final service in _inProcessServices.values) {
        service.stop();
      }
      _inProcessServices.clear();
      _inProcessContexts.clear();
      _inProcessNode?.stop();
      _inProcessNode = null;
    } else if (_service is CleonaService) {
      (_service as CleonaService).stop();
    }
    super.dispose();
  }
}
