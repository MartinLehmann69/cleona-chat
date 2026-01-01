import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/platform/bounded_call.dart';

/// macOS-only bindings for the login keychain through Security.framework,
/// WITHOUT a child process (architecture §4.5.2, §23.10; owner decision
/// D-95, way (a) of `mycelium/berichte/S413-VORLAGE-MACOS-SCHLUESSELBUND.md`).
///
/// Until S413 the macOS keyring called `/usr/bin/security` with
/// `Process.runSync`: the secret stood in the `-w` argument (readable by every
/// local user for the life of the process), every call was unbounded, and the
/// entry was created with `-T ''` — an EMPTY access list, so that every later
/// read, even by `security` itself, raised the confirmation dialog of
/// `SecurityAgent`. In CI nobody answers it and the test hung until the job
/// limit (CI run 42123022250).
///
/// Sources for the facts this file relies on (Apple, `apple-oss-distributions/
/// Security`, branch `main`, and the SDK headers):
///  * `SecAccess.h`, `SecAccessCreate`, parameter `trustedlist`: "specifying
///    which applications should be allowed to access an item without
///    triggering confirmation dialogs … To set no applications, pass a CFArray
///    with no elements." — the `-T ''` of 4.2.3–4.2.6 is that empty list
///    (`SecurityTool/macOS/keychain_add.c`, `-T` branch).
///  * `SecKeychain.h:634-649`, `SecKeychainSetUserInteractionAllowed`: "Turns
///    on or off any optional user interaction" — process-wide, not per thread
///    or isolate. With interaction off, a read that would need the dialog
///    returns `errSecInteractionNotAllowed` instead of waiting
///    (`SecBase.h:361`).
///  * `SecBase.h:335-368` for the status codes below.
///  * `keychain_add.c:604`, `:736`: `security add-generic-password` uses the
///    service name as label and as access descriptor when `-l` is omitted —
///    mirrored here, so an entry written by this file looks like one the CLI
///    wrote.
///  * `CFString.h`: `kCFStringEncodingUTF8 = 0x08000100`.
///
/// The entry attributes are those every 4.2.x build wrote: class generic
/// password, account `cleona`, service `cleona_<name>` / `cleona_live_<name>`,
/// value `utf8(base64(data))`. A 4.2.3–4.2.6 build therefore finds what this
/// file writes, and this file finds what they wrote.
///
/// The secret travels only in a `calloc`'d buffer that is zeroed before it is
/// released and in the `CFData` copy Security.framework is handed; it never
/// appears in a process argument, an environment variable, a log line or an
/// exception text. The `CFData` copies inside CoreFoundation are not zeroed —
/// the seed lies in ordinary process memory anyway (§4.5.2 point 2, D-50).

/// `errSecSuccess`.
const int kSecStatusSuccess = 0;

/// `errSecItemNotFound` (`SecBase.h:353`): the entry does not exist.
const int kSecStatusItemNotFound = -25300;

/// `errSecDuplicateItem` (`SecBase.h:352`).
const int kSecStatusDuplicateItem = -25299;

/// `errSecInteractionNotAllowed` (`SecBase.h:361`): the entry exists, but
/// reading it would need the confirmation dialog, and interaction is off.
const int kSecStatusInteractionNotAllowed = -25308;

/// `errSecAuthFailed` (`SecBase.h:346`).
const int kSecStatusAuthFailed = -25293;

/// `errSecUserCanceled` (`SecBase.h:335`): the user pressed "Deny".
const int kSecStatusUserCanceled = -128;

/// Not an Apple code: this file could not even ask (framework not loadable,
/// or a takeover is in flight and holds interaction open, see
/// [KeychainTakeover]). Treated like every other non-success, non-not-found
/// answer: the entry is NOT known to be absent.
const int kSecStatusNotAsked = -1;

/// Not an Apple code: the keychain did not answer within the bound of
/// [BoundedKeychainBackend], or an earlier call that did not answer is still
/// running. The entry is NOT known to be absent (§4.5.2 fail-loud).
const int kSecStatusTimedOut = -2;

/// Result of one read: the Security.framework status and, on success, the
/// value bytes as stored (the base64 text, not yet decoded).
class KeychainRead {
  final int status;
  final Uint8List? value;
  const KeychainRead(this.status, this.value);
}

/// What the macOS keyring needs from the keychain — the seam between the
/// status mapping in `keyring_service.dart` (pure Dart, tested on Linux with
/// a stand-in, `test/smoke/smoke_keychain_unreadable.dart`) and the native
/// calls below.
abstract class KeychainBackend {
  /// Reads the value of [service]. Never shows a dialog unless interaction
  /// was switched on (only [KeychainTakeover] does that).
  KeychainRead read(String service);

  /// Adds [service] with [value] and an access list of [trustedPaths].
  int add(String service, Uint8List value, List<String> trustedPaths);

  /// Removes [service].
  int remove(String service);
}

typedef _OSStatus = Int32;

typedef _SecItemAddNative = _OSStatus Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemAddDart = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemDeleteNative = _OSStatus Function(Pointer<Void>);
typedef _SecItemDeleteDart = int Function(Pointer<Void>);
typedef _SetInteractionNative = _OSStatus Function(Uint8);
typedef _SetInteractionDart = int Function(int);
typedef _SecAccessCreateNative = _OSStatus Function(
    Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecAccessCreateDart = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _TrustedAppFromPathNative = _OSStatus Function(
    Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _TrustedAppFromPathDart = int Function(
    Pointer<Utf8>, Pointer<Pointer<Void>>);

typedef _CFStringCreateNative = Pointer<Void> Function(
    Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreateDart = Pointer<Void> Function(
    Pointer<Void>, Pointer<Utf8>, int);
typedef _CFDataCreateNative = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _CFDataCreateDart = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, int);
typedef _CFDataGetLengthNative = IntPtr Function(Pointer<Void>);
typedef _CFDataGetLengthDart = int Function(Pointer<Void>);
typedef _CFDataGetBytePtrNative = Pointer<Uint8> Function(Pointer<Void>);
typedef _CFDataGetBytePtrDart = Pointer<Uint8> Function(Pointer<Void>);
typedef _CFDictCreateMutableNative = Pointer<Void> Function(
    Pointer<Void>, IntPtr, Pointer<Void>, Pointer<Void>);
typedef _CFDictCreateMutableDart = Pointer<Void> Function(
    Pointer<Void>, int, Pointer<Void>, Pointer<Void>);
typedef _CFDictSetValueNative = Void Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _CFDictSetValueDart = void Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _CFArrayCreateNative = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, IntPtr, Pointer<Void>);
typedef _CFArrayCreateDart = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, int, Pointer<Void>);
typedef _CFReleaseNative = Void Function(Pointer<Void>);
typedef _CFReleaseDart = void Function(Pointer<Void>);
typedef _CFTypeIdOfNative = UintPtr Function(Pointer<Void>);
typedef _CFTypeIdOfDart = int Function(Pointer<Void>);
typedef _CFDataTypeIdNative = UintPtr Function();
typedef _CFDataTypeIdDart = int Function();

/// `kCFStringEncodingUTF8` (`CFString.h`).
const int _kCFStringEncodingUTF8 = 0x08000100;

/// The account every 4.2.x build wrote (`security … -a cleona`).
const String kKeychainAccount = 'cleona';

/// Direct FFI access to Security.framework and CoreFoundation. One instance
/// per isolate — an isolate does not share its parent's handles, so
/// [KeychainTakeover] builds its own.
class KeychainFfi implements KeychainBackend {
  static KeychainFfi? _instance;

  /// The instance of this isolate; `null` where the frameworks do not load
  /// (every platform but macOS).
  static KeychainFfi? get instance {
    if (_instance != null) return _instance;
    if (!Platform.isMacOS) return null;
    try {
      return _instance = KeychainFfi._();
    } catch (_) {
      return null;
    }
  }

  late final _SecItemAddDart _secItemAdd;
  late final _SecItemAddDart _secItemCopyMatching;
  late final _SecItemDeleteDart _secItemDelete;
  late final _SetInteractionDart _setInteraction;
  late final _SecAccessCreateDart _secAccessCreate;
  late final _TrustedAppFromPathDart _trustedAppFromPath;
  late final _CFStringCreateDart _cfStringCreate;
  late final _CFDataCreateDart _cfDataCreate;
  late final _CFDataGetLengthDart _cfDataGetLength;
  late final _CFDataGetBytePtrDart _cfDataGetBytePtr;
  late final _CFDictCreateMutableDart _cfDictCreateMutable;
  late final _CFDictSetValueDart _cfDictSetValue;
  late final _CFArrayCreateDart _cfArrayCreate;
  late final _CFReleaseDart _cfRelease;
  late final _CFTypeIdOfDart _cfGetTypeId;
  late final _CFDataTypeIdDart _cfDataGetTypeId;

  late final Pointer<Void> _dictKeyCallBacks;
  late final Pointer<Void> _dictValueCallBacks;
  late final Pointer<Void> _arrayCallBacks;
  late final Pointer<Void> _cfTrue;

  late final Pointer<Void> _kSecClass;
  late final Pointer<Void> _kSecClassGenericPassword;
  late final Pointer<Void> _kSecAttrAccount;
  late final Pointer<Void> _kSecAttrService;
  late final Pointer<Void> _kSecAttrLabel;
  late final Pointer<Void> _kSecAttrAccess;
  late final Pointer<Void> _kSecValueData;
  late final Pointer<Void> _kSecReturnData;
  late final Pointer<Void> _kSecMatchLimit;
  late final Pointer<Void> _kSecMatchLimitOne;

  KeychainFfi._() {
    final sec = DynamicLibrary.open(
        '/System/Library/Frameworks/Security.framework/Security');
    final cf = DynamicLibrary.open(
        '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');

    _secItemAdd =
        sec.lookupFunction<_SecItemAddNative, _SecItemAddDart>('SecItemAdd');
    _secItemCopyMatching = sec.lookupFunction<_SecItemAddNative,
        _SecItemAddDart>('SecItemCopyMatching');
    _secItemDelete = sec
        .lookupFunction<_SecItemDeleteNative, _SecItemDeleteDart>('SecItemDelete');
    _setInteraction = sec.lookupFunction<_SetInteractionNative,
        _SetInteractionDart>('SecKeychainSetUserInteractionAllowed');
    _secAccessCreate = sec.lookupFunction<_SecAccessCreateNative,
        _SecAccessCreateDart>('SecAccessCreate');
    _trustedAppFromPath = sec.lookupFunction<_TrustedAppFromPathNative,
        _TrustedAppFromPathDart>('SecTrustedApplicationCreateFromPath');

    _cfStringCreate = cf.lookupFunction<_CFStringCreateNative,
        _CFStringCreateDart>('CFStringCreateWithCString');
    _cfDataCreate =
        cf.lookupFunction<_CFDataCreateNative, _CFDataCreateDart>('CFDataCreate');
    _cfDataGetLength = cf.lookupFunction<_CFDataGetLengthNative,
        _CFDataGetLengthDart>('CFDataGetLength');
    _cfDataGetBytePtr = cf.lookupFunction<_CFDataGetBytePtrNative,
        _CFDataGetBytePtrDart>('CFDataGetBytePtr');
    _cfDictCreateMutable = cf.lookupFunction<_CFDictCreateMutableNative,
        _CFDictCreateMutableDart>('CFDictionaryCreateMutable');
    _cfDictSetValue = cf.lookupFunction<_CFDictSetValueNative,
        _CFDictSetValueDart>('CFDictionarySetValue');
    _cfArrayCreate = cf
        .lookupFunction<_CFArrayCreateNative, _CFArrayCreateDart>('CFArrayCreate');
    _cfRelease =
        cf.lookupFunction<_CFReleaseNative, _CFReleaseDart>('CFRelease');
    _cfGetTypeId =
        cf.lookupFunction<_CFTypeIdOfNative, _CFTypeIdOfDart>('CFGetTypeID');
    _cfDataGetTypeId = cf
        .lookupFunction<_CFDataTypeIdNative, _CFDataTypeIdDart>('CFDataGetTypeID');

    // Callback structs: their ADDRESS is the argument, not their content.
    _dictKeyCallBacks = cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks');
    _dictValueCallBacks = cf.lookup<Void>('kCFTypeDictionaryValueCallBacks');
    _arrayCallBacks = cf.lookup<Void>('kCFTypeArrayCallBacks');
    // Exported constants are `const CFStringRef` VARIABLES: read the pointer.
    _cfTrue = cf.lookup<Pointer<Void>>('kCFBooleanTrue').value;

    Pointer<Void> c(String n) => sec.lookup<Pointer<Void>>(n).value;
    _kSecClass = c('kSecClass');
    _kSecClassGenericPassword = c('kSecClassGenericPassword');
    _kSecAttrAccount = c('kSecAttrAccount');
    _kSecAttrService = c('kSecAttrService');
    _kSecAttrLabel = c('kSecAttrLabel');
    _kSecAttrAccess = c('kSecAttrAccess');
    _kSecValueData = c('kSecValueData');
    _kSecReturnData = c('kSecReturnData');
    _kSecMatchLimit = c('kSecMatchLimit');
    _kSecMatchLimitOne = c('kSecMatchLimitOne');
  }

  /// Switches the confirmation dialog of macOS on or off for the WHOLE
  /// process (`SecKeychain.h:634`). Off from the first keychain call on
  /// (`KeyringService.init`); on only inside [KeychainTakeover].
  int setInteractionAllowed(bool allowed) => _setInteraction(allowed ? 1 : 0);

  Pointer<Void> _cfString(String s) {
    final c = s.toNativeUtf8();
    try {
      return _cfStringCreate(nullptr, c, _kCFStringEncodingUTF8);
    } finally {
      calloc.free(c);
    }
  }

  /// A query dictionary for class + account + [service]. The caller
  /// releases the returned dictionary and every object in [owned].
  Pointer<Void> _query(String service, List<Pointer<Void>> owned) {
    final dict = _cfDictCreateMutable(
        nullptr, 0, _dictKeyCallBacks, _dictValueCallBacks);
    final account = _cfString(kKeychainAccount);
    final svc = _cfString(service);
    owned..add(account)..add(svc);
    _cfDictSetValue(dict, _kSecClass, _kSecClassGenericPassword);
    _cfDictSetValue(dict, _kSecAttrAccount, account);
    _cfDictSetValue(dict, _kSecAttrService, svc);
    return dict;
  }

  void _releaseAll(List<Pointer<Void>> owned) {
    for (final p in owned) {
      if (p != nullptr) _cfRelease(p);
    }
  }

  @override
  KeychainRead read(String service) {
    final owned = <Pointer<Void>>[];
    final out = calloc<Pointer<Void>>();
    out.value = nullptr;
    try {
      final q = _query(service, owned);
      owned.add(q);
      _cfDictSetValue(q, _kSecReturnData, _cfTrue);
      _cfDictSetValue(q, _kSecMatchLimit, _kSecMatchLimitOne);
      final status = _secItemCopyMatching(q, out);
      if (status != kSecStatusSuccess) return KeychainRead(status, null);
      final data = out.value;
      if (data == nullptr || _cfGetTypeId(data) != _cfDataGetTypeId()) {
        // Success without a data object: nothing readable came back. The
        // entry exists, so this is never "absent".
        if (data != nullptr) _cfRelease(data);
        return const KeychainRead(kSecStatusNotAsked, null);
      }
      try {
        final len = _cfDataGetLength(data);
        final ptr = _cfDataGetBytePtr(data);
        return KeychainRead(
            status, Uint8List.fromList(ptr.asTypedList(len)));
      } finally {
        _cfRelease(data);
      }
    } finally {
      calloc.free(out);
      _releaseAll(owned);
    }
  }

  @override
  int add(String service, Uint8List value, List<String> trustedPaths) {
    final owned = <Pointer<Void>>[];
    final buf = calloc<Uint8>(value.isEmpty ? 1 : value.length);
    try {
      for (var i = 0; i < value.length; i++) {
        buf[i] = value[i];
      }
      final access = _access(service, trustedPaths, owned);
      if (access == nullptr) return kSecStatusNotAsked;
      final dict = _query(service, owned);
      owned.add(dict);
      final label = _cfString(service);
      owned.add(label);
      final data = _cfDataCreate(nullptr, buf, value.length);
      owned.add(data);
      _cfDictSetValue(dict, _kSecAttrLabel, label);
      _cfDictSetValue(dict, _kSecValueData, data);
      _cfDictSetValue(dict, _kSecAttrAccess, access);
      return _secItemAdd(dict, nullptr.cast());
    } finally {
      for (var i = 0; i < value.length; i++) {
        buf[i] = 0;
      }
      calloc.free(buf);
      _releaseAll(owned);
    }
  }

  /// `SecAccessCreate(descriptor = service, trustedlist = [each existing
  /// path])`. A path that does not exist or whose trusted-application
  /// object cannot be built is left out; with none left the access would be
  /// the empty list of 4.2.3–4.2.6 — that is refused (`nullptr`), never
  /// written.
  Pointer<Void> _access(
      String service, List<String> trustedPaths, List<Pointer<Void>> owned) {
    final apps = <Pointer<Void>>[];
    final out = calloc<Pointer<Void>>();
    try {
      for (final path in trustedPaths) {
        if (!File(path).existsSync()) continue;
        final c = path.toNativeUtf8();
        out.value = nullptr;
        try {
          if (_trustedAppFromPath(c, out) == kSecStatusSuccess &&
              out.value != nullptr) {
            apps.add(out.value);
          }
        } finally {
          calloc.free(c);
        }
      }
      if (apps.isEmpty) return nullptr;
      final values = calloc<Pointer<Void>>(apps.length);
      try {
        for (var i = 0; i < apps.length; i++) {
          values[i] = apps[i];
        }
        final array =
            _cfArrayCreate(nullptr, values, apps.length, _arrayCallBacks);
        owned.add(array);
        final descriptor = _cfString(service);
        owned.add(descriptor);
        out.value = nullptr;
        final status = _secAccessCreate(descriptor, array, out);
        if (status != kSecStatusSuccess || out.value == nullptr) return nullptr;
        owned.add(out.value);
        return out.value;
      } finally {
        calloc.free(values);
      }
    } finally {
      // The array retained every application object (kCFTypeArrayCallBacks).
      _releaseAll(apps);
      calloc.free(out);
    }
  }

  @override
  int remove(String service) {
    final owned = <Pointer<Void>>[];
    try {
      final q = _query(service, owned);
      owned.add(q);
      return _secItemDelete(q);
    } finally {
      _releaseAll(owned);
    }
  }
}

// ── The bound (§4.5.2 "Every keyring call is bounded in time") ──────────
//
// Security.framework has no cancellation handle (unlike GLib's GCancellable,
// `libsecret_ffi.dart`), and a synchronous FFI call blocks its isolate until
// the framework returns. The bound is therefore built as on Linux from a
// helper isolate that is spawned and confirmed BEFORE the first guarded call
// (`KeyringService.init`), but with the roles reversed: the helper makes the
// Security call, and the caller waits for its answer with a deadline. The
// wait logic is shared with Windows (`bounded_call.dart`, [BoundedCaller]);
// this file contributes the POSIX primitives: `pthread_cond_timedwait`. No
// library of our own is needed: the pthread and clock functions are part of
// libSystem (macOS) and libc (Linux, where the smokes run).

final class _Timespec extends Struct {
  /// `time_t tv_sec` — 64 bit on every 64-bit macOS and Linux target
  /// (`<sys/_types/_timespec.h>`; glibc `bits/types/struct_timespec.h`).
  @Int64()
  external int sec;

  /// `long tv_nsec` — 64 bit on the same targets (LP64).
  @Int64()
  external int nsec;
}

typedef _PthreadInitNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _PthreadInitDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _PthreadOneNative = Int32 Function(Pointer<Void>);
typedef _PthreadOneDart = int Function(Pointer<Void>);
typedef _PthreadTimedWaitNative = Int32 Function(
    Pointer<Void>, Pointer<Void>, Pointer<_Timespec>);
typedef _PthreadTimedWaitDart = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<_Timespec>);
typedef _ClockGettimeNative = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGettimeDart = int Function(int, Pointer<_Timespec>);

/// `CLOCK_REALTIME` — 0 on macOS (`<time.h>`, `_CLOCK_REALTIME = 0`) and on
/// Linux (`<linux/time.h>`); the clock `pthread_cond_timedwait` measures its
/// absolute deadline against when the condition has default attributes.
const int _kClockRealtime = 0;

/// Room for one `pthread_mutex_t` / `pthread_cond_t`: macOS 64 and 48 bytes
/// (`<sys/_pthread/_pthread_types.h>`, `__PTHREAD_MUTEX_SIZE__ 56` and
/// `__PTHREAD_COND_SIZE__ 40`, each plus the 8-byte `__sig`), glibc x86_64 40
/// and 48 (`bits/pthreadtypes-arch.h`). Generous on purpose; `calloc` aligns
/// to 16 bytes.
const int _kPthreadObjectBytes = 128;

/// The POSIX [WaitPrimitives] of this process (macOS libSystem, Linux libc),
/// looked up once per isolate.
class PosixWaitPrimitives implements WaitPrimitives {
  final _PthreadOneDart _lock;
  final _PthreadOneDart _unlock;
  final _PthreadOneDart _broadcast;
  final _PthreadTimedWaitDart _timedWait;
  final _PthreadInitDart _mutexInit;
  final _PthreadInitDart _condInit;
  final _ClockGettimeDart _clockGettime;

  PosixWaitPrimitives._(this._lock, this._unlock, this._broadcast,
      this._timedWait, this._mutexInit, this._condInit, this._clockGettime);

  factory PosixWaitPrimitives() {
    final p = DynamicLibrary.process();
    return PosixWaitPrimitives._(
      p.lookupFunction<_PthreadOneNative, _PthreadOneDart>('pthread_mutex_lock'),
      p.lookupFunction<_PthreadOneNative, _PthreadOneDart>(
          'pthread_mutex_unlock'),
      p.lookupFunction<_PthreadOneNative, _PthreadOneDart>(
          'pthread_cond_broadcast'),
      p.lookupFunction<_PthreadTimedWaitNative, _PthreadTimedWaitDart>(
          'pthread_cond_timedwait'),
      p.lookupFunction<_PthreadInitNative, _PthreadInitDart>(
          'pthread_mutex_init'),
      p.lookupFunction<_PthreadInitNative, _PthreadInitDart>(
          'pthread_cond_init'),
      p.lookupFunction<_ClockGettimeNative, _ClockGettimeDart>('clock_gettime'),
    );
  }

  @override
  int get objectBytes => _kPthreadObjectBytes;

  @override
  bool init(Pointer<Void> lock, Pointer<Void> cond) =>
      _mutexInit(lock, nullptr) == 0 && _condInit(cond, nullptr) == 0;

  @override
  void lock(Pointer<Void> lock) => _lock(lock);

  @override
  void unlock(Pointer<Void> lock) => _unlock(lock);

  @override
  void wakeAll(Pointer<Void> cond) => _broadcast(cond);

  /// `pthread_cond_timedwait` takes an ABSOLUTE deadline on `CLOCK_REALTIME`
  /// (the clock of a condition with default attributes): now + [ms].
  /// 0 = woken; ETIMEDOUT or any other error = `false`.
  @override
  bool waitMs(Pointer<Void> cond, Pointer<Void> lock, int ms) {
    final deadline = calloc<_Timespec>();
    try {
      _clockGettime(_kClockRealtime, deadline);
      final ns = deadline.ref.nsec + ms * 1000000;
      deadline.ref.sec += ns ~/ 1000000000;
      deadline.ref.nsec = ns % 1000000000;
      return _timedWait(cond, lock, deadline) == 0;
    } finally {
      calloc.free(deadline);
    }
  }
}

/// A top-level constructor for [BoundedCaller.start] (sendable to the
/// helper isolate).
WaitPrimitives posixWaitPrimitives() => PosixWaitPrimitives();

const int _opRead = 0;
const int _opAdd = 1;
const int _opRemove = 2;

/// A [KeychainBackend] whose every call is bounded in time (§4.5.2).
///
/// The calls of [inner] run in one helper isolate; the caller waits for the
/// answer at most [readBound] (read, remove) or [writeBound] (add). When
/// the bound passes, the call answers [kSecStatusTimedOut] — for a read that
/// is "present but not readable", never "absent", so nothing is generated
/// and nothing is written over (`keyring_service.dart`). The helper stays in
/// the call that does not return; its late answer is discarded.
///
/// A call made while the helper is still stuck answers [kSecStatusTimedOut]
/// AT ONCE instead of queuing behind it: every keychain call of the process
/// goes to the same `securityd`, so a second helper would hang the same way,
/// and the profile watchdog (every 30 s, §4.5.2) would leave one stuck
/// thread behind per round. Once the stuck call returns, the helper serves
/// again.
class BoundedKeychainBackend implements KeychainBackend {
  final BoundedCaller _caller;
  final Duration readBound;
  final Duration writeBound;

  BoundedKeychainBackend._(this._caller, this.readBound, this.writeBound);

  /// Spawns the helper isolate, which builds its backend with [open] (an
  /// isolate does not share its parent's `DynamicLibrary` handles), and
  /// confirms it is listening. MUST be awaited before the first call.
  /// `null` when the helper could not be confirmed: the caller never falls
  /// back to an unbounded call.
  static Future<BoundedKeychainBackend?> start(KeychainBackend Function() open,
      {Duration readBound = const Duration(seconds: 3),
      Duration writeBound = const Duration(seconds: 5)}) async {
    final caller = await BoundedCaller.start(
        posixWaitPrimitives, _KeychainWorkerFactory(open).build,
        errorStatus: kSecStatusNotAsked);
    if (caller == null) return null;
    return BoundedKeychainBackend._(caller, readBound, writeBound);
  }

  KeychainRead _call(List<Object?> request, Duration bound) {
    final a = _caller.call(request, bound);
    if (a.timedOut) return const KeychainRead(kSecStatusTimedOut, null);
    return KeychainRead(a.status, a.data);
  }

  @override
  KeychainRead read(String service) =>
      _call(<Object?>[_opRead, service], readBound);

  @override
  int add(String service, Uint8List value, List<String> trustedPaths) =>
      _call(<Object?>[_opAdd, service, value, trustedPaths], writeBound).status;

  @override
  int remove(String service) =>
      _call(<Object?>[_opRemove, service], readBound).status;
}

/// Sent to the helper isolate: builds the worker there around the backend
/// [open] builds.
class _KeychainWorkerFactory {
  final KeychainBackend Function() open;
  const _KeychainWorkerFactory(this.open);
  BoundedWorker build() => _KeychainWorker(open());
}

/// Executes the requests of [BoundedKeychainBackend] in the helper isolate.
class _KeychainWorker implements BoundedWorker {
  final KeychainBackend backend;
  _KeychainWorker(this.backend);

  @override
  BoundedReply handle(List<Object?> m) {
    final service = m[1] as String;
    switch (m[0] as int) {
      case _opRead:
        final r = backend.read(service);
        return BoundedReply(r.status, r.value);
      case _opAdd:
        final value = m[2] as Uint8List;
        try {
          return BoundedReply(
              backend.add(service, value, (m[3] as List).cast<String>()));
        } finally {
          value.fillRange(0, value.length, 0);
        }
      case _opRemove:
        return BoundedReply(backend.remove(service));
    }
    return const BoundedReply(kSecStatusNotAsked);
  }
}

/// The backend the helper isolate of [BoundedKeychainBackend] builds on
/// macOS. Throws where Security.framework does not load — the helper then
/// fails on startup and no bounded backend comes up.
KeychainBackend openKeychainFfiInWorker() => KeychainFfi.instance!;

/// The programs that read the master seed: the GUI and the daemon of the
/// same `.app` (§22.6; `ios-build.yml` places the daemon at
/// `Contents/MacOS/bin/cleona-daemon`). Pure, so that the derivation is
/// testable without a Mac.
///
/// [exe] is the running program. [macOsDirFiles] are the regular files
/// directly in `Contents/MacOS` — a Flutter macOS bundle carries exactly
/// its GUI executable there; the daemon lives one level lower in `bin/`.
List<String> keychainTrustedPaths(String exe, List<String> macOsDirFiles) {
  final norm = exe;
  final slash = norm.lastIndexOf('/');
  if (slash <= 0) return [exe];
  final dir = norm.substring(0, slash);
  final inBin = dir.endsWith('/bin');
  final macOsDir = inBin ? dir.substring(0, dir.length - 4) : dir;
  final result = <String>{exe};
  if (inBin) {
    result.addAll(macOsDirFiles);
  }
  result.add('$macOsDir/bin/cleona-daemon');
  return result.toList();
}

/// [keychainTrustedPaths] for this process.
List<String> keychainTrustedPathsOfThisProcess() {
  final exe = Platform.resolvedExecutable;
  final slash = exe.lastIndexOf('/');
  var macOsDir = slash > 0 ? exe.substring(0, slash) : '.';
  if (macOsDir.endsWith('/bin')) {
    macOsDir = macOsDir.substring(0, macOsDir.length - 4);
  }
  final files = <String>[];
  try {
    for (final e in Directory(macOsDir).listSync(followLinks: false)) {
      if (e is File) files.add(e.path);
    }
  } catch (_) {}
  return keychainTrustedPaths(exe, files);
}

/// Outcome of one takeover attempt.
enum KeychainTakeoverOutcome {
  /// Every entry that needed it was read with the dialog, rewritten with the
  /// new access list and read back without a dialog.
  done,

  /// The user pressed "Deny" (or the password was wrong): nothing changed.
  denied,

  /// No answer within the bound. The dialog may still stand; the attempt
  /// keeps running in its helper isolate and is joined by the next offer —
  /// a second dialog is never opened next to the first.
  timedOut,

  /// Something else failed; nothing was overwritten that had not been read.
  failed,
}

/// THE ONE-TIME TAKEOVER of 4.2.3–4.2.6 entries (D-95).
///
/// Their access list is empty, so the one dialog per entry is unavoidable.
/// It runs in a helper isolate, because a synchronous FFI call blocks its
/// isolate until macOS returns — the window must stay usable. Interaction is
/// process-wide (`SecKeychain.h:634`): while the helper runs, [inFlight] is
/// true and every keychain call of the main isolate refuses at once
/// (`keyring_service.dart`), so that no second dialog opens there.
///
/// The order inside the helper: read (dialog) → remove → add with the
/// access list GUI + daemon → read back WITHOUT dialog and compare. A value
/// that was not read is never removed. If the add fails after the remove,
/// the value is written back once more (same access list) and the outcome
/// is `failed`; it stays in the helper's memory only.
///
/// Not provable here: there is no Mac, and CI cannot type a password. The
/// success case is unproven until a device or a user shows it (D-95).
class KeychainTakeover {
  static Future<KeychainTakeoverOutcome>? _running;

  /// Whether a takeover holds interaction open right now.
  static bool get inFlight => _running != null;

  /// Takes over [services] (full service names). Joins an attempt that is
  /// still running instead of starting a second one.
  static Future<KeychainTakeoverOutcome> run(List<String> services,
      {Duration bound = const Duration(minutes: 2)}) {
    final running = _running ?? _start(services);
    return running.timeout(bound,
        onTimeout: () => KeychainTakeoverOutcome.timedOut);
  }

  static Future<KeychainTakeoverOutcome> _start(List<String> services) {
    final completer = Completer<KeychainTakeoverOutcome>();
    final port = RawReceivePort();
    port.handler = (Object? message) {
      port.close();
      _running = null;
      if (message is int &&
          message >= 0 &&
          message < KeychainTakeoverOutcome.values.length) {
        completer.complete(KeychainTakeoverOutcome.values[message]);
      } else {
        completer.complete(KeychainTakeoverOutcome.failed);
      }
    };
    final trusted = keychainTrustedPathsOfThisProcess();
    final future = completer.future;
    _running = future;
    Isolate.spawn(_entry, <Object?>[port.sendPort, services, trusted],
            onError: port.sendPort, errorsAreFatal: true)
        .catchError((Object _) {
      port.close();
      _running = null;
      if (!completer.isCompleted) {
        completer.complete(KeychainTakeoverOutcome.failed);
      }
      return Isolate.current;
    });
    return future;
  }

  static void _entry(List<Object?> args) {
    final reply = args[0] as SendPort;
    final services = (args[1] as List).cast<String>();
    final trusted = (args[2] as List).cast<String>();
    final ffi = KeychainFfi.instance;
    if (ffi == null) {
      reply.send(KeychainTakeoverOutcome.failed.index);
      return;
    }
    var outcome = KeychainTakeoverOutcome.done;
    ffi.setInteractionAllowed(true);
    try {
      for (final service in services) {
        final r = ffi.read(service);
        if (r.status == kSecStatusItemNotFound) continue;
        if (r.status == kSecStatusUserCanceled ||
            r.status == kSecStatusAuthFailed) {
          outcome = KeychainTakeoverOutcome.denied;
          break;
        }
        final value = r.value;
        if (r.status != kSecStatusSuccess || value == null) {
          outcome = KeychainTakeoverOutcome.failed;
          break;
        }
        final removed = ffi.remove(service);
        if (removed != kSecStatusSuccess) {
          outcome = removed == kSecStatusUserCanceled
              ? KeychainTakeoverOutcome.denied
              : KeychainTakeoverOutcome.failed;
          break;
        }
        if (ffi.add(service, value, trusted) != kSecStatusSuccess) {
          // Write it back once more so the value is not lost; then stop.
          ffi.add(service, value, trusted);
          outcome = KeychainTakeoverOutcome.failed;
          break;
        }
        // Read back without the dialog: the new list must carry this program.
        ffi.setInteractionAllowed(false);
        final back = ffi.read(service);
        ffi.setInteractionAllowed(true);
        if (back.status != kSecStatusSuccess ||
            back.value == null ||
            !_same(back.value!, value)) {
          outcome = KeychainTakeoverOutcome.failed;
          break;
        }
      }
    } catch (_) {
      outcome = KeychainTakeoverOutcome.failed;
    } finally {
      ffi.setInteractionAllowed(false);
    }
    reply.send(outcome.index);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

/// Decodes a stored value (`utf8(base64(data))`) — the format every 4.2.x
/// build wrote. Returns `null` when the bytes are no base64 text.
Uint8List? decodeKeychainValue(Uint8List stored) {
  try {
    final text = utf8.decode(stored).trim();
    if (text.isEmpty) return null;
    return base64Decode(text);
  } catch (_) {
    return null;
  }
}
