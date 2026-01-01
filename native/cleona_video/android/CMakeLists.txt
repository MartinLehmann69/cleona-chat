# Android video backend -- work package V1.14.
#
# SPEC:         docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.14".
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.6 (normative).
#
# Picked up automatically by native/cleona_video/CMakeLists.txt's platform
# loop, per native/cleona_video/test/BUILD_REQUEST.md §1. That loop is
# unconditional (mirrors the cleona_voice tree, whose android/CMakeLists.txt
# guards itself the same way), so this file must make itself a no-op on every
# other host -- otherwise a Linux/Windows configure would descend into it and
# fail on missing <camera/NdkCameraManager.h>/<media/NdkMediaCodec.h> or, once
# V1.13/V1.16 land, die on a duplicate `cleona_video` target the way
# BUILD_REQUEST_V1.2.md §5 documents for the voice tree's Linux backend.
#
# `if(NOT UNIX)` would be the wrong guard here for the same reason
# BUILD_REQUEST_V1.2.md §5 calls out: CMake sets UNIX for an Android NDK
# toolchain build too. `if(NOT ANDROID)` is what native/cleona_voice/android/
# already uses and is the only guard that actually distinguishes the two.
if(NOT ANDROID)
  return()
endif()

# ---------------------------------------------------------------------------
# The backend itself.
#
# Output name is libcleona_video.so, matching what the Dart binding's search
# path expects (lib/core/calls/video_pipeline.dart: "libcleona_video.so" next
# to the executable / in native/cleona_video/CMakeLists.txt's parent include
# dir) and what scripts/build-android-libs.sh will install into jniLibs once
# BUILD_REQUEST_V1.14.md §1 lands.
# ---------------------------------------------------------------------------
add_library(cleona_video SHARED cleona_video_android.c)
target_include_directories(cleona_video PRIVATE "${CMAKE_CURRENT_LIST_DIR}/..")
target_link_libraries(cleona_video PRIVATE log mediandk)
set_target_properties(cleona_video PROPERTIES C_VISIBILITY_PRESET hidden)

# ---------------------------------------------------------------------------
# On-device conformance runner (SPEC §10 gate 4), same shape as
# native/cleona_voice/android/CMakeLists.txt's CLEONA_VOICE_ANDROID_CONFORMANCE.
#
# The Android video backend is reachable only through the Java API for the
# same structural reason as voice (see cleona_video_android.c's file header):
# Camera2's CameraManager and the Flutter TextureRegistry both need a Context
# / a running Flutter engine that an `adb shell` process does not have. The
# harness is therefore packaged into a purpose-made APK instead of pushed as a
# bare command-line binary.
#
# Off by default -- a normal app build must not carry the harness.
# ---------------------------------------------------------------------------
option(CLEONA_VIDEO_ANDROID_CONFORMANCE
       "Build the on-device conformance runner library (test only)" OFF)

if(CLEONA_VIDEO_ANDROID_CONFORMANCE)
  if(NOT CLEONA_VIDEO_CONFORMANCE_SOURCES)
    message(FATAL_ERROR
            "CLEONA_VIDEO_CONFORMANCE_SOURCES is empty -- native/cleona_video/test "
            "was not processed. Configure from native/cleona_video, not from here.")
  endif()

  add_library(cleona_video_conformance SHARED
              ${CLEONA_VIDEO_CONFORMANCE_SOURCES}
              conformance/conformance_jni.c)
  target_include_directories(cleona_video_conformance PRIVATE
                             ${CMAKE_CURRENT_LIST_DIR}/../test)
  # Link mode: the harness calls the backend's symbols directly, so the copy
  # under test is the same copy Dart/JNI would load -- not a second dlopen'd
  # instance.
  target_link_libraries(cleona_video_conformance PRIVATE cleona_video log)
endif()
