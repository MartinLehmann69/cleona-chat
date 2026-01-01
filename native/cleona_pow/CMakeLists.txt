# libcleona_pow — PoW SHA-256 iteration loop in C.
#
# Build (Linux):
#   cmake -B build -S .
#   cmake --build build --config Release
#
# Build (Windows, MSVC):
#   cmake -B build -S . -A x64
#   cmake --build build --config Release
#
# Build (iOS — static, linked into libcleona_all.a):
#   cmake -GNinja -DCMAKE_SYSTEM_NAME=iOS ...
#
# Build (Android — shared, NDK toolchain):
#   cmake -GNinja -DCMAKE_TOOLCHAIN_FILE=<ndk>/android.toolchain.cmake ...

cmake_minimum_required(VERSION 3.13)

project(cleona_pow
        VERSION 1.0.0
        LANGUAGES C
        DESCRIPTION "Cleona PoW SHA-256 iteration loop (links libsodium)")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT MSVC)
  add_compile_options(-fvisibility=hidden -Wall -Wextra -Wpedantic -O3)
endif()

# iOS requires static libraries (no custom dylibs allowed).
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(cleona_pow STATIC cleona_pow.c)
else()
  add_library(cleona_pow SHARED cleona_pow.c)
endif()

find_library(SODIUM_LIB NAMES sodium libsodium)
if(NOT SODIUM_LIB)
  message(FATAL_ERROR "libsodium not found — install libsodium-dev or set SODIUM_LIB")
endif()
target_link_libraries(cleona_pow PRIVATE ${SODIUM_LIB})

# sodium.h
find_path(SODIUM_INCLUDE sodium.h)
if(SODIUM_INCLUDE)
  target_include_directories(cleona_pow PRIVATE ${SODIUM_INCLUDE})
endif()

if(WIN32)
  set_target_properties(cleona_pow PROPERTIES PREFIX "")
endif()

if(UNIX AND NOT APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set_target_properties(cleona_pow PROPERTIES
                        VERSION ${PROJECT_VERSION}
                        SOVERSION 1)
endif()
