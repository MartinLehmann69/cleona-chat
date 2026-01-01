# verify_bundle_dlls.cmake — post-build completeness check for the Windows bundle.
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

list(LENGTH _expected _count)
message(STATUS "Windows bundle complete: ${_count} native DLLs present in ${BUNDLE_DIR}")
