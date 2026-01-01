import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── A synchronous call with a deadline (§4.5.2 "Every keyring call is
//    bounded in time; a locked keyring never makes the application hang") ──
//
// A synchronous FFI call blocks its isolate until the native side returns,
// and none of the keyring APIs of macOS (Security.framework) or Windows
// (DPAPI, crypt32) offers a cancellation handle. The bound is therefore the
// textbook "work on another thread, wait on a condition variable with a
// timeout": the call runs in one helper isolate (every isolate runs on a
// thread of the VM pool), spawned and confirmed BEFORE the first guarded
// call (`KeyringService.init`), and the caller waits for its answer in a
// NATIVE timed wait — which, unlike a `ReceivePort`, can be awaited from
// synchronous code, so the `KeyringService` interface stays synchronous.
// `SendPort.send` is a non-blocking enqueue: the request reaches the helper
// while the caller is already waiting.
//
// The wait logic below is the same on every platform; only the lock and the
// condition variable differ ([WaitPrimitives]): POSIX `pthread_*` on macOS
// and Linux (`keychain_ffi.dart`), kernel32 SRW lock + condition variable on
// Windows (`dpapi_ffi.dart`). Lock and unlock always happen inside one
// synchronous span of one isolate, so they run on one OS thread — both
// `pthread_mutex_unlock` and `ReleaseSRWLockExclusive` require the thread
// that acquired the lock.

/// The native lock and condition variable of one platform. Built once per
/// isolate (an isolate does not share its parent's `DynamicLibrary`
/// handles); the objects themselves live in shared native memory.
abstract class WaitPrimitives {
  /// Bytes to reserve for one lock and for one condition variable.
  int get objectBytes;

  /// Initialises the lock at [lock] and the condition at [cond]. `false`
  /// when the platform refused.
  bool init(Pointer<Void> lock, Pointer<Void> cond);

  void lock(Pointer<Void> lock);
  void unlock(Pointer<Void> lock);

  /// Wakes every waiter on [cond]. Called with [lock] held.
  void wakeAll(Pointer<Void> cond);

  /// Releases [lock], sleeps on [cond] for at most [ms] milliseconds and
  /// re-acquires [lock]. `true` when woken (possibly spuriously — the caller
  /// rechecks its predicate), `false` on timeout or any error.
  bool waitMs(Pointer<Void> cond, Pointer<Void> lock, int ms);
}

/// The answer one helper call produced: a platform status and, optionally,
/// value bytes.
class BoundedReply {
  final int status;
  final Uint8List? data;
  const BoundedReply(this.status, [this.data]);
}

/// The object the helper isolate builds and hands every request to.
abstract class BoundedWorker {
  /// Executes [request]. Runs in the helper isolate; may block for as long
  /// as the platform blocks. [errorStatus] of [BoundedCaller] answers for a
  /// worker that throws.
  BoundedReply handle(List<Object?> request);
}

/// What the caller gets back.
class BoundedAnswer {
  /// The helper did not answer within the bound, or an earlier call that did
  /// not answer is still running. [status] and [data] are then meaningless.
  final bool timedOut;
  final int status;
  final Uint8List? data;
  const BoundedAnswer._(this.timedOut, this.status, this.data);
  static const BoundedAnswer timeout = BoundedAnswer._(true, 0, null);
}

/// Fields of the shared slot (an `int64` array in native memory, read and
/// written only under the lock).
const int _slotRequested = 0; // sequence number of the last request
const int _slotDone = 1; // sequence number of the last answer
const int _slotStatus = 2; // status of the last answer
const int _slotData = 3; // address of a malloc'd value buffer, or 0
const int _slotLength = 4; // its length
const int _slotFields = 5;

/// Runs the requests of one [BoundedWorker] in a helper isolate; every
/// [call] waits at most its bound.
///
/// A call made while the helper is still stuck in an earlier one answers
/// [BoundedAnswer.timeout] AT ONCE instead of queuing behind it: every
/// keyring call of a process goes to the same service (`securityd`, the
/// DPAPI of the session), so a second helper would hang the same way, and
/// the profile watchdog (every 30 s, §4.5.2) would leave one stuck thread
/// behind per round. Once the stuck call returns, the helper serves again;
/// its late answer is zeroed and discarded by the next call.
class BoundedCaller {
  final SendPort _worker;
  final WaitPrimitives _w;
  final Pointer<Void> _lock;
  final Pointer<Void> _cond;
  final Pointer<Int64> _slot;

  /// Keeps the handshake port alive for the life of the process.
  // ignore: unused_field
  final RawReceivePort _reply;

  BoundedCaller._(
      this._worker, this._w, this._lock, this._cond, this._slot, this._reply);

  /// Spawns the helper isolate, which builds its primitives with
  /// [primitives] and its worker with [open], and confirms it is listening.
  /// MUST be awaited before the first call. `null` when the primitives do
  /// not load or the helper could not be confirmed — the caller then never
  /// falls back to an unbounded call.
  ///
  /// [primitives] and [open] are sent to the helper: top-level functions or
  /// tear-offs of objects whose fields can cross isolates.
  static Future<BoundedCaller?> start(WaitPrimitives Function() primitives,
      BoundedWorker Function() open,
      {required int errorStatus}) async {
    final WaitPrimitives w;
    try {
      w = primitives();
    } catch (_) {
      return null;
    }
    final lock = calloc<Uint8>(w.objectBytes).cast<Void>();
    final cond = calloc<Uint8>(w.objectBytes).cast<Void>();
    final slot = calloc<Int64>(_slotFields);
    if (!w.init(lock, cond)) return null;
    final completer = Completer<SendPort?>();
    final reply = RawReceivePort();
    reply.handler = (Object? message) {
      if (completer.isCompleted) return;
      // Anything but a SendPort is the onError answer of a helper that
      // failed on startup.
      completer.complete(message is SendPort ? message : null);
    };
    SendPort? worker;
    try {
      await Isolate.spawn(_workerEntry, <Object?>[
        reply.sendPort,
        primitives,
        open,
        lock.address,
        cond.address,
        slot.address,
        errorStatus,
      ], onError: reply.sendPort);
      worker = await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      worker = null;
    }
    if (worker == null) {
      reply.close();
      // lock, cond and slot stay allocated: a helper that started late may
      // still hold their addresses.
      return null;
    }
    return BoundedCaller._(worker, w, lock, cond, slot, reply);
  }

  static void _workerEntry(List<Object?> args) {
    final replyTo = args[0] as SendPort;
    final w = (args[1] as WaitPrimitives Function())();
    final worker = (args[2] as BoundedWorker Function())();
    final lock = Pointer<Void>.fromAddress(args[3] as int);
    final cond = Pointer<Void>.fromAddress(args[4] as int);
    final slot = Pointer<Int64>.fromAddress(args[5] as int);
    final errorStatus = args[6] as int;
    final port = RawReceivePort();
    port.handler = (Object? message) {
      final m = message as List<Object?>;
      final seq = m[0] as int;
      BoundedReply r;
      try {
        r = worker.handle(m.sublist(1));
      } catch (_) {
        r = BoundedReply(errorStatus);
      }
      final data = r.data;
      var buf = nullptr.cast<Uint8>();
      if (data != null) {
        buf = malloc<Uint8>(data.isEmpty ? 1 : data.length);
        buf.asTypedList(data.length).setAll(0, data);
        data.fillRange(0, data.length, 0);
      }
      w.lock(lock);
      slot[_slotStatus] = r.status;
      slot[_slotData] = buf.address;
      slot[_slotLength] = data?.length ?? 0;
      slot[_slotDone] = seq;
      w.wakeAll(cond);
      w.unlock(lock);
    };
    replyTo.send(port.sendPort);
  }

  /// Zeroes and frees a value buffer the slot still holds. Under the lock.
  Uint8List? _takeData() {
    final address = _slot[_slotData];
    if (address == 0) return null;
    final len = _slot[_slotLength];
    final buf = Pointer<Uint8>.fromAddress(address);
    final view = buf.asTypedList(len);
    final copy = Uint8List.fromList(view);
    view.fillRange(0, len, 0);
    malloc.free(buf);
    _slot[_slotData] = 0;
    _slot[_slotLength] = 0;
    return copy;
  }

  /// Sends [request] to the worker and waits at most [bound] for its
  /// answer. A request carrying a secret (a `Uint8List`) is copied by the
  /// send; the worker zeroes its copy.
  BoundedAnswer call(List<Object?> request, Duration bound) {
    final int seq;
    _w.lock(_lock);
    try {
      if (_slot[_slotRequested] != _slot[_slotDone]) {
        // An earlier call is still stuck in the helper: do not queue.
        return BoundedAnswer.timeout;
      }
      // A late answer to a call that already timed out: discard it.
      final stale = _takeData();
      stale?.fillRange(0, stale.length, 0);
      seq = _slot[_slotRequested] + 1;
      _slot[_slotRequested] = seq;
    } finally {
      _w.unlock(_lock);
    }
    _worker.send(<Object?>[seq, ...request]);

    // A monotonic clock for the remaining time: a wake-up (real or
    // spurious) re-enters the wait with what is left, never with the full
    // bound again.
    final clock = Stopwatch()..start();
    final boundMs = bound.inMilliseconds;
    _w.lock(_lock);
    try {
      while (_slot[_slotDone] != seq) {
        final left = boundMs - clock.elapsedMilliseconds;
        if (left <= 0) break;
        if (!_w.waitMs(_cond, _lock, left)) break;
      }
      if (_slot[_slotDone] != seq) return BoundedAnswer.timeout;
      return BoundedAnswer._(false, _slot[_slotStatus], _takeData());
    } finally {
      _w.unlock(_lock);
    }
  }
}
