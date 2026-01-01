import 'dart:convert';
import 'dart:io';

/// The inbound firewall rule of the Windows daemon (v4_2 §22.x "Windows
/// Desktop", owner 14.10.2026 A).
///
/// The setup asks once for administrator rights and sets an inbound allow
/// rule for `cleona-daemon.exe` (UDP and TCP, all network profiles); the
/// application checks the rule at every start and, when it is missing or a
/// blocking rule stands, offers "Allow in firewall", which runs the same
/// elevated step. Both run the one helper script shipped in the bundle,
/// [helperFileName] (source `windows/cleona-firewall.cmd`), so there is one
/// definition of the rule.
///
/// Reading needs no rights: the COM object `HNetCfg.FwPolicy2` hands every
/// rule to a standard user. It is read through PowerShell because the
/// numeric fields of the COM object do not depend on the display language —
/// the text output of `netsh advfirewall firewall show rule` does
/// ("Aktion: Zulassen" on the German lab VM, measured 14.10.2026).
///
/// Until S407 the daemon ran `netsh advfirewall firewall add rule` itself at
/// start. Without administrator rights that always failed ("should be set by
/// installer") and nobody set the rule; Windows then asked at the first
/// listen, and "Cancel" left two blocking "Query User" rules for the program
/// (measured on the lab VM with the published v4.2.3 setup, 14.10.2026).
enum WindowsFirewallState {
  /// Allow rules for UDP and TCP cover every enabled profile, and no
  /// enabled blocking rule names the program.
  allowed,

  /// No allow rule (or not for every enabled profile, or not for both
  /// protocols), and no blocking rule.
  missing,

  /// An enabled inbound blocking rule names the program — a blocking rule
  /// wins over every allow rule in the Windows firewall.
  blocked,

  /// The check could not be run or its output was not complete.
  unknown,
}

/// One inbound rule naming the program, as read from `HNetCfg.FwPolicy2`.
class WindowsFirewallRule {
  /// `NET_FW_ACTION`: 0 block, 1 allow.
  final int action;

  /// IANA protocol number: 6 TCP, 17 UDP, 256 any.
  final int protocol;

  /// `NET_FW_PROFILE_TYPE2` bit mask: 1 domain, 2 private, 4 public
  /// (0x7FFFFFFF = all).
  final int profiles;

  final bool enabled;

  const WindowsFirewallRule({
    required this.action,
    required this.protocol,
    required this.profiles,
    required this.enabled,
  });
}

abstract final class WindowsFirewall {
  /// The helper script in the bundle root, beside `cleona.exe`.
  static const String helperFileName = 'cleona-firewall.cmd';

  static const int _udp = 17, _tcp = 6, _anyProtocol = 256;
  static const int _allProfiles = 1 | 2 | 4;

  /// The end marker of the check script: without it the output is
  /// incomplete and the state [WindowsFirewallState.unknown].
  static const String _endMarker = 'END';

  /// The PowerShell script that lists every inbound rule naming [exe] and
  /// the profiles in which the firewall is on. One line per rule
  /// `R|action|protocol|profiles|enabled`, one line `F|mask`, then [_endMarker].
  ///
  /// Paths are compared without regard to case and after expanding
  /// environment variables: the "Query User" rules Windows creates carry
  /// the path in lower case (`c:\users\cleona\appdata\local\cleona chat\…`,
  /// measured 14.10.2026).
  static String checkScript(String exe) {
    final e = exe.replaceAll("'", "''");
    return '\$ErrorActionPreference = \'Stop\'\n'
        '\$exe = [IO.Path]::GetFullPath(\'$e\')\n'
        '\$p = New-Object -ComObject HNetCfg.FwPolicy2\n'
        '\$on = 0\n'
        'foreach (\$t in 1, 2, 4) { if (\$p.FirewallEnabled(\$t)) { \$on = \$on -bor \$t } }\n'
        'foreach (\$r in \$p.Rules) {\n'
        '  if (\$r.Direction -ne 1) { continue }\n'
        '  \$a = \$r.ApplicationName\n'
        '  if (-not \$a) { continue }\n'
        '  \$a = [Environment]::ExpandEnvironmentVariables(\$a)\n'
        '  if ([string]::Compare(\$a, \$exe, \$true) -ne 0) { continue }\n'
        '  \'R|{0}|{1}|{2}|{3}\' -f [int]\$r.Action, [int]\$r.Protocol, '
        '[int]\$r.Profiles, [int][bool]\$r.Enabled\n'
        '}\n'
        '\'F|\' + \$on\n'
        '\'$_endMarker\'\n';
  }

  /// Evaluates the output of [checkScript]. Pure, so the smoke checks every
  /// case on any platform.
  static WindowsFirewallState evaluate(String output) {
    final rules = <WindowsFirewallRule>[];
    int? enabledProfiles;
    var complete = false;
    for (final raw in const LineSplitter().convert(output)) {
      final line = raw.trim();
      if (line == _endMarker) {
        complete = true;
        continue;
      }
      final parts = line.split('|');
      if (parts.first == 'F' && parts.length == 2) {
        enabledProfiles = int.tryParse(parts[1]);
      } else if (parts.first == 'R' && parts.length == 5) {
        final v = parts.skip(1).map(int.tryParse).toList();
        if (v.contains(null)) return WindowsFirewallState.unknown;
        rules.add(WindowsFirewallRule(
            action: v[0]!, protocol: v[1]!, profiles: v[2]!,
            enabled: v[3] != 0));
      }
    }
    if (!complete || enabledProfiles == null) {
      return WindowsFirewallState.unknown;
    }
    return evaluateRules(rules, enabledProfiles);
  }

  /// The decision on parsed rules. [enabledProfiles] is the mask of the
  /// profiles in which the firewall is on; a profile with the firewall off
  /// needs no rule.
  static WindowsFirewallState evaluateRules(
      List<WindowsFirewallRule> rules, int enabledProfiles) {
    final need = enabledProfiles & _allProfiles;
    if (need == 0) return WindowsFirewallState.allowed;
    bool covers(int proto, int p) => p == proto || p == _anyProtocol;
    var udp = 0, tcp = 0;
    for (final r in rules) {
      if (!r.enabled) continue;
      final relevant = covers(_udp, r.protocol) || covers(_tcp, r.protocol);
      if (r.action == 0 && relevant && (r.profiles & need) != 0) {
        return WindowsFirewallState.blocked;
      }
      if (r.action != 1) continue;
      if (covers(_udp, r.protocol)) udp |= r.profiles;
      if (covers(_tcp, r.protocol)) tcp |= r.profiles;
    }
    final ok = (udp & need) == need && (tcp & need) == need;
    return ok ? WindowsFirewallState.allowed : WindowsFirewallState.missing;
  }

  /// Runs [checkScript] for [exe] (no rights needed).
  static Future<WindowsFirewallState> check(String exe) async {
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-EncodedCommand', encodeCommand(checkScript(exe)),
      ]).timeout(const Duration(seconds: 60));
      if (r.exitCode != 0) return WindowsFirewallState.unknown;
      return evaluate(r.stdout.toString());
    } catch (_) {
      return WindowsFirewallState.unknown;
    }
  }

  /// The PowerShell script that runs the helper elevated (one consent
  /// prompt of Windows) and passes its exit code on. When `Start-Process`
  /// fails — in practice: the consent was declined — the script ends with
  /// 1223 (`ERROR_CANCELLED`).
  static String allowScript({required String helper, required String exe}) {
    // Single-quoted PowerShell strings: a quote inside is doubled.
    //
    // The helper runs through `cmd.exe /d /s /c ""<helper>" allow "<exe>""`,
    // not as the file itself. Measured on the lab VM 14.10.2026: started
    // directly with the verb RunAs, Windows runs the .cmd as
    // `cmd.exe /C "<helper>" allow "<exe>"`; with more than two quotes and
    // no /S, cmd.exe strips the first and the last quote, the path breaks at
    // the space of "Cleona Chat", and the helper ends with exit 1 without
    // setting a rule. /S makes the stripping of the outer pair explicit.
    final h = helper.replaceAll("'", "''");
    final e = exe.replaceAll("'", "''");
    return '\$ErrorActionPreference = \'Stop\'\n'
        'try {\n'
        '  \$p = Start-Process -FilePath \'cmd.exe\' '
        '-ArgumentList \'/d /s /c ""$h" allow "$e""\' '
        '-Verb RunAs -WindowStyle Hidden -Wait -PassThru\n'
        '  exit \$p.ExitCode\n'
        '} catch {\n'
        '  exit 1223\n'
        '}\n';
  }

  /// Runs the helper elevated with `allow` for [exe]. Returns the exit code
  /// of the helper (0 = rule set), 1223 when the consent was declined.
  static Future<int> allow({required String helper, required String exe}) async {
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-EncodedCommand', encodeCommand(allowScript(helper: helper, exe: exe)),
      ]);
      return r.exitCode;
    } catch (_) {
      return -1;
    }
  }

  /// `-EncodedCommand` takes base64 of UTF-16LE. Used instead of `-Command`
  /// so no path needs quoting on the command line.
  static String encodeCommand(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return base64Encode(bytes);
  }
}
