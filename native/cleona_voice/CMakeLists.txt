# CMakeLists for the cleona_voice ABI and its hardware-free mock backend.
#
# Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V0.2.
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.4.
#
# SCOPE OF THIS FILE
# ------------------
# V0.2 owns native/cleona_voice/** and nothing else. This file therefore builds
# the ABI header target and the mock only. It is deliberately NOT referenced
# from linux/CMakeLists.txt, windows/runner/CMakeLists.txt, or any script in
# scripts/ — those files belong to the build owner (V0.5 / V1.8, SPEC §9).
# What they have to add is written down in BUILD_REQUEST.md next to this file.
#
# Platform backends (V1.1-V1.4) add their own subdirectories under
# native/cleona_voice/<platform>/ and are picked up by the block at the bottom
# when they exist; adding one must not require editing this file.
#
# BUILD (Linux, standalone):
#   cmake -B build -S native/cleona_voice
#   cmake --build build -j
#   ./build/cleona_voice_smoke
#
# BUILD with AddressSanitizer + LeakSanitizer (SPEC §6 check 9):
#   cmake -B build-asan -S native/cleona_voice -DCLEONA_VOICE_ASAN=ON
#   cmake --build build-asan -j
#   ./build-asan/cleona_voice_smoke

cmake_minimum_required(VERSION 3.13)

project(cleona_voice
        VERSION 1.0.0
        LANGUAGES C
        DESCRIPTION "Cleona native OS voice session — ABI and mock backend")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(CLEONA_VOICE_BUILD_MOCK  "Build the hardware-free mock backend" ON)
option(CLEONA_VOICE_BUILD_SMOKE "Build the V0.2 C smoke programme"     ON)
option(CLEONA_VOICE_ASAN        "Build with Address/Leak sanitizer"    OFF)
# Set by the platform build (V0.5) when the iOS static-merge path is used, in
# the same way native/cleona_audio/CMakeLists.txt uses CLEONA_IOS_STATIC.
option(CLEONA_IOS_STATIC        "Build static archives for the iOS merge" OFF)

if(NOT MSVC)
  add_compile_options(-Wall -Wextra -Wpedantic -fvisibility=hidden)
endif()

if(CLEONA_VOICE_ASAN)
  if(MSVC)
    message(WARNING "CLEONA_VOICE_ASAN is a no-op on MSVC in this file")
  else()
    add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address)
  endif()
endif()

# ---------------------------------------------------------------------------
# Header-only interface target. Platform backends link this to get the ABI
# header on their include path without inheriting anything else.
# ---------------------------------------------------------------------------
add_library(cleona_voice_abi INTERFACE)
target_include_directories(cleona_voice_abi INTERFACE ${CMAKE_CURRENT_LIST_DIR})

# ---------------------------------------------------------------------------
# Mock backend
#
# Output names are deliberately distinct from the real backend's:
#   real  -> libcleona_voice.so   / cleona_voice.dll
#   mock  -> libcleona_voice_mock.so / cleona_voice_mock.dll
# Both export the same symbols, so a single process must never load both. The
# Dart binding selects one by name (VoiceNativeLibrary.mock() vs .platform()),
# which keeps the choice explicit at the call site instead of depending on the
# loader search order.
# ---------------------------------------------------------------------------
if(CLEONA_VOICE_BUILD_MOCK)
  if(CLEONA_IOS_STATIC)
    add_library(cleona_voice_mock STATIC mock/cleona_voice_mock.c)
  else()
    add_library(cleona_voice_mock SHARED mock/cleona_voice_mock.c)
  endif()

  target_link_libraries(cleona_voice_mock PUBLIC cleona_voice_abi)

  if(UNIX)
    # sin() for the synthetic tone.
    target_link_libraries(cleona_voice_mock PRIVATE m)
  endif()
  if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(cleona_voice_mock PRIVATE pthread)
  endif()
  if(WIN32)
    # Strip the "lib" prefix so the output is cleona_voice_mock.dll, matching
    # the naming the Dart loader expects on Windows.
    set_target_properties(cleona_voice_mock PROPERTIES PREFIX "")
  endif()

  set_target_properties(cleona_voice_mock PROPERTIES
                        C_VISIBILITY_PRESET hidden)
endif()

# ---------------------------------------------------------------------------
# V0.2 smoke programme
#
# This is NOT the conformance test. The conformance harness is work package
# V0.4 and owns native/cleona_voice/test/**; this directory is deliberately
# separate so the two never collide in git. The smoke programme walks the nine
# mandatory checks of SPEC §6 against the mock so that V0.2 can be accepted on
# its own, and V0.4 replaces it with the shared harness.
# ---------------------------------------------------------------------------
if(CLEONA_VOICE_BUILD_SMOKE AND CLEONA_VOICE_BUILD_MOCK)
  add_executable(cleona_voice_smoke smoke/voice_smoke.c)
  target_link_libraries(cleona_voice_smoke PRIVATE cleona_voice_mock)
  if(UNIX)
    target_link_libraries(cleona_voice_smoke PRIVATE m)
  endif()

  enable_testing()
  add_test(NAME cleona_voice_smoke COMMAND cleona_voice_smoke)
endif()

# ---------------------------------------------------------------------------
# V0.4 conformance harness. Added BEFORE the platform loop on purpose: it
# defines cleona_voice_add_conformance_test(), which a platform backend calls
# from its own CMakeLists to build the harness against itself (SPEC §10 gate 4,
# "conformance test green on the target platform"). A CMake function is only
# visible to directories processed after the one that defined it.
#
# enable_testing() is unconditional here so that `ctest --test-dir <build>`
# finds the conformance tests even in a configuration that builds no smoke.
# ---------------------------------------------------------------------------
enable_testing()
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/test/CMakeLists.txt")
  add_subdirectory(test)
endif()

# ---------------------------------------------------------------------------
# Platform backends, when they land (V1.1-V1.4). Each brings its own
# CMakeLists.txt and its own BUILD_REQUEST.md.
# ---------------------------------------------------------------------------
foreach(_plat linux android apple windows)
  if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
    add_subdirectory(${_plat})
  endif()
endforeach()
