import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/service/mycelium_seam.dart';
import 'package:cleona/core/update/data_port_http.dart';
import 'package:cleona/core/util/local_addresses.dart'
    show dialableLocalAddresses, isRealNetworkChange;
import 'package:cleona/core/util/network_metered.dart' as network_metered;
import 'package:mycelium/node_post_box.dart' show NodePostBox;
import 'package:mycelium/host.dart';
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
import 'package:cleona/core/platform/router_db.dart';
import 'package:cleona/ui/screens/setup_screen.dart';
import 'package:cleona/ui/screens/settings_screen.dart';
import 'package:cleona/ui/screens/device_management_screen.dart';
import 'package:cleona/ui/screens/identity_detail_screen.dart';
import 'package:cleona/ui/screens/network_stats_screen.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/calls/call_integration_channel.dart';
import 'package:cleona/core/calls/session_behaviour_channel.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:collection/collection.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity/identity_remote_deletion.dart';
import 'package:cleona/core/media/media_store.dart';
import 'package:cleona/core/media/media_vault.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/crypto/keyring_mobile.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/screens/call_screen.dart';
import 'package:cleona/ui/screens/chat_screen.dart';
import 'package:cleona/ui/screens/group_call_screen.dart';
import 'package:cleona/ui/screens/qr_contact_screen.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/update/install_source.dart';
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:cleona/core/calls/video_engine.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/platform/window_show.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/windows_session.dart';
import 'package:cleona/core/platform/disk_space.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/log/log_redaction.dart';
import 'package:cleona/core/platform/lifecycle_drain_observer.dart';
import 'package:cleona/core/platform/ios_background_fetch.dart';
import 'package:cleona/ui/theme/skin.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/update_offer.dart';
import 'package:cleona/core/platform/apk_installer.dart';
import 'package:cleona/ui/screens/update_required_screen.dart';
import 'package:cleona/ui/screens/first_start_wipe_notice_screen.dart';
import 'package:cleona/core/platform/first_start_wipe.dart';
import 'package:cleona/core/channels/system_channels.dart' as sys_ch;
import 'package:cleona/ui/components/connection_sheet.dart';
import 'package:cleona/ui/components/crash_report_dialog.dart';
import 'package:cleona/ui/components/pending_security_dialogs.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart' as pp;


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // §19.6: hand the Android platform call to lib/core, which must stay
  // Flutter-free — the daemon is a pure-Dart AOT binary and cannot link
  // dart:ui (S299). Registered here, in the only entry point that actually
  // has a Flutter binding; the daemon leaves it null and falls back to
  // `sideload`, exactly as the previous MissingPluginException branch did.
  InstallSourceDetector.installerPackageNameProvider = () async {
    const channel = MethodChannel('chat.cleona/update');
    return channel.invokeMethod<String?>('getInstallerPackageName');
  };

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
    CleonaService.apkPathResolver = () async {
      const channel = MethodChannel('chat.cleona/share');
      return await channel.invokeMethod<String>('getApkSourcePath');
    };
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

  // Single-Instance (desktops: Linux, macOS, Windows)
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    if (_signalExistingInstance()) {
      exit(0);
    }
    _writeGuiLock();
  }

  // Mobile: Portrait lock prevents Activity/Scene recreation on rotation
  // which would destroy the in-process node (port conflict, state
  // corruption). Until the CUT of 2026-08-31 that was the `CleonaNode`; since
  // the CUT it is the V4.1 node (`_v41`, see below) — the same
  // reasoning, a different object.
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
    // §3.7: start up the keyring. On Linux/Windows the
    // START sequence (`initCrypto`: first-start wipe path, envelope change,
    // cleaner) belongs to the daemon — the UI there ONLY starts up the
    // keyring, see the `else` branch below.
    //
    // S368: here stood "the GUI connects via IPC and never accesses keys
    // directly". That was wrong and carried the finding: `setup_screen.dart`
    // CREATES the master seed in this process and reads it again.
    // Without a keyring it had no admissible storage location there and
    // landed under the raw `db.key` — the chain that S368 closes.
    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('[main] Initializing KeyringService (mobile)...');
      await MobileKeyringService.init(AppPaths.dataDir);
      await IdentityContext.initCrypto(AppPaths.dataDir);
      debugPrint('[main] KeyringService OK (hw=${KeyringService.instance.isHardwareProtected}).');
    } else if (Platform.isMacOS) {
      debugPrint('[main] Initializing KeyringService (macOS)...');
      await IdentityContext.initCrypto(AppPaths.dataDir);
      debugPrint('[main] KeyringService OK (hw=${KeyringService.instance.isHardwareProtected}).');
    } else {
      // ── THE UI DOES NEED THE KEYRING AFTER ALL (S368) ──────
      //
      // Here stood only "Skipping KeyringService init (daemon owns
      // keyring)". The omission was a saving measure (W3: double
      // DPAPI probe, file locks) — but the UI CREATES the seed on
      // Linux and Windows (`setup_screen.dart:143`,
      // `generateSeedPhrase`) and READS it afterwards itself (`:1880`,
      // `:2097`, `:2888` via `mgr.loadMasterSeed()`). Without a
      // keyring the only way for that was
      // `master_seed.json.enc` under the raw `db.key` — the
      // plaintext key from which the whole chain down to the
      // message store falls.
      //
      // It is EXPRESSLY only the keyring, not `initCrypto`:
      // the first-start wipe path, the envelope change and the cleaner
      // stay with the daemon. Two wipers on one profile would be a
      // race with data loss as the price.
      debugPrint('[main] Initializing KeyringService (desktop GUI — '
          'the seed is created and read here, S368)...');
      await KeyringService.init(AppPaths.dataDir);
      debugPrint('[main] KeyringService OK '
          '(hw=${KeyringService.instance.isHardwareProtected}).');
    }
  } catch (e, stack) {
    startupError = 'FFI init failed on ${Platform.operatingSystem}\n'
        'home=${AppPaths.home}\ndataDir=${AppPaths.dataDir}\n\n$e\n$stack';
    debugPrint('[main] FATAL: $startupError');
    _logCrash('main-ffi-init', e, stack);
  }

  // Enable accessibility semantics so AT-SPI can inspect the widget tree
  // This is required for automated GUI testing via accessibility tools
  SemanticsBinding.instance.ensureSemantics();

  // H7 (#U17): global error handlers — uncaught exceptions otherwise crash
  // Android silently. Mirror of the pattern from service_daemon.dart.
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
  // ── THE NOTE FROM THE WIPE PATH (§21.4, S363 option A) ──────────────
  //
  // On Android, iOS and macOS `IdentityContext.initCrypto` has run above in
  // THIS process (l. 157-166) — a wipe from just now is thus
  // already present as a note. On Linux and Windows the DAEMON wipes, and
  // the UI deliberately runs here without `initCrypto`; there the
  // note is that of an EARLIER start. Both are the same call, and
  // both are right: the note stays until someone has
  // confirmed it.
  final wipeNotice = FirstStartWipe.readNotice(AppPaths.dataDir);

  runApp(CleonaApp(
    hardBlocked: hardBlocked,
    blockManifest: blockManifest,
    wipeNotice: wipeNotice,
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
  // Bypasses the buffering of CLogger, not its redaction — see the
  // identically worded place in `service_daemon.dart`.
  final entry = LogRedaction.apply(
      '${DateTime.now().toIso8601String()} [$source] $error\n$stack\n\n');
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
    if (_isGuiProcessAlive(otherPid)) {
      File('$home/.cleona/gui.show').writeAsStringSync('$pid');
      return true;
    }
  } catch (_) {}

  // Stale lock file
  try { lockFile.deleteSync(); } catch (_) {}
  return false;
}

bool _isGuiProcessAlive(int p) {
  try {
    if (Platform.isWindows) {
      return _isWindowsProcessAlive(p);
    }
    return Process.runSync('kill', ['-0', '$p']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

bool _isWindowsProcessAlive(int p) {
  try {
    final result = Process.runSync(
        'tasklist', ['/FI', 'PID eq $p', '/FO', 'CSV', '/NH']);
    final out = result.stdout.toString().trim();
    if (out.isEmpty || out.startsWith('INFO:')) return false;
    return out.contains('"$p"');
  } catch (_) {
    return false;
  }
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

  /// §21.4: report of a first-start wipe path that has not yet been confirmed.
  /// `null` in the normal case.
  final WipeReport? wipeNotice;

  const CleonaApp({
    super.key,
    this.hardBlocked = false,
    this.blockManifest,
    this.wipeNotice,
  });

  @override
  State<CleonaApp> createState() => _CleonaAppState();
}

class _CleonaAppState extends State<CleonaApp> {
  late bool _showHardBlock = widget.hardBlocked && widget.blockManifest != null;

  /// §21.4: as long as set, the message about the wipe path stands before everything
  /// else except the version block screen.
  late WipeReport? _wipeNotice = widget.wipeNotice;

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
          state.appLocaleAdopt(_appLocale);
          // Sec H-5 / T13: if the user already chose "skip into limited" on
          // this session before the appState was constructed (impossible in
          // the current flow — appState is created the first build — but
          // guards against future reordering), re-apply.
          if (!_showHardBlock && widget.hardBlocked) {
            state._sessionReducedMode = true;
          }
          state._boot();
          // Bug #U16 + lifecycle-hijack fix: single observer drains both
          // shares and deep links on resume (and once on cold start).
          LifecycleDrainObserver.register(
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
            // §19.6: the sync startup cache-read that produced blockManifest
            // cannot know in-network availability (needs a running service's
            // DHT check) — fold in the live result once CleonaService.
            // onUpdateAvailable has fired for the same manifest version.
            final liveManifest = appState.availableUpdateManifest;
            final inNetworkAvailable = appState.availableUpdateInNetwork &&
                liveManifest != null &&
                liveManifest.version == widget.blockManifest!.version;
            home = UpdateRequiredScreen(
              downloadUrl: widget.blockManifest!.downloadUrl,
              reasonI18nKey: widget.blockManifest!.minRequiredReason
                  ?? 'update_required_kem_v2',
              inNetworkAvailable: inNetworkAvailable,
              onApplyUpdate: appState.applyUpdate,
              updateState: appState.updateState,
              updateProgress: appState.updateProgress,
              onSkipLimited: () {
                appState.setReducedModeSession(true);
                setState(() {
                  _showHardBlock = false;
                });
              },
            );
          } else if (_wipeNotice != null) {
            // §13.8 standard: active and unmistakable, before the
            // first frame of the application. The note is only
            // thrown away on confirmation — whoever closes the application before
            // gets the message at the next start.
            home = FirstStartWipeNoticeScreen(
              report: _wipeNotice!,
              onAcknowledge: () {
                FirstStartWipe.clearNotice(AppPaths.dataDir);
                setState(() => _wipeNotice = null);
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
              title: activeNetworkChannel == NetworkChannel.beta
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
                Text('Connecting to service...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// §7.5: an outstanding "rotation quorum not met" warning for one contact —
/// see [ICleonaService.onRotationCoAuthWarning]. Purely a UI-side record;
/// there is no daemon-side counterpart to keep in sync (unlike the pairing /
/// rotation-approval lists, nothing here is ever "answered").
class CoAuthWarning {
  final String contactNodeIdHex;
  final String displayName;
  final int tokensPresent;
  final int tokensRequired;

  const CoAuthWarning({
    required this.contactNodeIdHex,
    required this.displayName,
    required this.tokensPresent,
    required this.tokensRequired,
  });
}

/// §14.4/§14.5: an applied identity rotation of a CONTACT — the "visible
/// warning" of the visibility principle. Fires for EVERY accepted rotation
/// (`ICleonaService.onContactIdentityRotated`), because §14.5 applies the new
/// key even when the quorum cannot be judged ("the new key is **applied
/// anyway** — the **visibility principle**"). [wasVerified] says whether the
/// contact held `verified`/`trusted` before, and only drives how loudly the
/// banner words itself — never whether it appears.
class ContactRotationNotice {
  final String contactNodeIdHex;
  final String displayName;
  final bool wasVerified;

  const ContactRotationNotice({
    required this.contactNodeIdHex,
    required this.displayName,
    required this.wasVerified,
  });
}

/// §7.5 / §14.5: a LINKED DEVICE of a contact actively rejected a rotation —
/// the strongest theft signal the system has. Distinct from
/// [CoAuthWarning] (which says "the quorum was not reached"): here a device
/// did not merely stay silent, it objected.
class RotationRejectionNotice {
  final String contactNodeIdHex;
  final String displayName;

  const RotationRejectionNotice({
    required this.contactNodeIdHex,
    required this.displayName,
  });
}

class CleonaAppState extends ChangeNotifier with WidgetsBindingObserver {
  static CleonaAppState? _instance;

  ICleonaService? _service;
  IpcClient? _ipcClient;
  bool _isInitialized = false;
  bool _hasProfile = false;
  String? _initError;

  /// S395 (S394-5): exit status of the daemon THIS GUI started (Linux).
  /// `null` when the daemon was already running or was started otherwise —
  /// then the crash report says so instead of guessing.
  Future<int>? _daemonExit;

  /// V2.3: texture-based video delivery. [CallScreen] registers a callback
  /// that receives the remote peer's texture id (non-null = video active,
  /// null = video stopped). No longer per-frame — the texture is valid for
  /// the pipeline's lifetime; the native backend renders into it continuously.
  void Function(int? textureId)? onRemoteVideoTextureChanged;

  /// Non-null while a second (or later) identity is being created.
  /// Set before PQ keygen starts so the IdentityTabBar can show
  /// a "creating..." placeholder chip with a spinner immediately.
  String? _creatingIdentityName;
  String? get creatingIdentityName => _creatingIdentityName;
  /// Sec H-5 (V3.1.72) / T13: true after the user clicked "open anyway
  /// (limited)" on the [UpdateRequiredScreen]. Per-session, not persisted.
  /// Propagated to every concrete [CleonaService] (in-process) and,
  /// on Desktop, pushed to the daemon via [IpcClient.setReducedModeSession]
  /// (follow-up task 2026-04-26). See sec-h5 §8.2.
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

  /// Takes over the language management AND reports every change to the
  /// daemon (owner decision V-10-a = b, 09.09.2026).
  ///
  /// The daemon draws the tray state text (§22.9) and until S377 had
  /// only `Platform.localeName` — the language of the OPERATING SYSTEM. The
  /// listener hangs on `AppLocale` itself and not on the language selector,
  /// because there are TWO ways to change the language: the selection in the
  /// settings (`language_selector.dart`) and the GUI action
  /// `switch_language` from the E2E path. One listener covers both.
  void appLocaleAdopt(AppLocale locale) {
    _appLocale?.removeListener(_uiLanguageReport);
    _appLocale = locale;
    locale.addListener(_uiLanguageReport);
    _uiLanguageReport();
  }

  /// Only sets a field on the IPC client. By itself it costs NO
  /// message — the code travels with the next request that is due anyway
  /// (`IpcClient._sendRequest`).
  void _uiLanguageReport() {
    _ipcClient?.uiLocale = _appLocale?.currentLocale;
  }
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<ConnectivityResult> _connectivityResults = [];
  Timer? _networkChangeDebounce;
  bool _networkChangeRunning = false;

  /// The last seen inventory of dialable addresses (S380).
  ///
  /// The counterpart to `_lastPollIps` in the daemon. Without it every
  /// EVENT counted as a CHANGE here — as there until S380 in the `ip monitor` branch —
  /// and every change drops all sessions. On
  /// Android events without an address change are the rule (captive
  /// portal, switching between two bands of the same network).
  List<String> _lastDialableAddresses = const <String>[];
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

  /// Peers with confirmed mutual contact in this session.
  ///
  /// IN-PROCESS THE V3 SOURCE HAS GONE (CUT, 31.08.): it was
  /// `NodeHost.confirmedPeerCount` -> `CleonaNode.confirmedPeerIds`, i.e.
  /// Kademlia peers. The V4.1 replacement is NOT this quantity, but
  /// [syncPartnersOutbound] (§25.4/§22.9: confirmed sync partners are
  /// the input quantity of the connection icon). Putting the one in place
  /// of the other would be exactly the surrogate that §22.7
  /// excludes — that is why `0` stands here and not a substitute value.
  /// The IPC path stays untouched; it belongs to the `ipc_*` package.
  int get confirmedPeerCount {
    if (_ipcClient != null) return _ipcClient!.confirmedPeerCount;
    return 0;
  }

  /// §22.7 — the readiness state for the display layer.
  ///
  /// Via [service] and not via [_nodeHost]: readiness
  /// arises in the V4.1 delivery layer, and that hangs on the service, not
  /// on the node. Without a service `searching` — that is the cautious
  /// direction, the same as in `CleonaService.readinessState`.
  String get readinessState => _service?.readinessState ?? kReadinessSearching;

  /// §25.4 — confirmed sync partners by direction, for the display.
  ///
  /// Outgoing is the input quantity of the five-tier
  /// connection icon (§22.9: "The tiering's input quantity is the
  /// count of verified outbound sync partners"). Incoming says what
  /// this node carries for others.
  int get syncPartnersOutbound => _service?.syncPartnersOutbound ?? 0;
  int get syncPartnersInbound => _service?.syncPartnersInbound ?? 0;
  int get independentSyncPartners => _service?.independentSyncPartners ?? 0;

  /// §9.2 — the measured responsibility set. The consent dialog
  /// from §9.3 computes its time span from it.
  int get reachableResponsibleRelays =>
      _service?.reachableResponsibleRelays ?? 0;

  // ── UI peer counter (S252) ─────────────────────────────────────────
  // Confirmed + relay-reachable peers. Must be used by ALL UI surfaces
  // that display a peer count (Home badge, Settings, Contacts, Status).
  // The comparison with `NetworkStats.activePeerCount` stood here until
  // 01.09.2026 (S360). The field has gone — the network statistics now show
  // the direction-separated partner counts (§25.4) and read them
  // from the same source as this line. Reasoning in detail in
  // `service_interface.dart` at [peerCount].
  int get reachablePeerCount {
    // Like [confirmedPeerCount]: in-process without V3 source and without
    // substitute quantity. §25.4 lists the V4.1 numbers separately.
    if (_ipcClient != null) return _ipcClient!.reachablePeerCount;
    return 0;
  }

  /// True when UPnP/PCP successfully opened an inbound port mapping — used by
  /// the connection-status icon to split "strong (Hulk)" from "good (normal man)".
  bool get hasPortMapping {
    // ── UNTIL S373 A THREEFOLD WRONG TOMBSTONE STOOD HERE ──────────
    //
    // "V4.1 opens no port forwarding — it knows neither hole
    // punching nor port prediction." Of the three statements none was
    // tenable any more since 02.09.: hole punching and port prediction exist
    // for calls (`calls/punch_window.dart`,
    // `calls/address_candidates.dart:389-411`), and the port mapping was
    // brought back on 07.09.2026 with owner approval
    // (`lib/core/link_io/port_mapper.dart`). Right about the paragraph was
    // only that the V3 carrier lay in `lib/core/network/`.
    //
    // BOTH PATHS NOW READ THE SAME SOURCE: via IPC the daemon, which
    // sends `CleonaService.hasPortMapping` (`ipc_server.dart:233`), and
    // in-process the same getter directly. The `false` fallback only applies
    // when no service hangs at all.
    if (_ipcClient != null) return _ipcClient!.hasPortMapping;
    return _service?.hasPortMapping ?? false;
  }

  /// Whether transport is using mobile fallback (WiFi broken, mobile works).
  /// When true, icon should show mobile even if OS reports WiFi.
  // `final`, because since the CUT there is no writer any more: the
  // observer was `NodeHost.onMobileFallbackChanged` ->
  // `Transport.isMobileFallbackActive`. V4.1 holds ONE socket set and
  // knows no substitute path with dead WLAN. The value deliberately stays as a
  // field (instead of disappearing as a constant in the getter), so that
  // the place stays visible at which a V4.1 counterpart would have to
  // dock.
  final bool _mobileFallbackActive = false;
  bool get isMobileFallbackActive {
    // Gone in-process: the mobile fallback socket was a
    // `Transport` state from `lib/core/network/`. V4.1 holds ONE
    // socket set via `UdpSocketSet` and knows no substitute path with
    // dead WLAN — reported gap, no substitute value.
    if (_ipcClient != null) return _ipcClient!.mobileFallbackActive;
    return _mobileFallbackActive;
  }

  // System channel crash reporting (§9.5)
  final List<(Object, StackTrace)> _pendingCrashes = [];
  bool _crashDialogShowing = false;

  // In-process multi-identity state (Android, iOS, macOS-no-daemon)

  /// The ONE mycelium host of this process (S387, V4.2 §4.5.1): one node,
  /// one port, one mailbox per identity. Replaces `V41Runtime` +
  /// `V41Host` per identity.
  Host? _host;

  /// The same key as `_wirt`'s (`wirtSchluessel`, set at
  /// start) — kept for the port mapping (task D): its
  /// network-change edge lies in a different method body than the local
  /// `masterSeed` at start.
  Uint8List? _masterSeedForHost;

  /// The HTTP delivery at the host port (§26.6.5, S386 part A).
  DataPortHttp? _delivery;
  final Map<String, CleonaService> _inProcessServices = {};
  final Map<String, IdentityContext> _inProcessContexts = {};

  /// Is the app in the foreground? The edge counter for the catch-up harvest.
  ///
  /// SINCE S376 IT LIES HERE and no longer only in every service: the
  /// NODE PART of the foreground edge is run once by the process (P5
  /// finding 5), and whoever runs it needs the edge.
  ///
  /// Initial value `false`, so that the first report `resumed` counts as an edge
  /// — the same assumption as in `CleonaService._isAppResumed`.
  bool _appResumed = false;


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
    try {
      service.saveState();
    } catch (_) {}
    _scheduleCrashDialog(service, error, stack);
  }

  CleonaService? get _activeCleonaService {
    final s = _service;
    if (s is CleonaService && _inProcessServices.containsValue(s)) {
      return s;
    }
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
    _crashDialogShowing = true;
    final reporter = service.crashReporter;
    final report = reporter.buildReport(error, stack);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        _crashDialogShowing = false;
        return;
      }
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

    // §22.9: "Android foreground notification | Readiness state as the
    // leading statement." Until AP-5 a PEER COUNT stood here and, what
    // weighs more heavily, the word "Verbunden" — a success message that
    // §22.7 expressly forbids before `ready` ("before `ready`, the app
    // reports progress, not success"). A reachable peer count says
    // nothing about whether a message can be placed.
    //
    // COMPOSITION. §22-O-3 is OPEN: (a) three fixed texts per
    // state, (b) state plus partner count, (c) state plus
    // remaining task. Here stands (a) — the only variant that does not
    // anticipate a decision: each of the three variants needs the three state texts,
    // (b) and (c) only append something. The connection kind
    // stays as a TRAILING addition, because it answers a different question
    // (§22.9: "complementary … not competing") and because it
    // already stands there today.
    //
    // The texts come from `translations.dart` (§24.4.1). Before, they
    // were German literals — in each of the 34 languages the same German
    // line in the system bar.
    final locale = _appLocale;
    String t(String key) => locale == null ? key : locale.get(key);

    final String text;
    if (!hasNetwork) {
      // No network is no readiness statement, but the absence
      // of the prerequisite — it takes precedence.
      text = t('conn_offline');
    } else {
      final state = switch (readinessState) {
        kReadinessReady => t('readiness_ready'),
        kReadinessConnecting => t('readiness_connecting'),
        _ => t('readiness_searching'),
      };
      final String? kind;
      if (isMobileFallbackActive) {
        kind = t('conn_mobile_fallback');
      } else if (hasWifi) {
        kind = t('conn_wifi');
      } else if (hasMobile) {
        kind = t('conn_mobile');
      } else {
        kind = null;
      }
      text = kind == null ? state : '$state \u00b7 $kind';
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
    //
    // ── WITHOUT THE NODE PART (S376, P5 finding 5) ─────────────────────
    //
    // This here is a loop PER IDENTITY, and the catch-up harvest is
    // a matter of the NODE: one responsibility set, one
    // have-list. Until S376 every pass triggered it — with three
    // identities three times network traffic for ONE return to the
    // foreground (working rule 5). The node part now runs exactly
    // once, below, on the EDGE of this state object.
    for (final service in _inProcessServices.values) {
      service.setAppResumed(isResumed, triggerNodeHarvest: false);
    }
    _service?.setAppResumed(isResumed, triggerNodeHarvest: false);

    // ── THE EDGE, ONCE PER PROCESS ───────────────────────────────
    //
    // IT MUST LIE HERE, since the services no longer evaluate it:
    // the life-cycle observer reports `resumed` even when the
    // app was already in the foreground (dialogs, keyboard, permission requests).
    // Without the edge an edge would have become a tick — exactly
    // what working rule 5 excludes. The same calculation as before
    // in `CleonaService.setAppResumed`, only one level higher.
    final beforeFront = _appResumed;
    _appResumed = isResumed;
    final host = _host;
    if (isResumed && !beforeFront && host != null) {
      // S387: the mycelium counterpart of the V4.1 catch-up harvest — ONE
      // collection request per known holder, on the edge, no tick
      // (`NodePostBox.collect`).
      // S388: the manifest slot after the end of this collection (M1+).
      unawaited(host.node.collect().then((_) => _updateManifestAsk()));
    }

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      for (final service in _inProcessServices.values) {
        service.saveState();
      }
      if (_service is CleonaService) {
        (_service as CleonaService).saveState();
      }
      // `_nodeHost.saveNetworkState()` (V3 routing table) has gone with the
      // CUT. The V4.1 counterpart — entry supply and age
      // of the peers — is saved by `startV41Node` itself via the debounced
      // `entryPersist` timer; there is nothing to catch up here.
      // S12.5: Schedule iOS background fetch when going to background.
      // The BGTaskScheduler will wake the app periodically (earliest 15 min)
      // to retrieve pending P2P messages.
      if (Platform.isIOS) {
        IosBackgroundFetch.scheduleBackgroundFetch();
      }
    } else if (isResumed) {
      // Android 14: user can dismiss FGS notification; re-push on resume.
      if (Platform.isAndroid) _lastNotificationText = '';
      // GONE WITH V3 (CUT, 31.08.): after Doze/background seed peers
      // were pinged anew here (`onNetworkChanged`) and the public
      // address was asked anew via ipify (`_queryPublicIp`, from the
      // deleted `main_v3_address.dart`).
      //
      // ── UNTIL S376 A REPORTED GAP STOOD HERE THAT DOES NOT EXIST ──
      //
      // Verbatim: "V4.1 binds its socket at start and announces the address
      // determined then. If a phone switches from WLAN to mobile during Doze,
      // the own entry record is silently wrong afterwards,
      // and today there is no path that issues it anew."
      //
      // The path has lain there since S360, and it lies there twice. Re-measured on
      // 08.09.2026 on THIS tree:
      //
      //   1. THIS method, at the head: `service.setAppResumed(isResumed)`
      //      runs over every service (`cleona_service.dart`,
      //      "if (isResumed && !vorher)") calls `v41OnForeground` and thus
      //      `V41Node.nachholErnte(grund: 'Vordergrund')` — that fetches what
      //      stayed lying on the responsible relays during the absence.
      //   2. The network change itself, via `_startConnectivityMonitor`
      //      further below: `service.onNetworkChanged` →
      //      `CleonaService.v41OnNetworkChanged` (set in
      //      `v41_attach.dart`) → clear port mapping, re-read addresses,
      //      `setzeAnsageadressen`, `V41Node.onNetworkChanged`
      //      (sessions fall, observed addresses forgotten) and
      //      `announceOwnEntry(vorrangig: true)`. The entry record
      //      is thus very much issued anew, and with priority.
      //
      // WHAT IS REALLY MISSING, and only that (measured 08.09.2026): the
      // MULTICAST MEMBERSHIP of the LAN call. `startLanEntry`
      // (`lan_entry_wiring.dart`, `joinMulticast` in the loop over
      // `NetworkInterface.list`) joins the group ONCE at start,
      // per interface present at that time; there is no second
      // call, neither from `v41OnNetworkChanged` nor elsewhere. After an
      // interface change the node no longer hears a foreign call in the new segment
      // — it still CALLS there (`lanEntry?.announceNow()`
      // stands in the seam), but it does not hear. The data socket itself
      // is bound to the wildcard (`udp_sockets.dart`,
      // `family.wildcard`) and survives the change.
    }
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

  /// §19.6: latest verified update manifest reported by any in-process
  /// [CleonaService.onUpdateAvailable] fire (newest wins). Consumed by the
  /// hard-block [UpdateRequiredScreen] to offer the in-network update path
  /// in addition to the external `downloadUrl` — the synchronous startup
  /// cache-read in [main] cannot know [_availableUpdateInNetwork] because
  /// the DHT binary-availability check requires a running service.
  UpdateManifest? _availableUpdateManifest;
  bool _availableUpdateInNetwork = false;
  CleonaService? _availableUpdateSourceService;

  UpdateManifest? get availableUpdateManifest => _availableUpdateManifest;
  bool get availableUpdateInNetwork => _availableUpdateInNetwork;

  /// In-process (Android/iOS): collecting and installing separated (S387,
  /// owner decision 14.09.2026). In daemon mode the daemon holds its
  /// own offer; the GUI there only sends the click (`apply_update`).
  /// A moment according to M1+ (S388). Only the service with an update carrier asks
  /// (`updateAnbinden`); for the others the call is empty — no packet.
  Future<void> _updateManifestAsk() async {
    for (final s in List.of(_inProcessServices.values)) {
      await s.updateManifestAsk();
    }
    // E-9 (package 10 = A, S389): a collection run that ended without a result
    // was never repeated until the restart. The renewed attempt hangs on
    // THIS edge — no timer, no deadline (§1.2, working rule 5). Whether
    // collecting really happens is decided by `beiManifest`; no
    // second version of the rules stands here.
    _updateOffer.againTry();
  }

  late final UpdateOffer<CleonaService> _updateOffer =
      UpdateOffer<CleonaService>(
    assemble: (svc, manifest) => svc.startInNetworkUpdate(manifest),
    install: _installInProcess,
    isNew: (a, b) => UpdateChecker().isNewer(a, b),
    report: (m) => debugPrint('[update] $m'),
    fetchLocked: _updateFetchLocked,
  );

  /// Metered connection, last read — `null`: not yet read
  /// (S388, owner decision 15.09.2026: no update fetching over mobile
  /// or metered connection). Read at the edges of
  /// `connectivity_plus` in [_startConnectivityMonitor], no tick.
  bool? _connectionMetered;

  /// On mobile a not yet read network kind counts as metered: otherwise a
  /// manifest that arrives before the first reading would fetch over mobile.
  bool _updateFetchLocked() {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    return _connectionMetered ?? true;
  }

  /// Reads the network kind and reports a change to the offer.
  ///
  /// Android: `ConnectivityManager.isActiveNetworkMetered` — the information
  /// of the system, it also covers a WLAN marked as metered.
  /// iOS: `connectivity_plus` only knows the kind; mobile without WLAN counts
  /// as metered (`NWPath.isExpensive` is not connected, report S388).
  static Future<bool> _meteredDetermine(List<ConnectivityResult> results) async {
    final onlyMobil = results.contains(ConnectivityResult.mobile) &&
        !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
    var metered = onlyMobil;
    if (Platform.isAndroid) {
      try {
        metered = await const MethodChannel('chat.cleona/update')
                .invokeMethod<bool>('isActiveNetworkMetered') ??
            true;
      } catch (e) {
        debugPrint('[update] network kind not readable ($e) — mobile data counts as '
            'metered');
      }
    }
    return metered;
  }

  Future<void> _networkKindRead(List<ConnectivityResult> results) async {
    final metered = await _meteredDetermine(results);
    final before = _connectionMetered;
    _connectionMetered = metered;
    if (before != metered) {
      debugPrint('[update] connection ${metered ? 'metered' : 'unmetered'}');
      _updateOffer.networkKindChanged();
    }
  }

  BinaryUpdateState _updateState = BinaryUpdateState.idle;
  double _updateProgress = 0.0;
  bool _updateBannerDismissed = false;
  bool _updateApplyPending = false;
  bool _updateNeedsInstallPermission = false;

  BinaryUpdateState get updateState => _updateState;
  double get updateProgress => _updateProgress;
  bool get updateBannerDismissed => _updateBannerDismissed;
  bool get updateApplyPending => _updateApplyPending;
  bool get updateNeedsInstallPermission => _updateNeedsInstallPermission;

  void dismissUpdateBanner() {
    _updateBannerDismissed = true;
    notifyListeners();
  }

  void undismissUpdateBanner() {
    _updateBannerDismissed = false;
    notifyListeners();
  }

  // ── §7.1 LD-2 / §7.5: pending pairing + rotation-approval catch-up, and
  // the §7.5 co-authorization warning banner ────────────────────────────
  //
  // Single source of truth for state that arrives via fire-and-forget daemon
  // events (`onDevicePairRequest` / `onRotationApprovalRequest` /
  // `onRotationCoAuthWarning`). Both transport wiring blocks below (IPC and
  // in-process) funnel into the private handlers here instead of setting the
  // callback fields directly in two places with drifting logic — so the
  // global live dialog (works regardless of which screen is open, same
  // pattern as [_showIncomingCallScreen]) and the persistent list in
  // Settings → Devices (read via `context.watch<CleonaAppState>()`) always
  // agree on what is still outstanding.

  List<Map<String, dynamic>> _pendingPairRequests = [];
  List<Map<String, dynamic>> _pendingRotationApprovals = [];
  final List<CoAuthWarning> _coAuthWarnings = [];

  // WIRING ERROR, PRE-EXISTING (S360). `onContactIdentityRotated` and
  // `onRotationRejectionAlert` were fired by the service
  // (`cleona_service.dart` emergency rotation, `cleona_service_contact_request
  // .dart` 3x) and passed on by the IPC server (`ipc_server.dart:491`,
  // `:545`) — but never assigned in THIS file, neither on the IPC client
  // nor on the in-process service. Measured on 2026-09-01:
  //
  //     $ grep -n "onContactIdentityRotated\\|onRotationRejectionAlert" lib/main.dart
  //     (no match)
  //
  // Thus the "visible warning" required by §14.5 was ineffective
  // all along: the service called into a null callback, and the
  // visibility principle ("a rotation is never blocked, only shown") showed
  // nothing. NOT caused by the CUT — `onRotationCoAuthWarning` next to it was
  // always wired, these two never.
  final List<ContactRotationNotice> _contactRotationNotices = [];
  final List<RotationRejectionNotice> _rotationRejections = [];

  List<Map<String, dynamic>> get pendingPairRequests => _pendingPairRequests;
  List<Map<String, dynamic>> get pendingRotationApprovals =>
      _pendingRotationApprovals;
  List<CoAuthWarning> get coAuthWarnings => List.unmodifiable(_coAuthWarnings);
  List<ContactRotationNotice> get contactRotationNotices =>
      List.unmodifiable(_contactRotationNotices);
  List<RotationRejectionNotice> get rotationRejections =>
      List.unmodifiable(_rotationRejections);

  bool _showingGlobalPairDialog = false;
  bool _showingGlobalRotationDialog = false;

  /// Re-fetches both catch-up lists from the active service. No-op with no
  /// active service. Called at startup/reconnect/identity-switch (the actual
  /// catch-up — see [ICleonaService.getPendingPairRequests] /
  /// [ICleonaService.getPendingRotationApprovals]) AND after every live event
  /// and every user decision, so the daemon's now-authoritative state is
  /// always what these lists show — nothing here hand-mutates them.
  Future<void> refreshPendingSecurityRequests() async {
    final svc = _service;
    if (svc == null) return;
    final results = await Future.wait([
      svc.getPendingPairRequests(),
      svc.getPendingRotationApprovals(),
    ]);
    _pendingPairRequests = results[0];
    _pendingRotationApprovals = results[1];
    notifyListeners();
  }

  /// §7.5: dismiss a co-auth warning banner. Purely a UI acknowledgement —
  /// there is nothing to answer (unlike the pairing/rotation prompts), so
  /// this never touches the service.
  void dismissCoAuthWarning(String contactNodeIdHex) {
    _coAuthWarnings.removeWhere((w) => w.contactNodeIdHex == contactNodeIdHex);
    notifyListeners();
  }

  Future<void> _handleDevicePairRequest(String deviceIdHex) async {
    await refreshPendingSecurityRequests();
    final svc = _service;
    if (svc == null || _showingGlobalPairDialog) return;
    // Re-check against the just-refreshed list: the request may already be
    // gone again (LD-9 auto-approve, or it lost a race with another client's
    // decision) between the event firing and this refresh completing.
    final stillPending = _pendingPairRequests
        .any((e) => e['deviceIdHex'] == deviceIdHex);
    if (!stillPending) return;
    _showGlobalDialog((ctx) {
      _showingGlobalPairDialog = true;
      return showIncomingPairRequestDialog(
        context: ctx,
        service: svc,
        deviceIdHex: deviceIdHex,
      ).whenComplete(() {
        _showingGlobalPairDialog = false;
        unawaited(refreshPendingSecurityRequests());
      });
    });
  }

  /// [kind] distinguishes key rotation from device-set change (§7.5,
  /// proto field `approval_kind`). It is passed through up to here so that the
  /// dialog can name what it is about — otherwise one would obtain consent under a
  /// false description. The labelling in the dialog is still pending
  /// (needs its own i18n keys in all 34 locales); until then the value is
  /// available here and is logged.
  Future<void> _handleRotationApprovalRequest(
      String rotationHashHex, String requestingDeviceIdHex,
      RotationApprovalKind kind, List<String> newDeviceNodeIds) async {
    await refreshPendingSecurityRequests();
    final svc = _service;
    if (svc == null || _showingGlobalRotationDialog) return;
    final entry = _pendingRotationApprovals
        .firstWhereOrNull((e) => e['rotationHashHex'] == rotationHashHex);
    if (entry == null) return; // already answered/expired before we refreshed
    final expiresAtMs = entry['expiresAtMs'] as int;
    // Until the dialog labels the occasion, it at least stays traceable in the log
    // — a device-set change must not pass unnoticed as a
    // key rotation (§7.5).
    debugPrint('§7.5 approval request: kind=${kind.wireName} '
        'devices=${newDeviceNodeIds.length} hash=${rotationHashHex.substring(0, 8)}');
    _showGlobalDialog((ctx) {
      _showingGlobalRotationDialog = true;
      return showRotationApprovalDialog(
        context: ctx,
        service: svc,
        rotationHashHex: rotationHashHex,
        requestingDeviceIdHex: requestingDeviceIdHex,
        expiresAtMs: expiresAtMs,
      ).whenComplete(() {
        _showingGlobalRotationDialog = false;
        unawaited(refreshPendingSecurityRequests());
      });
    });
  }

  void _handleRotationCoAuthWarning(String contactNodeIdHex,
      String displayName, int tokensPresent, int tokensRequired) {
    // A repeat broadcast for the same contact replaces rather than stacks —
    // the banner shows the latest token count, not a growing pile of alerts
    // for one ongoing incident.
    _coAuthWarnings.removeWhere((w) => w.contactNodeIdHex == contactNodeIdHex);
    _coAuthWarnings.add(CoAuthWarning(
      contactNodeIdHex: contactNodeIdHex,
      displayName: displayName,
      tokensPresent: tokensPresent,
      tokensRequired: tokensRequired,
    ));
    notifyListeners();
  }

  /// §14.5 visibility principle: an accepted identity rotation of a contact.
  /// Replaces rather than stacks per contact, same reason as
  /// [_handleRotationCoAuthWarning] — one incident, one line.
  ///
  /// `wasVerified` is sticky across repeats: a contact who was `verified`
  /// before the FIRST rotation is still the loud case if a second rotation
  /// arrives before the user acknowledged the first, even though by then the
  /// level has already been reset to `unverified` and the second event
  /// reports `wasVerified == false`. Dropping the flag on the repeat would
  /// silently downgrade the very warning the repeat makes more urgent.
  void _handleContactIdentityRotated(
      String contactNodeIdHex, String displayName, bool wasVerified) {
    final before = _contactRotationNotices
        .where((n) => n.contactNodeIdHex == contactNodeIdHex)
        .any((n) => n.wasVerified);
    _contactRotationNotices
        .removeWhere((n) => n.contactNodeIdHex == contactNodeIdHex);
    _contactRotationNotices.add(ContactRotationNotice(
      contactNodeIdHex: contactNodeIdHex,
      displayName: displayName,
      wasVerified: wasVerified || before,
    ));
    notifyListeners();
  }

  /// §7.5: a linked device of a contact actively rejected a rotation.
  void _handleRotationRejectionAlert(
      String contactNodeIdHex, String displayName) {
    _rotationRejections
        .removeWhere((n) => n.contactNodeIdHex == contactNodeIdHex);
    _rotationRejections.add(RotationRejectionNotice(
      contactNodeIdHex: contactNodeIdHex,
      displayName: displayName,
    ));
    notifyListeners();
  }

  /// UI acknowledgement only — nothing to answer, same as
  /// [dismissCoAuthWarning].
  void dismissContactRotationNotice(String contactNodeIdHex) {
    _contactRotationNotices
        .removeWhere((n) => n.contactNodeIdHex == contactNodeIdHex);
    notifyListeners();
  }

  /// UI acknowledgement only — see [dismissContactRotationNotice].
  void dismissRotationRejection(String contactNodeIdHex) {
    _rotationRejections
        .removeWhere((n) => n.contactNodeIdHex == contactNodeIdHex);
    notifyListeners();
  }

  /// Shows a dialog against `navigatorKey`'s current context regardless of
  /// which screen is on top. Buffers like [_showIncomingCallScreen] for the
  /// case where the event races the very first frame (Navigator not attached
  /// yet).
  void _showGlobalDialog(Future<void> Function(BuildContext) show) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showGlobalDialog(show));
      return;
    }
    show(ctx);
  }

  Future<void> retryInstallPermission() async {
    final hasPermission = await ApkInstaller.requestInstallPermission();
    if (hasPermission) {
      _updateNeedsInstallPermission = false;
      notifyListeners();
      await applyUpdate();
    } else {
      notifyListeners();
    }
  }

  void cancelUpdate() {
    _updateNeedsInstallPermission = false;
    _updateState = BinaryUpdateState.idle;
    _updateBannerDismissed = true;
    notifyListeners();
  }

  /// Starts the in-network binary update. In IPC mode (Linux/Windows desktop)
  /// sends the command to the daemon; in-process (Android/iOS) calls the
  /// service directly.
  Future<void> startInNetworkUpdate() async {
    final ipc = _ipcClient;
    debugPrint('[update] startInNetworkUpdate: ipc=${ipc != null}, '
        'manifest=${_availableUpdateManifest?.version}, '
        'state=$_updateState');
    if (ipc != null) {
      final ok = await ipc.startInNetworkUpdate();
      debugPrint('[update] IPC startInNetworkUpdate returned: $ok');
      return;
    }
    final manifest = _availableUpdateManifest;
    final source = _availableUpdateSourceService;
    if (manifest == null || source == null) {
      debugPrint('[update] in-process fallback: manifest=${manifest != null}, source=${source != null} — no-op');
      return;
    }
    await source.startInNetworkUpdate(manifest);
  }

  /// The click on "Installieren" — in the banner or in the UpdateRequiredScreen.
  /// The ONLY path to installation (S387, [UpdateOffer]).
  Future<void> applyUpdate() async {
    // IPC/daemon mode: tell daemon to apply the update and restart
    final ipc = _ipcClient;
    if (ipc != null) {
      _updateApplyPending = true;
      notifyListeners();
      await ipc.applyUpdate();
      return;
    }
    await _updateOffer.consent();
  }

  /// In-process: installs the checked, ready update. Called
  /// exclusively from [UpdateOffer.consent], i.e. after the click.
  /// `true` only if the installation has been carried out; on Android
  /// the system installer returns, and an abort there leaves the banner
  /// standing — hence `false` there, a second click remains possible.
  Future<bool> _installInProcess(CleonaService source) async {
    if (Platform.isAndroid) {
      // ── BACK IN OPERATION (2026-09-01, gap G-7) ───────────────────
      //
      // From the cut on 31.08. up to here this branch was a visible
      // failure: it lacked `source.binaryFragmentStore`, the access to the
      // path of the finished assembled APK. The getter has been recreated in
      // `cleona_service_update.dart` — field and class
      // had survived the cut anyway, only the access was missing.
      //
      // The body below is VERBATIM the state before the cut (`git show
      // 62151c46 -- lib/main.dart`), not newly invented. §26.6.1 step 6
      // lists it as a critical user path that must not be
      // changed; `test/smoke/smoke_update_mandatory_flow.dart` now measures
      // each of its four stages individually, so that a second cut does not
      // silently take it along again.
      final mgr = source.binaryUpdateManager;
      final store = source.binaryFragmentStore;
      if (mgr == null || store == null) return false;
      _updateNeedsInstallPermission = false;
      // The state stays `ready` — the update IS ready. Earlier
      // `verifying` stood here, and the banner (only visible on `ready`)
      // would disappear during the handover; an abort in the
      // system installer would allow no second click.
      _updateApplyPending = true;
      notifyListeners();
      try {
        final completePath = store.completePath(
            Platform.operatingSystem, mgr.targetVersion ?? '');
        if (!File(completePath).existsSync()) return false;
        var hasPermission = await ApkInstaller.canInstallPackages();
        if (!hasPermission) {
          hasPermission = await ApkInstaller.requestInstallPermission();
        }
        if (!hasPermission) {
          _updateNeedsInstallPermission = true;
          return false;
        }
        await ApkInstaller.installApk(completePath);
        return false;
      } finally {
        _updateApplyPending = false;
        notifyListeners();
      }
    } else {
      final mgr = source.binaryUpdateManager;
      if (mgr == null) return false;
      _updateApplyPending = true;
      notifyListeners();
      final path = await mgr.getVerifiedBinaryPath(
          Platform.operatingSystem, mgr.targetVersion ?? '');
      final ok = path != null &&
          await mgr.applyDesktopUpdate(Platform.resolvedExecutable);
      if (ok) exit(0);
      _updateApplyPending = false;
      notifyListeners();
      return false;
    }
  }

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt('cleona_theme_mode');
      if (idx != null && idx >= 0 && idx < ThemeMode.values.length) {
        _themeMode = ThemeMode.values[idx];
        notifyListeners();
      }
    } catch (_) {}
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
      if (Platform.isWindows) return _isWindowsProcessAlive(p);
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

  void _spawnGuiRestartHelper() {
    () async {
      try {
        if (Platform.isLinux) {
          final cmdlineBytes = File('/proc/self/cmdline').readAsBytesSync();
          final cmdParts = String.fromCharCodes(cmdlineBytes)
              .split('\x00')
              .where((s) => s.isNotEmpty)
              .toList();
          final quotedCmd = cmdParts.map((p) => "'${p.replaceAll("'", r"'\''")}'").join(' ');
          await Process.start('/bin/bash', ['-c', 'sleep 3 && exec $quotedCmd'],
              mode: ProcessStartMode.detached);
        }
        // Windows: no separate restart helper needed — update-apply.bat
        // starts both daemon and GUI after extraction.
      } catch (e) {
        _guiUpdateLog('Failed to spawn restart helper: $e');
      }
      _guiUpdateLog('exit(0)');
      exit(0);
    }();
  }

  void _guiUpdateLog(String msg) {
    final line = '${DateTime.now().toIso8601String()} [gui-update] '
        '${LogRedaction.apply(msg)}';
    debugPrint(line);
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      File('$home/.cleona/gui-update.log').writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Where the daemon's stdout/stderr go (Linux, S395). Cut to its last half
  /// before each start once it passes 1 MB, so it cannot grow without bound.
  String _prepareDaemonStdioLog() {
    final path = '$_baseDir/logs/daemon-stdio.log';
    try {
      Directory('$_baseDir/logs').createSync(recursive: true);
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        final bytes = f.readAsBytesSync();
        f.writeAsBytesSync(bytes.sublist(bytes.length - 512 * 1024), flush: true);
      }
    } catch (e) {
      debugPrint('[main] Daemon stdio log not prepared: $e');
    }
    return path;
  }

  /// The last [lines] lines of the daemon's stdout/stderr (Linux), or a line
  /// saying why there are none.
  String _daemonStdioTail({int lines = 40}) {
    try {
      final f = File('$_baseDir/logs/daemon-stdio.log');
      if (!f.existsSync()) return '(no daemon-stdio.log)';
      final all = f.readAsLinesSync();
      final from = all.length > lines ? all.length - lines : 0;
      return all.sublist(from).join('\n');
    } catch (e) {
      return '(daemon-stdio.log not readable: $e)';
    }
  }

  /// Reports a vanished daemon, then ends the GUI. Waits briefly for the exit
  /// status: the IPC socket and the process end at nearly the same moment,
  /// and without the wait the report would regularly miss it.
  Future<void> _logDaemonCrashAndExit() async {
    int? exitCode;
    try {
      exitCode = await _daemonExit?.timeout(const Duration(seconds: 2));
    } catch (_) {}
    _logDaemonCrash(exitCode: exitCode);
    exit(0);
  }

  void _logDaemonCrash({int? exitCode}) {
    try {
      final ts = DateTime.now().toIso8601String();
      final buf = StringBuffer()
        ..writeln('=== Daemon crash detected at $ts ===');
      if (_daemonExit == null) {
        buf.writeln('Exit status: unknown (daemon not started by this GUI)');
      } else if (exitCode == null) {
        buf.writeln('Exit status: not yet available after 2 s');
      } else if (exitCode < 0) {
        buf.writeln('Exit status: killed by signal ${-exitCode}');
      } else {
        buf.writeln('Exit status: $exitCode');
      }

      // Read PID from lock/pid file
      int? daemonPid;
      for (final name in ['cleona.lock', 'cleona.pid']) {
        try {
          final content = File('$_baseDir/$name').readAsStringSync().trim();
          daemonPid = int.tryParse(content);
          if (daemonPid != null) break;
        } catch (_) {}
      }
      buf.writeln('Daemon PID: ${daemonPid ?? "unknown"}');

      // Check dmesg for OOM/segfault for this PID (Linux only)
      if (Platform.isLinux) {
        try {
          final r = Process.runSync('dmesg', ['--time-format', 'iso'],
              stdoutEncoding: const SystemEncoding());
          if (r.exitCode == 0) {
            final lines = (r.stdout as String).split('\n');
            final relevant = lines.where((l) =>
                l.contains('oom-kill') ||
                l.contains('Out of memory') ||
                l.contains('segfault') ||
                l.contains('killed process') ||
                (daemonPid != null && l.contains('$daemonPid')));
            if (relevant.isNotEmpty) {
              buf.writeln('dmesg matches:');
              for (final l in relevant) {
                buf.writeln('  $l');
              }
            } else {
              buf.writeln('dmesg: no OOM/segfault/kill signals found');
            }
          } else {
            // S395: an ordinary user usually may not read the kernel ring
            // buffer (`kernel.dmesg_restrict`). Until now that case wrote
            // nothing, which read like "nothing was checked".
            buf.writeln('dmesg: not readable (exit ${r.exitCode})');
          }
        } catch (e) {
          buf.writeln('dmesg: $e');
        }
        buf.writeln('Last lines of $_baseDir/logs/daemon-stdio.log:');
        buf.writeln(_daemonStdioTail());
      }

      final crashLog = File('/tmp/cleona-daemon-crash.log');
      // This file lies in `/tmp`, so it is readable for every user of the
      // device — it needs the redaction rather more than the one in the
      // profile, not less.
      crashLog.writeAsStringSync('${LogRedaction.apply(buf.toString())}\n',
          mode: FileMode.append, flush: true);
      debugPrint('[main] Crash info written to /tmp/cleona-daemon-crash.log');
    } catch (e) {
      debugPrint('[main] Failed to log daemon crash: $e');
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

    // THE PORT OF THE DEVICE (S374, §11). Here stood "Use first identity's
    // port if available" — and exactly that passed the list position through
    // to the command line of the daemon that this GUI starts.
    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    final port = identities.isEmpty ? 4443 : mgr.deviceDataPort;

    final args = [
      '--base-dir', _baseDir,
      '--port', '$port',
    ];

    if (Platform.isLinux) {
      // Use setsid to create a new session — the daemon becomes session leader
      // and is fully detached. This avoids the zombie intermediate process that
      // Dart's ProcessStartMode.detached creates via double-fork.
      //
      // S395 (S394-5): stdout, stderr and the exit status of the daemon were
      // thrown away here (`drain`, `exitCode.then((_) {})`). stderr is where
      // the Dart VM writes its crash report on a segmentation fault — the
      // S394-4 tray crash left nothing but "Daemon crash detected, PID". The
      // shell behind `setsid` now redirects the daemon's own descriptors into
      // a file: a pipe to this GUI would break with the GUI, the file does
      // not. `exec` replaces the shell, so the process tree is unchanged and
      // `exitCode` is the daemon's own. No core dumps: an image of the
      // daemon's memory would carry its keys (§4).
      final stdioLog = _prepareDaemonStdioLog();
      final proc = await Process.start('setsid', [
        'sh', '-c', r'log=$1; shift; exec "$@" >>"$log" 2>&1',
        'sh', stdioLog, daemonBinary, ...args,
      ]);
      // Reaps the child (no zombie) and keeps its status for the crash report.
      _daemonExit = proc.exitCode;
    } else if (Platform.isWindows) {
      // S397 (S394-9): the Windows daemon died with 0xc0000409 (fail-fast of
      // the Dart VM, event log 25.09. 16:07:18) and left no reason — its
      // stderr went nowhere. Same remedy as on Linux: stderr into
      // daemon-stdio.log. A launcher file instead of an inline `cmd /c`
      // line: Dart quotes arguments with backslash escapes, which cmd.exe
      // does not understand. stdout goes to NUL — it only repeats the log.
      final stdioLog = _prepareDaemonStdioLog().replaceAll('/', r'\');
      final launcher = File('$_baseDir/daemon-start.cmd'); // not a log
      final line = [daemonBinary, ...args].map((a) => '"$a"').join(' ');
      launcher.writeAsStringSync('@$line 2>>"$stdioLog" >NUL\r\n');
      await Process.start('cmd.exe', ['/d', '/c', launcher.path.replaceAll('/', r'\')],
          mode: ProcessStartMode.detached);
    } else {
      await Process.start(daemonBinary, args, mode: ProcessStartMode.detached);
    }
    return _waitForSocketConnectable(maxWaitMs: 15000);
  }

  /// Can the running daemon show an icon in the notification area of this user?
  /// (Linux: DISPLAY/WAYLAND_DISPLAY. Windows: session comparison.)
  ///
  /// ── WINDOWS WAS UNCONDITIONALLY `true` HERE (finding 4, S370) ──────────
  ///
  /// "no SSH daemon story there" was not true. Measured on 06.09.2026 on
  /// the Windows build VM: the daemon ran in session 0, the shell in
  /// session 3 — no notification area, no icon. Because this function returned `true`,
  /// the GUI never replaced it; and because `NativeTrayWindows.init`
  /// discarded the return value of `Shell_NotifyIcon`, the daemon reported
  /// "Tray icon: OK" on top. The tray contract was checked on Windows at no
  /// place.
  ///
  /// WHAT THE GUI DOES WITH THE NEW VALUE (`_ensureDaemonRunning`, above):
  ///   * daemon alive, service running, icon possible  -> `return true`,
  ///     unchanged normal case, nothing is touched.
  ///   * daemon alive, service running, icon NOT possible (session 0)
  ///     -> `_killExistingDaemon()` and a new daemon in the session
  ///     of THIS GUI. Exactly the repair that the Linux branch has always
  ///     done for the DISPLAY-less daemon.
  ///   * session not measurable -> [windowsDaemonCanShowTray] returns
  ///     `true`, i.e. exactly the behaviour from before S370. A
  ///     failed measurement never kills a daemon.
  ///
  /// macOS stays unconditionally `true`: there is no daemon tray there
  /// (`native_tray.dart` returns immediately for macOS), and no procfs
  /// for the environment check.
  bool _daemonHasDisplay() {
    if (Platform.isMacOS) return true;
    if (Platform.isWindows) return _windowsDaemonHasTray();
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

  /// Windows: does the daemon sit in the same session as this GUI?
  ///
  /// What is read is `cleona.pid`, NOT `cleona.lock` — the running daemon
  /// holds the lock file under Windows exclusively with `LockFileEx`, so that
  /// every read access to it throws for its whole runtime (the same
  /// reason for which `ipc_client.dart:_isDaemonProcessAlive` falls back to
  /// `cleona.pid`).
  bool _windowsDaemonHasTray() {
    int? daemonPid;
    try {
      daemonPid =
          int.tryParse(File('$_baseDir/cleona.pid').readAsStringSync().trim());
    } catch (_) {
      daemonPid = null;
    }
    // No PID = no measurement = when in doubt, do not kill.
    if (daemonPid == null || daemonPid <= 0) return true;
    return windowsDaemonCanShowTray(
      daemonSession: windowsSessionIdOf(daemonPid),
      guiSession: windowsSessionIdOf(pid),
    );
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

  /// Finds the daemon binary in the bundle.
  ///
  /// `<bundleDir>/bin/` COMES FIRST (S367). `dart build cli` embeds the
  /// path of the store library as `../lib/…` relative to the binary;
  /// that is why the daemon lies there and no longer in the
  /// bundle root. If the GUI nonetheless starts a root copy,
  /// that fails when opening the store — and that with EXIT 0, i.e. for
  /// the GUI indistinguishable from "running, just opens no socket".
  /// The root stays in the list as fallback, so that an
  /// old-layout bundle and the test trees keep starting.
  String? _findDaemonBinary() {
    final sep = Platform.pathSeparator;
    final bundleDir = AppPaths.bundleDir;
    final daemonName = AppPaths.daemonBinaryName;
    for (final path in [
      AppPaths.daemonPathIn(bundleDir),
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
        timer.cancel();
        debugPrint('[main] Daemon still not ready after ${attempt * 5}s — giving up');
        _initError = 'Daemon not reachable after ${attempt * 5}s.\n\n'
            'baseDir: $_baseDir\n'
            'lock: ${File('$_baseDir/cleona.lock').existsSync()}\n'
            'pid: ${File('$_baseDir/cleona.pid').existsSync()}\n'
            '${Platform.isWindows ? 'port' : 'sock'}: '
            '${File('$_baseDir/${Platform.isWindows ? 'cleona.port' : 'cleona.sock'}').existsSync()}';
        notifyListeners();
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
      unawaited(_networkKindRead(results));
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      debugPrint('[connectivity] Change: $results');
      _connectivityResults = results;
      notifyListeners();
      unawaited(_networkKindRead(results));
      if (!_isInitialized) return;

      // ── `typeChanged` IS NO LONGER COMPUTED (CUT, 31.08.) ───────
      //
      // Here a `typeChanged` was computed from `prevResults`/`results`
      // — WLAN/Ethernet <-> mobile — and passed on as
      // `_nodeHost.onNetworkChanged(force: typeChanged)`.
      // `force` bypassed the "IP unchanged" lock there.
      //
      // The CALCULATION stays gone, and that is the reason why this
      // paragraph stands: V4.1 does not need it. `V41Node.onNetworkChanged`
      // knows no "IP unchanged" lock that would have to be bypassed — it
      // UNCONDITIONALLY drops all sessions and forgets the
      // observed addresses. A second bit that forced the same once more
      // would be a dead parameter.
      //
      // ── UNTIL S376 IT STOOD HERE THAT THE NODE PART WAS NOT REPLACED ───────
      //
      // Verbatim: "It is not handled — V4.1 binds its socket
      // once and has no path to rebind it after an interface change.
      // Reported gap". That was wrong since S360; the
      // chain stands written out in the resume branch further up
      // (`didChangeAppLifecycleState`). The node part runs, it just
      // no longer hangs on a call of its own from here, but IN the
      // service: `service.onNetworkChanged` calls it itself.

      // P4: debounce rapid connectivity events (Hotel-WLAN, captive portals).
      // Without this, each event fires onNetworkChanged() immediately —
      // concurrent runs corrupt peer/route state.
      _networkChangeDebounce?.cancel();
      _networkChangeDebounce = Timer(const Duration(seconds: 2), () async {
        if (_networkChangeRunning) return;
        // ── AN EVENT IS NOT YET A CHANGE (S380) ────────────────
        //
        // The same probe as in the daemon, from the same source
        // (`istEchterNetzwechsel`). It never stood here: the debouncing
        // bundled events, but never checked whether an
        // address change follows them. The damage was measured on the
        // Linux daemon (there via `ip monitor`); THAT it has the same
        // gap here is proven in the code, the event rate of
        // `connectivity_plus` on a real device is not.
        final addresses = await dialableLocalAddresses();
        if (!isRealNetworkChange(
            before: _lastDialableAddresses, after: addresses)) {
          debugPrint('[connectivity] event without address change — '
              'discarded (${addresses.join(',')})');
          return;
        }
        debugPrint('[connectivity] address change: '
            '${_lastDialableAddresses.join(',')} → ${addresses.join(',')}');
        _lastDialableAddresses = addresses;
        _networkChangeRunning = true;
        try {
          // ONE CALL, BOTH PARTS. `service.onNetworkChanged` does
          // the service part (local addresses, rendezvous, backoff,
          // resends) AND calls the seam `v41OnNetworkChanged`, i.e.
          // the node part. `triggerNodeReset` does NOT control that — the
          // parameter stems from the V3 era and separated callers that
          // had already triggered the node themselves; this double path
          // no longer exists (see `CleonaService.onNetworkChanged`).
          if (_inProcessServices.isNotEmpty) {
            // ── THE NODE PART ONCE (S376 P5 finding 5; S387 mycelium) ─
            //
            // `Host.networkChanged` (§11.8, §22.7.1) — once per event
            // for the whole process; the services below only with
            // `triggerNodeReset: false`.
            final host = _host;
            if (host != null) {
              try {
                await host.networkChanged();
              } catch (e) {
                debugPrint('[main] mycelium network change (node part): $e');
              }
              // The manifest slot AFTER the end of the network change (S388, M1+).
              unawaited(_updateManifestAsk());
              // The port mapping at the same edge (§7.3, task D) —
              // NOT awaited, for the same reason as at start
              // (RFC 6886 backoff).
              unawaited(() async {
                try {
                  await portMappingToEdge(
                    host,
                    baseDir: _baseDir,
                    key: hostKey(_baseDir, _masterSeedForHost),
                    report: (m) => debugPrint('[main] $m'),
                  );
                } catch (e) {
                  debugPrint('[main] port mapping (network change): $e');
                }
              }());
            }
            for (final service in _inProcessServices.values) {
              service.onNetworkChanged(triggerNodeReset: false);
            }
          } else {
            // SINGLE SERVICE, hence with the node part: here there is no
            // loop that could multiply it. In the IPC case
            // the seam is `null` anyway — the node stands in the daemon.
            await _service?.onNetworkChanged();
          }
        } finally {
          _networkChangeRunning = false;
        }
      });
    });
  }

  // ── Initialize ────────────────────────────────────────────────────

  /// Registers the media keys of all identities and starts the
  /// decrypting reader IN THIS process (S362 variant B).
  ///
  /// **Why the UI must do this itself.** On Linux and Windows
  /// service and UI run separately (`initialize()` connects
  /// right below via IPC to the daemon). The daemon writes the
  /// attachments, the UI displays them — so it needs the same
  /// key. It can derive it itself: `loadMasterSeed()` reads the
  /// keyring or `master_seed.json` and is process-independent
  /// (`identity_manager.dart:207`), and `hdIndex` stands in
  /// `identities.json`.
  ///
  /// The reader of this process is a SEPARATE one — its own ephemeral port,
  /// its own path secret. Two readers side by side are no problem:
  /// both only bind the loopback, and neither knows the secret of the
  /// other.
  ///
  /// Without a master seed (linked device, §7.6.2) the base key
  /// falls back to `db.key` as everywhere else — the same choice that
  /// `CleonaService._fileEnc` makes, so that both processes find the same
  /// key.
  Future<void> _mediaDepositRegister() async {
    try {
      final mgr = IdentityManager();
      final masterSeed = mgr.loadMasterSeed();
      for (final id in mgr.loadIdentities()) {
        if (id.profileDir.isEmpty) continue;
        final key = (masterSeed != null && id.hdIndex != null)
            ? HdWallet.deriveFileEncKey(masterSeed, id.hdIndex!)
            : null;
        MediaStore.instance.register(id.profileDir,
            FileEncryption(baseDir: _baseDir, key: key).effectiveKey);
      }
      await MediaVault.instance.start(profileDir: _baseDir);
    } catch (e) {
      debugPrint('[main] media store: $e — attachments stay invisible in this '
          'session (but they lie intact and encrypted).');
    }
  }

  Future<void> initialize() async {
    _hasProfile = true;

    // S362: before building the UI, so that the first rendering
    // of a conversation can already resolve the attachments.
    await _mediaDepositRegister();

    final daemonStarted = await _ensureDaemonRunning();

    if (daemonStarted) {
      final socketPath = '$_baseDir/cleona.sock';
      final ipcClient = IpcClient(socketPath: socketPath);
      final connected = await ipcClient.connect();

      if (connected) {
        _ipcClient = ipcClient;
        _service = ipcClient;

        // V-10-a = b: the language in which the daemon labels its tray.
        // Here, because the client has only just been created —
        // `appLocaleUebernehmen` ran long ago, but had no
        // receiver yet.
        _uiLanguageReport();

        ipcClient.onStateChanged = () => notifyListeners();
        ipcClient.onNewMessage = (convId, msg) => notifyListeners();
        ipcClient.onContactRequestReceived = (nodeId, name) => notifyListeners();
        ipcClient.onContactAccepted = (nodeId) => notifyListeners();
        ipcClient.onIncomingCall = (call) => _showIncomingCallScreen(call);
        ipcClient.onCallEnded = (_) => notifyListeners();
        ipcClient.onCallAccepted = (_) => notifyListeners();
        ipcClient.onCallRejected = (call, reason) => notifyListeners();
        ipcClient.onJuryRequestReceived = (_) => notifyListeners();
        ipcClient.onIncomingGroupCall = (call) => _showIncomingGroupCallScreen(call);
        ipcClient.onGroupCallStarted = (_) => notifyListeners();
        ipcClient.onGroupCallEnded = (_) => notifyListeners();
        ipcClient.onGuiAction = (data) => _handleGuiAction(data);
        // §7.1 LD-2 / §7.5: see [refreshPendingSecurityRequests] doc for why
        // these funnel through the shared handlers instead of setting
        // per-transport UI logic here.
        ipcClient.onDevicePairRequest = (deviceIdHex) {
          unawaited(_handleDevicePairRequest(deviceIdHex));
        };
        ipcClient.onRotationApprovalRequest =
            (hashHex, requesterHex, kind, newDeviceNodeIds) {
          unawaited(_handleRotationApprovalRequest(
              hashHex, requesterHex, kind, newDeviceNodeIds));
        };
        ipcClient.onRotationCoAuthWarning =
            (contactHex, displayName, tokensPresent, tokensRequired) {
          _handleRotationCoAuthWarning(
              contactHex, displayName, tokensPresent, tokensRequired);
        };
        // S360: not assigned until today — the IPC client parsed both
        // events (`ipc_client.dart:637`, `:662`) and called into a
        // null callback.
        ipcClient.onContactIdentityRotated =
            (contactHex, displayName, wasVerified) {
          _handleContactIdentityRotated(
              contactHex, displayName, wasVerified);
        };
        ipcClient.onRotationRejectionAlert = (contactHex, displayName) {
          _handleRotationRejectionAlert(contactHex, displayName);
        };
        // §19.6: Desktop update notification from daemon via IPC
        ipcClient.onUpdateAvailable = (manifest, inNetworkAvailable) {
          final prev = _availableUpdateManifest;
          if (prev != null &&
              !UpdateChecker().isNewer(manifest.version, prev.version)) {
            return;
          }
          _availableUpdateManifest = manifest;
          _availableUpdateInNetwork = inNetworkAvailable;
          _updateBannerDismissed = false;
          notifyListeners();
        };
        ipcClient.onUpdateStateChanged = (state, progress) {
          _guiUpdateLog('state: ${_updateState.name} -> ${state.name} (progress=$progress)');
          _updateState = state;
          _updateProgress = progress;
          notifyListeners();
        };
        ipcClient.onDaemonDied = () {
          _guiUpdateLog('onDaemonDied: updateState=${_updateState.name}, applyPending=$_updateApplyPending');
          if (_updateApplyPending || _updateState == BinaryUpdateState.ready) {
            _guiUpdateLog('Daemon restarting for update — spawning GUI restart helper');
            _spawnGuiRestartHelper();
            return;
          }
          debugPrint('[main] Daemon process gone — logging crash info before exit');
          unawaited(_logDaemonCrashAndExit());
        };
        ipcClient.onIpcStalled = () {
          _guiUpdateLog('onIpcStalled: updateState=${_updateState.name}, applyPending=$_updateApplyPending');
          if (_updateApplyPending || _updateState == BinaryUpdateState.ready) {
            _guiUpdateLog('IPC stalled during update — spawning GUI restart helper');
            _spawnGuiRestartHelper();
            return;
          }
          debugPrint('[main] IPC stalled (daemon alive) — re-arming retry');
          _ipcClient = null;
          _service = null;
          _isInitialized = false;
          // ── P-12: `_hasProfile` IS A STATEMENT ABOUT THE DISK ────
          //
          // The switch was set ONCE to `true` at start
          // (`_hasProfile = true` in `initialize()` and in `initState`)
          // and NEVER measured again afterwards. As long as the daemon could only delete
          // an identity when a second one remained, that did
          // not show. With the remote deletion of the LAST identity
          // (owner decision (b)) the daemon stops its services, the
          // IPC socket falls, this branch runs — and the UI
          // would stand permanently with `isInitialized == false` and `hasProfile == true`
          // on the `_LoadingScreen` (l. 506-512), waiting two minutes
          // for a daemon that does exactly what it
          // should. That is why it is re-measured here.
          //
          // FAIL CLOSED: `loadIdentities()` only returns `[]` if
          // there really are none — with a missing seed or broken
          // ciphertext it THROWS (`IdentitiesFileCorruptException`,
          // `identity_manager.dart:869/881`). A throw must never lead to the
          // SetupScreen: there the user would create a new profile over an
          // existing one. So `_hasProfile` stays as it was in the
          // error case.
          try {
            _hasProfile = IdentityManager().loadIdentities().isNotEmpty;
          } catch (e) {
            debugPrint('[main] identities not readable ($e) — '
                'hasProfile stays $_hasProfile');
          }
          notifyListeners();
          if (_hasProfile) {
            _scheduleRetryConnect();
          } else {
            // No profile any more: there is nothing to wait for.
            // The SetupScreen creates the next identity and calls
            // `initialize()` itself — that wakes the waiting daemon
            // via `cleona.start` (`_signalDaemonToStart`).
            _retryTimer?.cancel();
            debugPrint('[main] No identity left on disk — '
                'no reconnect, the initial setup takes over');
          }
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
        // §7.1 LD-2 / §7.5: catch-up for requests that arrived while no GUI
        // was connected to receive the live event.
        unawaited(refreshPendingSecurityRequests());
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

  /// Foreground setup, under the iOS lock.
  ///
  /// -- WHY A WRAPPER STANDS HERE (F-8, S370) ------------------------
  ///
  /// [_initInProcessBody] set the lock
  /// `IosBackgroundFetch.foregroundInitInProgress` from outside to `true`
  /// and 121 lines later from outside to `false`. In between lay three
  /// throw paths (`NodeKeys.loadOrCreate`, the `rethrow` of the
  /// EADDRINUSE loop, the `StateError` on `startV41Node == null`) and
  /// in the whole body not a single `finally`. If one throws, the
  /// lock stays for the entire process lifetime, and
  /// `ios_background_fetch.dart` afterwards leaves EVERY background run
  /// immediately with `messageCount: 0` -- while Swift acknowledges `success: true`
  /// and reschedules. The caller above (`initialize()`, `main.dart:2036-2043`)
  /// catches the throw and shows an error screen; the lock learns
  /// nothing of it.
  ///
  /// The wrapper releases it on every exit. The release in the body
  /// (directly after the node start) additionally stays: it is the
  /// EARLY release in the healthy case -- the wake-up may already
  /// run again as soon as the port is assigned, and need not wait for the
  /// service loop. Releasing twice is a no-op.
  Future<void> _initInProcess() async {
    await IosBackgroundFetch.guardForegroundInit(_initInProcessBody);
  }

  Future<void> _initInProcessBody() async {
    // -- THE REGISTRATION STANDS BEFORE EVERY RETURN (F-8, S370) -----
    //
    // `IosBackgroundFetch.init()` stood until S370 in line 2156, i.e. BEHIND
    // the return on zero identities below. Without an identity the
    // MethodChannel handler was thus not registered, and Swift called into the
    // void.
    //
    // CORRECTION OF THE FINDING, re-measured 06.09.2026: the addition "and
    // never caught up afterwards" is NOT right. `initialize()` runs at
    // program start only with identities (l. 1427-1431) and is called again after
    // `createIdentity` (`setup_screen.dart:173` and `:606`),
    // so the handler did come in the ordinary flow after all. The error is
    // real nonetheless: the registration hangs on a condition on which it
    // has no business, and an empty `loadIdentities()` for another
    // reason (read error, deletion during the run) made it drop out without replacement.
    //
    // MAY THE HANDLER BE REGISTERED WITHOUT AN IDENTITY? Measured yes, and
    // it then does the right thing: `_performBackgroundFetch` loads the identities in step 1
    // and turns back immediately on an empty list with
    // `messageCount: 0` (`ios_background_fetch.dart:292-295`), still before
    // any node start and before the time window. A cheap, correct
    // exit -- no reason to make the registration depend on it.
    if (Platform.isIOS) {
      IosBackgroundFetch.init();
    }

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
    // Kept for the network-change edge of the port mapping (task D),
    // which lies in a different method body.
    _masterSeedForHost = masterSeed;
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

    // ── THE ASSERTION FROM `NodeHost.adoptIdentities` (taken over) ──
    //
    // `adoptIdentities` threw when the passed view was empty or the
    // primary identity was missing. The reason was a field finding:
    // `_inProcessContexts.values` is a LIVE view onto a map that
    // the caller still fills. If the call stood one line too early,
    // the node came up with ZERO identities, without an
    // error standing anywhere — and afterwards discarded every frame. The registration at the
    // node has gone with `CleonaNode` (V4.1 hangs pairwise on the
    // service), THE CHECK STAYS: the loop further below that
    // calls `attachV41` runs over the same live view. If it runs
    // zero times, the delivery layer hangs on nothing, and the app is up
    // and mute.
    if (_inProcessContexts.isEmpty ||
        !_inProcessContexts.values.any((c) => identical(c, primaryCtx))) {
      throw StateError('Identity collection empty or without primary '
          'identity (all=${_inProcessContexts.length}) — the '
          'V4.1 delivery would hang on nothing.');
    }

    // GONE WITH V3: `wireEvents(onNetworkChangeDetected:)` -> ipify,
    // and `wireEvents(onPeersChanged:)` -> `service.onStateChanged`.
    // The former was the V3 address model (`main_v3_address.dart`, deleted,
    // its own header said "caller AND callee disappear
    // together"). The latter was the signal by which the UI learned of
    // address changes; V4.1 has no producer for that today —
    // reported gap.

    // S12.5: wait for a running wake-up before the port
    // is bound.
    //
    // Setting the lock has disappeared from here with S370 -- it is
    // now taken by the wrapper [_initInProcess] and released there in the `finally`.
    // `IosBackgroundFetch.init()` has moved to the beginning of this
    // body, before the return on zero identities.
    //
    // The wait loop stays HERE, because it is bound to the port and
    // not to the registration: it must stand immediately before `startV41Node`.
    // Limited to 60 x 500 ms = 30 s -- the longest bounded path
    // in the held section, and the calculation behind the hold deadline in
    // `ios_background_fetch.dart`.
    if (Platform.isIOS && IosBackgroundFetch.isFetching) {
      debugPrint('[main] BG-fetch running — waiting for port release...');
      for (var i = 0; i < 60 && IosBackgroundFetch.isFetching; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // ── THE V3 RECEIVING SIDE IS GONE (CUT, 31.08.) ────────────────────
    //
    // Here stood ~165 lines: `host.wireReceive(...)` with the
    // ApplicationFrame dispatcher (KEM try loop over all hosted
    // identities, `serviceRecency` heuristic) and the infrastructure
    // switch with 22 `MessageTypeV3` selectors.
    //
    // It is a selector list over a wire that no longer exists:
    // `InfrastructureFrameV3`/`NetworkPacketV3` arose in
    // `CleonaNode`, and the handlers on the service side fell with the ten
    // `cleona_service_v3_*.dart`.
    //
    // V4.1 receives via `attachV41` per identity (`V41Host.accept`,
    // `MessageSealer.open`, `Aggregate.unpack`). It also no longer needs the
    // ordering rule from above — the node can only
    // accept something when a service hangs on it, and `attachV41`
    // creates both in one go.

    // THE PORT OF THE DEVICE (S374, §11), 4443 as a substitute for one not yet
    // assigned. Since S387 it is bound by the mycelium host, and that
    // starts AFTER the service loop (see there).
    final gp = IdentityManager().deviceDataPort;
    final devicesPort = gp <= 0 ? 4443 : gp;

    // GONE WITH V3: `onMobileFallbackChanged`. The substitute path with
    // dead WLAN was a second socket in `Transport`; V4.1 holds ONE
    // socket set. See [isMobileFallbackActive] — reported gap, and
    // `_mobileFallbackActive` therefore stays at its initial value
    // instead of jumping to an invented one.

    // Wire Android/iOS disk space query for dynamic S&F storage budget.
    // Must be set BEFORE startService() so the initial _updateBudget()
    // in mailboxStore.load() gets the real free-disk value.
    if (Platform.isAndroid) {
      DiskSpace.platformQueryFn = (path) async {
        const ch = MethodChannel('chat.cleona/storage');
        return await ch.invokeMethod<int>('getFreeDiskSpace', path) ?? 0;
      };
    } else if (Platform.isIOS) {
      DiskSpace.platformQueryFn = (path) async {
        const ch = MethodChannel('chat.cleona/storage');
        return await ch.invokeMethod<int>('getFreeDiskSpace', path) ?? 0;
      };
    }

    // Create and start a CleonaService for EACH identity
    for (final ctx in _inProcessContexts.values) {
      final service = CleonaService(
        identity: ctx,
        displayName: ctx.displayName,
        // The device port in advance; `myceliumAttach` sets the actually
        // bound one on connection (S387).
        port: devicesPort,
      );
      // Sec H-5 / T13: inherit splash decision.
      if (_sessionReducedMode) service.reducedMode = true;
      _wireServiceCallbacks(service);
      await service.startService();
      _inProcessServices[ctx.userIdHex] = service;
      debugPrint('[main] Service started: ${ctx.displayName} (${ctx.userIdHex.substring(0, 16)}...)');
    }

    // ── THE ONE HOST, ONE MAILBOX PER IDENTITY (S387) ─────────────
    //
    // Replaces `startV41Node` + `attachV41` per identity. AFTER the
    // service loop, because the host collects and delivers immediately at start.
    //
    // The EADDRINUSE retry stays: the iOS background run
    // (`ios_background_fetch.dart`) binds THE SAME port and can still hold it briefly after
    // tearing down.
    //
    // INTO THE LOG FILE, NOT ONLY TO LOGCAT (30.08.): on Android
    // `debugPrint` only goes into the rotating logcat ring.
    final hostLog = CLogger.get('mycelium', profileDir: firstId.profileDir);
    // W1 (S391): the cover rate follows the same network kind as the update gate.
    network_metered.mobilMetered = () async =>
        _meteredDetermine(await Connectivity().checkConnectivity());
    for (var attempt = 0;; attempt++) {
      try {
        _host = await hostStart(
          services: _inProcessServices.values.toList(),
          baseDir: _baseDir,
          key: hostKey(_baseDir, masterSeed),
          port: devicesPort,
          report: hostLog.info,
        );
        break;
      } on SocketException catch (e) {
        if (attempt < 2 && '$e'.contains('errno = 48')) {
          debugPrint('[main] Port in use (attempt ${attempt + 1}/3), '
              'retrying in 2s...');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        rethrow;
      }
    }
    debugPrint('[main] mycelium host started on port ${_host!.port}');
    // The moment "start" (S388): ONE service per process carries the update.
    attachUpdateToService(_host!, _inProcessServices.values.first,
        report: hostLog.info);
    // The port mapping (task D, §7.3): asked at this edge, NOT
    // awaited — the RFC 6886 backoff takes in the worst case
    // eight and a half minutes, and the node start must not wait for it.
    unawaited(() async {
      try {
        await portMappingToEdge(
          _host!,
          baseDir: _baseDir,
          key: hostKey(_baseDir, _masterSeedForHost),
          report: hostLog.info,
        );
      } catch (e) {
        debugPrint('[main] port mapping: $e');
      }
    }());
    // The release in the healthy case: the port is assigned, a wake-up
    // may run again. The `finally` wrapper in [_initInProcess] releases
    // the same hold once more on every exit — releasing twice
    // is a no-op.
    IosBackgroundFetch.releaseForegroundInitEarly();
    // The HTTP delivery at the host port (§26.6.5, S386 part A).
    _delivery = await deliveryForServices(
        _host!, _inProcessServices.values,
        report: hostLog.info);

    // Process any crashes that occurred before services were ready (§9.5)
    _processPendingCrashes();

    // §19.6: mark previous update as healthy after 30s of stable running.
    Timer(const Duration(seconds: 30), () {
      BinaryUpdateManager.markUpdateHealthy(null);
    });


    // Save updated nodeIdHex values
    mgr.saveIdentities(identities);

    // Set active service (based on IdentityManager selection)
    final activeId = IdentityManager().getActiveIdentity();
    final activeHex = activeId?.nodeIdHex ?? primaryCtx.userIdHex;
    _service = _inProcessServices[activeHex] ?? _inProcessServices.values.first;

    _isInitialized = true;
    _startConnectivityMonitor();
    // `_queryPublicIp()` (§27, ipify) lay in `main_v3_address.dart` and
    // is deleted with the V3 address model — the file header itself said
    // "caller AND callee disappear together". V4.1 determines
    // its announceable addresses without a third-party service
    // (`dialableLocalAddresses`, filtered against DS-Lite/CGNAT/link-local,
    // B-26). What is NOT replaced: the public address behind symmetric NAT
    // confirmed via NAT probe — reported gap.
    navigatorKey = GlobalKey<NavigatorState>();
    notifyListeners();
    // §7.1 LD-2 / §7.5: catch-up for requests that arrived while no GUI was
    // connected to receive the live event.
    unawaited(refreshPendingSecurityRequests());
    // Precache the active skin's hero image after the first home-screen frame.
    _scheduleSkinPrecache(activeId?.skinId);

    // In-process heartbeat — liveness diagnostics for the main Dart
    // isolate. On Linux/Windows the equivalent lives in
    // lib/service_daemon.dart (commit a13b490); on mobile/macOS the node runs
    // in-process in the UI isolate, so we add the same Timer.periodic(5s)
    // drift-detector here. Logs to `[heartbeat]` via the primary service's
    // CLogger so entries land in the identity's daily log AND in logcat
    // (INFO level not filtered). Relevant for #U17 hotel WLAN crashes and
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
        // §12.5 S254: refresh the timed WakeLock every 5s so the CPU stays
        // active as long as the Dart isolate is alive. The 30s timeout on
        // the Kotlin side acts as a dead-man switch if ticks stop arriving.
        try {
          const channel = MethodChannel('chat.cleona/service');
          channel.invokeMethod('acquireWakeLock');
        } catch (_) {}
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
    // S362: an identity that did not yet exist at start (newly
    // created or restored from the registry) would have no
    // media key here and its attachments would stay invisible.
    // `register` is idempotent, the run costs one HKDF per identity.
    await _mediaDepositRegister();
    if (_ipcClient != null && identity.nodeIdHex != null) {
      final ok = await _ipcClient!.switchIdentity(identity.nodeIdHex!);
      debugPrint('[switchIdentity] IPC result=$ok '
          'service.nodeIdHex=${_ipcClient!.nodeIdHex.substring(0, 8)}');
      if (ok) {
        IdentityManager().setActiveIdentity(identity);
        notifyListeners();
        _scheduleSkinPrecache(identity.skinId);
        // §7.1 LD-2 / §7.5: these lists are per-identity daemon state — a
        // switch without this would keep showing the PREVIOUS identity's
        // pending requests until the next live event happened to refresh.
        unawaited(refreshPendingSecurityRequests());
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
        unawaited(refreshPendingSecurityRequests());
        return;
      }
      debugPrint('[switchIdentity] WARNING: in-process switch FAILED — '
          'nodeIdHex ${identity.nodeIdHex!.substring(0, 8)} not in '
          '[${_inProcessServices.keys.map((k) => k.substring(0, 8)).join(", ")}]');
    }

    debugPrint('[switchIdentity] FALLTHROUGH: both IPC and in-process switch '
        'failed — NOT persisting to avoid wrong-identity-key corruption');
    return;
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
    // P-12: the host hooks onto the remote deletion. NOT in the stack of the
    // frame that brought the report — `onIdentityDeletedRemotely`
    // is called synchronously from within `_handleTwinIdentityDeleted`, and
    // the body stops exactly the service whose receive path still lies on the
    // stack. `Future(…)` puts the work at the END of the
    // event queue (not `Future.microtask`, which would still run into the
    // current continuation).
    service.onIdentityDeletedRemotely = (id) {
      unawaited(Future(() => _identityFernDeleted(id)));
    };
    service.onJuryRequestReceived = (_) => notifyListeners();
    service.onIncomingGroupCall = (call) => _showIncomingGroupCallScreen(call);
    service.onGroupCallStarted = (_) => notifyListeners();
    service.onGroupCallEnded = (_) => notifyListeners();

    // §7.1 LD-2 / §7.5: in-process mode wires one [CleonaService] per
    // identity (unlike IPC, which only ever forwards events for whichever
    // identity is currently switched-to server-side — see
    // `IpcClient._handleEvent`'s identityId filter). `_pendingPairRequests` /
    // `_pendingRotationApprovals` are refreshed from `_service` (the ACTIVE
    // identity) elsewhere, so acting on an event from a BACKGROUND identity's
    // `service` here would refresh/act against the wrong identity's request.
    // Mirror the IPC behaviour instead: silently drop events for identities
    // that are not currently active. A background identity's request is not
    // lost — it stays queryable via `getPendingPairRequests()` /
    // `getPendingRotationApprovals()` once the user switches to it.
    service.onDevicePairRequest = (deviceIdHex) {
      if (!identical(service, _service)) return;
      unawaited(_handleDevicePairRequest(deviceIdHex));
    };
    service.onRotationApprovalRequest =
        (hashHex, requesterHex, kind, newDeviceNodeIds) {
      if (!identical(service, _service)) return;
      unawaited(_handleRotationApprovalRequest(
          hashHex, requesterHex, kind, newDeviceNodeIds));
    };
    service.onRotationCoAuthWarning =
        (contactHex, displayName, tokensPresent, tokensRequired) {
      if (!identical(service, _service)) return;
      _handleRotationCoAuthWarning(
          contactHex, displayName, tokensPresent, tokensRequired);
    };
    // S360: the same gap as on the IPC path next to it. Same
    // background identity lock as the neighbours — an event of a
    // NON-active identity does not belong in the banners of the active one.
    service.onContactIdentityRotated =
        (contactHex, displayName, wasVerified) {
      if (!identical(service, _service)) return;
      _handleContactIdentityRotated(contactHex, displayName, wasVerified);
    };
    service.onRotationRejectionAlert = (contactHex, displayName) {
      if (!identical(service, _service)) return;
      _handleRotationRejectionAlert(contactHex, displayName);
    };

    // §19.6: a newer signed manifest was verified (any newer version, not
    // only hard-blocking ones) and — if it carries a DHT binary tag — the
    // in-network binary-distribution availability has already been checked.
    // Store both so the UI can offer the in-network path alongside the
    // external downloadUrl. See [_availableUpdateManifest].
    service.onUpdateAvailable = (manifest, inNetworkAvailable) {
      // S387: collecting begins without user action — the offer
      // decides whether (newer target, or the same one without a result).
      _updateOffer.onManifest(service, manifest, inNetworkAvailable);
      final prev = _availableUpdateManifest;
      if (prev != null &&
          !UpdateChecker().isNewer(manifest.version, prev.version)) {
        return;
      }
      _availableUpdateManifest = manifest;
      _availableUpdateInNetwork = inNetworkAvailable;
      _availableUpdateSourceService = service;
      _updateBannerDismissed = false;
      notifyListeners();
    };
    // S387: collecting happens automatically, installing ONLY after the click
    // ([applyUpdate]). Here stood `if (state == ready) applyUpdate();` —
    // right as long as `ready` only came after the download click.
    service.onUpdateStateChanged = (state, progress) {
      _updateOffer.onState(service, state);
      if (!identical(_updateOffer.source, service)) return;
      _updateState = state;
      _updateProgress = progress;
      notifyListeners();
    };

    // V2.3: video engine factory. No longer needs dart:ui — VideoEngine uses
    // VideoPipeline (V0.3), so the daemon can load it too. Desktop video
    // calls are no longer silently audio-only.
    service.createVideoEngine = (sharedSecret, onFrame) =>
        _createVideoEngine(sharedSecret, onFrame);

    // V3.2 / §10.4 stage 7: CallKit (iOS) and the self-managed
    // ConnectionService (Android). Constructed here rather than inside
    // CallService because the MethodChannel implementation pulls in dart:ui,
    // which would break `dart compile exe lib/service_daemon.dart`. The daemon
    // keeps the no-op, which is correct there: it has no system call UI.
    service.callIntegration = MethodChannelCallIntegration();

    // §10.4 "Session behaviour" (V1.10, S367): AudioFocus / interruption
    // handling + earpiece-only proximity monitoring. Android
    // (MainActivity.kt + CleonaForegroundService.kt) and iOS
    // (SessionBehaviourHandler.swift) are the only platforms with a native
    // handler on `chat.cleona/session_behaviour` (measured: no macOS/Linux/
    // Windows counterpart exists) — wiring it unconditionally would throw
    // MissingPluginException out of CallService's unawaited
    // onRequestAudioFocus/onAbandonAudioFocus calls on those platforms.
    if (Platform.isAndroid || Platform.isIOS) {
      SessionBehaviourChannel.ensureHandlerInstalled();
      SessionBehaviourChannel.onInterruption = (event, endInfo) {
        service.feedVoiceInterruptionEvent(event);
      };
      service.onRequestAudioFocus = SessionBehaviourChannel.requestAudioFocus;
      service.onAbandonAudioFocus = SessionBehaviourChannel.abandonAudioFocus;
      service.onSetProximityMonitoring = (enabled) {
        SessionBehaviourChannel.setProximityMonitoring(enabled);
      };
    }

    service.onVideoUnavailable = (reason) {
      debugPrint('[video] $reason');
    };

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
      service.notificationSound.onStartLoopSoundAndroid = (asset) async {
        const channel = MethodChannel('chat.cleona/notification');
        await channel.invokeMethod('startLoopSound', {'asset': asset});
      };
      service.notificationSound.onStopSoundAndroid = () async {
        const channel = MethodChannel('chat.cleona/notification');
        await channel.invokeMethod('stopSound');
      };

      // Vibration via platform channel
      service.notificationSound.onVibrateAndroid = (durationMs) async {
        const channel = MethodChannel('chat.cleona/vibration');
        await channel.invokeMethod('vibrate', {'duration': durationMs});
      };

      service.onSetCallAudioModeAndroid = (speaker) {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('setCallAudioMode', {'speaker': speaker});
      };
      service.onResetCallAudioModeAndroid = () {
        const channel = MethodChannel('chat.cleona/notification');
        channel.invokeMethod('resetCallAudioMode');
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

  /// V2.3: constructs the [VideoEngine] behind [CleonaService.createVideoEngine].
  /// No dart:ui, no Isolate, no pixel conversions — the native backend
  /// (VideoPipeline V0.3) handles capture, H.264 encode/decode, and renders
  /// into a texture that Flutter's Texture widget displays directly (I10).
  dynamic _createVideoEngine(
      Uint8List sharedSecret, void Function(Uint8List) onFrame) {
    // A-5: pass profileDir through, otherwise the VideoEngine logs into no
    // log file (see VideoEngine constructor). `_baseDir` is the same
    // directory that is already used above as profileDir.
    final engine =
        VideoEngine(sharedSecret: sharedSecret, profileDir: _baseDir);
    engine.onVideoFrame = onFrame;

    engine.onVideoShutdown = (reason, detail) {
      debugPrint('[video] shutdown: $detail');
      onRemoteVideoTextureChanged?.call(null);
    };

    engine.onCaptureStop = () {
      onRemoteVideoTextureChanged?.call(null);
    };

    unawaited(engine.start().then((ok) {
      if (!ok) {
        debugPrint('[video] VideoEngine.start() failed — audio-only');
        return;
      }
      onRemoteVideoTextureChanged?.call(engine.textureId);
    }));

    return engine;
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
    // UNREGISTER THE MAILBOX OF THIS IDENTITY (S387). Without this line
    // the host would keep delivering to a stopped service.
    final host = _host;
    if (host != null && service != null) {
      serviceDeregister(host, service, report: debugPrint);
    }

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

    // Android: in-process — broadcast IDENTITY_DELETED before cleanup
    if (_inProcessServices.isNotEmpty) {
      final svc = _inProcessServices[nodeIdHex];
      if (svc != null) {
        try {
          await svc.broadcastIdentityDeleted().timeout(const Duration(seconds: 15));
        } catch (_) {}
      }
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

  /// §6.4.3: Recover additional identities from DHT registry after seed restore.
  /// Fire-and-forget — runs in background, notifies UI when done.
  Future<void> recoverIdentitiesFromRegistry() async {
    // Linux: delegate to daemon via IPC
    if (_ipcClient != null) {
      final count = await (_ipcClient as IpcClient).recoverIdentitiesFromRegistry();
      if (count > 0) {
        debugPrint('[main] Registry recovery: $count identities restored via IPC');
        notifyListeners();
      }
      return;
    }

    // Android: in-process
    final svc = _service;
    final host = _host;
    if (svc is CleonaService && host != null) {
      final created = await svc.recoverIdentitiesFromRegistry();
      if (created.isNotEmpty) {
        final mgr = IdentityManager();
        final masterSeed = mgr.loadMasterSeed();
        for (final identity in created) {
          final ctx = await IdentityContext.createFromIdentity(
            identity: identity,
            baseDir: _baseDir,
            masterSeed: masterSeed,
          );
          final ids = mgr.loadIdentities();
          for (final id in ids) {
            if (id.id == identity.id) {
              id.nodeIdHex = ctx.userIdHex;
              break;
            }
          }
          mgr.saveIdentities(ids);
          _inProcessContexts[ctx.userIdHex] = ctx;
          final service = CleonaService(
            identity: ctx,
            displayName: identity.displayName,
            port: host.port,
          );
          if (_sessionReducedMode) service.reducedMode = true;
          _wireServiceCallbacks(service);
          await service.startService();
          // CATCH UP THE MAILBOX (S387) — otherwise this identity would have
          // no network, and that silently. First the service, then the
          // connection: the connection collects immediately.
          serviceRegister(host, service);
          _inProcessServices[ctx.userIdHex] = service;
        }
        debugPrint('[main] Registry recovery: ${created.length} identities restored in-process');
        notifyListeners();
      }
    }
  }

  Future<void> _handleGuiAction(Map<String, dynamic> data) async {
    final action = data['action'] as String?;
    if (action == null) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      debugPrint('[gui_action] $action DROPPED: navigatorKey.currentState=null');
      return;
    }

    switch (action) {
      case 'open_identity_detail':
        final idParam = data['identityId'] as String?;
        final identity = idParam != null
            ? IdentityManager().loadIdentities().firstWhereOrNull(
                (i) => i.nodeIdHex == idParam || i.id == idParam)
            : IdentityManager().getActiveIdentity();
        if (identity == null) {
          debugPrint('[gui_action] open_identity_detail DROPPED: '
              'identity=null (idParam=$idParam, '
              'identityCount=${IdentityManager().loadIdentities().length})');
          break;
        }
        if (_service == null) {
          debugPrint('[gui_action] open_identity_detail DROPPED: _service=null');
          break;
        }
        nav.push(MaterialPageRoute(
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: this),
              if (_appLocale != null) ChangeNotifierProvider.value(value: _appLocale!),
            ],
            child: IdentityDetailScreen(service: _service!, identity: identity),
          ),
        ));
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
          // S363, point 1 (option D): on Android the 24 words lie
          // behind the device-code lock; `loadSeedPhrase()` no longer sees them
          // there. On all other platforms
          // `loadSeedPhraseGated` returns the same value as before.
          // The same design as in the status line further above: `_appLocale`
          // is nullable here, and a missing locale returns the
          // key instead of a German line.
          final loc = _appLocale;
          String t(String key) => loc == null ? key : loc.get(key);
          final access = await IdentityManager().loadSeedPhraseGated(
            title: t('seed_phrase_gate_title'),
            description: t('seed_phrase_gate_description'),
          );
          // The `await` above has produced a time jump (the user was in the
          // system dialog). The navigator may be gone by now.
          if (!nav.mounted) break;
          final words = access.words;
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
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    AppLocale.read(dialogCtx)
                                        .get('recovery_phrase_never_share'),
                                    style: const TextStyle(fontSize: 13))),
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
            // The reason belongs in the dialog. Three exits that a
            // user otherwise cannot place: abort, removed
            // screen lock, and "nothing lies on this device" (after
            // a reinstallation the normal case — the keyring is
            // app-bound, measured in
            // `docs/v4-redesign/S363-messung-schluesselbund.md`, 5.1).
            final String reason;
            switch (access.outcome) {
              case GateOutcome.cancelled:
                reason = t('seed_phrase_gate_cancelled');
                break;
              case GateOutcome.invalidated:
                reason = t('seed_phrase_gate_invalidated');
                break;
              case GateOutcome.absent:
                // NOT `hasDeviceGate` — the statement is "the
                // keyring falls with the app installation", and
                // that holds on both mobile platforms; the
                // device-code lock only exists on Android.
                reason = IdentityManager().hasAppBoundKeyring
                    ? t('seed_phrase_absent_device')
                    : t('no_recovery_phrase');
                break;
              default:
                reason = t('no_recovery_phrase');
            }
            showDialog(
              context: nav.context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text('Recovery Phrase'),
                content: Text(reason),
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
                CLogger.get('nat-wizard', profileDir: svc.profileDir)
                    .info('loading RouterDb...');
                final routerDb = await RouterDb.load();
                final navNow = navigatorKey.currentState;
                if (navNow == null || !navNow.mounted) {
                  CLogger.get('nat-wizard', profileDir: svc.profileDir)
                      .warn('navigator state gone after RouterDb.load');
                  return;
                }
                // UPnP DETECTION DOES NOT EXIST IN V4.1 (gap G-12). Here stood
                // `svc.getNetworkStats().upnpRouterInfo`; the field fell on
                // 01.09.2026 (S360), because it had no filler any more
                // and was permanently `null`. The user chooses his
                // model from the list — the preselection has gone, the
                // instructions have not.
                const UpnpRouterInfo? detectedInfo = null;
                CLogger.get('nat-wizard', profileDir: svc.profileDir)
                    .info('pushing NatWizardRouterSelectScreen');
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
      final host = _host;
      if (host != null) {
        final mgr = IdentityManager();
        final identity = await mgr.createIdentity(displayName);
        final ctx = await IdentityContext.createFromIdentity(
          identity: identity,
          baseDir: _baseDir,
          masterSeed: mgr.loadMasterSeed(),
        );

        _inProcessContexts[ctx.userIdHex] = ctx;

        final service = CleonaService(
          identity: ctx,
          displayName: displayName,
          port: host.port,
        );
        // Sec H-5 / T13: inherit splash decision for newly added identities.
        if (_sessionReducedMode) service.reducedMode = true;
        _wireServiceCallbacks(service);
        await service.startService();
        // As above: without a mailbox the new identity would be mute (S387).
        serviceRegister(host, service);
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

  /// Stops the mycelium host of this process and closes the
  /// HTTP delivery (S387).
  ///
  /// PULLED OUT OF `dispose()` (S377, P-12), because there is a SECOND
  /// caller: the remote deletion of the last identity. `stop`
  /// saves the neighbours and closes wire and state checker — an
  /// open timer would keep the Dart VM alive.
  void _hostStop() {
    _delivery?.close();
    _delivery = null;
    // The port mapping (task D): MANDATORY before stopping — its
    // own renewal timer otherwise keeps the Dart VM alive. Like
    // `_auslieferung?.close()` next to it not awaited: `_wirtStoppen`
    // is synchronous (callers include `State.dispose()`, which allows no
    // asynchronous override).
    final hostBeforeTheStop = _host;
    if (hostBeforeTheStop != null) {
      unawaited(portMappingLayDown(hostBeforeTheStop));
    }
    _host?.stop();
    _host = null;
  }

  // ── P-12: THE REMOTE DELETION ALSO NEEDS A LISTENER IN-PROCESS ──
  //
  // The in-process path (Android/iOS) is the second host next to
  // `service_daemon.dart`. Without this branch the gap would stay open on a
  // release platform: the service clears up, reports upwards, and
  // the identity would stay in `identities.json` and in the process.
  //
  // Body and reasoning stand in `identity_remote_deletion.dart`;
  // here stands only what belongs to THIS host: the running service, the
  // active identity and the screen state.
  Future<void> _identityFernDeleted(String nodeIdHex) async {
    try {
      final profileDir = _inProcessContexts[nodeIdHex]?.profileDir;

      // First unregister and stop, then delete — otherwise the still
      // running service would create `messages.db` anew in the just deleted directory.
      // The same steps as `deleteIdentityAndroid`, but WITHOUT
      // its gate `_inProcessServices.length <= 1` (owner
      // decision (b) of 09.09.2026) and without a broadcast to the contacts
      // (the deletion came from outside, working rule #5).
      final service = _inProcessServices.remove(nodeIdHex);
      final warActive = identical(_service, service);
      if (service != null) {
        await service.stop();
      }
      _inProcessContexts.remove(nodeIdHex);
      // Unregister the mailbox (S387). The last one stays at the node until
      // `_wirtStoppen` below stops the whole host.
      final host = _host;
      if (host != null && service != null) {
        serviceDeregister(host, service, report: debugPrint);
      }

      final remaining = remoteDeletionRemoveEntry(
        nodeIdHex: nodeIdHex,
        mgr: IdentityManager(),
        profileDir: profileDir,
        log: (m) => debugPrint('[fernloeschung] $m'),
      );

      if (remaining == 0) {
        // The transition into "zero identities" — the counterpart to
        // `stopAll()` in the daemon. The node MUST fall: `initialize()`
        // binds the port again at the next attempt
        // (`_initInProcessBody` -> `startV41Node`), and a still
        // bound socket would turn that into a start error.
        _hostStop();
        _service = null;
        // `_isInitialized` and `_hasProfile` are the two switches
        // from which `CleonaApp` chooses its screen (`main.dart`
        // l. 506-512). Both false means: SetupScreen. That is the
        // right state — `SetupScreen` creates NO new one when a seed exists
        // (`setup_screen.dart:143`
        // `if (!identityMgr.hasMasterSeed())`), but derives the
        // next identity from the existing one.
        _isInitialized = false;
        _hasProfile = false;
      } else if (warActive) {
        _service = _inProcessServices.values.firstOrNull;
        final mgr = IdentityManager();
        final firstRemaining = mgr.loadIdentities().firstOrNull;
        if (firstRemaining != null) {
          mgr.setActiveIdentity(firstRemaining);
        }
      }
      notifyListeners();
    } catch (e, s) {
      // Visible, not silent: this is a deletion path.
      debugPrint('[remote-deletion] FAILED for $nodeIdHex: $e\n$s');
    }
  }

  @override
  void dispose() {
    _appLocale?.removeListener(_uiLanguageReport);
    _showTriggerTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _networkChangeDebounce?.cancel();
    _connectivitySub?.cancel();
    final home = AppPaths.home;
    try { File('$home/.cleona/gui.lock').deleteSync(); } catch (_) {}
    if (_ipcClient != null) {
      // Prevent onDaemonDied from firing during intentional GUI close
      _ipcClient!.onDaemonDied = null;
      _ipcClient!.disconnect();
    } else if (_inProcessServices.isNotEmpty) {
      // In-process: THE HOST FIRST (S387), then the services — the other way round
      // the still running host would deliver to a stopped service.
      _hostStop();
      for (final service in _inProcessServices.values) {
        service.stop();
      }
      _inProcessServices.clear();
      _inProcessContexts.clear();
    } else if (_service is CleonaService) {
      (_service as CleonaService).stop();
    }
    super.dispose();
  }
}

// The addresses that the V4.1 entry calls in addition to the broadcast
// (B-27, S349) came here until S351 from `svc.node.routingTable.allPeers` —
// the V3 node. That was exactly the grip against which `smoke_seam_node_
// member_guard` (AP-1 step 7) stands: the V4.1 entry cascade talked
// past the V3 transport instead of replacing it as planned. Since the
// persistent entry supply (`95b2b104`) the same purpose without V3 gives
// the same information — moved to `lib/core/tagline/v41_attach.dart`
// (`vorratUnicastTargets`), source now `v41.entries.dialCandidates()`.
