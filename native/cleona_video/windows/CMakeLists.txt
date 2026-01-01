# CMakeLists for the Media Foundation backend of cleona_video.h — work package
# V1.16.
#
# SPEC: docs/SPEC_VOICE_VIDEO_REWORK.md §7 "V1.13-V1.16 — Video-Backends Linux
# / Android / Apple / Windows". Architecture: Cleona_Chat_Architecture_v3_0.md
# §10.6 (platform matrix, Windows row: IMFSourceReader / MFT).
#
# Picked up automatically once native/cleona_video/CMakeLists.txt grows the
# same platform-subdirectory loop the voice tree already has (foreach(_plat
# linux android apple windows) ... add_subdirectory) -- that file is not this
# package's to edit (native/cleona_video/test/BUILD_REQUEST.md §1 already asks
# the build owner for exactly that loop). Until it lands, this directory is
# still fully buildable and testable standalone; see BUILD_REQUEST_V1.16.md
# for the exact commands used for this package's own acceptance run.
#
# Output name is deliberately "cleona_video" (PREFIX ""), matching the naming
# table in ../CMakeLists.txt's sibling doc for the voice tree ("real ->
# libcleona_voice.so / cleona_voice.dll") and what video_pipeline.dart's
# VideoNativeLibrary.platform() looks for on Windows ("cleona_video.dll").

cmake_minimum_required(VERSION 3.13)

if(NOT WIN32)
  return()
endif()

add_library(cleona_video_windows SHARED cleona_video_windows.c)

# mfapi.h's MFGetAttributeSize/MFSetAttributeSize/...Ratio helpers are C99
# `inline` functions; MSVC's default C dialect predates C99 inline and treats
# the keyword as absent, which turned every call into an implicit-int
# undeclared-function warning (C4013) at best and a silent wrong-ABI call at
# worst. Same fix, same precedent as ../CMakeLists.txt's own MSVC branch for
# the mock target (/std:c11) -- verified necessary here by the exact same
# compiler on the same Windows Kit, not assumed by analogy.
if(MSVC)
  target_compile_options(cleona_video_windows PRIVATE /std:c11)
endif()

# Media Foundation (capture + encode/decode MFTs), D3D11 (decode render
# target), Ole32 (CoInitializeEx/CoCreateInstance/VariantClear/CoTaskMemFree).
# No separate import lib is needed for the CODECAPI_* property GUIDs this file
# defines itself (see the file's own doc comment on the codecapi.h storage
# gap) -- they are plain `const GUID` definitions in the translation unit, not
# externs to resolve at link time.
target_link_libraries(cleona_video_windows PRIVATE
  mf mfplat mfreadwrite mfuuid
  d3d11 dxgi
  ole32
  strmiids  # IID_ICodecAPI (icodecapi.h declares it EXTERN_C, unconditional
            # extern regardless of INITGUID -- the DirectShow/Media-Foundation-
            # shared base IID library, not mfuuid.lib. See BUILD_REQUEST_V1.16.md
            # for the link failure this fixed.
)

set_target_properties(cleona_video_windows PROPERTIES
                       PREFIX ""
                       OUTPUT_NAME "cleona_video")

# ---------------------------------------------------------------------------
# Conformance test, link mode (SPEC §10 gate 4: "green on the target
# platform" -- see BUILD_REQUEST_V1.16.md for what "green" actually means on
# a camera-less, GPU-less VM). Registered with ctest by
# native/cleona_video/test/CMakeLists.txt via the function it defines, exactly
# like the voice tree's cleona_voice_conformance_windows target.
# ---------------------------------------------------------------------------
if(TARGET cleona_video_conformance_loader)
  cleona_video_add_conformance_test(cleona_video_conformance_windows cleona_video_windows)
endif()
