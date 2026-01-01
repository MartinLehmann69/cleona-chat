# cleona_tray.dll -- the thread that owns the daemon's notification-area icon
# (see cleona_tray.c, S423 B-5). Builds standalone
#   cmake -S windows/cleona_tray -B <dir> && cmake --build <dir> --config Release
# and as a subdirectory of windows/runner/CMakeLists.txt, which copies the DLL
# next to cleona.exe; the daemon (bin\cleona-daemon.exe) opens it from there
# (lib/core/tray/windows_tray_thread.dart, the same lookup as cleona_net.dll).
#
# Lives under windows/ and not under native/ for the same reason as
# cleona_play and cleona_notify: native/*/CMakeLists.txt means "a shim for
# every platform" to the preflight (check 8a demands lib<name>.so on Android),
# and a notification-area icon exists on Windows only. Preflight check 14b
# accepts a cleona_*.dll in EXPECTED_DLLS whose module is tracked under
# windows/<name>/ for exactly this case.
cmake_minimum_required(VERSION 3.14)
project(cleona_tray LANGUAGES C)

if(NOT WIN32)
  message(FATAL_ERROR "cleona_tray is a Windows-only library")
endif()

add_library(cleona_tray SHARED cleona_tray.c)
# Output cleona_tray.dll (no "lib" prefix), like cleona_net.
set_target_properties(cleona_tray PROPERTIES PREFIX "")
target_compile_definitions(cleona_tray PRIVATE UNICODE _UNICODE)
# C runtime: the build's default, the same as cleona_net.dll and the other
# DLLs the daemon opens from the bundle root.
if(MSVC)
  # Own code: /W4 and warnings as errors, like cleona-play and the runner.
  target_compile_options(cleona_tray PRIVATE /W4 /WX)
  target_compile_definitions(cleona_tray PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
target_link_libraries(cleona_tray PRIVATE user32 shell32)
