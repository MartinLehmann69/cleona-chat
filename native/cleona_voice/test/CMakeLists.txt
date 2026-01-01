# Conformance harness for the cleona_voice ABI — work package V0.4.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §6 (the nine mandatory checks) and §7
# (V0.4). Architecture: Cleona_Chat_Architecture_v3_0.md §10.4.
#
# ===========================================================================
# READ THIS IF YOU ARE V1.1, V1.2, V1.3 OR V1.4
# ===========================================================================
# Your package is accepted when "the conformance test is green ON THE TARGET
# PLATFORM" (SPEC §10, gate 4). This directory is that test. You do not copy it,
# you do not fork it, and you do not need anything from V0.5 to run it.
#
# There are exactly two ways to point it at your backend.
#
# ---------------------------------------------------------------------------
# (A) YOUR BACKEND IS A SHARED LIBRARY  — Linux, Android, Windows, macOS
# ---------------------------------------------------------------------------
# Nothing to integrate. Build the loader once and hand it your library:
#
#     cmake -S native/cleona_voice -B build/voice
#     cmake --build build/voice -j
#     ./build/voice/test/cleona_voice_conformance_loader \
#           /path/to/libcleona_voice_pipewire.so --shipping \
#           --json acceptance/voice_linux.json
#
# On Android, push the binary and the .so to the device and run it there — the
# harness needs no files, no network and no framework, only libc and libdl:
#
#     adb push cleona_voice_conformance_loader /data/local/tmp/
#     adb push libcleona_voice_android.so      /data/local/tmp/
#     adb shell 'cd /data/local/tmp && ./cleona_voice_conformance_loader \
#                 ./libcleona_voice_android.so --shipping'
#
# On Windows the same binary takes a .dll. The loader resolves exactly the
# twelve ABI symbols and nothing else, so a backend that also exports test knobs
# is neither helped nor hindered by them.
#
# ---------------------------------------------------------------------------
# (B) YOUR BACKEND IS A STATIC LIBRARY  — iOS, or any no-dlopen deployment
# ---------------------------------------------------------------------------
# From your own CMakeLists (native/cleona_voice/<platform>/CMakeLists.txt), call
# the function this file defines:
#
#     cleona_voice_add_conformance_test(cleona_voice_conformance_apple
#                                       cleona_voice_apple)
#
# It builds the harness against your target and registers it with ctest. The
# function is defined by the time your subdirectory is processed, because the
# parent adds test/ before the platform loop.
#
# If you need to build the harness completely outside CMake — a device toolchain
# with its own build system — these are the sources, and there is nothing else:
#
#     native/cleona_voice/test/conformance.c
#     native/cleona_voice/test/conformance_abi.c
#     native/cleona_voice/test/conformance_harness.c
#
# C11, no dependencies beyond libc (and libdl when built with
# -DCLEONA_CONFORMANCE_LOAD). They are also exported in the cache variable
# CLEONA_VOICE_CONFORMANCE_SOURCES.
#
# ---------------------------------------------------------------------------
# WHAT TO PUT IN YOUR ACCEPTANCE REPORT
# ---------------------------------------------------------------------------
# The whole console output. It contains a JSON object between
# ---BEGIN-CLEONA-CONFORMANCE-JSON--- and ---END-CLEONA-CONFORMANCE-JSON---
# carrying the verification report (I11), so the effect states, the chain
# origin, the negotiated format and every check result are machine-comparable
# across backends. SPEC §6 additionally requires a written reason for every
# effect that is not ENABLED; the harness prints which ones those are (note N2)
# but cannot write the reason for you.
#
# Run with --shipping. It asserts what cleona_voice.h calls a valid release
# gate: a shipped backend never reports an id in the non-shipping range (>=100).
#
# ===========================================================================

cmake_minimum_required(VERSION 3.13)

set(CLEONA_VOICE_CONFORMANCE_SOURCES
    ${CMAKE_CURRENT_LIST_DIR}/conformance.c
    ${CMAKE_CURRENT_LIST_DIR}/conformance_abi.c
    ${CMAKE_CURRENT_LIST_DIR}/conformance_harness.c
    CACHE INTERNAL "Sources of the cleona_voice conformance harness (V0.4)")

# ---------------------------------------------------------------------------
# cleona_voice_add_conformance_test(<test-target-name> <backend-target>)
#
# Link mode: the harness calls the symbols of <backend-target> directly. This is
# the mode iOS needs, where the backend is a static archive.
# ---------------------------------------------------------------------------
function(cleona_voice_add_conformance_test TEST_NAME BACKEND_TARGET)
  add_executable(${TEST_NAME} ${CLEONA_VOICE_CONFORMANCE_SOURCES})
  target_include_directories(${TEST_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
  target_link_libraries(${TEST_NAME} PRIVATE ${BACKEND_TARGET})
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(${TEST_NAME} PRIVATE pthread)
  endif()
  add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME} ${ARGN})
  set_tests_properties(${TEST_NAME} PROPERTIES TIMEOUT 180)
endfunction()

# ---------------------------------------------------------------------------
# cleona_voice_add_conformance_loader(<test-target-name>)
#
# Load mode: one binary, any backend, chosen at run time. Not registered as a
# test by itself — a loader without a library to load has nothing to certify.
# ---------------------------------------------------------------------------
function(cleona_voice_add_conformance_loader TEST_NAME)
  add_executable(${TEST_NAME} ${CLEONA_VOICE_CONFORMANCE_SOURCES})
  target_include_directories(${TEST_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
  target_compile_definitions(${TEST_NAME} PRIVATE CLEONA_CONFORMANCE_LOAD)
  if(UNIX)
    target_link_libraries(${TEST_NAME} PRIVATE ${CMAKE_DL_LIBS})
  endif()
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(${TEST_NAME} PRIVATE pthread)
  endif()
endfunction()

# ===========================================================================
# What this package itself builds and registers
# ===========================================================================

if(CLEONA_VOICE_BUILD_MOCK)

  # (1) Link mode against the mock. The default ctest entry: it proves the ABI
  #     and the mock agree, and it is the variant iOS will use verbatim.
  cleona_voice_add_conformance_test(cleona_voice_conformance cleona_voice_mock)

  # (2) Load mode. Built here so that every platform package gets a working
  #     loader from a plain build of native/cleona_voice, and registered against
  #     the mock so the loader path itself is covered by ctest — a mechanism
  #     four platform packages depend on must not be first exercised by them.
  cleona_voice_add_conformance_loader(cleona_voice_conformance_loader)
  add_test(NAME cleona_voice_conformance_loader
           COMMAND cleona_voice_conformance_loader $<TARGET_FILE:cleona_voice_mock>)
  set_tests_properties(cleona_voice_conformance_loader PROPERTIES TIMEOUT 180)

  # -------------------------------------------------------------------------
  # (3) Negative controls.
  #
  # Each runs the very same harness against a backend that breaks exactly one
  # property, and passes only when the harness reports exactly that check as
  # failed (--expect-fail is an equality, not a threshold — see
  # conformance_harness.c). Without these, "green" would be indistinguishable
  # from "the test never looked".
  # -------------------------------------------------------------------------
  add_library(cleona_voice_saboteur SHARED saboteur/voice_saboteur.c)
  target_include_directories(cleona_voice_saboteur PRIVATE
                             ${CMAKE_CURRENT_LIST_DIR}/../mock)
  if(UNIX)
    target_link_libraries(cleona_voice_saboteur PRIVATE m)
  endif()
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(cleona_voice_saboteur PRIVATE pthread)
  endif()
  if(WIN32)
    set_target_properties(cleona_voice_saboteur PROPERTIES PREFIX "")
  endif()
  set_target_properties(cleona_voice_saboteur PROPERTIES C_VISIBILITY_PRESET hidden)

  # id -> injected defect -> the check(s) that must catch it
  #
  # The second field is the FULL set of ids expected to go red, comma-separated,
  # because --expect-fail is an equality. Where a defect legitimately trips two
  # checks, both are named rather than one of them being engineered away: S13
  # asserts that BOTH mute states survive a route change (§10.4 says "states",
  # plural), so a backend that cannot report one of them fails S13 as well as the
  # per-direction check. Naming both is the honest expectation; narrowing S13 to
  # one direction to keep the table tidy would have weakened the check.
  set(_negctl
      "short_frame|C3"                    # I4    short capture frame
      "duplex|C2"                         # I2    two devices, not one session
      "accept_wrong_size|C4"              # §6.4  playback adapts, not rejects
      "fx_no_origin|C7"                   # I11   ENABLED effect, no chain origin
      "route_not_in_mask|C8"              # §6.8  active route missing from mask
      # ---- erratum E6a -------------------------------------------------------
      "mic_mute_not_reported|C5c,S13"     # E6a   mic mute set but not observable
      "output_mute_not_reported|C6b,S13"  # E6a   output mute not observable
      "mute_lost_on_route|S13"            # §10.4 route switch clears the mutes
      "mute_dirty_after_open|S12")        # E6a   muted before anyone asked

  foreach(_entry IN LISTS _negctl)
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _defect)
    list(GET _parts 1 _expect)
    add_test(NAME cleona_voice_negctl_${_defect}
             COMMAND cleona_voice_conformance_loader
                     $<TARGET_FILE:cleona_voice_saboteur>
                     --expect-fail ${_expect})
    set_tests_properties(cleona_voice_negctl_${_defect} PROPERTIES
                         TIMEOUT 180
                         ENVIRONMENT "CLEONA_VOICE_SABOTAGE=${_defect}")
  endforeach()

  # -------------------------------------------------------------------------
  # (4) The leak negative control — only meaningful under a sanitizer.
  #
  # SPEC §6 check 9 says "clean stop/close without leak (under ASan/Valgrind,
  # where available)". A run that reports no leak is worthless unless a run WITH
  # a leak is shown to report one, so the saboteur can also leak a block per
  # open(). Configure with -DCLEONA_VOICE_ASAN=ON and this test passes only when
  # LeakSanitizer actually speaks up.
  # -------------------------------------------------------------------------
  if(CLEONA_VOICE_ASAN)
    add_test(NAME cleona_voice_negctl_leak
             COMMAND cleona_voice_conformance_loader
                     $<TARGET_FILE:cleona_voice_saboteur>)
    set_tests_properties(cleona_voice_negctl_leak PROPERTIES
                         TIMEOUT 180
                         ENVIRONMENT "CLEONA_VOICE_SABOTAGE=leak"
                         PASS_REGULAR_EXPRESSION "detected memory leaks")
  endif()

endif()
