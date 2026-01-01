cmake_minimum_required(VERSION 3.13)
project(cleona_video C)

# Work package V0.3 of docs/SPEC_VOICE_VIDEO_REWORK.md.
#
# SCOPE OF THIS FILE. It builds only what lives under native/cleona_video/ and
# is deliberately self-contained: V0.3 does not own any build file outside this
# directory (SPEC §7 / §9). Everything repo-wide — linux/CMakeLists.txt,
# windows/runner/CMakeLists.txt, scripts/build-*-libs.sh,
# ios/CleonaNative/cleona_exported_symbols.txt, preflight jniLibs lists — is
# owned by the build package V0.5. What V0.5 has to add is written down in
# native/cleona_video/BUILD_REQUEST.md.
#
# Standalone use (this is what the V0.3 acceptance runs):
#   cmake -S native/cleona_video -B build/cleona_video
#   cmake --build build/cleona_video
#   ./build/cleona_video/smoke_video_mock
#
# Targets:
#   cleona_video_mock        SHARED  libcleona_video_mock.so — the ABI without
#                                    hardware, dlopen-able from Dart
#   cleona_video_mock_static STATIC  same objects, for tests that link directly
#   smoke_video_mock         EXE     V0.3 acceptance smoke (see smoke/)
#
# The conformance harness proper is package V0.4 and will live in
# native/cleona_video/test/. This file adds that subdirectory when it appears,
# so V0.4 does not have to touch this file either.

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(CLEONA_VIDEO_BUILD_MOCK  "Build the hardware-free mock backend" ON)
option(CLEONA_VIDEO_BUILD_SMOKE "Build the V0.3 smoke program"         ON)
option(CLEONA_VIDEO_STATIC      "Build static instead of shared (iOS)" OFF)
# Default ON so a platform build is unchanged. OFF configures the hardware-free
# half of this tree only — mock, smoke and the conformance harness.
#
# Why it exists: the platform subdirectories hard-require their vendor SDKs at
# CONFIGURE time (linux/CMakeLists.txt:46 pkg_check_modules(... libva)), so on
# a machine without them the whole tree fails to configure and even the mock —
# which needs no hardware by definition — cannot be built. That made the Dart
# smoke coverage (test/smoke/smoke_video_calls.dart, which loads
# build/cleona_video/libcleona_video_mock.so) unreachable on any box without a
# VAAPI toolchain, which is exactly the kind of box that runs it.
option(CLEONA_VIDEO_BUILD_PLATFORM "Build the platform backends (needs their SDKs)" ON)

# Warnings are on and stay on. Lowering them to make a build go green is
# explicitly out of bounds for this package.
if(MSVC)
  add_compile_options(/W3)
else()
  add_compile_options(-Wall -Wextra)
endif()

if(CLEONA_VIDEO_BUILD_MOCK)
  if(CLEONA_VIDEO_STATIC)
    add_library(cleona_video_mock STATIC mock/cleona_video_mock.c)
  else()
    add_library(cleona_video_mock SHARED mock/cleona_video_mock.c)
  endif()

  target_include_directories(cleona_video_mock PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/mock
  )

  # Only the annotated entry points are visible: CLEONA_VIDEO_API for the ABI,
  # CLEONA_VIDEO_MOCK_API for the mock knobs (which Dart must be able to dlopen,
  # SPEC §5). Everything else stays internal. Same posture as
  # native/cleona_audio.
  set_target_properties(cleona_video_mock PROPERTIES
    C_VISIBILITY_PRESET hidden
    OUTPUT_NAME cleona_video_mock
  )

  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(cleona_video_mock PRIVATE pthread)
  endif()
  if(ANDROID)
    # Bionic has pthread and clock_gettime in libc; nothing extra to link.
  endif()
  if(MSVC)
    # <stdint.h>/QueryPerformanceCounter only; no atomics used here.
    target_compile_options(cleona_video_mock PRIVATE /std:c11)
  endif()

  # Static flavour for C tests that link the mock directly (the smoke below,
  # and the V0.4 conformance harness). Same sources, no dlopen.
  add_library(cleona_video_mock_static STATIC mock/cleona_video_mock.c)
  target_include_directories(cleona_video_mock_static PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/mock
  )
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(cleona_video_mock_static PRIVATE pthread)
  endif()
endif()

if(CLEONA_VIDEO_BUILD_SMOKE AND CLEONA_VIDEO_BUILD_MOCK)
  add_executable(smoke_video_mock smoke/smoke_video_mock.c)
  target_link_libraries(smoke_video_mock PRIVATE cleona_video_mock_static)
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(smoke_video_mock PRIVATE pthread)
  endif()

  enable_testing()
  add_test(NAME video_mock_smoke COMMAND smoke_video_mock)
endif()

# V0.4 drops the conformance harness in here. Picked up automatically.
#
# enable_testing() is called unconditionally so that `ctest --test-dir <build>`
# finds the conformance tests even in a configuration that builds no smoke
# (-DCLEONA_VIDEO_BUILD_SMOKE=OFF), which is how a platform package building
# only its own backend will configure this tree.
enable_testing()
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/test/CMakeLists.txt")
  add_subdirectory(test)
endif()

# ---------------------------------------------------------------------------
# Platform backends, when they land (V1.13-V1.16). Each brings its own
# CMakeLists.txt and its own BUILD_REQUEST.md. Added after test/ so that
# cleona_video_add_conformance_test() is already defined (mirrors
# native/cleona_voice/CMakeLists.txt's identical loop).
# ---------------------------------------------------------------------------
if(CLEONA_VIDEO_BUILD_PLATFORM)
  foreach(_plat linux android apple windows)
    if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
      add_subdirectory(${_plat})
    endif()
  endforeach()
else()
  message(STATUS "cleona_video: platform backends skipped "
                 "(-DCLEONA_VIDEO_BUILD_PLATFORM=OFF) — mock/smoke/test only")
endif()
