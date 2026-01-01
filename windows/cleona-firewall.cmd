@echo off
rem Cleona Chat: the inbound firewall rule of the daemon (v4_2 section 22,
rem "Windows Desktop"). Runs elevated; started by the setup (once, after one
rem consent), by the uninstaller, and by the app's "Allow in firewall".
rem
rem   cleona-firewall.cmd allow  "<full path of cleona-daemon.exe>" [beta]
rem   cleona-firewall.cmd remove "<full path of cleona-daemon.exe>"
rem
rem Every inbound rule naming the program goes first: an allow rule from an
rem earlier run, and the blocking "Query User" rules Windows leaves behind
rem when its own prompt was cancelled (a blocking rule wins over every allow
rem rule). Then "allow" sets one rule for UDP and one for TCP, all network
rem profiles. The rule names the program path, not a port, so updates into
rem the same folder keep it.
rem
rem No labels and no blocks: the file reaches the bundle with LF line ends.
rem Exit codes: 0 done, 2 bad arguments, 3 netsh refused to add a rule.
setlocal
set "ACTION=%~1"
set "EXE=%~2"
if "%EXE%"=="" exit /b 2
if /I not "%ACTION%"=="allow" if /I not "%ACTION%"=="remove" exit /b 2
netsh advfirewall firewall delete rule name=all dir=in program="%EXE%" >nul 2>&1
if /I "%ACTION%"=="remove" exit /b 0
set "RULE=Cleona Chat"
if /I "%~3"=="beta" set "RULE=Cleona Beta"
netsh advfirewall firewall add rule name="%RULE% (UDP)" dir=in action=allow protocol=UDP program="%EXE%" profile=any enable=yes >nul || exit /b 3
netsh advfirewall firewall add rule name="%RULE% (TCP)" dir=in action=allow protocol=TCP program="%EXE%" profile=any enable=yes >nul || exit /b 3
exit /b 0
