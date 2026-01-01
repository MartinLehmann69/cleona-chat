# Conformance harness for the cleona_video ABI — work package V0.4.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 (V0.4), §13 Erratum E1.
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.6, §10.3.1.
#
# ===========================================================================
# READ THIS IF YOU ARE V1.13, V1.14, V1.15 OR V1.16
# ===========================================================================
# Your package is accepted when the video conformance test is green on your
# platform and the report shows hardware_encode = 1 with H.264 as the negotiable
# base (SPEC §7, V1.13-V1.16). This directory is that test. Do not copy it, do
# not fork it, and you need nothing from V0.5 to run it.
#
# SPEC §6 lists nine mandatory checks for VOICE and none for video; the video
# list is derived from cleona_video.h, invariants I9/I10/I11/I12 and Erratum E1,
# and the derivation is written down at the top of conformance.c so you can
# check it rather than trust it.
#
# ---------------------------------------------------------------------------
# (A) YOUR BACKEND IS A SHARED LIBRARY  — Linux, Android, Windows, macOS
# ---------------------------------------------------------------------------
#     cmake -S native/cleona_video -B build/video
#     cmake --build build/video -j
#     ./build/video/test/cleona_video_conformance_loader \
#           /path/to/libcleona_video_vaapi.so --shipping \
#           --json acceptance/video_linux.json
#
# On a device, push the binary and the library and run it there — the harness
# needs libc and libdl and nothing else:
#
#     adb push cleona_video_conformance_loader /data/local/tmp/
#     adb push libcleona_video_android.so      /data/local/tmp/
#     adb shell 'cd /data/local/tmp && ./cleona_video_conformance_loader \
#                 ./libcleona_video_android.so --shipping'
#
# ---------------------------------------------------------------------------
# (B) YOUR BACKEND IS A STATIC LIBRARY  — iOS, or any no-dlopen deployment
# ---------------------------------------------------------------------------
# From your own CMakeLists:
#
#     cleona_video_add_conformance_test(cleona_video_conformance_apple
#                                       cleona_video_apple)
#
# NOTE FOR V1.13-V1.16: native/cleona_video/CMakeLists.txt does not yet add
# platform subdirectories at all (unlike the voice tree, which has a loop for
# them). Adding that loop is a change to a file this package does not own; it is
# requested in native/cleona_video/test/BUILD_REQUEST.md. Until it lands, use
# route (A), which needs no build integration whatsoever.
#
# Building outside CMake — these are the sources, and there is nothing else:
#     native/cleona_video/test/conformance.c
#     native/cleona_video/test/conformance_abi.c
#     native/cleona_video/test/conformance_harness.c
# C11, libc only (plus libdl with -DCLEONA_CONFORMANCE_LOAD). Also exported as
# CLEONA_VIDEO_CONFORMANCE_SOURCES.
#
# ---------------------------------------------------------------------------
# WHAT TO PUT IN YOUR ACCEPTANCE REPORT
# ---------------------------------------------------------------------------
# The whole console output. It carries a JSON object between
# ---BEGIN-CLEONA-CONFORMANCE-JSON--- and ---END-CLEONA-CONFORMANCE-JSON---
# with the verification report (I11) — codec, hardware_encode/decode, the
# backend ids, every counter and every check result — so several backends can be
# compared without re-running anything.
#
# ===========================================================================

cmake_minimum_required(VERSION 3.13)

set(CLEONA_VIDEO_CONFORMANCE_SOURCES
    ${CMAKE_CURRENT_LIST_DIR}/conformance.c
    ${CMAKE_CURRENT_LIST_DIR}/conformance_abi.c
    ${CMAKE_CURRENT_LIST_DIR}/conformance_harness.c
    CACHE INTERNAL "Sources of the cleona_video conformance harness (V0.4)")

# ---------------------------------------------------------------------------
# cleona_video_add_conformance_test(<test-target-name> <backend-target>)
# Link mode — the harness calls the symbols of <backend-target> directly.
# ---------------------------------------------------------------------------
function(cleona_video_add_conformance_test TEST_NAME BACKEND_TARGET)
  add_executable(${TEST_NAME} ${CLEONA_VIDEO_CONFORMANCE_SOURCES})
  target_include_directories(${TEST_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
  target_link_libraries(${TEST_NAME} PRIVATE ${BACKEND_TARGET})
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(${TEST_NAME} PRIVATE pthread)
  endif()
  add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME} ${ARGN})
  set_tests_properties(${TEST_NAME} PROPERTIES TIMEOUT 300)
endfunction()

# ---------------------------------------------------------------------------
# cleona_video_add_conformance_loader(<target-name>)
# Load mode — one binary, any backend, chosen at run time.
# ---------------------------------------------------------------------------
function(cleona_video_add_conformance_loader TEST_NAME)
  add_executable(${TEST_NAME} ${CLEONA_VIDEO_CONFORMANCE_SOURCES})
  target_include_directories(${TEST_NAME} PRIVATE ${CMAKE_CURRENT_LIST_DIR})
  target_compile_definitions(${TEST_NAME} PRIVATE CLEONA_CONFORMANCE_LOAD)
  if(UNIX)
    target_link_libraries(${TEST_NAME} PRIVATE ${CMAKE_DL_LIBS})
  endif()
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(${TEST_NAME} PRIVATE pthread)
  endif()
endfunction()

# ---------------------------------------------------------------------------
# Sanitizer switch for this directory only.
#
# native/cleona_video/CMakeLists.txt has no ASan option and belongs to V0.3, so
# the flags are applied to the targets built here instead of to the whole
# project. That is enough for SPEC §6 check 9: LeakSanitizer intercepts the
# allocator process-wide, so a leak inside the (uninstrumented) mock is still
# reported — with a slightly shorter stack. The saboteur, which is where the
# deliberate leak lives, is compiled here and is fully instrumented.
# ---------------------------------------------------------------------------
option(CLEONA_VIDEO_TEST_ASAN "Build the conformance targets with ASan/LSan" OFF)
if(CLEONA_VIDEO_TEST_ASAN AND NOT MSVC)
  add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
  add_link_options(-fsanitize=address)
endif()

# ===========================================================================
# What this package itself builds and registers
# ===========================================================================

if(CLEONA_VIDEO_BUILD_MOCK)

  # (1) Link mode against the mock — the default ctest entry, and the variant
  #     iOS will use verbatim.
  cleona_video_add_conformance_test(cleona_video_conformance cleona_video_mock_static)

  # (2) Load mode, registered against the shared mock so the mechanism four
  #     platform packages depend on is itself covered by ctest.
  cleona_video_add_conformance_loader(cleona_video_conformance_loader)
  add_test(NAME cleona_video_conformance_loader
           COMMAND cleona_video_conformance_loader $<TARGET_FILE:cleona_video_mock>)
  set_tests_properties(cleona_video_conformance_loader PROPERTIES TIMEOUT 300)

  # -------------------------------------------------------------------------
  # (3) Negative controls: the same harness against a backend that breaks
  #     exactly one property. --expect-fail is an equality over the set of
  #     failed check ids, so "something went red" is not accepted as proof.
  # -------------------------------------------------------------------------
  add_library(cleona_video_saboteur SHARED saboteur/video_saboteur.c)
  target_include_directories(cleona_video_saboteur PRIVATE
                             ${CMAKE_CURRENT_LIST_DIR}/..
                             ${CMAKE_CURRENT_LIST_DIR}/../mock)
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(cleona_video_saboteur PRIVATE pthread)
  endif()
  if(WIN32)
    set_target_properties(cleona_video_saboteur PROPERTIES PREFIX "")
  endif()
  set_target_properties(cleona_video_saboteur PROPERTIES C_VISIBILITY_PRESET hidden)

  # defect -> the check(s) that must catch it
  set(_vnegctl
      "oversize|V7"             # I9  frame handed out beyond the ceiling
      "pts_from_index|V8,V17"   # E1  pts walks backwards when fps rises again
      "capture_closed|V20"      # I12 own video off reported as session gone
      "no_h264|V2"              # H.264 is the mandatory interop level
      "open_err_swap|V1b")      # E6b open() blames the caller for a slow link

  foreach(_entry IN LISTS _vnegctl)
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _defect)
    list(GET _parts 1 _expect)
    add_test(NAME cleona_video_negctl_${_defect}
             COMMAND cleona_video_conformance_loader
                     $<TARGET_FILE:cleona_video_saboteur>
                     --expect-fail ${_expect})
    set_tests_properties(cleona_video_negctl_${_defect} PROPERTIES
                         TIMEOUT 300
                         ENVIRONMENT "CLEONA_VIDEO_SABOTAGE=${_defect}")
  endforeach()

  # (4) The leak negative control — proves LeakSanitizer is actually running,
  #     without which "no leak reported" and "nothing was checked" look alike.
  if(CLEONA_VIDEO_TEST_ASAN)
    add_test(NAME cleona_video_negctl_leak
             COMMAND cleona_video_conformance_loader
                     $<TARGET_FILE:cleona_video_saboteur>)
    set_tests_properties(cleona_video_negctl_leak PROPERTIES
                         TIMEOUT 300
                         ENVIRONMENT "CLEONA_VIDEO_SABOTAGE=leak"
                         PASS_REGULAR_EXPRESSION "detected memory leaks")
  endif()

endif()
