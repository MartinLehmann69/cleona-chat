#!/bin/bash
# =============================================================================
# check-daemon-lib-resolvable.sh — does the binary resolve its store? (S367)
# =============================================================================
#
# Usage:   scripts/check-daemon-lib-resolvable.sh <binary> [...]
# Returns: 0 = every embedded library path resolves, 1 = not.
#
# ── WHAT THIS GATE MEASURES, AND WHY NOT THE OBVIOUS ──────────────────
#
# Until S367 three places here had `[ -f "<bundle>/lib/libsqlite3.so" ]`.
# This check was GREEN while the defect was present — the file was
# always there, it was just in the wrong place relative to the BINARY. It measured a
# value that only coincided with the statement by chance.
#
# The statement is: "the path that THIS binary opens at runtime
# exists". So exactly that is checked — read out of the binary,
# not repeated in the script. If the tool changes the path
# (`../lib/` → something else), the gate follows; a `../lib/`
# spelled out here would, at the next Dart update, again be a
# gate that measures the wrong object.
#
# ── WHERE THE PATH COMES FROM ────────────────────────────────────────
#
# `dart build cli` puts the library into `bundle/lib/` and embeds in
# the binary the path `../lib/<name>` — RELATIVE TO THE
# EXECUTABLE. Re-measured 05.09.2026 in this tree:
#
#     $ strings build/daemon/bin/cleona-daemon | grep libsqlite3
#     package:sqlite3/src/ffi/libsqlite3.g.dart
#     ../lib/libsqlite3.so
#
# Working directory, `LD_LIBRARY_PATH` and `RPATH $ORIGIN/` have no effect
# here; the Dart loader computes by itself and in case of error reports
# literally "relative to '<path of the binary>'".
#
# ── WHAT A FINDING MEANS ─────────────────────────────────────────────
#
# Not "a file is missing", but: the daemon terminates when opening
# the store — WITH EXIT 0. Measured on 05.09.2026, the same binary
# once in `bin/` and once in the bundle root:
#
#     bin/    → "V4.1-Knoten gestartet auf Port 41501, 1 Identitäten"
#     root    → ALIVE=0 EXIT=0 and in the log
#               "[ERROR] Dienst-Start fehlgeschlagen: … Failed to load
#               dynamic library '../lib/libsqlite3.so' relative to
#               '…/layout-falsch/cleona-daemon'"
#
# Exit 0 is indistinguishable for the UI from "running, just not opening
# a socket". Therefore a finding here is hard and not a warning.
#
# ── LIMITS, EXPLICITLY ───────────────────────────────────────────────
#
#  * What is checked is EXISTENCE of the path, not loadability (architecture,
#    symbols, permissions). A `dlopen` would be the stronger measurement,
#    but needs the target platform — this gate also runs over
#    a Windows binary collected via `scp`.
#  * If the gate finds NO embedded path AT ALL, it fails
#    CLOSED (exit 1). A binary without a library reference is exactly the case
#    that `dart compile exe` produces — the original error.
#  * An embedded name WITHOUT `/` (bare `libsqlite3.so`) cannot
#    be decided from here: then the loader searches via the
#    system's search paths. That also fails closed, with its own message.

set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <binary> [more...]" >&2
  exit 2
fi

# Names of the libraries that come via a code asset (build hook).
# Today exactly one: `package:sqlite3`. Further ones belong here, not in
# a second copy of this script.
ASSET_LIB_RE='libsqlite3|sqlite3'

RC=0

check_one() {
  local bin="$1"
  local bindir
  if [ ! -f "$bin" ]; then
    echo "FAIL: '$bin' does not exist." >&2
    return 1
  fi
  bindir="$(cd "$(dirname "$bin")" && pwd)"

  # All embedded strings that look like a path to one of the
  # asset libraries. `grep -a` reads the binary as
  # text; `strings` is not installed on every workbench.
  local paths
  paths="$(grep -aoE "[A-Za-z0-9_./\\\\:+-]*(${ASSET_LIB_RE})[A-Za-z0-9_.+-]*\.(so|dll|dylib)" "$bin" \
            | grep -vE '\.g\.dart' | sort -u)"

  if [ -z "$paths" ]; then
    echo "FAIL: '$bin' contains no reference to a storage library." >&2
    echo "      That is exactly what 'dart compile exe' produces — it runs no" >&2
    echo "      build hooks and silently builds without the library." >&2
    echo "      Build path: scripts/build-daemon.sh (dart build cli)." >&2
    return 1
  fi

  local p target error=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # Convert Windows separators to POSIX form, so that the same code can
    # check an .exe collected via scp.
    local pn="${p//\\//}"
    case "$pn" in
      /*|[A-Za-z]:/*)
        target="$pn" ;;
      */*)
        target="$bindir/$pn" ;;
      *)
        echo "FAIL: '$bin' embeds '$p' WITHOUT a directory." >&2
        echo "      Then the system search path decides which" >&2
        echo "      library is loaded — that cannot be checked from" >&2
        echo "      here, and in the bundle it is not wanted." >&2
        error=1
        continue ;;
    esac
    if [ -f "$target" ]; then
      echo "OK: $bin -> '$p' resolves ($target)"
    else
      echo "FAIL: $bin embeds '$p' — this path does not exist." >&2
      echo "      Searched from the directory of the binary: $target" >&2
      echo "      Consequence: the daemon exits when opening the storage" >&2
      echo "      with EXIT 0 — for the UI indistinguishable from" >&2
      echo "      'running'. The daemon belongs in <bundle>/bin/, the" >&2
      echo "      library in <bundle>/lib/." >&2
      error=1
    fi
  done <<< "$paths"

  return "$error"
}

for b in "$@"; do
  check_one "$b" || RC=1
done

exit "$RC"
