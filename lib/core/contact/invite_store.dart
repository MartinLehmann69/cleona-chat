// The encrypted storage of the invitation ledger (§21.4).
//
// WHY ENCRYPTED AND NOT ON THE SIDE. §21.4 is explicit: the local identity
// data lie under the seed-derived key, and "a ‚cache directory' …
// outside encryption is explicitly impermissible". The invitation ledger
// is exactly such a correlation target: it lists HOW MANY invitations a
// node holds open, with which label and since when. Whoever finds it in
// plaintext has the tag lines this node listens to (§15.3.2) — they can
// be computed from index and generation as soon as the seed is added,
// and already the NUMBER is information about the person.
//
// WHAT IS NOT IN THE STORAGE: no `K_inv(i)`, no invitation root, no
// seed. All of that is computed (`InviteLedger.keyFor`), none of it
// stored.
library;

import 'package:cleona/core/contact/invite_ledger.dart';
import 'package:cleona/core/storage/message_store.dart';

/// Loads and writes the invitation ledger of an identity.
///
/// S366: until now the ledger lay as `invites.json.enc` per identity in
/// the profile and was rewritten completely on EVERY change. That is
/// exactly the pattern the storage is built against, and here it weighs
/// more heavily than elsewhere: **the ledger grows monotonically.**
/// `kMaxOpenInvites` (ten) caps only the OPEN invitations; revoked,
/// expired and generation-step-invalidated records remain, because
/// `byIndex` still needs them. An identity that invites over years thus
/// rewrites an ever longer ledger every time.
///
/// That is why [MessageStore.putEntry] stands here and not `replaceArea`:
/// an issuing costs two rows (the new record and the header), no matter
/// how long the ledger is.
///
/// [store] may be `null` — that is the UI proxy (IPC client), which has
/// no profile on disk. Then nothing happens, the same construction as in
/// `PollManager`.
class InviteStore {
  /// The profile directory of the identity (`~/.cleona/identities/<id>`).
  ///
  /// No longer needed for writing — the storage knows its own path.
  /// Remains, because callers and log lines pin the identity to it.
  final String profileDir;

  final MessageStore? _store;

  // `this._store` is still called `store` at the CALL SITE — since
  // language version 3.x Dart maps the private name onto the public one.
  // The call thus stays the same as in `PollManager` and `ChannelIndex`.
  InviteStore({required this.profileDir, this._store});

  /// The area in the table `state`.
  static const String area = 'invites';

  /// The header record: generation, highwater and the withdrawn
  /// generations. It carries a leading underscore so that it cannot
  /// collide with any record key — those look like `3:17`.
  static const String headerKey = '_';

  /// The key of ONE record.
  ///
  /// Generation AND index, although today the index alone would already
  /// be unique (`issue` keeps counting `highwater` across generation
  /// boundaries). That is intentional: `byIndex` asks for both, and a
  /// key that is only unique by chance is one that no longer is at the
  /// next rework.
  static String keyFor(InviteRecord rec) =>
      '${rec.generation}:${rec.index}';

  /// Loads the ledger. A missing ledger is an empty ledger — an identity
  /// that has never issued an invitation is the normal case and not an
  /// error.
  ///
  /// **An unreadable ledger is not.** An empty ledger at this point would
  /// not be a harmless loss: the next `issue()` would start at index 0
  /// again, and TWO invitations would get the same `K_inv(i)` — the same
  /// promise for two different people.
  ///
  /// ── THE DATA-LOSS LATCH, AND WHAT IT HANGS ON NOW ─────────────
  ///
  /// Until S366 it asked about the FILE: "`readJsonFile` returned `null`,
  /// but `invites.json.enc` is there" — i.e. unreadable instead of
  /// missing. After the switch this file no longer exists; the same latch
  /// would have stayed silently green and would no longer have held
  /// anything. It now measures the same statement on the new carrier: if
  /// there are rows in the storage (`countArea`) from which nevertheless
  /// no ledger can be built, it THROWS and does not start at 0.
  ///
  /// Two paths lead there, and both are covered:
  ///   1. the header record is missing while records are there,
  ///   2. `loadArea` returns nothing at all although `countArea > 0`
  ///      (a row whose payload cannot be unpacked — exactly the case
  ///      that `loadArea` silently skips).
  ///
  /// The failure is closed: if the storage itself throws, nobody here
  /// catches it; the error goes to the caller.
  InviteLedger load() {
    final s = _store;
    if (s == null) return InviteLedger(); // Stellvertreter-Betrieb (IPC)

    final lines = s.loadArea(area);
    final header = lines.remove(headerKey);

    if (header == null) {
      final present = s.countArea(area);
      if (present > 0) {
        throw StateError(
            'InviteStore: the area `$area` holds $present line(s), '
            'but no readable header record — NO fresh book is '
            'created. A fresh book would reset the invitation index to 0 '
            'and give a second invitation the same K_inv(i) '
            'as one already issued (v4.1 §15.3.1: "i monotonic '
            'per invitation").');
      }
      return InviteLedger();
    }

    // Path 2: the header is there, but the records got lost along the
    // way. `highwater` alone saves the index; the revocations and labels
    // would be gone, and a revoked invitation would be armed again after
    // the restart.
    final expected = s.countArea(area) - 1; // without the header
    if (lines.length < expected) {
      throw StateError(
          'InviteStore: the area `$area` holds $expected record '
          'line(s), of which only ${lines.length} can be unpacked — '
          'NO incomplete book is delivered. A missing '
          'record makes a revoked invitation live again '
          '(§15.3.3).');
    }

    // The storage does not guarantee any order. `byIndex` and `openAt`
    // search the list anyway, but an unsorted list makes every log line
    // and every test dependent on the row order — so it is sorted the
    // way the ledger came into being.
    final records = lines.values.toList()
      ..sort((a, b) {
        final ga = (a['g'] as int? ?? 0).compareTo(b['g'] as int? ?? 0);
        return ga != 0
            ? ga
            : (a['i'] as int? ?? 0).compareTo(b['i'] as int? ?? 0);
      });

    return InviteLedger.fromJson({...header, 'records': records});
  }

  /// Writes ONE record and the header.
  ///
  /// The path for every single change to the ledger — issuing,
  /// revocation, redemption. The header comes along because `highwater`
  /// and `generation` can change with the record, and a ledger with a
  /// new record but old `highwater` would assign the same index a second
  /// time at the next `issue()`.
  ///
  /// ORDER: first the record, then the header. If it breaks off in
  /// between, a record without increased `highwater` lies there — the
  /// next issuing burns it and keeps counting. The other way round, an
  /// increased `highwater` without a record would lie there, and the
  /// revocation of an already issued invitation would be lost.
  void persistRecord(InviteLedger ledger, InviteRecord rec) {
    final s = _store;
    if (s == null) return;
    s.putEntry(area, keyFor(rec), rec.toJson());
    s.putEntry(area, headerKey, _header(ledger));
  }

  /// Writes ONLY the header — generation and highwater.
  ///
  /// For recovery from the rescue bundle (§15.3.3, K-7):
  /// there `g_inv` and `highwater` move upwards without a single record
  /// coming into existence.
  void persistHead(InviteLedger ledger) {
    final s = _store;
    if (s == null) return;
    s.putEntry(area, headerKey, _header(ledger));
  }

  /// Writes the whole ledger.
  ///
  /// Deliberately WITHOUT `replaceArea`: that would first delete the area
  /// completely and rebuild it: a crash in the middle is covered by the
  /// transaction, but the full-state writer is the wrong path anyway for
  /// a monotonically growing collection. Here the rows are overwritten
  /// individually; nothing is deleted, because a record never disappears
  /// from the ledger.
  void save(InviteLedger ledger) {
    final s = _store;
    if (s == null) return;
    for (final rec in ledger.records) {
      s.putEntry(area, keyFor(rec), rec.toJson());
    }
    s.putEntry(area, headerKey, _header(ledger));
  }

  /// The header record — everything from [InviteLedger.toJson] except the
  /// records, which have their own rows.
  Map<String, dynamic> _header(InviteLedger ledger) {
    final j = ledger.toJson();
    j.remove('records');
    return j;
  }
}
