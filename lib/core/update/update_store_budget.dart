import 'dart:math' show max;

import 'package:cleona/core/update/update_manifest.dart';

/// The update store as part of the bulk-cache class (S407-UPDATEFRAGMENTE).
///
/// v4_2 §21.2 table and §21.3.3 item 3: the bulk cache is ONE capped class,
/// desktop 1 GB, phone 100 MB (D-32); §31.3 tier 1: "Bulk cache of 1 GB …
/// and the objects of the binary distribution (§26.6.1), which only
/// desktops hold"; §26.6.1 step 3: "desktop installations hold the complete
/// objects of the current manifest; a phone holds none"; §5.5: the own
/// update target is "exempt from the bulk-cache cap until it is installed
/// or superseded". Until S407 the store had a budget of its own
/// (`kDesktopBudgetBytes` = 32 MiB, `kMobileBudgetBytes` = 5 MB) — smaller
/// than one linux binary (35 MB for 4.2.3), so a desktop evicted the
/// objects it is to hold.
///
/// Two halves of the one class:
///  * the pieces of lane 3 (mycelium `BulkHolder`) get the class less the
///    objects held for others (`BulkHolder.reserved`);
///  * the update store keeps what is protected ([heldForOthers], the
///    install target) unconditionally and everything else within the class
///    less the pieces ([updateStoreBudget]).

/// Whether a desktop holds [platform]/[version] for others: an object the
/// current [manifest] names, not fetched on demand for one visitor
/// (§26.6.3 "no network-wide advertising"). A phone holds none.
bool heldForOthers(UpdateManifest? manifest, String platform, String version,
    {required bool desktop, bool Function(String, String)? onDemand}) {
  if (!desktop || manifest == null) return false;
  if (version != manifest.version) return false;
  if (manifest.binaryHashes?[platform] == null) return false;
  return !(onDemand?.call(platform, version) ?? false);
}

/// What the update store may hold beyond its protected objects: the class
/// [classBytes] less what the pieces of lane 3 hold ([piecesBytes]).
int updateStoreBudget({required int classBytes, required int piecesBytes}) =>
    max(0, classBytes - piecesBytes);
