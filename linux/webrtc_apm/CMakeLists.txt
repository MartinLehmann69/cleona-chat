# =============================================================================
# linux/webrtc_apm — webrtc-audio-processing 1.3 (AEC3) from the pinned source
# =============================================================================
#
# WHY (S410, S410-I6-MESSUNG.md finding 2, owner decision B 29.10.2026):
# libcleona_voice.so's fallback chain (v4_2 §17.5: "Linux via PipeWire duplex
# with the echo-cancel module, or failing that, a directly linked WebRTC APM")
# was linked against the SYSTEM webrtc-audio-processing 0.3.1. No system
# version is common to the distributions Cleona targets — measured 29.10.2026:
#   * Ubuntu 24.04: only 0.3.1 (`libwebrtc-audio-processing1`, soname
#     libwebrtc_audio_processing.so.1, the legacy component API)
#   * Ubuntu 26.04: only 1.3 (`libwebrtc-audio-processing-1-3`, soname
#     libwebrtc-audio-processing-1.so.3, the AEC3 API)
# so libcleona_voice.so did not load on 26.04 at all and the .deb was not
# installable there. Decision B: the fallback binds the 1.x (AEC3) API, built
# here from one pinned source and shipped inside the bundle.
#
# WHAT THIS PROJECT PRODUCES: a STATIC libwebrtc-audio-processing-1.a (with
# its abseil objects) and its headers under CLEONA_WEBRTC_APM_PREFIX. It is
# linked into exactly one shared object, libcleona_voice_apm.so
# (native/cleona_voice/linux/CMakeLists.txt), which exports nothing but the
# C functions of voice_apm_shim.h. Static, so that the bundle carries ONE
# file, no soname of its own collides with a system copy that PipeWire's own
# echo-cancel plugin may load into the same process, and no system
# webrtc/abseil package is needed at run time.
#
# THE PIN:
#   https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-1.3.tar.xz
#   SHA-256 2365e93e778d7b61b5d6e02d21c47d97222e9c7deff9e1d0838ad6ec2e86f1b9
#   = the checksum freedesktop publishes next to it
#   (…/webrtc-audio-processing-1.3.tar.xz.sha256sum, read 29.10.2026).
#   1.3 is the version Ubuntu 26.04 ships (`libwebrtc-audio-processing-1-3`
#   1.3-3build2) and Debian trixie/sid (1.3-3). A changed archive fails the
#   download (URL_HASH), it is never built.
#
# ABSEIL: 1.3 needs abseil-cpp. Its meson.build takes it from pkg-config if
# the build host has libabsl-dev, else from its own wrap
# (subprojects/abseil-cpp.wrap: abseil 20230125.1, source_hash 81311c17…ed145,
# patch_hash 112ee720…6610d — part of the hashed archive above, and meson
# refuses a download whose hash differs: mesonbuild/wrap/wrap.py check_hash,
# "Incorrect hash for …"). `--force-fallback-for=abseil-cpp` always takes the
# wrap, so the result does not depend on what the build host has installed.
#
# MESON: the upstream build is meson (>= 0.63). meson is pure Python and runs
# from its release archive (`python3 meson.py`), so it is fetched pinned like
# every other input instead of being installed on the build host:
#   https://github.com/mesonbuild/meson/releases/download/1.4.2/meson-1.4.2.tar.gz
#   SHA-256 ea2546a26f4a171a741c1fd036f22c9c804d6198e3259f1df588e01f842dd69f
#   = the sha256 PyPI lists for meson-1.4.2.tar.gz (pypi.org/pypi/meson/1.4.2/json,
#   read 29.10.2026). Needs python3 >= 3.7 (setup.cfg python_requires) and
#   ninja, which the Flutter Linux build needs anyway; meson finds ninja via
#   the NINJA environment variable (mesonbuild/environment.py).
#
# CPU: x86_64 AVX2 code paths are compiled in and chosen at run time
# (meson.build of 1.3: "actual usage is determined by runtime CPU
# detection"), so the build machine's CPU does not leak into the result.
#
# Network: the first configure of a fresh build directory downloads meson,
# webrtc-audio-processing and abseil (like linux/liboqs); a rebuild in the
# same directory needs none. Measured 29.10.2026 on the workstation (16
# threads): ~40 s.
cmake_minimum_required(VERSION 3.16)
project(cleona_webrtc_apm LANGUAGES NONE)

include(ExternalProject)
find_package(Python3 3.7 COMPONENTS Interpreter REQUIRED)
find_program(CLEONA_NINJA NAMES ninja ninja-build REQUIRED)

set(CLEONA_MESON_VERSION "1.4.2")
set(CLEONA_MESON_SHA256 "ea2546a26f4a171a741c1fd036f22c9c804d6198e3259f1df588e01f842dd69f")
set(CLEONA_WEBRTC_APM_VERSION "1.3")
set(CLEONA_WEBRTC_APM_SHA256 "2365e93e778d7b61b5d6e02d21c47d97222e9c7deff9e1d0838ad6ec2e86f1b9")

set(CLEONA_MESON_DIR "${CMAKE_CURRENT_BINARY_DIR}/meson-src")
set(CLEONA_WEBRTC_APM_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/webrtc-apm-install"
    CACHE PATH "webrtc-audio-processing built from the pinned source (install prefix)" FORCE)
set(CLEONA_WEBRTC_APM_LIBRARY "${CLEONA_WEBRTC_APM_PREFIX}/lib/libwebrtc-audio-processing-1.a"
    CACHE FILEPATH "static webrtc-audio-processing-1 (with abseil)" FORCE)

ExternalProject_Add(cleona_meson
  URL               "https://github.com/mesonbuild/meson/releases/download/${CLEONA_MESON_VERSION}/meson-${CLEONA_MESON_VERSION}.tar.gz"
  URL_HASH          "SHA256=${CLEONA_MESON_SHA256}"
  DOWNLOAD_NO_PROGRESS TRUE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  SOURCE_DIR        "${CLEONA_MESON_DIR}"
  CONFIGURE_COMMAND ""
  BUILD_COMMAND     ""
  INSTALL_COMMAND   ""
)

# The compilers of the surrounding build (clang under `flutter build linux`,
# the host default for a standalone build) — one compiler for the shim and the
# library it links statically.
if(CMAKE_C_COMPILER AND CMAKE_CXX_COMPILER)
  set(_cleona_cc "CC=${CMAKE_C_COMPILER}" "CXX=${CMAKE_CXX_COMPILER}")
else()
  set(_cleona_cc "")
endif()

ExternalProject_Add(cleona_webrtc_apm
  DEPENDS           cleona_meson
  URL               "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-${CLEONA_WEBRTC_APM_VERSION}.tar.xz"
  URL_HASH          "SHA256=${CLEONA_WEBRTC_APM_SHA256}"
  DOWNLOAD_NO_PROGRESS TRUE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${_cleona_cc} "NINJA=${CLEONA_NINJA}"
                    ${Python3_EXECUTABLE} ${CLEONA_MESON_DIR}/meson.py setup
                    <BINARY_DIR> <SOURCE_DIR>
                    --prefix=${CLEONA_WEBRTC_APM_PREFIX} --libdir=lib
                    --buildtype=release --default-library=static
                    -Db_staticpic=true --force-fallback-for=abseil-cpp
  BUILD_COMMAND     ${CMAKE_COMMAND} -E env "NINJA=${CLEONA_NINJA}"
                    ${Python3_EXECUTABLE} ${CLEONA_MESON_DIR}/meson.py compile -C <BINARY_DIR>
  INSTALL_COMMAND   ${CMAKE_COMMAND} -E env "NINJA=${CLEONA_NINJA}"
                    ${Python3_EXECUTABLE} ${CLEONA_MESON_DIR}/meson.py install -C <BINARY_DIR> --quiet
  BUILD_BYPRODUCTS  "${CLEONA_WEBRTC_APM_LIBRARY}"
)
