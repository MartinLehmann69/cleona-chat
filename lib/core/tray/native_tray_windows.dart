// ignore_for_file: constant_identifier_names, camel_case_types
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:cleona/core/log/redacted_console.dart';
import 'package:cleona/core/service/readiness_names.dart';
import 'package:cleona/core/tray/tray_status.dart';
import 'package:cleona/core/tray/windows_tray_thread.dart';

// ── WHO OWNS WHAT (S423 B-5) ────────────────────────────────────────
//
// The hidden tray window, its message loop, the icon handles and every
// `Shell_NotifyIconW` call live on ONE native thread in cleona_tray.dll
// (windows/cleona_tray/cleona_tray.c, binding windows_tray_thread.dart).
// Until S423 this file created the window itself, on whatever Dart
// thread-pool worker ran `init`; when that worker ended after 5 s idle,
// Windows freed the window and with it the icon (lab 14.11.2026:
// `NIM_MODIFY rejected … window alive=false`, 7 s after `NIM_ADD`). This
// file keeps what needs no thread: the record (NOTIFYICONDATAW), the texts,
// the menu content, the decisions — and hands each change to the thread.
// It creates no window and pumps no messages; the guard
// `smoke_tray_windows_modify_measure.dart` keeps it that way.

// ── Win32 constants ─────────────────────────────────────────────────
const _NIM_ADD = 0x00000000;
const _NIM_MODIFY = 0x00000001;
const _NIF_MESSAGE = 0x00000001;
const _NIF_ICON = 0x00000002;
const _NIF_TIP = 0x00000004;
const _WM_APP = 0x8000;
// The icon's callback message. The tray thread sets the same value itself
// (TRAY_MSG_CALLBACK in cleona_tray.c); written here so the record is
// complete as built.
const _WM_TRAYICON = _WM_APP + 1;
const _LR_LOADFROMFILE = 0x0010;
const _LR_DEFAULTSIZE = 0x0040;
// GetSystemMetrics: edge length of the SMALL icon. Exactly the size
// that the notification area displays.
const _SM_CXSMICON = 49;
const _SM_CYSMICON = 50;

// Menu item IDs. The tray thread reports the chosen one through the event
// callback; 1001 doubles as the double-click event (kTrayEventShow).
const _IDM_SHOW = kTrayEventShow;
const _IDM_STOP = 1002;
const _IDM_START = 1003;
const _IDM_QUIT = 1004;

// GetSystemMetrics — any thread may ask it; it creates nothing.
typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsDart = int Function(int);

// S425 T-1 measurement: where the tray window lives (window station,
// desktop, session), so the E2E probe can be compared against it.
typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);
typedef _GetThreadDesktopC = IntPtr Function(Uint32);
typedef _GetThreadDesktopDart = int Function(int);
typedef _GetProcessWindowStationC = IntPtr Function();
typedef _GetProcessWindowStationDart = int Function();
typedef _GetUserObjectInformationWC = Int32 Function(
    IntPtr, Int32, Pointer<Uint16>, Uint32, Pointer<Uint32>);
typedef _GetUserObjectInformationWDart = int Function(
    int, int, Pointer<Uint16>, int, Pointer<Uint32>);
typedef _ProcessIdToSessionIdC = Int32 Function(Uint32, Pointer<Uint32>);
typedef _ProcessIdToSessionIdDart = int Function(int, Pointer<Uint32>);

/// `Tray window 0x… of thread N on <station>\<desktop>, session S` — the
/// daemon's side of the S425 T-1 measurement. UOI_NAME = 2 (Microsoft Learn,
/// GetUserObjectInformationW). Never throws.
String trayWindowWhereLine(int hwnd) {
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final threadOf = user32.lookupFunction<_GetWindowThreadProcessIdC,
        _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
    final desktopOf = user32.lookupFunction<_GetThreadDesktopC,
        _GetThreadDesktopDart>('GetThreadDesktop');
    final station = user32.lookupFunction<_GetProcessWindowStationC,
        _GetProcessWindowStationDart>('GetProcessWindowStation');
    final info = user32.lookupFunction<_GetUserObjectInformationWC,
        _GetUserObjectInformationWDart>('GetUserObjectInformationW');
    final sessionOf = kernel32.lookupFunction<_ProcessIdToSessionIdC,
        _ProcessIdToSessionIdDart>('ProcessIdToSessionId');
    final buf = calloc<Uint16>(256);
    final need = calloc<Uint32>();
    final sid = calloc<Uint32>();
    try {
      String name(int handle) {
        if (handle == 0 || info(handle, 2, buf, 512, need) == 0) return '?';
        return buf.cast<Utf16>().toDartString();
      }
      final tid = threadOf(hwnd, nullptr);
      final desk = name(desktopOf(tid));
      final sta = name(station());
      final session = sessionOf(pid, sid) != 0 ? '${sid.value}' : '?';
      return 'Tray window 0x${hwnd.toRadixString(16)} of thread $tid on '
          '$sta\\$desk, session $session';
    } finally {
      calloc.free(buf);
      calloc.free(need);
      calloc.free(sid);
    }
  } catch (e) {
    return 'Tray window 0x${hwnd.toRadixString(16)}: where-probe failed (${e.runtimeType})';
  }
}

// ── NOTIFYICONDATAW struct (simplified, 64-bit) ─────────────────────
// We use a raw byte buffer since Dart FFI structs can't easily handle
// the complex NOTIFYICONDATAW with its embedded arrays. cleona_tray.c fails
// its build when sizeof(NOTIFYICONDATAW) is not this number, and rejects any
// other cbSize at run time.
const _NOTIFYICONDATAW_SIZE = 976; // sizeof(NOTIFYICONDATAW) on 64-bit

/// The context menu as handed to the tray thread (`cleona_tray_set_menu`).
///
/// Lines separated by `\n`; a line `-` is a separator, every other line is
/// `<id>\t<text>`, and id 0 is an information line (greyed, not selectable).
/// The content and order are what the menu showed before S423, when it was
/// built in the window procedure of this file:
///
///   STATE LINE AT THE VERY TOP, GREYED OUT (§22.9) — information, not a
///   command; then each identity on its own greyed line (V-10-c = b, the same
///   structure as the GTK menu, so that both platforms say the same); then
///   "show", "stop" or "start" depending on the service, and "quit".
///
/// Tabs and line breaks inside a text would break the format; they become
/// spaces.
String trayMenuSpec({
  required String statusLine,
  required List<String> identityLines,
  required bool serviceRunning,
  required String localeCode,
}) {
  String clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]'), ' ');
  final lines = <String>[];
  if (statusLine.isNotEmpty) {
    lines.add('0\t${clean(statusLine)}');
    for (final line in identityLines) {
      lines.add('0\t    ${clean(line)}');
    }
    lines.add('-');
  }
  lines.add('$_IDM_SHOW\t${clean(trayTranslate('tray_menu_show', localeCode))}');
  lines.add('-');
  if (serviceRunning) {
    lines.add('$_IDM_STOP\t${clean(trayTranslate('tray_menu_stop', localeCode))}');
  } else {
    lines.add(
        '$_IDM_START\t${clean(trayTranslate('tray_menu_start', localeCode))}');
  }
  lines.add('-');
  lines.add('$_IDM_QUIT\t${clean(trayTranslate('tray_menu_quit', localeCode))}');
  return lines.join('\n');
}

/// Has the notification area accepted the icon?
///
/// `Shell_NotifyIconW` returns BOOL: non-zero means "accepted",
/// zero means "rejected". This function is the one place at which a
/// statement is made from this return value, so that it can be checked without Windows
/// (`test/smoke/smoke_tray_windows_meldung_guard.dart`).
///
/// ── WHY IT EXISTS (finding 4, S370, 06.09.2026) ───────────────────
///
/// Until S370 [NativeTrayWindows.init] simply contained
///
///     _shellNotifyIcon(_NIM_ADD, _nid);
///
/// — the return value was discarded, `init` reported `true` as soon as
/// `CreateWindowExW` had succeeded, and `service_daemon.dart` thereupon printed
/// "Tray icon: OK". Measured on 06.09.2026 on the
/// Windows build VM 192.168.10.74:
///
///   12:09:13.901399 [INFO ] [daemon] Tray icon: OK (icon: …app_icon_beta.ico)
///   PS> Get-Process cleona-daemon | Select Id,SessionId -> 5156, session 0
///   PS> Get-Process explorer     | Select Id,SessionId -> 2264, session 3
///
/// The daemon ran in session 0, the shell in session 3. There
/// `Shell_NotifyIcon` cannot create an icon — there is no notification area.
/// `CreateWindowExW` however succeeds even without a shell, and exactly on that
/// the success report relied. The Linux branch of the same class warns
/// expressly when DISPLAY is missing; the Windows branch claimed
/// success instead.
bool trayIconAccepted(int shellNotifyIconResult) => shellNotifyIconResult != 0;

/// Measurement line for a rejected `NIM_MODIFY` (S420 G3 11a, D-123).
///
/// The measurement this line carries found the cause (S423 B-5): the window
/// was gone (`window alive=false`) because the thread that had created it
/// had ended; since S423 the window lives on its own thread
/// (cleona_tray.dll). The line stays, because it is what tells a rejection
/// apart: the error code (Microsoft Learn, `Shell_NotifyIconW`: "Returns
/// TRUE if successful, or FALSE otherwise. … you can call GetLastError for
/// more specific information"), whether the owning window still exists
/// (`IsWindow`), the time since `NIM_ADD` and how many rejections in a row.
/// The error code is read by the tray thread right after its own call, on
/// the thread that made it — no Dart code runs in between. When the call
/// could not even be handed over, it is the error of the hand-over
/// (1460 = timeout, 1400 = no window).
String trayModifyRejectedLine({
  required int lastError,
  required bool windowAlive,
  required Duration sinceAdd,
  required int inARow,
}) =>
    'Shell_NotifyIcon(NIM_MODIFY) rejected — tooltip and icon stay at the '
    'old state (GetLastError=$lastError, window alive=$windowAlive, '
    '${sinceAdd.inSeconds} s after NIM_ADD, rejection $inARow in a row).';

/// Measurement line for an accepted `NIM_MODIFY`: once for the first
/// acceptance after `NIM_ADD`, and once when acceptance returns after
/// rejections — never for every accepted change (null then).
String? trayModifyAcceptedLine({
  required bool firstEver,
  required int rejectedBefore,
  required Duration sinceAdd,
}) {
  if (firstEver) {
    return 'Shell_NotifyIcon(NIM_MODIFY) accepted for the first time '
        '(${sinceAdd.inSeconds} s after NIM_ADD, after $rejectedBefore '
        'rejection(s)).';
  }
  if (rejectedBefore > 0) {
    return 'Shell_NotifyIcon(NIM_MODIFY) accepted again after '
        '$rejectedBefore rejection(s) (${sinceAdd.inSeconds} s after '
        'NIM_ADD).';
  }
  return null;
}

/// The text of the tooltip (szTip) for an unread state.
///
/// The same rule the Linux branch uses for the tray TITLE
/// (`native_tray.dart:_rebuildMenu`: `unreadCount > 0 ? '$baseName
/// ($unreadCount)' : baseName`) — the two platforms are to say the same,
/// only via different carriers.
///
/// ── WHY IT EXISTS (finding 5, S370, 06.09.2026) ───────────────────
///
/// `service_daemon.dart:1602` computes the unread sum over all
/// identities and calls `tray.updateMenu(serviceRunning:,
/// unreadCount:)`. `native_tray.dart:268-275` passed of that ONLY
/// `serviceRunning` on to the Windows tray, and
/// `NativeTrayWindows.updateMenu` had no parameter at all for `unreadCount`.
/// `_NIM_MODIFY` was not even defined as a constant in the file:
/// after `NIM_ADD` the notification area was never touched again.
/// The producer existed, the receiver did not.
///
/// [statusLine] was added with S376 (§22.9): the tooltip is under
/// Windows the only surface that shows the state WITHOUT a click. szTip
/// holds 127 characters; if the line is longer, it drops instead of
/// displacing the counter — the counter is the older promise.
String trayTooltipText(String basis, int unreadCount, [String statusLine = '']) {
  final header = unreadCount > 0 ? '$basis ($unreadCount)' : basis;
  if (statusLine.isEmpty) return header;
  final full = '$header\n$statusLine';
  return full.length <= 127 ? full : header;
}

/// Writes [text] as a null-terminated UTF-16 string into the szTip field
/// of a NOTIFYICONDATAW structure.
///
/// On a 64-bit Windows szTip lies at BYTE OFFSET 40 and holds 128
/// WCHAR. Recalculated (S370): cbSize 4 + 4 padding bytes = 8, hWnd 8 = 16,
/// uID 4 = 20, uFlags 4 = 24, uCallbackMessage 4 + 4 padding bytes = 32,
/// hIcon 8 = 40. Thus 127 characters plus terminating null are usable.
///
/// Extracted, because this pointer arithmetic is the only place with a
/// real risk of error and can be checked WITHOUT Windows — a
/// `calloc` buffer behaves the same under Linux
/// (`smoke_tray_windows_ungelesen_guard.dart`).
void writeSzTip(Pointer<Uint8> nid, String text) {
  final tipPtr = (nid + 40).cast<Uint16>();
  final units = text.codeUnits;
  final n = units.length < 127 ? units.length : 127;
  for (var i = 0; i < n; i++) {
    tipPtr[i] = units[i];
  }
  tipPtr[n] = 0;
}

/// Windows system tray implementation using Win32 Shell_NotifyIcon, carried
/// out by the tray thread of cleona_tray.dll.
class NativeTrayWindows {
  bool _initialized = false;
  final _nid = calloc<Uint8>(_NOTIFYICONDATAW_SIZE);

  /// The tray thread, once [init] has opened and started it.
  TrayThreadLibrary? _tray;

  /// The callback the tray thread reports events through. A
  /// `NativeCallable.listener` may be called from any thread; the call is
  /// posted to this isolate and returns at once, so the tray thread never
  /// waits for Dart. It is closed only after the thread has ended
  /// ([_stopThread]) — until then the thread may still call it.
  NativeCallable<TrayEventCallback>? _events;

  /// Log channel of the caller (`NativeTray.init`'s `logger`). Without it
  /// a failed `Shell_NotifyIcon` stayed mute even when the
  /// daemon keeps a log.
  void Function(String level, String msg)? _logger;

  /// The tooltip without counter, as [init] got it. Basis for
  /// [trayTooltipText] at every [updateStatus].
  String _tooltipBasis = 'Cleona Chat';

  /// Last set tooltip — prevents one `NIM_MODIFY` per call
  /// when nothing has changed. `updateStatus` comes with every
  /// incoming message.
  String? _tooltipSet;

  /// Last menu handed to the tray thread — the same reason as
  /// [_tooltipSet].
  String? _menuSet;

  /// Language of the menu items. Until S376 four German
  /// strings stood here in the code — the only surface of the product that
  /// knew none of the 34 languages.
  String _menuLocale = 'en';

  /// Loaded state icons (HICON) per readiness state.
  ///
  /// ── WHY IT EXISTS (V-10-b, owner decision 09.09.2026) ──────
  ///
  /// Until S377 the Windows tray carried its display ONLY as text: tooltip
  /// and greyed-out first menu line. The reason was no code problem,
  /// but a missing image format — `Shell_NotifyIcon` takes an
  /// HICON resource, and the images were only available as PNG. They lie
  /// additionally as `.ico` next to them (`scripts/make_tray_icos.dart`), and
  /// with that the ICON carries the state here too, as §22.9 requires for
  /// both platforms. Since S388 (E3 = A) these are three images
  /// for the three readiness states instead of five tiers.
  ///
  /// FAIL-SAFE, for the same reason as under Linux: if a file is missing
  /// or `LoadImageW` fails, it stays with the base icon and the
  /// state keeps travelling via the text. A tray that loses its icon at a
  /// state change would be worse than one
  /// that does not show the state in the icon.
  ///
  /// Loaded BY THE TRAY THREAD (`cleona_tray_load_icon`), which also
  /// destroys them (`DestroyIcon`) when it ends — after the icon has left
  /// the notification area. The base icon is destroyed there as well when
  /// it came from a file; the shared system icon of the fallback never.
  final Map<String, int> _stateSymbols = {};

  /// The base icon (HICON).
  int _trayHicon = 0;

  /// The icon last written into the structure — prevents a
  /// `NIM_MODIFY` for a change that does not exist.
  int _setSymbol = 0;

  /// The path of the state icon that the tray SHOULD show — set even
  /// when there is no notification area at all.
  ///
  /// The same design and the same reason as [intendedTooltip]: only
  /// thus can "the state reaches the Windows icon" be checked without Windows.
  /// A guard that instead measures the existence of
  /// `_zustandsSymbole` measures a proxy.
  String? intendedStateIcon;

  /// Base icon from [init] — the fallback when a state image is missing.
  String _baseIconPath = '';

  /// The EXISTING state files next to the base icon.
  ///
  /// Determined once at start and not at every state report:
  /// `updateStatus` comes at every change of the service, and an
  /// `existsSync` per change would be a system call for an answer
  /// that no longer changes at runtime.
  final Map<String, String> _statePaths = {};

  // Measurement of `NIM_MODIFY` (see [trayModifyRejectedLine]).
  final Stopwatch _sinceAdd = Stopwatch();
  bool _modifyEverAccepted = false;
  int _modifyRejectedInARow = 0;

  // Callbacks
  void Function()? onShowWindow;
  void Function()? onStop;
  void Function()? onStart;
  void Function()? onQuit;

  /// `Shell_NotifyIconW(message, nid)` — run by the tray thread, the owner
  /// of the window the record names.
  TrayNotifyResult _shellNotifyIcon(int message, Pointer<Uint8> nid) =>
      _tray!.notify(message, nid);

  bool init({
    required String iconPath,
    String tooltip = 'Cleona Chat',
    void Function(String level, String msg)? logger,
  }) {
    _logger = logger;
    _tooltipBasis = tooltip;
    _tooltipSet = tooltip;
    // BEFORE the `try` and before any Win32 binding, for the same reason as
    // [beabsichtigteKurzinfo]: "which state icon SHOULD the tray
    // show" is a true statement even when there is no Windows at all.
    // Only thus can it be checked without Windows — and it is pure
    // file system work that needs no Win32.
    _baseIconPath = iconPath;
    _statePaths.clear();
    for (final state in kReadinessNames) {
      final path =
          readinessIconSiblingPath(iconPath, state, extension: 'ico');
      if (path != null && File(path).existsSync()) {
        _statePaths[state] = path;
      }
    }
    if (_initialized) return true;

    try {
      // Outside Windows this throws (no cleona_tray.dll) and `init` reports
      // false below, with the reason in the log.
      final tray = TrayThreadLibrary.open();
      final getSystemMetrics = DynamicLibrary.open('user32.dll')
          .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsDart>(
              'GetSystemMetrics');

      final events = NativeCallable<TrayEventCallback>.listener(_onEvent);
      // The tray must not keep the daemon alive; the daemon's lifetime is
      // decided elsewhere (tray "quit" -> shutdownAll -> dispose).
      events.keepIsolateAlive = false;
      _events = events;
      _tray = tray;
      _stopRequested = false;
      final hwnd = tray.start(events.nativeFunction);
      if (hwnd == 0) {
        _logger?.call(
            'warn',
            'The tray thread (cleona_tray.dll) could not create its window '
            '— NO icon will appear.');
        _stopThread();
        return false;
      }
      // S425 T-1 measurement: the E2E probe compares its own desktop and
      // session against this line.
      _logger?.call('info', trayWindowWhereLine(hwnd));

      // Load icon
      if (iconPath.endsWith('.ico') && File(iconPath).existsSync()) {
        _trayHicon = tray.loadIcon(
            iconPath, 0, 0, _LR_LOADFROMFILE | _LR_DEFAULTSIZE);
      }
      if (_trayHicon == 0) {
        // Fallback: default application icon
        _trayHicon = tray.loadIcon(null, 0, 0, 0);
      }
      _setSymbol = _trayHicon;

      // ── THE THREE STATE ICONS (§22.9, V-10-b, E3 = A) ─────────────
      //
      // In the EXACT size that the notification area shows. The base icon
      // above loads with `LR_DEFAULTSIZE`, i.e. 32 x 32
      // (`SM_CXICON`), and lets the shell scale down; for the
      // states the container holds a 16 version of its own, and that is
      // sharper than a scaled-down 32. If
      // `GetSystemMetrics` returns nothing (0), it falls back to `LR_DEFAULTSIZE`
      // instead of to an invented number.
      var kx = 0;
      var ky = 0;
      try {
        kx = getSystemMetrics(_SM_CXSMICON);
        ky = getSystemMetrics(_SM_CYSMICON);
      } catch (_) {}
      final flags = (kx > 0 && ky > 0)
          ? _LR_LOADFROMFILE
          : (_LR_LOADFROMFILE | _LR_DEFAULTSIZE);
      var found = 0;
      for (final entry in _statePaths.entries) {
        final state = entry.key;
        final path = entry.value;
        final h = tray.loadIcon(path, kx, ky, flags);
        if (h == 0) {
          _logger?.call('warn',
              'State icon "$path" could not be loaded (LoadImageW = 0).');
          continue;
        }
        _stateSymbols[state] = h;
        found++;
      }
      if (found == 0) {
        _logger?.call(
            'warn',
            'none of the three state icons (conn_*.ico) lies next to '
            '"$iconPath" — the icon stays fixed, the state travels only '
            'as text (§22.9).');
      } else {
        _logger?.call('info',
            'State icons: $found of ${kReadinessNames.length} '
            '(${kx > 0 ? "${kx}x$ky" : "default size"})');
      }

      // Fill NOTIFYICONDATAW
      final nidView = _nid.cast<Uint32>();
      nidView[0] = _NOTIFYICONDATAW_SIZE; // cbSize
      _nid.cast<IntPtr>()[1] = hwnd; // hWnd (offset 8 on 64-bit)
      nidView[4] = 1; // uID (offset 16)
      nidView[5] = _NIF_MESSAGE | _NIF_ICON | _NIF_TIP; // uFlags (offset 20)
      nidView[6] = _WM_TRAYICON; // uCallbackMessage (offset 24)
      _nid.cast<IntPtr>()[4] = _trayHicon; // hIcon (offset 32 on 64-bit)

      // szTip: UTF-16 string at offset 40, max 128 chars
      writeSzTip(_nid, tooltip);

      // The menu as it stands before the first state report.
      _pushMenu(trayMenuSpec(
        statusLine: '',
        identityLines: const [],
        serviceRunning: true,
        localeCode: _menuLocale,
      ));

      // The return value IS the statement — see [trayIconAccepted].
      // If the insertion fails, abort here and end the tray thread: there
      // is then nothing to withdraw, and `service_daemon.dart` prints
      // "Tray icon: FAILED" instead of "OK".
      final added = _shellNotifyIcon(_NIM_ADD, _nid);
      if (!trayIconAccepted(added.result)) {
        _logger?.call(
            'warn',
            'Shell_NotifyIcon(NIM_ADD) rejected — in this session there is '
            'no notification area (session 0 / no shell / Explorer not '
            'started). NO icon will appear (GetLastError=${added.lastError}).');
        _stopThread();
        return false;
      }
      _sinceAdd
        ..reset()
        ..start();

      _initialized = true;
      return true;
    } catch (e) {
      _logger?.call('warn', 'NativeTrayWindows init failed: $e');
      try { RedactedConsole.err('NativeTrayWindows init failed: $e'); } catch (_) {}
      _stopThread();
      return false;
    }
  }

  /// What the tooltip SHOULD show — independent of whether the
  /// notification area has accepted the icon.
  ///
  /// Set BEFORE the `_initialized` check, for the same reason as
  /// `NativeTray.letzterZustand`: otherwise "the readiness reaches
  /// the Windows tray" would only be checkable on a Windows with a session, and
  /// the guard would have to make do with a text comparison of the source
  /// — i.e. with a proxy.
  String? intendedTooltip;

  /// The last passed state (counterpart to
  /// `NativeTray.letzterZustand` on the Windows branch).
  TrayStatus? lastState;

  /// Readiness state and counter to the notification area.
  ///
  /// Windows has no permanently visible menu like the
  /// StatusNotifierItem — the state therefore travels via the TOOLTIP
  /// (szTip, on hovering) and via the greyed-out first line of the
  /// context menu (on right-click).
  void updateStatus(TrayStatus status, String basisName, String localeCode) {
    _menuLocale = localeCode;
    final statusLine = trayStatusText(status, localeCode);
    final menu = trayMenuSpec(
      statusLine: statusLine,
      identityLines: [
        for (final z in status.identities) trayIdentityLineText(z, localeCode)
      ],
      serviceRunning: status.serviceRunning,
      localeCode: localeCode,
    );
    lastState = status;
    final basis = basisName.isEmpty ? _tooltipBasis : basisName;
    final text = trayTooltipText(basis, status.unreadCount, statusLine);
    intendedTooltip = text;
    // The intended statement about the ICON — before the
    // `_initialized` check, for the same reason as the tooltip
    // above (see [beabsichtigtesZustandssymbol]).
    // The fallback is expressly represented here: if the
    // state file is missing, the base icon is the statement — not a path that
    // does not exist. Otherwise this seam would claim a change that the
    // notification area never sees.
    intendedStateIcon = _baseIconPath.isEmpty
        ? null
        : (_statePaths[status.readiness] ?? _baseIconPath);
    if (!_initialized) return;

    _pushMenu(menu);

    final symbol = _stateSymbols[status.readiness] ?? _trayHicon;
    final symbolNew = symbol != 0 && symbol != _setSymbol;
    final textNew = text != _tooltipSet;
    // A `NIM_MODIFY` without change is traffic without a statement — and
    // `updateStatus` comes with every state report of the service.
    if (!symbolNew && !textNew) return;

    if (textNew) {
      _tooltipSet = text;
      writeSzTip(_nid, text);
    }
    if (symbolNew) {
      _setSymbol = symbol;
      _nid.cast<IntPtr>()[4] = symbol; // hIcon (offset 32 on 64 bit)
    }
    // NIM_MODIFY with unchanged uFlags (MESSAGE|ICON|TIP): the
    // notification area takes over the whole record anew — now including
    // a changed icon.
    final r = _shellNotifyIcon(_NIM_MODIFY, _nid);
    if (!trayIconAccepted(r.result)) {
      // Read by the tray thread right after its call (see
      // [trayModifyRejectedLine]).
      _modifyRejectedInARow++;
      _logger?.call(
          'warn',
          trayModifyRejectedLine(
            lastError: r.lastError,
            windowAlive: r.windowAlive,
            sinceAdd: _sinceAdd.elapsed,
            inARow: _modifyRejectedInARow,
          ));
    } else {
      final line = trayModifyAcceptedLine(
        firstEver: !_modifyEverAccepted,
        rejectedBefore: _modifyRejectedInARow,
        sinceAdd: _sinceAdd.elapsed,
      );
      _modifyEverAccepted = true;
      _modifyRejectedInARow = 0;
      if (line != null) _logger?.call('info', line);
    }
  }

  /// Hands [spec] to the tray thread when it differs from the last one.
  void _pushMenu(String spec) {
    final tray = _tray;
    if (tray == null || spec == _menuSet) return;
    if (tray.setMenu(spec)) {
      _menuSet = spec;
    } else {
      _logger?.call('warn',
          'The tray thread did not take the context menu over — it keeps the previous one.');
    }
  }

  /// An event of the tray thread, delivered on this isolate by the
  /// `NativeCallable.listener` — the same order as the menu clicks, one
  /// call per event.
  void _onEvent(int event) {
    switch (event) {
      case _IDM_SHOW:
        onShowWindow?.call();
      case _IDM_STOP:
        onStop?.call();
      case _IDM_START:
        onStart?.call();
      case _IDM_QUIT:
        onQuit?.call();
      case kTrayEventReadded:
        _logger?.call('info',
            'Tray icon added again after the taskbar was re-created (TaskbarCreated).');
      case kTrayEventReaddFailed:
        _logger?.call('warn',
            'The taskbar was re-created (TaskbarCreated), but the tray icon could not be added again.');
      // Measurement (S424 R-3, M-1): when and how the tray window ends.
      case kTrayEventCloseReceived:
        _logger?.call('warn',
            'Tray window received WM_CLOSE (stop requested by this process: $_stopRequested).');
      case kTrayEventDestroyed:
        _logger?.call('warn',
            'Tray window destroyed (WM_DESTROY) — the tray icon is gone (stop requested by this process: $_stopRequested).');
      case kTrayEventThreadEnded:
        _logger?.call('warn',
            'Tray thread ended (exit code 0): its message loop received WM_QUIT (stop requested by this process: $_stopRequested).');
      case kTrayEventThreadEndedLoopError:
        _logger?.call('warn',
            'Tray thread ended (exit code 0): GetMessageW failed with -1 (stop requested by this process: $_stopRequested).');
    }
  }

  /// Set when this process itself ends the tray thread ([_stopThread]), so
  /// the measurement lines above tell an intended end from a foreign one.
  bool _stopRequested = false;

  /// Ends the tray thread (it removes the icon, destroys the window and the
  /// icons it loaded) and only then closes the event callback. If the
  /// thread does not end within 5 s the callback stays open — a thread that
  /// may still call it must never find it closed.
  void _stopThread() {
    final tray = _tray;
    final events = _events;
    _tray = null;
    _events = null;
    var ended = true;
    if (tray != null) {
      _stopRequested = true;
      try {
        ended = tray.stop();
      } catch (_) {
        ended = false;
      }
    }
    if (events == null) return;
    if (ended) {
      events.close();
    } else {
      _logger?.call('warn',
          'The tray thread did not end within 5 s; its event callback stays open.');
    }
  }

  void dispose() {
    _stopThread();
    _stateSymbols.clear();
    _trayHicon = 0;
    _setSymbol = 0;
    _menuSet = null;
    calloc.free(_nid);
    _initialized = false;
  }
}
