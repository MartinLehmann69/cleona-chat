@echo off
REM ============================================================================
REM Cleona Windows: daemon only (`dart compile exe`).
REM Runs ON the Windows build VM via scheduled task `CleonaDaemonBuild`.
REM See windows/scripts/README.md.
REM
REM No parallelism knob here on purpose: gen_snapshot (Dart AOT) is
REM single-threaded and has no -j equivalent. Measured 2026-07-28 on Linux:
REM 113 % CPU across a 12-core machine. That is a property of the compiler,
REM not a missing setting.
REM ============================================================================
setlocal

if "%CLEONA_PROJECT%"==""     set CLEONA_PROJECT=C:\Users\Cleona\Cleona
if "%CLEONA_FLUTTER_BIN%"=="" set CLEONA_FLUTTER_BIN=C:\Users\Cleona\flutter\bin
if "%CLEONA_TMP%"==""         set CLEONA_TMP=C:\tmp

set LOG=%CLEONA_TMP%\daemon-compile.log
set MARK=%CLEONA_TMP%\daemon-compile-exit.txt
set OUT=build\windows\x64\runner\Release\cleona-daemon.exe

cd /d %CLEONA_PROJECT%
del %MARK% 2>nul
echo [%date% %time%] Daemon compile started > %LOG%

call %CLEONA_FLUTTER_BIN%\dart compile exe lib\service_daemon.dart -o %OUT% >> %LOG% 2>&1
if errorlevel 1 (echo FAIL > %MARK%) else (echo DONE > %MARK%)

echo [%date% %time%] Daemon compile finished >> %LOG%
