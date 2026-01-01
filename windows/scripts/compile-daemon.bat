@echo off
REM ============================================================================
REM Cleona Windows: daemon only (`dart build cli`).
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
REM ── S367: `dart build cli`, NOT `dart compile exe` ─────────────────────────
REM
REM Since the store (v4_1 §21.4.1) depends on a code asset, `dart compile exe`
REM no longer carries: it runs NO build hooks. The Dart docs say the command
REM should then fail; measured, it does not — it silently produces an exe
REM WITHOUT sqlite3.dll. The daemon starts with it, fails when opening the
REM store and ends with EXIT 0: for the UI indistinguishable from "runs,
REM only opens no socket".
REM
REM `dart build cli` builds only targets under bin\ (hence the entry point
REM bin\cleona_daemon.dart, which passes lib\service_daemon.dart through) and
REM embeds the path of the DLL as ..\lib\sqlite3.dll — RELATIVE TO THE EXE.
REM The exe therefore stays in Release\bin\, the DLLs lie in Release\lib\.
set STAGE=build\.daemon-cli
set OUTDIR=build\windows\x64\runner\Release
set OUT=%OUTDIR%\bin\cleona-daemon.exe

cd /d %CLEONA_PROJECT%
del %MARK% 2>nul
echo [%date% %time%] Daemon compile started > %LOG%

call %CLEONA_FLUTTER_BIN%\dart build cli --target bin/cleona_daemon.dart --output %STAGE% >> %LOG% 2>&1
if errorlevel 1 goto fail

if not exist %OUTDIR%\bin mkdir %OUTDIR%\bin
if not exist %OUTDIR%\lib mkdir %OUTDIR%\lib
copy /Y %STAGE%\bundle\bin\cleona_daemon.exe %OUT% >> %LOG% 2>&1
if errorlevel 1 goto fail
copy /Y %STAGE%\bundle\lib\*.dll %OUTDIR%\lib\ >> %LOG% 2>&1
if errorlevel 1 goto fail
REM A leftover in the root would be worse than none: the GUI would find it
REM and start a daemon that cannot open its store.
del /Q %OUTDIR%\cleona-daemon.exe 2>nul

REM Resolvability probe: exactly the path the exe uses (<exe>\..\lib\), not
REM mere presence somewhere. The FILE NAME is deliberately not fixed — which
REM name the build hook of package:sqlite3 produces on Windows cannot be
REM measured from the Linux workbench, and a guessed name would be a gate
REM that reports the wrong reason.
if not exist %OUTDIR%\bin\..\lib\*.dll (
  echo There is no DLL under %OUTDIR%\bin\..\lib\ — exactly this path is where the exe looks. >> %LOG%
  goto fail
)

echo DONE > %MARK%
goto ende

:fail
echo FAIL > %MARK%

:ende

echo [%date% %time%] Daemon compile finished >> %LOG%
