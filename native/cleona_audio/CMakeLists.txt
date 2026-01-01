cmake_minimum_required(VERSION 3.13)
project(cleona_audio C)

# Find SpeexDSP via pkg-config (Linux preferred) or vendored fallback
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")
find_package(SpeexDSP REQUIRED)

add_library(cleona_audio SHARED
  cleona_audio.c
  cleona_audio_ring.c
  miniaudio_impl.c
)

target_include_directories(cleona_audio PRIVATE
  ${CMAKE_CURRENT_LIST_DIR}
  ${SPEEXDSP_INCLUDE_DIRS}
)

target_link_libraries(cleona_audio PRIVATE
  ${SPEEXDSP_LIBRARIES}
)

# Linux: link pthread, math, dl
if(UNIX AND NOT APPLE AND NOT ANDROID)
  target_link_libraries(cleona_audio PRIVATE pthread m dl)
endif()

# Windows: WASAPI is via ole32 + winmm. MSVC needs /std:c17 (or /std:c11 with
# /experimental:c11atomics) for <stdatomic.h> support — cleona_audio_ring.c
# uses atomic_store/atomic_load/atomic_fetch_add. /std:c17 enables them by
# default on VS 2022 17.5+; older toolchains need the experimental flag.
# We pass both for portability across MSVC versions.
if(WIN32)
  target_link_libraries(cleona_audio PRIVATE ole32 winmm)
  if(MSVC)
    target_compile_options(cleona_audio PRIVATE /std:c17 /experimental:c11atomics)
  endif()
endif()

set_target_properties(cleona_audio PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
  C_VISIBILITY_PRESET hidden
)
