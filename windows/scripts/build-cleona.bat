@echo off
REM ============================================================================
REM Cleona Windows: full build -- kills processes, builds GUI + daemon,
REM verifies the native DLLs. Exit 0 = success.
REM
REM Runs ON the Windows build VM via scheduled task `CleonaBuild`, because
REM Visual Studio Build Tools require an active desktop session -- see
REM windows/scripts/README.md.
REM ============================================================================
setlocal

if "%CLEONA_PROJECT%"==""     set CLEONA_PROJECT=C:\Users\Cleona\Cleona
if "%CLEONA_FLUTTER_BIN%"=="" set CLEONA_FLUTTER_BIN=C:\Users\Cleona\flutter\bin
if "%CLEONA_TMP%"==""         set CLEONA_TMP=C:\tmp

REM MSBuild parallelism: `flutter build windows` runs `cmake --build` without
REM --parallel, so CMake omits /m and MSBuild compiles every project serially.
REM Measured on the build VM 2026-07-28: one CL.exe on 8 cores, ~25 % CPU.
REM 6 rather than 8 -- see README.md for the memory rationale.
if "%CMAKE_BUILD_PARALLEL_LEVEL%"=="" set CMAKE_BUILD_PARALLEL_LEVEL=6

set PROJECT=%CLEONA_PROJECT%
set FLUTTER=%CLEONA_FLUTTER_BIN%\flutter
set DART=%CLEONA_FLUTTER_BIN%\dart
set RELEASE=%PROJECT%\build\windows\x64\runner\Release
set LOG=%CLEONA_TMP%\cleona-build.log
set MARK=%CLEONA_TMP%\cleona-build-exit.txt

echo [%date% %time%] Build started > %LOG%
echo [info] CMAKE_BUILD_PARALLEL_LEVEL=%CMAKE_BUILD_PARALLEL_LEVEL% >> %LOG%

REM --- Kill existing processes ---
echo [STEP 1] Killing existing processes...
taskkill /IM cleona.exe /F >NUL 2>&1
taskkill /IM cleona-daemon.exe /F >NUL 2>&1
taskkill /IM dart.exe /F >NUL 2>&1
timeout /T 2 /NOBREAK >NUL
echo [OK] Processes killed >> %LOG%

REM --- Flutter pub get ---
echo [STEP 2] Flutter pub get...
cd /d %PROJECT%
call %FLUTTER% pub get >> %LOG% 2>&1
if errorlevel 1 (
    echo [FAIL] pub get failed >> %LOG%
    echo FAIL_PUBGET > %MARK%
    exit /b 1
)
echo [OK] pub get >> %LOG%

REM --- Flutter build windows ---
echo [STEP 3] Flutter build windows --release...
call %FLUTTER% build windows --release >> %LOG% 2>&1
if errorlevel 1 (
    echo [FAIL] flutter build failed >> %LOG%
    echo FAIL_BUILD > %MARK%
    exit /b 1
)
echo [OK] flutter build >> %LOG%

REM --- Dart compile daemon ---
echo [STEP 4] Dart compile daemon...
call %DART% compile exe lib\service_daemon.dart -o %RELEASE%\cleona-daemon.exe >> %LOG% 2>&1
if errorlevel 1 (
    echo [FAIL] daemon compile failed >> %LOG%
    echo FAIL_DAEMON > %MARK%
    exit /b 1
)
echo [OK] daemon compile >> %LOG%

REM --- DLL Check ---
REM Fallback copies from windows\runner\. For libsodium.dll this branch should
REM no longer trigger since provisioning via windows/provision-libsodium.ps1 --
REM if it does, the provisioned package did not reach the Release directory and
REM that is worth investigating rather than silently patching over.
echo [STEP 5] DLL verification...
set DLL_OK=1
call :checkdll libsodium.dll
call :checkdll liboqs.dll
call :checkdll libzstd.dll
if "%DLL_OK%"=="0" (
    echo FAIL_DLL > %MARK%
    exit /b 1
)
echo [OK] All DLLs present >> %LOG%

REM --- Summary ---
echo [STEP 6] Build complete! >> %LOG%
dir %RELEASE%\cleona.exe %RELEASE%\cleona-daemon.exe %RELEASE%\libsodium.dll %RELEASE%\liboqs.dll %RELEASE%\libzstd.dll >> %LOG% 2>&1
echo ALL_DONE > %MARK%
echo [%date% %time%] Build finished successfully >> %LOG%
exit /b 0

REM --- helper: verify one DLL, fall back to windows\runner\ ---
:checkdll
if not exist "%RELEASE%\%~1" (
    echo [WARN] %~1 missing in Release, copying from runner... >> %LOG%
    if exist "%PROJECT%\windows\runner\%~1" (
        copy "%PROJECT%\windows\runner\%~1" "%RELEASE%\" >NUL
    ) else (
        echo [FAIL] %~1 not found anywhere >> %LOG%
        set DLL_OK=0
    )
)
exit /b 0
