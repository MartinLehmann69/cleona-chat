#!/bin/bash
# Build the VP8 codec shim library (wraps libvpx for Dart FFI).
# Requires: gcc, libvpx (runtime only, no -dev package needed).
#
# Usage:
#   scripts/build-vpx-shim.sh          # Build for current platform
#   scripts/build-vpx-shim.sh --install # Build + copy to build output

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="native/vpx_shim.c"
OUT="native/libcleona_vpx.so"

echo "Building VP8 shim: $SRC → $OUT"
gcc -shared -fPIC -O2 -o "$OUT" "$SRC" -ldl

echo "OK: $(ls -lh "$OUT" | awk '{print $5}') — $(nm -D "$OUT" | grep -c ' T cleona_') exported symbols"

if [[ "${1:-}" == "--install" ]]; then
  BUNDLE="build/linux/x64/release/bundle/lib"
  if [[ -d "$BUNDLE" ]]; then
    cp "$OUT" "$BUNDLE/"
    echo "Installed to $BUNDLE/"
  else
    echo "Warning: $BUNDLE not found — run 'flutter build linux --release' first"
  fi
fi
