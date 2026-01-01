#!/usr/bin/env bash
# Cleona Release Signing Script
# Signs Linux release bundles with GPG and generates SHA-256 checksums.
#
# Usage: ./scripts/sign-release.sh [bundle-dir]
#   bundle-dir: Path to the Flutter Linux bundle (default: build/linux/x64/release/bundle)
#
# Prerequisites:
#   - GPG key for signing (gpg --gen-key if needed)
#   - Flutter Linux build completed (flutter build linux --release)

set -euo pipefail

BUNDLE_DIR="${1:-build/linux/x64/release/bundle}"
VERSION=$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}')
ARCHIVE="cleona-linux-${VERSION}.tar.gz"
CHECKSUMS="cleona-linux-${VERSION}.sha256"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Bundle directory not found: $BUNDLE_DIR"
    echo "Run 'flutter build linux --release' first."
    exit 1
fi

echo "=== Cleona Release Signing ==="
echo "Version: $VERSION"
echo "Bundle:  $BUNDLE_DIR"
echo ""

# Step 1: Create tarball
echo "[1/3] Creating archive..."
tar -czf "$ARCHIVE" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")"
echo "  → $ARCHIVE"

# Step 2: Generate SHA-256 checksums
echo "[2/3] Generating checksums..."
sha256sum "$ARCHIVE" > "$CHECKSUMS"
# Also checksum individual binaries
find "$BUNDLE_DIR" -type f -executable | while read -r f; do
    sha256sum "$f" >> "$CHECKSUMS"
done
echo "  → $CHECKSUMS"

# Step 3: GPG sign
echo "[3/3] GPG signing..."
if gpg --list-secret-keys 2>/dev/null | grep -q 'sec'; then
    gpg --armor --detach-sign "$ARCHIVE"
    gpg --armor --detach-sign "$CHECKSUMS"
    echo "  → ${ARCHIVE}.asc"
    echo "  → ${CHECKSUMS}.asc"
else
    echo "  ⚠ No GPG key found. Skipping GPG signature."
    echo "  Run 'gpg --gen-key' to create a signing key."
fi

echo ""
echo "=== Release artifacts ==="
ls -la "$ARCHIVE"* "$CHECKSUMS"* 2>/dev/null
echo ""
echo "Done. Upload these files to the release page."
