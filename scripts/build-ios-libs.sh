#!/bin/bash
###############################################################################
# build-ios-libs.sh — Build native libraries for iOS
#
# Builds libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp
# and libcleona_audio as STATIC libraries (.a) for iOS.
#
# iOS does not allow loading custom dynamic libraries — all native code must
# be statically linked into the app binary. Flutter's dart:ffi then accesses
# the symbols via DynamicLibrary.process().
#
# Output: XCFrameworks in build/ios-frameworks/<lib>.xcframework
# Each XCFramework bundles arm64-iphoneos + arm64-iphonesimulator slices.
#
# Must run on macOS with Xcode installed (xcrun, clang, iOS SDKs).
#
# Prerequisites (Homebrew):
#   brew install cmake autoconf automake libtool ninja pkg-config git
#
# Usage:
#   ./scripts/build-ios-libs.sh                      # all libs, device + sim
#   ./scripts/build-ios-libs.sh --device-only         # arm64-iphoneos only
#   ./scripts/build-ios-libs.sh --sim-only            # arm64-iphonesimulator
#   ./scripts/build-ios-libs.sh sodium                # only libsodium
#   ./scripts/build-ios-libs.sh sodium oqs            # only libsodium + liboqs
###############################################################################
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script must run on macOS (needs Xcode iOS SDK)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Flag parsing ─────────────────────────────────────────────────────────────
BUILD_DEVICE=1
BUILD_SIM=1
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --device-only) BUILD_SIM=0; shift ;;
        --sim-only) BUILD_DEVICE=0; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

TARGETS=("${@:-all}")

IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-13.0}"

LIBSODIUM_VERSION="1.0.20"
LIBOQS_VERSION="0.10.1"
LIBZSTD_VERSION="1.5.6"
LIBERASURECODE_VERSION="1.6.2"
LIBOPUS_VERSION="1.5.2"
WHISPER_VERSION="v1.7.1"

NPROC="$(sysctl -n hw.ncpu)"

# macOS Homebrew names libtool as glibtool to avoid conflict with Apple's
# libtool. Autotools scripts (autogen.sh) look for libtoolize which is
# glibtoolize on macOS. Ensure the symlink path from brew is on PATH.
if command -v glibtoolize &>/dev/null && ! command -v libtoolize &>/dev/null; then
    export LIBTOOLIZE="glibtoolize"
fi
XCFW_DIR="$PROJECT_DIR/build/ios-frameworks"
mkdir -p "$XCFW_DIR"

# ── SDK paths ────────────────────────────────────────────────────────────────
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

# ── Architecture setup ───────────────────────────────────────────────────────
setup_env() {
    local platform="$1"  # iphoneos | iphonesimulator
    case "$platform" in
        iphoneos)
            SDK_PATH="$IOS_SDK"
            ARCH="arm64"
            TARGET_TRIPLE="arm64-apple-ios${IOS_DEPLOYMENT_TARGET}"
            CONFIGURE_HOST="aarch64-apple-darwin"
            PLATFORM_TAG="device"
            CMAKE_SYSTEM_NAME="iOS"
            ;;
        iphonesimulator)
            SDK_PATH="$SIM_SDK"
            ARCH="arm64"
            TARGET_TRIPLE="arm64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            CONFIGURE_HOST="aarch64-apple-darwin"
            PLATFORM_TAG="simulator"
            CMAKE_SYSTEM_NAME="iOS"
            ;;
        *) echo "Unknown platform: $platform"; exit 1 ;;
    esac

    CC="$(xcrun --sdk "$platform" -f clang)"
    CXX="$(xcrun --sdk "$platform" -f clang++)"
    AR="$(xcrun --sdk "$platform" -f ar)"
    RANLIB="$(xcrun --sdk "$platform" -f ranlib)"

    CFLAGS_BASE="-arch $ARCH -isysroot $SDK_PATH -target $TARGET_TRIPLE -O2 -fPIC"
    export CC CXX AR RANLIB
    export CFLAGS="$CFLAGS_BASE"
    export CXXFLAGS="$CFLAGS_BASE"
    export LDFLAGS="-arch $ARCH -isysroot $SDK_PATH -target $TARGET_TRIPLE"

    BUILD_DIR="/tmp/ios-libs-build-$PLATFORM_TAG"
    INSTALL_DIR="$BUILD_DIR/install"
    mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

    echo ">>> Target: $platform ($ARCH) → $BUILD_DIR"
}

# ── XCFramework creator ─────────────────────────────────────────────────────
create_xcframework() {
    local name="$1"      # e.g. libsodium
    local device_lib="$2"  # path to device .a (or empty)
    local sim_lib="$3"     # path to simulator .a (or empty)
    local header_dir="${4:-}"  # optional headers

    local outdir="$XCFW_DIR/${name}.xcframework"
    rm -rf "$outdir"

    local args=()
    if [ -n "$device_lib" ] && [ -f "$device_lib" ]; then
        args+=(-library "$device_lib")
        if [ -n "$header_dir" ] && [ -d "$header_dir" ]; then
            args+=(-headers "$header_dir")
        fi
    fi
    if [ -n "$sim_lib" ] && [ -f "$sim_lib" ]; then
        args+=(-library "$sim_lib")
        if [ -n "$header_dir" ] && [ -d "$header_dir" ]; then
            args+=(-headers "$header_dir")
        fi
    fi

    if [ ${#args[@]} -eq 0 ]; then
        echo "  [!] No libraries found for $name — skipping XCFramework"
        return 1
    fi

    xcodebuild -create-xcframework "${args[@]}" -output "$outdir"
    echo "  ✓ $outdir"
}

# ── Individual build steps ───────────────────────────────────────────────────

build_libsodium() {
    local platform="$1"
    echo "── libsodium ($platform) ──────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/libsodium"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$LIBSODIUM_VERSION-RELEASE" \
            https://github.com/jedisct1/libsodium.git "$src"
    fi
    cd "$src"
    make distclean 2>/dev/null || true
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$INSTALL_DIR/sodium" \
        --enable-static --disable-shared \
        --disable-dependency-tracking
    make -j"$NPROC"
    make install
    cd "$PROJECT_DIR"
}

build_liboqs() {
    local platform="$1"
    echo "── liboqs ($platform) ─────────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/liboqs"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$LIBOQS_VERSION" \
            https://github.com/open-quantum-safe/liboqs.git "$src"
    fi
    cd "$src"
    rm -rf build-ios && mkdir build-ios && cd build-ios

    # iOS cross-compile via CMake toolchain variables (no external toolchain file)
    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/oqs" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DOQS_USE_OPENSSL=OFF \
        -DOQS_MINIMAL_BUILD="KEM_ml_kem_768;SIG_ml_dsa_65" \
        -DOQS_DIST_BUILD=ON \
        -DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON \
        ..
    ninja -j"$NPROC" install
    cd "$PROJECT_DIR"
}

build_libzstd() {
    local platform="$1"
    echo "── libzstd ($platform) ────────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/zstd"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "v$LIBZSTD_VERSION" \
            https://github.com/facebook/zstd.git "$src"
    fi
    cd "$src/build/cmake"
    rm -rf build-ios && mkdir build-ios && cd build-ios
    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/zstd" \
        -DCMAKE_BUILD_TYPE=Release \
        -DZSTD_BUILD_STATIC=ON \
        -DZSTD_BUILD_SHARED=OFF \
        -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF \
        ..
    ninja -j"$NPROC" install
    cd "$PROJECT_DIR"
}

build_liberasurecode() {
    local platform="$1"
    echo "── liberasurecode ($platform) ─────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/liberasurecode"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$LIBERASURECODE_VERSION" \
            https://opendev.org/openstack/liberasurecode.git "$src"
    fi
    cd "$src"
    make distclean 2>/dev/null || true
    [ -f configure ] || ./autogen.sh
    CFLAGS="$CFLAGS -Wno-strict-prototypes -Wno-error" \
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$INSTALL_DIR/ec" \
        --enable-static --disable-shared
    make -j"$NPROC"
    make install
    cd "$PROJECT_DIR"
}

build_libopus() {
    local platform="$1"
    echo "── libopus ($platform) ────────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/opus"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "v$LIBOPUS_VERSION" \
            https://github.com/xiph/opus.git "$src"
    fi
    cd "$src"
    make distclean 2>/dev/null || true
    [ -f configure ] || ./autogen.sh
    ./configure --host="$CONFIGURE_HOST" \
        --prefix="$INSTALL_DIR/opus" \
        --enable-static --disable-shared \
        --disable-doc --disable-extra-programs
    make -j"$NPROC"
    make install
    cd "$PROJECT_DIR"
}

build_whisper() {
    local platform="$1"
    echo "── whisper.cpp ($platform) ────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/whisper.cpp"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "$WHISPER_VERSION" \
            https://github.com/ggerganov/whisper.cpp.git "$src"
    fi
    cd "$src"
    rm -rf build-ios && mkdir build-ios && cd build-ios

    # Metal acceleration only on device (not simulator). Requires iOS Metal SDK
    # in the Xcode toolchain. Disable if Metal headers aren't available.
    local metal_flag="-DGGML_METAL=OFF"
    if [ "$platform" = "iphoneos" ] && [ -d "$SDK_PATH/System/Library/Frameworks/Metal.framework" ]; then
        metal_flag="-DGGML_METAL=ON"
    fi

    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/whisper" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF \
        -DGGML_NATIVE=OFF \
        -DGGML_OPENMP=OFF \
        $metal_flag \
        ..
    ninja -j"$NPROC" install
    cd "$PROJECT_DIR"
}

build_cleona_audio() {
    local platform="$1"
    echo "── libcleona_audio ($platform) ────────────────────────────────"
    setup_env "$platform"
    local src="$PROJECT_DIR/native/cleona_audio"
    local build="$BUILD_DIR/cleona_audio"
    rm -rf "$build" && mkdir -p "$build" && cd "$build"

    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCLEONA_IOS_STATIC=ON \
        "$src"
    ninja -j"$NPROC"
    mkdir -p "$INSTALL_DIR/cleona_audio/lib" "$INSTALL_DIR/cleona_audio/include"
    cp libcleona_audio.a "$INSTALL_DIR/cleona_audio/lib/"
    cp "$src/cleona_audio.h" "$INSTALL_DIR/cleona_audio/include/"
    cd "$PROJECT_DIR"
}

# ── Build orchestrator ───────────────────────────────────────────────────────
PLATFORMS=()
[ "$BUILD_DEVICE" -eq 1 ] && PLATFORMS+=(iphoneos)
[ "$BUILD_SIM" -eq 1 ] && PLATFORMS+=(iphonesimulator)

ALL_LIBS=(sodium oqs zstd erasurecode opus whisper cleona_audio)
WANTED=("${TARGETS[@]}")
if [ "${WANTED[0]}" = "all" ]; then
    WANTED=("${ALL_LIBS[@]}")
fi

for platform in "${PLATFORMS[@]}"; do
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Platform: $platform"
    echo "╚══════════════════════════════════════════════════════════════╝"
    for t in "${WANTED[@]}"; do
        case "$t" in
            sodium)        build_libsodium "$platform" ;;
            oqs)           build_liboqs "$platform" ;;
            zstd)          build_libzstd "$platform" ;;
            erasurecode)   build_liberasurecode "$platform" ;;
            opus)          build_libopus "$platform" ;;
            whisper)       build_whisper "$platform" ;;
            cleona_audio)  build_cleona_audio "$platform" ;;
            *) echo "Unknown target: $t"; exit 1 ;;
        esac
    done
done

# ── Create XCFrameworks ──────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Creating XCFrameworks"
echo "╚══════════════════════════════════════════════════════════════╝"

DEVICE_INSTALL="/tmp/ios-libs-build-device/install"
SIM_INSTALL="/tmp/ios-libs-build-simulator/install"

make_xcfw() {
    local name="$1"
    local subdir="$2"
    local libfile="$3"
    local headerdir="${4:-}"

    local device_lib="" sim_lib="" headers=""
    [ -f "$DEVICE_INSTALL/$subdir/lib/$libfile" ] && device_lib="$DEVICE_INSTALL/$subdir/lib/$libfile"
    [ -f "$SIM_INSTALL/$subdir/lib/$libfile" ] && sim_lib="$SIM_INSTALL/$subdir/lib/$libfile"
    [ -n "$headerdir" ] && [ -d "$DEVICE_INSTALL/$subdir/$headerdir" ] && headers="$DEVICE_INSTALL/$subdir/$headerdir"
    [ -n "$headerdir" ] && [ -z "$headers" ] && [ -d "$SIM_INSTALL/$subdir/$headerdir" ] && headers="$SIM_INSTALL/$subdir/$headerdir"

    if [ -n "$device_lib" ] || [ -n "$sim_lib" ]; then
        create_xcframework "$name" "$device_lib" "$sim_lib" "$headers"
    else
        echo "  [!] $name: no .a files found — skipped"
    fi
}

for t in "${WANTED[@]}"; do
    case "$t" in
        sodium)        make_xcfw libsodium sodium libsodium.a include ;;
        oqs)           make_xcfw liboqs oqs liboqs.a include ;;
        zstd)          make_xcfw libzstd zstd libzstd.a include ;;
        erasurecode)   make_xcfw liberasurecode ec liberasurecode.a include ;;
        opus)          make_xcfw libopus opus libopus.a include ;;
        whisper)
            make_xcfw libwhisper whisper libwhisper.a include
            for ggml_lib in libggml.a libggml-base.a libggml-cpu.a; do
                local_name="${ggml_lib%.a}"
                [ -f "$DEVICE_INSTALL/whisper/lib/$ggml_lib" ] || [ -f "$SIM_INSTALL/whisper/lib/$ggml_lib" ] && \
                    make_xcfw "$local_name" whisper "$ggml_lib" ""
            done
            ;;
        cleona_audio)  make_xcfw libcleona_audio cleona_audio libcleona_audio.a include ;;
    esac
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "XCFrameworks in: $XCFW_DIR/"
ls -1 "$XCFW_DIR/" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Next: these XCFrameworks are referenced by ios/Podfile."
echo "Run 'cd ios && pod install' to link them into the Xcode project."
