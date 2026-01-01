#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone build and measurement of cleona-play.exe on the Windows build VM.

.DESCRIPTION
    Builds windows/cleona_play/ on its own (no Flutter build) and measures what
    the decision record asks for before the helper goes into the bundle:
    tool versions, compiler warnings in our own file, size, subsystem, decode
    of every bundled sound, playback return value with timing, the PowerShell
    start it replaces, the audio endpoints the session sees, the presence of
    the Web Media Extensions package, and Defender detections.

    Runs ON the build VM inside the desktop session via a scheduled task
    (docs/WINDOWS_BUILD_SCRIPTS.md) -- the Visual Studio Build Tools need one.

    Log:    %CLEONA_TMP%\cleona-play-probe.log
    Marker: %CLEONA_TMP%\cleona-play-probe-exit.txt
            (ALL_DONE / FAIL_TOOLS / FAIL_CONFIGURE / FAIL_BUILD / FAIL_CHECK)
#>
[CmdletBinding()]
param(
    [string]$Project = $(if ($env:CLEONA_PROJECT) { $env:CLEONA_PROJECT } else { 'C:\Users\Cleona\Cleona' }),
    [string]$Tmp = $(if ($env:CLEONA_TMP) { $env:CLEONA_TMP } else { 'C:\tmp' }),
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$Platform = 'x64'
)

$ErrorActionPreference = 'Continue'
$Log = Join-Path $Tmp 'cleona-play-probe.log'
$Mark = Join-Path $Tmp 'cleona-play-probe-exit.txt'
$BuildDir = Join-Path $Tmp 'cleona-play-probe-build'
$Source = Join-Path $Project 'windows\cleona_play'
$Sounds = Join-Path $Project 'assets\sounds'

function Say([string]$line) { Add-Content -Path $Log -Value $line -Encoding UTF8 }
# The parameter must not be called `mark`: PowerShell names are not case
# sensitive, it would hide the marker PATH above.
function Done([string]$result) { Set-Content -Path $Mark -Value $result -Encoding ASCII; exit ($(if ($result -eq 'ALL_DONE') { 0 } else { 1 })) }

# Same lookup as windows/provision-opus.ps1: PATH first, then the Visual
# Studio installation.
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

Remove-Item $Mark -ErrorAction SilentlyContinue
Set-Content -Path $Log -Value "[$(Get-Date -Format o)] cleona-play probe started" -Encoding UTF8
Say "session: $env:SESSIONNAME  user: $env:USERNAME  interactive: $([Environment]::UserInteractive)"

# --- 1. tools ---------------------------------------------------------------
$cmake = Find-Tool 'cmake' @('Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
$git = Find-Tool 'git' @('Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe')
$dumpbin = Find-Tool 'dumpbin' @('VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe')
Say "== 1. tools"
Say "cmake:   $cmake"
Say "git:     $git"
Say "dumpbin: $dumpbin"
if (-not $cmake -or -not $git) { Say 'FAIL: cmake or git missing'; Done 'FAIL_TOOLS' }
Say ((& $cmake --version | Select-Object -First 1) -join '')
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    Say ('visual studio: ' + ((& $vswhere -latest -products * -property catalog_productDisplayVersion) -join ''))
    Say ('installation:  ' + ((& $vswhere -latest -products * -property installationPath) -join ''))
}
# git must be reachable for FetchContent, which calls it by name.
$env:PATH = (Split-Path $git) + ';' + $env:PATH

# --- 2. build ---------------------------------------------------------------
Say "== 2. build (fresh directory, sources fetched from github.com/xiph)"
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
$configure = Measure-Command {
    & $cmake -S $Source -B $BuildDir -G $Generator -A $Platform *>> (Join-Path $Tmp 'cleona-play-probe-configure.txt')
}
$configureExit = $LASTEXITCODE
Say "configure: exit $configureExit, $([int]$configure.TotalSeconds) s"
if ($configureExit -ne 0) {
    Get-Content (Join-Path $Tmp 'cleona-play-probe-configure.txt') -Tail 30 | ForEach-Object { Say $_ }
    Done 'FAIL_CONFIGURE'
}
$buildOut = Join-Path $Tmp 'cleona-play-probe-build.txt'
Remove-Item $buildOut -ErrorAction SilentlyContinue
$build = Measure-Command {
    & $cmake --build $BuildDir --config Release --parallel 6 *>> $buildOut
}
$buildExit = $LASTEXITCODE
Say "build: exit $buildExit, $([int]$build.TotalSeconds) s"
$warnAll = @(Select-String -Path $buildOut -Pattern ': warning ' -ErrorAction SilentlyContinue)
$warnOwn = @($warnAll | Where-Object { $_.Line -match 'cleona_play\.c' })
Say "warnings total: $($warnAll.Count), in cleona_play.c: $($warnOwn.Count)"
$warnAll | Group-Object { if ($_.Line -match 'warning (C\d+)') { $Matches[1] } else { 'other' } } |
    Sort-Object Count -Descending | ForEach-Object { Say "  $($_.Name): $($_.Count)" }
if ($buildExit -ne 0) {
    Get-Content $buildOut -Tail 40 | ForEach-Object { Say $_ }
    Done 'FAIL_BUILD'
}
$exe = Join-Path $BuildDir 'Release\cleona-play.exe'
if (-not (Test-Path $exe)) { Say "FAIL: $exe missing"; Done 'FAIL_BUILD' }

# --- 3. size, 4. subsystem ---------------------------------------------------
Say "== 3. size"
Say "cleona-play.exe: $((Get-Item $exe).Length) bytes"
Say "== 4. subsystem and imports"
if ($dumpbin) {
    (& $dumpbin /headers $exe | Select-String -Pattern 'subsystem|machine \(') | ForEach-Object { Say "  $($_.Line.Trim())" }
    (& $dumpbin /dependents $exe | Select-String -Pattern '\.dll') | ForEach-Object { Say "  needs $($_.Line.Trim())" }
}

# --- 7. every bundled sound: decode, then play --------------------------------
Say "== 7. decode (--check) and play, per file: exit code and wall time"
$allDecoded = $true
Get-ChildItem (Join-Path $Sounds '*.ogg') | Sort-Object Name | ForEach-Object {
    $file = $_.FullName
    $p = Start-Process -FilePath $exe -ArgumentList @("`"$file`"", '--check') -Wait -PassThru -WindowStyle Hidden
    $checkExit = $p.ExitCode
    if ($checkExit -ne 0) { $allDecoded = $false }
    $t = Measure-Command {
        $script:q = Start-Process -FilePath $exe -ArgumentList @("`"$file`"", '--volume', '0.5') -Wait -PassThru -WindowStyle Hidden
    }
    Say ("  {0,-22} check={1} play={2} {3,6} ms" -f $_.Name, $checkExit, $script:q.ExitCode, [int]$t.TotalMilliseconds)
}

# --- error paths ---------------------------------------------------------------
Say "== error paths"
$p = Start-Process -FilePath $exe -ArgumentList @('C:\does-not-exist.ogg') -Wait -PassThru -WindowStyle Hidden
Say "  missing file:  exit $($p.ExitCode) (expected 3)"
$p = Start-Process -FilePath $exe -ArgumentList @("`"$exe`"") -Wait -PassThru -WindowStyle Hidden
Say "  not vorbis:    exit $($p.ExitCode) (expected 4)"
$p = Start-Process -FilePath $exe -Wait -PassThru -WindowStyle Hidden
Say "  no argument:   exit $($p.ExitCode) (expected 2)"

# --- stop in the middle of a sound (the loop is ended by ending the process) ---
Say "== stop in the middle"
$ringback = Join-Path $Sounds 'ringback.ogg'
$p = Start-Process -FilePath $exe -ArgumentList @("`"$ringback`"") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 1500
$alive = -not $p.HasExited
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Say "  ringback after 1.5 s: running=$alive, after kill: exited=$($p.HasExited)"

# --- two at once -------------------------------------------------------------
Say "== two sounds at once"
$a = Start-Process -FilePath $exe -ArgumentList @("`"$ringback`"") -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 500
$b = Start-Process -FilePath $exe -ArgumentList @("`"$(Join-Path $Sounds 'message.ogg')`"") -Wait -PassThru -WindowStyle Hidden
Say "  message during ringback: exit $($b.ExitCode); ringback still running: $(-not $a.HasExited)"
Stop-Process -Id $a.Id -Force -ErrorAction SilentlyContinue

# --- 4b. what it replaces: one PowerShell start ---------------------------------
Say "== 4b. comparison: start of the PowerShell player that is replaced"
$t = Measure-Command {
    Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-Command', 'exit 0') -Wait -WindowStyle Hidden
}
Say "  powershell -NoProfile start+exit: $([int]$t.TotalMilliseconds) ms"

# --- 5. audio endpoints ------------------------------------------------------
Say "== 5. audio endpoints seen by this session"
Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue | ForEach-Object { Say "  device: $($_.Name) [$($_.Status)]" }
Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | ForEach-Object { Say "  endpoint: $($_.FriendlyName) [$($_.Status)]" }
Say "  audio service: $((Get-Service Audiosrv -ErrorAction SilentlyContinue).Status)"
# The number PlaySound itself depends on: output devices winmm offers to THIS
# session. 0 means every play above had to end with exit 5.
Add-Type -Namespace CleonaProbe -Name Winmm -MemberDefinition '[DllImport("winmm.dll")] public static extern uint waveOutGetNumDevs();'
Say "  waveOutGetNumDevs: $([CleonaProbe.Winmm]::waveOutGetNumDevs())"

# --- 8. Web Media Extensions -------------------------------------------------
Say "== 8. Microsoft.WebMediaExtensions"
$pkg = Get-AppxPackage Microsoft.WebMediaExtensions -ErrorAction SilentlyContinue
if ($pkg) { Say "  present: $($pkg.Version)" } else { Say '  not installed' }

# --- 9. Defender --------------------------------------------------------------
Say "== 9. Defender"
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) { Say "  real-time protection: $($mp.RealTimeProtectionEnabled), signatures: $($mp.AntivirusSignatureVersion)" }
$hits = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.Resources -match 'cleona-play' })
Say "  detections naming cleona-play: $($hits.Count)"

Say "[$(Get-Date -Format o)] probe finished"
if (-not $allDecoded) { Done 'FAIL_CHECK' }
Done 'ALL_DONE'
