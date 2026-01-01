#!/bin/bash
###############################################################################
# build-android-libs.sh — Cross-compile native libs for Android
#
# Baut libsodium, liboqs, libzstd, whisper.cpp (inkl. libggml) und den
# libcleona_vpx-Shim (libvpx statisch eingebunden, nur VP8) mit 16KB
# Page-Alignment (Android 15+).
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
#   ./scripts/build-android-libs.sh vpx                    # Nur libcleona_vpx arm64
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

# Pin whisper.cpp version — MUST match iOS/macOS scripts to keep struct layout
# in sync with Dart FFI (whisper_ffi.dart hardcoded offsets).
WHISPER_VERSION="v1.7.1"

# Pin libvpx version — offsets in native/vpx_shim.c (opaque-buffer field
# offsets + ABI version constants) are only valid for this exact minor
# version; bump both together after re-validating offsets/ABI numbers
# against the new vpx/vpx_encoder.h + vpx/vpx_decoder.h.
LIBVPX_VERSION="v1.14.1"

setup_arch() {
    local arch="$1"
    case "$arch" in
        arm64-v8a)
            CC="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
            CXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"
            CONFIGURE_HOST="aarch64-linux-android"
            CMAKE_ABI="arm64-v8a"
            VPX_TARGET="arm64-android-gcc"
            ;;
        x86_64)
            CC="$TOOLCHAIN/bin/x86_64-linux-android${API_LEVEL}-clang"
            CXX="$TOOLCHAIN/bin/x86_64-linux-android${API_LEVEL}-clang++"
            CONFIGURE_HOST="x86_64-linux-android"
            CMAKE_ABI="x86_64"
            VPX_TARGET="x86_64-android-gcc"
            ;;
        *) echo "Unbekannte Architektur: $arch (arm64-v8a oder x86_64)"; exit 1 ;;
    esac
    JNILIBS="$PROJECT_DIR/android/app/src/main/jniLibs/$arch"
    BUILD_DIR="/tmp/android-libs-build-$arch"
    mkdir -p "$BUILD_DIR" "$JNILIBS"
    export CC CXX CONFIGURE_HOST CMAKE_ABI VPX_TARGET JNILIBS BUILD_DIR
}

# Default setup (may be overridden by 'all' loop)
if [ "$ARCH" != "all" ]; then
    setup_arch "$ARCH"
fi

verify_alignment() {
    local lib="$1"
    local name="$(basename "$lib")"
    # Alignment is the last hex field on the continuation line after LOAD
    # Format: "   LOAD  0x... 0x... 0x...\n               0x... 0x...  R E  0x4000"
    local align=$(readelf -l "$lib" 2>/dev/null | grep -A1 '^\s*LOAD' | grep -v 'LOAD' | grep -oP '0x[0-9a-f]+' | tail -1 | head -1)
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
        local REAL_LIB=$(find "$BUILD" -name "${libname}.so*" -type f ! -type l 2>/dev/null | head -1)
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

build_libcleona_audio() {
    echo "=== libcleona_audio bauen ==="
    local SRC="$PROJECT_DIR/native/cleona_audio"
    local BUILD="$BUILD_DIR/cleona_audio"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # speexdsp is vendored under native/cleona_audio/vendor/speexdsp and built
    # as a static library by cleona_audio's CMakeLists.txt — no separate
    # libspeexdsp.so step needed. The static lib gets linked into
    # libcleona_audio.so so the APK ships exactly one .so for the audio stack.
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        "$SRC"

    ninja -j"$(nproc)"

    cp libcleona_audio.so "$JNILIBS/libcleona_audio.so"
    "$STRIP" "$JNILIBS/libcleona_audio.so"
    verify_alignment "$JNILIBS/libcleona_audio.so"
    echo "  → $JNILIBS/libcleona_audio.so ($(du -h "$JNILIBS/libcleona_audio.so" | cut -f1))"
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
    local REAL_LIB=$(find "$BUILD_DIR/install/zstd/lib" -name "libzstd.so.*.*.*" -type f 2>/dev/null | head -1)
    if [ -n "$REAL_LIB" ]; then
        cp "$REAL_LIB" "$JNILIBS/libzstd.so"
    else
        cp "$BUILD_DIR/install/zstd/lib/libzstd.so" "$JNILIBS/libzstd.so"
    fi
    "$STRIP" "$JNILIBS/libzstd.so"
    verify_alignment "$JNILIBS/libzstd.so"
    echo "  → $JNILIBS/libzstd.so ($(du -h "$JNILIBS/libzstd.so" | cut -f1))"
}

build_libvpx() {
    echo "=== libvpx bauen (nur VP8, statisch) ==="
    local SRC="$BUILD_DIR/libvpx"

    if [ -d "$SRC" ]; then
        local cached_tag
        cached_tag=$(git -C "$SRC" describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$cached_tag" != "$LIBVPX_VERSION" ]; then
            echo "  Cached libvpx is $cached_tag, need $LIBVPX_VERSION — re-cloning"
            rm -rf "$SRC"
        fi
    fi
    if [ ! -d "$SRC" ]; then
        echo "  Klone libvpx ($LIBVPX_VERSION)..."
        git clone --depth 1 --branch "$LIBVPX_VERSION" https://github.com/webmproject/libvpx.git "$SRC"
    fi

    local BUILD="$SRC/build-android-$CMAKE_ABI"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    # native/vpx_shim.c only calls vpx_codec_vp8_{cx,dx} — VP9 stays
    # disabled to shrink the static lib and drop unused attack surface.
    # examples/tools/docs/unit-tests off: this is a library-only build.
    # --enable-static --disable-shared: libvpx.a gets linked statically
    # into libcleona_vpx.so below, so no separate libvpx.so ships in the
    # APK (see build_libcleona_vpx).
    local X86_ASM_FLAGS=()
    if [ "$CMAKE_ABI" = "x86_64" ]; then
        # libvpx's x86 SIMD paths are hand-written .asm (yasm/nasm syntax,
        # not clang's integrated assembler) and yasm/nasm aren't part of
        # the NDK toolchain or a build prerequisite of this script. Rather
        # than adding a yasm/nasm dependency for the emulator-only x86_64
        # target, disable x86 SIMD and fall back to the portable C code
        # paths (ARM64 devices, the release target, are unaffected — NEON
        # is handled by clang's integrated assembler, no yasm needed).
        X86_ASM_FLAGS=(--disable-mmx --disable-sse --disable-sse2 \
            --disable-sse3 --disable-ssse3 --disable-sse4_1 \
            --disable-avx --disable-avx2 --disable-avx512)
    fi

    CC="$CC" CXX="$CXX" AR="$AR" AS="$CC" LD="$CC" RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    "$SRC/configure" --target="$VPX_TARGET" \
        --disable-examples --disable-tools --disable-docs --disable-unit-tests \
        --enable-vp8 --disable-vp9 --enable-pic \
        --enable-static --disable-shared \
        --disable-webm-io --disable-libyuv \
        --extra-cflags="-fPIC" \
        "${X86_ASM_FLAGS[@]}"

    make -j"$(nproc)"

    echo "  → $BUILD/libvpx.a ($(du -h libvpx.a | cut -f1)) [$CMAKE_ABI]"
}

build_libcleona_vpx() {
    echo "=== libcleona_vpx bauen (VP8-Shim, libvpx statisch eingebunden) ==="
    build_libvpx

    local VPX_SRC="$BUILD_DIR/libvpx"
    local VPX_BUILD="$VPX_SRC/build-android-$CMAKE_ABI"
    local SHIM_SRC="$PROJECT_DIR/native/vpx_shim.c"

    # -DCLEONA_VPX_STATIC_LINK: vpx_shim.c resolves the real libvpx
    # functions directly at link time instead of via dlopen/dlsym (that
    # path is Linux-only, where the shim dlopen()s the system libvpx.so).
    # libvpx.a is linked in directly so the shim + codec end up in one
    # single .so — no separate libvpx.so lands in jniLibs/.
    "$CC" -shared -fPIC -O2 \
        -DCLEONA_VPX_STATIC_LINK \
        -o "$JNILIBS/libcleona_vpx.so" \
        "$SHIM_SRC" \
        "$VPX_BUILD/libvpx.a" \
        "$PAGE_SIZE_FLAG"

    "$STRIP" "$JNILIBS/libcleona_vpx.so"
    verify_alignment "$JNILIBS/libcleona_vpx.so"
    echo "  → $JNILIBS/libcleona_vpx.so ($(du -h "$JNILIBS/libcleona_vpx.so" | cut -f1))"
}

build_libcleona_pow() {
    echo "=== libcleona_pow bauen ==="
    local SRC="$PROJECT_DIR/native/cleona_pow"
    local BUILD="$BUILD_DIR/cleona_pow"
    rm -rf "$BUILD"
    mkdir -p "$BUILD"
    cd "$BUILD"

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$CMAKE_ABI" \
        -DANDROID_NATIVE_API_LEVEL=$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_SIZE_FLAG" \
        -DCMAKE_PREFIX_PATH="$BUILD_DIR/install/sodium" \
        "$SRC"

    ninja -j"$(nproc)"

    cp libcleona_pow.so "$JNILIBS/libcleona_pow.so"
    "$STRIP" "$JNILIBS/libcleona_pow.so"
    verify_alignment "$JNILIBS/libcleona_pow.so"
    echo "  → $JNILIBS/libcleona_pow.so ($(du -h "$JNILIBS/libcleona_pow.so" | cut -f1))"
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
}

# --- Main ---
TARGET="${1:-all}"

build_target() {
    case "$TARGET" in
        sodium)        build_libsodium ;;
        oqs)           build_liboqs ;;
        zstd)          build_libzstd ;;
        whisper)       build_libwhisper ;;
        cleona_audio)  build_libcleona_audio ;;
        vpx)           build_libcleona_vpx ;;
        pow)           build_libcleona_pow ;;
        net)           build_libcleona_net ;;
        all)
            build_libsodium
            echo ""
            build_liboqs
            echo ""
            build_libzstd
            echo ""
            build_libcleona_audio
            echo ""
            build_libcleona_vpx
            echo ""
            build_libcleona_pow
            echo ""
            build_libcleona_net
            echo ""
            build_libwhisper
            ;;
        *)
            echo "Nutzung: $0 [--arch arm64-v8a|x86_64|all] [sodium|oqs|zstd|whisper|cleona_audio|vpx|pow|net|all]"
            exit 1
            ;;
    esac
}

if [ "$ARCH" = "all" ]; then
    for a in arm64-v8a x86_64; do
        echo "╔══════════════════════════════════════╗"
        echo "║  Architektur: $a"
        echo "╚══════════════════════════════════════╝"
        setup_arch "$a"
        build_target
        echo ""
    done
else
    build_target
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
