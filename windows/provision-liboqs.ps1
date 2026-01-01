#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions liboqs.dll for the Windows build from pinned upstream sources.

.DESCRIPTION
    Windows equivalent of the liboqs provisioning the other four platforms
    already do inside their build scripts, all pinned to the SAME version:

        scripts/build-android-libs.sh   LIBOQS_VERSION="0.15.0"
        scripts/build-ios-libs.sh       LIBOQS_VERSION="0.15.0"
        scripts/build-macos-libs.sh     LIBOQS_VERSION="0.15.0"

    One upstream version across all five platforms is deliberate and not a
    packaging detail: a Windows client running a different liboqs than its peer
    is a correctness risk in the KEM/signature path, not a cosmetic difference.

    Unlike libsodium this is built from source rather than downloaded. Nothing
    in this repository LINKS against liboqs -- no translation unit under
    native/ references it, it is loaded exclusively via
    DynamicLibrary.open('liboqs.dll') in lib/core/crypto/oqs_ffi.dart. There is
    therefore no import library (.lib) that has to originate from the same
    archive as the DLL, which is the single reason libsodium must come from the
    official MSVC package (see windows/provision-libsodium.ps1).

    Supersedes windows/scripts/build-oqs.bat, which was removed with this
    script. That batch file pointed at whatever happened to live in
    C:\Users\Cleona\liboqs-src: no clone, no tag, no hash, not even an
    existence check. It documented the provenance of the resulting DLL no
    better than the DLL itself did. docs/PUBLISHING.md 9.3a records an incident
    of exactly this class (v3.1.156 linked against a foreign source tree) and
    its lesson: a published artifact must demonstrably originate from its own
    sources. Two build paths to the same DLL are the pattern that produces the
    error class (PUBLISHING.md 6.3a), so there is now one.

    Fail-closed in three places:
      1. A version without a pinned commit SHA below is refused.
      2. After the clone, git rev-parse HEAD must equal that SHA. A tag is
         movable; this script exists for provability. On mismatch the tree is
         deleted and nothing is built.
      3. The finished DLL must export OQS_KEM_new (checked with dumpbin
         /exports, the Windows counterpart to the nm -g assertions in
         scripts/build-ios-libs.sh). On absence the DLL is deleted.

    Idempotent: a complete package is left untouched unless -Force is given.

    It does not copy anything into the source tree.
    windows/runner/CMakeLists.txt reads the DLL out of the provisioned package
    and keeps the hand-placed windows/runner/liboqs.dll only as a fallback.

.PARAMETER Version
    liboqs git tag to build. Must have a pinned commit SHA below.

.PARAMETER Root
    Directory that holds provisioned packages. Default:
    $env:CLEONA_LIBS_DIR, else "$env:LOCALAPPDATA\cleona-libs".

.PARAMETER Generator
    CMake generator. Override when the VM gets a different Visual Studio.

.PARAMETER Platform
    CMake generator platform (architecture).

.PARAMETER Parallel
    Compiler processes. `cmake --build` without --parallel calls MSBuild
    without /m, which compiles liboqs -- a large library -- one file at a time
    (measured on the build VM 2026-07-28: a single CL.exe on 8 cores). 6 rather
    than 8 because the VM has 16 GB at roughly 73 % baseline usage.

.PARAMETER Force
    Re-clone, rebuild and re-install even when the package is already present.

.PARAMETER EmitRootTo
    Optional file path. The resolved package root is written to it (one line),
    for callers that cannot parse stdout reliably.

.PARAMETER EmitDllTo
    Optional file path. The resolved liboqs.dll path is written to it.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-liboqs.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-liboqs.ps1 `
        -Root C:\cleona-libs -Version 0.15.0 -Force
#>
[CmdletBinding()]
param(
    [string]$Version = '0.15.0',
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

# Upstream commit per tag. A git tag is movable, so the tag alone proves
# nothing; the commit SHA does. Verified 2026-07-30 by a real
# `git clone --depth 1 --branch <tag>` followed by `git rev-parse HEAD`:
#   0.15.0 -> 97f6b86b1b6d109cfd43cf276ae39c2e776aed80
#             ("0.15.0 full release [extended tests] (#2320)", 2025-11-14)
# 0.15.0 is a lightweight tag, so refs/tags/0.15.0 IS the commit; annotated
# tags would need the peeled value (refs/tags/X^{}) instead -- which is what
# rev-parse HEAD returns after checkout either way.
# Adding a version without its commit is refused: an unverified checkout is not
# a pinned dependency. To add one, clone the tag, read rev-parse HEAD, confirm
# it against the upstream release page, and record it here.
$KnownCommits = @{
    '0.15.0' = '97f6b86b1b6d109cfd43cf276ae39c2e776aed80'
}

if (-not $KnownCommits.ContainsKey($Version)) {
    throw ("No pinned commit for liboqs $Version. Fill in `$KnownCommits " +
           "before use -- see docs/PUBLISHING.md")
}
$ExpectedCommit = $KnownCommits[$Version]
if (-not $ExpectedCommit -or $ExpectedCommit.Trim() -eq '') {
    throw ("No pinned commit for liboqs $Version. Fill in `$KnownCommits " +
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

$Url         = 'https://github.com/open-quantum-safe/liboqs.git'
$PkgName     = "liboqs-$Version"
$BaseDir     = Join-Path $Root $PkgName
$SrcDir      = Join-Path $BaseDir 'src'
$BuildDir    = Join-Path $BaseDir 'build'
$PkgDir      = Join-Path $BaseDir 'pkg'
# Upstream names the MSVC output oqs.dll (target "oqs", and MSVC adds no "lib"
# prefix). The app opens it as liboqs.dll, matching the .so/.dylib names on the
# other platforms, so a copy under that name is placed next to it. Renaming a
# DLL is safe here precisely because nothing imports it: the name embedded in
# the PE header only matters for import resolution, and this DLL is opened by
# path via LoadLibrary. The upstream-named file is kept so the installed
# package stays an unmodified upstream install.
$DllPath     = Join-Path $PkgDir 'bin\liboqs.dll'
$RequiredSym = 'OQS_KEM_new'

function Write-Step($msg) { Write-Host "[provision-liboqs] $msg" }

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
    # edition and update. build-oqs.bat hardcoded one and had to fall back to a
    # recursive scan of Program Files (x86) when it was wrong.
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
    Write-Step "cloning $Url @ $Version"
    Invoke-Native $git @('clone', '--depth', '1', '--branch', $Version,
                         '--config', 'advice.detachedHead=false',
                         $Url, $SrcDir) 'git clone'

    $head = (& $git -C $SrcDir rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'git rev-parse HEAD failed in the fresh clone.' }
    $head = $head.Trim().ToLowerInvariant()
    if ($head -ne $ExpectedCommit) {
        Remove-Item $SrcDir -Recurse -Force
        throw ("liboqs $Version does not point at the pinned commit.`n" +
               "  expected $ExpectedCommit`n" +
               "  actual   $head`n" +
               "The tag moved upstream, or the remote is not the expected one. " +
               "Source tree deleted, nothing was built. Re-verify the tag and " +
               "update `$KnownCommits deliberately -- do not paste the new value blindly.")
    }
    Write-Step "verified commit $head"

    if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force }
    if (Test-Path $PkgDir)   { Remove-Item $PkgDir   -Recurse -Force }

    # Flags mirror the other platforms so all five ship the same algorithm set:
    #   OQS_USE_OPENSSL=OFF     no dependency on a machine-local OpenSSL, whose
    #                           provenance would be exactly as untraceable as
    #                           the DLL this script replaces, and no unbundled
    #                           libcrypto DLL at runtime.
    #   OQS_MINIMAL_BUILD       only what docs/CRYPTO.md uses: ML-KEM-768 and
    #                           ML-DSA-65.
    #   OQS_DIST_BUILD=ON       runtime CPU dispatch, so the DLL runs on any
    #                           x86-64 rather than only on the build machine.
    #   OQS_BUILD_ONLY_LIB=ON   no tests, no KAT vectors, no docs.
    Write-Step "configuring ($Generator / $Platform)"
    Invoke-Native $cmake @(
        '-S', (ToCMakePath $SrcDir),
        '-B', (ToCMakePath $BuildDir),
        '-G', $Generator,
        '-A', $Platform,
        "-DCMAKE_INSTALL_PREFIX=$(ToCMakePath $PkgDir)",
        '-DCMAKE_BUILD_TYPE=Release',
        '-DBUILD_SHARED_LIBS=ON',
        '-DOQS_BUILD_ONLY_LIB=ON',
        '-DOQS_USE_OPENSSL=OFF',
        '-DOQS_MINIMAL_BUILD=KEM_ml_kem_768;SIG_ml_dsa_65',
        '-DOQS_DIST_BUILD=ON'
    ) 'cmake configure'

    Write-Step "building (--parallel $Parallel)"
    Invoke-Native $cmake @('--build', (ToCMakePath $BuildDir), '--config', 'Release',
                           '--parallel', "$Parallel") 'cmake build'

    Write-Step "installing to $PkgDir"
    Invoke-Native $cmake @('--install', (ToCMakePath $BuildDir), '--config', 'Release') 'cmake install'

    $upstreamDll = Get-ChildItem -Path $PkgDir -Filter 'oqs.dll' -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    if (-not $upstreamDll) {
        # Older/other liboqs layouts put the DLL only in the build tree.
        $upstreamDll = Get-ChildItem -Path $BuildDir -Filter 'oqs.dll' -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Release' } |
                       Select-Object -First 1
    }
    if (-not $upstreamDll) {
        throw ("Build produced no oqs.dll under $PkgDir or $BuildDir. " +
               "BUILD_SHARED_LIBS was ON, so the layout changed -- inspect the " +
               "trees before adjusting this script.")
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DllPath) | Out-Null
    Copy-Item $upstreamDll.FullName $DllPath -Force
    Write-Step "placed $DllPath (from $($upstreamDll.FullName))"
}

# Export check -- fail-closed. A DLL that builds and installs but exports
# nothing loads fine and then fails on the first lookup, at runtime, in the
# field. OQS_API expands to __declspec(dllexport) on _WIN32
# (src/common/common.h), so this symbol is present in a correct shared build
# even with OQS_MINIMAL_BUILD, because OQS_KEM_new is the generic constructor
# rather than an algorithm entry point.
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
           "oqs_ffi.dart. Deleted. Check that BUILD_SHARED_LIBS=ON took effect.")
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
