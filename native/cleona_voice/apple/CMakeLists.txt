# Apple voice backend — VoiceProcessingIO, shared by iOS and macOS.
#
# Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
# Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4.
#
# ===========================================================================
# HOW THIS IS REACHED
# ===========================================================================
# native/cleona_voice/CMakeLists.txt ends with
#
#     foreach(_plat linux android apple windows)
#       if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
#         add_subdirectory(${_plat})
#
# so this directory is picked up merely by existing. Nothing in the parent file
# was changed by this package — it belongs to V0.2/V0.4.
#
# Standalone (the way the conformance test is meant to be built):
#
#   macOS:  cmake -S native/cleona_voice -B build/voice \
#                 -DCLEONA_VOICE_BUILD_MOCK=OFF -DCLEONA_VOICE_BUILD_SMOKE=OFF
#           cmake --build build/voice -j
#           ctest --test-dir build/voice -R cleona_voice_conformance_apple -V
#
#   iOS:    the same configure with -DCMAKE_SYSTEM_NAME=iOS -DCLEONA_IOS_STATIC=ON
#           produces libcleona_voice.a plus an iOS conformance executable. The
#           executable LINKS on the build machine but has to be run on a device;
#           see BUILD_REQUEST_V1.3.md §5 for what that costs and who can do it.
#
# ===========================================================================
# WHY TWO SOURCE FILES AND NOT ONE
# ===========================================================================
# §10.4 says iOS and macOS share "the same AudioUnit, one shared implementation"
# — and they do: cleona_voice_apple.c is the entire ABI, the VPIO instance, both
# mandatory properties, the rings and the verification report, built for both.
# What is NOT shared is the session/route layer: iOS has AVAudioSession (and it
# is Objective-C only), macOS has the CoreAudio HAL and no AVAudioSession at
# all. Exactly one of the two is compiled per target, chosen here rather than by
# a #if inside a single file, so an iOS build never has to parse CoreAudio HAL
# code and a macOS build never links AVFoundation for nothing.

if(NOT APPLE)
  # Not an error: native/cleona_voice/CMakeLists.txt adds every platform
  # subdirectory it finds, including on Linux, where this one has nothing to do.
  return()
endif()

option(CLEONA_VOICE_APPLE_BUILD_CONFORMANCE
       "Build the V0.4 conformance harness against the Apple backend" ON)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(CVA_IS_IOS TRUE)
else()
  set(CVA_IS_IOS FALSE)
endif()

if(CVA_IS_IOS)
  # AVAudioSession has no C API, so the session layer is Objective-C. The
  # parent project is declared `LANGUAGES C` (and belongs to V0.2), so OBJC is
  # enabled here, in the only scope that needs it. Same switch the superseded
  # native/cleona_audio/CMakeLists.txt needed on Apple, and the architecture
  # (§ "Besonderheit libcleona_audio") predicted this file would need it too.
  enable_language(OBJC)
  set(CVA_PLATFORM_SRC cleona_voice_apple_ios.m)
else()
  set(CVA_PLATFORM_SRC cleona_voice_apple_mac.c)
endif()

set(CVA_SOURCES cleona_voice_apple.c ${CVA_PLATFORM_SRC})

if(CLEONA_IOS_STATIC)
  # dart:ffi on iOS is DynamicLibrary.process() — everything is linked into the
  # Runner binary, so the backend has to be a static archive that
  # scripts/build-ios-libs.sh can merge (BUILD_REQUEST_V1.3.md §1).
  add_library(cleona_voice_apple STATIC ${CVA_SOURCES})
else()
  add_library(cleona_voice_apple SHARED ${CVA_SOURCES})
endif()

# The Dart loader looks for `cleona_voice` (VoiceNativeLibrary.platform()), and
# scripts/build-macos-libs.sh copies the dylib into Contents/Frameworks under
# that name. The CMake TARGET is cleona_voice_apple so it cannot collide with
# the Linux/Windows/Android targets in a build that configures several; the
# ARTEFACT is cleona_voice, because that is what has to be loadable.
set_target_properties(cleona_voice_apple PROPERTIES
                      OUTPUT_NAME cleona_voice
                      C_VISIBILITY_PRESET hidden)

target_link_libraries(cleona_voice_apple PUBLIC cleona_voice_abi)

if(CVA_IS_IOS)
  # ARC for the Objective-C translation unit only. The C files stay plain C;
  # the two bridge casts in cleona_voice_apple_ios.m (__bridge_retained /
  # __bridge_transfer for the notification observer token) are what let an
  # ARC-managed object be owned by a malloc'd C struct.
  set_source_files_properties(cleona_voice_apple_ios.m PROPERTIES
                              COMPILE_OPTIONS "-fobjc-arc")
  target_link_libraries(cleona_voice_apple PRIVATE
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework Foundation"
    "-framework CoreFoundation")
else()
  target_link_libraries(cleona_voice_apple PRIVATE
    "-framework AudioToolbox"
    "-framework CoreAudio"
    "-framework CoreFoundation")
endif()

# ---------------------------------------------------------------------------
# Conformance test (SPEC §10 gate 4 — "green ON THE TARGET PLATFORM").
#
# Link mode, as native/cleona_voice/test/CMakeLists.txt prescribes for a static
# backend. --shipping asserts what cleona_voice.h calls a valid release gate:
# a shipped backend never reports an id in the non-shipping range (>= 100).
# ---------------------------------------------------------------------------
if(CLEONA_VOICE_APPLE_BUILD_CONFORMANCE AND COMMAND cleona_voice_add_conformance_test)
  cleona_voice_add_conformance_test(cleona_voice_conformance_apple
                                    cleona_voice_apple --shipping)
  if(CVA_IS_IOS)
    # The binary links (which is the half of the check a build machine CAN
    # perform) but cannot be executed by ctest on the host — it is an iOS
    # Mach-O. Registering it and letting ctest report a green run would be a
    # test that looks like it ran; DISABLED says plainly that it did not.
    set_tests_properties(cleona_voice_conformance_apple PROPERTIES DISABLED TRUE)
  endif()
endif()
