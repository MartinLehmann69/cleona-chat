/// Dart binding to `native/cleona_link` — Elligator2 for the V4 link handshake
/// (architecture v4 §2.6, build plan `docs/MIGRATION_V3_TO_V4_0_MYZEL.md` §4d, stage 0/2).
///
/// Stage 0 built the library and wired it on five platforms, but never
/// connected it to Dart; this file closes exactly that gap and nothing
/// else. It makes **no** handshake decision: framing of `init`, epoch
/// encoding, MAC truncation and the response direction are **not
/// specified** at the time of this file (measured 2026-08-19 across the
/// whole corpus) and therefore deliberately do not stand in here. This
/// file is therefore also independent of how those questions are decided:
/// the Elligator2 ABI has been frozen since stage 0.
///
/// **Why a shim at all.** libsodium does not export the needed direction
/// — only `crypto_core_ed25519_from_uniform` exists (the opposite
/// direction, and Ed25519 instead of X25519). Reasoning and procurement:
/// E-42, architecture v4 §20.4.1, migration plan §4d.5.
///
/// **The three contract details from `native/cleona_link/cleona_link.c`
/// that this binding must carry** — they stand there in the header comment
/// under "Vertragsdetails fuer die spaetere Dart-FFI-Bindung":
///
/// 1. `rev` returns `-1` if the point is not encodable (about half of all
///    points); `hidden` is then **undefined**. That is why [rev] returns
///    `null` and not, say, a buffer with an error code next to it — an
///    undefined buffer must never reach the caller.
/// 2. `key_pair` **wipes the passed seed** (Monocypher contract,
///    `crypto_wipe(seed, 32)`). Monocypher wipes the native copy; **this
///    binding** wipes the caller's `Uint8List`, otherwise Dart would keep
///    holding exactly the secret that C has just deleted, and the contract
///    would be broken on the Dart side.
/// 3. `key_pair` has **no constant running time** (on average two
///    attempts, because only about half of the points are encodable). That
///    is explicitly decided as harmless in §4d.5: the loop runs **before**
///    any wire contact on discarded candidates. Constant time is required
///    where a secret can be correlated — at the responder's MAC check
///    (stage 2), not here. Whoever "hardens" this loop later repairs
///    nothing and slows down connection setup.
///
/// Loading pattern: `native_udp_sender.dart` / `proof_of_work.dart`
/// (candidate list with bundle paths). Deliberate deviation from
/// `proof_of_work.dart`: there the library is optional and a load error
/// silently falls back to pure Dart. For Elligator2 there is **no** Dart
/// fallback — without the library there is no handshake, so this binding
/// throws.
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Length of every buffer of this interface: X25519 point, uniform
/// representation, secret key and seed are all 32 B (Monocypher ABI).
const int kElligatorBytes = 32;

// void cleona_link_elligator_map(uint8_t curve[32], const uint8_t hidden[32])
typedef _ElligatorMapNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint8> curve, ffi.Pointer<ffi.Uint8> hidden);
typedef _ElligatorMapDart = void Function(
    ffi.Pointer<ffi.Uint8> curve, ffi.Pointer<ffi.Uint8> hidden);

// int cleona_link_elligator_rev(uint8_t hidden[32], const uint8_t curve[32],
//                               uint8_t tweak)
typedef _ElligatorRevNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8> hidden,
    ffi.Pointer<ffi.Uint8> curve, ffi.Uint8 tweak);
typedef _ElligatorRevDart = int Function(
    ffi.Pointer<ffi.Uint8> hidden, ffi.Pointer<ffi.Uint8> curve, int tweak);

// void cleona_link_elligator_key_pair(uint8_t hidden[32],
//                                     uint8_t secret_key[32], uint8_t seed[32])
typedef _ElligatorKeyPairNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint8> hidden,
    ffi.Pointer<ffi.Uint8> secretKey,
    ffi.Pointer<ffi.Uint8> seed);
typedef _ElligatorKeyPairDart = void Function(ffi.Pointer<ffi.Uint8> hidden,
    ffi.Pointer<ffi.Uint8> secretKey, ffi.Pointer<ffi.Uint8> seed);

/// Thrown if `libcleona_link` cannot be loaded.
///
/// Deliberately with diagnostic text following the pattern of
/// `NativeUdpLibraryMissingException`: the most frequent reason is a bundle
/// into which the artefact was not copied, and that is hard to see without
/// a hint.
class ElligatorLibraryMissingException implements Exception {
  final List<String> triedPaths;
  final Object? underlyingError;

  const ElligatorLibraryMissingException(this.triedPaths, this.underlyingError);

  @override
  String toString() =>
      'libcleona_link could not be loaded.\n'
      'Tried: ${triedPaths.join(", ")}\n'
      'Underlying error: $underlyingError\n'
      'This is a hard dependency: the V4 link handshake (Architektur v4 §2.6) '
      'needs the Elligator2 encoding of the ephemeral X25519 key, and libsodium '
      'does not provide that direction (E-42). There is no Dart fallback. '
      'Most likely cause: the native artefact was not copied into the bundle. '
      'Rebuild native/cleona_link/ and deploy the .so/.dll/.dylib next to the '
      'application binary.';
}

/// Thrown on violation of the call contract (wrong buffer length).
class ElligatorException implements Exception {
  final String message;
  const ElligatorException(this.message);

  @override
  String toString() => 'ElligatorException: $message';
}

/// Elligator2 encoding for the link handshake.
///
/// Singleton like [SodiumFFI] — the library is opened once and the three
/// symbols bound eagerly.
class ElligatorFFI {
  static ElligatorFFI? _instance;

  factory ElligatorFFI() => _instance ??= ElligatorFFI._internal();

  late final _ElligatorMapDart _map;
  late final _ElligatorRevDart _rev;
  late final _ElligatorKeyPairDart _keyPair;

  ElligatorFFI._internal() {
    final lib = _openLibrary();
    _map = lib.lookupFunction<_ElligatorMapNative, _ElligatorMapDart>(
        'cleona_link_elligator_map');
    _rev = lib.lookupFunction<_ElligatorRevNative, _ElligatorRevDart>(
        'cleona_link_elligator_rev');
    _keyPair =
        lib.lookupFunction<_ElligatorKeyPairNative, _ElligatorKeyPairDart>(
            'cleona_link_elligator_key_pair');
  }

  /// Candidate list per platform — byte for byte the same convention as
  /// `native_udp_sender.dart` and `proof_of_work.dart`, so that the bundle
  /// build needs no second special case.
  static ffi.DynamicLibrary _openLibrary() {
    // iOS links statically; the three symbols stand in
    // ios/CleonaNative/cleona_exported_symbols.txt, otherwise the linker
    // strips them and this lookup would fail at runtime.
    if (Platform.isIOS) {
      try {
        return ffi.DynamicLibrary.process();
      } catch (e) {
        throw ElligatorLibraryMissingException(
            const ['DynamicLibrary.process() (iOS, statically linked)'], e);
      }
    }
    // Android: the linker resolves via jniLibs, no fallback needed.
    if (Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libcleona_link.so');
      } catch (e) {
        throw ElligatorLibraryMissingException(const ['libcleona_link.so'], e);
      }
    }

    // `AppPaths.bundleDir` instead of `File(exe).parent.path` (S367): since
    // the rework the daemon lies in `<bundleDir>/bin/`, because
    // `dart build cli` embeds the path of its storage library as `../lib/…`
    // relative to the binary. Its own directory is thus NO longer the
    // bundle root; for the GUI both are the same, nothing changes there.
    final candidates = <String>[];
    if (Platform.isLinux) {
      candidates.add('libcleona_link.so');
      try {
        candidates.add('${AppPaths.bundleDir}/lib/libcleona_link.so');
      } catch (_) {}
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        candidates.add('$home/cleona-app/lib/libcleona_link.so');
      }
      candidates.add(
          '${Directory.current.path}/build/cleona_link/libcleona_link.so');
      // The same one level higher — for a run from within a SUBPACKAGE of
      // the tree. The smokes of the delivery layer run by the convention in
      // CLAUDE.md as `cd mycelium && dart run test/<file>`; their
      // `Directory.current` is thus `<tree>/mycelium`, and the candidate above
      // never hit. Since the shell (package 7) mycelium needs Elligator2 on
      // every path, not only the application — without this path every
      // mycelium smoke would be bound to an environment variable, and such
      // a silent precondition is exactly the workaround that work rule 1
      // excludes.
      candidates.add(
          '${Directory.current.path}/../build/cleona_link/libcleona_link.so');
    } else if (Platform.isWindows) {
      candidates.add('cleona_link.dll');
      try {
        candidates.add('${AppPaths.bundleDir}\\cleona_link.dll');
      } catch (_) {}
    } else if (Platform.isMacOS) {
      candidates.add('libcleona_link.dylib');
      try {
        candidates.add('${AppPaths.macFrameworksDir}/libcleona_link.dylib');
      } catch (_) {}
      // Stays as a fallback: for the GUI it has always held.
      candidates.add('@executable_path/../Frameworks/libcleona_link.dylib');
    } else {
      throw ElligatorLibraryMissingException(
          const [], 'unsupported platform: ${Platform.operatingSystem}');
    }

    Object? lastError;
    for (final c in candidates) {
      try {
        return ffi.DynamicLibrary.open(c);
      } catch (e) {
        lastError = e;
      }
    }
    throw ElligatorLibraryMissingException(candidates, lastError);
  }

  /// Receiver direction: uniform bytes → X25519 curve point (u coordinate).
  ///
  /// Total function — every 32-B input maps to a point. That is the
  /// direction with which the receiver decodes an incoming `E2(eph_pub)`.
  Uint8List map(Uint8List hidden) {
    _requireLength(hidden, 'hidden');
    final outPtr = calloc<ffi.Uint8>(kElligatorBytes);
    final inPtr = calloc<ffi.Uint8>(kElligatorBytes);
    try {
      inPtr.asTypedList(kElligatorBytes).setAll(0, hidden);
      _map(outPtr, inPtr);
      return Uint8List.fromList(outPtr.asTypedList(kElligatorBytes));
    } finally {
      calloc.free(outPtr);
      calloc.free(inPtr);
    }
  }

  /// Send direction: X25519 curve point → uniform bytes.
  ///
  /// Returns `null` if the point is **not encodable** — that is the normal
  /// case for about half of all points and not an error. Whether a point is
  /// encodable does **not** depend on the [tweak]; a renewed attempt with a
  /// different tweak therefore does not help, a different key does (that
  /// is what [keyPair] is for).
  ///
  /// [tweak] is a random byte and chooses root and MSB padding bits.
  Uint8List? rev(Uint8List curve, int tweak) {
    _requireLength(curve, 'curve');
    if (tweak < 0 || tweak > 255) {
      throw ElligatorException('rev: tweak must be a byte, got $tweak');
    }
    final outPtr = calloc<ffi.Uint8>(kElligatorBytes);
    final inPtr = calloc<ffi.Uint8>(kElligatorBytes);
    try {
      inPtr.asTypedList(kElligatorBytes).setAll(0, curve);
      final rc = _rev(outPtr, inPtr, tweak);
      if (rc != 0) return null; // not encodable; outPtr is undefined
      return Uint8List.fromList(outPtr.asTypedList(kElligatorBytes));
    } finally {
      SodiumFFI().memzero(outPtr, kElligatorBytes);
      calloc.free(outPtr);
      calloc.free(inPtr);
    }
  }

  /// Key pair with a guaranteed encodable — i.e. already uniformly
  /// encoded — public part.
  ///
  /// **[seed] is deleted**, natively by Monocypher and on the Dart side by
  /// this binding. The caller must not reuse the buffer afterwards; after
  /// return it is demonstrably zeroed.
  ///
  /// The retry loop (on average two attempts) deliberately lies in C, so
  /// that it does not wander into the application code — §4d.5. It is
  /// **not** constant-time and need not be: it runs before any wire contact
  /// on discarded candidates.
  ({Uint8List hidden, Uint8List secretKey}) keyPair(Uint8List seed) {
    _requireLength(seed, 'seed');
    final hiddenPtr = calloc<ffi.Uint8>(kElligatorBytes);
    final skPtr = calloc<ffi.Uint8>(kElligatorBytes);
    final seedPtr = calloc<ffi.Uint8>(kElligatorBytes);
    try {
      seedPtr.asTypedList(kElligatorBytes).setAll(0, seed);
      _keyPair(hiddenPtr, skPtr, seedPtr);
      return (
        hidden: Uint8List.fromList(hiddenPtr.asTypedList(kElligatorBytes)),
        secretKey: Uint8List.fromList(skPtr.asTypedList(kElligatorBytes)),
      );
    } finally {
      // Contract 2: wipe the caller's buffer as well. Monocypher only
      // deleted the native copy.
      seed.fillRange(0, seed.length, 0);
      SodiumFFI().memzero(skPtr, kElligatorBytes);
      SodiumFFI().memzero(seedPtr, kElligatorBytes);
      calloc.free(hiddenPtr);
      calloc.free(skPtr);
      calloc.free(seedPtr);
    }
  }

  static void _requireLength(Uint8List buf, String name) {
    if (buf.length != kElligatorBytes) {
      throw ElligatorException(
          '$name must be $kElligatorBytes bytes, got ${buf.length}');
    }
  }
}
