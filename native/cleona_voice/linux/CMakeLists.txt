# Linux backend for cleona_voice.h — work package V1.1.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.1 — Linux-Voice-Backend
# (PipeWire)". Architecture: Cleona_Chat_Architecture_v3_0.md §10.4.
#
# Picked up automatically by native/cleona_voice/CMakeLists.txt's platform
# loop (`foreach(_plat linux android apple windows) ... add_subdirectory`) --
# that file is V0.5/build owner property and was not edited to add this;
# the loop already existed and finds this file by convention.
#
# This directory owns exactly this file and the two backend sources
# (cleona_voice_linux.c, voice_apm_shim.{h,cpp}); it does not own
# linux/CMakeLists.txt (the Flutter Linux runner's build) -- wiring the
# resulting library into an actual `flutter build linux` bundle was done by
# the build owner in linux/CMakeLists.txt (BUGFIX_CURRENT.md AV-V1.1).
#
# The library TARGET is named exactly `cleona_voice` (not `cleona_voice_linux`)
# on purpose: linux/CMakeLists.txt:86-88 already carries a placeholder comment
# from the build owner naming that exact target for
# `install(TARGETS cleona_voice ...)`, the same pattern used for `cleona_audio`
# and `cleona_net` a few lines below it. Matching the name they already wrote
# down meant the build owner only had to uncomment two lines, not reconcile
# a name.
#
# DEPENDENCIES
# -------------
# libpipewire-0.3 (>= 1.0, this machine has 1.0.5) and libspa-0.2 are always
# required -- there is no code path in this backend that runs without
# PipeWire.
#
# THE FALLBACK CHAIN IS A SEPARATE LIBRARY (S410, owner decision B 29.10.2026;
# S410-I6-MESSUNG.md finding 2). v4_2 §17.5: "Linux via PipeWire duplex with
# the echo-cancel module, or failing that, a directly linked WebRTC APM".
# Two targets:
#   * cleona_voice      -> libcleona_voice.so, the backend. Links PipeWire
#                          only. NO webrtc dependency: the preferred chain does
#                          not need one, and until S410 the fixed link to the
#                          system's webrtc-audio-processing 0.3.1 kept the
#                          whole library from loading on Ubuntu 26.04 (which
#                          ships only 1.3).
#   * cleona_voice_apm  -> libcleona_voice_apm.so, voice_apm_shim.cpp with
#                          webrtc-audio-processing 1.3 (AEC3) linked statically,
#                          built from the pinned source by linux/webrtc_apm.
#                          Exports only the cleona_voice_apm_* functions.
#                          cleona_voice_linux.c dlopen()s it from its own
#                          directory when it falls back (voice_apm_shim.h,
#                          "WHY A SEPARATE LIBRARY").
# Both carry RUNPATH $ORIGIN — they live in bundle/lib/ themselves, not in a
# lib/ below it (the runner's global CMAKE_INSTALL_RPATH "$ORIGIN/lib" is for
# the executable in the bundle root).

cmake_minimum_required(VERSION 3.13)

# ---------------------------------------------------------------------------
# Host guard -- this directory only builds on a genuine Linux HOST build.
# ---------------------------------------------------------------------------
# native/cleona_voice/CMakeLists.txt's platform loop
# (`foreach(_plat linux android apple windows) ... add_subdirectory(${_plat})`)
# descends into every platform directory that exists, UNCONDITIONALLY -- that
# parent file is build owner property and is not this package's to add a
# condition to (SPEC §9). The condition has to live here instead.
#
# Without it, an Android NDK cross-build (scripts/build-android-libs.sh, which
# passes -DCMAKE_TOOLCHAIN_FILE=.../android.toolchain.cmake) still walks into
# this directory, still finds a HOST pkg-config (this machine's own
# libpipewire-0.3/libwebrtc-audio-processing, not anything for the target
# ABI), and still defines a target literally named `cleona_voice` -- which
# then collides with V1.2's real Android backend target of the same name and
# kills the whole configure step before anything builds:
#
#   CMake Error at android/CMakeLists.txt:4 (add_library):
#     add_library cannot create target "cleona_voice" because another target
#     with the same name already exists. The existing target is a shared
#     library created in source directory ".../native/cleona_voice/linux".
#
# (reproduced verbatim against a throwaway stand-in android/CMakeLists.txt
# during this fix's own verification -- see the V1.1 session report for the
# full transcript, both with and without this guard).
#
# THE OBVIOUS WRONG GUARD IS `if(NOT UNIX)`. CMake's NDK toolchain file sets
# UNIX too -- Android's kernel is Linux -- so `if(NOT UNIX) return()` looks
# exactly right and does nothing: the cross-build still has UNIX true, still
# descends, still collides. `ANDROID` is the variable that actually
# distinguishes the two in this repo's own NDK toolchain setup, and it is not
# a novel choice: native/cleona_audio/CMakeLists.txt:36 already gates its
# POSIX-only pthread linkage on `UNIX AND NOT APPLE AND NOT ANDROID` for
# exactly this reason. `return()` at the top of an add_subdirectory()'d file
# is documented CMake behaviour: it ends processing of this file only, the
# parent loop continues to the next platform directory unaffected.
if(NOT UNIX OR ANDROID OR APPLE)
  return()
endif()

find_package(PkgConfig REQUIRED)

pkg_check_modules(CLEONA_PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(CLEONA_SPA      REQUIRED IMPORTED_TARGET libspa-0.2)
enable_language(CXX)
# webrtc-audio-processing 1.3 is C++17 (its meson.build: cpp_std=c++17).
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# webrtc-audio-processing 1.3 from the pinned source — one project for the
# Flutter bundle and the standalone builds (scripts/build-daemon.sh); the
# guard keeps a second add_subdirectory from defining it twice.
if(NOT TARGET cleona_webrtc_apm)
  add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../linux/webrtc_apm"
                   "${CMAKE_CURRENT_BINARY_DIR}/webrtc_apm")
endif()

# --- the backend: PipeWire only, opens the fallback library on demand ---
add_library(cleona_voice SHARED
    cleona_voice_linux.c
)

target_link_libraries(cleona_voice PRIVATE
    cleona_voice_abi
    PkgConfig::CLEONA_PIPEWIRE
    PkgConfig::CLEONA_SPA
    pthread
    ${CMAKE_DL_LIBS}
)

# --- the fallback chain: shim + static webrtc-audio-processing 1.3 ---
add_library(cleona_voice_apm SHARED
    voice_apm_shim.cpp
)
add_dependencies(cleona_voice_apm cleona_webrtc_apm)
# The include directory exists only after cleona_webrtc_apm has installed
# (build time), so it is a plain path here, not an imported target. SYSTEM:
# the library's own headers do not pass -Wextra (audio_processing.h:85,
# unused parameter) — their warnings are not ours to fix.
target_include_directories(cleona_voice_apm SYSTEM PRIVATE
    "${CLEONA_WEBRTC_APM_PREFIX}/include/webrtc-audio-processing-1"
    "${CLEONA_WEBRTC_APM_PREFIX}/include")
# The two defines the library's own pkg-config file hands to its users
# (webrtc-audio-processing-1.pc: Cflags … -DWEBRTC_LIBRARY_IMPL -DWEBRTC_POSIX).
target_compile_definitions(cleona_voice_apm PRIVATE WEBRTC_LIBRARY_IMPL WEBRTC_POSIX)
target_link_libraries(cleona_voice_apm PRIVATE
    "${CLEONA_WEBRTC_APM_LIBRARY}"
    pthread
)
# --exclude-libs,ALL: no symbol of the static archive is exported, so a
# system webrtc-audio-processing that PipeWire's echo-cancel plugin may load
# into the same process cannot be interposed by ours or vice versa.
# --no-undefined: an unresolved symbol fails the link here, not the dlopen()
# on a user's machine.
target_link_options(cleona_voice_apm PRIVATE
    "LINKER:--exclude-libs,ALL"
    "LINKER:--no-undefined")

foreach(_t cleona_voice cleona_voice_apm)
  set_target_properties(${_t} PROPERTIES
      C_VISIBILITY_PRESET hidden
      CXX_VISIBILITY_PRESET hidden
      VISIBILITY_INLINES_HIDDEN ON
      # Both live in the same directory (bundle/lib/, build/daemon/lib/, and
      # this build directory); cleona_voice_linux.c opens the fallback from
      # there. The same RUNPATH in the build tree and installed.
      BUILD_WITH_INSTALL_RPATH ON
      INSTALL_RPATH "$ORIGIN")
  if(NOT MSVC)
    target_compile_options(${_t} PRIVATE -Wall -Wextra)
  endif()
endforeach()

# ---------------------------------------------------------------------------
# Conformance test (SPEC §10 gate 4: "green on the target platform"), both
# ways the harness supports:
#  (1) link mode against this shared library's own target, so `ctest` in a
#      plain build of native/cleona_voice exercises the real Linux backend
#      alongside the mock's link-mode test -- no manual step required.
#  (2) documented here for anyone reading this file: the loader built by
#      native/cleona_voice/test/CMakeLists.txt also works,
#      `cleona_voice_conformance_loader $<TARGET_FILE:cleona_voice> --shipping`,
#      and is what a release-acceptance report should actually run (link mode
#      re-links the harness against this exact target, which is convenient
#      for local iteration but is not testing the shared library artefact the
#      Flutter bundle ships).
# ---------------------------------------------------------------------------
if(COMMAND cleona_voice_add_conformance_test)
  cleona_voice_add_conformance_test(cleona_voice_conformance_linux cleona_voice --shipping)
endif()
