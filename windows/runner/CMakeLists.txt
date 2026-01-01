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

# Copy native DLLs (libsodium, liboqs, libzstd) to the build output directory.
set(NATIVE_DLLS
  "${CMAKE_CURRENT_SOURCE_DIR}/libsodium.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/liboqs.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/libzstd.dll"
)
foreach(DLL ${NATIVE_DLLS})
  if(EXISTS "${DLL}")
    add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DLL}" "$<TARGET_FILE_DIR:${BINARY_NAME}>"
    )
  endif()
endforeach()
