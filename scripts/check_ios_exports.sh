#!/usr/bin/env bash
# Quality gate: verifies every FFI symbol loaded via lookupFunction in Dart
# code is listed in the iOS exported symbols file.
# Without this, the iOS linker silently dead-strips unlisted symbols and the
# app crashes at runtime with "symbol not found" from dlsym().
#
# Usage: scripts/check_ios_exports.sh [--ci]
#   --ci  exit 1 on missing symbols (for CI / pre-commit)
#   default: prints warnings only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORTS="$REPO_ROOT/ios/CleonaNative/cleona_exported_symbols.txt"
LIB_DIR="$REPO_ROOT/lib"

CI_MODE=0
[[ "${1:-}" == "--ci" ]] && CI_MODE=1

if [[ ! -f "$EXPORTS" ]]; then
  echo "ERROR: exports file not found: $EXPORTS"
  exit 1
fi

# Files that contain platform-specific FFI bindings NOT relevant for iOS.
# These load Win32 APIs, Linux GTK/appindicator, V4L2, or Windows-only shims.
EXCLUDE_PATTERN="native_tray\.dart|native_tray_windows\.dart|native_udp_sender\.dart|video_capture_linux\.dart|dpapi_ffi\.dart"

# Collect all FFI symbols from Dart code that runs on iOS.
SYMBOLS=$(grep -rA1 "lookupFunction\|\.lookup<" "$LIB_DIR" --include="*.dart" \
  | grep -vE "$EXCLUDE_PATTERN" \
  | grep -oE "'[a-zA-Z_][a-zA-Z0-9_]*'" \
  | tr -d "'" \
  | sort -u)

TOTAL=0
MISSING=()
for sym in $SYMBOLS; do
  TOTAL=$((TOTAL + 1))

  # Check exact match
  if grep -q "^_${sym}$" "$EXPORTS"; then
    continue
  fi

  # Check wildcard match (e.g. _cleona_audio_* matches _cleona_audio_create)
  matched=0
  while IFS= read -r line; do
    prefix="${line%\*}"
    if [[ "_${sym}" == "${prefix}"* ]]; then
      matched=1
      break
    fi
  done < <(grep '\*$' "$EXPORTS" | grep -v '^#')

  if [[ $matched -eq 0 ]]; then
    MISSING+=("$sym")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "✓ All $TOTAL FFI symbols found in iOS exports file."
  exit 0
fi

echo "ERROR: ${#MISSING[@]} FFI symbol(s) missing from iOS exports file!"
echo ""
echo "  File: ios/CleonaNative/cleona_exported_symbols.txt"
echo ""
for sym in "${MISSING[@]}"; do
  echo "  MISSING: _${sym}"
done
echo ""
echo "Add the missing symbol(s) with underscore prefix to the exports file."
echo "Without this, iOS will silently dead-strip them and the app crashes."

if [[ $CI_MODE -eq 1 ]]; then
  exit 1
fi
