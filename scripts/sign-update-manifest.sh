#!/usr/bin/env bash
# Sign a Cleona update manifest with the maintainer key — HYBRID.
#
# ── TWO SIGNATURES OVER THE SAME BYTES (v4_2 §4.4.3, §26.5.2) ────────────
#
# §4.4.3 "Signature rule (normative)" lists the update manifest as
# `hybrid`; §4.4.1 requires that the receiver checks both signatures individually
# and that BOTH must be valid. This script therefore produces:
#
#   `sig`   Ed25519   over $PAYLOAD   (openssl, classic key)
#   `sigPq` ML-DSA-65 over $PAYLOAD   (liboqs via scripts/maintainer_mldsa.dart)
#
# If either of the two is missing, this script aborts. A manifest with only
# one signature would not be a weaker manifest — `UpdateManifest.verify`
# rejects it, so the pipeline would have published an artefact that its
# own clients do not accept (the same trap as with --mono-seq, S368).
#
# Why ML-DSA-65 is NOT signed via openssl: the verifying side
# is liboqs (`lib/core/crypto/oqs_ffi.dart`, `OQS_SIG_verify`/`ML-DSA-65`).
# Another library may implement the same standard in a different variant
# (pure/prehash, context, framing) — the error then only shows in the
# field. `scripts/maintainer_mldsa.dart` uses the same library and
# the same calls as the node.
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
#                      cleona-linux, cleona-android, cleona-windows.
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
#   - Maintainer Ed25519 private key at ~/CleonaPrivat/keys/cleona_maintainer_private.pem
#     (or CLEONA_MAINTAINER_KEY env)
#   - Maintainer ML-DSA-65 private key at ~/CleonaPrivat/keys/cleona_maintainer_mldsa.key
#     (or CLEONA_MAINTAINER_MLDSA_KEY env). Generated with
#     `scripts/gen-maintainer-mldsa-key.sh` — by the owner, once.
#
# After signing a manifest with --bin-dir, distribute the binaries into the network with:
#   scripts/publish-in-network-update.sh --manifest <manifest.json> --bin-dir <DIR>

set -euo pipefail

PRIVATE_KEY="${CLEONA_MAINTAINER_KEY:-$HOME/CleonaPrivat/keys/cleona_maintainer_private.pem}"
MLDSA_KEY="${CLEONA_MAINTAINER_MLDSA_KEY:-$HOME/CleonaPrivat/keys/cleona_maintainer_mldsa.key}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Platforms supported by §19.6.2 in-network distribution, in the fixed order
# used everywhere below (JSON map key order). Must stay stable — the signed
# payload embeds these maps as compact JSON and the receiver's verification
# re-serializes the decoded map in the same order it appeared in the manifest.
# macOS/iOS excluded: macOS uses DMG (GitHub Release), iOS uses TestFlight.
PLATFORMS=(linux android windows)

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

# ML-DSA-65 via liboqs — the same library that the verifying node
# uses. Prints the signature base64 on stdout.
mldsa_sign_stdin() {
    local tmp="$SIGN_TMPDIR/sign-pq-input-$$-$RANDOM"
    cat > "$tmp"
    ( cd "$PROJECT_DIR" && dart run scripts/maintainer_mldsa.dart sign "$MLDSA_KEY" "$tmp" )
    rm -f "$tmp"
}

# --- Argument parsing: pull out flags, leave positional args in place ---
BIN_DIR=""
MONO_SEQ=""
PREVS=()
DELTA_OUT=""
BSDIFF="${BSDIFF:-bsdiff}"
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
        --prev)
            # S387, D1 (§26.6.2): PLATFORM=VERSION=FILE of the installed
            # predecessor version; at most two per platform (V-1, V-2).
            [ $# -ge 2 ] || usage
            PREVS+=("$2")
            shift 2
            ;;
        --delta-out)
            [ $# -ge 2 ] || usage
            DELTA_OUT="$2"
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
    echo "Error: Maintainer Ed25519 private key not found at: $PRIVATE_KEY" >&2
    echo "Set CLEONA_MAINTAINER_KEY, or place the key at" >&2
    echo "  ~/CleonaPrivat/keys/cleona_maintainer_private.pem" >&2
    exit 1
fi

# The PQ half is not optional. Without it a manifest would arise that every
# 4.2 client rejects (§4.4.3) — aborting here is cheaper than a
# published, unusable release.
if [ ! -f "$MLDSA_KEY" ]; then
    echo "ERROR: ML-DSA-65 maintainer key not found: $MLDSA_KEY" >&2
    echo "  The manifest is signed HYBRID (v4_2 4.4.3). Without the" >&2
    echo "  post-quantum half every client rejects the manifest." >&2
    echo "  Generate once (owner, own machine):" >&2
    echo "    scripts/gen-maintainer-mldsa-key.sh" >&2
    echo "  or set CLEONA_MAINTAINER_MLDSA_KEY to the existing one." >&2
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

# --- S387, D1 (§26.6.2): deltas from V-1 and V-2, each with hash and length ---
#
# "The manifest names every delta together with its content hash and
# length, per platform and per source version; without both, a node can
# neither derive the delta's key nor tell when it is complete." Until S387
# this script produced no delta, and deltaBin stayed empty in the payload.
#
# Generated with bsdiff (environment variable BSDIFF, default `bsdiff`).
# If the tool is missing, the script aborts — a manifest that promises a delta
# that does not exist would be worse than none.
DELTA_BIN_JSON=""
DELTA_HASH_JSON=""
DELTA_SIZE_JSON=""
if [ "${#PREVS[@]}" -gt 0 ]; then
    if ! assoc_nonempty BIN_HASH; then
        echo "Error: --prev requires --bin-dir with the new binaries" >&2
        exit 1
    fi
    if ! command -v "$BSDIFF" >/dev/null 2>&1; then
        echo "Error: --prev needs bsdiff ('$BSDIFF' not found; set BSDIFF=...)" >&2
        exit 1
    fi
    DELTA_OUT="${DELTA_OUT:-$BIN_DIR/deltas}"
    mkdir -p "$DELTA_OUT"
    declare -A PREV_COUNT D_BIN D_HASH D_SIZE
    for SPEC in "${PREVS[@]}"; do
        P_PLAT="${SPEC%%=*}"
        REST="${SPEC#*=}"
        P_VER="${REST%%=*}"
        P_FILE="${REST#*=}"
        if [ -z "$P_PLAT" ] || [ -z "$P_VER" ] || [ "$P_FILE" = "$REST" ] || [ ! -f "$P_FILE" ]; then
            echo "Error: --prev '$SPEC' is not PLATFORM=VERSION=EXISTING_FILE" >&2
            exit 1
        fi
        if [ -z "${BIN_HASH[$P_PLAT]:-}" ]; then
            echo "Error: --prev for '$P_PLAT', but no new cleona-$P_PLAT in --bin-dir" >&2
            exit 1
        fi
        PREV_COUNT["$P_PLAT"]=$(( ${PREV_COUNT[$P_PLAT]:-0} + 1 ))
        if [ "${PREV_COUNT[$P_PLAT]}" -gt 2 ]; then
            echo "Error: more than two --prev for '$P_PLAT' — D1 allows V-1 and V-2 only" >&2
            exit 1
        fi
        D_FILE="$DELTA_OUT/cleona-$P_PLAT-$VERSION-from-$P_VER.bsdiff"
        "$BSDIFF" "$P_FILE" "$(realpath "$BIN_DIR/cleona-$P_PLAT")" "$D_FILE"
        D_HEX=$(openssl dgst -sha256 "$D_FILE" | awk '{print $NF}')
        D_LEN=$(stat -c%s "$D_FILE" 2>/dev/null || stat -f%z "$D_FILE")
        D_BIN["$P_PLAT"]+="${D_BIN[$P_PLAT]:+,}\"$P_VER\":\"1\""
        D_HASH["$P_PLAT"]+="${D_HASH[$P_PLAT]:+,}\"$P_VER\":\"$D_HEX\""
        D_SIZE["$P_PLAT"]+="${D_SIZE[$P_PLAT]:+,}\"$P_VER\":$D_LEN"
        echo "  [$P_PLAT] delta $P_VER -> $VERSION: $D_FILE hash=$D_HEX size=${D_LEN}B" >&2
    done
    DB="{"; DH="{"; DZ="{"
    FIRST=1
    for PLATFORM in "${PLATFORMS[@]}"; do
        [ -n "${D_BIN[$PLATFORM]:-}" ] || continue
        if [ "$FIRST" -eq 0 ]; then DB+=","; DH+=","; DZ+=","; fi
        FIRST=0
        DB+="\"$PLATFORM\":{${D_BIN[$PLATFORM]}}"
        DH+="\"$PLATFORM\":{${D_HASH[$PLATFORM]}}"
        DZ+="\"$PLATFORM\":{${D_SIZE[$PLATFORM]}}"
    done
    DELTA_BIN_JSON="$DB}"
    DELTA_HASH_JSON="$DH}"
    DELTA_SIZE_JSON="$DZ}"
fi

# --- S368: the sequence number is MANDATORY, not optional ----------------
#
# `UpdateManifest.isDowngradeAttempt` fails closed since S368: a
# manifest WITHOUT `monotoneSeq` counts as a downgrade attempt and is rejected for
# in-network updates. Before, a missing field was a
# free pass — an old, validly signed manifest thus bypassed the
# replay protection completely.
#
# This check stands here so that the pipeline does not publish something
# that its own clients reject. Without it the fix on the read side
# would be a silent update block.
if [ -z "$MONO_SEQ" ]; then
    echo "ERROR: --mono-seq missing." >&2
    echo "  Since S368 every client rejects a manifest without monotoneSeq" >&2
    echo "  (replay protection, §19.6). A manifest without the number" >&2
    echo "  would not merely be weaker — it would be ineffective." >&2
    exit 1
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
        # S387: deltaBin sits in the second slot; hash and length of the deltas
        # are appended at the end, ONLY if there are deltas — exactly like
        # UpdateManifest.signedPayload.
        PAYLOAD="${PAYLOAD}\n${DHT_BIN_JSON}\n${DELTA_BIN_JSON}\n${MONO_SEQ}\n${BIN_HASH_JSON}\n${BIN_SIG_JSON}\n${BIN_SIZE_JSON}"
        if [ -n "$DELTA_HASH_JSON" ]; then
            PAYLOAD="${PAYLOAD}\n${DELTA_HASH_JSON}\n${DELTA_SIZE_JSON}"
        fi
    fi
fi

# --- Hybrid signature: BOTH over exactly the same bytes ------------------
#
# `printf '%b'` is fed twice with the same $PAYLOAD; the two
# signatures thus cover the same byte sequence, exactly as
# `UpdateManifest.verify` rebuilds it from the read manifest.
SIGNATURE=$(printf '%b' "$PAYLOAD" | ed25519_sign_stdin)
if [ -z "$SIGNATURE" ]; then
    echo "ERROR: Ed25519 signature is empty — openssl delivered nothing." >&2
    exit 1
fi

SIGNATURE_PQ=$(printf '%b' "$PAYLOAD" | mldsa_sign_stdin)
if [ -z "$SIGNATURE_PQ" ]; then
    echo "ERROR: ML-DSA-65 signature is empty." >&2
    exit 1
fi

# --- Build JSON output ---
FIELDS=()
FIELDS+=("\"v\": \"$VERSION\"")
FIELDS+=("\"url\": \"$URL\"")
FIELDS+=("\"hash\": \"$HASH\"")
FIELDS+=("\"log\": \"$CHANGELOG\"")
FIELDS+=("\"ts\": $TIMESTAMP")
FIELDS+=("\"sig\": \"$SIGNATURE\"")
FIELDS+=("\"sigPq\": \"$SIGNATURE_PQ\"")
[ -n "$MIN_REQ" ] && FIELDS+=("\"minReq\": \"$MIN_REQ\"")
[ -n "$MIN_REQ_REASON" ] && FIELDS+=("\"minReqReason\": \"$MIN_REQ_REASON\"")
[ -n "$DHT_BIN_JSON" ] && FIELDS+=("\"dhtBin\": $DHT_BIN_JSON")
[ -n "$MONO_SEQ" ] && FIELDS+=("\"monotoneSeq\": $MONO_SEQ")
[ -n "$BIN_HASH_JSON" ] && FIELDS+=("\"binHash\": $BIN_HASH_JSON")
[ -n "$BIN_SIG_JSON" ] && FIELDS+=("\"binSig\": $BIN_SIG_JSON")
[ -n "$BIN_SIZE_JSON" ] && FIELDS+=("\"binSize\": $BIN_SIZE_JSON")
[ -n "$DELTA_BIN_JSON" ] && FIELDS+=("\"deltaBin\": $DELTA_BIN_JSON")
[ -n "$DELTA_HASH_JSON" ] && FIELDS+=("\"deltaHash\": $DELTA_HASH_JSON")
[ -n "$DELTA_SIZE_JSON" ] && FIELDS+=("\"deltaSize\": $DELTA_SIZE_JSON")

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
