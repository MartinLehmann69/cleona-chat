#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions libzstd.dll for the Windows build from pinned upstream sources.

.DESCRIPTION
    Windows equivalent of the libzstd provisioning the Apple platforms already
    do inside their build scripts, pinned to the SAME version:

        scripts/build-ios-libs.sh       LIBZSTD_VERSION="1.5.6"
        scripts/build-macos-libs.sh     LIBZSTD_VERSION="1.5.6"

    One upstream version across all platforms is deliberate. zstd frames are
    forward and backward compatible, so this is less critical than for liboqs,
    but a single pin removes the question entirely and keeps the five platforms
    comparable.

    Built from source rather than downloaded. Nothing in this repository LINKS
    against libzstd -- no translation unit under native/ references it, it is
    loaded exclusively via DynamicLibrary.open('libzstd.dll') in
    lib/core/network/compression.dart. There is therefore no import library
    (.lib) that has to originate from the same archive as the DLL, which is the
    single reason libsodium must come from the official MSVC package (see
    windows/provision-libsodium.ps1).

    Before this script libzstd.dll simply lay hand-placed and unversioned in
    windows\runner\ on the build VM, with no recorded provenance at all -- not
    even a build script. docs/PUBLISHING.md 9.3a records an incident of exactly
    this class (v3.1.156 linked against a foreign source tree) and its lesson: a
    published artifact must demonstrably originate from its own sources.

    Fail-closed in three places:
      1. A version without a pinned commit SHA below is refused.
      2. After the clone, git rev-parse HEAD must equal that SHA. A tag is
         movable; this script exists for provability. On mismatch the tree is
         deleted and nothing is built.
      3. The finished DLL must export ZSTD_compress (checked with dumpbin
         /exports, the Windows counterpart to the nm -g assertions in
         scripts/build-ios-libs.sh). On absence the DLL is deleted.

    Idempotent: a complete package is left untouched unless -Force is given.

    It does not copy anything into the source tree.
    windows/runner/CMakeLists.txt reads the DLL out of the provisioned package
    and keeps the hand-placed windows/runner/libzstd.dll only as a fallback.

.PARAMETER Version
    zstd version to build. The git tag is "v<Version>". Must have a pinned
    commit SHA below.

.PARAMETER Root
    Directory that holds provisioned packages. Default:
    $env:CLEONA_LIBS_DIR, else "$env:LOCALAPPDATA\cleona-libs".

.PARAMETER Generator
    CMake generator. Override when the VM gets a different Visual Studio.

.PARAMETER Platform
    CMake generator platform (architecture).

.PARAMETER Parallel
    Compiler processes. `cmake --build` without --parallel calls MSBuild
    without /m and every file compiles serially (measured on the build VM
    2026-07-28: a single CL.exe on 8 cores). 6 rather than 8 because the VM has
    16 GB at roughly 73 % baseline usage.

.PARAMETER Force
    Re-clone, rebuild and re-install even when the package is already present.

.PARAMETER EmitRootTo
    Optional file path. The resolved package root is written to it (one line),
    for callers that cannot parse stdout reliably.

.PARAMETER EmitDllTo
    Optional file path. The resolved libzstd.dll path is written to it.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-libzstd.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-libzstd.ps1 `
        -Root C:\cleona-libs -Version 1.5.6 -Force
#>
[CmdletBinding()]
param(
    [string]$Version = '1.5.6',
    [string]$Root = '',
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$Platform = 'x64',
    [int]$Parallel = 6,
    [switch]$Force,
    [string]$EmitRootTo = '',
    [string]$EmitDllTo = ''
)

$ErrorActionPreference = 'Stop'

# Nothing here downloads over HTTP, but git and cmake write a lot of progress
# output and a stray Write-Progress renderer costs a factor of ~50 in a process
# that owns a console host (measured for Invoke-WebRequest on the build VM:
# 15.7 KB/s versus 1462 KB/s). Silenced for the same reason as in
# provision-libsodium.ps1.
$ProgressPreference = 'SilentlyContinue'

# Upstream commit per version. A git tag is movable, so the tag alone proves
# nothing; the commit SHA does. Verified 2026-07-30 by a real
# `git clone --depth 1 --branch v<version>` followed by `git rev-parse HEAD`:
#   1.5.6 -> 794ea1b0afca0f020f4e57b6732332231fb23c70
#            ("Merge pull request #3984 from facebook/dev", 2024-03-21)
# Note that v1.5.6 is an ANNOTATED tag: refs/tags/v1.5.6 is the tag object
# (35016bc1c0b9a2f7121b7ecc312100aad7d9f2ad), the commit is the peeled value
# refs/tags/v1.5.6^{}. rev-parse HEAD after checkout returns the commit, which
# is what is pinned here.
# Adding a version without its commit is refused: an unverified checkout is not
# a pinned dependency. To add one, clone the tag, read rev-parse HEAD, confirm
# it against the upstream release page, and record it here.
$KnownCommits = @{
    '1.5.6' = '794ea1b0afca0f020f4e57b6732332231fb23c70'
}

if (-not $KnownCommits.ContainsKey($Version)) {
    throw ("No pinned commit for libzstd $Version. Fill in `$KnownCommits " +
           "before use -- see docs/PUBLISHING.md")
}
$ExpectedCommit = $KnownCommits[$Version]
if (-not $ExpectedCommit -or $ExpectedCommit.Trim() -eq '') {
    throw ("No pinned commit for libzstd $Version. Fill in `$KnownCommits " +
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

$Url         = 'https://github.com/facebook/zstd.git'
$Tag         = "v$Version"
$PkgName     = "zstd-$Version"
$BaseDir     = Join-Path $Root $PkgName
$SrcDir      = Join-Path $BaseDir 'src'
$BuildDir    = Join-Path $BaseDir 'build'
$PkgDir      = Join-Path $BaseDir 'pkg'
# zstd keeps its CMake project in a subdirectory, not at the repository root --
# same path the Apple scripts use (build/cmake).
$CmakeSrcDir = Join-Path $SrcDir 'build\cmake'
# Upstream sets OUTPUT_NAME zstd on the shared target, so MSVC produces
# zstd.dll. The app opens it as libzstd.dll, matching the .so/.dylib names on
# the other platforms, so a copy under that name is placed next to it. Renaming
# a DLL is safe here precisely because nothing imports it: the name embedded in
# the PE header only matters for import resolution, and this DLL is opened by
# path via LoadLibrary. The upstream-named file is kept so the installed
# package stays an unmodified upstream install.
$DllPath     = Join-Path $PkgDir 'bin\libzstd.dll'
$RequiredSym = 'ZSTD_compress'

function Write-Step($msg) { Write-Host "[provision-libzstd] $msg" }

function Invoke-Native([string]$exe, [string[]]$argv, [string]$what) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) {
        throw "$what failed (exit $LASTEXITCODE): $exe $($argv -join ' ')"
    }
}

# CMake wants forward slashes even on Windows. A backslash path reaches the CMake
# language as an escape sequence -- "...\AppData\Local\..." carries \A and \L --
# which is why every CMake path variable is normalised this way (see
# file(TO_CMAKE_PATH ...) in native/cleona_pow/CMakeLists.txt). The PowerShell
# cmdlets accept both, so only the cmake arguments are converted.
function ToCMakePath([string]$p) { return $p.Replace('\', '/') }

function Find-Tool([string]$name, [string[]]$globs) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # vswhere ships with every Visual Studio 2017+ installer and is the only
    # supported way to locate a VS installation; hardcoded paths break on every
    # edition and update.
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
    Write-Step "cloning $Url @ $Tag"
    Invoke-Native $git @('clone', '--depth', '1', '--branch', $Tag,
                         '--config', 'advice.detachedHead=false',
                         $Url, $SrcDir) 'git clone'

    $head = (& $git -C $SrcDir rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse HEAD failed in the fresh clone.' }
    $head = $head.Trim().ToLowerInvariant()
    if ($head -ne $ExpectedCommit) {
        Remove-Item $SrcDir -Recurse -Force
        throw ("libzstd $Tag does not point at the pinned commit.`n" +
               "  expected $ExpectedCommit`n" +
               "  actual   $head`n" +
               "The tag moved upstream, or the remote is not the expected one. " +
               "Source tree deleted, nothing was built. Re-verify the tag and " +
               "update `$KnownCommits deliberately -- do not paste the new value blindly.")
    }
    Write-Step "verified commit $head"

    if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
    if (Test-Path $PkgDir)   { Remove-Item $PkgDir   -Recurse -Force }

    # SHARED here, STATIC on Apple: Apple links the libs into the Runner binary
    # (DynamicLibrary.process()), Windows dlopens them. Programs and tests are
    # off -- the app needs the library only.
    #
    # CMAKE_RC_FLAGS: the MSVC branch of build/cmake/lib/CMakeLists.txt adds
    # build/VS2010/libzstd-dll/libzstd-dll.rc as a source of the shared target
    # (`set(PlatformDependResources ...)`), and that .rc does `#include
    # "zstd.h"`. The library's own .c files never need an explicit include
    # path for this -- the C preprocessor's quoted-include search always
    # checks the including file's own directory first, and every .c file
    # already lives next to (or under) zstd.h in lib/. The .rc file does not:
    # it lives in build/VS2010/libzstd-dll/, a different directory, so its
    # quoted include has nothing to resolve against on its own.
    # target_include_directories(libzstd_shared INTERFACE ...) in that
    # CMakeLists.txt does not help either -- INTERFACE scope only reaches
    # something that LINKS AGAINST libzstd_shared, never the target's own
    # sources, and there is no other include_directories() call anywhere in
    # this project. So the resource compiler (rc.exe) has always been missing
    # this include path; nothing upstream ever demonstrated that on this
    # commit -- this script cloned it from CI logs that likely run on Ninja
    # (Apple) or with a different resource-file wiring, not this exact
    # Visual-Studio-generator path. Verified against a throwaway build of the
    # pinned commit (${ExpectedCommit}) on 2026-07-30: reproduces RC1015
    # ("cannot open include file 'zstd.h'") without this flag, builds and
    # exports ZSTD_compress with it.
    #
    # This does not touch the source tree (no file in $SrcDir is modified) --
    # only a build/tool CONFIGURATION parameter, the same class as
    # -DZSTD_BUILD_SHARED=ON below.
    $LibDir = Join-Path $SrcDir 'lib'
    Write-Step "configuring ($Generator / $Platform)"
    Invoke-Native $cmake @(
        '-S', (ToCMakePath $CmakeSrcDir),
        '-B', (ToCMakePath $BuildDir),
        '-G', $Generator,
        '-A', $Platform,
        "-DCMAKE_INSTALL_PREFIX=$(ToCMakePath $PkgDir)",
        '-DCMAKE_BUILD_TYPE=Release',
        '-DZSTD_BUILD_SHARED=ON',
        '-DZSTD_BUILD_STATIC=OFF',
        '-DZSTD_BUILD_PROGRAMS=OFF',
        '-DZSTD_BUILD_TESTS=OFF',
        "-DCMAKE_RC_FLAGS=/I `"$LibDir`""
    ) 'cmake configure'

    Write-Step "building (--parallel $Parallel)"
    Invoke-Native $cmake @('--build', (ToCMakePath $BuildDir), '--config', 'Release',
                           '--parallel', "$Parallel") 'cmake build'

    Write-Step "installing to $PkgDir"
    Invoke-Native $cmake @('--install', (ToCMakePath $BuildDir), '--config', 'Release') 'cmake install'

    $upstreamDll = Get-ChildItem -Path $PkgDir -Filter 'zstd.dll' -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    if (-not $upstreamDll) {
        # Other layouts put the DLL only in the build tree.
        $upstreamDll = Get-ChildItem -Path $BuildDir -Filter 'zstd.dll' -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Release' } |
                       Select-Object -First 1
    }
    if (-not $upstreamDll) {
        throw ("Build produced no zstd.dll under $PkgDir or $BuildDir. " +
               "ZSTD_BUILD_SHARED was ON, so the layout changed -- inspect the " +
               "trees before adjusting this script.")
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DllPath) | Out-Null
    Copy-Item $upstreamDll.FullName $DllPath -Force
    Write-Step "placed $DllPath (from $($upstreamDll.FullName))"
}

# Export check -- fail-closed. A DLL that builds and installs but exports
# nothing loads fine and then fails on the first lookup, at runtime, in the
# field. The MSVC branch of the zstd CMake project defines ZSTD_DLL_EXPORT=1 on
# the shared target (build/cmake/lib/CMakeLists.txt), which turns ZSTDLIB_API into
# __declspec(dllexport), so ZSTD_compress is present in a correct shared build.
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
           "compression.dart. Deleted. Check that ZSTD_BUILD_SHARED=ON took effect.")
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
