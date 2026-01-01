import 'dart:io';

import 'identity_manager.dart';

/// ── THE HOST PART OF THE REMOTE DELETION (P-12) ───────────────────────────
///
/// In response to the message TWIN_IDENTITY_DELETED, `CleonaService` clears
/// away EVERYTHING that belongs to IT (`_wipeLocalIdentityData`: memory,
/// storage `messages.db`, legacy `*.json.enc`) and reports the deletion
/// upwards via [CleonaService.onIdentityDeletedRemotely]. What is then
/// still pending belongs to a layer above and is exactly this here:
///
///   1. the entry in `identities.json` (encrypted: `.enc`),
///   2. the profile directory itself — and with it the attachments
///      (`<profileDir>/media/*.cmenc`, `media_store.dart:25`).
///
/// [IdentityManager.deleteIdentity] does both in ONE step
/// (`identity_manager.dart:1319-1335`: `saveIdentities` without the entry,
/// then `dir.deleteSync(recursive: true)`).
///
/// ── WHY THIS STANDS HERE AND NOT TWICE IN THE HOST ───────────────────
///
/// There are TWO hosts: `service_daemon.dart` (Linux/Windows/macOS) and
/// the in-process path in `main.dart` (Android/iOS). Both need the same
/// body. A second copy would be the next place at which a deletion
/// deletes only on one platform — and a guard that measures a copy
/// measures a proxy.
/// `smoke_twin_identity_deleted_host.dart` runs EXACTLY THIS function.
///
/// ── WHAT DELIBERATELY DOES NOT HAPPEN HERE ─────────────────────────────────
///
/// NO renewed broadcast to the contacts (`broadcastIdentityDeleted`).
/// The deletion came from outside — the broadcast has already run on the
/// deleting device. A second one would be additional network traffic
/// without purpose (work rule #5). That is the only difference to the
/// tail of `_deleteIdentityAtRuntime`.
///
/// NO gate `_services.length <= 1`. Owner decision of 09.09.2026,
/// variant (b): the twin message overrules it. A device whose only
/// identity was deleted elsewhere ends with ZERO identities — otherwise
/// the promise "deleted on all my devices" would not hold precisely where
/// only one identity lives. For the IPC path (the user deletes himself)
/// the gate stays unchanged (`service_daemon.dart`
/// `_deleteIdentityAtRuntime`, `ipc_server.dart` `delete_identity`) —
/// there it is right.
///
/// The return value is the number of REMAINING identities. `0` means for
/// the host: go into the waiting state. What that means in each case is
/// decided by the host, not by this function — the daemon holds a
/// process and a tray, the UI holds a screen state.
int remoteDeletionRemoveEntry({
  required String nodeIdHex,
  required IdentityManager mgr,
  String? profileDir,
  void Function(String)? log,
}) {
  final identities = mgr.loadIdentities();

  // First by the identifier, then by the directory. The same order as in
  // the IPC path: `nodeIdHex` may be missing from an entry written before
  // the first start (`identity_manager.dart` sets it only when the
  // service is running) — then only the path holds.
  var match = identities.where((i) => i.nodeIdHex == nodeIdHex).toList();
  if (match.isEmpty && profileDir != null) {
    match = identities.where((i) => i.profileDir == profileDir).toList();
  }

  for (final id in match) {
    mgr.deleteIdentity(id.id);
  }

  final remaining = mgr.loadIdentities().length;
  log?.call('Remote deletion carried out: ${match.length} entry/entries '
      'removed from identities.json, profile directory deleted — '
      '$remaining identity(ies) remain');

  // Only a MEASUREMENT, not a second deletion path: if the directory stays
  // lying there, the deletion is not complete, and that must stand in the
  // log instead of passing silently. A deletion that does not delete is
  // the error.
  if (profileDir != null && Directory(profileDir).existsSync()) {
    log?.call('WARNING: profile directory $profileDir is STILL THERE after the '
        'remote deletion — entries hit: ${match.length}');
  }

  return remaining;
}
