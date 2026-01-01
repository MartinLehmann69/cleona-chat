# CMakeLists for libcleona_net.
#
# Outputs:
#   Linux:   libcleona_net.so
#   Windows: cleona_net.dll
#
# Build (Linux):
#   cmake -B build -S .
#   cmake --build build --config Release
#   ls build/libcleona_net.so
#
# Build (Windows, MSVC via Visual Studio Build Tools):
#   cmake -B build -S . -A x64
#   cmake --build build --config Release
#   ls build/Release/cleona_net.dll
#
# See native/cleona_net/README.md for deployment paths.

cmake_minimum_required(VERSION 3.13)

project(cleona_net
        VERSION 1.0.0
        LANGUAGES C
        DESCRIPTION "Cleona direct-syscall UDP send-path shim")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Hide non-exported symbols. The header's CLEONA_NET_EXPORT macro promotes
# the four public functions to default visibility, everything else stays
# library-private.
if(NOT MSVC)
  add_compile_options(-fvisibility=hidden -Wall -Wextra -Wpedantic)
endif()

add_library(cleona_net SHARED
            src/cleona_net.c)

target_include_directories(cleona_net PUBLIC include)

if(WIN32)
  # WinSock2 is needed; ws2_32 link is also forced via pragma in cleona_net.c
  # for MSVC, but we set it explicitly here as well so MinGW builds work.
  target_link_libraries(cleona_net PRIVATE ws2_32)
  # Strip the "lib" prefix so the output is cleona_net.dll (not libcleona_net.dll)
  set_target_properties(cleona_net PROPERTIES PREFIX "")
endif()

# Linux: ensure soname so dlopen finds the file by its short name
if(UNIX AND NOT APPLE)
  set_target_properties(cleona_net PROPERTIES
                        VERSION ${PROJECT_VERSION}
                        SOVERSION 1)
endif()
