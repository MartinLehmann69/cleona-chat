#!/bin/bash
###############################################################################
# build-ios-libs.sh — Build native libraries for iOS
#
# Builds libsodium, liboqs, libzstd, liberasurecode, libopus, whisper.cpp,
# as STATIC libraries (.a) for iOS.
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
WHISPER_VERSION="v1.8.4"  NPROC="$(sysctl -n hw.ncpu)"

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
            ;;
        iphonesimulator)
            SDK_PATH="$SIM_SDK"
            ARCH="arm64"
            TARGET_TRIPLE="arm64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            CONFIGURE_HOST="aarch64-apple-darwin"
            PLATFORM_TAG="simulator"
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
    if [ -d m4 ] && [ ! -f "m4/lt~obsolete.m4" ]; then
        touch "m4/lt~obsolete.m4"
    fi
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
    # macOS APFS + newer libtool may drop lt~obsolete.m4 (tilde in filename)
    if [ -d m4 ] && [ ! -f "m4/lt~obsolete.m4" ]; then
        touch "m4/lt~obsolete.m4"
    fi
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

build_cleona_pow() {
    local platform="$1"
    echo "── libcleona_pow ($platform) ─────────────────────────────────"
    setup_env "$platform"
    local src="$PROJECT_DIR/native/cleona_pow"
    local build="$BUILD_DIR/cleona_pow"
    rm -rf "$build" && mkdir -p "$build" && cd "$build"

    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DSODIUM_LIB="$INSTALL_DIR/sodium/lib/libsodium.a" \
        -DSODIUM_INCLUDE="$INSTALL_DIR/sodium/include" \
        "$src"
    ninja -j"$NPROC"
    mkdir -p "$INSTALL_DIR/cleona_pow/lib"
    cp libcleona_pow.a "$INSTALL_DIR/cleona_pow/lib/"
    cd "$PROJECT_DIR"
}

# Dart FFI bridge to whisper.cpp (S280).
#
# native/whisper_wrapper.c provides whisper_full_from_ptr() plus the setters
# whisper_params_set_language/_n_threads. Since 2026-07-26 both setters are
# listed in ios/CleonaNative/cleona_exported_symbols.txt (lines 83-84) and thus
# must be resolved at runner link time — but they were never built for iOS.
# build-whisper-wrapper.sh claims in its header that
# "iOS/macOS-Statik-Builds linken die Quelle direkt mit"; for iOS that was not
# true. The last green iOS build (v3.1.156, 2026-07-24) predates those lines,
# and afterwards the prefix cache masked the breakage.
#
# Installed into whisper/lib because that directory is already on the merge
# subdir list.
build_whisper_wrapper() {
    local platform="$1"
    echo "── whisper_wrapper ($platform) ───────────────────────────────"
    setup_env "$platform"
    local src="$PROJECT_DIR/native/whisper_wrapper.c"
    local build="$BUILD_DIR/whisper_wrapper"
    rm -rf "$build" && mkdir -p "$build" && cd "$build"

    if [ ! -f "$INSTALL_DIR/whisper/include/whisper.h" ]; then
        echo "  [!] whisper.h missing in $INSTALL_DIR/whisper/include — whisper must be built first"
        exit 1
    fi

    # whisper.h pulls in ggml.h; in the install tree both live under include/,
    # and for some whisper releases additionally under ggml/include.
    local ggml_inc=""
    [ -d "$INSTALL_DIR/whisper/include/ggml" ] && ggml_inc="-I$INSTALL_DIR/whisper/include/ggml"

    # shellcheck disable=SC2086  # CFLAGS intentionally word-split (arch/-isysroot/-target)
    "$CC" $CFLAGS -I"$INSTALL_DIR/whisper/include" $ggml_inc \
        -c "$src" -o whisper_wrapper.o
    "$AR" rcs libwhisper_wrapper.a whisper_wrapper.o
    "$RANLIB" libwhisper_wrapper.a

    for sym in _whisper_params_set_language _whisper_params_set_n_threads _whisper_full_from_ptr; do
        if ! nm -g libwhisper_wrapper.a 2>/dev/null | grep -q "$sym"; then
            echo "  [!] libwhisper_wrapper.a does not define $sym"
            exit 1
        fi
    done

    mkdir -p "$INSTALL_DIR/whisper/lib"
    cp libwhisper_wrapper.a "$INSTALL_DIR/whisper/lib/"
    echo "  -> $INSTALL_DIR/whisper/lib/libwhisper_wrapper.a"
    cd "$PROJECT_DIR"
}

build_cleona_voice() {
    local platform="$1"
    echo "── libcleona_voice (VoiceProcessingIO) ($platform) ─────────────"
    setup_env "$platform"
    local src="$PROJECT_DIR/native/cleona_voice"
    local build="$BUILD_DIR/cleona_voice"
    rm -rf "$build" && mkdir -p "$build" && cd "$build"

    cmake -GNinja \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCLEONA_IOS_STATIC=ON \
        -DCLEONA_VOICE_BUILD_MOCK=OFF \
        -DCLEONA_VOICE_BUILD_SMOKE=OFF \
        -DCLEONA_VOICE_APPLE_BUILD_CONFORMANCE=OFF \
        "$src"
    ninja -j"$NPROC"
    mkdir -p "$INSTALL_DIR/cleona_voice/lib" "$INSTALL_DIR/cleona_voice/include"
    cp apple/libcleona_voice.a "$INSTALL_DIR/cleona_voice/lib/"
    cp "$src/cleona_voice.h"   "$INSTALL_DIR/cleona_voice/include/"
    cd "$PROJECT_DIR"
}

# ── Build orchestrator ───────────────────────────────────────────────────────
PLATFORMS=()
[ "$BUILD_DEVICE" -eq 1 ] && PLATFORMS+=(iphoneos)
[ "$BUILD_SIM" -eq 1 ] && PLATFORMS+=(iphonesimulator)

ALL_LIBS=(sodium oqs zstd erasurecode opus whisper cleona_pow cleona_voice)
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
            # Wrapper haengt an whisper (braucht dessen Header) und wird
            # deshalb im selben Ziel gebaut — so greift auch
            # `build-ios-libs.sh whisper`.
            whisper)       build_whisper "$platform"; build_whisper_wrapper "$platform" ;;
            cleona_pow)    build_cleona_pow "$platform" ;;
            cleona_voice)  build_cleona_voice "$platform" ;;
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
        cleona_pow)    make_xcfw libcleona_pow cleona_pow libcleona_pow.a ;;
        cleona_voice)  make_xcfw CleonaVoice cleona_voice libcleona_voice.a include ;;
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
    #
    # ggml is split across libggml.a / libggml-base.a / libggml-cpu.a and how
    # the objects are distributed across those three archives is a whisper.cpp
    # implementation detail that CHANGES BETWEEN VERSIONS. Up to whisper 1.7.1
    # libggml.a was an umbrella that already contained the other two, so this
    # loop skipped them by name. b042cd09 pinned whisper 1.8.4, where the three
    # archives are disjoint — the hardcoded skip then dropped every symbol that
    # only lives in libggml-base.a / libggml-cpu.a and the Runner link died with
    # "Undefined symbol: _ggml_reshape_2d" and ~200 siblings (S279, run
    # 30209700530). The macOS job ships all three as separate dylibs, which is
    # what proved they are disjoint under 1.8.4.
    #
    # So: do not encode the layout, MEASURE it. Include an archive unless its
    # global symbols are already fully covered by an archive we accepted
    # earlier. That is correct for both the umbrella layout and the disjoint
    # layout, and it stays correct across the next whisper bump.
    # Order matters: an umbrella archive must be considered BEFORE its parts,
    # otherwise the parts get accepted first and the umbrella still adds unique
    # symbols on top, so all three land in the merge and we are back to
    # duplicate symbols. Processing by descending symbol count makes the
    # umbrella win in the 1.7.1 layout, and is a no-op in the 1.8.4 layout where
    # the three archives are disjoint and all three are needed.
    _symdir="$(mktemp -d)"
    _index="$_symdir/index"
    : > "$_index"

    for subdir in sodium/lib oqs/lib zstd/lib ec/lib opus/lib whisper/lib cleona_pow/lib cleona_voice/lib; do
        for a in "$INSTALL/$subdir"/*.a; do
            [ -f "$a" ] || continue
            _slug="$(echo "$a" | tr -c 'A-Za-z0-9' '_')"
            # Defined global symbols. Uppercase type letters are definitions;
            # 'U' entries are undefined references and must not count as
            # "provided by this archive".
            nm -g "$a" 2>/dev/null \
              | awk '$2 ~ /^[A-TV-Z]$/ { print $3 }' \
              | sort -u > "$_symdir/$_slug"
            printf '%s\t%s\t%s\n' \
              "$(wc -l < "$_symdir/$_slug" | tr -d ' ')" "$a" "$_symdir/$_slug" >> "$_index"
        done
    done

    ALL_ARCHIVES=()
    _accepted="$_symdir/.accepted"
    : > "$_accepted"
    # Descending symbol count, path as tie-breaker for reproducibility.
    while IFS=$'\t' read -r _count _path _syms; do
        [ -n "$_path" ] || continue
        if [ "$_count" -eq 0 ]; then
            echo "  skip $(basename "$_path") (no global symbols)"
            continue
        fi
        if [ -s "$_accepted" ] && [ -z "$(comm -23 "$_syms" "$_accepted" | head -1)" ]; then
            echo "  skip $(basename "$_path") ($_count symbols already covered)"
            continue
        fi
        ALL_ARCHIVES+=("$_path")
        sort -u -o "$_accepted" "$_accepted" "$_syms"
    done < <(sort -t"$(printf '\t')" -k1,1nr -k2,2 "$_index")

    rm -rf "$_symdir"

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
