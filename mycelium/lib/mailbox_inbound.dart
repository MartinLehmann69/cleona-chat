import 'package:mycelium/message.dart' show Inbound, kModeRoutesApplyFurther;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/history.dart' show HistoryEntry;

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
/// From the [History] and from nowhere else: it carries the identifier anyway
/// and is restart-proof (one encrypted file per peer). There is
/// therefore NO deadline, NO ring size and NO second storage
/// that someone would have to maintain — the memory span is not a number
/// but a statement: as long as the message stands in the conversation,
/// a second copy is not accepted again (S390, B2-3 variant A,
/// owner decision 16.09.2026).
///
/// **Two named limits, both accepted:**
///
///  1. If the user deletes a message and a late copy arrives afterwards,
///     it appears again. The alternative would be a
///     tombstone per deleted message — more state than the case is
///     worth.
///  2. An UNKNOWN sender has no history and thus no
///     memory (§12.5: mycelium makes nobody a contact). Its
///     copies ALL go upwards until the application has decided and
///     called [MailboxInbound.inboundMark]; from then on the
///     check applies to it too. Before that there is nothing in the mailbox by which
///     a copy could be recognised, and creating a storage for unknown senders
///     would mean giving the gate for unknown senders (§15.7) a storage
///     that a stranger can fill.
extension MailboxInbound on Mailbox {
  /// An inbound with `to` = this identity.
  ///
  /// A KNOWN sender: address via the adoption rule, entry in the
  /// history. An UNKNOWN one does NOT become a contact here (§12.5, product rule
  /// 15.09.2026: mycelium makes nobody a contact) and gets no
  /// history — the inbound only goes upwards, and there the decision is made:
  /// if the application keeps it as a contact, it marks it with
  /// [inboundMark], otherwise it discards it (§15.7). Until S388
  /// every proven sender made itself a contact here (S388-BAU-NAHT B-2).
  ///
  /// SECOND COPY (S390, B2-3 variant A): §7.1 starts all steps
  /// SIMULTANEOUSLY, the same message therefore arrives several times in normal operation.
  /// It goes upwards EXACTLY ONCE — checked against the
  /// [History], which carries the identifier anyway and survives the restart;
  /// there is no second storage with its own deadline for this. EVERY copy
  /// is RECEIPTED: `message.dart` does that AFTER this callback, and
  /// §9.2 means by "exactly one packet" the FORM of the receipt, not an
  /// upper bound over time — if the first gets lost, the second
  /// copy is the second chance. LIMIT, named: if the user deletes a
  /// message and a late copy arrives afterwards, it appears
  /// again; the alternative would be a tombstone per deleted message.
  /// An UNKNOWN sender has no history and thus also no
  /// memory — its copies all go upwards until the application
  /// has decided and called [inboundMark].
  void inboundAccept(Inbound e) {
    if (e.mode != null) return _announcementAccept(e);
    if (e.kind != null) return pairNoticeAccept(e);
    if (contactOrNull(identifierFrom(e.from)) != null) {
      if (historyFor(e.from).alreadyIncoming(e.identifier)) return;
      inboundMark(e);
    }
    onMessage?.call(e);
  }

  /// Remembers the sender of [e] and puts the inbound into its history —
  /// for a known contact, or if it has been DECIDED above that the
  /// sender is a contact.
  void inboundMark(Inbound e) {
    contactRemember(e.from);
    historyFor(e.from).append(HistoryEntry(
      identifier: e.identifier,
      outgoing: false,
      content: e.content,
      instant: e.at,
    ));
  }

  /// A publication (0x15): no history entry, no callback
  /// upwards — only the address, only for a KNOWN contact, and only by
  /// the adoption rule. An unknown sender does not create a contact this way.
  void _announcementAccept(Inbound e) {
    if (contactOrNull(identifierFrom(e.from)) == null) {
      report?.call('Announcement from unknown identifier — discarded');
      return;
    }
    if (e.mode != kModeRoutesApplyFurther) {
      report?.call('Announcement with unknown mode ${e.mode} — '
          'address nevertheless by the adoption rule');
    }
    if (!contactRemember(e.from)) {
      report?.call('Announcement without higher state — nothing taken over');
    }
  }}
