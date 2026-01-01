# Linux backend for cleona_voice.h — work package V1.1.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.1 — Linux-Voice-Backend
# (PipeWire)". Architecture: Cleona_Chat_Architecture_v3_0.md §10.4.
#
# Picked up automatically by native/cleona_voice/CMakeLists.txt's platform
# loop (`foreach(_plat linux android apple windows) ... add_subdirectory`) --
# that file is V0.5/Build-Eigentümer property and was not edited to add this;
# the loop already existed and finds this file by convention.
#
# This directory owns exactly this file and the two backend sources
# (cleona_voice_linux.c, voice_apm_shim.{h,cpp}); it does not own
# linux/CMakeLists.txt (the Flutter Linux runner's build) -- wiring the
# resulting library into an actual `flutter build linux` bundle is requested
# from the Build-Eigentümer in BUILD_REQUEST_V1.1.md next to this file.
#
# The library TARGET is named exactly `cleona_voice` (not `cleona_voice_linux`)
# on purpose: linux/CMakeLists.txt:86-88 already carries a placeholder comment
# from the Build-Eigentümer naming that exact target for
# `install(TARGETS cleona_voice ...)`, the same pattern used for `cleona_audio`
# and `cleona_net` a few lines below it. Matching the name they already wrote
# down means BUILD_REQUEST_V1.1.md only has to ask for the two lines to be
# uncommented, not for a name to be reconciled.
#
# DEPENDENCIES
# -------------
# libpipewire-0.3 (>= 1.0, this machine has 1.0.5) and libspa-0.2 are always
# required -- there is no code path in this backend that runs without
# PipeWire.
#
# webrtc-audio-processing is required too, even though the PREFERRED chain
# (the PipeWire echo-cancel filter) does not link it directly: the backend
# falls back to linking it itself when the filter's AEC3 plugin cannot be
# loaded (architecture §10.4's Linux row; SPEC §12 risk table: "WebRTC APM
# linken; C++-Abhängigkeit auf einer Plattform bewusst akzeptiert"). A build
# without it therefore cannot deliver the fallback the architecture commits
# to, so this is REQUIRED, not optional.
#
# VERSION NOTE (see voice_apm_shim.h for the full explanation): this file
# looks for the classic `webrtc-audio-processing` pkg-config module (0.3.x,
# the legacy component API voice_apm_shim.cpp binds against). A distribution
# that only ships `webrtc-audio-processing-1` (the modern AEC3-based rewrite,
# an entirely different C++ API) will fail this pkg_check_modules() call --
# by design, not by omission: silently trying to compile the 0.3.x-shaped shim
# against a 1.x header tree would fail with confusing C++ errors deep in a
# vendored header instead of one clear CMake message here. Porting the shim to
# the modern API is a follow-up, not a silent recompile.

cmake_minimum_required(VERSION 3.13)

# ---------------------------------------------------------------------------
# Host guard -- this directory only builds on a genuine Linux HOST build.
# ---------------------------------------------------------------------------
# native/cleona_voice/CMakeLists.txt's platform loop
# (`foreach(_plat linux android apple windows) ... add_subdirectory(${_plat})`)
# descends into every platform directory that exists, UNCONDITIONALLY -- that
# parent file is Build-Eigentümer property and is not this package's to add a
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
if(ANDROID)
  return()
endif()

find_package(PkgConfig REQUIRED)

pkg_check_modules(CLEONA_PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(CLEONA_SPA      REQUIRED IMPORTED_TARGET libspa-0.2)
pkg_check_modules(CLEONA_WEBRTC_APM REQUIRED IMPORTED_TARGET webrtc-audio-processing)

if(CLEONA_WEBRTC_APM_VERSION VERSION_GREATER_EQUAL "1.0")
  message(WARNING
    "native/cleona_voice/linux: found webrtc-audio-processing "
    "${CLEONA_WEBRTC_APM_VERSION} (>= 1.0, the modern AEC3-based API). "
    "voice_apm_shim.cpp binds the legacy 0.3.x component API "
    "(EchoCancellation/NoiseSuppression/GainControl) and will not compile "
    "against this version. Known limitation, see voice_apm_shim.h.")
endif()

enable_language(CXX)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(cleona_voice SHARED
    cleona_voice_linux.c
    voice_apm_shim.cpp
)

target_link_libraries(cleona_voice PRIVATE
    cleona_voice_abi
    PkgConfig::CLEONA_PIPEWIRE
    PkgConfig::CLEONA_SPA
    PkgConfig::CLEONA_WEBRTC_APM
    pthread
)

set_target_properties(cleona_voice PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
)

if(NOT MSVC)
  target_compile_options(cleona_voice PRIVATE -Wall -Wextra)
endif()

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
