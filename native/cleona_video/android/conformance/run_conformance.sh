#!/usr/bin/env bash
#
# run_conformance.sh — build and run the cleona_video conformance harness on a
# real Android runtime. Work package V1.14, acceptance (SPEC §10 gate 4).
#
# WHY NOT THE PLAIN adb-shell BINARY
# ----------------------------------
# native/cleona_video/test/CMakeLists.txt describes route (A): push the loader
# binary and the backend .so to /data/local/tmp and run them there. That is
# right for a backend that is pure native code. This one is not: Camera2's
# `CameraManager` needs an application `Context`, which an `adb shell` process
# does not have (it is not even a Zygote-forked Dalvik process). This script
# therefore packages the *unmodified* V0.4 harness sources into a small test
# APK and runs them there, which is the same environment production runs in --
# exactly the precedent native/cleona_voice/android/conformance/run_conformance.sh
# (V1.2) set for the same structural reason.
#
# The harness itself is never copied or edited. It is compiled from
# CLEONA_VIDEO_CONFORMANCE_SOURCES, the extension point V0.4 exports for
# exactly this purpose.
#
# THE PLATFORM-LOOP PATCH (staged copy only, never the repository)
# ------------------------------------------------------------------
# native/cleona_video/CMakeLists.txt does not (yet) add a platform-subdirectory
# loop the way native/cleona_voice/CMakeLists.txt does; that loop belongs to
# the build owner and is requested in native/cleona_video/test/BUILD_REQUEST.md
# §1 -- open, not blocking (route (A) does not need it). It DOES block this
# script's route (which needs android/CMakeLists.txt reached from the parent
# tree), so this script applies the exact snippet BUILD_REQUEST.md §1 already
# specifies to a STAGED COPY only, exactly the interim measure
# BUILD_REQUEST_V1.2.md §5 used for the analogous voice-tree blocker (linux
# backend missing a host guard). Nothing under native/cleona_video/ in the
# repository is touched.
#
# VARIANTS — the negative controls
# ---------------------------------
# A green run only means something if a broken backend comes out red. Every
# variant other than `default` patches a staged COPY of VideoSession.kt; the
# repository tree is never modified.
#
#   default          the backend as it ships.
#   open-err-swap    THE TRAP THIS PACKAGE WAS BRIEFED ON (V1.14 §3): swaps
#                     ERR_RATE_UNACHIEVABLE for ERR_BACKEND in openSession()'s
#                     phase-1 refusal. V1b must fail (Erratum 6b: the two codes
#                     must not be confused), and it must be the ONLY check that
#                     fails -- a backend that always claims "camera busy"
#                     instead of "link too slow" would otherwise look identical
#                     to a conformant one on every other check.
#   short-frame      the JNI facade's read wrapper is defeated by truncating
#                     one delivered frame by 4 bytes before it reaches the
#                     harness -- corrupts the size/guard-zone bookkeeping V7
#                     asserts on every frame.
#
# USAGE
#   run_conformance.sh [--serial S] [--variant V] [--expect-fail IDS]
#                      [--no-shipping] [--revoke-camera] [--keep]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PKG="chat.cleona.videoconformance"
ACTIVITY="$PKG/chat.cleona.videoconformance.ConformanceActivity"

SERIAL=""
VARIANT="default"
EXPECT_FAIL=""
SHIPPING="true"
REVOKE_CAMERA="false"
KEEP="false"
RUN_TIMEOUT=300

while [ $# -gt 0 ]; do
    case "$1" in
        --serial)        SERIAL="$2"; shift 2 ;;
        --variant)       VARIANT="$2"; shift 2 ;;   # see the variant list above
        --expect-fail)   EXPECT_FAIL="$2"; shift 2 ;;
        --no-shipping)   SHIPPING="false"; shift ;;
        --revoke-camera) REVOKE_CAMERA="true"; shift ;;
        --keep)          KEEP="true"; shift ;;
        -h|--help)       sed -n '2,45p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android}"
ADB="${ADB:-$ANDROID_HOME/platform-tools/adb}"

pick_newest() { ls -d "$@" 2>/dev/null | sort -V | tail -1; }

NDK="${ANDROID_NDK:-$(pick_newest "$ANDROID_HOME"/ndk/*)}"
BUILD_TOOLS="$(pick_newest "$ANDROID_HOME"/build-tools/*)"
ANDROID_PLATFORM_DIR="$(pick_newest "$ANDROID_HOME"/platforms/android-*)"
ANDROID_JAR="$ANDROID_PLATFORM_DIR/android.jar"

# Both Kotlin jars are taken from the SAME Gradle distribution directory so the
# compiler and the stdlib can never be a mismatched pair (same reasoning as
# the voice script).
KOTLIN_LIB_DIR="${KOTLIN_LIB_DIR:-$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-*/*/gradle-*/lib 2>/dev/null | sort -V | tail -1)}"
KOTLINC_JAR="$(ls "$KOTLIN_LIB_DIR"/kotlin-compiler-embeddable-*.jar 2>/dev/null | head -1 || true)"
KOTLIN_STDLIB="$(ls "$KOTLIN_LIB_DIR"/kotlin-stdlib-*.jar 2>/dev/null | head -1 || true)"

KOTLINC_CP="$KOTLINC_JAR"
for j in kotlin-stdlib kotlin-reflect kotlin-script-runtime kotlin-daemon-embeddable \
         kotlinx-coroutines-core-jvm trove4j annotations; do
    extra="$(ls "$KOTLIN_LIB_DIR"/"$j"-*.jar 2>/dev/null | head -1 || true)"
    [ -n "$extra" ] && KOTLINC_CP="$KOTLINC_CP:$extra"
done

for v in ADB NDK BUILD_TOOLS ANDROID_JAR KOTLINC_JAR KOTLIN_STDLIB; do
    if [ -z "${!v}" ] || [ ! -e "${!v}" ]; then
        echo "FATAL: $v not found (${!v:-unset})" >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Device
# ---------------------------------------------------------------------------
if [ -z "$SERIAL" ]; then
    SERIAL="$("$ADB" devices | awk '$2=="device"{print $1; exit}')"
fi
if [ -z "$SERIAL" ]; then
    echo "FATAL: no adb device. Attach a phone or start the emulator." >&2
    exit 2
fi
adbs() { "$ADB" -s "$SERIAL" "$@"; }

ABI="$(adbs shell getprop ro.product.cpu.abi | tr -d '\r')"
API="$(adbs shell getprop ro.build.version.sdk | tr -d '\r')"
MODEL="$(adbs shell getprop ro.product.model | tr -d '\r')"

echo "=== cleona_video conformance (V1.14) ==="
echo "device   : $SERIAL  $MODEL  API $API  $ABI"
echo "variant  : $VARIANT"
echo "shipping : $SHIPPING   expect-fail: '${EXPECT_FAIL:-none}'   revoke-camera: $REVOKE_CAMERA"
echo "ndk      : $NDK"
echo "kotlin   : $(basename "$KOTLINC_JAR")"
echo

BUILD="$REPO_ROOT/build/video-android/$VARIANT"
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$STAGE/kotlin" "$BUILD/classes" "$BUILD/dex" "$BUILD/pack/lib/$ABI"

# ---------------------------------------------------------------------------
# Stage the sources. Patches are applied to this copy, never to the repository.
# ---------------------------------------------------------------------------
cp -a "$REPO_ROOT/native/cleona_video" "$STAGE/cleona_video"
cp "$REPO_ROOT/android/app/src/main/kotlin/chat/cleona/cleona/VideoSession.kt" \
   "$STAGE/kotlin/VideoSession.kt"
cp "$SCRIPT_DIR/runner/ConformanceRunner.kt" "$STAGE/kotlin/ConformanceRunner.kt"

# The platform-loop patch described in the file header -- verbatim from
# native/cleona_video/test/BUILD_REQUEST.md §1, applied to the STAGED tree
# only. `android/CMakeLists.txt` is the only platform directory this stage
# needs (V1.13/V1.15/V1.16 do not exist as directories yet, so the loop is
# inert for the other three names).
cat >> "$STAGE/cleona_video/CMakeLists.txt" <<'EOF'

# --- interim patch applied ONLY to the staged copy by
# native/cleona_video/android/conformance/run_conformance.sh (V1.14).
# Verbatim from native/cleona_video/test/BUILD_REQUEST.md §1. Never applied to
# the repository -- see that file for the real fix, owned by the build package.
foreach(_plat linux android apple windows)
  if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
    add_subdirectory(${_plat})
  endif()
endforeach()
EOF
echo "staging  : appended the platform loop from test/BUILD_REQUEST.md §1 (staged copy only)"

# `sed -i` succeeds on a pattern that matches nothing, which would silently
# produce a "negative control" that sabotages nothing at all. Every patch is
# therefore verified to have changed the file -- same discipline as the voice
# script's patch_file().
patch_file() {   # patch_file <file> <sed-expr> <description>
    local f="$1" expr="$2" what="$3"
    local before after
    before="$(md5sum "$f" | cut -d' ' -f1)"
    sed -i "$expr" "$f"
    after="$(md5sum "$f" | cut -d' ' -f1)"
    if [ "$before" = "$after" ]; then
        echo "FATAL: variant patch did not apply: $what" >&2
        exit 2
    fi
    echo "patched: $what"
}

case "$VARIANT" in
    default) ;;
    open-err-swap)
        # THE TRAP (V1.14 briefing §3): swap the two failure codes at the one
        # place a real "camera busy" condition and a real "link too slow"
        # condition could otherwise be confused. Only the deliberately
        # unachievable synthetic case (mfb=1, conformance.c V1b) is
        # reproducible without hardware, so that is what flips.
        patch_file "$STAGE/kotlin/VideoSession.kt" \
            's|return fail(Abi.ERR_RATE_UNACHIEVABLE)|return fail(Abi.ERR_BACKEND)|' \
            "openSession() reports ERR_BACKEND instead of ERR_RATE_UNACHIEVABLE for an unmeetable ceiling" ;;
    short-frame)
        patch_file "$STAGE/kotlin/VideoSession.kt" \
            's|buf.put(frame.data)|buf.put(frame.data, 0, frame.data.size - 4)|' \
            "readEncoded copies four bytes less than the frame it reports" ;;
    *) echo "unknown variant: $VARIANT (default|open-err-swap|short-frame)" >&2
       exit 2 ;;
esac

# ---------------------------------------------------------------------------
# 1. Native
# ---------------------------------------------------------------------------
echo "--- building native ($ABI) ---"
cmake -S "$STAGE/cleona_video" -B "$BUILD/cmake" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$ABI" \
      -DANDROID_PLATFORM=android-24 \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCLEONA_VIDEO_BUILD_MOCK=OFF \
      -DCLEONA_VIDEO_BUILD_SMOKE=OFF \
      -DCLEONA_VIDEO_ANDROID_CONFORMANCE=ON \
      > "$BUILD/cmake-configure.log" 2>&1 \
  || { echo "FATAL: cmake configure failed"; tail -40 "$BUILD/cmake-configure.log"; exit 2; }

cmake --build "$BUILD/cmake" -j"$(nproc)" > "$BUILD/cmake-build.log" 2>&1 \
  || { echo "FATAL: cmake build failed"; tail -60 "$BUILD/cmake-build.log"; exit 2; }

SO_BACKEND="$(find "$BUILD/cmake" -name libcleona_video.so | head -1)"
SO_HARNESS="$(find "$BUILD/cmake" -name libcleona_video_conformance.so | head -1)"
[ -n "$SO_BACKEND" ] || { echo "FATAL: libcleona_video.so not produced"; exit 2; }
[ -n "$SO_HARNESS" ] || { echo "FATAL: libcleona_video_conformance.so not produced"; exit 2; }
cp "$SO_BACKEND" "$SO_HARNESS" "$BUILD/pack/lib/$ABI/"

# All twelve ABI entry points must really be exported, or the harness links
# against nothing and the Dart binding would fail the same way at runtime.
LLVM_NM="$(pick_newest "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-nm)"
if [ -z "$LLVM_NM" ] || [ ! -x "$LLVM_NM" ]; then
    echo "FATAL: llvm-nm not found under $NDK" >&2
    exit 2
fi

MISSING=""
for sym in open reconfigure start stop close read_encoded submit_encoded \
           get_texture_id request_keyframe set_capture_enabled switch_camera get_report; do
    "$LLVM_NM" --dynamic --defined-only "$SO_BACKEND" 2>/dev/null \
        | grep -q " cleona_video_$sym\$" \
        || MISSING="$MISSING cleona_video_$sym"
done
if [ -n "$MISSING" ]; then
    echo "FATAL: backend does not export:$MISSING" >&2
    exit 2
fi
echo "exports  : 12/12 ABI symbols present"

# ---------------------------------------------------------------------------
# 2. Kotlin -> dex
# ---------------------------------------------------------------------------
echo "--- compiling kotlin ---"
java -cp "$KOTLINC_CP" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
     -no-stdlib -nowarn -jvm-target 11 \
     -classpath "$ANDROID_JAR:$KOTLIN_STDLIB" \
     -d "$BUILD/classes" \
     "$STAGE/kotlin" > "$BUILD/kotlinc.log" 2>&1 \
  || { echo "FATAL: kotlinc failed"; cat "$BUILD/kotlinc.log"; exit 2; }

echo "--- dexing ---"
# shellcheck disable=SC2046
"$BUILD_TOOLS/d8" --release --min-api 24 --lib "$ANDROID_JAR" \
     --output "$BUILD/dex" \
     $(find "$BUILD/classes" -name '*.class') "$KOTLIN_STDLIB" \
     > "$BUILD/d8.log" 2>&1 \
  || { echo "FATAL: d8 failed"; tail -40 "$BUILD/d8.log"; exit 2; }
cp "$BUILD/dex/classes.dex" "$BUILD/pack/"

# ---------------------------------------------------------------------------
# 3. APK
# ---------------------------------------------------------------------------
echo "--- packaging ---"
"$BUILD_TOOLS/aapt2" link \
     -I "$ANDROID_JAR" \
     --manifest "$SCRIPT_DIR/runner/AndroidManifest.xml" \
     --min-sdk-version 24 --target-sdk-version 35 \
     -o "$BUILD/base.apk" > "$BUILD/aapt2.log" 2>&1 \
  || { echo "FATAL: aapt2 link failed"; cat "$BUILD/aapt2.log"; exit 2; }

cp "$BUILD/base.apk" "$BUILD/unsigned.apk"
( cd "$BUILD/pack" && zip -q -r -X "$BUILD/unsigned.apk" classes.dex lib )

KEYSTORE="$HOME/.android/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$(dirname "$KEYSTORE")"
    keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
            -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
            -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

"$BUILD_TOOLS/zipalign" -p -f 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk" >/dev/null
"$BUILD_TOOLS/apksigner" sign \
     --ks "$KEYSTORE" --ks-pass pass:android \
     --ks-key-alias androiddebugkey --key-pass pass:android \
     --out "$BUILD/conformance.apk" "$BUILD/aligned.apk" >/dev/null

# ---------------------------------------------------------------------------
# 4. Install and run
# ---------------------------------------------------------------------------
echo "--- installing ---"
# Fresh install, "Success" required, and the APK on the device must hash to
# the APK just built -- BUILD_REQUEST_V1.2.md's documented finding
# (`adb install -r` prints "Failure [...]" but still exits 0 on this adb) is
# just as reachable here, so the same discipline applies unconditionally
# rather than being re-discovered.
adbs uninstall "$PKG" >/dev/null 2>&1 || true
INSTALL_OUT="$(adbs install -t "$BUILD/conformance.apk" 2>&1 | tr -d '\r')"
if ! printf '%s' "$INSTALL_OUT" | grep -q "Success"; then
    echo "FATAL: install did not report Success:" >&2
    printf '%s\n' "$INSTALL_OUT" >&2
    exit 2
fi

DEV_APK="$( { adbs shell pm path "$PKG" || true; } | tr -d '\r' | sed -n 's/^package://p' | head -1)"
DEV_MD5="$( { adbs shell "md5sum $DEV_APK" || true; } | tr -d '\r' | awk '{print $1}')"
LOCAL_MD5="$(md5sum "$BUILD/conformance.apk" | awk '{print $1}')"
if [ -z "$DEV_MD5" ] || [ "$DEV_MD5" != "$LOCAL_MD5" ]; then
    echo "FATAL: the APK on the device is not the one just built." >&2
    echo "  device: ${DEV_MD5:-<unreadable>} ($DEV_APK)" >&2
    echo "  local : $LOCAL_MD5" >&2
    exit 2
fi
echo "apk      : $LOCAL_MD5 verified on device"

if [ "$REVOKE_CAMERA" = "true" ]; then
    adbs shell pm revoke "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
    echo "camera   : CAMERA REVOKED (negative control)"
else
    adbs shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
    echo "camera   : CAMERA granted"
fi

adbs shell am force-stop "$PKG" >/dev/null 2>&1 || true
adbs logcat -c >/dev/null 2>&1 || true

# Capture the backend's own log for the whole run, for the same reason the
# voice script does: a chatty driver can rotate the ring buffer within the
# run's duration and take the verification-relevant lines with it.
adbs logcat -v time -s CleonaVideo:V CleonaVideoConf:V CleonaVideoHeadlessTex:V \
     AndroidRuntime:E \
     > "$BUILD/logcat.txt" 2>/dev/null &
LOGCAT_PID=$!
trap 'kill "$LOGCAT_PID" 2>/dev/null || true' EXIT

echo "--- running ---"
AM_EXTRA=""
[ -n "$EXPECT_FAIL" ] && AM_EXTRA="--es expectFail $EXPECT_FAIL"
# shellcheck disable=SC2086
adbs shell am start -n "$ACTIVITY" --ez shipping "$SHIPPING" $AM_EXTRA >/dev/null

DONE=""
for _ in $(seq 1 "$RUN_TIMEOUT"); do
    DONE="$( { adbs shell "run-as $PKG cat files/conformance.done 2>/dev/null" || true; } | tr -d '\r')"
    [ -n "$DONE" ] && break
    sleep 1
done

# Stop the app before reading its output -- see the file header and
# ConformanceRunner.kt's comment: finishAndRemoveTask() should already have
# prevented a relaunch, but the read must not depend on that holding on every
# OEM.
adbs shell am force-stop "$PKG" >/dev/null 2>&1 || true

echo
if [ -z "$DONE" ]; then
    echo "FATAL: run did not finish within ${RUN_TIMEOUT}s"
    adbs shell "run-as $PKG cat files/conformance.txt 2>/dev/null" || true
    adbs logcat -d -s CleonaVideo CleonaVideoConf AndroidRuntime | tail -60
    exit 2
fi

{ adbs shell "run-as $PKG cat files/conformance.txt" || true; } | tr -d '\r' \
    | tee "$BUILD/conformance.txt"
{ adbs shell "run-as $PKG cat files/conformance.json 2>/dev/null" || true; } | tr -d '\r' \
    > "$BUILD/conformance.json"

echo
echo "=== exit code: $DONE  (0 = conformant) ==="
echo "console : $BUILD/conformance.txt"
echo "json    : $BUILD/conformance.json"
sleep 1
kill "$LOGCAT_PID" 2>/dev/null || true
echo "--- backend log ---"
grep -E "CleonaVideo" "$BUILD/logcat.txt" | tr -d '\r' | tail -60 || true

if [ "$KEEP" != "true" ]; then
    adbs uninstall "$PKG" >/dev/null 2>&1 || true
fi

exit "$DONE"
