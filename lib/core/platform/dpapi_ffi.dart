import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/platform/bounded_call.dart';
import 'package:ffi/ffi.dart';

/// Win32 DATA_BLOB structure used by CryptProtectData / CryptUnprotectData.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptProtectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer pReserved,
  Pointer pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer Function(Pointer hMem);
typedef _LocalFreeDart = Pointer Function(Pointer hMem);

/// Direct FFI access to Windows DPAPI (crypt32.dll).
///
/// Replaces the PowerShell-subprocess approach that spawned 2-5 processes
/// per daemon startup (2-5s CLR JIT each). FFI calls complete in <1ms.
class DpapiFfi {
  static DpapiFfi? _instance;

  late final _CryptProtectDataDart _cryptProtectData;
  late final _CryptUnprotectDataDart _cryptUnprotectData;
  late final _LocalFreeDart _localFree;

  DpapiFfi._() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    _cryptProtectData = crypt32.lookupFunction<
        _CryptProtectDataNative, _CryptProtectDataDart>('CryptProtectData');

    _cryptUnprotectData = crypt32.lookupFunction<
        _CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData');

    _localFree = kernel32
        .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  }

  static DpapiFfi get instance => _instance ??= DpapiFfi._();

  /// Encrypt [data] using DPAPI (CurrentUser scope).
  /// Returns the encrypted bytes, or null on failure.
  Uint8List? protect(Uint8List data) {
    final pDataIn = calloc<_DataBlob>();
    final pDataOut = calloc<_DataBlob>();
    Pointer<Uint8>? inputBuf;

    try {
      inputBuf = calloc<Uint8>(data.length);
      for (var i = 0; i < data.length; i++) {
        inputBuf[i] = data[i];
      }
      pDataIn.ref.cbData = data.length;
      pDataIn.ref.pbData = inputBuf;

      pDataOut.ref.cbData = 0;
      pDataOut.ref.pbData = nullptr.cast();

      final ok = _cryptProtectData(
        pDataIn,
        nullptr.cast(), // no description
        nullptr.cast(), // no entropy
        nullptr, // reserved
        nullptr, // no prompt
        0, // CRYPTPROTECT_UI_FORBIDDEN is 0x1 but we pass 0 for CurrentUser
        pDataOut,
      );

      if (ok == 0) return null;

      final outLen = pDataOut.ref.cbData;
      final outPtr = pDataOut.ref.pbData;
      if (outLen == 0 || outPtr == nullptr.cast<Uint8>()) return null;

      final result = Uint8List(outLen);
      for (var i = 0; i < outLen; i++) {
        result[i] = outPtr[i];
      }
      return result;
    } finally {
      if (pDataOut.ref.pbData != nullptr.cast<Uint8>()) {
        _localFree(pDataOut.ref.pbData.cast());
      }
      if (inputBuf != null) calloc.free(inputBuf);
      calloc.free(pDataIn);
      calloc.free(pDataOut);
    }
  }

  /// Decrypt DPAPI-protected [data] (CurrentUser scope).
  /// Returns the plaintext bytes, or null on failure.
  Uint8List? unprotect(Uint8List data) {
    final pDataIn = calloc<_DataBlob>();
    final pDataOut = calloc<_DataBlob>();
    Pointer<Uint8>? inputBuf;

    try {
      inputBuf = calloc<Uint8>(data.length);
      for (var i = 0; i < data.length; i++) {
        inputBuf[i] = data[i];
      }
      pDataIn.ref.cbData = data.length;
      pDataIn.ref.pbData = inputBuf;

      pDataOut.ref.cbData = 0;
      pDataOut.ref.pbData = nullptr.cast();

      final ok = _cryptUnprotectData(
        pDataIn,
        nullptr.cast(), // no description out
        nullptr.cast(), // no entropy
        nullptr, // reserved
        nullptr, // no prompt
        0, // flags
        pDataOut,
      );

      if (ok == 0) return null;

      final outLen = pDataOut.ref.cbData;
      final outPtr = pDataOut.ref.pbData;
      if (outLen == 0 || outPtr == nullptr.cast<Uint8>()) return null;

      final result = Uint8List(outLen);
      for (var i = 0; i < outLen; i++) {
        result[i] = outPtr[i];
      }
      return result;
    } finally {
      if (pDataOut.ref.pbData != nullptr.cast<Uint8>()) {
        _localFree(pDataOut.ref.pbData.cast());
      }
      if (inputBuf != null) calloc.free(inputBuf);
      calloc.free(pDataIn);
      calloc.free(pDataOut);
    }
  }
}

// ── The DPAPI keyring store and its bound (§4.5.2) ──────────────────────
//
// "Every keyring call is bounded in time" holds on Windows too, although
// DPAPI shows no dialog on the path built here: `pPromptStruct = NULL` and
// flags 0 (`CryptProtectData`, learn.microsoft.com, parameter
// `pPromptStruct`: "Passing NULL … will use the non-interactive path").
// What DPAPI can wait on are network paths for which Microsoft documents
// no time limit:
//  * a domain account whose master key cannot be opened locally (after a
//    password reset) is opened with the backup key of a domain controller
//    ("DPAPI backup keys on Active Directory domain controllers", protocol
//    MS-BKRP) — a call to the network;
//  * `%APPDATA%` is a known folder, and Folder Redirection can "redirect the
//    path of a known folder to … a directory on a file share"
//    ("Folder Redirection and Roaming User Profiles", learn.microsoft.com);
//    "Offline Files might not transition to offline mode for 3-6 minutes
//    after a user loses access to the file share" ("Deploy Folder
//    Redirection with Offline Files"). The `.dpapi` file lives there.
// Hence the whole store operation — file I/O AND the crypt32 call — runs in
// the helper isolate of a [BoundedCaller], and the caller waits at most the
// bound (`bounded_call.dart`).

/// Status of one store operation. Not Win32 codes.
const int kDpapiOk = 0;

/// No `.dpapi` file (or an empty one) under this name.
const int kDpapiAbsent = 1;

/// The file exists, but `CryptUnprotectData` refused it.
const int kDpapiUnprotectFailed = 2;

/// `CryptProtectData` refused.
const int kDpapiProtectFailed = 3;

/// Reading, writing or deleting the file threw.
const int kDpapiIoError = 4;

/// The file holds text that is no base64 (pre-FFI format, damaged).
const int kDpapiBadContent = 5;

/// The store did not answer within the bound of [BoundedDpapiStore], or an
/// earlier call that did not answer is still running. The entry is NOT
/// known to be absent (§4.5.2 fail-loud).
const int kDpapiTimedOut = -2;

/// Result of one read: the status and, on [kDpapiOk], the plaintext.
class DpapiRead {
  final int status;
  final Uint8List? value;
  const DpapiRead(this.status, [this.value]);
}

/// What the Windows keyring needs — the seam between the status mapping in
/// `keyring_service.dart` and the store below, so that the bound is
/// testable on Linux with a stand-in (`smoke_dpapi_bounded_call.dart`).
abstract class DpapiStore {
  /// Reads and decrypts the entry [name].
  DpapiRead read(String name);

  /// Encrypts [data] and writes it as [name].
  int write(String name, Uint8List data);

  /// Deletes [name]. [kDpapiOk] if a file was deleted, [kDpapiAbsent] if
  /// there was none.
  int remove(String name);

  /// Round trip protect → unprotect of a fixed test value, nothing written.
  int probe();
}

/// The store every 4.2.x build used: one file `<baseDir>/<name>.dpapi`
/// holding the raw `CryptProtectData` output (CurrentUser scope, no
/// entropy). Files of the pre-FFI PowerShell builds hold the same bytes as
/// base64 text; they are read and rewritten raw.
class DpapiFileStore implements DpapiStore {
  final String baseDir;
  const DpapiFileStore(this.baseDir);

  String _pathFor(String name) => '$baseDir/$name.dpapi';

  @override
  DpapiRead read(String name) {
    try {
      final file = File(_pathFor(name));
      if (!file.existsSync()) return const DpapiRead(kDpapiAbsent);
      final raw = file.readAsBytesSync();
      if (raw.isEmpty) return const DpapiRead(kDpapiAbsent);

      // Migration: old PowerShell-based code wrote base64-encoded DPAPI
      // ciphertext as text. Detect by checking if content is valid ASCII
      // base64 (only printable chars + whitespace). Raw DPAPI ciphertext
      // contains non-ASCII bytes, so the heuristic is reliable.
      final asText = _looksLikeBase64Text(raw);
      Uint8List encrypted;
      if (asText) {
        var text = String.fromCharCodes(raw).trim();
        text = text.replaceAll(RegExp(r'\s+'), '');
        if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text)) {
          return const DpapiRead(kDpapiBadContent);
        }
        encrypted = base64Decode(text);
      } else {
        encrypted = raw;
      }

      final decrypted = DpapiFfi.instance.unprotect(encrypted);
      if (decrypted == null) return const DpapiRead(kDpapiUnprotectFailed);

      // Re-write as raw binary so future loads skip the base64 path.
      if (asText) {
        try {
          file.writeAsBytesSync(encrypted);
        } catch (_) {}
      }
      return DpapiRead(kDpapiOk, decrypted);
    } catch (_) {
      return const DpapiRead(kDpapiIoError);
    }
  }

  static bool _looksLikeBase64Text(Uint8List data) {
    for (final b in data) {
      if (b > 0x7E) return false;
      if (b < 0x09) return false;
    }
    return true;
  }

  @override
  int write(String name, Uint8List data) {
    try {
      final encrypted = DpapiFfi.instance.protect(data);
      if (encrypted == null) return kDpapiProtectFailed;
      final file = File(_pathFor(name));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(encrypted);
      return kDpapiOk;
    } catch (_) {
      return kDpapiIoError;
    }
  }

  @override
  int remove(String name) {
    try {
      final file = File(_pathFor(name));
      if (!file.existsSync()) return kDpapiAbsent;
      file.deleteSync();
      return kDpapiOk;
    } catch (_) {
      return kDpapiIoError;
    }
  }

  @override
  int probe() {
    final testData = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
    final encrypted = DpapiFfi.instance.protect(testData);
    if (encrypted == null) return kDpapiProtectFailed;
    final decrypted = DpapiFfi.instance.unprotect(encrypted);
    if (decrypted == null) return kDpapiUnprotectFailed;
    if (decrypted.length != testData.length) return kDpapiUnprotectFailed;
    for (var i = 0; i < testData.length; i++) {
      if (decrypted[i] != testData[i]) return kDpapiUnprotectFailed;
    }
    return kDpapiOk;
  }
}

/// Sent to the helper isolate: builds the [DpapiFileStore] of [baseDir]
/// there (the crypt32 handles are per isolate, `DpapiFfi.instance`).
class DpapiFileStoreFactory {
  final String baseDir;
  const DpapiFileStoreFactory(this.baseDir);
  DpapiStore open() => DpapiFileStore(baseDir);
}

// ── Windows wait primitives (kernel32) ──────────────────────────────────
//
// Sources (learn.microsoft.com, read 06.11.2026; DLL Kernel32.dll, minimum
// client Windows Vista, for every function below):
//  * `InitializeSRWLock`: "An SRW lock must be initialized before it is
//    used … An SRW lock cannot be moved or copied while in use." — it lives
//    in `calloc`'d native memory that never moves.
//  * `InitializeConditionVariable` / "Condition Variables": "the caller must
//    allocate a CONDITION_VARIABLE structure and initialize it".
//  * `SleepConditionVariableSRW(cond, lock, dwMilliseconds, Flags)`: "The
//    time-out interval, in milliseconds. The function returns if the
//    interval elapses"; Flags other than CONDITION_VARIABLE_LOCKMODE_SHARED
//    = exclusive mode; "If the timeout expires the function returns FALSE";
//    "Condition variables are subject to spurious wakeups … recheck a
//    predicate (typically in a while loop)" — [BoundedCaller.call] does.
//  * `WakeAllConditionVariable`: wakes every waiter; "either inside or
//    outside the lock" ("Condition Variables").
//  * `ReleaseSRWLockExclusive`: "The SRW lock must be released by the same
//    thread that acquired it." — [BoundedCaller] acquires and releases
//    inside one synchronous span of one isolate.
// `SRWLOCK` and `CONDITION_VARIABLE` are one pointer each (`winnt.h`:
// `typedef struct _RTL_SRWLOCK { PVOID Ptr; }`,
// `typedef struct _RTL_CONDITION_VARIABLE { PVOID Ptr; }`); 64 bytes are
// reserved, `calloc` zeroes them (= SRWLOCK_INIT / CONDITION_VARIABLE_INIT)
// and aligns them.

typedef _WinPtrNative = Void Function(Pointer<Void>);
typedef _WinPtrDart = void Function(Pointer<Void>);
typedef _SleepCvSrwNative = Int32 Function(
    Pointer<Void>, Pointer<Void>, Uint32, Uint32);
typedef _SleepCvSrwDart = int Function(Pointer<Void>, Pointer<Void>, int, int);

/// The kernel32 [WaitPrimitives], looked up once per isolate. Throws where
/// kernel32.dll does not load (every platform but Windows).
class Win32WaitPrimitives implements WaitPrimitives {
  final _WinPtrDart _initLock;
  final _WinPtrDart _initCond;
  final _WinPtrDart _acquire;
  final _WinPtrDart _release;
  final _WinPtrDart _wakeAll;
  final _SleepCvSrwDart _sleep;

  Win32WaitPrimitives._(this._initLock, this._initCond, this._acquire,
      this._release, this._wakeAll, this._sleep);

  factory Win32WaitPrimitives() {
    final k = DynamicLibrary.open('kernel32.dll');
    _WinPtrDart f(String name) =>
        k.lookupFunction<_WinPtrNative, _WinPtrDart>(name);
    return Win32WaitPrimitives._(
      f('InitializeSRWLock'),
      f('InitializeConditionVariable'),
      f('AcquireSRWLockExclusive'),
      f('ReleaseSRWLockExclusive'),
      f('WakeAllConditionVariable'),
      k.lookupFunction<_SleepCvSrwNative, _SleepCvSrwDart>(
          'SleepConditionVariableSRW'),
    );
  }

  @override
  int get objectBytes => 64;

  @override
  bool init(Pointer<Void> lock, Pointer<Void> cond) {
    _initLock(lock);
    _initCond(cond);
    return true;
  }

  @override
  void lock(Pointer<Void> lock) => _acquire(lock);

  @override
  void unlock(Pointer<Void> lock) => _release(lock);

  @override
  void wakeAll(Pointer<Void> cond) => _wakeAll(cond);

  /// Flags 0 = the lock is held in exclusive mode. [ms] is at least 1 here
  /// ([BoundedCaller.call] stops at 0), never INFINITE (0xFFFFFFFF).
  @override
  bool waitMs(Pointer<Void> cond, Pointer<Void> lock, int ms) =>
      _sleep(cond, lock, ms, 0) != 0;
}

/// A top-level constructor for [BoundedCaller.start] (sendable to the
/// helper isolate).
WaitPrimitives win32WaitPrimitives() => Win32WaitPrimitives();

const int _opRead = 0;
const int _opWrite = 1;
const int _opRemove = 2;
const int _opProbe = 3;

/// A [DpapiStore] whose every call is bounded in time (§4.5.2): the calls
/// of the store [open] builds run in one helper isolate; the caller waits
/// at most [readBound] (read, remove) or [writeBound] (write, probe) — the
/// same 3 s / 5 s as macOS (`keychain_ffi.dart`) and Linux
/// (`libsecret_ffi.dart`). On expiry: [kDpapiTimedOut]; while the helper is
/// still stuck, every further call answers [kDpapiTimedOut] at once
/// ([BoundedCaller]).
class BoundedDpapiStore implements DpapiStore {
  final BoundedCaller _caller;
  final Duration readBound;
  final Duration writeBound;

  BoundedDpapiStore._(this._caller, this.readBound, this.writeBound);

  /// Spawns and confirms the helper. MUST be awaited before the first call.
  /// `null` when the primitives do not load or the helper is not confirmed.
  /// [primitives] defaults to kernel32; the smoke hands in the POSIX ones.
  static Future<BoundedDpapiStore?> start(DpapiStore Function() open,
      {WaitPrimitives Function() primitives = win32WaitPrimitives,
      Duration readBound = const Duration(seconds: 3),
      Duration writeBound = const Duration(seconds: 5)}) async {
    final caller = await BoundedCaller.start(
        primitives, _DpapiWorkerFactory(open).build,
        errorStatus: kDpapiIoError);
    if (caller == null) return null;
    return BoundedDpapiStore._(caller, readBound, writeBound);
  }

  int _status(List<Object?> request, Duration bound) {
    final a = _caller.call(request, bound);
    return a.timedOut ? kDpapiTimedOut : a.status;
  }

  @override
  DpapiRead read(String name) {
    final a = _caller.call(<Object?>[_opRead, name], readBound);
    if (a.timedOut) return const DpapiRead(kDpapiTimedOut);
    return DpapiRead(a.status, a.data);
  }

  @override
  int write(String name, Uint8List data) =>
      _status(<Object?>[_opWrite, name, data], writeBound);

  @override
  int remove(String name) => _status(<Object?>[_opRemove, name], readBound);

  @override
  int probe() => _status(<Object?>[_opProbe, ''], writeBound);
}

class _DpapiWorkerFactory {
  final DpapiStore Function() open;
  const _DpapiWorkerFactory(this.open);
  BoundedWorker build() => _DpapiWorker(open());
}

/// Executes the requests of [BoundedDpapiStore] in the helper isolate.
class _DpapiWorker implements BoundedWorker {
  final DpapiStore store;
  _DpapiWorker(this.store);

  @override
  BoundedReply handle(List<Object?> m) {
    final name = m[1] as String;
    switch (m[0] as int) {
      case _opRead:
        final r = store.read(name);
        return BoundedReply(r.status, r.value);
      case _opWrite:
        final data = m[2] as Uint8List;
        try {
          return BoundedReply(store.write(name, data));
        } finally {
          data.fillRange(0, data.length, 0);
        }
      case _opRemove:
        return BoundedReply(store.remove(name));
      case _opProbe:
        return BoundedReply(store.probe());
    }
    return const BoundedReply(kDpapiIoError);
  }
}
