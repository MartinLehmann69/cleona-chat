# CMakeLists for the WASAPI backend of cleona_voice.h — work package V1.4.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.4 — Windows-Voice-Backend
# (WASAPI)". Architecture: Cleona_Chat_Architecture_v3_0.md §10.4, §15.2.
#
# Picked up automatically by the parent ../CMakeLists.txt's platform loop
# (`foreach(_plat linux android apple windows) ... add_subdirectory`) -- that
# file is V0.4/build-owner territory and was NOT edited to add this; the loop
# already looks for exactly this path.
#
# Output name is deliberately "cleona_voice" (PREFIX ""), matching the naming
# table in ../CMakeLists.txt ("real -> libcleona_voice.so / cleona_voice.dll")
# and what BUILD_REQUEST_V1.4.md asks windows/runner/CMakeLists.txt (owned by
# the build owner, not this package) to bundle next to cleona.exe.

cmake_minimum_required(VERSION 3.13)

if(NOT WIN32)
  return()
endif()

add_library(cleona_voice_windows SHARED cleona_voice_windows.c)
target_link_libraries(cleona_voice_windows PUBLIC cleona_voice_abi)

# Ole32: CoInitializeEx/CoCreateInstance/CoTaskMemFree/PropVariantClear.
# No other import lib needed -- IMMDeviceEnumerator, IAudioClient2 and friends
# are obtained purely through COM activation, not linked entry points.
target_link_libraries(cleona_voice_windows PRIVATE ole32)

set_target_properties(cleona_voice_windows PROPERTIES
                       PREFIX ""
                       OUTPUT_NAME "cleona_voice")

# ---------------------------------------------------------------------------
# Conformance test, link mode (SPEC §10 gate 4: "green on the target
# platform"). Registered with ctest by native/cleona_voice/test/CMakeLists.txt
# via the function it defines -- see that file's own doc comment for why link
# mode is available even though this package's real acceptance run in
# BUILD_REQUEST_V1.4.md's absence uses the loader binary against the built DLL.
# ---------------------------------------------------------------------------
if(TARGET cleona_voice_conformance_loader)
  cleona_voice_add_conformance_test(cleona_voice_conformance_windows cleona_voice_windows)
endif()
