# set-gui-subsystem.ps1 - marks a PE executable as a Windows-subsystem
# (GUI) program, so that Windows opens no console window when it starts.
#
# WHY (S407, v4_2 section 22 "Windows Desktop": "The daemon runs without a
# console window"). `dart build cli` produces cleona-daemon.exe as a console
# program. Started by the GUI (cmd.exe as a detached process - no console -
# which then starts the daemon), from `HKCU\...\Run`, from update-apply.bat
# (`start "" ...`) or a scheduled task, Windows gives it a console of its own;
# on Windows 11 that is a terminal window full of log lines, and closing it
# ends the daemon (measured on the lab VM with the v4.2.3 setup, 14.10.2026).
# The subsystem field decides this for EVERY start path at once; hiding the
# window per start path would have needed four separate fixes.
#
# What stays: standard handles a caller hands over still work: the GUI's
# launcher redirection into logs\daemon-stdio.log, and output over SSH
# (`--export-contact-seed`); cmd.exe running a batch file waits for the
# program and passes its exit code on (measured 14.10.2026 with a patched
# copy of the v4.2.3 daemon: stderr in the file, exit 64 seen). Without any
# handle (Run key, `start ""`) console output is switched off by CLogger
# (`disableConsole`), as for the console-less starts before.
#
# Only the 16-bit Subsystem field of the optional header changes (offset 68
# from its start, PE32 and PE32+ alike); entry point, size and the appended
# snapshot stay as they are. Fails closed: anything that is not a PE file
# with subsystem 2 or 3 ends with exit 1, and the value is read back.

param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
try {
  $b = [IO.File]::ReadAllBytes($Path)
  if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { throw "not an MZ file: $Path" }
  $pe = [BitConverter]::ToInt32($b, 0x3C)
  if ($pe -lt 0 -or $pe + 24 + 70 -gt $b.Length -or [BitConverter]::ToUInt32($b, $pe) -ne 0x4550) {
    throw "no PE header: $Path"
  }
  $off = $pe + 24 + 68
  $cur = [BitConverter]::ToUInt16($b, $off)
  if ($cur -ne 2 -and $cur -ne 3) { throw "unexpected subsystem $cur in $Path" }
  if ($cur -eq 3) {
    $b[$off] = 2; $b[$off + 1] = 0
    [IO.File]::WriteAllBytes($Path, $b)
  }
  $check = [BitConverter]::ToUInt16([IO.File]::ReadAllBytes($Path), $off)
  if ($check -ne 2) { throw "subsystem is $check after writing $Path" }
  Write-Output "set-gui-subsystem: $Path subsystem $cur -> 2"
  exit 0
} catch {
  Write-Output "set-gui-subsystem: FAILED: $_"
  exit 1
}
