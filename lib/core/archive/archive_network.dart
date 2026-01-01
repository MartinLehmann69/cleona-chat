// The optional narrowings in front of the share probe (§21.6, network
// detection).
//
// §21.6: "Two optional narrowings come before that probe and never replace
// it: the local subnet and default-gateway address (free of any permission
// on all five platforms), and an SSID list where the platform hands the name
// over without a location permission (Linux, Windows). A configured
// narrowing that does not match skips the run; an empty one narrows
// nothing."
//
// A narrowing only saves the attempt. It is NOT the gate — subnet, gateway
// address and SSID are all trivially forged by any foreign network; the gate
// is the share's identity (`share_identity.dart`).
//
// ── WHAT THIS PACKAGE READS, AND WHERE (S394, desktop package) ──────────
//
// * Subnet: `NetworkInterface.list()` on all five platforms. dart:io hands
//   out addresses WITHOUT a prefix length, so the subnet is the address's
//   /24 — measured API limit, not a choice. IPv4 only: many access providers
//   rotate the IPv6 prefix daily, a stored /64 would stop matching.
// * Gateway: Linux `ip route`, macOS `route -n get default`, Windows
//   `route print`. Android and iOS read none in this package (it needs
//   `LinkProperties` / `sysctl` in native code); there the device captures
//   the gateway as null and compares the subnet alone — it captures only
//   what it can read, and compares the same way.
// * SSID: Linux (nmcli, iwgetid) and Windows (netsh). macOS, Android and iOS
//   hand the name out only against a location permission; there the SSID
//   list is neither offered nor applied.

import 'dart:io';

import 'package:cleona/core/platform/process_runner.dart';
import 'package:cleona/core/util/host_interfaces.dart';

/// One network the user captured with "only in this network".
class ArchiveNetwork {
  /// IPv4 subnet in CIDR notation (`192.168.1.0/24`).
  final String subnet;

  /// Default-gateway address when captured; `null` where the platform does
  /// not read it (Android, iOS) — then the subnet alone decides.
  final String? gateway;

  const ArchiveNetwork({required this.subnet, this.gateway});

  bool matches(CurrentNetwork now) {
    if (!now.subnets.contains(subnet)) return false;
    return gateway == null || gateway == now.gateway;
  }

  @override
  bool operator ==(Object other) =>
      other is ArchiveNetwork &&
      other.subnet == subnet &&
      other.gateway == gateway;

  @override
  int get hashCode => Object.hash(subnet, gateway);

  Map<String, dynamic> toJson() =>
      {'subnet': subnet, if (gateway != null) 'gateway': gateway};

  static ArchiveNetwork? fromJson(Object? j) {
    if (j is! Map || j['subnet'] is! String) return null;
    final g = j['gateway'];
    return ArchiveNetwork(
        subnet: j['subnet'] as String, gateway: g is String ? g : null);
  }
}

/// What the device sees right now.
class CurrentNetwork {
  final List<String> subnets;
  final String? gateway;
  const CurrentNetwork({required this.subnets, this.gateway});

  /// The entry "only in this network" would store: the subnet that holds
  /// the gateway, else the first one. `null` without any IPv4 subnet.
  ArchiveNetwork? capture() {
    if (subnets.isEmpty) return null;
    final g = gateway;
    final holding = g == null ? null : subnet24(g);
    final subnet =
        holding != null && subnets.contains(holding) ? holding : subnets.first;
    return ArchiveNetwork(subnet: subnet, gateway: g);
  }
}

/// `a.b.c.d` → `a.b.c.0/24`; `null` for anything that is not IPv4.
String? subnet24(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return null;
  final n = p.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return null;
  return '${n[0]}.${n[1]}.${n[2]}.0/24';
}

/// Does this platform hand out the SSID without a location permission?
bool ssidReadableOn({required bool linux, required bool windows}) =>
    linux || windows;

bool get ssidReadableHere =>
    ssidReadableOn(linux: Platform.isLinux, windows: Platform.isWindows);

// ── Parsers (pure, so the probes can feed them the real outputs) ─────────

/// `ip -4 route show default` → `default via 192.168.1.1 dev wlp2s0 ...`
String? parseLinuxDefaultGateway(String out) =>
    RegExp(r'^default via (\d+\.\d+\.\d+\.\d+)', multiLine: true)
        .firstMatch(out)
        ?.group(1);

/// `route -n get default` → `    gateway: 192.168.1.1`
String? parseMacDefaultGateway(String out) =>
    RegExp(r'^\s*gateway:\s*(\d+\.\d+\.\d+\.\d+)\s*$', multiLine: true)
        .firstMatch(out)
        ?.group(1);

/// `route print -4` → `          0.0.0.0          0.0.0.0      192.168.1.1 ...`
/// (the column is `On-link` when there is no gateway — no match then).
String? parseWindowsDefaultGateway(String out) =>
    RegExp(r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)\s',
            multiLine: true)
        .firstMatch(out)
        ?.group(1);

/// `nmcli -t -f active,ssid dev wifi` → `yes:HomeNet`
String? parseNmcliSsid(String out) {
  for (final line in out.split('\n')) {
    if (line.startsWith('yes:')) {
      final s = line.substring(4).trim();
      if (s.isNotEmpty) return s;
    }
  }
  return null;
}

/// `netsh wlan show interfaces` → `    SSID                   : HomeNet`.
/// The `BSSID` line must not match; the label stays `SSID` in every
/// Windows display language (the other labels are translated).
String? parseNetshSsid(String out) {
  final m = RegExp(r'^\s*SSID\s*:\s*(.+?)\s*$', multiLine: true).firstMatch(out);
  final s = m?.group(1);
  return s == null || s.isEmpty ? null : s;
}

// ── Reading the device ───────────────────────────────────────────────────

const Duration _kToolTimeout = Duration(seconds: 5);

Future<String?> _tool(String exe, List<String> args) async {
  final r = await ProcessRunner.run(exe, args, timeout: _kToolTimeout);
  if (r == null || r.exitCode != 0) return null;
  return r.stdout as String;
}

/// The default-gateway address, where this package reads it (see header).
Future<String?> readDefaultGateway() async {
  try {
    if (Platform.isLinux) {
      final o = await _tool('ip', ['-4', 'route', 'show', 'default']);
      return o == null ? null : parseLinuxDefaultGateway(o);
    }
    if (Platform.isMacOS) {
      final o = await _tool('route', ['-n', 'get', 'default']);
      return o == null ? null : parseMacDefaultGateway(o);
    }
    if (Platform.isWindows) {
      final o = await _tool('route', ['print', '-4']);
      return o == null ? null : parseWindowsDefaultGateway(o);
    }
  } catch (_) {}
  return null; // Android, iOS: not in this package.
}

/// Subnets (/24, IPv4) of every interface that leads outside, plus gateway.
Future<CurrentNetwork> readCurrentNetwork() async {
  final subnets = <String>{};
  try {
    final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifs) {
      if (!interfaceLeadsAfterOutside(i.name)) continue;
      for (final a in i.addresses) {
        if (a.address.startsWith('169.254.')) continue;
        final s = subnet24(a.address);
        if (s != null) subnets.add(s);
      }
    }
  } catch (_) {}
  return CurrentNetwork(
      subnets: subnets.toList(), gateway: await readDefaultGateway());
}

/// The Wi-Fi name, where it is free (Linux, Windows); `null` elsewhere.
Future<String?> readCurrentSsid() async {
  try {
    if (Platform.isLinux) {
      final o = await _tool('nmcli', ['-t', '-f', 'active,ssid', 'dev', 'wifi']);
      final s = o == null ? null : parseNmcliSsid(o);
      if (s != null) return s;
      final o2 = await _tool('iwgetid', ['-r']);
      final s2 = o2?.trim();
      return s2 == null || s2.isEmpty ? null : s2;
    }
    if (Platform.isWindows) {
      final o = await _tool('netsh', ['wlan', 'show', 'interfaces']);
      return o == null ? null : parseNetshSsid(o);
    }
  } catch (_) {}
  return null;
}
