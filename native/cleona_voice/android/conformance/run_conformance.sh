#!/usr/bin/env bash
#
# run_conformance.sh — build and run the cleona_voice conformance harness on a
# real Android runtime. Work package V1.2, acceptance (SPEC §10 gate 4).
#
# WHY NOT THE PLAIN adb-shell BINARY
# ----------------------------------
# native/cleona_voice/test/CMakeLists.txt describes pushing the loader binary to
# /data/local/tmp. That is right for a backend that is pure native code. The
# Android backend is not: §10.4 makes the Java API mandatory, so it needs an ART
# runtime, an application Context for AudioManager and a real RECORD_AUDIO
# grant. An `adb shell` process has none of them. This script therefore packages
# the *unmodified* V0.4 harness sources into a small test APK and runs them
# there, which is the same environment production runs in.
#
# The harness itself is never copied or edited. It is compiled from
# CLEONA_VOICE_CONFORMANCE_SOURCES, the extension point V0.4 exports for exactly
# this purpose.
#
# VARIANTS — the negative controls
# --------------------------------
# A green run only means something if a broken backend comes out red. Every
# variant other than `default` patches a staged COPY of the sources; the
# repository tree is never modified.
#
#   default          the backend as it ships.
#   agc-not-started  AutomaticGainControl is created but never enabled — the
#                    historical defect (architecture §10.4, superseded-stack
#                    row 6: "AGC was never switched on at all"). The run must
#                    still be green, and the report must say `available_off`
#                    instead of quietly claiming `enabled`.
#                    CAVEAT: this control is INERT on any device where
#                    AutomaticGainControl.isAvailable() is false, because
#                    attachEffect() returns FX_UNAVAILABLE before it reaches the
#                    patched line. That is the case on both targets used so far
#                    (emulator API 35, Pixel 8 Pro API 37). Use ns-not-started
#                    to exercise the same code path where the effect exists.
#   ns-not-started   the same injection, applied to NoiseSuppressor — an effect
#                    that IS available on the Pixel 8 Pro. MEASURED RESULT: also
#                    inert, but for a different and more interesting reason. The
#                    platform auto-attaches and auto-ENABLES the pre-processing
#                    chain for a VOICE_COMMUNICATION capture session (the
#                    audio_effects.xml <preprocess> entry AudioDiagnostics.kt
#                    describes), so getEnabled() reads back true even when we
#                    never called setEnabled(true). The report is not lying —
#                    the effect really is running — but "not started by us" is
#                    indistinguishable from "started by us" on such a device.
#   ns-force-off     therefore the decisive control: setEnabled(FALSE) for NS.
#                    If the report merely echoed our intent it would still say
#                    `enabled`; reading back `available_off` is what proves the
#                    state is observed rather than asserted. The run stays
#                    CONFORMANT because available_off is a truthful state — the
#                    verdict lives in the report field, not in the exit code.
#   short-frame      the JNI facade copies two samples less than a frame. C3
#                    must fail, and with --expect-fail C3 the harness passes
#                    only if C3 is the ONLY failure.
#   mute-swap        set_output_muted stores the microphone's flag instead of
#                    its own argument — the "one shared mute flag for both
#                    directions" mistake conformance.c:606-608 names. C6b must
#                    fail. It is checked at the one moment the two flags hold
#                    DIFFERENT values (mic 0, output 1), because a swap between
#                    two equal values is invisible by construction.
#
# USAGE
#   run_conformance.sh [--serial S] [--variant V] [--expect-fail IDS]
#                      [--no-shipping] [--revoke-mic] [--keep]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PKG="chat.cleona.voiceconformance"
ACTIVITY="$PKG/chat.cleona.voiceconformance.ConformanceActivity"

SERIAL=""
VARIANT="default"
EXPECT_FAIL=""
SHIPPING="true"
REVOKE_MIC="false"
KEEP="false"
RUN_TIMEOUT=300

while [ $# -gt 0 ]; do
    case "$1" in
        --serial)      SERIAL="$2"; shift 2 ;;
        --variant)     VARIANT="$2"; shift 2 ;;   # see the variant list above
        --expect-fail) EXPECT_FAIL="$2"; shift 2 ;;
        --no-shipping) SHIPPING="false"; shift ;;
        --revoke-mic)  REVOKE_MIC="true"; shift ;;
        --keep)        KEEP="true"; shift ;;
        -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
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
# compiler and the stdlib can never be a mismatched pair.
KOTLIN_LIB_DIR="${KOTLIN_LIB_DIR:-$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-*/*/gradle-*/lib 2>/dev/null | sort -V | tail -1)}"
KOTLINC_JAR="$(ls "$KOTLIN_LIB_DIR"/kotlin-compiler-embeddable-*.jar 2>/dev/null | head -1 || true)"
KOTLIN_STDLIB="$(ls "$KOTLIN_LIB_DIR"/kotlin-stdlib-*.jar 2>/dev/null | head -1 || true)"

# kotlin-compiler-embeddable is itself compiled Kotlin and is NOT self-contained:
# it needs the stdlib, reflect, coroutines and trove4j on its own classpath.
# Only kotlin-stdlib ends up in the APK; the rest are compiler runtime only.
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

echo "=== cleona_voice conformance (V1.2) ==="
echo "device   : $SERIAL  $MODEL  API $API  $ABI"
echo "variant  : $VARIANT"
echo "shipping : $SHIPPING   expect-fail: '${EXPECT_FAIL:-none}'   revoke-mic: $REVOKE_MIC"
echo "ndk      : $NDK"
echo "kotlin   : $(basename "$KOTLINC_JAR")"
echo

BUILD="$REPO_ROOT/build/voice-android/$VARIANT"
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$STAGE/kotlin" "$BUILD/classes" "$BUILD/dex" "$BUILD/pack/lib/$ABI"

# ---------------------------------------------------------------------------
# Stage the sources. Patches are applied to this copy, never to the repository.
# ---------------------------------------------------------------------------
cp -a "$REPO_ROOT/native/cleona_voice" "$STAGE/cleona_voice"

# Drop the other platforms' backends from the STAGED COPY (never from the repo).
#
# native/cleona_voice/CMakeLists.txt adds linux/, android/, apple/ and windows/
# unconditionally, leaving each backend to disqualify itself on a foreign host.
# native/cleona_voice/android/CMakeLists.txt does that (`if(NOT ANDROID)
# return()`); native/cleona_voice/linux/CMakeLists.txt does not, so an Android
# cross-build descends into it, pkg-config happily finds the HOST libpipewire,
# and the configure dies on a target-name collision:
#
#   CMake Error at android/CMakeLists.txt:24 (add_library):
#     add_library cannot create target "cleona_voice" because another target
#     with the same name already exists.
#
# That is a defect in V1.1's file, requested there in BUILD_REQUEST_V1.2.md §5 —
# it breaks the build owner's Android path too, not just this script. Until it
# is fixed, an Android build has no business compiling a PipeWire backend, so
# the staged copy simply does not contain one.
for _plat in linux apple windows; do
    if [ -d "$STAGE/cleona_voice/$_plat" ]; then
        rm -rf "$STAGE/cleona_voice/$_plat"
        echo "staging  : dropped $_plat backend (BUILD_REQUEST_V1.2.md §5)"
    fi
done
cp "$REPO_ROOT/android/app/src/main/kotlin/chat/cleona/cleona/VoiceSession.kt" \
   "$STAGE/kotlin/VoiceSession.kt"
cp "$SCRIPT_DIR/runner/ConformanceRunner.kt" "$STAGE/kotlin/ConformanceRunner.kt"

# `sed -i` succeeds on a pattern that matches nothing, which would silently
# produce a "negative control" that sabotages nothing at all. Every patch is
# therefore verified to have changed the file.
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
    agc-not-started)
        patch_file "$STAGE/kotlin/VoiceSession.kt" \
            's|fx\.setEnabled(true)|if (name == "AGC") AudioEffect.SUCCESS else fx.setEnabled(true)|' \
            "AGC is created but never enabled" ;;
    ns-not-started)
        patch_file "$STAGE/kotlin/VoiceSession.kt" \
            's|fx\.setEnabled(true)|if (name == "NS") AudioEffect.SUCCESS else fx.setEnabled(true)|' \
            "NS is created but never enabled" ;;
    ns-force-off)
        patch_file "$STAGE/kotlin/VoiceSession.kt" \
            's|fx\.setEnabled(true)|if (name == "NS") fx.setEnabled(false) else fx.setEnabled(true)|' \
            "NS is explicitly switched OFF" ;;
    short-frame)
        patch_file "$STAGE/cleona_voice/android/cleona_voice_android.c" \
            's|memcpy(out, s->cap_addr, (size_t)s->fmt.frame_bytes);|memcpy(out, s->cap_addr, (size_t)s->fmt.frame_bytes - 4);|' \
            "capture_read copies two samples too few" ;;
    mute-swap)
        patch_file "$STAGE/kotlin/VoiceSession.kt" \
            's|^        outputMuted = muted$|        outputMuted = micMuted|' \
            "set_output_muted stores the microphone flag instead of its own" ;;
    *) echo "unknown variant: $VARIANT (default|agc-not-started|ns-not-started|ns-force-off|short-frame|mute-swap)" >&2
       exit 2 ;;
esac

# ---------------------------------------------------------------------------
# 1. Native
# ---------------------------------------------------------------------------
echo "--- building native ($ABI) ---"
cmake -S "$STAGE/cleona_voice" -B "$BUILD/cmake" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$ABI" \
      -DANDROID_PLATFORM=android-24 \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCLEONA_VOICE_BUILD_MOCK=OFF \
      -DCLEONA_VOICE_BUILD_SMOKE=OFF \
      -DCLEONA_VOICE_ANDROID_CONFORMANCE=ON \
      > "$BUILD/cmake-configure.log" 2>&1 \
  || { echo "FATAL: cmake configure failed"; tail -40 "$BUILD/cmake-configure.log"; exit 2; }

cmake --build "$BUILD/cmake" -j"$(nproc)" > "$BUILD/cmake-build.log" 2>&1 \
  || { echo "FATAL: cmake build failed"; tail -60 "$BUILD/cmake-build.log"; exit 2; }

SO_BACKEND="$(find "$BUILD/cmake" -name libcleona_voice.so | head -1)"
SO_HARNESS="$(find "$BUILD/cmake" -name libcleona_voice_conformance.so | head -1)"
[ -n "$SO_BACKEND" ] || { echo "FATAL: libcleona_voice.so not produced"; exit 2; }
[ -n "$SO_HARNESS" ] || { echo "FATAL: libcleona_voice_conformance.so not produced"; exit 2; }
cp "$SO_BACKEND" "$SO_HARNESS" "$BUILD/pack/lib/$ABI/"

# The twelve ABI entry points must really be exported, or the harness links
# against nothing and the Dart binding would fail the same way at runtime.
#
# llvm-nm is resolved into a variable first rather than globbed at the call
# site: a glob as a command name silently turns every additional match into an
# argument (shellcheck SC2211), which here would mean nm reading the wrong file
# and the export check passing for the wrong reason.
LLVM_NM="$(pick_newest "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-nm)"
if [ -z "$LLVM_NM" ] || [ ! -x "$LLVM_NM" ]; then
    echo "FATAL: llvm-nm not found under $NDK" >&2
    exit 2
fi

MISSING=""
for sym in open start stop close capture_read playback_write set_mic_muted \
           set_output_muted set_route get_routes poll_event get_report; do
    "$LLVM_NM" --dynamic --defined-only "$SO_BACKEND" 2>/dev/null \
        | grep -q " cleona_voice_$sym\$" \
        || MISSING="$MISSING cleona_voice_$sym"
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
# Uninstall unconditionally, then verify the install by CONTENT.
#
# This used to be `install -r` with its output discarded, and that is how the
# short-frame negative control first came back green: `adb install` prints
# "Failure [...]" but still exits 0 on this adb, so a failed replace went
# unnoticed and the run certified the APK that happened to be installed from the
# PREVIOUS run — a sabotaged backend reported as conformant. A test rig that can
# silently certify the wrong artefact is worth less than no test rig, so the
# check is now: fresh install, "Success" required, and the APK on the device
# must hash to the APK just built.
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

if [ "$REVOKE_MIC" = "true" ]; then
    adbs shell pm revoke "$PKG" android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
    echo "mic      : RECORD_AUDIO REVOKED (negative control)"
else
    adbs shell pm grant "$PKG" android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
    echo "mic      : RECORD_AUDIO granted"
fi

adbs shell am force-stop "$PKG" >/dev/null 2>&1 || true
adbs logcat -c >/dev/null 2>&1 || true

# Capture the backend's own log for the whole run. Reading it afterwards is not
# good enough: a device with a chatty GPU driver rotates the ring buffer within
# the ~40 s the run takes, and the verification-relevant lines (chosen rate,
# session id, per-effect setEnabled/getEnabled, audio-mode read-back) are gone
# by the time the harness finishes.
adbs logcat -v time -s CleonaVoice:V CleonaVoiceConf:V AndroidRuntime:E \
     > "$BUILD/logcat.txt" 2>/dev/null &
LOGCAT_PID=$!
trap 'kill "$LOGCAT_PID" 2>/dev/null || true' EXIT

echo "--- running ---"
# `adb shell` re-joins its arguments into one command line, so an empty string
# argument simply vanishes and `am` then reports "Argument expected after
# expectFail". The extra is therefore omitted entirely when it is empty; the
# activity defaults it to "".
AM_EXTRA=""
[ -n "$EXPECT_FAIL" ] && AM_EXTRA="--es expectFail $EXPECT_FAIL"
# shellcheck disable=SC2086
adbs shell am start -n "$ACTIVITY" --ez shipping "$SHIPPING" $AM_EXTRA >/dev/null

# `set -o pipefail` is on, and adb propagates the remote exit code, so the
# not-yet-there `cat` would abort the script instead of polling. Hence `|| true`.
DONE=""
for _ in $(seq 1 "$RUN_TIMEOUT"); do
    DONE="$( { adbs shell "run-as $PKG cat files/conformance.done 2>/dev/null" || true; } | tr -d '\r')"
    [ -n "$DONE" ] && break
    sleep 1
done

# Stop the app before reading its output. finishAndRemoveTask() in the runner
# should already have prevented a relaunch, but the read must not depend on that
# holding on every OEM: a restarted activity deletes conformance.txt in onCreate,
# and this is the exact window in which that would happen.
adbs shell am force-stop "$PKG" >/dev/null 2>&1 || true

echo
if [ -z "$DONE" ]; then
    echo "FATAL: run did not finish within ${RUN_TIMEOUT}s"
    adbs shell "run-as $PKG cat files/conformance.txt 2>/dev/null" || true
    adbs logcat -d -s CleonaVoice CleonaVoiceConf AndroidRuntime | tail -60
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
grep -E "CleonaVoice" "$BUILD/logcat.txt" | tr -d '\r' | tail -40 || true

if [ "$KEEP" != "true" ]; then
    adbs uninstall "$PKG" >/dev/null 2>&1 || true
fi

exit "$DONE"
