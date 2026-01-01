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
# Arguments (all three required):
#   -DBUNDLE_DIR=<dir>            directory to inspect
#   -DEXPECTED_DLLS=a.dll,b.dll   comma-separated (NOT semicolon: a semicolon
#                                 would be split by CMake while assembling the
#                                 custom-command argument list)
#   -DEXPECTED_LIB_DLLS=a.dll,... the same for <dir>/lib (S422: the
#                                 whisper.cpp set, see "Library directory"
#                                 below). Required, so that a caller that
#                                 forgets it fails instead of skipping it.
# Optional: -DEXPECTED_PROGRAMS=a.exe,b.exe (see the end of this file).

if(NOT DEFINED BUNDLE_DIR)
  message(FATAL_ERROR "verify_bundle_dlls: -DBUNDLE_DIR=<dir> is required")
endif()
if(NOT DEFINED EXPECTED_DLLS)
  message(FATAL_ERROR "verify_bundle_dlls: -DEXPECTED_DLLS=a.dll,b.dll is required")
endif()
if(NOT DEFINED EXPECTED_LIB_DLLS)
  message(FATAL_ERROR "verify_bundle_dlls: -DEXPECTED_LIB_DLLS=a.dll,b.dll is required")
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

# ── Library directory (S422): -DEXPECTED_LIB_DLLS=a.dll,b.dll ───────────────
#
# The whisper.cpp set (whisper.dll, whisper_wrapper.dll, ggml*.dll) lies in
# <bundle>/lib, where whisper_ffi.dart looks for it (AppPaths.bundleLibDir —
# for the daemon in bin/ the only bundle path it searches). Until S422 no
# build path put it there and no list asked for it, so every Windows build
# shipped without transcription and every gate stayed green
# (`mycelium/berichte/S422-RCA-E2E-LAUF-4.2.8.md`, R-11).
#
# Both directions, as above: every expected file present in lib/, and no
# whisper*.dll / ggml*.dll that is not expected — neither in lib/ (a stale
# DLL of an older whisper.cpp, e.g. a renamed ggml backend) nor in the
# bundle root, where the GUI's bare-name lookup would pick it up before the
# one in lib/. The namespace is whisper*/ggml* on purpose, the same reasoning
# as cleona_*: only that set does EXPECTED_LIB_DLLS describe exhaustively;
# lib/ also holds sqlite3.dll from the build hook of package:sqlite3.
string(REPLACE "," ";" _lib_expected "${EXPECTED_LIB_DLLS}")
set(_lib_nonempty "")
foreach(_dll IN LISTS _lib_expected)
  string(STRIP "${_dll}" _dll)
  if(NOT _dll STREQUAL "")
    list(APPEND _lib_nonempty "${_dll}")
  endif()
endforeach()
if(NOT _lib_nonempty)
  message(FATAL_ERROR
    "verify_bundle_dlls: EXPECTED_LIB_DLLS parsed to an empty list (got: "
    "'${EXPECTED_LIB_DLLS}').\n"
    "Fix the -DEXPECTED_LIB_DLLS argument in windows/runner/CMakeLists.txt.")
endif()
set(_lib_expected "${_lib_nonempty}")

set(_lib_missing "")
foreach(_dll IN LISTS _lib_expected)
  if(NOT EXISTS "${BUNDLE_DIR}/lib/${_dll}")
    list(APPEND _lib_missing "lib/${_dll}")
  endif()
endforeach()
if(_lib_missing)
  string(REPLACE ";" "\n  " _lib_missing_text "${_lib_missing}")
  message(FATAL_ERROR
    "Windows bundle is incomplete — these DLLs are missing from lib/:\n"
    "  ${_lib_missing_text}\n"
    "\n"
    "Bundle directory:\n  ${BUNDLE_DIR}\n"
    "\n"
    "They come from the package windows/provision-whisper.ps1 builds\n"
    "(<libs>/whisper-<version>/pkg/bin) and are copied by a POST_BUILD step\n"
    "in windows/runner/CMakeLists.txt. Without them the transcription page\n"
    "says \"whisper.cpp library not available\" and nothing else reports it.")
endif()

file(GLOB _lib_bundle RELATIVE "${BUNDLE_DIR}/lib"
     "${BUNDLE_DIR}/lib/whisper*.dll" "${BUNDLE_DIR}/lib/ggml*.dll")
file(GLOB _root_whisper RELATIVE "${BUNDLE_DIR}"
     "${BUNDLE_DIR}/whisper*.dll" "${BUNDLE_DIR}/ggml*.dll")
set(_lib_foreign "")
foreach(_dll IN LISTS _lib_bundle)
  list(FIND _lib_expected "${_dll}" _idx)
  if(_idx EQUAL -1)
    list(APPEND _lib_foreign "lib/${_dll}")
  endif()
endforeach()
foreach(_dll IN LISTS _root_whisper)
  list(APPEND _lib_foreign "${_dll}")
endforeach()
if(_lib_foreign)
  string(REPLACE ";" "\n  " _lib_foreign_text "${_lib_foreign}")
  message(FATAL_ERROR
    "Windows bundle contains whisper*/ggml* DLLs that do not belong there:\n"
    "  ${_lib_foreign_text}\n"
    "\n"
    "Bundle directory:\n  ${BUNDLE_DIR}\n"
    "\n"
    "The whisper.cpp set belongs in lib/ and consists exactly of\n"
    "-DEXPECTED_LIB_DLLS in windows/runner/CMakeLists.txt. A copy in the\n"
    "bundle root would be loaded by the GUI before the one in lib/; an extra\n"
    "one in lib/ is a leftover of another whisper.cpp build (the Release\n"
    "directory is not cleared between builds). Delete the named file.")
endif()
list(LENGTH _lib_expected _lib_count)

# ── Helper programs (S403): -DEXPECTED_PROGRAMS=a.exe,b.exe ─────────────────
#
# A helper program the daemon starts by name is the same failure class as a
# DLL it loads by name: when it is absent nothing fails, a feature is just
# gone. Without cleona-play.exe every sound is silent on Windows — which was
# the state of every Windows build up to S403 and went unnoticed for months,
# because the old player quietly did nothing. The same holds for
# cleona-notify.exe (S420): without it Windows shows no system notification
# and nothing else says so. The argument is optional so
# that a caller with no helper program stays valid; a caller that passes it
# must pass a non-empty list.
set(_program_count 0)
if(DEFINED EXPECTED_PROGRAMS)
  string(REPLACE "," ";" _programs "${EXPECTED_PROGRAMS}")
  set(_missing_programs "")
  foreach(_program IN LISTS _programs)
    string(STRIP "${_program}" _program)
    if(_program STREQUAL "")
      continue()
    endif()
    math(EXPR _program_count "${_program_count} + 1")
    if(NOT EXISTS "${BUNDLE_DIR}/${_program}")
      list(APPEND _missing_programs "${_program}")
    endif()
  endforeach()
  if(_program_count EQUAL 0)
    message(FATAL_ERROR
      "verify_bundle_dlls: EXPECTED_PROGRAMS parsed to an empty list (got: "
      "'${EXPECTED_PROGRAMS}').\n"
      "Fix the -DEXPECTED_PROGRAMS argument in windows/runner/CMakeLists.txt.")
  endif()
  if(_missing_programs)
    string(REPLACE ";" "\n  " _missing_programs_text "${_missing_programs}")
    message(FATAL_ERROR
      "Windows bundle is incomplete — these helper programs are missing:\n"
      "  ${_missing_programs_text}\n"
      "\n"
      "Bundle directory:\n  ${BUNDLE_DIR}\n"
      "\n"
      "Each one is copied by a POST_BUILD step in\n"
      "windows/runner/CMakeLists.txt; check that its target was built and\n"
      "that the copy succeeded:\n"
      "  cleona-play.exe      from windows/cleona_play/ (its sources are\n"
      "                       fetched from github.com/xiph on the first\n"
      "                       configure) -- without it no sound\n"
      "  cleona-notify.exe    from windows/cleona_notify/ -- without it no\n"
      "                       system notification\n"
      "  cleona-firewall.cmd  from windows/ -- without it no firewall rule\n"
      "\n"
      "This build is failed on purpose: the daemon starts these by name, and\n"
      "a missing one fails silently.")
  endif()
endif()

list(LENGTH _expected _count)
message(STATUS
  "Windows bundle verified: ${_count} native DLLs, ${_lib_count} DLLs in lib/ "
  "and ${_program_count} helper program(s) present, no foreign cleona_*.dll "
  "or whisper*/ggml* DLL in ${BUNDLE_DIR}")
