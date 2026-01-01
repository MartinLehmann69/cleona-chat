# verify_bundle_dlls.cmake — post-build check for the Windows bundle,
# in BOTH directions: completeness (every expected DLL present) and
# hygiene (no cleona_*.dll present that is not expected).
#
# Invoked via `cmake -P` from a POST_BUILD step in windows/runner/CMakeLists.txt.
#
# WHY THIS EXISTS (S290). "Wenn was fehlt ist die App kaputt = unbrauchbar"
# (project owner). Before this, an incomplete bundle was only noticed — if at
# all — much later: release-build.sh looked for build OUTPUTS in the INPUT
# directory before the build even ran, cleona_pow.dll was not checked anywhere
# in the Windows path, and the copy loop skipped a missing input silently. The
# consequence is quiet, not loud: without cleona_net.dll the client falls back
# to Dart's RawDatagramSocket.send(), which returns 0 for every destination on
# Windows (architecture §4.5.2) — it cannot send a single packet and logs one
# warn line.
#
# Two failure classes exist and only a directory check catches both:
#   * inputs (libsodium/liboqs/libzstd) — verified at configure time as well,
#     but a POST_BUILD copy can still fail afterwards
#   * outputs (cleona_net/cleona_pow) — the target may be dropped
#     from the MSBuild solution filter, or copy_if_different may hit a file lock
#     from a still-running cleona.exe. Exactly how cleona_pow.dll was absent
#     from every Windows build until S281.
#
# Arguments (both required):
#   -DBUNDLE_DIR=<dir>            directory to inspect
#   -DEXPECTED_DLLS=a.dll,b.dll   comma-separated (NOT semicolon: a semicolon
#                                 would be split by CMake while assembling the
#                                 custom-command argument list)

if(NOT DEFINED BUNDLE_DIR)
  message(FATAL_ERROR "verify_bundle_dlls: -DBUNDLE_DIR=<dir> is required")
endif()
if(NOT DEFINED EXPECTED_DLLS)
  message(FATAL_ERROR "verify_bundle_dlls: -DEXPECTED_DLLS=a.dll,b.dll is required")
endif()

if(NOT IS_DIRECTORY "${BUNDLE_DIR}")
  message(FATAL_ERROR
    "verify_bundle_dlls: bundle directory does not exist:\n  ${BUNDLE_DIR}")
endif()

string(REPLACE "," ";" _expected "${EXPECTED_DLLS}")

# Fail closed on an empty expected list (S338). Both callers assemble the
# argument from a literal, but if that assembly ever degrades to an empty
# string, every check below would trivially pass and report "0 native DLLs
# present" as success — a gate that silently shrank to nothing, the S336
# blind-gate class. An empty list is a broken caller, not a complete bundle.
set(_nonempty "")
foreach(_dll IN LISTS _expected)
  string(STRIP "${_dll}" _dll)
  if(NOT _dll STREQUAL "")
    list(APPEND _nonempty "${_dll}")
  endif()
endforeach()
if(NOT _nonempty)
  message(FATAL_ERROR
    "verify_bundle_dlls: EXPECTED_DLLS parsed to an empty list (got: "
    "'${EXPECTED_DLLS}').\n"
    "The caller's list assembly is broken — an empty expectation would make\n"
    "every check pass vacuously. Fix the -DEXPECTED_DLLS argument in\n"
    "windows/runner/CMakeLists.txt.")
endif()
set(_expected "${_nonempty}")

set(_missing "")
foreach(_dll IN LISTS _expected)
  string(STRIP "${_dll}" _dll)
  if(_dll STREQUAL "")
    continue()
  endif()
  if(NOT EXISTS "${BUNDLE_DIR}/${_dll}")
    list(APPEND _missing "${_dll}")
  endif()
endforeach()

if(_missing)
  string(REPLACE ";" "\n  " _missing_text "${_missing}")
  message(FATAL_ERROR
    "Windows bundle is incomplete — these native DLLs are missing:\n"
    "  ${_missing_text}\n"
    "\n"
    "Bundle directory:\n  ${BUNDLE_DIR}\n"
    "\n"
    "Inputs (libsodium/liboqs/libzstd) come from the provisioned package or\n"
    "windows/runner/ — provision them with windows/provision-<lib>.ps1.\n"
    "Outputs (cleona_net/cleona_pow) are built from native/ —\n"
    "check that the target was built and that its POST_BUILD copy succeeded\n"
    "(a running cleona.exe locks the destination file).\n"
    "\n"
    "This build is failed on purpose: shipping without one of these produces a\n"
    "client that is broken in a way that only shows up as a single warn line.")
endif()

# ── Reverse direction (S338): no foreign cleona_*.dll in the bundle ──────────
#
# The presence loop above cannot see an EXTRA DLL. That is not theoretical:
# after the §10.4 audio rework removed native/cleona_audio/ from the source
# tree, its cleona_audio.dll kept sitting in
# build/windows/x64/runner/Release on the build VM — the Release directory is
# not cleared between builds, `flutter build windows` only overwrites what it
# produces, and the ZIP/installer package the WHOLE directory. A dead,
# never-again-rebuilt binary would have shipped in every release, unnoticed by
# all three DLL gates (this script, WIN_BUNDLE_DLLS in release-build.sh,
# preflight Check 14), because all of them only asked "is everything there?"
# and never "is anything there that shouldn't be?".
#
# Scope is cleona_*.dll on purpose: those are the names this repo produces and
# the only ones whose full set EXPECTED_DLLS authoritatively describes. The
# bundle legitimately contains DLLs outside that set (flutter_windows.dll,
# MSVC runtime, plugin DLLs) whose inventory is Flutter's business, not ours.
#
# Matching is EXACT filename membership, not substring: a stale
# cleona_net2.dll must be flagged even though "cleona_net" is a prefix of it —
# a substring test is precisely the too-weak gate class from S338.
file(GLOB _bundle_cleona RELATIVE "${BUNDLE_DIR}" "${BUNDLE_DIR}/cleona_*.dll")
set(_foreign "")
foreach(_dll IN LISTS _bundle_cleona)
  list(FIND _expected "${_dll}" _idx)
  if(_idx EQUAL -1)
    list(APPEND _foreign "${_dll}")
  endif()
endforeach()

if(_foreign)
  string(REPLACE ";" "\n  " _foreign_text "${_foreign}")
  message(FATAL_ERROR
    "Windows bundle contains foreign cleona_*.dll files that no tracked\n"
    "native module produces:\n"
    "  ${_foreign_text}\n"
    "\n"
    "Bundle directory:\n  ${BUNDLE_DIR}\n"
    "\n"
    "Most likely a stale artifact of a removed native/ module (the Release\n"
    "directory is not cleared between builds — exactly how cleona_audio.dll\n"
    "survived the §10.4 audio rework). Delete the file from the bundle\n"
    "directory. If the DLL is genuinely new and wanted, it must be built via\n"
    "add_subdirectory from a tracked native/<name>/CMakeLists.txt and listed\n"
    "in -DEXPECTED_DLLS in windows/runner/CMakeLists.txt — preflight Check 14\n"
    "keeps that list bound to native/.\n"
    "\n"
    "This build is failed on purpose: the ZIP and the installer package this\n"
    "directory 1:1, so a stale DLL here ships to end users.")
endif()

list(LENGTH _expected _count)
message(STATUS
  "Windows bundle verified: ${_count} native DLLs present, "
  "no foreign cleona_*.dll in ${BUNDLE_DIR}")
