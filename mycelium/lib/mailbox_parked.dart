import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/envelope.dart' show EnvelopeBroken, KemParts;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/parked.dart';

/// The mailbox side of the parked cells (V4.2 §4.5.4, D-40, E7 = c): attach
/// the store of THIS identity, take a generation another own device rotated
/// to, and open what was parked for want of it (`parked.dart`).

/// Attaches the parked cells of [m]'s identity, stored next to its memory in
/// [directory] under [key]. Called once, by the mailbox's constructor.
void parkedAttach(Mailbox m, Directory directory, Uint8List key) =>
    parkedPut(m.identity,
        ParkedCells(directory: directory, key: key, report: m.report));

extension MailboxParked on Mailbox {
  /// Type 19 `KEM_ROTATED` arrived (§14.7): [fresh] becomes the current
  /// generation — the current one the ONE previous, exactly as on the
  /// rotating device ([keyChange], same [now]) — and the parked cells are
  /// opened. Returns how many opened.
  int kemTake(KemParts fresh, {DateTime? now}) {
    keyChange(fresh, now: now);
    return parkedOpen();
  }

  /// Opens the parked cells with the generations held now and feeds each as
  /// if just collected: a message is acknowledged to its sender and reaches
  /// the application like any other (which mirrors it, §14.2). What still
  /// does not open at the KEM goes back, keeping its time; anything else is
  /// dropped and reported. Returns how many opened.
  int parkedOpen() {
    final store = parkedOf(identity);
    if (store == null || store.held == 0) return 0;
    var opened = 0;
    var dropped = 0;
    for (final c in store.takeAll()) {
      try {
        if (kinds.isAmendment(c.cell[0])) {
          identity.amendments.receive(c.cell, c.origin);
        } else {
          identity.messages.receive(c.cell, null);
        }
        opened++;
      } on EnvelopeBroken catch (e) {
        if (e.reason == EnvelopeBroken.kemClosed) {
          store.putBack(c);
        } else {
          dropped++;
        }
      } on Object {
        dropped++;
      }
    }
    store.save();
    report?.call('parked: $opened opened, ${store.held} still parked'
        '${dropped == 0 ? '' : ', $dropped dropped (not a KEM failure)'}');
    return opened;
  }

  /// Cells of this identity lost unopened (expired or pushed out, D-40) —
  /// for the application's statistics.
  int get parkedLost => parkedOf(identity)?.lost ?? 0;

  /// Cells of this identity parked right now.
  int get parkedHeld => parkedOf(identity)?.held ?? 0;
}
