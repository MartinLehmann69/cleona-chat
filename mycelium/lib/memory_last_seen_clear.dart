/// Once, at the first start of S405: every contact's last observed address
/// is cleared (owner decision 06.10.2026, S405 V2 = B).
///
/// Until `338bc827` (S405 E-4) a contact accepted through a forwarded
/// request kept the FORWARDER's address as its last observed address. Since
/// 122b8264 that made the forwarder "a contact's device", and every later
/// card of the issuer named no neighbour (field test 06.10.2026). The fix
/// stops new wrong entries; it does not touch stored ones, and nothing
/// replaces them by itself — messages do not set the last observed address
/// (`node_amendment.dart` passes only `returnRoute`), so a contact behind
/// carrier-grade NAT would carry the wrong one for good.
///
/// The address is evidence only — "a packet came from there" (§6.3). Without
/// it, a contact in the own segment is found by the search call at the next
/// sending (§7.2: a send without any address); over the internet steps 3
/// and 4 carry anyway. The price, named: one search call per contact in the
/// own segment, and step 1 waits for its answer.
///
/// ── "ONCE" WITHOUT A FILE OF ITS OWN ────────────────────────────────────
///
/// §4.5.2 names what lies below an identity's `mycelium/` — no marker file
/// (`smoke_history_in_store_run` guards it). The one-time event is the
/// first-contact store's version step that came with S405 F-1 (2 → 3,
/// `memory_first_contact.dart`): a mailbox whose store still carries an
/// older version starts for the first time with this release, and the
/// enforcer removes that store right after (`firstContactOpen`). A device
/// that never had a first contact has no store — and no contact whose
/// address a forwarded request could have set.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/memory.dart';
import 'package:mycelium/memory_first_contact.dart'
    show kFileFirstContact, kVersionFirstContact;

/// Clears every last observed address of [g] when the first-contact store in
/// [directory] still carries a version older than [kVersionFirstContact].
/// Reads, never deletes the store (that is the enforcer's). Returns how many
/// contacts were cleared.
int lastSeenClearAtUpgrade(
    Directory directory, Uint8List key, Memory g, void Function(String)? report) {
  final path = '${directory.path}/$kFileFirstContact';
  if (!File('$path.enc').existsSync()) return 0;
  final old = FileEncryption(baseDir: directory.path, key: key).readBinaryFile(path);
  if (old == null || old.isEmpty || old[0] >= kVersionFirstContact) return 0;
  var cleared = 0;
  for (final k in g.contacts) {
    if (k.lastSeen == null) continue;
    g.contactRemember(contactWithoutLastSeen(k));
    cleared++;
  }
  if (cleared > 0) g.save();
  report?.call('mycelium: first start with first-contact store version '
      '$kVersionFirstContact (was ${old[0]}) — last observed address cleared '
      'once for $cleared contact(s) (S405 V2)');
  return cleared;
}
