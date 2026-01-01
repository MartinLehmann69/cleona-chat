#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions whisper.dll, ggml.dll, ggml-base.dll, ggml-cpu.dll and
    whisper_wrapper.dll for the Windows build from the pinned whisper.cpp
    source archive.

.DESCRIPTION
    Windows equivalent of the whisper.cpp builds the other platforms already
    do, all pinned to the SAME version:

        scripts/build-android-libs.sh     WHISPER_VERSION="v1.8.4"
        scripts/build-ios-libs.sh         (same pin)
        scripts/build-macos-libs.sh       (same pin)
        scripts/build-whisper-wrapper.sh  WHISPER_VERSION="v1.8.4"

    One version on every platform is not cosmetic: whisper_ffi.dart reads and
    writes fields of `struct whisper_full_params`, and their offsets moved
    between releases (`language` at 96 in v1.7.1, at 104 in 1.8.4 -- see
    native/whisper_wrapper.c). Architecture v4_2 section 27.3 names the pin.

    Until S422 no build path produced these DLLs for Windows at all, so every
    Windows build showed "whisper.cpp library not available"
    (`mycelium/berichte/S422-RCA-E2E-LAUF-4.2.8.md`, R-11).

    Source: the GitHub source archive of the tag, checked against a fixed
    SHA-256 before it is unpacked -- the pattern of provision-libsodium.ps1.
    Nothing links against whisper inside the app; whisper_ffi.dart opens the
    DLLs with DynamicLibrary.open(). The one thing that links against
    whisper.dll is the wrapper, and it is built here, against the header of
    exactly this source tree and the import library of exactly this build
    (the same rule scripts/build-whisper-wrapper.sh follows: "the wrapper is
    compiled against whisper.h, and field offsets differ between releases").

    Idempotent: a complete package is left untouched unless -Force is given.
    The wrapper is rebuilt on its own when native/whisper_wrapper.c changed
    (SHA-256 stamp in the package), because its source lives in this
    repository and not in the pinned archive.

    It does not copy anything into the source tree.
    windows/runner/CMakeLists.txt reads the five DLLs out of the provisioned
    package (pkg\bin) and copies them into the bundle's lib\ directory.

.PARAMETER Version
    whisper.cpp version (tag without "v"). Must have a pinned SHA-256 below.

.PARAMETER Root
    Directory that holds provisioned packages. Default:
    $env:CLEONA_LIBS_DIR, else "$env:LOCALAPPDATA\cleona-libs".

.PARAMETER Generator
    CMake generator. Override when the VM gets a different Visual Studio.

.PARAMETER Platform
    CMake generator platform (architecture).

.PARAMETER Parallel
    Compiler processes, same reasoning as provision-liboqs.ps1's -Parallel.

.PARAMETER Force
    Re-download, rebuild and re-install even when the package is present.

.PARAMETER EmitRootTo
    Optional file path. The resolved package bin directory is written to it
    (one line), for callers that cannot parse stdout reliably.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-whisper.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-whisper.ps1 `
        -Root C:\cleona-libs -Version 1.8.4 -Force
#>
[CmdletBinding()]
param(
    [string]$Version = '1.8.4',
    [string]$Root = '',
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$Platform = 'x64',
    [int]$Parallel = 6,
    [switch]$Force,
    [string]$EmitRootTo = ''
)

$ErrorActionPreference = 'Stop'

# Same reasoning as provision-libsodium.ps1: Invoke-WebRequest renders a
# progress bar per received buffer, which costs a large factor in a process
# that owns a console host.
$ProgressPreference = 'SilentlyContinue'

# SHA-256 of the GitHub source archive per version. Determined 2026-11-13
# (S422) by downloading
#   https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.4.zip
# twice (also through the old name github.com/ggerganov/whisper.cpp, which
# redirects to it) with the same result. The tag points at commit
#   9386f239401074690479731c1e41683fbbeac557
# (`git ls-remote https://github.com/ggml-org/whisper.cpp.git refs/tags/v1.8.4`).
# Adding a version without its hash is refused: an unverified download is not
# a pinned dependency.
$KnownHashes = @{
    '1.8.4' = '337ad27aa18d8272762a517f369596eeffcf7a97131a107961c418ff46070a26'
}

if (-not $KnownHashes.ContainsKey($Version)) {
    throw ("No pinned SHA-256 for whisper.cpp $Version. Add the hash to " +
           "`$KnownHashes in windows\provision-whisper.ps1 before using it -- " +
           "and move the pin on every other platform with it (see .DESCRIPTION).")
}
$ExpectedSha = $KnownHashes[$Version]

if (-not $Root -or $Root.Trim() -eq '') {
    if ($env:CLEONA_LIBS_DIR) {
        $Root = $env:CLEONA_LIBS_DIR
    } else {
        $Root = Join-Path $env:LOCALAPPDATA 'cleona-libs'
    }
}

$Url          = "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$Version.zip"
$PkgName      = "whisper-$Version"
$BaseDir      = Join-Path $Root $PkgName
$ZipPath      = Join-Path $BaseDir "whisper.cpp-v$Version.zip"
$ExtractDir   = Join-Path $BaseDir 'src'
# The archive carries a single top-level directory "whisper.cpp-<version>".
$SrcDir       = Join-Path $ExtractDir "whisper.cpp-$Version"
$BuildDir     = Join-Path $BaseDir 'build'
$PkgDir       = Join-Path $BaseDir 'pkg'
$BinDir       = Join-Path $PkgDir 'bin'
$WrapSrcDir   = Join-Path $BaseDir 'wrapper-src'
$WrapBuildDir = Join-Path $BaseDir 'wrapper-build'
$WrapStamp    = Join-Path $PkgDir 'whisper_wrapper.c.sha256'
$WrapperC     = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\native\whisper_wrapper.c'))

# The names whisper_ffi.dart opens on Windows (_libNamesForPlatform).
$UpstreamDlls = @('whisper.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-cpu.dll')
$WrapperDll   = 'whisper_wrapper.dll'

# One symbol per DLL that whisper_ffi.dart (or the loader chain) needs. A DLL
# that builds but exports nothing loads fine and fails at the first lookup.
$RequiredExports = [ordered]@{
    'whisper.dll'         = @('whisper_init_from_file', 'whisper_full',
                              'whisper_full_default_params_by_ref',
                              'whisper_free_params', 'whisper_lang_str')
    'ggml-base.dll'       = @('ggml_init')
    'ggml-cpu.dll'        = @('ggml_backend_cpu_init')
    'ggml.dll'            = @('ggml_backend_reg_count')
    'whisper_wrapper.dll' = @('whisper_full_from_ptr', 'whisper_params_set_language',
                              'whisper_params_set_n_threads')
}

function Write-Step($msg) { Write-Host "[provision-whisper] $msg" }

function Get-Sha256([string]$path) {
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-Native([string]$exe, [string[]]$argv, [string]$what) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) {
        throw "$what failed (exit $LASTEXITCODE): $exe $($argv -join ' ')"
    }
}

# CMake wants forward slashes even on Windows -- see provision-liboqs.ps1.
function ToCMakePath([string]$p) { return $p.Replace('\', '/') }

function Find-Tool([string]$name, [string[]]$globs) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $inst = & $vswhere -latest -products * `
                    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                    -property installationPath
        if ($LASTEXITCODE -eq 0 -and $inst) {
            foreach ($g in $globs) {
                $hit = Get-ChildItem -Path (Join-Path $inst.Trim() $g) -ErrorAction SilentlyContinue |
                       Sort-Object FullName | Select-Object -Last 1
                if ($hit) { return $hit.FullName }
            }
        }
    }
    return ''
}

function Find-CMake {
    $cmake = Find-Tool 'cmake' @(
        'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
    if (-not $cmake) {
        throw ('cmake not found in PATH and not in the Visual Studio ' +
               'installation -- install the "C++ CMake tools for Windows" component.')
    }
    return $cmake
}

# Places one build output into pkg\bin. `cmake --install` puts the DLLs of a
# shared build into bin\ (RUNTIME default destination); should a future
# upstream layout not do that, the Release directory of the build tree is
# the second place, the same fallback provision-opus.ps1 has.
function Place-Dll([string]$name, [string]$fromTree) {
    $dst = Join-Path $BinDir $name
    if (Test-Path $dst) { return }
    $hit = Get-ChildItem -Path $fromTree -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\Release\\' } |
           Select-Object -First 1
    if (-not $hit) {
        throw ("Build produced no $name under $PkgDir or $fromTree. " +
               "BUILD_SHARED_LIBS was ON, so the layout changed -- inspect " +
               "the trees before adjusting this script.")
    }
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Copy-Item $hit.FullName $dst -Force
    Write-Step "placed $dst (from $($hit.FullName))"
}

if (-not (Test-Path $WrapperC)) {
    throw "native\whisper_wrapper.c not found at $WrapperC -- run this script from the repository's windows\ directory."
}
$wrapperSha = Get-Sha256 $WrapperC

$upstreamThere = $true
foreach ($d in $UpstreamDlls) {
    if (-not (Test-Path (Join-Path $BinDir $d))) { $upstreamThere = $false }
}
# whisper.h of exactly this tree: the wrapper is compiled against it.
if (-not (Test-Path (Join-Path $SrcDir 'include\whisper.h'))) { $upstreamThere = $false }

# --- 1. whisper.cpp itself -------------------------------------------------
if ($upstreamThere -and -not $Force) {
    Write-Step "already provisioned: $BinDir"
} else {
    $cmake = Find-CMake
    Write-Step "cmake: $cmake"
    New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

    # Reuse an existing archive only when its hash matches; otherwise it is a
    # truncated or tampered leftover and gets replaced.
    $needDownload = $true
    if ((Test-Path $ZipPath) -and -not $Force) {
        $have = Get-Sha256 $ZipPath
        if ($have -eq $ExpectedSha) {
            Write-Step "archive present and verified: $ZipPath"
            $needDownload = $false
        } else {
            Write-Step "archive present but hash mismatch ($have) -- re-downloading"
            Remove-Item $ZipPath -Force
        }
    }
    if ($needDownload) {
        Write-Step "downloading $Url"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = "$ZipPath.part"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
        $have = Get-Sha256 $tmp
        if ($have -ne $ExpectedSha) {
            Remove-Item $tmp -Force
            throw ("SHA-256 mismatch for whisper.cpp v$Version source archive`n" +
                   "  expected $ExpectedSha`n" +
                   "  actual   $have`n" +
                   "Download rejected -- nothing was extracted.")
        }
        Move-Item $tmp $ZipPath -Force
        Write-Step "verified SHA-256 $ExpectedSha"
    }

    # A leftover tree cannot be trusted (other version, partial extraction,
    # an earlier build that wrote into it); extracting again is cheaper than
    # proving any of that.
    foreach ($d in @($ExtractDir, $BuildDir, $PkgDir, $WrapSrcDir, $WrapBuildDir)) {
        if (Test-Path $d) {
            Write-Step "removing previous $d"
            Remove-Item $d -Recurse -Force
        }
    }
    Write-Step "extracting to $ExtractDir"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    if (-not (Test-Path (Join-Path $SrcDir 'CMakeLists.txt'))) {
        throw ("Extraction did not produce $SrcDir\CMakeLists.txt -- archive " +
               "layout changed. Inspect $ExtractDir before adjusting this script.")
    }

    # Flags:
    #   BUILD_SHARED_LIBS=ON          whisper.dll + ggml*.dll, the names
    #                                 whisper_ffi.dart opens.
    #   WHISPER_BUILD_TESTS/EXAMPLES=OFF  library only, as on Android
    #                                 (build-android-libs.sh).
    #   GGML_NATIVE=OFF               no -march=native: the DLL must run on
    #                                 other CPUs than the build VM's. With it
    #                                 OFF, ggml/CMakeLists.txt switches
    #                                 SSE4.2/AVX/AVX2/BMI2 on as the baseline
    #                                 (INS_ENB, ggml/CMakeLists.txt:138-154).
    #   GGML_OPENMP=OFF               as on Android. With MSVC, OpenMP would
    #                                 make ggml-cpu.dll import vcomp140.dll,
    #                                 which the bundle does not carry; ggml
    #                                 then uses its own thread pool.
    Write-Step "configuring ($Generator / $Platform)"
    Invoke-Native $cmake @(
        '-S', (ToCMakePath $SrcDir),
        '-B', (ToCMakePath $BuildDir),
        '-G', $Generator,
        '-A', $Platform,
        "-DCMAKE_INSTALL_PREFIX=$(ToCMakePath $PkgDir)",
        '-DCMAKE_BUILD_TYPE=Release',
        '-DBUILD_SHARED_LIBS=ON',
        '-DWHISPER_BUILD_TESTS=OFF',
        '-DWHISPER_BUILD_EXAMPLES=OFF',
        '-DGGML_NATIVE=OFF',
        '-DGGML_OPENMP=OFF'
    ) 'cmake configure'

    Write-Step "building (--parallel $Parallel)"
    Invoke-Native $cmake @('--build', (ToCMakePath $BuildDir), '--config', 'Release',
                           '--parallel', "$Parallel") 'cmake build'

    Write-Step "installing to $PkgDir"
    Invoke-Native $cmake @('--install', (ToCMakePath $BuildDir), '--config', 'Release') 'cmake install'

    foreach ($d in $UpstreamDlls) { Place-Dll $d $BuildDir }
    # A fresh whisper build needs a fresh wrapper: drop the stamp.
    if (Test-Path $WrapStamp) { Remove-Item $WrapStamp -Force }
}

# --- 2. whisper_wrapper.dll ------------------------------------------------
# Rebuilt when absent, forced, or when native/whisper_wrapper.c changed.
$wrapperDst = Join-Path $BinDir $WrapperDll
$stampOk = (Test-Path $WrapStamp) -and
           ((Get-Content $WrapStamp -Raw).Trim() -eq $wrapperSha)
if ((Test-Path $wrapperDst) -and $stampOk -and -not $Force) {
    Write-Step "wrapper up to date: $wrapperDst"
} else {
    $cmake = Find-CMake
    # Import library of exactly this whisper build.
    $importLib = Get-ChildItem -Path $PkgDir, $BuildDir -Filter 'whisper.lib' -Recurse -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if (-not $importLib) {
        throw "No whisper.lib (import library) under $PkgDir or $BuildDir -- cannot link the wrapper."
    }
    foreach ($d in @($WrapSrcDir, $WrapBuildDir)) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    }
    New-Item -ItemType Directory -Force -Path $WrapSrcDir | Out-Null

    # MSVC exports nothing from a DLL by default; the wrapper source carries
    # no __declspec(dllexport) because it is shared with Linux/macOS/iOS.
    # WINDOWS_EXPORT_ALL_SYMBOLS exports its three functions without touching
    # the source. WHISPER_SHARED: whisper.h then declares the API dllimport,
    # matching whisper.dll (include/whisper.h, `#ifdef WHISPER_SHARED`).
    $cmakeLists = @"
cmake_minimum_required(VERSION 3.14)
project(whisper_wrapper C)
add_library(whisper_wrapper SHARED "$(ToCMakePath $WrapperC)")
set_target_properties(whisper_wrapper PROPERTIES
  PREFIX ""
  OUTPUT_NAME whisper_wrapper
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_include_directories(whisper_wrapper PRIVATE
  "$(ToCMakePath (Join-Path $SrcDir 'include'))"
  "$(ToCMakePath (Join-Path $SrcDir 'ggml\include'))")
target_compile_definitions(whisper_wrapper PRIVATE WHISPER_SHARED)
target_link_libraries(whisper_wrapper PRIVATE "$(ToCMakePath $importLib.FullName)")
"@
    Set-Content -Path (Join-Path $WrapSrcDir 'CMakeLists.txt') -Value $cmakeLists -Encoding ASCII

    Write-Step "building $WrapperDll from $WrapperC (header: $SrcDir\include\whisper.h)"
    Invoke-Native $cmake @(
        '-S', (ToCMakePath $WrapSrcDir),
        '-B', (ToCMakePath $WrapBuildDir),
        '-G', $Generator,
        '-A', $Platform
    ) 'cmake configure (wrapper)'
    Invoke-Native $cmake @('--build', (ToCMakePath $WrapBuildDir), '--config', 'Release') 'cmake build (wrapper)'

    if (Test-Path $wrapperDst) { Remove-Item $wrapperDst -Force }
    Place-Dll $WrapperDll $WrapBuildDir
    Set-Content -Path $WrapStamp -Value $wrapperSha -Encoding ASCII -NoNewline
}

# --- 3. Checks, fail-closed ------------------------------------------------
$dumpbin = Find-Tool 'dumpbin' @('VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe')
if (-not $dumpbin) {
    throw ('dumpbin.exe not found -- cannot verify the exports of the whisper ' +
           'DLLs. It ships with the MSVC build tools. Refusing to report ' +
           'unverified DLLs as provisioned.')
}
foreach ($name in $RequiredExports.Keys) {
    $path = Join-Path $BinDir $name
    if (-not (Test-Path $path)) { throw "missing after provisioning: $path" }
    $exports = & $dumpbin /nologo /exports $path
    if ($LASTEXITCODE -ne 0) { throw "dumpbin /exports failed (exit $LASTEXITCODE) on $path" }
    foreach ($sym in $RequiredExports[$name]) {
        # Whole-word match: whisper_full must not be satisfied by whisper_full_n_segments.
        if (-not ($exports | Select-String -Quiet -Pattern ("\s" + [regex]::Escape($sym) + "$"))) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
            throw "$path does not export $sym -- unusable for whisper_ffi.dart. Deleted."
        }
    }
    Write-Step "verified exports of ${name}: $($RequiredExports[$name] -join ', ')"

    # Imports: what the loader has to find for this DLL. Printed for the build
    # log; an OpenMP runtime import fails the provisioning (see GGML_OPENMP).
    $deps = & $dumpbin /nologo /dependents $path
    if ($LASTEXITCODE -ne 0) { throw "dumpbin /dependents failed (exit $LASTEXITCODE) on $path" }
    $depNames = @($deps | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\.dll$' -and $_ -notmatch '^Dump of' })
    Write-Step "  $name imports: $($depNames -join ' ')"
    if ($depNames | Where-Object { $_ -match '^vcomp' }) {
        throw "$path imports an OpenMP runtime ($($depNames -join ' ')) that the bundle does not carry."
    }
}
$wrapDeps = & $dumpbin /nologo /dependents (Join-Path $BinDir $WrapperDll)
if (-not ($wrapDeps | Select-String -Quiet -SimpleMatch 'whisper.dll')) {
    throw "$WrapperDll does not import whisper.dll -- it was not linked against this whisper build."
}

if ($EmitRootTo -and $EmitRootTo.Trim() -ne '') {
    $dir = Split-Path -Parent $EmitRootTo
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $EmitRootTo -Value $BinDir -Encoding ASCII -NoNewline
}

# Last stdout line is the bin directory, for callers that parse it.
Write-Output $BinDir
