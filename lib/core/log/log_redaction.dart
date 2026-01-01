import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../platform/app_paths.dart';
import '../util/ip_address_class.dart';

/// Redaction of sensitive quantities before a line goes into a log.
///
/// ── WHY THIS FILE EXISTS ────────────────────────────────────────
///
/// `Cleona_Chat_Architecture_v4_1.md` §4.5.3 lists the log files
/// under "Not encrypted with the identity key" and justifies this as follows:
///
///   > Log files — unencrypted, because they are debug output; sensitive
///   > material is redacted by the logger.
///
/// This redactor did not exist. Measured on 06.09.2026 against
/// `lib/core/log/clogger.dart`: zero hits for `redact`, `sanitiz`,
/// `scrub`. The document claimed a property without a carrier in the code.
/// This file is the carrier.
///
/// ── WHY AT THE SINK POINT AND NOT AT THE CALL SITE ──────────────
///
/// Measured on 06.09.2026 in `lib/`, across ALL call forms:
///
///     _log.<level>(       1508
///     log.<level>(         102
///     log?.<level>(         15
///     logger.<level>(        1
///     log?.call(            60
///     onLog?.call(           8
///                        ─────
///                         1694
///
/// An assurance that only holds if 1694 callers observe it is
/// no assurance. Exactly on that the protection has already failed once:
/// a guard that only looked at `_log.*` was blind to 164
/// places. The redaction therefore sits in `CLogger._write` — the
/// ONE point every line passes through before it reaches console, ring buffer
/// or file.
///
/// ── WHY "only at debug" DID NOT PROTECT ───────────────────────
///
/// `CLogger._log` only filters the CONSOLE by level. File and
/// ring buffer take every level except TRACE. A display name at
/// `debug` thus still lay in plaintext in the profile (3 days live, 7
/// beta) — and the ring buffer travels via the crash report (§9.5.8)
/// into the bug log to THIRD PARTIES.
///
/// ── THE STAND-IN ───────────────────────────────────────────────
///
/// A deleted quantity destroys the diagnostics; a log from which
/// nobody can read an error any more is worthless. Every redacted
/// quantity is therefore replaced by a STABLE marker:
///
///     `<name#3f2a1b9c>`, `<ip4-priv#8c01de55>`, `<host#11a9f0b2>`
///
/// The marker is HMAC-SHA256 under a **per-process-start random**
/// 32 B key, truncated to 4 B. Thus:
///
///   * within ONE run the same quantity is recognisable —
///     "the same partner", "the same address", "the same name" stay
///     readable, and that is the question asked in the field;
///   * across runs it is NOT, and the value cannot be computed back
///     from the marker: the key stands in no
///     log and does not survive the process.
///
/// **The price, expressly:** two nodes assign different markers for the same
/// address. A cross-node correlation
/// "the same IP here as there" is thus no longer possible. That is
/// intended — a key shared between nodes would make the marker
/// a network-wide pseudonym and thus exactly what is
/// prevented here.
///
/// The 8 hex digits are the same length that `shortPairLabel`
/// (`lib/core/service/v41_routing.dart:419`) uses for identifiers.
/// Unlike there, however, the marker here is NOT a prefix of the value: a
/// prefix of "Martin Lehmann" still names a person. A prefix
/// is fit for a public identifier, not for a name.
///
/// ── WHAT IS NOT REDACTED, AND WHY ──────────────────────────────
///
/// User ID, device node ID, device ID, field tags, key fingerprints,
/// group and channel identifiers stay in plaintext. They are
/// public or pseudonymous protocol quantities — the user ID stands in
/// every entry record —, and they carry the diagnostics. Likewise
/// port numbers, timestamps, module names, counters, file names and
/// stack traces stay.
abstract final class LogRedaction {
  /// Whether redaction happens.
  ///
  /// Default: on. It is switched off exclusively for the REVERSAL TEST of the
  /// guard, namely via `--define=CLEONA_LOG_REDACTION_OFF=true`
  /// — a COMPILE-TIME quantity. Deliberately NOT an environment variable:
  /// that could be set from outside on a shipped binary
  /// and would thus be a switch that clears away the protection at runtime.
  static bool enabled =
      !const bool.fromEnvironment('CLEONA_LOG_REDACTION_OFF');

  // ── Keys and markers ──────────────────────────────────────────

  static final List<int> _salt = _freshSalt();

  static List<int> _freshSalt() {
    final r = Random.secure();
    return List<int>.generate(32, (_) => r.nextInt(256));
  }

  static final Map<String, String> _labelCache = {};

  static String _label(String kind, String value) {
    final key = '$kind $value';
    final cached = _labelCache[key];
    if (cached != null) return cached;
    final mac = Hmac(sha256, _salt).convert(utf8.encode(key));
    final hex = mac.bytes
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final label = '<$kind#$hex>';
    _labelCache[key] = label;
    return label;
  }

  // ── Registered values ──────────────────────────────────────────────

  /// Word markers (names, machine name). Replaces only at token boundaries.
  static final Map<String, String> _names = {};
  static RegExp? _nameRe;

  /// Path roots. Replaces WITHOUT token boundary — they stand in the middle of a
  /// longer path.
  static final Map<String, String> _paths = {};
  static RegExp? _pathRe;

  /// Shortest length from which a name is replaced.
  ///
  /// A name below this length would strike everywhere as a substring
  /// — a display name "a" would hit every free-standing "a" in the
  /// log and make it unreadable. That is not a makeshift solution but
  /// proportionate: a name of one to two characters names
  /// nobody. It stays visible, and that is stated so in the report.
  static const int minNameLength = 3;

  /// Registers a name. Idempotent, cheap, callable at any time.
  ///
  /// [kind] only controls the label of the marker (`name`, `host`,
  /// `group`, `channel`).
  static void registerName(String? value, {String kind = 'name'}) {
    if (value == null) return;
    final v = value.trim();
    if (v.length < minNameLength) return;
    if (_names.containsKey(v)) return;
    _names[v] = _label(kind, v);
    _nameRe = null;
  }

  /// Registers a path root. [replacement] replaces it unchanged —
  /// for the own home directory that is `~`, because the
  /// entire diagnostics are thus preserved (the rest of the path is the
  /// structure of the application and names nobody) and still no
  /// user name stands there any more.
  static void registerPath(String? value, {String replacement = '~'}) {
    if (value == null) return;
    var v = value.trim();
    while (v.length > 1 && (v.endsWith('/') || v.endsWith('\\'))) {
      v = v.substring(0, v.length - 1);
    }
    // Do not register roots that are too short or shared: replacing `/tmp` as `~`
    // would mutilate every path under `/tmp` that has nothing to do with the
    // home directory.
    if (v.length < 5) return;
    if (v == '/tmp' || v == '/var' || v == '/data') return;
    if (_paths.containsKey(v)) return;
    _paths[v] = replacement;
    _pathRe = null;
  }

  /// Tests only: forget everything (key stays).
  static void resetForTest() {
    _names.clear();
    _paths.clear();
    _nameRe = null;
    _pathRe = null;
    _autoDone = false;
  }

  // ── Selbstanmeldung ────────────────────────────────────────────────

  static bool _autoDone = false;

  /// The redaction can find out the home directory and machine name
  /// itself. It does so here and not in the entry points,
  /// so that it cannot be forgotten — `service_daemon.dart` and
  /// `main.dart` are two entry points, and that would be two opportunities.
  static void _ensureAuto() {
    if (_autoDone) return;
    _autoDone = true; // FIRST — protects against re-entry.
    try {
      registerPath(AppPaths.home);
    } catch (_) {}
    try {
      final h = Platform.localHostname;
      if (h != 'localhost') registerName(h, kind: 'host');
    } catch (_) {}
  }

  // ── Strukturelle Muster ────────────────────────────────────────────

  /// A foreign home directory — one that is not the own and
  /// therefore does not go via [registerPath]. Measured on 06.09.2026:
  /// in the crash log of a run with `HOME=/tmp/...` there nonetheless stood
  /// `/home/claude/flutter/bin/...`, because the load path of the native
  /// libraries comes from the compiler path. Only the
  /// user segment is replaced; the rest of the path carries the
  /// diagnostics.
  static final RegExp _userHomeRe =
      RegExp(r'''(/home/|/Users/|[A-Za-z]:\\Users\\)([^/\\\s:"',;)\]}]+)''');

  /// Candidate for an IP address. Deliberately broad — confirmed
  /// exclusively via `InternetAddress.tryParse`, so that nothing
  /// is hit that merely looks like one (a time `09:02:22`, a
  /// version number `4.1.0`).
  static final RegExp _ipCandidateRe = RegExp(
      r'(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:\.\d{1,3}){0,3}'
      r'|(?:\d{1,3}\.){3}\d{1,3}');

  static String _ipLabel(String raw) {
    final norm = IpAddressClass.normalizeIp(raw);
    final addr = InternetAddress.tryParse(norm);
    if (addr == null) return raw; // was not an address after all

    // Loopback, multicast and the unspecified address name
    // nobody and carry diagnostics: they stay in plaintext.
    if (addr.isLoopback || addr.isMulticast) return raw;
    if (norm == '0.0.0.0' || norm == '::' || norm == '255.255.255.255') {
      return raw;
    }

    final v6 = addr.type == InternetAddressType.IPv6;
    // `IpAddressClass.isPrivate` keeps the one distinction that is
    // really asked in the field: does the node sit behind NAT or not.
    final scope = IpAddressClass.isPrivate(norm) ? 'priv' : 'pub';
    return _label(v6 ? 'ip6-$scope' : 'ip4-$scope', norm);
  }

  // ── Anwendung ──────────────────────────────────────────────────────

  static RegExp _buildLiteralRe(Iterable<String> values,
      {bool bounded = false}) {
    // Longest first: otherwise a name that is the prefix of another
    // wins, and the longer one would remain half standing.
    final sorted = values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final old = sorted.map(RegExp.escape).join('|');
    return bounded
        ? RegExp('(?<![A-Za-z0-9_])(?:$old)(?![A-Za-z0-9_])')
        : RegExp('(?:$old)');
  }

  /// Redacts [s]. Returns the string unchanged if
  /// there is nothing to do.
  static String apply(String s) {
    if (!enabled || s.isEmpty) return s;
    _ensureAuto();
    var out = s;

    // 1. Path roots first — otherwise `_userHomeRe` would strike on the
    //    own home directory and the `~` would never come about.
    if (_paths.isNotEmpty && (out.contains('/') || out.contains(r'\'))) {
      final re = _pathRe ??= _buildLiteralRe(_paths.keys);
      out = out.replaceAllMapped(re, (m) => _paths[m[0]] ?? m[0]!);
    }

    // 2. Foreign home directories.
    if (out.contains('/home/') ||
        out.contains('/Users/') ||
        out.contains(r'\Users\')) {
      out = out.replaceAllMapped(
          _userHomeRe, (m) => '${m[1]}${_label('user', m[2]!)}');
    }

    // 3. Registered names.
    if (_names.isNotEmpty) {
      final re = _nameRe ??= _buildLiteralRe(_names.keys, bounded: true);
      out = out.replaceAllMapped(re, (m) => _names[m[0]] ?? m[0]!);
    }

    // 4. IP addresses. The pre-test saves the regex run on the many
    //    lines without a digit-dot or colon sequence.
    if (out.contains('.') || out.contains(':')) {
      out = out.replaceAllMapped(_ipCandidateRe, (m) => _ipLabel(m[0]!));
    }

    return out;
  }
}
