#!/usr/bin/env bash
# Sign a Cleona update manifest with the maintainer Ed25519 key.
#
# Usage: ./scripts/sign-update-manifest.sh <version> <download-url> <archive-hash> <changelog>
#
# Example:
#   ./scripts/sign-update-manifest.sh "1.0.0" "https://github.com/cleona/releases/v1.0.0/cleona-linux.tar.gz" \
#     "abc123..." "First public release"
#
# Prerequisites:
#   - Maintainer private key at ~/Schreibtisch/cleona_maintainer_private.pem

set -euo pipefail

PRIVATE_KEY="${CLEONA_MAINTAINER_KEY:-$HOME/Schreibtisch/cleona_maintainer_private.pem}"

if [ $# -lt 4 ]; then
    echo "Usage: $0 <version> <download-url> <archive-hash> <changelog>"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Maintainer private key not found at: $PRIVATE_KEY"
    echo "Set CLEONA_MAINTAINER_KEY env var or place key at ~/Schreibtisch/cleona_maintainer_private.pem"
    exit 1
fi

VERSION="$1"
URL="$2"
HASH="$3"
CHANGELOG="$4"
TIMESTAMP=$(date +%s)

# Payload to sign
PAYLOAD="${VERSION}\n${URL}\n${HASH}\n${CHANGELOG}\n${TIMESTAMP}"

# Sign with Ed25519
SIGNATURE=$(printf '%b' "$PAYLOAD" | openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -rawin | base64 -w0)

# Output JSON manifest
cat <<EOF
{
  "v": "$VERSION",
  "url": "$URL",
  "hash": "$HASH",
  "log": "$CHANGELOG",
  "ts": $TIMESTAMP,
  "sig": "$SIGNATURE"
}
EOF

echo ""
echo "Manifest created. Publish to DHT with key SHA-256('cleona-update-manifest')."
