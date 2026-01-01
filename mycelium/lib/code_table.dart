/// The code table at the neighbour (V4.2 §8.1; proposal M, S391).
///
/// A device tells its fixed neighbour which codes belong to it —
/// not who it is. The neighbour holds "code → device", and a device is
/// its **device code** (16 B, `code_registration.dart`); the source address of the
/// registration stands IN the entry and is updated on every registration:
///
/// | Limit | Value |
/// |---|---|
/// | Codes per device | [kCodesPerDevice] — beyond it the oldest code of THIS device gives way |
/// | Devices | [kDevicesAtMost] — beyond it the device with the oldest registration gives way |
/// | Validity | until the end of the day after the code's day (UTC) |
/// | Precedence | whoever registers a code FIRST keeps it until expiry |
///
/// A later registration of the same code from a different DEVICE is
/// discarded and reported: otherwise every node could pull foreign codes to itself
/// as soon as it has seen them once (every forwarder sees them).
///
/// ── WHY NOT "ADDRESS:PORT" (S392, option B) ──────────────────────────
///
/// Until S392 a device WAS its source address here. Thus the rule
/// "whoever registers first" hit the own device that had moved: after NAT rebinding,
/// network change or a new port mapping the neighbour rejected every registration
/// until the old entry expired — 24 to 48 h without step 3 for ALL
/// contacts (`berichte/S392-M2-ADRESSWECHSEL.md`, finding B-1; plus B-3:
/// handshakes to the dead address, amplification 4). The rule itself is
/// in force unchanged — it now binds the code to the device instead of to
/// an address that does not belong to the device.
///
/// The table removes nothing on a clock. Expired entries fall out on
/// lookup and on the next registration of a new day.
/// A code that a device no longer registers (contact removed) thus lives
/// at most until the end of the following day.
///
/// Memory in the limit case: 256 × 4096 × 16 B ≈ 17 MB (proposal M, 3).
library;

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/pair.dart' show kCodeLength, utcDay;

/// Codes per device (§8.1).
const int kCodesPerDevice = 4096;

/// Devices per neighbour (§8.1).
const int kDevicesAtMost = 256;

class _Device {
  /// Where this device LAST registered — changeable, that is the
  /// point (§8.1, S392).
  InternetAddress address;
  int port;

  /// Code (hex) → Tag. Einfuegereihenfolge = Alter.
  final LinkedHashMap<String, int> codes = LinkedHashMap();
  DateTime last;
  _Device(this.address, this.port, this.last);
}

class CodeTable {
  final void Function(String)? report;

  /// Changeable ONLY for tests.
  DateTime Function() now;

  /// Device code (hex) → entry.
  final Map<String, _Device> _devices = {};

  /// Code (hex) → Geraetecode (hex).
  final Map<String, String> _owner = {};

  /// Device code (hex) + address type → where the device was last seen in
  /// that family (registration or keep-alive, §8.1). Only for devices in
  /// [_devices]; goes with them.
  final Map<String, (InternetAddress, int)> _seen = {};

  int _clearedAt = -1;

  /// Counters for probes and the network statistics — read only.
  int droppedForeign = 0;
  int droppedDay = 0;
  int droppedWithoutDevice = 0;
  int moves = 0;

  CodeTable({this.report, this.now = DateTime.now});

  int get countDevices => _devices.length;
  int get countCodes => _owner.length;

  /// How many codes the device [device] holds here.
  int codesFrom(Uint8List device) => _devices[_hex(device)]?.codes.length ?? 0;

  /// Where [device] last registered — `null` if it is none here.
  ({InternetAddress address, int port})? whereIs(Uint8List device) {
    final g = _devices[_hex(device)];
    return g == null ? null : (address: g.address, port: g.port);
  }

  /// The device (its code, hex) that last registered or kept alive here
  /// from [address]:[port] — `null` if none. The open check (§8.1) answers
  /// only for a device registered here and knows it only by the address
  /// its question came from.
  String? deviceAt(InternetAddress address, int port) {
    bool at((InternetAddress, int) w) =>
        w.$2 == port && w.$1.address == address.address;
    for (final e in _devices.entries) {
      if (at((e.value.address, e.value.port))) return e.key;
    }
    for (final e in _seen.entries) {
      if (at(e.value)) return e.key.split('/').first;
    }
    return null;
  }

  static bool _valid(int codeDay, int today) => today <= codeDay + 1;

  /// Registers [codes] of day [day] for the device [device], which is currently
  /// sending under [address]:[port]. Returns how many were
  /// accepted.
  int register(Uint8List device, InternetAddress address, int port, int day,
      Iterable<Uint8List> codes) {
    if (device.length != kCodeLength) {
      droppedWithoutDevice++;
      report?.call('Code registration from ${address.address}:$port without '
          'valid device code (${device.length} B) — discarded');
      return 0;
    }
    final today = utcDay(now());
    // A device registers today and tomorrow; one day of slack per direction for
    // a skewed clock. What has already expired only costs space.
    if (day < today - 1 || day > today + 2) {
      droppedDay++;
      report?.call('Code registration for day $day discarded (today $today)');
      return 0;
    }
    _clear(today);
    final who = _hex(device);
    final g = _devices.remove(who) ?? _Device(address, port, now());
    // THE point of S392: the same device under a new address keeps its
    // codes, the entry moves along. No packet, no clock — just a field.
    if (g.address.address != address.address || g.port != port) {
      moves++;
      report?.call('Device ${who.substring(0, 8)} now reports from '
          '${address.address}:$port instead of ${g.address.address}:${g.port} — '
          'entry moves along (§8.1)');
      g
        ..address = address
        ..port = port;
    }
    g.last = now();
    _seen[_seenKey(who, address)] = (address, port);
    _devices[who] = g; // to the end: most recent registration
    if (_devices.length > kDevicesAtMost) {
      final oldest = _devices.keys.first;
      _remove(oldest);
      report?.call('Code table full — device $oldest gives way');
    }
    var accepted = 0;
    var foreign = 0;
    for (final c in codes) {
      if (c.length != kCodeLength) continue;
      final h = _hex(c);
      final old = _owner[h];
      if (old != null && old != who) {
        final oldDay = _devices[old]?.codes[h];
        if (oldDay != null && _valid(oldDay, today)) {
          foreign++;
          continue;
        }
        _devices[old]?.codes.remove(h);
      }
      final soFar = g.codes.remove(h);
      g.codes[h] = soFar == null || soFar < day ? day : soFar;
      _owner[h] = who;
      accepted++;
      while (g.codes.length > kCodesPerDevice) {
        final route = g.codes.keys.first;
        g.codes.remove(route);
        _owner.remove(route);
      }
    }
    if (foreign > 0) {
      droppedForeign += foreign;
      report?.call('Code registration from device ${who.substring(0, 8)}: $foreign '
          'code(s) already belong to another device — discarded');
    }
    return accepted;
  }

  /// A keep-alive of [device] arrived from [address]:[port] (§8.1). The
  /// entry follows it when it is of the entry's family — step 3 then
  /// reaches the device at once, not only at its next registration.
  /// Returns `true` if the device was seen in this family before under
  /// ANOTHER address: its mapping has moved. A device that has not
  /// registered here is none of this table's business — `false`.
  bool sighted(Uint8List device, InternetAddress address, int port) {
    if (device.length != kCodeLength) return false;
    final who = _hex(device);
    final g = _devices[who];
    if (g == null) return false;
    final key = _seenKey(who, address);
    final before = _seen[key];
    _seen[key] = (address, port);
    if (g.address.type == address.type &&
        (g.address.address != address.address || g.port != port)) {
      moves++;
      report?.call('Device ${who.substring(0, 8)} keeps alive from '
          '${address.address}:$port instead of ${g.address.address}:${g.port} — '
          'entry moves along (§8.1)');
      g
        ..address = address
        ..port = port;
    }
    return before != null &&
        (before.$1.address != address.address || before.$2 != port);
  }

  static String _seenKey(String who, InternetAddress a) => '$who/${a.type.name}';

  /// The device that registered [code] here — `null` if none or
  /// expired.
  ({InternetAddress address, int port})? who(Uint8List code) {
    final h = _hex(code);
    final owner = _owner[h];
    if (owner == null) return null;
    final g = _devices[owner];
    final day = g?.codes[h];
    if (g == null || day == null) {
      _owner.remove(h);
      return null;
    }
    if (!_valid(day, utcDay(now()))) {
      g.codes.remove(h);
      _owner.remove(h);
      return null;
    }
    return (address: g.address, port: g.port);
  }

  /// Once per UTC day, everything expired goes out.
  void _clear(int today) {
    if (_clearedAt == today) return;
    _clearedAt = today;
    for (final g in _devices.values) {
      g.codes.removeWhere((h, day) {
        if (_valid(day, today)) return false;
        _owner.remove(h);
        return true;
      });
    }
    _devices.removeWhere((_, g) => g.codes.isEmpty);
    _seen.removeWhere((k, _) => !_devices.containsKey(k.split('/').first));
  }

  void _remove(String who) {
    final g = _devices.remove(who);
    if (g == null) return;
    _seen.removeWhere((k, _) => k.split('/').first == who);
    for (final h in g.codes.keys) {
      if (_owner[h] == who) _owner.remove(h);
    }
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
