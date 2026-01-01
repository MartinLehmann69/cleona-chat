# libcleona_pow — PoW SHA-256 iteration loop in C.
#
# Build (Linux):
#   cmake -B build -S .
#   cmake --build build --config Release
#
# Build (Windows, MSVC):
#   cmake -B build -S . -A x64
#   cmake --build build --config Release
#   The libsodium import library is provisioned automatically; to do it up front
#   or to a fixed location:
#     powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-libsodium.ps1
#     cmake -B build -S . -A x64 -DSODIUM_ROOT=<...>/libsodium-1.0.20-stable-msvc/libsodium
#   Normally not built standalone — windows/runner/CMakeLists.txt pulls this in
#   via add_subdirectory during `flutter build windows`.
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

# ── libsodium ────────────────────────────────────────────────────────────────
# cleona_pow.c uses exactly one libsodium symbol (crypto_hash_sha256). It has to
# come from libsodium: replacing it with a hand-written SHA-256 would swap the
# project's crypto provider (docs/CRYPTO.md) to solve a packaging problem.
#
# MSVC does not link against a DLL, it links against the import library (.lib)
# that is produced alongside it. find_library() therefore never succeeds on
# Windows — the machine only has libsodium.dll — and the FATAL_ERROR below used
# to abort the configure step. That is why cleona_pow.dll was missing from every
# Windows build and the Dart PoW fallback ran instead (~561 ms at difficulty 20
# versus <10 ms native).
#
# The MSVC branch resolves the official pre-built package, provisioning it on
# demand exactly like scripts/build-android-libs.sh clones libsodium and
# scripts/build-macos-libs.sh downloads the pinned tarball.
if(MSVC AND NOT SODIUM_LIB)

  # 1) Locate the package root (the "libsodium" directory inside the archive).
  set(_cp_root "")
  if(SODIUM_ROOT)
    set(_cp_root "${SODIUM_ROOT}")
  elseif(DEFINED ENV{SODIUM_ROOT})
    set(_cp_root "$ENV{SODIUM_ROOT}")
  endif()

  set(_cp_libs_dir "$ENV{CLEONA_LIBS_DIR}")
  if(NOT _cp_libs_dir)
    set(_cp_libs_dir "$ENV{LOCALAPPDATA}/cleona-libs")
  endif()
  file(TO_CMAKE_PATH "${_cp_libs_dir}" _cp_libs_dir)

  # Provisioning script lives with the Windows shell because it also supplies
  # the libsodium.dll that windows/runner/CMakeLists.txt ships in the bundle.
  set(_cp_provision "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/provision-libsodium.ps1")

  function(_cp_find_package_root outvar)
    file(GLOB _cands "${_cp_libs_dir}/libsodium-*-stable-msvc/libsodium")
    list(SORT _cands)
    set(_hit "")
    foreach(_c ${_cands})
      if(EXISTS "${_c}/include/sodium.h")
        set(_hit "${_c}")   # sorted glob: last match wins = highest version
      endif()
    endforeach()
    set(${outvar} "${_hit}" PARENT_SCOPE)
  endfunction()

  if(NOT _cp_root)
    _cp_find_package_root(_cp_root)
  endif()

  option(CLEONA_AUTO_PROVISION
         "Download the pinned libsodium MSVC package when it is missing" ON)

  if(NOT _cp_root AND CLEONA_AUTO_PROVISION AND EXISTS "${_cp_provision}")
    message(STATUS "cleona_pow: libsodium MSVC package missing — provisioning into ${_cp_libs_dir}")
    execute_process(
      COMMAND powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass
              -File "${_cp_provision}" -Root "${_cp_libs_dir}"
      RESULT_VARIABLE _cp_rc
      OUTPUT_VARIABLE _cp_out
      ERROR_VARIABLE  _cp_err)
    if(NOT _cp_rc EQUAL 0)
      message(WARNING "cleona_pow: provisioning failed (exit ${_cp_rc}):\n${_cp_out}\n${_cp_err}")
    endif()
    _cp_find_package_root(_cp_root)
  endif()

  if(NOT _cp_root)
    message(FATAL_ERROR
      "libsodium MSVC package not found.\n"
      "  Run:  powershell -NoProfile -ExecutionPolicy Bypass -File "
      "windows\\provision-libsodium.ps1\n"
      "  Or point SODIUM_ROOT at an extracted libsodium-<ver>-stable-msvc/libsodium "
      "directory (-DSODIUM_ROOT=... or environment variable).")
  endif()

  # 2) Architecture directory. The archive names them exactly like MSVC's
  #    generator platform (x64 / Win32 / ARM64).
  if(CMAKE_GENERATOR_PLATFORM)
    set(_cp_arch "${CMAKE_GENERATOR_PLATFORM}")
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(_cp_arch "x64")
  else()
    set(_cp_arch "Win32")
  endif()

  # 3) Toolset directory. The package ships one directory per MSVC toolset
  #    (currently v142 and v143); which ones exist changes with every libsodium
  #    release, so this must not be hardcoded. Pick the newest one that is not
  #    newer than the compiler in use: MSVC toolsets are binary compatible
  #    forwards (v142 objects link into a v143 build), not backwards.
  set(_cp_relbase "${_cp_root}/${_cp_arch}/Release")
  if(NOT IS_DIRECTORY "${_cp_relbase}")
    message(FATAL_ERROR "cleona_pow: ${_cp_relbase} does not exist — "
                        "package has no ${_cp_arch} build.")
  endif()
  file(GLOB _cp_tsdirs RELATIVE "${_cp_relbase}" "${_cp_relbase}/v*")
  set(_cp_want "${MSVC_TOOLSET_VERSION}")   # e.g. 143; empty on odd generators
  if(NOT _cp_want MATCHES "^[0-9]+$")
    set(_cp_want 99999)   # unknown compiler toolset: accept the newest present
  endif()
  set(_cp_best 0)
  foreach(_t ${_cp_tsdirs})
    if(IS_DIRECTORY "${_cp_relbase}/${_t}")
      string(REGEX REPLACE "^v" "" _tn "${_t}")
      if(_tn MATCHES "^[0-9]+$")
        if(NOT _tn GREATER _cp_want)      # not newer than the compiler
          if(_tn GREATER _cp_best)
            set(_cp_best "${_tn}")
          endif()
        endif()
      endif()
    endif()
  endforeach()
  if(_cp_best EQUAL 0)
    set(_cp_best "")
  endif()
  if(NOT _cp_best)
    message(FATAL_ERROR
      "cleona_pow: no usable toolset in ${_cp_relbase} "
      "(found '${_cp_tsdirs}', compiler toolset v${_cp_want}). "
      "Update the pinned libsodium version in windows/provision-libsodium.ps1.")
  endif()

  # 4) Always the Release/dynamic variant: that is the DLL the app ships, and
  #    the import library must belong to it. The Debug variant links the debug
  #    CRT and would drag msvcp140d.dll into user machines.
  set(_cp_dyn "${_cp_relbase}/v${_cp_best}/dynamic")
  set(SODIUM_LIB     "${_cp_dyn}/libsodium.lib" CACHE FILEPATH "libsodium import library" FORCE)
  set(SODIUM_INCLUDE "${_cp_root}/include"      CACHE PATH     "libsodium headers"        FORCE)
  set(CLEONA_SODIUM_DLL "${_cp_dyn}/libsodium.dll"
      CACHE FILEPATH "libsodium runtime DLL matching SODIUM_LIB" FORCE)

  if(NOT EXISTS "${SODIUM_LIB}" OR NOT EXISTS "${CLEONA_SODIUM_DLL}")
    message(FATAL_ERROR "cleona_pow: incomplete libsodium package — "
                        "${SODIUM_LIB} or ${CLEONA_SODIUM_DLL} missing.")
  endif()
  message(STATUS "cleona_pow: libsodium ${_cp_arch}/v${_cp_best} from ${_cp_root}")
endif()

# Non-MSVC (Linux, Android NDK, macOS, iOS) — unchanged. iOS/macOS builds pass
# -DSODIUM_LIB / -DSODIUM_INCLUDE explicitly, everything else discovers them.
if(NOT SODIUM_LIB)
  find_library(SODIUM_LIB NAMES sodium libsodium)
endif()
if(NOT SODIUM_LIB)
  message(FATAL_ERROR "libsodium not found — install libsodium-dev or set SODIUM_LIB")
endif()
target_link_libraries(cleona_pow PRIVATE ${SODIUM_LIB})

# sodium.h
if(NOT SODIUM_INCLUDE)
  find_path(SODIUM_INCLUDE sodium.h)
endif()
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
