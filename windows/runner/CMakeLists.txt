cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# === cleona_audio shim (cleona_audio.dll) ===
# Built from native/cleona_audio/, copied next to cleona.exe so DynamicLibrary
# can load it for FFI calls (audio_engine_shim.dart looks for "cleona_audio.dll"
# in the same directory as the executable).
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_audio" "${CMAKE_BINARY_DIR}/cleona_audio_build")
add_dependencies(${BINARY_NAME} cleona_audio)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_audio>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_audio.dll into Windows bundle"
)

# === cleona_net shim (cleona_net.dll) ===
# Direct-syscall UDP send-path — see Cleona_Chat_Architecture_v3_0.md §4.5.2.
# Built from native/cleona_net/, copied next to cleona.exe so DynamicLibrary
# can load it for FFI calls (native_udp_sender.dart looks for "cleona_net.dll"
# in the same directory as the executable). Hard dependency on Windows desktop;
# the daemon refuses to start if this DLL is missing from the bundle.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_net" "${CMAKE_BINARY_DIR}/cleona_net_build")
add_dependencies(${BINARY_NAME} cleona_net)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_net>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_net.dll into Windows bundle"
)

# === cleona_pow shim (cleona_pow.dll) ===
# PoW SHA-256 iteration loop. Without it proof_of_work.dart falls back to the
# Dart loop — measured ~561 ms median at difficulty 20 versus <10 ms native.
# Built from native/cleona_pow/ and copied next to cleona.exe, where
# proof_of_work.dart looks for "cleona_pow.dll".
#
# The subdirectory also resolves the libsodium MSVC package (import library +
# matching DLL) and exports CLEONA_SODIUM_DLL, which the libsodium bundle copy
# below prefers — that is what keeps libsodium.lib and libsodium.dll from
# drifting apart. It must therefore be added BEFORE the NATIVE_DLLS block.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_pow" "${CMAKE_BINARY_DIR}/cleona_pow_build")
add_dependencies(${BINARY_NAME} cleona_pow)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_pow>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_pow.dll into Windows bundle"
)

# === cleona_voice / cleona_video — NOT wired in yet, deliberately ===
# docs/SPEC_VOICE_VIDEO_REWORK.md V0.5 (build ownership) + the two
# BUILD_REQUEST.md files under native/cleona_voice/ and native/cleona_video/.
#
# Only the hardware-free mocks exist today (native/cleona_voice/mock,
# native/cleona_video/mock). Wiring add_subdirectory here now would have
# nothing but the mock to copy next to cleona.exe, and it must never ship in a
# release (both BUILD_REQUESTs). scripts/preflight.sh Check "Mock backend not
# in production build wiring" keeps this file free of `cleona_voice_mock` /
# `cleona_video_mock` until a real backend lands.
#
# Wire this up when the real backend lands, not before:
#   voice (V1.4, WASAPI):  add_subdirectory + add_dependencies + POST_BUILD copy of
#                          cleona_voice.dll (NOT cleona_voice_mock.dll), same shape as
#                          cleona_pow above. See native/cleona_voice/BUILD_REQUEST.md §3 —
#                          the mock needs no /std:c17 /experimental:c11atomics flags,
#                          but the real backend's requirements are V1.4's to determine.
#   video (V1.16, Media Foundation MFT): same shape, cleona_video.dll (NOT
#                          cleona_video_mock.dll). See native/cleona_video/BUILD_REQUEST.md §3.
# Once either DLL is added, extend NATIVE_DLLS below only if it becomes a build
# INPUT (pinned upstream via a provision-*.ps1) — a DLL built from
# add_subdirectory is an OUTPUT and is copied via $<TARGET_FILE:...> instead
# (preflight.sh Check 14 enforces this distinction).

# Copy native DLLs (libsodium, liboqs, libzstd) to the build output directory.
# libsodium comes out of the provisioned MSVC package when cleona_pow resolved
# one (same archive as libsodium.lib — see native/cleona_pow/CMakeLists.txt);
# the hand-placed windows/runner/libsodium.dll stays as fallback.
if(CLEONA_SODIUM_DLL AND EXISTS "${CLEONA_SODIUM_DLL}")
  set(SODIUM_DLL_SRC "${CLEONA_SODIUM_DLL}")
  message(STATUS "runner: libsodium.dll from provisioned package (${CLEONA_SODIUM_DLL})")
else()
  set(SODIUM_DLL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/libsodium.dll")
endif()

# liboqs, libzstd and opus: same treatment, same reason. Until S290 liboqs and
# libzstd were resolved from the source tree only — hand-placed, unversioned
# copies on the build VM whose provenance nothing recorded (git ls-files
# windows/ lists no .dll at all). PUBLISHING.md §9.3a: a published artifact
# must demonstrably originate from its own sources. windows/provision-liboqs.ps1,
# windows/provision-libzstd.ps1 and windows/provision-opus.ps1 (V1.8) build
# them from a commit-pinned upstream checkout; this block prefers that
# package and keeps the hand-placed DLL as fallback, mirroring the libsodium
# handling in native/cleona_pow/CMakeLists.txt.
#
# Unlike libsodium there is no .lib to keep in sync: nothing links against
# these three, they are opened with DynamicLibrary.open() (oqs_ffi.dart,
# compression.dart, opus_ffi.dart). Source builds are therefore a
# full-fledged path here.
set(CLEONA_OQS_DLL "")
set(CLEONA_ZSTD_DLL "")
set(CLEONA_OPUS_DLL "")
if(MSVC)
  set(_cr_libs_dir "$ENV{CLEONA_LIBS_DIR}")
  if(NOT _cr_libs_dir)
    set(_cr_libs_dir "$ENV{LOCALAPPDATA}/cleona-libs")
  endif()
  file(TO_CMAKE_PATH "${_cr_libs_dir}" _cr_libs_dir)

  # Already declared by the cleona_pow subdirectory above; option() is a no-op
  # when the cache entry exists, so this only matters if that ordering changes.
  option(CLEONA_AUTO_PROVISION
         "Build/download pinned native packages when they are missing" ON)

  # <pkg-prefix>-<version>/pkg/bin/<dll> is the layout both provision scripts
  # produce. The sorted glob picks the last match, i.e. the highest version —
  # lexicographically, the same simplification the libsodium lookup makes.
  macro(_cr_resolve_dll _prefix _dll _script _outvar)
    set(${_outvar} "")
    file(GLOB _cr_hits "${_cr_libs_dir}/${_prefix}-*/pkg/bin/${_dll}")
    list(SORT _cr_hits)
    foreach(_cr_h ${_cr_hits})
      set(${_outvar} "${_cr_h}")
    endforeach()
    if(NOT ${_outvar} AND CLEONA_AUTO_PROVISION
       AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../${_script}")
      message(STATUS "runner: ${_dll} missing — provisioning into ${_cr_libs_dir}")
      execute_process(
        COMMAND powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass
                -File "${CMAKE_CURRENT_SOURCE_DIR}/../${_script}" -Root "${_cr_libs_dir}"
        RESULT_VARIABLE _cr_rc
        OUTPUT_VARIABLE _cr_out
        ERROR_VARIABLE  _cr_err)
      if(NOT _cr_rc EQUAL 0)
        message(WARNING "runner: ${_script} failed (exit ${_cr_rc}):\n${_cr_out}\n${_cr_err}")
      endif()
      file(GLOB _cr_hits "${_cr_libs_dir}/${_prefix}-*/pkg/bin/${_dll}")
      list(SORT _cr_hits)
      foreach(_cr_h ${_cr_hits})
        set(${_outvar} "${_cr_h}")
      endforeach()
    endif()
  endmacro()

  _cr_resolve_dll("liboqs" "liboqs.dll"  "provision-liboqs.ps1"  CLEONA_OQS_DLL)
  _cr_resolve_dll("zstd"   "libzstd.dll" "provision-libzstd.ps1" CLEONA_ZSTD_DLL)
  _cr_resolve_dll("opus"   "opus.dll"    "provision-opus.ps1"    CLEONA_OPUS_DLL)
endif()

if(CLEONA_OQS_DLL AND EXISTS "${CLEONA_OQS_DLL}")
  set(OQS_DLL_SRC "${CLEONA_OQS_DLL}")
  message(STATUS "runner: liboqs.dll from provisioned package (${CLEONA_OQS_DLL})")
else()
  set(OQS_DLL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/liboqs.dll")
endif()

if(CLEONA_ZSTD_DLL AND EXISTS "${CLEONA_ZSTD_DLL}")
  set(ZSTD_DLL_SRC "${CLEONA_ZSTD_DLL}")
  message(STATUS "runner: libzstd.dll from provisioned package (${CLEONA_ZSTD_DLL})")
else()
  set(ZSTD_DLL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/libzstd.dll")
endif()

if(CLEONA_OPUS_DLL AND EXISTS "${CLEONA_OPUS_DLL}")
  set(OPUS_DLL_SRC "${CLEONA_OPUS_DLL}")
  message(STATUS "runner: opus.dll from provisioned package (${CLEONA_OPUS_DLL})")
else()
  set(OPUS_DLL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/opus.dll")
endif()

# Fail closed on an incomplete bundle (S290). This used to be `if(EXISTS ...)`
# with a silent skip, justified by the worry that a FATAL_ERROR would make
# `flutter build windows` unbuildable on a machine without the full DLL set
# (PUBLISHING.md 10, reproducible builds). That reason no longer holds: the four
# inputs are provisioned from pinned sources by _cr_resolve_dll above, so a
# missing file now means the provisioning failed or was switched off -- not that
# the developer is merely unequipped. And a build that silently omits a DLL is
# worse than one that refuses: without cleona_net.dll the client degrades to
# Dart's RawDatagramSocket.send(), which returns 0 for every destination on
# Windows (architecture 4.5.2), so it cannot send a single packet and says so
# only in one warn line.
set(NATIVE_DLLS
  "${SODIUM_DLL_SRC}"
  "${OQS_DLL_SRC}"
  "${ZSTD_DLL_SRC}"
  "${OPUS_DLL_SRC}"
)
foreach(DLL ${NATIVE_DLLS})
  if(NOT EXISTS "${DLL}")
    message(FATAL_ERROR
      "Required native DLL is missing:\n"
      "  ${DLL}\n"
      "This is a build INPUT, expected in the provisioned package or in\n"
      "windows/runner/. Run windows/provision-<lib>.ps1 or place the file, then\n"
      "configure again.")
  endif()
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DLL}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
  )
endforeach()

# Post-build completeness check over the finished bundle. The three above are
# inputs and already verified at configure time, but their POST_BUILD copy can
# still fail; cleona_net, cleona_audio and cleona_pow are build OUTPUTS whose
# copy can fail for a second reason (target dropped from the MSBuild solution
# filter, destination locked by a running cleona.exe). Inspecting the directory
# is the only place that catches both classes. Comma-separated on purpose: a
# semicolon would be split while CMake assembles the argument list.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND}
          -DBUNDLE_DIR=$<TARGET_FILE_DIR:${BINARY_NAME}>
          -DEXPECTED_DLLS=libsodium.dll,liboqs.dll,libzstd.dll,opus.dll,cleona_net.dll,cleona_audio.dll,cleona_pow.dll
          -P "${CMAKE_CURRENT_SOURCE_DIR}/../verify_bundle_dlls.cmake"
  COMMENT "Verifying native DLLs in the Windows bundle"
  VERBATIM
)

# Bundle MSVC runtime (vcruntime140.dll, msvcp140.dll, etc.) next to the
# executable so end users don't need the VC++ Redistributable installed.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
include(InstallRequiredSystemLibraries)
foreach(RUNTIME_LIB ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS})
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${RUNTIME_LIB}" "$<TARGET_FILE_DIR:${BINARY_NAME}>")
endforeach()
