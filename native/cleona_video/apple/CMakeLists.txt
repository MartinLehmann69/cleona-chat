# Apple video backend -- work package V1.15.
#
# SPEC:         docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.15".
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.6 (normative).
#
# Picked up automatically by native/cleona_video/CMakeLists.txt's enable_testing
# block and, once the parent gains a foreach loop like the voice tree has, by
# that loop. Until then, the parent's `if(EXISTS .../apple/CMakeLists.txt)
# add_subdirectory(apple)` block (or the build-ios-libs.sh / build-macos-libs.sh
# scripts) include this directory.
#
# HOST GUARD: this file must be a no-op on non-Apple platforms — otherwise a
# Linux or Android configure step would descend into it and fail on missing
# VideoToolbox.h / AVFoundation.h, or collide with a Linux/Android backend
# defining the same `cleona_video` target.
#
# `if(NOT APPLE)` is the correct guard: CMake sets APPLE only for iOS, macOS,
# tvOS, and watchOS toolchains. Unlike `UNIX`, it is NOT set for Android NDK
# builds. This matches the pattern the voice tree's apple directory will use.
if(NOT APPLE)
  return()
endif()

cmake_minimum_required(VERSION 3.13)

enable_language(OBJC)

# ---------------------------------------------------------------------------
# The backend itself.
#
# iOS:   static library (.a) — merged into the XCFramework by
#        scripts/build-ios-libs.sh, same pattern as cleona_audio and
#        cleona_voice. The Flutter iOS runner links the merged static lib.
#
# macOS: shared library (.dylib) — installed into the app bundle's
#        Contents/Frameworks/ by the macOS build, same as cleona_audio.
#        The Dart binding dlopen()'s it by name.
#
# The distinction is controlled by CLEONA_VIDEO_STATIC (from the parent
# CMakeLists.txt or passed by the build script).
# ---------------------------------------------------------------------------
option(CLEONA_VIDEO_STATIC "Build static instead of shared (iOS)" OFF)

if(CLEONA_VIDEO_STATIC OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(cleona_video STATIC cleona_video_apple.m)
else()
  add_library(cleona_video SHARED cleona_video_apple.m)
endif()

target_include_directories(cleona_video PRIVATE "${CMAKE_CURRENT_LIST_DIR}/..")

# Apple frameworks required by this backend.
find_library(AVFOUNDATION_FW AVFoundation REQUIRED)
find_library(VIDEOTOOLBOX_FW VideoToolbox REQUIRED)
find_library(COREMEDIA_FW CoreMedia REQUIRED)
find_library(COREVIDEO_FW CoreVideo REQUIRED)
find_library(FOUNDATION_FW Foundation REQUIRED)

target_link_libraries(cleona_video PRIVATE
    ${AVFOUNDATION_FW}
    ${VIDEOTOOLBOX_FW}
    ${COREMEDIA_FW}
    ${COREVIDEO_FW}
    ${FOUNDATION_FW}
)

set_target_properties(cleona_video PROPERTIES
    C_VISIBILITY_PRESET hidden
    OBJC_VISIBILITY_PRESET hidden
)

# Objective-C ARC is on by default in modern Xcode toolchains; be explicit
# so that a manual cmake invocation without Xcode's defaults still compiles.
target_compile_options(cleona_video PRIVATE -fobjc-arc -Wall -Wextra)

# ---------------------------------------------------------------------------
# Conformance test (SPEC §10 gate 4), same pattern as the Android backend.
# The Apple backend can run the conformance harness natively (no JNI/APK
# indirection) — camera access from a command-line process requires user
# consent on macOS (TCC), but the harness can run the headless/no-capture
# checks without it.
# ---------------------------------------------------------------------------
if(COMMAND cleona_video_add_conformance_test)
  cleona_video_add_conformance_test(cleona_video_conformance_apple cleona_video --shipping)
endif()
