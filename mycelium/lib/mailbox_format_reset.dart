/// What the start of a mailbox threw away because of a format change — the
/// EXPLICIT signal to the application (owner decision W-a, S398).
///
/// ── THE FINDING (lab node .201, S398) ───────────────────────────────────
///
/// ```
/// mycelium: memory.enc carried version 16, running is 17 — old stock
///   removed, the node starts empty instead of not at all
/// first-contact store not readable — starts empty: ... unknown version 1
/// [service] mycelium: contact c0350896 made known to the mailbox (without route)
/// Post box step dropped: no daily pubkey for c0350896
/// ```
///
/// The enforcer (`memory_enforcer.dart`) removes a file of a foreign
/// version, and with the mailbox memory go `s_AB`, the day keys, routes,
/// invitations and waiting requests of EVERY contact; with the first-contact
/// store go the open joins. The application keeps its contacts — and until
/// here it learnt nothing of it: a contact it re-registered lazily
/// (`contactRemember` without `s_AB`) looked fine and never reached the post
/// box or step 3 again. `s_AB` only arises at first contact.
///
/// Therefore the reset is REPORTED, not guessed from a log line: the
/// enforcer's `true` is noted here per registration ([formatResetNote]),
/// handed to the mailbox at its creation ([MailboxFormatReset.formatResetAdopt])
/// and read ONCE by the application ([MailboxFormatReset.formatResetTake]),
/// which ends the affected contacts (§15.9 "deleted"). mycelium itself
/// decides nothing about the application's contacts.
///
/// A file that cannot be decrypted or is truncated is NOT a format change
/// and is not reported here — the enforcer does not judge it (see there).
library;

import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_start.dart' show MailboxDetails;

/// Which file of a mailbox the enforcer removed at this start.
enum FormatReset {
  /// The mailbox memory (`memory.dart`): contacts with `s_AB` and day keys,
  /// routes, invitations and their waiting requests.
  memory,

  /// The first-contact store (`memory_first_contact.dart`): open joins, the
  /// day keys of waiting requests, the invitations' own secrets.
  firstContact,
}

/// Per registration ([MailboxDetails]) — noted before the mailbox exists.
final Expando<Set<FormatReset>> _noted = Expando('formatResetNoted');

/// Per mailbox — until the application takes it.
final Expando<Set<FormatReset>> _held = Expando('formatResetHeld');

/// Notes that the start of the registration [a] removed [what].
void formatResetNote(MailboxDetails a, FormatReset what) =>
    (_noted[a] ??= <FormatReset>{}).add(what);

extension MailboxFormatReset on Mailbox {
  /// Takes over what was noted for [a] — once, when the mailbox is created.
  void formatResetAdopt(MailboxDetails a) {
    final n = _noted[a];
    _noted[a] = null;
    if (n != null && n.isNotEmpty) _held[this] = n;
  }

  /// What this start removed — and from now on nothing: the application
  /// acts on it ONCE (a second attach must not end a contact that was
  /// paired again in the meantime). Empty: nothing was removed.
  Set<FormatReset> formatResetTake() {
    final n = _held[this];
    _held[this] = null;
    return n == null ? const {} : Set.unmodifiable(n);
  }
}
