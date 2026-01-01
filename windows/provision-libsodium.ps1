#Requires -Version 5.1
<#
.SYNOPSIS
    Provisions the pinned libsodium MSVC package for the Windows build.

.DESCRIPTION
    Windows equivalent of the libsodium provisioning that Android and macOS
    already do inside their build scripts:

        scripts/build-android-libs.sh   git clone --depth 1 --branch stable
        scripts/build-macos-libs.sh     LIBSODIUM_VERSION="1.0.20" + tarball

    Windows cannot use either of those. MSVC does not link against a DLL, it
    links against the import library (.lib) that is generated together with
    that DLL. Only the official pre-built package
    "libsodium-<version>-stable-msvc.zip" ships both, and they must come from
    the SAME archive: an import library from a different build resolves at
    link time and fails at load time.

    This script is idempotent (a present, complete package is left untouched)
    and fail-closed (a SHA-256 mismatch aborts and deletes the download).

    It only downloads and extracts. It does not copy anything into the source
    tree -- native/cleona_pow/CMakeLists.txt reads libsodium.lib and
    libsodium.dll out of the extracted package and windows/runner/CMakeLists.txt
    copies that same DLL into the app bundle, so both provably originate from
    one archive.

.PARAMETER Version
    libsodium version to provision. Must have a pinned hash below.

.PARAMETER Root
    Directory that holds provisioned packages. Default:
    $env:CLEONA_LIBS_DIR, else "$env:LOCALAPPDATA\cleona-libs".

.PARAMETER Force
    Re-download and re-extract even when the package is already present.

.PARAMETER EmitRootTo
    Optional file path. The resolved package root is written to it (one line),
    for callers that cannot parse stdout reliably.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-libsodium.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File windows\provision-libsodium.ps1 `
        -Root C:\cleona-libs -Version 1.0.20 -Force
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.20',
    [string]$Root = '',
    [switch]$Force,
    [string]$EmitRootTo = ''
)

$ErrorActionPreference = 'Stop'

# Invoke-WebRequest renders a Write-Progress bar for every buffer it receives.
# In a process that owns a console host -- which is exactly how this script is
# invoked (powershell.exe -File ... from a batch file or CI step) -- that
# rendering dominates the transfer. Measured on the build VM 2026-07-28 against
# the same URL within minutes of each other:
#   raw HTTP range request            1462 KB/s
#   Invoke-WebRequest in a background job (no console host)   790 KB/s
#   Invoke-WebRequest as invoked here (console host, default) 15.7 KB/s
# The 24 MB archive took 20 minutes instead of well under one, with 16 % CPU
# burned on drawing. Silencing the progress stream costs nothing: this script
# reports its own progress through Write-Step.
$ProgressPreference = 'SilentlyContinue'

# SHA-256 of the official archive, per version. Adding a version without its
# hash is refused: an unverified download is not a pinned dependency.
$KnownHashes = @{
    '1.0.20' = 'ebaa204fdfcedc51dc1ee1bbd03c8d552a14b3372f87f94e44c71a8533f77df4'
}

if (-not $KnownHashes.ContainsKey($Version)) {
    throw ("No pinned SHA-256 for libsodium $Version. Add the hash to " +
           "`$KnownHashes in windows\provision-libsodium.ps1 (verify it against " +
           "the minisign signature on download.libsodium.org) before using it.")
}
$ExpectedSha = $KnownHashes[$Version]

if (-not $Root -or $Root.Trim() -eq '') {
    if ($env:CLEONA_LIBS_DIR) {
        $Root = $env:CLEONA_LIBS_DIR
    } else {
        $Root = Join-Path $env:LOCALAPPDATA 'cleona-libs'
    }
}

$PkgName     = "libsodium-$Version-stable-msvc"
$ZipPath     = Join-Path $Root "$PkgName.zip"
$ExtractDir  = Join-Path $Root $PkgName
# The archive carries a single top-level directory named "libsodium".
$SodiumRoot  = Join-Path $ExtractDir 'libsodium'
$SentinelHdr = Join-Path $SodiumRoot 'include\sodium.h'
$Url         = "https://download.libsodium.org/libsodium/releases/$PkgName.zip"

function Write-Step($msg) { Write-Host "[provision-libsodium] $msg" }

function Get-Sha256([string]$path) {
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$alreadyThere = (Test-Path $SentinelHdr) -and
                (Test-Path (Join-Path $SodiumRoot 'x64\Release'))

if ($alreadyThere -and -not $Force) {
    Write-Step "already provisioned: $SodiumRoot"
} else {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

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
            throw ("SHA-256 mismatch for $PkgName.zip`n" +
                   "  expected $ExpectedSha`n" +
                   "  actual   $have`n" +
                   "Download rejected -- nothing was extracted.")
        }
        Move-Item $tmp $ZipPath -Force
        Write-Step "verified SHA-256 $ExpectedSha"
    }

    if (Test-Path $ExtractDir) {
        Write-Step "removing previous extraction: $ExtractDir"
        Remove-Item $ExtractDir -Recurse -Force
    }
    Write-Step "extracting to $ExtractDir"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    if (-not (Test-Path $SentinelHdr)) {
        throw ("Extraction did not produce $SentinelHdr -- archive layout " +
               "changed. Inspect $ExtractDir before adjusting this script.")
    }
    Write-Step "provisioned $SodiumRoot"
}

# Report what is available so a build log shows which toolsets could be picked.
$rel = Join-Path $SodiumRoot 'x64\Release'
if (Test-Path $rel) {
    $toolsets = (Get-ChildItem -Path $rel -Directory | Select-Object -ExpandProperty Name) -join ' '
    Write-Step "x64 toolsets in package: $toolsets"
}

if ($EmitRootTo -and $EmitRootTo.Trim() -ne '') {
    $dir = Split-Path -Parent $EmitRootTo
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $EmitRootTo -Value $SodiumRoot -Encoding ASCII -NoNewline
}

# Last stdout line is the package root, for callers that parse it.
Write-Output $SodiumRoot
