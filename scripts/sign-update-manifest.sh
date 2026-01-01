#!/usr/bin/env bash
# Sign a Cleona update manifest with the maintainer Ed25519 key.
#
# Usage:
#   ./scripts/sign-update-manifest.sh <version> <download-url> <archive-hash> <changelog> \
#       [<min-required-version> <min-required-reason>] \
#       [--bin-dir DIR] [--dht-tag TAG | --dht-tag PLATFORM=TAG ...] [--mono-seq N]
#
# Example (legacy, no hard-block):
#   ./scripts/sign-update-manifest.sh "3.1.71" "https://github.com/.../cleona-linux.tar.gz" \
#     "abc123..." "Test release"
#
# Example (V3.1.72+ with hard-block):
#   ./scripts/sign-update-manifest.sh "3.1.72" "https://github.com/.../cleona-linux.tar.gz" \
#     "abc123..." "KEM v2 cutover" "3.1.72" "update_required_kem_v2"
#
# Example (§19.6 in-network distribution — per-platform binary hash/sig/size + DHT tags):
#   ./scripts/sign-update-manifest.sh "3.1.125" "https://github.com/.../cleona-linux.tar.gz" \
#     "abc123..." "Censorship-resistant distribution" "" "" \
#     --bin-dir ./release-binaries/ \
#     --dht-tag linux=aa11bb22... --dht-tag android=cc33dd44... \
#     --mono-seq 42
#
# New flags (§19.6.2 — Cleona_Chat_Architecture_v3_0.md §19.6):
#   --bin-dir DIR     Directory containing platform binaries named
#                      cleona-linux, cleona-android, cleona-windows, cleona-macos, cleona-ios.
#                      For every binary found: computes its SHA-256 hash, its byte size, and
#                      an Ed25519 signature (maintainer key) over the raw 32-byte hash — the
#                      same trust anchor verified by BinaryUpdateManager.verify() /
#                      PhysicalTransferHelper.importAndVerifyBinary() on the receiving node.
#                      Populates the manifest's binHash / binSig / binSize maps.
#   --dht-tag TAG              Apply TAG to every platform found via --bin-dir (only makes
#                               sense with a single-platform --bin-dir; see below).
#   --dht-tag PLATFORM=TAG     Set the DHT binary tag for one specific platform. Repeatable.
#                               Per §19.6.5 the tag is HKDF-derived per platform from the
#                               network secret — with more than one platform in --bin-dir,
#                               each platform needs its own tag via this form.
#   --mono-seq N      Monotonically increasing sequence number (downgrade protection,
#                      §19.6.2). Nodes reject any manifest whose minMonotoneSeq is not
#                      strictly greater than the highest previously-seen value.
#
# Prerequisites:
#   - Maintainer private key at ~/Schreibtisch/cleona_maintainer_private.pem (or CLEONA_MAINTAINER_KEY env)
#
# After signing a manifest with --bin-dir, distribute the binaries into the network with:
#   scripts/publish-in-network-update.sh --manifest <manifest.json> --bin-dir <DIR>

set -euo pipefail

PRIVATE_KEY="${CLEONA_MAINTAINER_KEY:-$HOME/Schreibtisch/cleona_maintainer_private.pem}"

# Platforms supported by §19.6.2 in-network distribution, in the fixed order
# used everywhere below (JSON map key order). Must stay stable — the signed
# payload embeds these maps as compact JSON and the receiver's verification
# re-serializes the decoded map in the same order it appeared in the manifest.
PLATFORMS=(linux android windows macos ios)

usage() {
    echo "Usage: $0 <version> <download-url> <archive-hash> <changelog> [<min-required-version> <min-required-reason>] [--bin-dir DIR] [--dht-tag TAG|PLATFORM=TAG] [--mono-seq N]" >&2
    exit 1
}

# Bash's `set -u` throws "unbound variable" for `${#assoc_array[@]}` when the
# array is declared but empty (long-standing behavior across bash versions).
# Use this instead of `${#ARR[@]}` for associative arrays that may be empty.
assoc_nonempty() {
    local -n _ref="$1"
    [[ -n "${_ref[*]-}" ]]
}

# OpenSSL 3.x's `pkeyutl -sign -rawin` needs a seekable input to determine
# the oneshot buffer size — piping data in via stdin fails with
# "unable to determine file size for oneshot operation". Sign via a temp
# file instead. Prints the base64 signature to stdout.
SIGN_TMPDIR=$(mktemp -d)
trap 'rm -rf "$SIGN_TMPDIR"' EXIT
ed25519_sign_stdin() {
    local tmp="$SIGN_TMPDIR/sign-input-$$-$RANDOM"
    cat > "$tmp"
    openssl pkeyutl -sign -inkey "$PRIVATE_KEY" -rawin -in "$tmp" | base64 -w0
    rm -f "$tmp"
}

# --- Argument parsing: pull out flags, leave positional args in place ---
BIN_DIR=""
MONO_SEQ=""
DHT_TAG_GLOBAL=""
declare -A DHT_TAGS
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --bin-dir)
            [ $# -ge 2 ] || usage
            BIN_DIR="$2"
            shift 2
            ;;
        --dht-tag)
            [ $# -ge 2 ] || usage
            if [[ "$2" == *"="* ]]; then
                DHT_TAGS["${2%%=*}"]="${2#*=}"
            else
                DHT_TAG_GLOBAL="$2"
            fi
            shift 2
            ;;
        --mono-seq)
            [ $# -ge 2 ] || usage
            MONO_SEQ="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

if [ $# -lt 4 ]; then
    usage
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

# --- §19.6.2: per-platform binary hash + signature + size ---
declare -A BIN_HASH BIN_SIG BIN_SIZE
BIN_HASH_JSON=""
BIN_SIG_JSON=""
BIN_SIZE_JSON=""

if [ -n "$BIN_DIR" ]; then
    if [ ! -d "$BIN_DIR" ]; then
        echo "Error: --bin-dir directory not found: $BIN_DIR" >&2
        exit 1
    fi
    echo "Hashing + signing platform binaries in $BIN_DIR ..." >&2
    for PLATFORM in "${PLATFORMS[@]}"; do
        BIN_FILE="$BIN_DIR/cleona-$PLATFORM"
        [ -f "$BIN_FILE" ] || continue

        REAL_FILE=$(realpath "$BIN_FILE")
        HASH_HEX=$(openssl dgst -sha256 "$REAL_FILE" | awk '{print $NF}')
        SIZE=$(stat -c%s "$REAL_FILE" 2>/dev/null || stat -f%z "$REAL_FILE")
        # Sign the RAW 32-byte SHA-256 digest (not the hex string) — this is
        # the exact scheme BinaryUpdateManager.verify() and
        # PhysicalTransferHelper.importAndVerifyBinary() check against on the
        # receiving node (SodiumFFI().sha256() returns raw bytes, and
        # verifyEd25519() is called with those raw bytes as the message).
        SIG_B64=$(openssl dgst -sha256 -binary "$REAL_FILE" | ed25519_sign_stdin)

        BIN_HASH["$PLATFORM"]="$HASH_HEX"
        BIN_SIG["$PLATFORM"]="$SIG_B64"
        BIN_SIZE["$PLATFORM"]="$SIZE"
        echo "  [$PLATFORM] $BIN_FILE -> hash=$HASH_HEX size=${SIZE}B" >&2
    done

    if ! assoc_nonempty BIN_HASH; then
        echo "Error: no cleona-{${PLATFORMS[*]// /,}} binaries found in $BIN_DIR" >&2
        exit 1
    fi

    # Build compact JSON maps (fixed platform order, no whitespace) — must
    # byte-for-byte match Dart's jsonEncode(Map) output, because the signed
    # payload embeds these strings directly and the receiver re-derives the
    # same payload from the decoded manifest to verify the signature.
    BH="{"; BS="{"; BZ="{"
    FIRST=1
    for PLATFORM in "${PLATFORMS[@]}"; do
        [ -n "${BIN_HASH[$PLATFORM]:-}" ] || continue
        if [ "$FIRST" -eq 0 ]; then
            BH+=","; BS+=","; BZ+=","
        fi
        FIRST=0
        BH+="\"$PLATFORM\":\"${BIN_HASH[$PLATFORM]}\""
        BS+="\"$PLATFORM\":\"${BIN_SIG[$PLATFORM]}\""
        BZ+="\"$PLATFORM\":${BIN_SIZE[$PLATFORM]}"
    done
    BH+="}"; BS+="}"; BZ+="}"
    BIN_HASH_JSON="$BH"
    BIN_SIG_JSON="$BS"
    BIN_SIZE_JSON="$BZ"
fi

# --- §19.6.2: per-platform DHT binary tag ---
DHT_BIN_JSON=""
if assoc_nonempty DHT_TAGS || [ -n "$DHT_TAG_GLOBAL" ]; then
    if ! assoc_nonempty BIN_HASH; then
        echo "Error: --dht-tag requires --bin-dir with at least one platform binary" >&2
        exit 1
    fi
    DT="{"
    FIRST=1
    for PLATFORM in "${PLATFORMS[@]}"; do
        [ -n "${BIN_HASH[$PLATFORM]:-}" ] || continue
        TAG_VAL="${DHT_TAGS[$PLATFORM]:-$DHT_TAG_GLOBAL}"
        if [ -z "$TAG_VAL" ]; then
            echo "Error: no --dht-tag value for platform '$PLATFORM' (use --dht-tag $PLATFORM=<hex>, or a single --dht-tag <hex> to apply to all platforms)" >&2
            exit 1
        fi
        if [ "$FIRST" -eq 0 ]; then
            DT+=","
        fi
        FIRST=0
        DT+="\"$PLATFORM\":\"$TAG_VAL\""
    done
    DT+="}"
    DHT_BIN_JSON="$DT"
fi

# --- Build payload — must match UpdateManifest.signedPayload in
#     lib/core/update/update_manifest.dart exactly (byte-for-byte). ---
HAS_BINARY_FIELDS=""
if [ -n "$BIN_HASH_JSON" ] || [ -n "$DHT_BIN_JSON" ] || [ -n "$MONO_SEQ" ]; then
    HAS_BINARY_FIELDS=1
fi

if [ -z "$MIN_REQ" ] && [ -z "$MIN_REQ_REASON" ] && [ -z "$HAS_BINARY_FIELDS" ]; then
    # Legacy format — identical to pre-§19.6 manifests.
    PAYLOAD="${VERSION}\n${URL}\n${HASH}\n${CHANGELOG}\n${TIMESTAMP}"
else
    PAYLOAD="${VERSION}\n${URL}\n${HASH}\n${CHANGELOG}\n${TIMESTAMP}\n${MIN_REQ}\n${MIN_REQ_REASON}"
    if [ -n "$HAS_BINARY_FIELDS" ]; then
        # deltaBinaryTag (deltaBin) is not produced by this script — its slot
        # in the payload is always the empty string, matching a null field
        # on the Dart side.
        PAYLOAD="${PAYLOAD}\n${DHT_BIN_JSON}\n\n${MONO_SEQ}\n${BIN_HASH_JSON}\n${BIN_SIG_JSON}\n${BIN_SIZE_JSON}"
    fi
fi

# Sign with Ed25519
SIGNATURE=$(printf '%b' "$PAYLOAD" | ed25519_sign_stdin)

# --- Build JSON output ---
FIELDS=()
FIELDS+=("\"v\": \"$VERSION\"")
FIELDS+=("\"url\": \"$URL\"")
FIELDS+=("\"hash\": \"$HASH\"")
FIELDS+=("\"log\": \"$CHANGELOG\"")
FIELDS+=("\"ts\": $TIMESTAMP")
FIELDS+=("\"sig\": \"$SIGNATURE\"")
[ -n "$MIN_REQ" ] && FIELDS+=("\"minReq\": \"$MIN_REQ\"")
[ -n "$MIN_REQ_REASON" ] && FIELDS+=("\"minReqReason\": \"$MIN_REQ_REASON\"")
[ -n "$DHT_BIN_JSON" ] && FIELDS+=("\"dhtBin\": $DHT_BIN_JSON")
[ -n "$MONO_SEQ" ] && FIELDS+=("\"monotoneSeq\": $MONO_SEQ")
[ -n "$BIN_HASH_JSON" ] && FIELDS+=("\"binHash\": $BIN_HASH_JSON")
[ -n "$BIN_SIG_JSON" ] && FIELDS+=("\"binSig\": $BIN_SIG_JSON")
[ -n "$BIN_SIZE_JSON" ] && FIELDS+=("\"binSize\": $BIN_SIZE_JSON")

echo "{"
LAST=$((${#FIELDS[@]} - 1))
for i in "${!FIELDS[@]}"; do
    if [ "$i" -lt "$LAST" ]; then
        echo "  ${FIELDS[$i]},"
    else
        echo "  ${FIELDS[$i]}"
    fi
done
echo "}"

# Info/status text goes to stderr, not stdout — stdout must stay pure JSON so
# `sign-update-manifest.sh ... > manifest.json` produces a directly
# machine-readable manifest (consumed by publish-in-network-update.sh).
echo "" >&2
echo "Manifest created. Publish to DHT with key SHA-256('cleona-update-manifest')." >&2
if [ -n "$BIN_HASH_JSON" ]; then
    echo "Binary hashes/signatures/sizes included for: ${!BIN_HASH[*]}" >&2
    echo "Next step: distribute the binaries into the network with" >&2
    echo "  scripts/publish-in-network-update.sh --manifest <this-output.json> --bin-dir $BIN_DIR" >&2
fi
