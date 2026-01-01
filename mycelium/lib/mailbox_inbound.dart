import 'package:mycelium/message.dart' show Inbound;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;

/// The inbound of the mailbox: what arrives for THIS identity, and what
/// of it goes upwards.
///
/// A separate file for the same reason as `mailbox_outbound.dart` and
/// `mailbox_amendment.dart` — the line budget of `mailbox.dart` knows
/// no exception. Until S390 the inbound was the only one of the four sides
/// (inbound, outbound, amendment, group) still in the core file; the check
/// against the second copy pushed it over the limit, and the
/// limit was right.
///
/// ── THE SECOND COPY AND ITS RECEIPT ────────────────────────────────
///
/// The two halves are DIFFERENT, and whoever lumps them together builds in
/// a new error:
///
///  * **Upwards exactly once.** §7.1 starts all applicable steps
///    simultaneously — the same message arrives several times in normal operation
///    (directly, via a neighbour, from the post box). Measured on
///    16.09.2026 before this change: the same packet fed in three times
///    yielded 3 inbounds, 3 history entries, 3 receipts.
///  * **Every copy is receipted.** §9.2 says "exactly one packet" about
///    the FORM of the receipt, not about an upper bound in time;
///    the same table lists "duplicate acknowledgement | ignored" on the
///    SENDER SIDE. If the receipt of the first copy gets lost, the
///    second copy is the second chance — whoever suppresses it here too leaves the
///    sender standing in `in transit` although it was delivered.
///
/// This falls apart because `message.dart` sends the receipt AFTER the
/// callback `onInbound` (`_messageCame`): a `return` here
/// does not reach it. This order is thus a precondition
/// of this file, not a coincidence — `smoke_double_inbound.dart` counts both
/// numbers.
///
/// ── WHERE THE MEMORY COMES FROM ───────────────────────────────────────
///
/// From the identity's received memory and from nowhere else
/// ([HistoryStore.incomingKnown]): every delivery the layer below
/// accepts is checked against it, and every sender that is kept gets its
/// identifier put into it ([HistoryStore.incomingKeep]). The memory is
/// the IDENTITY's, not a peer's (§20.2, owner decision 02.10.2026, V-1 =
/// B, V-3 = a): no per-peer record, no arrival time (V-4), no cap and no
/// deadline — its span is the statement "as long as the identity
/// exists", not a number. The application serves it from the
/// `received_ids` table of the message store (schema 4), so it survives
/// the restart; a lab tool gets [HistoryStoreMemory].
///
/// THE IDENTIFIER, NOT THE CONTENT (S401): of a received delivery only
/// the identifier is kept — the content goes upwards, into the
/// application's message store, and has no second place here (V4.2
/// §21.4.2; `history.dart`, "WHAT AN ENTRY KEEPS").
///
/// **Two named limits, both changed by the same decision:**
///
///  1. The user deletes a CONTACT: its records leave the store with it
///     (`MailboxOutbound.forget` names entries, `mailbox.dart` ends the
///     history), but the identifiers it once delivered STAY in the
///     identity's memory (V-3 = a) — a late copy from a post box is
///     still refused, still acknowledged. Until S403 the memory fell
///     with the contact's history and the copy went up a second time
///     (`mycelium/test/smoke_received_ids.dart`, statement 2).
///  2. An UNKNOWN sender is not admitted by its packets alone (§12.5:
///     mycelium makes nobody a contact): its copies ALL go upwards until
///     the application has decided and called [MailboxInbound.inboundMark];
///     from then on the check applies to it too. The check itself runs
///     for every sender — checking is not keeping, and creating a
///     storage a stranger could fill is the other thing §15.7 forbids:
///     nothing of an undecided sender is ever KEPT here.
extension MailboxInbound on Mailbox {
  /// An inbound with `to` = this identity.
  ///
  /// A KNOWN sender: address via the adoption rule, identifier into the
  /// identity's received memory. An UNKNOWN one does NOT become a
  /// contact here (§12.5, product rule 15.09.2026: mycelium makes
  /// nobody a contact) and is not kept either — the inbound only goes
  /// upwards, and there the decision is made: if the application keeps
  /// it as a contact, it marks it with [inboundMark], otherwise it
  /// discards it (§15.7). Until S388 every proven sender made itself a
  /// contact here (S388-BAU-NAHT B-2).
  ///
  /// SECOND COPY (S390, B2-3 variant A; §20.2): §7.1 starts all steps
  /// SIMULTANEOUSLY, the same message therefore arrives several times in
  /// normal operation. It goes upwards EXACTLY ONCE — checked against
  /// the identity's received memory, which survives the restart and the
  /// end of a contact; there is no second storage with its own deadline
  /// for this. The check stands BEFORE the branches on the sender: it
  /// applies to EVERY delivery, the deleted contact's late copy just as
  /// much as the stranger's — being checked costs a stranger nothing,
  /// nothing is kept for it. EVERY copy is RECEIPTED: `message.dart`
  /// does that AFTER this callback, and §9.2 means by "exactly one
  /// packet" the FORM of the receipt, not an upper bound over time — if
  /// the first gets lost, the second copy is the second chance.
  void inboundAccept(Inbound e) {
    if (e.kind != null) return pairNoticeAccept(e);
    if (histories.store.incomingKnown(e.identifier)) return;
    if (contactOrNull(identifierFrom(e.from)) != null) {
      inboundMark(e);
    } else if (groupPairOrNull(identifierFrom(e.from)) != null) {
      // A group pair (§4.3) has a history but never becomes a contact: what
      // it may carry into the application is decided there (§15.7).
      if (!groupPairInbound(e)) return;
    }
    onMessage?.call(e);
  }

  /// Remembers the sender of [e] and puts the identifier of its delivery
  /// into the identity's received memory — for a known contact, or if it
  /// has been DECIDED above that the sender is a contact. The IDENTIFIER
  /// only, no content and no time (file header): the content is the
  /// application's, the time is not stored at all (V-2 = b, V-4).
  void inboundMark(Inbound e) {
    contactRemember(e.from);
    histories.store.incomingKeep(e.identifier);
  }
}
