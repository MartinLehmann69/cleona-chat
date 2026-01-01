@echo off
REM ============================================================================
REM Cleona Windows: Flutter GUI only (release).
REM Runs ON the Windows build VM via scheduled task `CleonaGuiBuild`, because
REM Visual Studio Build Tools require an active desktop session -- see
REM windows/scripts/README.md.
REM ============================================================================
setlocal

if "%CLEONA_PROJECT%"==""     set CLEONA_PROJECT=C:\Users\Cleona\Cleona
if "%CLEONA_FLUTTER_BIN%"=="" set CLEONA_FLUTTER_BIN=C:\Users\Cleona\flutter\bin
if "%CLEONA_TMP%"==""         set CLEONA_TMP=C:\tmp

REM MSBuild parallelism: flutter calls `cmake --build` without --parallel, so
REM without this every project compiles serially. See README.md for why 6.
if "%CMAKE_BUILD_PARALLEL_LEVEL%"=="" set CMAKE_BUILD_PARALLEL_LEVEL=6

set LOG=%CLEONA_TMP%\cleona-build.log
set MARK=%CLEONA_TMP%\cleona-build-exit.txt

cd /d %CLEONA_PROJECT%
del %MARK% 2>nul
echo [%date% %time%] GUI build started > %LOG%
echo [info] CMAKE_BUILD_PARALLEL_LEVEL=%CMAKE_BUILD_PARALLEL_LEVEL% >> %LOG%

call %CLEONA_FLUTTER_BIN%\flutter build windows --release >> %LOG% 2>&1
if errorlevel 1 (echo FAIL_BUILD > %MARK%) else (echo GUI_DONE > %MARK%)

echo [%date% %time%] GUI build finished >> %LOG%
