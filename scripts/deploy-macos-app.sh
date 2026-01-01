#!/bin/bash
###############################################################################
# deploy-macos-app.sh — Assemble a ready-to-run Cleona.app bundle
#
# Runs the full macOS build pipeline:
#   1. Compile the daemon (dart compile exe)
#   2. Build the Flutter GUI (flutter build macos)
#   3. Copy native dylibs from build/macos-libs/<arch>/ into
#      Cleona.app/Contents/Frameworks/
#   4. Drop the daemon binary next to the GUI in Contents/MacOS/
#   5. Ad-hoc sign everything so Gatekeeper lets it run locally
#
# Prerequisite: run ./scripts/build-macos-libs.sh first so the dylibs exist.
#
# Usage:
#   ./scripts/deploy-macos-app.sh                   # arm64 Release
#   ./scripts/deploy-macos-app.sh --arch x86_64     # Intel
#   ./scripts/deploy-macos-app.sh --arch universal  # Universal
#   ./scripts/deploy-macos-app.sh --debug           # Debug build instead
###############################################################################
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script must run on macOS."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCH="arm64"
MODE="release"
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --debug) MODE="debug"; shift ;;
        --release) MODE="release"; shift ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

LIBS_DIR="$PROJECT_DIR/build/macos-libs/$ARCH"
if [ ! -d "$LIBS_DIR" ] || ! ls "$LIBS_DIR"/*.dylib >/dev/null 2>&1; then
    echo "!! No dylibs in $LIBS_DIR."
    echo "   Run first: ./scripts/build-macos-libs.sh --arch $ARCH"
    exit 1
fi

cd "$PROJECT_DIR"

# ── 1. Build daemon ──────────────────────────────────────────────────────────
#
# S367 — `dart build cli`, NOT `dart compile exe`.
#
# Since the store (§21.4.1) depends on a code asset,
# `dart compile exe` no longer holds: it runs NO build hooks. The
# Dart docs say the command should then fail; measured, it does
# not — it silently produces a binary WITHOUT `libsqlite3`. The daemon
# starts with it, fails when opening the store and ends with EXIT 0:
# for the UI indistinguishable from "running, just not opening a
# socket".
#
# `dart build cli` puts the library into `bundle/lib/` and embeds its
# path as `../lib/libsqlite3.dylib`, RELATIVE TO THE EXECUTABLE.
# Therefore the daemon below lands in `Contents/MacOS/bin/` and the
# library in `Contents/MacOS/lib/` — not in `Contents/Frameworks/`,
# which applies to the other dylibs.
echo ">>> Building cleona-daemon (dart build cli)"
mkdir -p build
rm -rf build/.daemon-cli
dart build cli --target bin/cleona_daemon.dart --output build/.daemon-cli

# ── 2. Flutter build macOS ───────────────────────────────────────────────────
echo ">>> Building Flutter macOS ($MODE)"
if [ "$MODE" = "release" ]; then
    flutter build macos --release
    APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Release/Cleona.app"
else
    flutter build macos --debug
    APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Debug/Cleona.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "!! Expected app at $APP_PATH — not found."
    exit 1
fi

FRAMEWORKS="$APP_PATH/Contents/Frameworks"
MACOS_BIN="$APP_PATH/Contents/MacOS"
mkdir -p "$FRAMEWORKS"

# ── 3. Copy dylibs into Frameworks/ ──────────────────────────────────────────
echo ">>> Copying dylibs into $FRAMEWORKS"
for f in "$LIBS_DIR"/*.dylib; do
    cp "$f" "$FRAMEWORKS/"
    echo "  + $(basename "$f")"
done

# ── 4. Install daemon in its own bin/, store library one level up ────────────
echo ">>> Installing cleona-daemon (Contents/MacOS/bin + Contents/MacOS/lib)"
mkdir -p "$MACOS_BIN/bin" "$MACOS_BIN/lib"
cp build/.daemon-cli/bundle/bin/cleona_daemon "$MACOS_BIN/bin/cleona-daemon"
chmod +x "$MACOS_BIN/bin/cleona-daemon"
cp build/.daemon-cli/bundle/lib/*.dylib "$MACOS_BIN/lib/" 2>/dev/null || true
# A leftover in the root would be worse than none: the GUI would find
# it (`_findDaemonBinary` knows the root as a fallback) and start
# a daemon that cannot open its store.
rm -f "$MACOS_BIN/cleona-daemon"

# Resolvability test: exactly the path that the binary uses.
"$PROJECT_DIR/scripts/check-daemon-lib-resolvable.sh" "$MACOS_BIN/bin/cleona-daemon" || {
    echo "!! The daemon does not find its storage library — abort."
    exit 1
}

# ── 5. Ad-hoc sign everything ────────────────────────────────────────────────
echo ">>> Ad-hoc signing dylibs + daemon"
for f in "$FRAMEWORKS"/*.dylib "$MACOS_BIN"/lib/*.dylib "$MACOS_BIN/bin/cleona-daemon"; do
    [ -e "$f" ] || continue
    codesign --force --sign - "$f" || true
done

echo ">>> Re-sealing the app bundle"
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "✓ App ready: $APP_PATH"
echo ""
echo "Launch:    open '$APP_PATH'"
echo "Console:   log stream --predicate 'subsystem == \"chat.cleona.cleona\"'"
