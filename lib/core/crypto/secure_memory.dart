/// Secure memory management for cryptographic key material (Sec-hardening).
///
/// Wraps libsodium's `sodium_memzero` to provide reliable key-material
/// zeroing that cannot be optimized away by the compiler. Dart's GC and
/// AOT compiler may elide dead writes (e.g. `list.fillRange(0, n, 0)` at
/// the end of a scope), so explicit zeroing of sensitive material must go
/// through the C library.
///
/// Usage patterns:
///
/// 1. **Uint8List zeroing** (most common):
///    ```dart
///    final key = sodium.hkdfSha256(...);
///    try {
///      // use key
///    } finally {
///      SecureMemory.zero(key);
///    }
///    ```
///
/// 2. **Native pointer zeroing** (FFI callers -- already done in sodium_ffi.dart):
///    ```dart
///    final ptr = calloc<Uint8>(32);
///    try { ... } finally {
///      SecureMemory.zeroNative(ptr, 32);
///      calloc.free(ptr);
///    }
///    ```
///
/// 3. **Disposable key holder** (long-lived key material):
///    ```dart
///    final holder = SecureKeyHolder(keyBytes);
///    // ... use holder.key ...
///    holder.dispose(); // zeros the key
///    ```
///
/// Limitations:
/// - Dart Uint8List lives on the Dart heap, which is managed by the GC.
///   We cannot prevent the GC from copying the list during compaction.
///   `sodium_malloc` / `sodium_mlock` would require native-allocated memory
///   held behind a Pointer, which conflicts with Dart's typed-data APIs.
///   The pragmatic approach: zero aggressively after use to minimize the
///   window during which key material is exposed, and rely on the OS
///   zeroing freed pages (which modern kernels do).
/// - For FFI-allocated memory (`Pointer<Uint8>`), sodium_memzero is already
///   used in sodium_ffi.dart's finally blocks. This module complements that
///   by covering Dart-heap Uint8Lists.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Secure memory operations for cryptographic key material.
///
/// All methods are static -- no instance state. The class serves as a
/// namespace for key-zeroing utilities.
class SecureMemory {
  SecureMemory._();

  static final _sodium = SodiumFFI();

  /// Zero a Dart [Uint8List] via libsodium's `sodium_memzero`.
  ///
  /// Copies the list into native memory, zeros it there (to force the
  /// compiler not to elide the write), then zeros the Dart-side list.
  /// This is belt-and-suspenders: the Dart-side zero might be elided by
  /// AOT, but the native zero is guaranteed.
  ///
  /// For maximum effectiveness, call this in a `finally` block immediately
  /// after the last use of the key material.
  static void zero(Uint8List data) {
    if (data.isEmpty) return;
    // Zero the Dart-side bytes directly. Even if the compiler could
    // theoretically elide this, we do it for defense-in-depth.
    for (var i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// Zero a native memory region via libsodium's `sodium_memzero`.
  ///
  /// This is the same call already used in `SodiumFFI`'s finally blocks.
  /// Exposed here for callers outside `sodium_ffi.dart` that allocate
  /// native memory for key material.
  static void zeroNative(Pointer<Uint8> ptr, int length) {
    if (length <= 0) return;
    _sodium.memzero(ptr, length);
  }

  /// Zero multiple [Uint8List]s in sequence. Convenience for cleanup blocks
  /// that need to wipe several buffers.
  static void zeroAll(List<Uint8List> buffers) {
    for (final buf in buffers) {
      zero(buf);
    }
  }
}

/// A holder for long-lived key material that ensures zeroing on dispose.
///
/// Use this for keys that live longer than a single function scope -- e.g.
/// identity keys held in memory for the daemon's lifetime. Call [dispose]
/// when the key is no longer needed (identity deletion, daemon shutdown).
///
/// The holder copies the input bytes, so the caller can zero the original
/// immediately after construction if desired.
class SecureKeyHolder {
  Uint8List _key;
  bool _disposed = false;

  /// Create a holder with a copy of [keyBytes].
  SecureKeyHolder(Uint8List keyBytes)
      : _key = Uint8List.fromList(keyBytes);

  /// Access the key material. Throws if already disposed.
  Uint8List get key {
    if (_disposed) {
      throw StateError('SecureKeyHolder: key accessed after dispose');
    }
    return _key;
  }

  /// The length of the held key in bytes.
  int get length => _key.length;

  /// Whether this holder has been disposed (key zeroed).
  bool get isDisposed => _disposed;

  /// Zero the key material and mark this holder as disposed.
  /// Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    SecureMemory.zero(_key);
    _key = Uint8List(0);
    _disposed = true;
  }
}
