# cleona-play.exe -- the sound player the Windows daemon starts per sound
# (see cleona_play.c). Builds standalone
#   cmake -S windows/cleona_play -B <dir> && cmake --build <dir> --config Release
# and as a subdirectory of windows/CMakeLists.txt, which installs the program
# next to cleona.exe.
#
# Lives under windows/ and not under native/: the preflight checks 8a and 14b
# derive "must exist as lib<name>.so on Android" and "must be a DLL in
# EXPECTED_DLLS" from native/*/CMakeLists.txt, and neither holds for a Windows
# helper program. Its presence in the bundle is checked by
# windows/verify_bundle_dlls.cmake (-DEXPECTED_PROGRAMS).
cmake_minimum_required(VERSION 3.14)
project(cleona_play LANGUAGES C)

include(FetchContent)

# Decoder sources, pinned to the COMMIT the release tag points at -- a tag can
# be moved, a commit id cannot. Read with `git ls-remote --tags` on 02.10.2026:
#   xiph/ogg     v1.3.6 -> be05b13e98b048f0b5a0f5fa8ce514d56db5f822
#   xiph/vorbis  v1.3.7 -> 0657aee69dec8508a0011f47f3b69d7538e9d262
# Cloned into <build>/_deps on the FIRST configure of a build directory only,
# like libopus in linux/CMakeLists.txt.
#
# SOURCE_SUBDIR names a directory that does not exist on purpose: the sources
# are fetched, but the upstream CMakeLists.txt files are NOT run. They would
# add install rules, an encoder library and a find_package(Ogg) that looks for
# an installed libogg. The few files the decoder needs are listed below.
FetchContent_Declare(cleona_ogg_src
    GIT_REPOSITORY https://github.com/xiph/ogg.git
    GIT_TAG        be05b13e98b048f0b5a0f5fa8ce514d56db5f822
    SOURCE_SUBDIR  cleona-does-not-run-upstream-cmake
)
FetchContent_Declare(cleona_vorbis_src
    GIT_REPOSITORY https://github.com/xiph/vorbis.git
    GIT_TAG        0657aee69dec8508a0011f47f3b69d7538e9d262
    SOURCE_SUBDIR  cleona-does-not-run-upstream-cmake
)
FetchContent_MakeAvailable(cleona_ogg_src cleona_vorbis_src)

set(_ogg "${cleona_ogg_src_SOURCE_DIR}")
set(_vorbis "${cleona_vorbis_src_SOURCE_DIR}")

# libvorbis without vorbisenc.c: the list of lib/CMakeLists.txt at the pin.
# The analysis files stay in because block.c and mapping0.c reference them;
# the linker drops what the decode path does not reach.
add_library(cleona_vorbis_decoder STATIC
    "${_ogg}/src/bitwise.c"
    "${_ogg}/src/framing.c"
    "${_vorbis}/lib/mdct.c"
    "${_vorbis}/lib/smallft.c"
    "${_vorbis}/lib/block.c"
    "${_vorbis}/lib/envelope.c"
    "${_vorbis}/lib/window.c"
    "${_vorbis}/lib/lsp.c"
    "${_vorbis}/lib/lpc.c"
    "${_vorbis}/lib/analysis.c"
    "${_vorbis}/lib/synthesis.c"
    "${_vorbis}/lib/psy.c"
    "${_vorbis}/lib/info.c"
    "${_vorbis}/lib/floor1.c"
    "${_vorbis}/lib/floor0.c"
    "${_vorbis}/lib/res0.c"
    "${_vorbis}/lib/mapping0.c"
    "${_vorbis}/lib/registry.c"
    "${_vorbis}/lib/codebook.c"
    "${_vorbis}/lib/sharedbook.c"
    "${_vorbis}/lib/lookup.c"
    "${_vorbis}/lib/bitrate.c"
    "${_vorbis}/lib/vorbisfile.c"
)
target_include_directories(cleona_vorbis_decoder
    PUBLIC  "${_ogg}/include" "${_vorbis}/include"
    PRIVATE "${_vorbis}/lib"
)

if(NOT WIN32)
  # ogg/os_types.h defines its integer types itself on Windows and includes a
  # generated <ogg/config_types.h> everywhere else. The upstream build
  # generates that file; here it is written for the check build.
  set(_gen "${CMAKE_CURRENT_BINARY_DIR}/generated")
  file(WRITE "${_gen}/ogg/config_types.h"
"#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__
#include <stdint.h>
typedef int16_t ogg_int16_t;
typedef uint16_t ogg_uint16_t;
typedef int32_t ogg_int32_t;
typedef uint32_t ogg_uint32_t;
typedef int64_t ogg_int64_t;
typedef uint64_t ogg_uint64_t;
#endif
")
  target_include_directories(cleona_vorbis_decoder PUBLIC "${_gen}")
  target_link_libraries(cleona_vorbis_decoder PUBLIC m)
endif()

# Foreign sources: the compiler's default warning level, never warnings as
# errors -- a new compiler version must not break the build over code this
# project does not maintain.
if(MSVC)
  target_compile_options(cleona_vorbis_decoder PRIVATE /W3)
  target_compile_definitions(cleona_vorbis_decoder PRIVATE
      _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_DEPRECATE)
endif()

# WIN32: Windows subsystem, entry WinMain -- no console window per sound.
add_executable(cleona-play WIN32 cleona_play.c)
target_link_libraries(cleona-play PRIVATE cleona_vorbis_decoder)
if(MSVC)
  # Own code: /W4 and warnings as errors, like the runner.
  target_compile_options(cleona-play PRIVATE /W4 /WX)
  target_compile_definitions(cleona-play PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_link_libraries(cleona-play PRIVATE winmm shell32)
else()
  target_compile_options(cleona-play PRIVATE -Wall -Wextra -Werror)
endif()
