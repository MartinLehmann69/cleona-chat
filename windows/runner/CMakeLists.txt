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
# §23.10 own screenshot: SHGetKnownFolderPath (shell32), CoTaskMemFree (ole32).
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib" "ole32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

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

# === cleona_link shim (cleona_link.dll) ===
# V4 Elligator2 link-handshake shim — docs/MIGRATION_V3_TO_V4.md §4d, V4-Doc
# §20.4.1. Monocypher 4.0.3 is vendored inside native/cleona_link/vendor/, so
# unlike cleona_pow this subdirectory resolves no external package. Built from
# native/cleona_link/ and copied next to cleona.exe — same OUTPUT pattern as
# cleona_net/cleona_pow ($<TARGET_FILE:...>), deliberately NOT in NATIVE_DLLS
# below: that list is for build INPUTS with a provenance script, and preflight
# Check 14 fails if an add_subdirectory output is listed there.
# CLEONA_LINK_BUILD_SMOKE=OFF: keeps the step-0 smoke executables and the
# deliberately broken cleona_link_saboteur library out of the production build
# tree (they are the standalone-build gate, native/cleona_link/CMakeLists.txt).
set(CLEONA_LINK_BUILD_SMOKE OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_link" "${CMAKE_BINARY_DIR}/cleona_link_build")
add_dependencies(${BINARY_NAME} cleona_link)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_link>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_link.dll into Windows bundle"
)

# === cleona_voice backend (cleona_voice.dll) ===
# WASAPI voice session — Cleona_Chat_Architecture_v3_0.md §10.4, work package
# docs/SPEC_VOICE_VIDEO_REWORK.md V1.4. Built from
# native/cleona_voice/windows/, copied next to cleona.exe so DynamicLibrary
# can load it for FFI calls (voice_session.dart looks for "cleona_voice.dll"
# in the same directory as the executable, VoiceNativeLibrary.platform()).
#
# native/cleona_voice/CMakeLists.txt's own platform loop already
# add_subdirectory()s native/cleona_voice/windows when it exists, so this
# add_subdirectory line is what pulls native/cleona_voice/** as a whole into
# the Flutter Windows build for the first time (BUGFIX_CURRENT.md AV-V1.4 §1).
# CMake target name is cleona_voice_windows (not cleona_voice — collision
# avoidance, native/cleona_voice/windows/CMakeLists.txt), OUTPUT_NAME/PREFIX
# make the produced file cleona_voice.dll regardless.
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_voice" "${CMAKE_BINARY_DIR}/cleona_voice_build")
add_dependencies(${BINARY_NAME} cleona_voice_windows)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_voice_windows>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_voice.dll into Windows bundle"
)

# === cleona_video backend (cleona_video.dll) ===
# Media Foundation capture/encode/decode — Cleona_Chat_Architecture_v3_0.md
# §10.6, work package docs/SPEC_VOICE_VIDEO_REWORK.md V1.16. Built from
# native/cleona_video/windows/, copied next to cleona.exe so DynamicLibrary
# can load it for FFI calls (video_pipeline.dart looks for "cleona_video.dll"
# in the same directory as the executable).
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_video" "${CMAKE_BINARY_DIR}/cleona_video_build")
add_dependencies(${BINARY_NAME} cleona_video_windows)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona_video_windows>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona_video.dll into Windows bundle"
)

# === cleona-play.exe (sound player the daemon starts per sound) ===
# Built from windows/cleona_play/ (libogg + libvorbis from pinned Xiph
# sources, output through winmm), copied next to cleona.exe:
# notification_sound_service.dart starts `<bundleDir>\cleona-play.exe`, and
# the MSVC runtime DLLs it needs are bundled in the same directory. Without
# it every sound is silent on Windows -- the verification below fails the
# build when it is missing (-DEXPECTED_PROGRAMS).
add_subdirectory("${CMAKE_SOURCE_DIR}/cleona_play" "${CMAKE_BINARY_DIR}/cleona_play_build")
add_dependencies(${BINARY_NAME} cleona-play)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona-play>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona-play.exe into Windows bundle"
)
# === cleona-notify.exe (toast helper the daemon starts per notification) ===
# Built from windows/cleona_notify/ (C++/WinRT from the Windows SDK, no
# download), copied next to cleona.exe: windows_toast_notifier.dart starts
# `<bundleDir>\cleona-notify.exe`, and the MSVC runtime DLLs it needs are
# bundled in the same directory. Without it Windows shows no system
# notification -- the verification below fails the build when it is missing
# (-DEXPECTED_PROGRAMS).
add_subdirectory("${CMAKE_SOURCE_DIR}/cleona_notify" "${CMAKE_BINARY_DIR}/cleona_notify_build")
add_dependencies(${BINARY_NAME} cleona-notify)
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:cleona-notify>
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona-notify.exe into Windows bundle"
)
# The helper must build its toast as text-only and silent (no toast shown,
# nothing written) -- see windows/cleona_notify/check_notify.cmake.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND}
            -DHELPER=$<TARGET_FILE:cleona-notify>
            -P "${CMAKE_SOURCE_DIR}/cleona_notify/check_notify.cmake"
    COMMENT "Self check of cleona-notify.exe (toast XML, no toast)"
    VERBATIM
)
# === cleona-firewall.cmd (inbound firewall rule of the daemon, S407) ===
# The one definition of the rule: the setup runs it elevated after install,
# the uninstaller to remove it, and the app's "Allow in firewall" button
# (lib/core/platform/windows_firewall.dart) from `<bundleDir>`. Checked by
# the verification below (-DEXPECTED_PROGRAMS).
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/cleona-firewall.cmd"
            $<TARGET_FILE_DIR:${BINARY_NAME}>
    COMMENT "Copying cleona-firewall.cmd into Windows bundle"
)
# The player must decode every sound the bundle ships (decode only, no
# output device needed) -- see windows/cleona_play/check_sounds.cmake.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND}
            -DPLAYER=$<TARGET_FILE:cleona-play>
            -DSOUNDS_DIR=${CMAKE_SOURCE_DIR}/../assets/sounds
            -P "${CMAKE_SOURCE_DIR}/cleona_play/check_sounds.cmake"
    COMMENT "Decoding every bundled sound with cleona-play.exe"
    VERBATIM
)

# === Third-party license texts (S403) ===================================
# cleona-play.exe statically links the pinned libogg/libvorbis sources (see
# assets/licenses/INDEX.txt), so their BSD-3-Clause texts ship with the
# bundle. Copied into a `licenses/` folder next to the executables, the same
# POST_BUILD pattern as the copies above. The Flutter assets carry the same
# texts into the GUI bundle (pubspec.yaml); this is the side the GUI does not
# own. make_directory first: `cmake -E copy` does not create the destination
# path, and the Release directory is not cleared between builds.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/../assets/licenses/libogg.txt"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses/libogg.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/../assets/licenses/libvorbis.txt"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses/libvorbis.txt"
    COMMENT "Copying Xiph license texts into Windows bundle"
)

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

  # whisper.cpp (S422, R-11): five DLLs from ONE package,
  # <libs>/whisper-<version>/pkg/bin/, built by provision-whisper.ps1 from the
  # pinned source archive. Resolved as a directory rather than per DLL
  # because the five belong together: whisper_wrapper.dll is linked against
  # exactly this whisper.dll, and the ggml*.dll are its own dependencies.
  # Provisioning runs when a file is missing OR when native/whisper_wrapper.c
  # no longer matches the hash the package recorded for its wrapper — the
  # wrapper source lives in this repository, so a changed wrapper must not be
  # served from an old package. CMAKE_CONFIGURE_DEPENDS re-runs the configure
  # when that file changes.
  set(_cr_wrapper_c "${CMAKE_SOURCE_DIR}/../native/whisper_wrapper.c")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_cr_wrapper_c}")
  file(SHA256 "${_cr_wrapper_c}" _cr_wrapper_sha)
  macro(_cr_find_whisper_bin)
    set(CLEONA_WHISPER_BIN "")
    file(GLOB _cr_whits "${_cr_libs_dir}/whisper-*/pkg/bin/whisper.dll")
    list(SORT _cr_whits)
    foreach(_cr_h ${_cr_whits})
      get_filename_component(CLEONA_WHISPER_BIN "${_cr_h}" DIRECTORY)
    endforeach()
    set(_cr_whisper_complete FALSE)
    if(CLEONA_WHISPER_BIN)
      set(_cr_whisper_complete TRUE)
      foreach(_cr_w whisper.dll whisper_wrapper.dll ggml.dll ggml-base.dll ggml-cpu.dll)
        if(NOT EXISTS "${CLEONA_WHISPER_BIN}/${_cr_w}")
          set(_cr_whisper_complete FALSE)
        endif()
      endforeach()
      set(_cr_stamp "${CLEONA_WHISPER_BIN}/../whisper_wrapper.c.sha256")
      if(EXISTS "${_cr_stamp}")
        file(READ "${_cr_stamp}" _cr_stamp_sha)
        string(STRIP "${_cr_stamp_sha}" _cr_stamp_sha)
        if(NOT _cr_stamp_sha STREQUAL _cr_wrapper_sha)
          set(_cr_whisper_complete FALSE)
        endif()
      else()
        set(_cr_whisper_complete FALSE)
      endif()
    endif()
  endmacro()
  _cr_find_whisper_bin()
  if(NOT _cr_whisper_complete AND CLEONA_AUTO_PROVISION
     AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../provision-whisper.ps1")
    message(STATUS "runner: whisper package missing or stale — provisioning into ${_cr_libs_dir}")
    execute_process(
      COMMAND powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass
              -File "${CMAKE_CURRENT_SOURCE_DIR}/../provision-whisper.ps1" -Root "${_cr_libs_dir}"
      RESULT_VARIABLE _cr_rc
      OUTPUT_VARIABLE _cr_out
      ERROR_VARIABLE  _cr_err)
    if(NOT _cr_rc EQUAL 0)
      message(WARNING "runner: provision-whisper.ps1 failed (exit ${_cr_rc}):\n${_cr_out}\n${_cr_err}")
    endif()
    _cr_find_whisper_bin()
  endif()
  if(NOT _cr_whisper_complete)
    set(CLEONA_WHISPER_BIN "")
  endif()
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

# === whisper.cpp into lib\ (S422, R-11) ===
# Voice transcription (architecture v4_2 §21.7, §27.3 "libwhisper (+ GGML)").
# Until S422 no build path put these into the Windows bundle, so the
# transcription page of every Windows build said "whisper.cpp library not
# available".
#
# WHERE: <bundle>\lib\, not beside cleona.exe. Transcription runs in the
# daemon (VoiceTranscriptionService lives in CleonaService), and the daemon
# is bin\cleona-daemon.exe. whisper_ffi.dart searches the bare name — which
# LoadLibraryW resolves from the directory of the EXECUTABLE, bin\ for the
# daemon — and `${AppPaths.bundleLibDir}\whisper.dll`, i.e. <bundle>\lib\
# for GUI and daemon alike (AppPaths.bundleDir maps bin\ to its parent). The
# bundle root is in neither list for the daemon. The ggml*.dll that
# whisper.dll imports are not searched in lib\ by Windows; whisper_ffi.dart
# loads them first by full path, and the loader then reuses the loaded
# modules (see _dirOf in whisper_ffi.dart).
#
# No hand-placed fallback: provisioning from the pinned archive is the only
# origin. The list here and -DEXPECTED_LIB_DLLS below must name the same
# five; a drift is caught at build time by the verification (missing file,
# or a whisper*/ggml* DLL in lib\ that is not expected).
foreach(_wdll whisper.dll whisper_wrapper.dll ggml.dll ggml-base.dll ggml-cpu.dll)
  if(NOT CLEONA_WHISPER_BIN OR NOT EXISTS "${CLEONA_WHISPER_BIN}/${_wdll}")
    message(FATAL_ERROR
      "Required whisper.cpp DLL is missing: ${_wdll}\n"
      "It is a build INPUT from the provisioned package\n"
      "<libs>/whisper-<version>/pkg/bin/. Run windows/provision-whisper.ps1\n"
      "(see its output for the reason), then configure again.")
  endif()
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>/lib"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CLEONA_WHISPER_BIN}/${_wdll}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/lib/${_wdll}"
  )
endforeach()
message(STATUS "runner: whisper.cpp DLLs from provisioned package (${CLEONA_WHISPER_BIN})")

# Post-build check over the finished bundle, in both directions (S338):
# completeness AND no foreign cleona_*.dll. The four above are inputs and
# already verified at configure time, but their POST_BUILD copy can still
# fail; cleona_net/cleona_pow/cleona_link/cleona_voice/cleona_video are build
# OUTPUTS whose copy can fail for a second reason (target dropped from the
# MSBuild solution filter, destination locked by a running cleona.exe). And a
# stale DLL of a REMOVED native module survives in the Release directory
# forever — it is never cleared between builds; that is how cleona_audio.dll
# outlived the §10.4 audio rework by 18 days on the build VM. Inspecting the
# directory is the only place that catches all three classes. EXPECTED_DLLS
# is the authoritative allowed-set; preflight Check 14b keeps it bound to the
# tracked native/*/CMakeLists.txt in both directions, and release-build.sh
# derives WIN_BUNDLE_DLLS from this literal — keep the -DEXPECTED_DLLS=
# format greppable. Comma-separated on purpose: a semicolon would be split
# while CMake assembles the argument list.
# EXPECTED_LIB_DLLS (S422) is the same for <bundle>\lib\ — the whisper.cpp
# set above. A separate list rather than "lib/whisper.dll" entries in
# EXPECTED_DLLS: every consumer of EXPECTED_DLLS reads it with the character
# class [A-Za-z0-9_.,+-], which ends at a "/" and would silently cut the list
# (release-build.sh, win-deploy.sh, preflight Check 14b, two self-tests).
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND}
          -DBUNDLE_DIR=$<TARGET_FILE_DIR:${BINARY_NAME}>
          -DEXPECTED_LIB_DLLS=whisper.dll,whisper_wrapper.dll,ggml.dll,ggml-base.dll,ggml-cpu.dll
          -DEXPECTED_DLLS=libsodium.dll,liboqs.dll,libzstd.dll,opus.dll,cleona_net.dll,cleona_pow.dll,cleona_link.dll,cleona_voice.dll,cleona_video.dll
          -DEXPECTED_PROGRAMS=cleona-play.exe,cleona-notify.exe,cleona-firewall.cmd
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
