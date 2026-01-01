# Vendored speexdsp 1.2.1 — used by cleona_audio shim for AEC + NS.
# Built as a static library so the resulting libcleona_audio.so is fully
# self-contained (no external libspeexdsp.so dependency).
#
# Source: https://github.com/xiph/speexdsp (tag SpeexDSP-1.2.1)
# Tarball SHA256: d17ca363654556a4ff1d02cc13d9eb1fc5a8642c90b40bd54ce266c3807b91a7
# License: BSD-style (see COPYING in this directory)

cmake_minimum_required(VERSION 3.13)
project(speexdsp_vendor C)

add_library(speexdsp STATIC
  libspeexdsp/preprocess.c
  libspeexdsp/mdf.c
  libspeexdsp/fftwrap.c
  libspeexdsp/filterbank.c
  libspeexdsp/resample.c
  libspeexdsp/buffer.c
  libspeexdsp/scal.c
  libspeexdsp/jitter.c
  libspeexdsp/kiss_fft.c
  libspeexdsp/kiss_fftr.c
  libspeexdsp/smallft.c
)

target_compile_definitions(speexdsp PRIVATE
  HAVE_CONFIG_H=1
)

target_include_directories(speexdsp
  PUBLIC
    ${CMAKE_CURRENT_LIST_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/libspeexdsp
)

# We're getting linked into libcleona_audio.so (a SHARED lib), so the static
# objects need to be position-independent.
set_target_properties(speexdsp PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  C_VISIBILITY_PRESET hidden
)

# Vendored upstream sources have a few unused-result and old-style declarations
# we don't want to babysit. Silence them but keep real warnings.
if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  target_compile_options(speexdsp PRIVATE
    -Wno-unused-result
    -Wno-unused-but-set-variable
    -Wno-unused-variable
    -Wno-unused-function
    -Wno-implicit-function-declaration
    -Wno-maybe-uninitialized
  )
elseif(CMAKE_C_COMPILER_ID MATCHES "Clang")
  target_compile_options(speexdsp PRIVATE
    -Wno-unused-result
    -Wno-unused-but-set-variable
    -Wno-unused-variable
    -Wno-unused-function
    -Wno-implicit-function-declaration
    -Wno-uninitialized
  )
endif()

# Math library on POSIX
if(UNIX)
  target_link_libraries(speexdsp PUBLIC m)
endif()
