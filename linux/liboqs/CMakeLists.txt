# =============================================================================
# linux/liboqs — liboqs for the Linux bundle, from the pinned upstream source
# =============================================================================
#
# WHY (S410, finding I-6, owner decision C 29.10.2026): the Linux app opens
# liboqs by name (lib/core/crypto/oqs_ffi.dart -> linux_native_libraries.dart),
# and no distribution Cleona targets packages it (Ubuntu 24.04:
# `apt-cache search liboqs` is empty). Until S410 the Linux bundle did not
# carry it — the app only ran where a developer had built liboqs by hand.
#
# WHY HERE AND NOT UNDER native/: native/<name>/ holds Cleona's OWN shims,
# and the preflight requires each of them on Android and Windows as well.
# This is a Linux-only build of a third-party library; Android, iOS, macOS
# and Windows build the same pin through their own scripts (below).
#
# ONE PROJECT, TWO CALLERS, one pin:
#   * linux/CMakeLists.txt  add_subdirectory -> installs the library as
#                           bundle/lib/liboqs.so (Flutter bundle, tar.gz,
#                           .deb, .rpm, AppImage, in-app update)
#   * scripts/build-daemon.sh  standalone build -> build/daemon/lib/liboqs.so
#     (with Ninja like the Flutter build: measured 29.10.2026, both then give
#     a byte-identical file; "Unix Makefiles" links in another object order)
#
# THE PIN is the one every other platform builds:
#   scripts/build-android-libs.sh, scripts/build-ios-libs.sh,
#   scripts/build-macos-libs.sh   LIBOQS_VERSION="0.15.0"
#   windows/provision-liboqs.ps1  0.15.0 -> 97f6b86b1b6d109cfd43cf276ae39c2e776aed80
# The archive below is pinned by its SHA-256, not by the movable tag. Measured
# 29.10.2026: the archive of tag 0.15.0
#   https://github.com/open-quantum-safe/liboqs/archive/refs/tags/0.15.0.tar.gz
# has SHA-256 3983f7cd1247f37fb76a040e6fd684894d44a84cecdcfbdb90559b3216684b5c
# and its tree is byte-identical (`diff -r`) to a `git clone --branch 0.15.0`
# whose HEAD is 97f6b86b1b6d109cfd43cf276ae39c2e776aed80 — the commit the
# Windows build pins. A changed archive fails the download (URL_HASH), it is
# never built.
#
# THE OPTIONS are those of the four other platforms: only ML-KEM-768 and
# ML-DSA-65 (the two algorithms oqs_ffi.dart names), no OpenSSL (so the
# library needs nothing but libc), OQS_DIST_BUILD=ON (runtime CPU dispatch —
# without it liboqs tunes for the build machine's CPU and may crash with an
# illegal instruction on an older one).
#
# OUTPUT: CLEONA_OQS_LIBRARY (cache) — the real file liboqs.so.0.15.0 (soname
# liboqs.so.9, `src/CMakeLists.txt` of 0.15.0: `SOVERSION 9`). Callers copy
# THIS file, not the liboqs.so symlink: install(FILES … RENAME) would copy a
# symlink as a symlink and leave it dangling.
#
# Network: the first configure of a fresh build directory downloads the
# archive (like FetchContent for libopus in linux/CMakeLists.txt); a rebuild
# in the same directory needs none.
cmake_minimum_required(VERSION 3.16)
project(cleona_oqs LANGUAGES NONE)

include(ExternalProject)

set(CLEONA_OQS_VERSION "0.15.0")
set(CLEONA_OQS_SHA256 "3983f7cd1247f37fb76a040e6fd684894d44a84cecdcfbdb90559b3216684b5c")
set(CLEONA_OQS_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/liboqs-install")
set(CLEONA_OQS_LIBRARY "${CLEONA_OQS_PREFIX}/lib/liboqs.so.${CLEONA_OQS_VERSION}"
    CACHE FILEPATH "liboqs built from the pinned source (real file, not the symlink)" FORCE)

ExternalProject_Add(cleona_oqs
  URL               "https://github.com/open-quantum-safe/liboqs/archive/refs/tags/${CLEONA_OQS_VERSION}.tar.gz"
  URL_HASH          "SHA256=${CLEONA_OQS_SHA256}"
  DOWNLOAD_NO_PROGRESS TRUE
  # The list separator: OQS_MINIMAL_BUILD takes a ';' list, which
  # ExternalProject would otherwise split into separate arguments.
  LIST_SEPARATOR    |
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=${CLEONA_OQS_PREFIX}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DBUILD_SHARED_LIBS=ON
    -DOQS_BUILD_ONLY_LIB=ON
    -DOQS_USE_OPENSSL=OFF
    -DOQS_MINIMAL_BUILD=KEM_ml_kem_768|SIG_ml_dsa_65
    -DOQS_DIST_BUILD=ON
  BUILD_BYPRODUCTS  "${CLEONA_OQS_LIBRARY}"
)
