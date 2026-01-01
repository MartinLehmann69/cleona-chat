# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "cleona")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "chat.cleona.cleona")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# === cleona_net shim (libcleona_net.so) ===
# Direct-syscall UDP send-path — see Cleona_Chat_Architecture_v3_0.md §4.5.2.
# Built here, installed below into bundle/lib/ after the Flutter bundle wipe.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_net" "${CMAKE_BINARY_DIR}/cleona_net_build")

# === libopus (audio codec, V1.8/V1.9) ===
# Built from the pinned Xiph upstream source — same LIBOPUS_VERSION as
# scripts/build-android-libs.sh / scripts/build-ios-libs.sh /
# scripts/build-macos-libs.sh / windows/provision-opus.ps1. One version across
# all five platforms is deliberate, same reasoning as
# windows/provision-liboqs.ps1's version-drift comment: opus_ffi.dart (V1.9)
# talks Opus with a peer over the wire, and a version drift there is a
# correctness risk, not a cosmetic packaging detail.
#
# Deliberately NOT a system libopus-dev dependency the way libsodium is
# (native/cleona_pow/CMakeLists.txt's find_library(SODIUM_LIB ...)): a distro
# package is whatever that distro happens to ship, not a pin, and the other
# four platforms already build this exact tag from source (see
# scripts/build-ios-libs.sh's build_libopus(), the template for all three
# platforms this package adds).
#
# FetchContent clones the tag into CMAKE_BINARY_DIR/_deps only on the FIRST
# configure of a given build/ directory — a rebuild in the same tree needs no
# network. A fresh `flutter clean` (or a first build in a new worktree) does
# need network access for this one dependency; every other Linux dependency in
# this file (GTK, libpipewire, webrtc-audio-processing) already comes from the
# system and needs none.
include(FetchContent)
set(CLEONA_OPUS_VERSION "1.5.2")
set(OPUS_BUILD_SHARED_LIBRARY ON CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(cleona_opus_src
    GIT_REPOSITORY https://github.com/xiph/opus.git
    GIT_TAG        "v${CLEONA_OPUS_VERSION}"
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(cleona_opus_src)
# opus_ffi.dart (V1.9) loads libopus.so by symbol name via dart:ffi — it needs
# no C header at runtime. Clearing PUBLIC_HEADER makes that explicit and
# silences a CMake dev warning ("Target opus has PUBLIC_HEADER files but no
# PUBLIC_HEADER DESTINATION") from the plain install(TARGETS opus ...) below,
# which installs LIBRARY only on purpose.
set_target_properties(opus PROPERTIES PUBLIC_HEADER "")

# === cleona_voice (libcleona_voice.so) — V1.1, PipeWire ===
# Built from native/cleona_voice/, installed into bundle/lib/ for FFI loading.
# Same install pattern as cleona_net: the install(TARGETS)
# directive lives further down, after the bundle REMOVE_RECURSE block.
# CLEONA_VOICE_BUILD_MOCK is intentionally left at its default (ON): Check 15
# (scripts/preflight.sh) only forbids REFERENCING the mock target from a
# production build file (below, nothing names `cleona_voice_mock`), and the
# mock target still needs to exist for native/cleona_voice/test's conformance
# harness (built as a subdirectory of the same CMake tree) to have something
# to link against in link mode (native/cleona_voice/BUILD_REQUEST_V1.1.md §1).
set(CLEONA_VOICE_BUILD_SMOKE OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_voice" "${CMAKE_BINARY_DIR}/cleona_voice_build")

# === cleona_video — NOT wired in yet, deliberately ===
# docs/SPEC_VOICE_VIDEO_REWORK.md V0.5 (build ownership) +
# native/cleona_video/BUILD_REQUEST.md.
#
# Only a hardware-free mock exists today (native/cleona_video/mock) — there is
# no real Linux backend to bundle yet. Wiring `add_subdirectory` in here now
# would have exactly one available target to install: the mock, which answers
# every call with a synthetic bitstream and must never reach a release build
# (native/cleona_video/BUILD_REQUEST.md §5). scripts/preflight.sh Check "Mock
# backend not in production build wiring" enforces that this file stays clean
# of `cleona_video_mock` until then.
#
# Wire this up when the real backend lands, not before, same shape as
# cleona_voice above:
#   video (V1.13, VA-API/V4L2 M2M): add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_video" "${CMAKE_BINARY_DIR}/cleona_video_build")
#                            install the `cleona_video` target (NOT `cleona_video_mock`)
#                            into ${INSTALL_BUNDLE_LIB_DIR}, same pattern as cleona_net below.
# See native/cleona_video/BUILD_REQUEST.md §2 for the exact snippet and the
# CMake options (CLEONA_VIDEO_BUILD_MOCK / BUILD_SMOKE) a production build
# must turn OFF.

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# cleona_net shim — installed after the bundle wipe above so the .so lands in
# bundle/lib/ next to libapp.so (RPATH $ORIGIN/lib resolves it for FFI).
install(TARGETS cleona_net LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# libopus — same install pattern as cleona_net.
install(TARGETS opus LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# cleona_voice — same install pattern as cleona_net.
install(TARGETS cleona_voice LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
