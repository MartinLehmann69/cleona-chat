import 'dart:ffi';

import 'app_paths.dart';

/// The three libraries every Linux process of Cleona (window AND daemon)
/// opens by name, and the one place that says under which names.
///
/// ══════════════════════════════════════════════════════════════════════
/// WHY THIS FILE EXISTS (S410, finding I-6, owner decision C 29.10.2026)
/// ══════════════════════════════════════════════════════════════════════
///
/// Until S410 the loaders in `sodium_ffi.dart`, `oqs_ffi.dart` and
/// `compression.dart` opened `libsodium.so`, `liboqs.so` and `libzstd.so`,
/// then the same names under `<bundle>/lib`. The unversioned name of a
/// distribution library is shipped ONLY by its development package
/// (Ubuntu 24.04, measured 29.10.2026 with `dpkg -S`: `libsodium.so` belongs
/// to `libsodium-dev`, `libsodium.so.23` to `libsodium23`; `libzstd.so` to
/// `libzstd-dev`, `libzstd.so.1` to `libzstd1`), and the bundle carried none
/// of the three. On a system without development packages the window and
/// the daemon could not start — and liboqs is packaged by no distribution
/// Cleona targets (`apt-cache search liboqs` on Ubuntu 24.04: empty).
///
/// Decision C:
///   * libsodium and libzstd come from the SYSTEM: first the runtime
///     sonames the distribution packages ship, then `<bundle>/lib` (only the
///     AppImage carries them there), last the unversioned name (a developer
///     machine, the smoke tests under `dart`/`flutter test`).
///   * liboqs ships IN THE BUNDLE and is found there first
///     (`linux/liboqs`, pinned 0.15.0 like every other platform).
///   * A missing library is named, with the package that provides it —
///     [missing] is what the window and the daemon ask at start.
///
/// The guard `test/smoke/smoke_linux_native_libraries.dart` checks the
/// statement "a runtime-only system finds every library" against this table,
/// and that no other file opens these three on Linux by its own list.
/// `scripts/release-build.sh` (`linux_bundle_check`) reads the
/// `LinuxBundleFile.always(...)` entries below: a bundle without such a file
/// is not shipped. Keep each `LinuxBundleFile.always('<name>')` on ONE line.
///
/// Nothing here touches the wire: which file is loaded does not change a
/// single byte any 4.2 peer receives.
class LinuxNativeLibrary {
  /// Library name as a person searches for it (`libsodium`).
  final String name;

  /// Runtime sonames of the distribution packages, newest first.
  final List<String> systemSonames;

  /// The file under `<bundle>/lib` and whether every bundle carries it.
  final LinuxBundleFile bundle;

  /// The unversioned name — only a development package provides it.
  final String developmentName;

  /// Package names to install, per family (shown to the user verbatim).
  final List<String> packageHints;

  const LinuxNativeLibrary({
    required this.name,
    required this.systemSonames,
    required this.bundle,
    required this.developmentName,
    required this.packageHints,
  });

  /// The candidates in the order the loader tries them.
  ///
  /// A library every bundle carries is looked for in the bundle FIRST: that
  /// copy is the pinned build the release was made with. A system library
  /// is looked for under its runtime soname first; the bundle copy (AppImage
  /// only) is the fallback for a system without the package.
  List<String> candidates(String bundleLibDir) {
    final inBundle = '$bundleLibDir/${bundle.fileName}';
    return [
      if (bundle.inEveryBundle) inBundle,
      ...systemSonames,
      if (!bundle.inEveryBundle) inBundle,
      developmentName,
    ];
  }
}

/// A library's file in `<bundle>/lib`.
class LinuxBundleFile {
  final String fileName;

  /// True: every Linux bundle (tar.gz, .deb, .rpm, AppImage, in-app update)
  /// carries it. False: only the AppImage does (its convention is to carry
  /// everything); the other formats take the library from the system.
  final bool inEveryBundle;

  const LinuxBundleFile.always(this.fileName) : inEveryBundle = true;
  const LinuxBundleFile.appImageOnly(this.fileName) : inEveryBundle = false;
}

/// libsodium. Soname 26 is libsodium 1.0.19 and later — the same 1.0.20 the
/// Android, iOS, macOS and Windows builds pin (`scripts/build-ios-libs.sh`
/// `LIBSODIUM_VERSION`); soname 23 is 1.0.18. Sources, read 29.10.2026:
///   * Debian sid/forky `libsodium26` ships
///     `/usr/lib/x86_64-linux-gnu/libsodium.so.26`
///     (packages.debian.org/sid/amd64/libsodium26/filelist);
///     bookworm/trixie ship `libsodium23` (`libsodium.so.23`).
///   * Ubuntu 22.04/24.04/26.04: libsodium 1.0.18 (`libsodium23`);
///     the series after 26.04: 1.0.22 (`libsodium26`)
///     (launchpad.net/ubuntu/+source/libsodium).
///   * Fedora rawhide `libsodium` 1.0.22 provides `libsodium.so.26()(64bit)`
///     (packages.fedoraproject.org/pkgs/libsodium/libsodium/fedora-rawhide.html);
///     EPEL 8/9 carry 1.0.18.
const LinuxNativeLibrary linuxSodium = LinuxNativeLibrary(
  name: 'libsodium',
  systemSonames: ['libsodium.so.26', 'libsodium.so.23'],
  bundle: LinuxBundleFile.appImageOnly('libsodium.so'),
  developmentName: 'libsodium.so',
  packageHints: [
    'Debian/Ubuntu: libsodium23 | libsodium26',
    'Fedora: libsodium',
  ],
);

/// libzstd. Soname 1 for every 1.x release. Sources, read 29.10.2026:
/// Ubuntu 24.04 `dpkg -S`: `libzstd1` ships `libzstd.so.1`; Fedora rawhide
/// `libzstd` provides `libzstd.so.1()(64bit)`
/// (packages.fedoraproject.org/pkgs/zstd/libzstd/fedora-rawhide.html).
const LinuxNativeLibrary linuxZstd = LinuxNativeLibrary(
  name: 'libzstd',
  systemSonames: ['libzstd.so.1'],
  bundle: LinuxBundleFile.appImageOnly('libzstd.so'),
  developmentName: 'libzstd.so',
  packageHints: [
    'Debian/Ubuntu: libzstd1',
    'Fedora: libzstd',
  ],
);

/// liboqs, built from the pinned 0.15.0 source by `linux/liboqs` and
/// shipped in every bundle. Soname 9 is the one 0.15.0 sets itself
/// (`src/CMakeLists.txt`: `SOVERSION 9`, read in the 0.15.0 source,
/// commit 97f6b86b1b6d109cfd43cf276ae39c2e776aed80) — a system copy of the
/// same ABI is the fallback, the unversioned name the developer machine.
const LinuxNativeLibrary linuxOqs = LinuxNativeLibrary(
  name: 'liboqs',
  systemSonames: ['liboqs.so.9'],
  bundle: LinuxBundleFile.always('liboqs.so'),
  developmentName: 'liboqs.so',
  packageHints: [],
);

/// Every library of this table, in start order.
const List<LinuxNativeLibrary> linuxNativeLibraries = [
  linuxSodium,
  linuxOqs,
  linuxZstd,
];

/// A library none of whose candidates could be opened.
class NativeLibraryMissingException implements Exception {
  final LinuxNativeLibrary library;
  final List<String> tried;

  const NativeLibraryMissingException(this.library, this.tried);

  /// True when the library ships with Cleona — then reinstalling Cleona,
  /// not a system package, is the remedy.
  bool get shipsWithCleona => library.bundle.inEveryBundle;

  /// One line for a log or a console: what is missing, what fixes it.
  String describe() {
    final remedy = shipsWithCleona
        ? 'ships with Cleona — the installation is incomplete, install Cleona again'
        : 'install ${library.packageHints.join(' or ')}';
    return '${library.name} not found (tried: ${tried.join(', ')}) — $remedy';
  }

  @override
  String toString() => 'NativeLibraryMissingException: ${describe()}';
}

/// Opens [library] through its candidates; [open] is `DynamicLibrary.open`
/// outside tests.
DynamicLibrary openLinuxNativeLibrary(
  LinuxNativeLibrary library, {
  String? bundleLibDir,
  DynamicLibrary Function(String path) open = DynamicLibrary.open,
}) {
  final tried = library.candidates(bundleLibDir ?? AppPaths.bundleLibDir);
  for (final candidate in tried) {
    try {
      return open(candidate);
    } catch (_) {}
  }
  throw NativeLibraryMissingException(library, tried);
}

/// The libraries of the table that cannot be opened — empty when all can.
///
/// Asked by the window and the daemon at start, BEFORE the first crypto
/// call, so a missing library is reported by name instead of as the first
/// exception some later code path happens to hit (libzstd e.g. is otherwise
/// opened only at the first compression).
List<NativeLibraryMissingException> missingLinuxNativeLibraries({
  String? bundleLibDir,
  DynamicLibrary Function(String path) open = DynamicLibrary.open,
}) {
  final missing = <NativeLibraryMissingException>[];
  for (final library in linuxNativeLibraries) {
    try {
      openLinuxNativeLibrary(library, bundleLibDir: bundleLibDir, open: open);
    } on NativeLibraryMissingException catch (e) {
      missing.add(e);
    }
  }
  return missing;
}
