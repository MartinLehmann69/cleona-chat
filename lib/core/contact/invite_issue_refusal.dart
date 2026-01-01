// The refusal reason of an issuing as a VALUE, not as a log line — and
// its mapping to process boundary and UI (§15.3.1, §15.3.4,
// §21.4).
//
// ══════════════════════════════════════════════════════════════════════
// WHY THIS FILE EXISTS (S381, 11.09.2026)
// ══════════════════════════════════════════════════════════════════════
//
// Measured in the field: the owner scanned the QR of a desktop node with
// the phone and got "This code carries no invitation". The S380 guard on
// the scanner side thus measures correctly — the code carries no `ki`.
// The question nobody could answer was the next one: WHY does it carry
// none.
//
// The reason was there. It got lost at four stations:
//
//   1. `CleonaService.issueInviteForSharing` knows it exactly — four
//      branches, each with its own log line: unknown class, cap
//      (§15.3.4), ledger unreadable (§21.4), no master seed (§15.3.1).
//      It returned `null`.
//   2. `ipc_server.dart` turned that into `error: 'not issued'` — with
//      the explicit note "The REASON stands in the issuer's log
//      […] the UI only needs 'not issued'".
//   3. `ipc_client.dart` turned `!resp.success` back into `null`.
//   4. `contact_share_card.dart` turned `null` into the display
//      `invite_cap_reached` — and the comment next to it itself said
//      that this is guessed: "The card names the most frequent one."
//
// A GUESSED reason is worse than none at all: whoever reads "invitation
// cap reached" revokes old invitations — and if the cause in truth was
// a legacy profile without master seed (§15.3.1), he afterwards has
// fewer invitations and still no first contact.
//
// §15.3.1 is normative at this point: "the issuer must choose the
// class at creation time, **and the UI must name the consequence**". A
// guessed consequence is not a named one.
//
// ── WHY THE REASON TYPE DOES NOT STAND HERE ──────────────────────────────
//
// [InviteIssueRefusal] lives in `invite_ledger.dart` and has always
// carried `capReached` there. Putting a second type of the same name next
// to it would be a SECOND path to the same fact — and two paths to one
// fact drift apart (the same reasoning as in the header of
// `contact_seed_invite_gate.dart`). Therefore the existing type was
// extended; here stands only what the ledger should NOT know: the
// identifier for the process boundary and the i18n key.
//
// This file is Flutter-free and service-free, so that a guard can
// measure the mapping reason → message without building a UI.
library;

import 'package:cleona/core/contact/invite_ledger.dart'
    show InviteIssueRefusal;

export 'package:cleona/core/contact/invite_ledger.dart'
    show InviteIssueRefusal;

/// Identifier for the path across the process boundary and message for the
/// user.
extension InviteIssueRefusalWire on InviteIssueRefusal {
  /// Stable identifier for IPC.
  ///
  /// NOT the enum index: an index travels as a number and shifts on the
  /// next insertion — exactly the trap that AP-4b found in
  /// `MediaDownloadState` ("travelled as enum index").
  String get wireCode {
    switch (this) {
      case InviteIssueRefusal.capReached:
        return 'cap-reached';
      case InviteIssueRefusal.ledgerUnreadable:
        return 'ledger-unreadable';
      case InviteIssueRefusal.noMasterSeed:
        return 'no-master-seed';
      case InviteIssueRefusal.unknownClass:
        return 'unknown-class';
      case InviteIssueRefusal.unknownReason:
        return 'unknown';
    }
  }

  /// i18n key of the message the user reads.
  ///
  /// It is named HERE and not only in the UI, so that a guard can measure
  /// without Flutter WHICH message belongs to which reason — the same
  /// consideration as with `kSeedNoInviteMessageKey`.
  String get messageKey {
    switch (this) {
      case InviteIssueRefusal.capReached:
        return 'invite_cap_reached';
      case InviteIssueRefusal.ledgerUnreadable:
        return 'invite_ledger_unreadable';
      case InviteIssueRefusal.noMasterSeed:
        return 'invite_no_master_seed';
      case InviteIssueRefusal.unknownClass:
        return 'invite_class_unknown';
      case InviteIssueRefusal.unknownReason:
        return 'invite_not_issued';
    }
  }
}

/// The field under which the refusal identifier travels across the process
/// boundary.
///
/// ONE constant for both ends. Two identical strings in
/// `ipc_server.dart` and `ipc_client.dart` would be exactly the case that
/// S378 found four times: built, documented — and silently drifted apart
/// on one side at the next renaming. A guard can measure against this
/// constant, not against two literals.
const String kInviteRefusalField = 'refusal';

/// Back from the [InviteIssueRefusalWire.wireCode].
///
/// [InviteIssueRefusal.unknownReason] if the other side names a reason
/// this version does not know, or none at all — an honest catch-all
/// message instead of a guessed neighbour.
InviteIssueRefusal refusalFromWire(String? code) {
  if (code == null) return InviteIssueRefusal.unknownReason;
  for (final r in InviteIssueRefusal.values) {
    if (r.wireCode == code) return r;
  }
  return InviteIssueRefusal.unknownReason;
}

/// The result of an issuing attempt: either the invitation or the
/// reason why there is none. Never both, never neither.
///
/// The type carries the invitation as a type parameter, so that this file
/// stays service-free; `IssuedInvite` lives on the service interface and
/// fixes the type there with `InviteIssueResult`.
class InviteIssueOutcome<T extends Object> {
  const InviteIssueOutcome.issued(T this.invite) : refusal = null;
  const InviteIssueOutcome.refused(InviteIssueRefusal this.refusal)
      : invite = null;

  /// The issued invitation, or `null` on refusal.
  final T? invite;

  /// The reason for the refusal, or `null` on success.
  final InviteIssueRefusal? refusal;

  /// True if issued.
  bool get ok => invite != null;
}
