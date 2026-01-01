# Find SpeexDSP — system or vendored fallback
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(SPEEXDSP QUIET speexdsp)
endif()

if(NOT SPEEXDSP_FOUND)
  # Fallback: build vendored speexdsp from native/cleona_audio/vendor/speexdsp/
  set(SPEEXDSP_VENDOR_DIR "${CMAKE_CURRENT_LIST_DIR}/../vendor/speexdsp")
  if(EXISTS "${SPEEXDSP_VENDOR_DIR}/CMakeLists.txt")
    add_subdirectory("${SPEEXDSP_VENDOR_DIR}" speexdsp_build)
    set(SPEEXDSP_LIBRARIES speexdsp)
    set(SPEEXDSP_INCLUDE_DIRS "${SPEEXDSP_VENDOR_DIR}/include")
    set(SPEEXDSP_FOUND TRUE)
  endif()
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(SpeexDSP
  REQUIRED_VARS SPEEXDSP_LIBRARIES SPEEXDSP_INCLUDE_DIRS)
