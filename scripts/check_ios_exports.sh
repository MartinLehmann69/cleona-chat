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
EXCLUDE_PATTERN="native_tray\.dart|native_tray_windows\.dart|native_udp_sender\.dart|android_udp_sender\.dart|dpapi_ffi\.dart"

# Symbols this gate deliberately does NOT require in the exports file.
# Currently empty, and the bar for adding one is high.
#
# THE RULE: a `providesSymbol()` guard in Dart is NOT a reason for an entry
# here. The guard only means the app SURVIVES the symbol being absent — it
# says nothing about the absence being intended. Counter-example that must
# stay outside this list: `whisper_free_params` is guarded exactly the same
# way, is correctly listed (cleona_exported_symbols.txt:82), and is therefore
# checked like every other symbol. The only legitimate entry would be a
# symbol that genuinely cannot exist in the iOS image (e.g. a Win32 or
# GTK/V4L2 entry point) — and those are already handled one level up by
# EXCLUDE_PATTERN, which drops whole platform-specific Dart files.
#
# HISTORY: whisper_params_set_language and whisper_params_set_n_threads sat
# here until S290, claiming to be "desktop-only". That was wrong from
# 99942e72 (2026-07-28) onwards: build_whisper_wrapper() in
# scripts/build-ios-libs.sh:415 compiles native/whisper_wrapper.c with the iOS
# toolchain and fail-closed verifies both setters via `nm -g` before
# installing libwhisper_wrapper.a into whisper/lib (which is on the static
# merge subdir list). Both setters ARE in the iOS image and ARE dead-strip
# roots (cleona_exported_symbols.txt:83-84). 99942e72 fixed the
# "Undefined symbol: _whisper_params_set_language" link error by BUILDING them
# for iOS — not by removing them from the image; the comment that used to
# stand here preserved the old misdiagnosis as if it were the intent.
#
# WHY THAT MATTERED: the exception made this gate silent for precisely the
# change it exists to catch. Deleting lines 83-84 from the exports file would
# dead-strip both setters; whisper_ffi.dart:277-292 would then see
# providesSymbol() == false and fall back, silently, to Dart-side struct-offset
# arithmetic — the very failure class the wrapper exists to eliminate. A wrong
# offset produces a wrong transcription language, not an error.
# The opposite direction ("listed but not built") is covered by
# scripts/preflight.sh Check 12 part B; "looked up by Dart but not listed" is
# THIS gate, and nothing may be exempt from it without a hard reason.
OPTIONAL_SYMBOLS=()

# Collect all FFI symbols from Dart code that runs on iOS.
SYMBOLS=$(grep -rA1 "lookupFunction\|\.lookup<" "$LIB_DIR" --include="*.dart" \
  | grep -vE "$EXCLUDE_PATTERN" \
  | grep -oE "'[a-zA-Z_][a-zA-Z0-9_]*'" \
  | tr -d "'" \
  | sort -u)

TOTAL=0
MISSING=()
for sym in $SYMBOLS; do
  # Optional, guarded lookups are not expected in the iOS image.
  # The ${a[@]+"${a[@]}"} form is required: `set -u` is active (line 11) and an
  # empty array expanded as "${a[@]}" is an unbound variable under bash < 4.4 —
  # this script runs on the macOS CI runner, which ships bash 3.2.
  skip=0
  for opt in ${OPTIONAL_SYMBOLS[@]+"${OPTIONAL_SYMBOLS[@]}"}; do
    [[ "$sym" == "$opt" ]] && skip=1 && break
  done
  [[ $skip -eq 1 ]] && continue

  TOTAL=$((TOTAL + 1))

  # Check exact match
  if grep -q "^_${sym}$" "$EXPORTS"; then
    continue
  fi

  # Check wildcard match (e.g. _cleona_voice_* matches _cleona_voice_open)
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
