#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions opus.dll for the Windows build from pinned upstream sources.

.DESCRIPTION
    Windows equivalent of the libopus provisioning the other four platforms
    already do inside their build scripts, all pinned to the SAME version:

        scripts/build-android-libs.sh   LIBOPUS_VERSION="1.5.2"
        scripts/build-ios-libs.sh       LIBOPUS_VERSION="1.5.2"
        scripts/build-macos-libs.sh     LIBOPUS_VERSION="1.5.2"
        linux/CMakeLists.txt            CLEONA_OPUS_VERSION "1.5.2"

    One upstream version across all five platforms is deliberate, same
    reasoning as windows/provision-liboqs.ps1's version-drift comment:
    opus_ffi.dart (V1.9) talks Opus with a peer over the wire, and a version
    drift there is a correctness risk, not a cosmetic packaging detail.

    Built from source via opus's own upstream CMakeLists.txt (present since
    1.3, confirmed for this pin), the same shape as provision-liboqs.ps1 --
    NOT downloaded as a prebuilt package, because upstream does not publish
    one for MSVC the way libsodium does. Unlike libsodium this is built from
    source rather than downloaded. Nothing in this repository LINKS against
    opus -- no translation unit under native/ references it, it is loaded
    exclusively via DynamicLibrary.open() in lib/core/calls/opus_ffi.dart.
    There is therefore no import library (.lib) that has to originate from
    the same archive as the DLL, which is the single reason libsodium must
    come from the official MSVC package (see windows/provision-libsodium.ps1).

    Idempotent: a complete package is left untouched unless -Force is given.

    It does not copy anything into the source tree.
    windows/runner/CMakeLists.txt reads the DLL out of the provisioned package
    and keeps the hand-placed windows/runner/opus.dll only as a fallback.

.PARAMETER Version
    opus git tag to build. Must have a pinned commit SHA below.

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
    Re-clone, rebuild and re-install even when the package is already present.

.PARAMETER EmitRootTo
    Optional file path. The resolved package root is written to it (one line),
    for callers that cannot parse stdout reliably.

.PARAMETER EmitDllTo
    Optional file path. The resolved opus.dll path is written to it.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-opus.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-opus.ps1 `
        -Root C:\cleona-libs -Version 1.5.2 -Force
#>
[CmdletBinding()]
param(
    [string]$Version = '1.5.2',
    [string]$Root = '',
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$Platform = 'x64',
    [int]$Parallel = 6,
    [switch]$Force,
    [string]$EmitRootTo = '',
    [string]$EmitDllTo = ''
)

$ErrorActionPreference = 'Stop'

# Same reasoning as provision-liboqs.ps1: a stray Write-Progress renderer in a
# process that owns a console host costs a large factor on git/cmake output.
$ProgressPreference = 'SilentlyContinue'

# Upstream commit per tag. A git tag is movable, so the tag alone proves
# nothing; the commit SHA does. Verified 2026-07-30 by a real
# `git clone --depth 1 --branch v<tag>` followed by `git rev-parse HEAD`:
#   1.5.2 -> ddbe48383984d56acd9e1ab6a090c54ca6b735a6
#            ("Update DRED REDME.md", 2024-04-10)
# 1.5.2 is a lightweight tag, so refs/tags/v1.5.2 IS the commit; annotated
# tags would need the peeled value instead -- which is what rev-parse HEAD
# returns after checkout either way.
# Adding a version without its commit is refused: an unverified checkout is
# not a pinned dependency.
$KnownCommits = @{
    '1.5.2' = 'ddbe48383984d56acd9e1ab6a090c54ca6b735a6'
}

if (-not $KnownCommits.ContainsKey($Version)) {
    throw ("No pinned commit for opus $Version. Fill in `$KnownCommits " +
           "before use -- see docs/PUBLISHING.md")
}
$ExpectedCommit = $KnownCommits[$Version]
if (-not $ExpectedCommit -or $ExpectedCommit.Trim() -eq '') {
    throw ("No pinned commit for opus $Version. Fill in `$KnownCommits " +
           "before use -- see docs/PUBLISHING.md")
}
$ExpectedCommit = $ExpectedCommit.Trim().ToLowerInvariant()

if (-not $Root -or $Root.Trim() -eq '') {
    if ($env:CLEONA_LIBS_DIR) {
        $Root = $env:CLEONA_LIBS_DIR
    } else {
        $Root = Join-Path $env:LOCALAPPDATA 'cleona-libs'
    }
}

$Url         = 'https://github.com/xiph/opus.git'
$TagRef      = "v$Version"
$PkgName     = "opus-$Version"
$BaseDir     = Join-Path $Root $PkgName
$SrcDir      = Join-Path $BaseDir 'src'
$BuildDir    = Join-Path $BaseDir 'build'
$PkgDir      = Join-Path $BaseDir 'pkg'
# Upstream's own CMakeLists.txt (target "opus") names the MSVC output
# opus.dll -- no rename needed, unlike liboqs's oqs.dll -> liboqs.dll.
$DllPath     = Join-Path $PkgDir 'bin\opus.dll'
$RequiredSym = 'opus_strerror'

function Write-Step($msg) { Write-Host "[provision-opus] $msg" }

function Invoke-Native([string]$exe, [string[]]$argv, [string]$what) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) {
        throw "$what failed (exit $LASTEXITCODE): $exe $($argv -join ' ')"
    }
}

# CMake wants forward slashes even on Windows -- see provision-liboqs.ps1's
# comment on the same helper for why.
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

$alreadyThere = Test-Path $DllPath

if ($alreadyThere -and -not $Force) {
    Write-Step "already provisioned: $DllPath"
} else {
    $git = Find-Tool 'git' @('Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe')
    if (-not $git) { throw 'git not found in PATH -- install Git for Windows.' }
    $cmake = Find-Tool 'cmake' @(
        'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
    if (-not $cmake) {
        throw ('cmake not found in PATH and not in the Visual Studio ' +
               'installation -- install the "C++ CMake tools for Windows" component.')
    }
    Write-Step "git:   $git"
    Write-Step "cmake: $cmake"

    New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

    # A leftover tree cannot be trusted: it may be a different tag, a dirty
    # checkout or a partial clone. Cheaper to re-clone (shallow) than to prove
    # any of that.
    if (Test-Path $SrcDir) {
        Write-Step "removing previous source tree: $SrcDir"
        Remove-Item $SrcDir -Recurse -Force
    }
    Write-Step "cloning $Url @ $TagRef"
    Invoke-Native $git @('clone', '--depth', '1', '--branch', $TagRef,
                         '--config', 'advice.detachedHead=false',
                         $Url, $SrcDir) 'git clone'

    $head = (& $git -C $SrcDir rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse HEAD failed in the fresh clone.' }
    $head = $head.Trim().ToLowerInvariant()
    if ($head -ne $ExpectedCommit) {
        Remove-Item $SrcDir -Recurse -Force
        throw ("opus $TagRef does not point at the pinned commit.`n" +
               "  expected $ExpectedCommit`n" +
               "  actual   $head`n" +
               "The tag moved upstream, or the remote is not the expected one. " +
               "Source tree deleted, nothing was built. Re-verify the tag and " +
               "update `$KnownCommits deliberately -- do not paste the new value blindly.")
    }
    Write-Step "verified commit $head"

    if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
    if (Test-Path $PkgDir)   { Remove-Item $PkgDir   -Recurse -Force }

    # Flags mirror the other platforms so all five ship the same codec build:
    #   OPUS_BUILD_SHARED_LIBRARY=ON  produces opus.dll instead of a static lib
    #                                  (default OFF upstream).
    #   OPUS_BUILD_TESTING/PROGRAMS=OFF  no test binaries, no opus_demo.exe --
    #                                  matches --disable-doc --disable-extra-programs
    #                                  in scripts/build-ios-libs.sh's build_libopus().
    Write-Step "configuring ($Generator / $Platform)"
    Invoke-Native $cmake @(
        '-S', (ToCMakePath $SrcDir),
        '-B', (ToCMakePath $BuildDir),
        '-G', $Generator,
        '-A', $Platform,
        "-DCMAKE_INSTALL_PREFIX=$(ToCMakePath $PkgDir)",
        '-DCMAKE_BUILD_TYPE=Release',
        '-DOPUS_BUILD_SHARED_LIBRARY=ON',
        '-DOPUS_BUILD_TESTING=OFF',
        '-DOPUS_BUILD_PROGRAMS=OFF'
    ) 'cmake configure'

    Write-Step "building (--parallel $Parallel)"
    Invoke-Native $cmake @('--build', (ToCMakePath $BuildDir), '--config', 'Release',
                           '--parallel', "$Parallel") 'cmake build'

    Write-Step "installing to $PkgDir"
    Invoke-Native $cmake @('--install', (ToCMakePath $BuildDir), '--config', 'Release') 'cmake install'

    $upstreamDll = Get-ChildItem -Path $PkgDir -Filter 'opus.dll' -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    if (-not $upstreamDll) {
        # Older/other opus layouts put the DLL only in the build tree.
        $upstreamDll = Get-ChildItem -Path $BuildDir -Filter 'opus.dll' -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Release' } |
                       Select-Object -First 1
    }
    if (-not $upstreamDll) {
        throw ("Build produced no opus.dll under $PkgDir or $BuildDir. " +
               "OPUS_BUILD_SHARED_LIBRARY was ON, so the layout changed -- " +
               "inspect the trees before adjusting this script.")
    }
    if ($upstreamDll.FullName -ne $DllPath) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DllPath) | Out-Null
        Copy-Item $upstreamDll.FullName $DllPath -Force
        Write-Step "placed $DllPath (from $($upstreamDll.FullName))"
    }
}

# Export check -- fail-closed. A DLL that builds and installs but exports
# nothing loads fine and then fails on the first lookup, at runtime, in the
# field. opus_strerror is unconditionally compiled in (no optional feature
# gates it), the same reasoning provision-liboqs.ps1 gives for OQS_KEM_new.
$dumpbin = Find-Tool 'dumpbin' @('VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe')
if (-not $dumpbin) {
    throw ('dumpbin.exe not found -- cannot verify the exports of ' +
           "$DllPath. It ships with the MSVC build tools; locate it with " +
           'vswhere or run this script from a Developer Command Prompt. ' +
           'Refusing to report an unverified DLL as provisioned.')
}
$exports = & $dumpbin /nologo /exports $DllPath
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /exports failed (exit $LASTEXITCODE) on $DllPath"
}
if (-not ($exports | Select-String -SimpleMatch -Quiet $RequiredSym)) {
    Remove-Item $DllPath -Force -ErrorAction SilentlyContinue
    throw ("$DllPath does not export $RequiredSym -- the DLL is unusable for " +
           "opus_ffi.dart. Deleted. Check that OPUS_BUILD_SHARED_LIBRARY=ON took effect.")
}
Write-Step "verified export $RequiredSym"

if ($EmitRootTo -and $EmitRootTo.Trim() -ne '') {
    $dir = Split-Path -Parent $EmitRootTo
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $EmitRootTo -Value $PkgDir -Encoding ASCII -NoNewline
}
if ($EmitDllTo -and $EmitDllTo.Trim() -ne '') {
    $dir = Split-Path -Parent $EmitDllTo
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $EmitDllTo -Value $DllPath -Encoding ASCII -NoNewline
}

# Last stdout line is the DLL path, for callers that parse it.
Write-Output $DllPath
