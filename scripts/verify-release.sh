#!/usr/bin/env bash
# verify-release.sh — verify a published Cleona release end to end.
#
# Checks the guarantees docs/PUBLISHING.md makes about a release:
#   [1] every artifact carries an Ed25519 signature that validates against
#       assets/cleona_maintainer_public.pem
#   [2] SHA256SUMS matches the artifacts on disk
#   [3] the update manifest agrees with SHA256SUMS and with real file sizes
#   [4] the in-network seeder serves every platform the manifest advertises
#
# WHY THIS EXISTS (S284). Until now the signature scheme lived only as a write
# operation inside release-build.sh; anyone verifying a release had to reverse
# engineer it. Two mistakes followed directly from that during the v3.1.159-beta
# run: the artifacts were "verified" against the file instead of its digest
# (every artifact reported a failure that did not exist), and the seeder was
# probed on the wrong port (every platform reported HTTP 000). Both are
# structural, not attentional — so the knowledge lives in one runnable place now.
#
# SIGNATURE FORMAT — mirrors sign_artifact() in release-build.sh:
#   Ed25519 over the SHA-256 *digest* of the file, base64-encoded.
#   Verifying the file itself fails for every artifact. Correct sequence:
#     openssl dgst -sha256 -binary FILE > digest
#     base64 -d FILE.sig               > sig
#     openssl pkeyutl -verify -pubin -inkey PUBKEY -rawin -in digest -sigfile sig
#
# SEEDER PORT — derived from the channel, never guessed:
#   beta -> 8081, live -> 8080.
#
# No private key required: verification needs the public key only, which ships
# with the app. That is the point of docs/PUBLISHING.md §10.
#
# Usage:
#   scripts/verify-release.sh 3.1.159-beta
#   scripts/verify-release.sh 3.1.159 --channel beta
#   scripts/verify-release.sh 3.1.159-beta --release-dir /path/to/release
#   CLEONA_BOOTSTRAP_HOST=host.example scripts/verify-release.sh 3.1.159-beta
#
# The seeder checks are skipped unless a host is given via --bootstrap or
# CLEONA_BOOTSTRAP_HOST; they need network access to a node that seeds the
# release. Everything else works offline against a downloaded release.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PUBKEY="${CLEONA_MAINTAINER_PUBKEY:-$PROJECT_DIR/assets/cleona_maintainer_public.pem}"
RELEASE_DIR=""
CHANNEL=""
BOOTSTRAP_HOST="${CLEONA_BOOTSTRAP_HOST:-}"
BOOTSTRAP_USER="${CLEONA_BOOTSTRAP_USER:-cleona}"
SSH_KEY="${CLEONA_SSH_KEY:-$HOME/.ssh/id_ed25519_cleona}"
VERSION_ARG=""

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

FAILURES=0
CHECKS=0

ok()   { CHECKS=$((CHECKS + 1)); echo "  ${GREEN}OK${NC}    $*"; }
bad()  { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); echo "  ${RED}FAIL${NC}  $*"; }
warn() { echo "  ${YELLOW}WARN${NC}  $*"; }
info() { echo "${BLUE}[verify]${NC} $*"; }
phase(){ echo ""; echo "${CYAN}$*${NC}"; }

usage() {
  sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit "${1:-1}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)     CHANNEL="$2"; shift 2 ;;
    --release-dir) RELEASE_DIR="$2"; shift 2 ;;
    --bootstrap)   BOOTSTRAP_HOST="$2"; shift 2 ;;
    --pubkey)      PUBKEY="$2"; shift 2 ;;
    -h|--help)     usage 0 ;;
    -*)            echo "Unknown option: $1" >&2; usage 1 ;;
    *)             VERSION_ARG="$1"; shift ;;
  esac
done

[ -n "$VERSION_ARG" ] || usage 1

# Accept both "3.1.159" and "3.1.159-beta". VERSION_NUM is the bare number —
# the Linux package formats carry only that, without the channel suffix.
VERSION_NUM="${VERSION_ARG%%-*}"
if [ -z "$CHANNEL" ]; then
  case "$VERSION_ARG" in
    *-beta) CHANNEL="beta" ;;
    *-rc*)  CHANNEL="beta" ;;
    *)      CHANNEL="live" ;;
  esac
fi
RELEASE_VER="$VERSION_NUM"
[ "$CHANNEL" = "beta" ] && RELEASE_VER="${VERSION_NUM}-beta"

case "$CHANNEL" in
  beta) SEEDER_PORT=8081 ;;
  live) SEEDER_PORT=8080 ;;
  *)    echo "Unknown channel '$CHANNEL' (expected beta or live)" >&2; exit 1 ;;
esac

[ -n "$RELEASE_DIR" ] || RELEASE_DIR="$HOME/CleonaGit/release"

echo "═══════════════════════════════════════════════════════════"
echo "  Cleona Release Verification — $RELEASE_VER"
echo "═══════════════════════════════════════════════════════════"
info "Release dir: $RELEASE_DIR"
info "Public key:  $PUBKEY"
info "Channel:     $CHANNEL (seeder port $SEEDER_PORT)"

for tool in openssl sha256sum base64 find; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool" >&2; exit 1; }
done
[ -d "$RELEASE_DIR" ] || { echo "Release dir not found: $RELEASE_DIR" >&2; exit 1; }
[ -f "$PUBKEY" ]      || { echo "Public key not found: $PUBKEY" >&2; exit 1; }

cd "$RELEASE_DIR" || exit 1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Match both naming schemes: "*<version>-<channel>*" for the platform bundles
# and "*<version>*" for the Linux package formats, which carry no channel
# suffix. Missing the second pattern is what kept .deb/.rpm/.AppImage out of
# every release until S280 — and out of the signing loop until S284.
#
# Deliberately NO extension allow-list. An earlier version of this script
# carried the same nine-extension list as the signing loop in release-build.sh
# and would therefore have been blind to exactly the case it exists to catch:
# a new artifact format that the upload ships automatically but the signer does
# not know about. Everything that matches the version must be signed; only
# signatures, the hash manifest and the update manifest are exempt.
mapfile -t ARTIFACTS < <(find . -maxdepth 1 -type f \
  \( -name "*${RELEASE_VER}*" -o -name "*${VERSION_NUM}*" \) \
  ! -name '*.sig' ! -name '*SHA256SUMS' ! -name 'update-manifest-*.json' \
  -printf '%f\n' | sort -u)

CHECKSUMS_FILE="cleona-chat_${RELEASE_VER}_SHA256SUMS"
MANIFEST_FILE="update-manifest-${RELEASE_VER}.json"

# ─── [1] Signatures ─────────────────────────────────────────────────────────
phase "[1/4] Ed25519 signatures"

verify_sig() {
  # verify_sig FILE -> 0 when the signature validates
  local f="$1"
  [ -f "$f.sig" ] || return 2
  openssl dgst -sha256 -binary "$f" > "$TMP/digest" 2>/dev/null || return 3
  base64 -d "$f.sig" > "$TMP/sig" 2>/dev/null || return 4
  openssl pkeyutl -verify -pubin -inkey "$PUBKEY" \
    -rawin -in "$TMP/digest" -sigfile "$TMP/sig" >/dev/null 2>&1
}

if [ "${#ARTIFACTS[@]}" -eq 0 ]; then
  bad "no artifacts for $RELEASE_VER found in $RELEASE_DIR"
else
  for f in "${ARTIFACTS[@]}" "$CHECKSUMS_FILE"; do
    [ -f "$f" ] || continue
    verify_sig "$f"
    case $? in
      0) ok   "$f" ;;
      2) bad  "$f — no .sig present (shipped unsigned)" ;;
      *) bad  "$f — signature invalid" ;;
    esac
  done
fi

# ─── [2] SHA256SUMS ─────────────────────────────────────────────────────────
phase "[2/4] SHA256SUMS"

if [ ! -f "$CHECKSUMS_FILE" ]; then
  bad "$CHECKSUMS_FILE missing"
else
  if sha256sum -c "$CHECKSUMS_FILE" >"$TMP/sums" 2>&1; then
    ok "$(grep -c ':' "$TMP/sums") artifacts, all hashes match"
  else
    bad "hash mismatch:"
    grep -v ': OK$' "$TMP/sums" | sed 's/^/          /'
  fi
  # Every artifact that shipped must also be covered by the hash manifest.
  for f in "${ARTIFACTS[@]}"; do
    grep -qF "  $f" "$CHECKSUMS_FILE" || bad "$f not listed in $CHECKSUMS_FILE"
  done
fi

# ─── [3] Update manifest ────────────────────────────────────────────────────
phase "[3/4] Update manifest"

MANIFEST_PLATFORMS=""
if [ ! -f "$MANIFEST_FILE" ]; then
  warn "$MANIFEST_FILE not in release dir — manifest checks skipped"
else
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 missing — manifest checks skipped"
  else
    MV=$(python3 -c "import json;print(json.load(open('$MANIFEST_FILE')).get('v','?'))")
    if [ "$MV" = "$VERSION_NUM" ]; then
      ok "manifest version $MV"
    else
      bad "manifest version $MV, expected $VERSION_NUM"
    fi

    MANIFEST_PLATFORMS=$(python3 -c "
import json; m=json.load(open('$MANIFEST_FILE'))
print(' '.join(sorted(m.get('binHash',{}).keys())))")
    [ -n "$MANIFEST_PLATFORMS" ] \
      && ok "platforms in manifest: $MANIFEST_PLATFORMS" \
      || bad "manifest lists no platforms (binHash empty)"

    # dhtBinaryTag is mandatory: without it clients never learn about the
    # update and the whole seeding effort is wasted (docs/PUBLISHING.md §6.3).
    for p in $MANIFEST_PLATFORMS; do
      TAG=$(python3 -c "
import json;print(json.load(open('$MANIFEST_FILE')).get('dhtBin',{}).get('$p',''))")
      [ -n "$TAG" ] && ok "dhtBinaryTag set: $p" \
                    || bad "dhtBinaryTag missing: $p — update will not be offered"
    done

    # binHash must equal the hash of the artifact that actually shipped.
    for p in $MANIFEST_PLATFORMS; do
      MH=$(python3 -c "
import json;print(json.load(open('$MANIFEST_FILE')).get('binHash',{}).get('$p',''))")
      MS=$(python3 -c "
import json;print(json.load(open('$MANIFEST_FILE')).get('binSize',{}).get('$p',''))")
      HIT=$(grep -i "^$MH  " "$CHECKSUMS_FILE" 2>/dev/null | head -1 | sed 's/^[^ ]*  //')
      if [ -n "$HIT" ]; then
        ok "binHash $p matches $HIT"
        ACTUAL=$(stat -c %s "$HIT" 2>/dev/null || echo "")
        if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "$MS" ]; then
          bad "binSize $p = $MS, file is $ACTUAL B"
        fi
      else
        bad "binHash $p ($MH) matches no SHA256SUMS entry"
      fi
    done
  fi
fi

# ─── [4] Seeder ─────────────────────────────────────────────────────────────
phase "[4/4] In-network seeder"

if [ -z "$BOOTSTRAP_HOST" ]; then
  warn "no seeder host (--bootstrap or CLEONA_BOOTSTRAP_HOST) — skipped"
elif [ -z "$MANIFEST_PLATFORMS" ]; then
  warn "no manifest platforms known — seeder checks skipped"
else
  info "Seeder: ${BOOTSTRAP_USER}@${BOOTSTRAP_HOST}:${SEEDER_PORT}"
  # Every platform the manifest advertises, not just the first one. A manifest
  # that promises a download nobody serves is the S227 failure mode.
  for p in $MANIFEST_PLATFORMS; do
    EXPECTED=$(python3 -c "
import json;print(json.load(open('$MANIFEST_FILE')).get('binSize',{}).get('$p',''))")
    GOT=$(timeout 60 ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 \
          "${BOOTSTRAP_USER}@${BOOTSTRAP_HOST}" \
          "curl -s --max-time 30 -o /dev/null -w '%{http_code}:%{size_download}' \
           http://127.0.0.1:${SEEDER_PORT}/cleona/binary/$p" 2>/dev/null)
    CODE="${GOT%%:*}"; SIZE="${GOT##*:}"
    if [ "$CODE" = "200" ] && [ "$SIZE" = "$EXPECTED" ]; then
      ok "$p — HTTP 200, $SIZE B (matches manifest)"
    else
      bad "$p — HTTP ${CODE:-000}, $SIZE B, manifest expects $EXPECTED B"
    fi
  done
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
if [ "$FAILURES" -eq 0 ]; then
  echo "  ${GREEN}VERIFICATION OK${NC} — $CHECKS checks, 0 failures"
  echo "═══════════════════════════════════════════════════════════"
  exit 0
else
  echo "  ${RED}VERIFICATION FAILED${NC} — $FAILURES of $CHECKS checks"
  echo "═══════════════════════════════════════════════════════════"
  exit 1
fi
