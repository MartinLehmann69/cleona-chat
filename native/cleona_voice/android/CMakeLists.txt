# Android voice backend — work package V1.2.
#
# SPEC:         docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.2".
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.4 (normative).
#
# Picked up automatically by native/cleona_voice/CMakeLists.txt, which iterates
# over linux/android/apple/windows and adds whichever subdirectory exists. That
# loop is unconditional, so this file must make itself a no-op on every other
# host — otherwise a plain `cmake -S native/cleona_voice` on the dev machine
# (which is how V0.4's ctest runs) would try to build JNI code against a
# non-existent jni.h.
if(NOT ANDROID)
  return()
endif()

# ---------------------------------------------------------------------------
# The backend itself.
#
# Output name is libcleona_voice.so, which is what the Dart binding asks the
# Android linker for (`lib/core/calls/voice_session.dart:368`) and what the
# jniLibs layout expects. Installing it there is the build owner's job — see
# BUILD_REQUEST_V1.2.md §1.
# ---------------------------------------------------------------------------
add_library(cleona_voice SHARED cleona_voice_android.c)
target_link_libraries(cleona_voice PUBLIC cleona_voice_abi)
target_link_libraries(cleona_voice PRIVATE log)
set_target_properties(cleona_voice PROPERTIES C_VISIBILITY_PRESET hidden)

# ---------------------------------------------------------------------------
# On-device conformance runner (SPEC §10 gate 4).
#
# The V0.4 harness is normally a command-line binary pushed to /data/local/tmp
# (test/CMakeLists.txt, variant A). That works for a backend that is pure native
# code; it cannot work for this one. The Android voice chain is only reachable
# through the Java API (§10.4: "The Java API is mandatory on Android"), so the
# backend needs a running ART runtime, an application `Context` for
# `AudioManager`, and a real RECORD_AUDIO grant. An `adb shell` process has none
# of the three.
#
# The harness is therefore built as a shared library and loaded into a purpose-
# made APK, where all three exist exactly as they do in production. Nothing in
# native/cleona_voice/test/** is copied or modified: this uses the documented
# extension point, the exported source list CLEONA_VOICE_CONFORMANCE_SOURCES.
#
# Off by default — a normal app build must not carry the harness.
# ---------------------------------------------------------------------------
option(CLEONA_VOICE_ANDROID_CONFORMANCE
       "Build the on-device conformance runner library (test only)" OFF)

if(CLEONA_VOICE_ANDROID_CONFORMANCE)
  if(NOT CLEONA_VOICE_CONFORMANCE_SOURCES)
    message(FATAL_ERROR
            "CLEONA_VOICE_CONFORMANCE_SOURCES is empty — native/cleona_voice/test "
            "was not processed. Configure from native/cleona_voice, not from here.")
  endif()

  add_library(cleona_voice_conformance SHARED
              ${CLEONA_VOICE_CONFORMANCE_SOURCES}
              conformance/conformance_jni.c)
  target_include_directories(cleona_voice_conformance PRIVATE
                             ${CMAKE_CURRENT_LIST_DIR}/../test)
  # Link mode: the harness calls the backend's symbols directly. Load mode would
  # dlopen a second copy of the library, and the copy Dart/JNI initialised would
  # not be the copy under test.
  target_link_libraries(cleona_voice_conformance PRIVATE cleona_voice log)
endif()
