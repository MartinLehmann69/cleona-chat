# Linux backend for cleona_video.h — work package V1.13.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.13-V1.16 — Video-Backends".
# Architecture: Cleona_Chat_Architecture_v3_0.md §10.6.
#
# STATUS: WORK IN PROGRESS, not yet acceptance-complete. See
# BUILD_REQUEST_V1.13.md in native/cleona_video/ (one level up — same
# placement precedent as native/cleona_voice/BUILD_REQUEST_V1.1.md) for the
# exact state, what remains, and what the next session needs to know before
# touching this package. Do not treat a green build of this CMakeLists.txt as
# proof the backend is accepted — it is not.
#
# native/cleona_video/CMakeLists.txt does NOT yet have the platform-loop that
# native/cleona_voice/CMakeLists.txt has (V0.4's test/BUILD_REQUEST.md §1 asks
# V0.5 for it, still open) — so this directory is not picked up automatically.
# Build standalone, matching test/CMakeLists.txt route (A):
#
#   cmake -S native/cleona_video/linux -B build/video_linux
#   cmake --build build/video_linux
#   cmake -S native/cleona_video -B build/video && cmake --build build/video -j
#   ./build/video/test/cleona_video_conformance_loader \
#       build/video_linux/libcleona_video.so --shipping
#
# DEPENDENCIES (not yet installable via apt in this sandbox — see
# BUILD_REQUEST_V1.13.md for how this was worked around locally):
#   libva, libva-drm (VAAPI — Video Acceleration API core + DRM backend)
#   Linux kernel headers for V4L2 (linux/videodev2.h — part of the standard
#   libc-dev toolchain on any real dev machine, no extra package needed)

cmake_minimum_required(VERSION 3.13)

# ---------------------------------------------------------------------------
# Host guard — same reasoning and same fix as
# native/cleona_voice/linux/CMakeLists.txt: native/cleona_video/CMakeLists.txt
# does not (yet) have a platform loop to guard this from an Android
# cross-build, but V1.14 (Android) will one day sit next to this directory, so
# the guard is added defensively now rather than discovered as a configure
# failure later. `ANDROID`, not `NOT UNIX` — see the voice package's own
# comment for why the obvious guard is wrong.
# ---------------------------------------------------------------------------
if(NOT UNIX OR ANDROID OR APPLE)
  return()
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(CLEONA_VA     REQUIRED IMPORTED_TARGET libva)
pkg_check_modules(CLEONA_VA_DRM REQUIRED IMPORTED_TARGET libva-drm)

add_library(cleona_video SHARED
    cleona_video_linux.c
    h264_bitstream.c
    v4l2_capture.c
)

target_link_libraries(cleona_video PRIVATE
    PkgConfig::CLEONA_VA
    PkgConfig::CLEONA_VA_DRM
    pthread
    m
)

set_target_properties(cleona_video PROPERTIES
    C_VISIBILITY_PRESET hidden
)

if(NOT MSVC)
  target_compile_options(cleona_video PRIVATE -Wall -Wextra)
endif()

# ---------------------------------------------------------------------------
# Conformance test (SPEC gate: "green on the target platform"). Registered the
# same way native/cleona_voice/linux/CMakeLists.txt registers its own —
# guarded by the function existing, so this file configures standalone too.
# ---------------------------------------------------------------------------
if(COMMAND cleona_video_add_conformance_test)
  cleona_video_add_conformance_test(cleona_video_conformance_linux cleona_video --shipping)
endif()
