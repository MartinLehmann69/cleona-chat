@echo off
REM ============================================================================
REM Cleona Windows: build liboqs from source.
REM Manual, rarely used -- there is no scheduled task for this one. Kept under
REM version control because the resulting liboqs.dll on the VM otherwise has no
REM traceable provenance (see SESSION_BLOCKERS.md).
REM ============================================================================
setlocal

if "%CLEONA_OQS_SRC%"==""   set CLEONA_OQS_SRC=C:\Users\Cleona\liboqs-src
if "%CLEONA_OQS_BUILD%"=="" set CLEONA_OQS_BUILD=C:\Users\Cleona\liboqs-build

echo === Building liboqs ===

set CMAKE="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

if not exist %CMAKE% (
  echo ERROR: cmake not found
  for /r "C:\Program Files (x86)\Microsoft Visual Studio" %%f in (cmake.exe) do echo Found: %%f
  exit /b 1
)

echo Using cmake: %CMAKE%

mkdir %CLEONA_OQS_BUILD% 2>NUL

echo --- Configuring ---
%CMAKE% -S %CLEONA_OQS_SRC% -B %CLEONA_OQS_BUILD% -G "Visual Studio 17 2022" -A x64 -DBUILD_SHARED_LIBS=ON -DOQS_BUILD_ONLY_LIB=ON
if errorlevel 1 (
  echo ERROR: cmake configure failed
  exit /b 1
)

echo --- Building ---
REM --parallel is passed explicitly here. Unlike `flutter build windows`, this
REM cmake invocation is ours, so we do not need the CMAKE_BUILD_PARALLEL_LEVEL
REM detour -- without either, CMake omits /m and MSBuild compiles liboqs (a
REM large library) one file at a time.
%CMAKE% --build %CLEONA_OQS_BUILD% --config Release --parallel 6
if errorlevel 1 (
  echo ERROR: cmake build failed
  exit /b 1
)

echo === liboqs build DONE ===
dir /s /b %CLEONA_OQS_BUILD%\*.dll
