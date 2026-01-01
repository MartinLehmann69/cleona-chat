# cleona-notify.exe -- the toast helper the Windows daemon starts per system
# notification (see cleona_notify.cpp). Builds standalone
#   cmake -S windows/cleona_notify -B <dir> && cmake --build <dir> --config Release
# and as a subdirectory of windows/runner/CMakeLists.txt, which copies the
# program next to cleona.exe.
#
# Lives under windows/ and not under native/ for the same reason as
# cleona_play: the preflight checks 8a and 14b derive "must exist as
# lib<name>.so on Android" and "must be a DLL in EXPECTED_DLLS" from
# native/*/CMakeLists.txt, and neither holds for a Windows helper program.
# Its presence in the bundle is checked by windows/verify_bundle_dlls.cmake
# (-DEXPECTED_PROGRAMS).
#
# C++/WinRT comes with the Windows SDK (measured on the build VM 11.11.2026:
# 10.0.26100.0\cppwinrt\winrt\Windows.UI.Notifications.h) -- no NuGet, no
# download at build time.
cmake_minimum_required(VERSION 3.14)
project(cleona_notify LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "cleona_notify is a Windows-only helper")
endif()

# WIN32: Windows subsystem, entry WinMain -- no console window per toast.
add_executable(cleona-notify WIN32 cleona_notify.cpp)
# C++/WinRT needs C++17.
target_compile_features(cleona-notify PRIVATE cxx_std_17)
target_compile_definitions(cleona-notify PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
# Own code: /W4 and warnings as errors, like cleona-play and the runner.
# Exceptions ON (/EHsc): C++/WinRT reports errors as winrt::hresult_error.
# This target deliberately does NOT use APPLY_STANDARD_SETTINGS, which sets
# _HAS_EXCEPTIONS=0. /permissive- is what C++/WinRT is written against.
# /external:anglebrackets /external:W0: the SDK headers (all included with
# <...>) are not this project's code and must not fail the build over a
# warning of a new SDK; own code keeps /W4 /WX.
# https://learn.microsoft.com/en-us/cpp/build/reference/external-external-headers-diagnostics
target_compile_options(cleona-notify PRIVATE
    /W4 /WX /EHsc /permissive- /external:anglebrackets /external:W0)
# windowsapp: the umbrella library of the WinRT functions C++/WinRT calls
# (C++/WinRT FAQ, "Why is the linker giving me a 'LNK2019: Unresolved
# external symbol' error?": link WindowsApp.lib,
# https://learn.microsoft.com/en-us/windows/uwp/cpp-and-winrt-apis/faq).
# advapi32: Reg* functions; shell32: CommandLineToArgvW, SHGetKnownFolderPath.
# The start-menu shortcut (S420): ole32 for CoCreateInstance, CoTaskMemFree,
# PropVariantClear; uuid for CLSID_ShellLink, FOLDERID_Programs and
# PKEY_AppUserModel_ID (all three found in Uuid.Lib of SDK 10.0.26100.0 on the
# build VM, 11.11.2026; Propkey.h declares the key `extern` without INITGUID).
# No propsys: the one propvarutil.h helper used, InitPropVariantFromString, is
# inline in that SDK and calls CoTaskMemAlloc only.
target_link_libraries(cleona-notify PRIVATE
    windowsapp advapi32 shell32 ole32 uuid)
