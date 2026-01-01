#!/usr/bin/env bash
# Sign a Cleona update manifest with the maintainer Ed25519 key.
#
# Usage:
#   ./scripts/sign-update-manifest.sh <version> <download-url> <archive-hash> <changelog> [<min-required-version> <min-required-reason>]
#
# Example (legacy, no hard-block):
#   ./scripts/sign-update-manifest.sh "3.1.71" "https://github.com/.../cleona-linux.tar.gz" \
#     "abc123..." "Test release"
#
# Example (V3.1.72+ with hard-block):
#   ./scripts/sign-update-manifest.sh "3.1.72" "https://github.com/.../cleona-linux.tar.gz" \
#     "abc123..." "KEM v2 cutover" "3.1.72" "update_required_kem_v2"
#
# Prerequisites:
#   - Maintainer private key at ~/Schreibtisch/cleona_maintainer_private.pem (or CLEONA_MAINTAINER_KEY env)

set -euo pipefail

PRIVATE_KEY="${CLEONA_MAINTAINER_KEY:-$HOME/Schreibtisch/cleona_maintainer_private.pem}"

if [ $# -lt 4 ]; then
    echo "Usage: $0 <version> <download-url> <archive-hash> <changelog> [<min-required-version> <min-required-reason>]"
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
MIN_REQ="${5:-}"
MIN_REQ_REASON="${6:-}"
TIMESTAMP=$(date +%s)

# Build payload — legacy format if both new fields empty
if [ -z "$MIN_REQ" ] && [ -z "$MIN_REQ_REASON" ]; then
    PAYLOAD="${VERSION}\n${URL}\n${HASH}\n${CHANGELOG}\n${TIMESTAMP}"
else
    PAYLOAD="${VERSION}\n${URL}\n${HASH}\n${CHANGELOG}\n${TIMESTAMP}\n${MIN_REQ}\n${MIN_REQ_REASON}"
fi

# Sign with Ed25519
SIGNATURE=$(printf '%b' "$PAYLOAD" | openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -rawin | base64 -w0)

# Build JSON output
if [ -z "$MIN_REQ" ] && [ -z "$MIN_REQ_REASON" ]; then
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
else
    cat <<EOF
{
  "v": "$VERSION",
  "url": "$URL",
  "hash": "$HASH",
  "log": "$CHANGELOG",
  "ts": $TIMESTAMP,
  "sig": "$SIGNATURE",
  "minReq": "$MIN_REQ",
  "minReqReason": "$MIN_REQ_REASON"
}
EOF
fi

echo ""
echo "Manifest created. Publish to DHT with key SHA-256('cleona-update-manifest')."
