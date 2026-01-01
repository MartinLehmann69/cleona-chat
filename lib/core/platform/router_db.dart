/// Router database for NAT-Troubleshooting-Wizard (§27.9.3).
///
/// Loads `assets/nat_wizard/router_db.json`, matches an [UpnpRouterInfo] to
/// a curated entry, or falls through to the generic entry.
///
/// Instructions are NOT stored in the JSON directly — only i18n keys are.
/// The UI layer resolves `steps_i18n_key` and `notes_i18n_key` via the
/// translations map.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Manufacturer and model of a router, as once read from the
/// UPnP `rootDesc`.
///
/// ── WHY THIS CLASS LIVES HERE AND NO LONGER IN THE NETWORK STATISTICS
///
/// Until 01.09.2026 (S360) it stood in `lib/core/stats/network_stats.dart`,
/// because its filler sat there: the UPnP detection filled
/// `NetworkStats.upnpRouterInfo`, and the wizard read it from there. With the
/// CUT of 31.08.2026 the detection fell and with it the filler.
///
/// **The class itself does not fall with it nonetheless.** The NAT wizard remains as
/// MANUAL help (tap on the connection icon -> instructions for
/// the own router), and [RouterDbEntry.matches] is the place that holds a
/// manufacturer/model statement against the curated list. It
/// therefore moves to the place that really needs it.
///
/// **CORRECTED ON 07.09.2026 (S373).** Here it said "V4.1 has no
/// NAT traversal (gap G-12) — there is no UPnP detection any more and
/// thus no filler". The first half-sentence was never an
/// architecture decision (v4_1 §25.9 lists "UPnP/PCP status, router info"
/// as a metric, §23.4 the port forwarding as "point of contact for others",
/// E-64 a `publicPort` assigned by UPnP-IGD), and the second has been
/// wrong since today: the detection is back
/// (`lib/core/link_io/upnp_igd.dart`), and `PortMapper.upnpRouterInfoJson`
/// delivers exactly the shape that [UpnpRouterInfo.fromJson] expects.
///
/// What is STILL missing is the path from there into this class: the GUI is a
/// separate process, it would need an IPC field and a getter on
/// `ICleonaService`. Until then the two callers (`main.dart`,
/// `home_screen.dart`) keep passing `null` in and the user chooses his
/// router himself — the instructions work, only the preselection is missing.
class UpnpRouterInfo {
  final String? manufacturer;
  final String? modelName;
  final String? modelNumber;
  final String? friendlyName;

  const UpnpRouterInfo({
    this.manufacturer,
    this.modelName,
    this.modelNumber,
    this.friendlyName,
  });

  bool get isEmpty =>
      (manufacturer?.isEmpty ?? true) &&
      (modelName?.isEmpty ?? true) &&
      (modelNumber?.isEmpty ?? true) &&
      (friendlyName?.isEmpty ?? true);

  Map<String, dynamic> toJson() => {
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (modelName != null) 'modelName': modelName,
        if (modelNumber != null) 'modelNumber': modelNumber,
        if (friendlyName != null) 'friendlyName': friendlyName,
      };

  static UpnpRouterInfo fromJson(Map<String, dynamic> json) => UpnpRouterInfo(
        manufacturer: json['manufacturer'] as String?,
        modelName: json['modelName'] as String?,
        modelNumber: json['modelNumber'] as String?,
        friendlyName: json['friendlyName'] as String?,
      );

  @override
  String toString() =>
      'UpnpRouterInfo(manufacturer=$manufacturer, model=$modelName, '
      'number=$modelNumber, friendly=$friendlyName)';
}

/// A single router entry from the database.
class RouterDbEntry {
  final String id;
  final String displayName;
  final List<String> manufacturerContains;
  final List<String> modelContains;
  final List<String> adminUrlHints;
  final String? deeplinkPath;
  final String stepsI18nKey;
  final String notesI18nKey;

  const RouterDbEntry({
    required this.id,
    required this.displayName,
    required this.manufacturerContains,
    required this.modelContains,
    required this.adminUrlHints,
    required this.deeplinkPath,
    required this.stepsI18nKey,
    required this.notesI18nKey,
  });

  /// True when both manufacturer and model (if specified) substring-match
  /// case-insensitively. The generic fallback has empty match lists and
  /// therefore matches anything.
  bool matches(UpnpRouterInfo? info) {
    if (manufacturerContains.isEmpty && modelContains.isEmpty) return true;
    final mfr = info?.manufacturer?.toLowerCase() ?? '';
    final model = info?.modelName?.toLowerCase() ?? '';
    if (manufacturerContains.isNotEmpty) {
      final hit = manufacturerContains.any((s) => mfr.contains(s.toLowerCase()));
      if (!hit) return false;
    }
    if (modelContains.isNotEmpty) {
      final hit = modelContains.any((s) => model.contains(s.toLowerCase()));
      if (!hit) return false;
    }
    return true;
  }

  static RouterDbEntry fromJson(Map<String, dynamic> json) {
    final match = (json['match'] as Map<String, dynamic>?) ?? const {};
    return RouterDbEntry(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? json['id'] as String,
      manufacturerContains: ((match['manufacturer_contains'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      modelContains: ((match['model_contains'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      adminUrlHints: ((json['admin_url_hints'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      deeplinkPath: json['deeplink_path'] as String?,
      stepsI18nKey: json['steps_i18n_key'] as String,
      notesI18nKey: json['notes_i18n_key'] as String,
    );
  }
}

/// Loads and queries the router database asset.
class RouterDb {
  static const String assetPath = 'assets/nat_wizard/router_db.json';

  final List<RouterDbEntry> entries;
  final int schemaVersion;

  const RouterDb._({required this.entries, required this.schemaVersion});

  /// Load the database from the flutter asset bundle. Call once at startup.
  static Future<RouterDb> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return fromJsonString(raw);
  }

  /// Parse from a JSON string (exposed for tests and non-flutter callers).
  static RouterDb fromJsonString(String jsonStr) {
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    final rawEntries = (decoded['entries'] as List?) ?? const [];
    final entries = rawEntries
        .cast<Map<String, dynamic>>()
        .map(RouterDbEntry.fromJson)
        .toList(growable: false);
    return RouterDb._(
      entries: entries,
      schemaVersion: decoded['schema_version'] as int? ?? 1,
    );
  }

  /// Return the first matching entry, or null if none match (including the
  /// generic entry). The generic entry should always match, so null usually
  /// means the DB is malformed / empty.
  RouterDbEntry? match(UpnpRouterInfo? info) {
    for (final entry in entries) {
      if (entry.matches(info)) return entry;
    }
    return null;
  }

  /// Alphabetical list of non-generic entries for the dropdown in Step 2.
  List<RouterDbEntry> get selectableEntries {
    return entries
        .where((e) => e.manufacturerContains.isNotEmpty || e.modelContains.isNotEmpty)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }
}
