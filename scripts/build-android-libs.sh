#!/bin/bash
###############################################################################
# build-android-libs.sh — Cross-compile native libs for Android
#
# Baut libsodium, liboqs, libzstd, libopus, whisper.cpp (inkl. libggml) sowie
# die libcleona_voice/libcleona_video Android-Backends (V1.2/V1.14) mit
# 16KB Page-Alignment (Android 15+).
# Ergebnis landet in android/app/src/main/jniLibs/<ABI>/
#
# Voraussetzungen: Android NDK (28.x), git, cmake, ninja-build, autoconf,
#                  automake, libtool
#
# Nutzung:
#   ./scripts/build-android-libs.sh                        # arm64-v8a (Default)
#   ./scripts/build-android-libs.sh --arch x86_64          # x86_64 (Emulator)
#   ./scripts/build-android-libs.sh --arch all             # Beide Architekturen
#   ./scripts/build-android-libs.sh --arch x86_64 sodium   # Nur libsodium x86_64
#   ./scripts/build-android-libs.sh whisper                # Nur whisper.cpp arm64
#   ./scripts/build-android-libs.sh voice                  # Nur libcleona_voice arm64
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse --arch flag
ARCH="arm64-v8a"
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# NDK Setup
NDK_DIR="$HOME/Android/ndk/28.2.13676358"
TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"
API_LEVEL=24  # minSdkVersion
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"
CMAKE_TOOLCHAIN="$NDK_DIR/build/cmake/android.toolchain.cmake"

# 16KB Page-Alignment (Android 15 Requirement)
PAGE_SIZE_FLAG="-Wl,-z,max-page-size=16384"

# Pin whisper.cpp version — MUST match iOS/macOS scripts.
# Die ausgelieferten jniLibs/XCFrameworks sind 1.8.4 (Versions-String in der
# Binary, plus whisper_vad_* und carry_initial_prompt, die es in v1.7.1 nicht
# gibt) — der Pin stand trotzdem auf v1.7.1. Ein sauberer Rebuild haette damit
# ein anderes whisper_full_params-Layout geliefert als die ausgelieferte
# Binary: `language` liegt in v1.7.1 bei Offset 96, in 1.8.4 bei 104.
# whisper_ffi.dart probed das Layout inzwischen zur Laufzeit, der Pin bleibt
# trotzdem die Referenz und muss stimmen.
WHISPER_VERSION="v1.8.4"

# Pin libopus version — MUST match scripts/build-ios-libs.sh and
# scripts/build-macos-libs.sh (V1.9's opus_ffi.dart talks to whichever backend
# a peer shipped; a version drift between platforms is a wire-format risk the
# same way an oqs/sodium drift would be).
LIBOPUS_VERSION="1.5.2"

setup_arch() {
    local arch="$1"
    case "$arch" in
        arm64-v8a)
            CC="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
            CXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"
            CONFIGURE_HOST="aarch64-linux-android"
            CMAKE_ABI="arm64-v8a"
            ;;
        x86_64)
            CC="$TOOLCHAIN/bin/x86_64-linux-android${API_LEVEL}-clang"
            CXX="$TOOLCHAIN/bin/x86_64-linux-android${API_LEVEL}-clang++"
            CONFIGURE_HOST="x86_64-linux-android"
            CMAKE_ABI="x86_64"
            ;;
        *) echo "Unbekannte Architektur: $arch (arm64-v8a oder x86_64)"; exit 1 ;;
    esac
    JNILIBS="$PROJECT_DIR/android/app/src/main/jniLibs/$arch"
    BUILD_DIR="/tmp/android-libs-build-$arch"
    mkdir -p "$BUILD_DIR" "$JNILIBS"
    export CC CXX CONFIGURE_HOST CMAKE_ABI JNILIBS BUILD_DIR
}

# Default setup (may be overridden by 'all' loop)
if [ "$ARCH" != "all" ]; then
    setup_arch "$ARCH"
fi

verify_alignment() {
    local lib="$1"
    local name; name="$(basename "$lib")"
    # Alignment is the last hex field on the continuation line after LOAD
    # Format: "   LOAD  0x... 0x... 0x...\n               0x... 0x...  R E  0x4000"
    local align; align=$(readelf -l "$lib" 2>/dev/null | grep -A1 '^\s*LOAD' | grep -v 'LOAD' | grep -oP '0x[0-9a-f]+' | tail -1 | head -1)
    if [ "$align" = "0x4000" ]; then
        echo "  [✓] $name: 16KB-aligned (0x4000)"
    else
        echo "  [✗] $name: Alignment=$align (erwartet 0x4000)"
        return 1
    fi
}

build_libsodium() {
    echo "=== libsodium bauen ==="
    local SRC="$BUILD_DIR/libsodium"

    if [ ! -d "$SRC" ]; then
        echo "  Klone libsodium (stable)..."
        git clone --depth 1 --branch stable https://github.com/jedisct1/libsodium.git "$SRC"
    fi

    cd "$SRC"
    make distclean 2>/dev/null || true
    ./autogen.sh

    ./configure \
        --host="$CONFIGURE_HOST" \
        --prefix="$BUILD_DIR/install/sodium" \
        --disable-static \
        --enable-shared \
        CC="$CC" \
        CXX="$CXX" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        CFLAGS="-O2 -fPIC" \
        LDFLAGS="$PAGE_SIZE_FLAG"

    make -j"$(nproc)" clean 2>/dev/null || true
    make -j"$(nproc)"
    make install

    cp "$BUILD_DIR/install/sodium/lib/libsodium.so" "$JNILIBS/libsodium.so"
    "$STRIP" "$JNILIBS/libsodium.so"
    verify_alignment "$JNILIBS/libsodium.so"
    echo "  → $JNILIBS/libsodium.so ($(du -h "$JNILIBS/libsodium.so" | cut -f1))"
}

build_liboqs() {
    echo "=== liboqs bauen ==="
    local LIBOQS_VERSION="0.15.0"
    local SRC="$BUILD_DIR/liboqs"

    if [ -d "$SRC" ]; then
        local cached_tag
        cached_tag=$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$cached_tag" != "$LIBOQS_VERSION" ]; then
            echo "  Cached liboqs is $cached_tag, need $LIBOQS_VERSION — re-cloning"
            rm -rf "$SRC"
        fi
    fi
    if [ ! -d "$SRC" ]; then
        echo "  Klone liboqs ($LIBOQS_VERSION)..."
        git clone --depth 1 --branch "$LIBOQS_VERSION" https://github.com/open-quantum-safe/liboqs.git "$SRC"
    fi

    local BUILD="$SRC/build-android"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install/oqs" \
        -DBUILD_SHARED_LIBS=ON \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_USE_OPENSSL=OFF \
        -DOQS_MINIMAL_BUILD="KEM_ml_kem_768;SIG_ml_dsa_65" \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        ..

    ninja -j"$(nproc)"
    ninja install

    cp "$BUILD_DIR/install/oqs/lib/liboqs.so" "$JNILIBS/liboqs.so"
    "$STRIP" "$JNILIBS/liboqs.so"
    verify_alignment "$JNILIBS/liboqs.so"
    echo "  → $JNILIBS/liboqs.so ($(du -h "$JNILIBS/liboqs.so" | cut -f1))"
}

build_libwhisper() {
    echo "=== whisper.cpp bauen (inkl. libggml) ==="
    local SRC="$BUILD_DIR/whisper.cpp"

    if [ ! -d "$SRC" ]; then
        echo "  Klone whisper.cpp ($WHISPER_VERSION)..."
        git clone --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggerganov/whisper.cpp.git "$SRC"
    fi

    local BUILD="$SRC/build-android"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # GGML_NATIVE=OFF: kein -march=native (wäre Host-Architektur statt ARM64).
    # GGML_NEON=ON: ARM NEON SIMD für schnellere Inference auf Android.
    # GGML_OPENMP=OFF: OpenMP braucht libomp.so das nicht im NDK-Sysroot ist.
    #   Whisper nutzt nur 1-4 Threads, NEON bringt mehr als OMP-Parallelismus.
    # WHISPER_BUILD_EXAMPLES/TESTS=OFF: nur Library, kein CLI-Tool.
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install/whisper" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF \
        -DGGML_NATIVE=OFF \
        -DGGML_NEON=ON \
        -DGGML_OPENMP=OFF \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        ..

    ninja -j"$(nproc)"

    # whisper.cpp baut: libwhisper.so, libggml.so, libggml-base.so, libggml-cpu.so
    # Alle .so finden (können in src/, ggml/src/ etc. liegen)
    for libname in libwhisper libggml-cpu libggml-base libggml; do
        local REAL_LIB; REAL_LIB=$(find "$BUILD" -name "${libname}.so*" -type f ! -type l 2>/dev/null | head -1)
        if [ -n "$REAL_LIB" ]; then
            cp "$REAL_LIB" "$JNILIBS/${libname}.so"
            "$STRIP" "$JNILIBS/${libname}.so"
            verify_alignment "$JNILIBS/${libname}.so"
            echo "  → $JNILIBS/${libname}.so ($(du -h "$JNILIBS/${libname}.so" | cut -f1))"
        else
            echo "  [!] ${libname}.so nicht gefunden im Build-Output"
        fi
    done
}

build_libzstd() {
    echo "=== libzstd bauen ==="
    local SRC="$BUILD_DIR/zstd"

    if [ ! -d "$SRC" ]; then
        echo "  Klone zstd (release)..."
        git clone --depth 1 --branch release https://github.com/facebook/zstd.git "$SRC"
    fi

    local BUILD="$SRC/build-android"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install/zstd" \
        -DBUILD_SHARED_LIBS=ON \
        -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        "$SRC/build/cmake"

    ninja -j"$(nproc)"
    ninja install

    # zstd baut libzstd.so.X.Y.Z mit Symlinks — wir brauchen nur libzstd.so
    local REAL_LIB; REAL_LIB=$(find "$BUILD_DIR/install/zstd/lib" -name "libzstd.so.*.*.*" -type f 2>/dev/null | head -1)
    if [ -n "$REAL_LIB" ]; then
        cp "$REAL_LIB" "$JNILIBS/libzstd.so"
    else
        cp "$BUILD_DIR/install/zstd/lib/libzstd.so" "$JNILIBS/libzstd.so"
    fi
    "$STRIP" "$JNILIBS/libzstd.so"
    verify_alignment "$JNILIBS/libzstd.so"
    echo "  → $JNILIBS/libzstd.so ($(du -h "$JNILIBS/libzstd.so" | cut -f1))"
}

build_libopus() {
    echo "=== libopus bauen ==="
    local SRC="$BUILD_DIR/opus"

    if [ -d "$SRC" ]; then
        local cached_tag
        cached_tag=$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$cached_tag" != "v$LIBOPUS_VERSION" ]; then
            echo "  Cached opus is $cached_tag, need v$LIBOPUS_VERSION — re-cloning"
            rm -rf "$SRC"
        fi
    fi
    if [ ! -d "$SRC" ]; then
        echo "  Klone opus (v$LIBOPUS_VERSION)..."
        git clone --depth 1 --branch "v$LIBOPUS_VERSION" https://github.com/xiph/opus.git "$SRC"
    fi

    cd "$SRC"
    make distclean 2>/dev/null || true
    ./autogen.sh

    ./configure \
        --host="$CONFIGURE_HOST" \
        --prefix="$BUILD_DIR/install/opus" \
        --disable-static \
        --enable-shared \
        --disable-doc --disable-extra-programs \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        CFLAGS="-O2 -fPIC" \
        LDFLAGS="$PAGE_SIZE_FLAG"

    make -j"$(nproc)" clean 2>/dev/null || true
    make -j"$(nproc)"
    make install

    cp "$BUILD_DIR/install/opus/lib/libopus.so" "$JNILIBS/libopus.so"
    "$STRIP" "$JNILIBS/libopus.so"
    verify_alignment "$JNILIBS/libopus.so"
    echo "  → $JNILIBS/libopus.so ($(du -h "$JNILIBS/libopus.so" | cut -f1))"
}

build_libcleona_pow() {
    echo "=== libcleona_pow bauen ==="
    local SRC="$PROJECT_DIR/native/cleona_pow"
    local BUILD="$BUILD_DIR/cleona_pow"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # libsodium must be pointed at explicitly. The NDK toolchain file sets
    # CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY, so find_library() searches the
    # NDK sysroot only and silently ignores CMAKE_PREFIX_PATH — the target
    # then failed with "libsodium not found" and no Android build of
    # libcleona_pow was ever produced (V3.1.156 shipped without it).
    # SODIUM_LIB/SODIUM_INCLUDE are cache variables in the CMakeLists, so
    # presetting them short-circuits the find_* calls entirely.
    local SODIUM_PREFIX="$BUILD_DIR/install/sodium"
    if [ ! -f "$SODIUM_PREFIX/lib/libsodium.so" ]; then
        echo "FEHLER: libsodium fuer $ARCH fehlt ($SODIUM_PREFIX)."
        echo "        Erst bauen: $0 --arch $ARCH sodium"
        exit 1
    fi

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        -DSODIUM_LIB="$SODIUM_PREFIX/lib/libsodium.so" \
        -DSODIUM_INCLUDE="$SODIUM_PREFIX/include" \
        "$SRC"

    ninja -j"$(nproc)"

    cp libcleona_pow.so "$JNILIBS/libcleona_pow.so"
    "$STRIP" "$JNILIBS/libcleona_pow.so"
    verify_alignment "$JNILIBS/libcleona_pow.so"
    echo "  → $JNILIBS/libcleona_pow.so ($(du -h "$JNILIBS/libcleona_pow.so" | cut -f1))"

    # Content stamp for preflight.sh Check 5 (Android native lib staleness).
    # mtimes are meaningless in git worktrees (checkout order, not content,
    # decides them) — the stamp lets that check compare source hash instead.
    sha256sum "$SRC/cleona_pow.c" | cut -d' ' -f1 > "$JNILIBS/libcleona_pow.so.srchash"
    echo "  → $JNILIBS/libcleona_pow.so.srchash ($(cat "$JNILIBS/libcleona_pow.so.srchash"))"
}

build_libcleona_net() {
    echo "=== libcleona_net bauen ==="
    local SRC="$PROJECT_DIR/native/cleona_net"
    local BUILD="$BUILD_DIR/cleona_net"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        "$SRC"

    ninja -j"$(nproc)"

    cp libcleona_net.so "$JNILIBS/libcleona_net.so"
    "$STRIP" "$JNILIBS/libcleona_net.so"
    verify_alignment "$JNILIBS/libcleona_net.so"
    echo "  → $JNILIBS/libcleona_net.so ($(du -h "$JNILIBS/libcleona_net.so" | cut -f1))"

    # Content stamp for preflight.sh Check 5 (Android native lib staleness).
    # mtimes are meaningless in git worktrees (checkout order, not content,
    # decides them) — the stamp lets that check compare source hash instead.
    # Note: unlike cleona_pow, cleona_net's source lives under
    # src/ (native/cleona_net/src/cleona_net.c), not directly in native/cleona_net/.
    sha256sum "$SRC/src/cleona_net.c" | cut -d' ' -f1 > "$JNILIBS/libcleona_net.so.srchash"
    echo "  → $JNILIBS/libcleona_net.so.srchash ($(cat "$JNILIBS/libcleona_net.so.srchash"))"
}

build_libcleona_voice() {
    echo "=== libcleona_voice bauen (Android-Backend, V1.2) ==="
    local SRC="$PROJECT_DIR/native/cleona_voice"
    local BUILD="$BUILD_DIR/cleona_voice"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # MOCK=OFF and SMOKE=OFF are not optional. CLEONA_VOICE_BUILD_MOCK
    # defaults ON (native/cleona_voice/CMakeLists.txt) and would also emit
    # libcleona_voice_mock.so into the same build tree — both libraries export
    # the identical twelve symbols, and voice_session.dart states the rule "a
    # process must never load both". Shipping the mock alongside the real
    # backend also puts wire value 100 (CLEONA_VOICE_BACKEND_MOCK) within
    # reach of a release build, exactly what preflight.sh Check 15 ("Mock
    # voice/video backend not in production build wiring") exists to prevent
    # (native/cleona_voice/BUILD_REQUEST.md §7). CLEONA_VOICE_ANDROID_CONFORMANCE
    # stays at its default OFF — the on-device conformance harness is test-only,
    # built via native/cleona_voice/android/conformance/run_conformance.sh, not
    # via this script.
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        -DCLEONA_VOICE_BUILD_MOCK=OFF \
        -DCLEONA_VOICE_BUILD_SMOKE=OFF \
        "$SRC"

    ninja -j"$(nproc)"

    # native/cleona_voice/CMakeLists.txt adds the platform backend as a
    # subdirectory, so the artefact lands under android/ in the build tree.
    cp android/libcleona_voice.so "$JNILIBS/libcleona_voice.so"
    "$STRIP" "$JNILIBS/libcleona_voice.so"
    verify_alignment "$JNILIBS/libcleona_voice.so"
    echo "  → $JNILIBS/libcleona_voice.so ($(du -h "$JNILIBS/libcleona_voice.so" | cut -f1))"

    # Content stamp for preflight.sh Check 5 (Android native lib staleness).
    # cleona_voice is a header-only-ABI package (sources live per-platform
    # under mock/, linux/, android/, apple/, windows/, not at a single
    # native/cleona_voice/cleona_voice.c) — the formula below MUST match
    # preflight.sh Check 5's cleona_voice branch exactly (path-relative-to-
    # PROJECT_DIR + content hash, NOT the absolute path — see that check's
    # comment for why an absolute path in the hash makes a .so built in one
    # worktree read as stale in every other one, measured cross-worktree),
    # or the two disagree about what "current" means. It hashes every
    # tracked *.c/*.h under native/cleona_voice/ except test/ and smoke/
    # (neither ships in the .so), plus VoiceSession.kt: the JNI facade
    # cleona_voice_android.c is a thin shell around it, so a rate-ladder or
    # effect change there changes no .c file at all and would otherwise
    # leave a stale stamp looking current.
    { find "$SRC" \( -name '*.c' -o -name '*.h' \) \
        -not -path '*/test/*' -not -path '*/smoke/*' -print0 | sort -z
      printf '%s\0' "$PROJECT_DIR/android/app/src/main/kotlin/chat/cleona/cleona/VoiceSession.kt"
    } | while IFS= read -r -d '' _bv_f; do
        printf '%s %s\n' "${_bv_f#"$PROJECT_DIR"/}" "$(sha256sum "$_bv_f" | cut -d' ' -f1)"
      done | sha256sum | cut -d' ' -f1 > "$JNILIBS/libcleona_voice.so.srchash"
    echo "  → $JNILIBS/libcleona_voice.so.srchash ($(cat "$JNILIBS/libcleona_voice.so.srchash"))"
}

build_libcleona_video() {
    echo "=== libcleona_video bauen (Android-Backend, V1.14) ==="
    local SRC="$PROJECT_DIR/native/cleona_video"
    local BUILD="$BUILD_DIR/cleona_video"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # MOCK=OFF and SMOKE=OFF are not optional, for the same reason as
    # cleona_voice above: CLEONA_VIDEO_BUILD_MOCK defaults ON
    # (native/cleona_video/CMakeLists.txt) and would also emit
    # libcleona_video_mock.so into the same build tree — the mock answers
    # every call with a synthetic bitstream, indistinguishable from success,
    # which is exactly what preflight.sh Check 15 ("Mock voice/video backend
    # not in production build wiring") exists to keep out of a release build.
    # CLEONA_VIDEO_ANDROID_CONFORMANCE stays at its default OFF — the
    # on-device conformance harness is test-only, built via
    # native/cleona_video/android/conformance/run_conformance.sh, not via
    # this script. ANDROID_ABI/the NDK toolchain file already set ANDROID=1
    # for CMake, the same way build_libcleona_voice above relies on it —
    # no separate -DANDROID=ON is needed or read by any CMakeLists here.
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        -DCLEONA_VIDEO_BUILD_MOCK=OFF \
        -DCLEONA_VIDEO_BUILD_SMOKE=OFF \
        "$SRC"

    ninja -j"$(nproc)"

    # native/cleona_video/CMakeLists.txt adds the platform backend as a
    # subdirectory, so the artefact lands under android/ in the build tree.
    cp android/libcleona_video.so "$JNILIBS/libcleona_video.so"
    "$STRIP" "$JNILIBS/libcleona_video.so"
    verify_alignment "$JNILIBS/libcleona_video.so"
    echo "  → $JNILIBS/libcleona_video.so ($(du -h "$JNILIBS/libcleona_video.so" | cut -f1))"

    # Content stamp for preflight.sh Check 5 (Android native lib staleness).
    # Must match Check 5's cleona_video branch exactly: every tracked
    # *.c/*.h under native/cleona_video/ except test/ and smoke/, fed as
    # "<path-relative-to-PROJECT_DIR> <content-sha256>" pairs — NOT the
    # absolute path (native/cleona_voice/BUILD_REQUEST_V1.2.md §4: an
    # absolute path in the hash makes a .so built in one worktree read as
    # stale in every other one). Unlike cleona_voice's branch, Check 5 does
    # not fold VideoSession.kt into this hash, so this stamp does not either.
    { find "$SRC" \( -name '*.c' -o -name '*.h' \) \
        -not -path '*/test/*' -not -path '*/smoke/*' -print0 | sort -z
    } | while IFS= read -r -d '' _bv_f; do
        printf '%s %s\n' "${_bv_f#"$PROJECT_DIR"/}" "$(sha256sum "$_bv_f" | cut -d' ' -f1)"
      done | sha256sum | cut -d' ' -f1 > "$JNILIBS/libcleona_video.so.srchash"
    echo "  → $JNILIBS/libcleona_video.so.srchash ($(cat "$JNILIBS/libcleona_video.so.srchash"))"
}

# --- Main ---
# Every remaining argument is a target. This used to be `TARGET="${1:-all}"`,
# which read the FIRST argument and silently discarded the rest: an invocation
# like `--arch x86_64 sodium pow` built libsodium, never touched libcleona_pow,
# and still exited 0, because the closing alignment check passes regardless of
# what was built. A caller had no way to notice the dropped target — the script
# reported success for work it had not done. Both targets are needed together in
# practice: libcleona_pow links against libsodium from the temp prefix, so
# `sodium pow` is the only self-contained way to refresh pow.
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("all")

build_target() {
    case "$TARGET" in
        sodium)        build_libsodium ;;
        oqs)           build_liboqs ;;
        zstd)          build_libzstd ;;
        opus)          build_libopus ;;
        whisper)       build_libwhisper ;;
        pow)           build_libcleona_pow ;;
        net)           build_libcleona_net ;;
        voice)         build_libcleona_voice ;;
        video)         build_libcleona_video ;;
        all)
            build_libsodium
            echo ""
            build_liboqs
            echo ""
            build_libzstd
            echo ""
            build_libopus
            echo ""
            echo ""
            echo ""
            build_libcleona_pow
            echo ""
            build_libcleona_net
            echo ""
            build_libcleona_voice
            echo ""
            build_libcleona_video
            echo ""
            build_libwhisper
            ;;
        *)
            echo "Nutzung: $0 [--arch arm64-v8a|x86_64|all] [sodium|oqs|zstd|opus|whisper|pow|net|voice|video|all]"
            exit 1
            ;;
    esac
}

build_all_targets() {
    for TARGET in "${TARGETS[@]}"; do
        build_target
        echo ""
    done
}

if [ "$ARCH" = "all" ]; then
    for a in arm64-v8a x86_64; do
        echo "╔══════════════════════════════════════╗"
        echo "║  Architektur: $a"
        echo "╚══════════════════════════════════════╝"
        setup_arch "$a"
        build_all_targets
    done
else
    build_all_targets
fi

echo ""
echo "=== Ergebnis ==="
echo "Alignment-Check aller Libraries:"
FAIL=0
for abi_dir in "$PROJECT_DIR/android/app/src/main/jniLibs"/*/; do
    [ -d "$abi_dir" ] || continue
    echo "  $(basename "$abi_dir"):"
    for lib in "$abi_dir"*.so; do
        [ -f "$lib" ] || continue
        verify_alignment "$lib" || FAIL=1
    done
done
if [ $FAIL -eq 0 ]; then
    echo ""
    echo "Alle Libraries 16KB-aligned. APK kann gebaut werden."
else
    echo ""
    echo "WARNUNG: Nicht alle Libraries korrekt aligned!"
    exit 1
fi
