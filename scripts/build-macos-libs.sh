#!/bin/bash
###############################################################################
# build-macos-libs.sh — Build native libraries for macOS
#
# Builds libsodium, liboqs, libzstd, liberasurecode, libopus and whisper.cpp
# as dylibs for macOS (arm64, x86_64 or universal via lipo).
#
# Run this on a macOS host (it cannot cross-compile from Linux — Apple's SDK
# and codesign are required). The resulting dylibs are dropped into
#   build/macos-libs/<arch>/
# and can then be copied into Cleona.app/Contents/Frameworks/ by the
# deploy step.
#
# Prerequisites (Homebrew):
#   brew install cmake autoconf automake libtool pkg-config git
#
# Usage:
#   ./scripts/build-macos-libs.sh                      # arm64 (Apple Silicon)
#   ./scripts/build-macos-libs.sh --arch x86_64        # Intel
#   ./scripts/build-macos-libs.sh --arch universal     # both + lipo merge
#   ./scripts/build-macos-libs.sh sodium               # only libsodium, arm64
#   ./scripts/build-macos-libs.sh --arch arm64 whisper # only whisper, arm64
#   ./scripts/build-macos-libs.sh --use-homebrew       # symlink Homebrew-built
#                                                      #   libs instead of from
#                                                      #   source (dev shortcut)
###############################################################################
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script must run on macOS."
    echo "       For cross-compile alternatives see docs/CROSS_MACOS.md (TBD)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Flag parsing ─────────────────────────────────────────────────────────────
ARCH="arm64"
USE_HOMEBREW=0
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --use-homebrew) USE_HOMEBREW=1; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

TARGETS=("${@:-all}")

MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-11.0}"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"

# Versions pinned — match Android script where possible so both platforms
# agree on ABI-relevant flags.
LIBSODIUM_VERSION="1.0.20"
LIBOQS_VERSION="0.10.1"
LIBZSTD_VERSION="1.5.6"
LIBERASURECODE_VERSION="1.6.2"
LIBOPUS_VERSION="1.5.2"
WHISPER_VERSION="v1.7.1"

# ── Architecture setup ───────────────────────────────────────────────────────
setup_arch() {
    local arch="$1"
    case "$arch" in
        arm64)
            export CMAKE_OSX_ARCHITECTURES="arm64"
            CONFIGURE_HOST="aarch64-apple-darwin"
            ;;
        x86_64)
            export CMAKE_OSX_ARCHITECTURES="x86_64"
            CONFIGURE_HOST="x86_64-apple-darwin"
            ;;
        *) echo "Unknown arch: $arch (arm64 or x86_64)"; exit 1 ;;
    esac
    CFLAGS_BASE="-arch $arch -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET -O2"
    export CFLAGS="$CFLAGS_BASE"
    export CXXFLAGS="$CFLAGS_BASE"
    export LDFLAGS="-arch $arch -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET"
    OUT_DIR="$PROJECT_DIR/build/macos-libs/$arch"
    BUILD_DIR="/tmp/macos-libs-build-$arch"
    mkdir -p "$OUT_DIR" "$BUILD_DIR"
    export CONFIGURE_HOST OUT_DIR BUILD_DIR
    echo ">>> Target: $arch → $OUT_DIR"
}

# ── Install-name rewrite so dylibs load from @rpath/Frameworks ───────────────
# macOS apps look up dylibs via the LC_LOAD_DYLIB install name recorded in
# the binary. We rewrite that to @rpath/<name>.dylib so the Cleona.app
# bundle can find them in Contents/Frameworks regardless of where the
# build was staged.
rewrite_install_name() {
    local dylib="$1"
    local name="$(basename "$dylib")"
    install_name_tool -id "@rpath/$name" "$dylib"
    # Fix transitive deps (e.g. libwhisper -> libggml)
    otool -L "$dylib" | awk 'NR>1 {print $1}' | while read -r dep; do
        case "$dep" in
            /opt/homebrew/*|/usr/local/*)
                local depname="$(basename "$dep")"
                install_name_tool -change "$dep" "@rpath/$depname" "$dylib" || true
                ;;
        esac
    done
    codesign --force --sign - "$dylib"
}

# ── Individual build steps ───────────────────────────────────────────────────
build_libsodium() {
    echo "── libsodium ────────────────────────────────────────────────"
    local src="$BUILD_DIR/libsodium"
    if [ ! -d "$src" ]; then
        curl -fsSL "https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VERSION.tar.gz" \
            | tar xz -C "$BUILD_DIR"
        mv "$BUILD_DIR/libsodium-$LIBSODIUM_VERSION" "$src"
    fi
    cd "$src"
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$BUILD_DIR/install-sodium" \
        --disable-static --enable-shared \
        --disable-dependency-tracking
    make -j"$(sysctl -n hw.ncpu)"
    make install
    cp "$BUILD_DIR/install-sodium/lib/libsodium."*.dylib "$OUT_DIR/libsodium.dylib"
    rewrite_install_name "$OUT_DIR/libsodium.dylib"
    cd "$PROJECT_DIR"
}

build_liboqs() {
    echo "── liboqs ───────────────────────────────────────────────────"
    local src="$BUILD_DIR/liboqs"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$LIBOQS_VERSION" \
            https://github.com/open-quantum-safe/liboqs.git "$src"
    fi
    cd "$src"
    rm -rf build && mkdir build && cd build
    cmake -GNinja \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-oqs" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$CMAKE_OSX_ARCHITECTURES" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DBUILD_SHARED_LIBS=ON \
        -DOQS_USE_OPENSSL=OFF \
        -DOQS_MINIMAL_BUILD="KEM_ml_kem_768;SIG_ml_dsa_65" \
        -DOQS_DIST_BUILD=ON \
        ..
    ninja install
    cp "$BUILD_DIR/install-oqs/lib/liboqs."*.dylib "$OUT_DIR/liboqs.dylib"
    rewrite_install_name "$OUT_DIR/liboqs.dylib"
    cd "$PROJECT_DIR"
}

build_libzstd() {
    echo "── libzstd ──────────────────────────────────────────────────"
    local src="$BUILD_DIR/zstd"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "v$LIBZSTD_VERSION" \
            https://github.com/facebook/zstd.git "$src"
    fi
    cd "$src/build/cmake"
    rm -rf build && mkdir build && cd build
    cmake -GNinja \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-zstd" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$CMAKE_OSX_ARCHITECTURES" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DZSTD_BUILD_STATIC=OFF \
        -DZSTD_BUILD_SHARED=ON \
        -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF \
        ..
    ninja install
    cp "$BUILD_DIR/install-zstd/lib/libzstd."*.dylib "$OUT_DIR/libzstd.dylib"
    rewrite_install_name "$OUT_DIR/libzstd.dylib"
    cd "$PROJECT_DIR"
}

build_liberasurecode() {
    echo "── liberasurecode ───────────────────────────────────────────"
    local src="$BUILD_DIR/liberasurecode"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$LIBERASURECODE_VERSION" \
            https://opendev.org/openstack/liberasurecode.git "$src"
    fi
    cd "$src"
    ./autogen.sh
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$BUILD_DIR/install-ec" \
        --disable-static --enable-shared
    make -j"$(sysctl -n hw.ncpu)"
    make install
    cp "$BUILD_DIR/install-ec/lib/liberasurecode."*.dylib "$OUT_DIR/liberasurecode.dylib"
    rewrite_install_name "$OUT_DIR/liberasurecode.dylib"
    cd "$PROJECT_DIR"
}

build_libopus() {
    echo "── libopus ──────────────────────────────────────────────────"
    local src="$BUILD_DIR/opus"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "v$LIBOPUS_VERSION" \
            https://github.com/xiph/opus.git "$src"
    fi
    cd "$src"
    ./autogen.sh
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$BUILD_DIR/install-opus" \
        --disable-static --enable-shared \
        --disable-doc --disable-extra-programs
    make -j"$(sysctl -n hw.ncpu)"
    make install
    cp "$BUILD_DIR/install-opus/lib/libopus."*.dylib "$OUT_DIR/libopus.dylib"
    rewrite_install_name "$OUT_DIR/libopus.dylib"
    cd "$PROJECT_DIR"
}

build_whisper() {
    echo "── whisper.cpp (+ libggml) ──────────────────────────────────"
    local src="$BUILD_DIR/whisper.cpp"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$WHISPER_VERSION" \
            https://github.com/ggerganov/whisper.cpp.git "$src"
    fi
    cd "$src"
    rm -rf build && mkdir build && cd build
    # Metal acceleration is macOS-native and fast; enable it on arm64.
    local metal_flag="-DGGML_METAL=ON"
    if [ "$CMAKE_OSX_ARCHITECTURES" = "x86_64" ]; then
        metal_flag="-DGGML_METAL=OFF"
    fi
    cmake -GNinja \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-whisper" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$CMAKE_OSX_ARCHITECTURES" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DBUILD_SHARED_LIBS=ON \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF \
        -DGGML_NATIVE=OFF \
        $metal_flag \
        ..
    ninja install
    for lib in libwhisper libggml libggml-base libggml-cpu; do
        if ls "$BUILD_DIR/install-whisper/lib/$lib."*.dylib 2>/dev/null; then
            cp "$BUILD_DIR/install-whisper/lib/$lib."*.dylib "$OUT_DIR/$lib.dylib"
            rewrite_install_name "$OUT_DIR/$lib.dylib"
        fi
    done
    cd "$PROJECT_DIR"
}

build_vpx_shim() {
    echo "── libcleona_vpx (shim + libvpx from Homebrew) ──────────────"
    # Assumes libvpx is available via Homebrew (`brew install libvpx`). The
    # shim compiles against libvpx headers and links dynamically.
    local vpx_prefix
    vpx_prefix="$(brew --prefix libvpx 2>/dev/null || true)"
    if [ -z "$vpx_prefix" ] || [ ! -d "$vpx_prefix" ]; then
        echo "!! libvpx not installed via Homebrew — skipping VPX shim."
        echo "   Install: brew install libvpx"
        return 0
    fi
    local src="$PROJECT_DIR/native/vpx_shim.c"
    if [ ! -f "$src" ]; then
        echo "!! $src missing — skipping VPX shim."
        return 0
    fi
    local out="$OUT_DIR/libcleona_vpx.dylib"
    clang -shared -fPIC $CFLAGS \
        -I"$vpx_prefix/include" -L"$vpx_prefix/lib" \
        -o "$out" "$src" -lvpx
    rewrite_install_name "$out"
}

# ── Homebrew shortcut ────────────────────────────────────────────────────────
use_homebrew_libs() {
    echo ">>> Using Homebrew-installed libs (symlinks into $OUT_DIR)"
    local BREW
    BREW="$(brew --prefix)"
    local mapping=(
        "libsodium:libsodium.dylib"
        "libzstd:libzstd.dylib"
        "libopus:libopus.dylib"
    )
    for m in "${mapping[@]}"; do
        local pkg="${m%%:*}"; local lib="${m##*:}"
        local prefix; prefix="$(brew --prefix "$pkg" 2>/dev/null || true)"
        if [ -n "$prefix" ] && [ -f "$prefix/lib/$lib" ]; then
            cp "$prefix/lib/$lib" "$OUT_DIR/$lib"
            rewrite_install_name "$OUT_DIR/$lib"
            echo "  ✓ $lib"
        else
            echo "  ✗ $pkg missing — brew install $pkg"
        fi
    done
    echo ">>> Homebrew path does not cover liboqs/liberasurecode/whisper —"
    echo "    run without --use-homebrew for a full build."
}

# ── Universal binary merge ───────────────────────────────────────────────────
merge_universal() {
    echo ">>> Merging arm64 + x86_64 → universal"
    local uni="$PROJECT_DIR/build/macos-libs/universal"
    mkdir -p "$uni"
    local a64="$PROJECT_DIR/build/macos-libs/arm64"
    local x64="$PROJECT_DIR/build/macos-libs/x86_64"
    for f in "$a64"/*.dylib; do
        local name="$(basename "$f")"
        if [ -f "$x64/$name" ]; then
            lipo -create "$a64/$name" "$x64/$name" -output "$uni/$name"
            codesign --force --sign - "$uni/$name"
            echo "  ✓ $name (universal)"
        else
            cp "$f" "$uni/$name"
            echo "  ~ $name (arm64 only)"
        fi
    done
}

# ── Verify ───────────────────────────────────────────────────────────────────
verify() {
    echo ">>> Verifying $OUT_DIR"
    for f in "$OUT_DIR"/*.dylib; do
        [ -f "$f" ] || continue
        local arch; arch="$(lipo -archs "$f" 2>/dev/null || echo '?')"
        local name="$(basename "$f")"
        echo "  ✓ $name ($arch)"
    done
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
run_builds() {
    local wanted=("${TARGETS[@]}")
    local all_targets=(sodium oqs zstd erasurecode opus whisper vpx)
    if [ "${wanted[0]}" = "all" ]; then
        wanted=("${all_targets[@]}")
    fi
    if [ "$USE_HOMEBREW" -eq 1 ]; then
        use_homebrew_libs
        return
    fi
    for t in "${wanted[@]}"; do
        case "$t" in
            sodium) build_libsodium ;;
            oqs) build_liboqs ;;
            zstd) build_libzstd ;;
            erasurecode) build_liberasurecode ;;
            opus) build_libopus ;;
            whisper) build_whisper ;;
            vpx) build_vpx_shim ;;
            *) echo "Unknown target: $t"; exit 1 ;;
        esac
    done
    verify
}

if [ "$ARCH" = "universal" ]; then
    setup_arch arm64; run_builds
    setup_arch x86_64; run_builds
    merge_universal
else
    setup_arch "$ARCH"
    run_builds
fi

echo ""
echo "✓ Done. Dylibs: $PROJECT_DIR/build/macos-libs/$ARCH/"
echo ""
echo "Next step: deploy into Cleona.app"
echo "  ./scripts/deploy-macos-app.sh --arch $ARCH"
