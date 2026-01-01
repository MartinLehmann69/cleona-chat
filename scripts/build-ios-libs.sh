#!/bin/bash
###############################################################################
# build-ios-libs.sh — Build native libraries for iOS
#
# Builds libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp,
# libcleona_audio, libvpx and libcleona_vpx as STATIC libraries (.a) for iOS.
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
LIBOQS_VERSION="0.15.0"
LIBZSTD_VERSION="1.5.6"
LIBERASURECODE_VERSION="1.6.2"
LIBOPUS_VERSION="1.5.2"
WHISPER_VERSION="v1.7.1"
LIBVPX_VERSION="1.14.0"

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
    if [ -d "$src" ]; then
        local cached_tag
        cached_tag=$(git -C "$src" describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$cached_tag" != "$LIBOQS_VERSION" ]; then
            echo "  Cached liboqs is $cached_tag, need $LIBOQS_VERSION — re-cloning"
            rm -rf "$src"
        fi
    fi
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
    ./autogen.sh
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
    ./autogen.sh
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
    # On iOS, CMake's Ninja generator embeds the speexdsp subdirectory
    # objects into libcleona_audio.a automatically (unlike shared lib
    # builds on other platforms). No separate speexdsp/lib needed.
    cp "$src/cleona_audio.h" "$INSTALL_DIR/cleona_audio/include/"
    cd "$PROJECT_DIR"
}

build_libvpx() {
    local platform="$1"
    echo "── libvpx ($platform) ─────────────────────────────────────────"
    setup_env "$platform"
    local src="$BUILD_DIR/libvpx"
    if [ ! -d "$src" ]; then
        git clone --depth 1 --branch "v$LIBVPX_VERSION" \
            https://github.com/webmproject/libvpx.git "$src"
    fi
    cd "$src"
    make distclean 2>/dev/null || true

    # libvpx does NOT use CMake/autotools-style --host=; it has its own
    # configure with --target=<isa>-<os>-<cc>. The target string selects
    # codec ISA features (NEON) AND — for the darwin/iphonesimulator
    # cases — makes configure append its own -isysroot/-miphoneos-
    # version-min flags on top of the CC/CFLAGS/LDFLAGS this script
    # already exports via setup_env. Verified against libvpx's
    # build/make/configure.sh (v1.14.0):
    #
    #   - Device (iphoneos): arm64-darwin-gcc
    #     Listed in configure's all_platforms whitelist. Matches the
    #     `arm*-darwin-*` case, which resolves the iphoneos SDK itself
    #     via `xcrun --sdk iphoneos` (redundant with, but consistent
    #     with, our own -isysroot).
    #
    #   - Simulator: arm64-iphonesimulator-gcc (with --force-toolchain)
    #     NOT in configure's all_platforms whitelist — libvpx only
    #     pre-registers x86/x86_64 iphonesimulator variants (predates
    #     Apple Silicon simulators). --force-toolchain bypasses the
    #     whitelist check (`is_in ... || enabled force_toolchain`);
    #     the toolchain string still matches the `*-iphonesimulator-*`
    #     case in configure.sh's target-parsing, which correctly
    #     resolves the iphonesimulator SDK. Using arm64-darwin-gcc for
    #     the simulator instead would be wrong: it hits the
    #     `arm*-darwin-*` case, which appends an *iphoneos* -isysroot
    #     AFTER ours, silently pointing the simulator build at the
    #     wrong SDK (last -isysroot wins).
    local vpx_target="arm64-darwin-gcc"
    local force_flag=""
    if [ "$platform" = "iphonesimulator" ]; then
        vpx_target="arm64-iphonesimulator-gcc"
        force_flag="--force-toolchain"
    fi

    # VP8-only: vpx_shim.c (native/vpx_shim.c) only calls vpx_codec_vp8_cx/
    # vpx_codec_vp8_dx and the codec-agnostic vpx_codec_* / vpx_img_*
    # entry points — no VP9 symbols are used. --disable-vp9 keeps the
    # build lean. --disable-webm-io/--disable-libyuv are already the
    # default (off); listed explicitly for documentation.
    # shellcheck disable=SC2086
    ./configure \
        --target="$vpx_target" $force_flag \
        --prefix="$INSTALL_DIR/vpx" \
        --disable-examples \
        --disable-tools \
        --disable-docs \
        --disable-unit-tests \
        --disable-install-bins \
        --disable-install-docs \
        --disable-vp9 \
        --enable-vp8 \
        --enable-static \
        --disable-shared \
        --disable-webm-io \
        --disable-libyuv
    make -j"$NPROC"
    make install
    cd "$PROJECT_DIR"
}

build_cleona_vpx() {
    local platform="$1"
    echo "── libcleona_vpx ($platform) ────────────────────────────────────"
    setup_env "$platform"
    local src="$PROJECT_DIR/native/vpx_shim.c"
    mkdir -p "$INSTALL_DIR/cleona_vpx/lib"

    # vpx_shim.c has no CMakeLists (unlike cleona_audio) — it is a single
    # translation unit with no external headers beyond libc/dlfcn (it
    # treats libvpx structs as opaque byte buffers rather than #include-ing
    # vpx headers), so a direct clang -c + ar via the CC/AR this script
    # already resolves in setup_env is simpler than adding build machinery.
    # shellcheck disable=SC2086
    "$CC" $CFLAGS -c "$src" -o "$BUILD_DIR/vpx_shim.o"
    rm -f "$INSTALL_DIR/cleona_vpx/lib/libcleona_vpx.a"
    "$AR" rcs "$INSTALL_DIR/cleona_vpx/lib/libcleona_vpx.a" "$BUILD_DIR/vpx_shim.o"
    cd "$PROJECT_DIR"
}

# ── Build orchestrator ───────────────────────────────────────────────────────
PLATFORMS=()
[ "$BUILD_DEVICE" -eq 1 ] && PLATFORMS+=(iphoneos)
[ "$BUILD_SIM" -eq 1 ] && PLATFORMS+=(iphonesimulator)

ALL_LIBS=(sodium oqs zstd erasurecode opus whisper cleona_audio vpx cleona_vpx)
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
            vpx)           build_libvpx "$platform" ;;
            cleona_vpx)    build_cleona_vpx "$platform" ;;
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
        vpx)           make_xcfw libvpx vpx libvpx.a include ;;
        cleona_vpx)    make_xcfw libcleona_vpx cleona_vpx libcleona_vpx.a ;;
    esac
done

# ── Merge all .a into libcleona_all.a ───────────────────────────────────────
# iOS requires static linking (no dlopen). dart:ffi uses DynamicLibrary.process()
# which needs symbols in the Runner binary. The linker dead-strips unreferenced
# C symbols unless we use -force_load. Merging into one archive avoids:
#   - liberasurecode internal cross-object-file deps under selective loading
#   - 10 separate -force_load flags
#   - path resolution headaches with per-lib XCFramework directories
# The merged archive is placed in ios/CleonaNative/ where the Podfile can
# reference it with a stable, known path.
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Merging all .a into libcleona_all.a"
echo "╚══════════════════════════════════════════════════════════════╝"

CLEONA_NATIVE_DIR="$PROJECT_DIR/ios/CleonaNative"
mkdir -p "$CLEONA_NATIVE_DIR"

for platform_tag in device simulator; do
    INSTALL="$( [ "$platform_tag" = "device" ] && echo "$DEVICE_INSTALL" || echo "$SIM_INSTALL" )"
    [ -d "$INSTALL" ] || continue

    # Collect all .a files from all lib install dirs.
    # Skip libggml-base.a and libggml-cpu.a — libggml.a is the umbrella
    # that already contains their object files. Including all three causes
    # duplicate symbols when DEAD_CODE_STRIPPING is disabled.
    ALL_ARCHIVES=()
    for subdir in sodium/lib oqs/lib zstd/lib ec/lib opus/lib whisper/lib cleona_audio/lib vpx/lib cleona_vpx/lib; do
        for a in "$INSTALL/$subdir"/*.a; do
            [ -f "$a" ] || continue
            case "$(basename "$a")" in
                libggml-base.a|libggml-cpu.a) echo "  skip $(basename "$a") (in libggml.a)"; continue ;;
            esac
            ALL_ARCHIVES+=("$a")
        done
    done

    if [ ${#ALL_ARCHIVES[@]} -eq 0 ]; then
        echo "  [!] No .a files for $platform_tag — skipping merge"
        continue
    fi

    MERGED="$INSTALL/libcleona_all.a"
    echo "  Merging ${#ALL_ARCHIVES[@]} archives for $platform_tag..."
    # Apple libtool -static merges multiple .a into one, resolving internal refs
    xcrun libtool -static -o "$MERGED" "${ALL_ARCHIVES[@]}"
    echo "  -> $MERGED ($(du -h "$MERGED" | cut -f1))"
done

# Create XCFramework for the merged archive
MERGED_XCFW="$XCFW_DIR/libcleona_all.xcframework"
rm -rf "$MERGED_XCFW"
MERGE_ARGS=()
[ -f "$DEVICE_INSTALL/libcleona_all.a" ] && MERGE_ARGS+=(-library "$DEVICE_INSTALL/libcleona_all.a")
[ -f "$SIM_INSTALL/libcleona_all.a" ] && MERGE_ARGS+=(-library "$SIM_INSTALL/libcleona_all.a")
if [ ${#MERGE_ARGS[@]} -gt 0 ]; then
    xcodebuild -create-xcframework "${MERGE_ARGS[@]}" -output "$MERGED_XCFW"
    echo "  -> $MERGED_XCFW"
fi

# Also copy the merged .a directly into ios/CleonaNative/ for the Podfile.
# The Podfile post_install references this path for -force_load.
# We copy the device slice (arm64-iphoneos) which is what ships in the IPA.
# For simulator builds, the xcframework approach handles slice selection.
if [ -f "$DEVICE_INSTALL/libcleona_all.a" ]; then
    cp "$DEVICE_INSTALL/libcleona_all.a" "$CLEONA_NATIVE_DIR/libcleona_all_device.a"
    echo "  -> $CLEONA_NATIVE_DIR/libcleona_all_device.a"
fi
if [ -f "$SIM_INSTALL/libcleona_all.a" ]; then
    cp "$SIM_INSTALL/libcleona_all.a" "$CLEONA_NATIVE_DIR/libcleona_all_simulator.a"
    echo "  -> $CLEONA_NATIVE_DIR/libcleona_all_simulator.a"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "XCFrameworks in: $XCFW_DIR/"
ls -1 "$XCFW_DIR/" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Merged archives in: $CLEONA_NATIVE_DIR/"
ls -lh "$CLEONA_NATIVE_DIR"/libcleona_all_*.a 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
echo ""
echo "Next: run 'cd ios && pod install' to set up the Xcode project."
echo "The Podfile post_install hook injects -force_load automatically."
