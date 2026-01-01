import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart' show ContactRequest;
import 'package:mycelium/memory.dart';
import 'package:mycelium/memory_last_seen_clear.dart';
import 'package:mycelium/memory_enforcer.dart' show legacyDataClear;
import 'package:mycelium/mailbox_format_reset.dart';
import 'package:mycelium/message.dart' show Inbound;
import 'package:mycelium/amendment.dart' show Edit, ReadMark, Reaction;
import 'package:mycelium/envelope.dart';
import 'package:mycelium/recovery.dart';

/// What a mailbox needs for registering — at the host's start for the
/// first, at runtime for every further one.
///
/// [directory] is the directory of THIS identity: there lie its
/// memory (post box, contacts, invitations) and its histories.
/// Port and neighbours lie with the host, not here.
///
/// [onContactRequest] reports a contact request on a card of THIS
/// identity; the decision is made later and explicitly (§12.5) — there is
/// NO default, without a callback it waits anyway; [onMessage] and the three
/// amendment callbacks run for inbounds to it, in addition to the storage
/// in the history.
class MailboxDetails {
  final Directory directory;
  final Uint8List key;
  final WordSequence? wordSequence;

  /// An already existing identity — see [postBoxFetch].
  final PostBox? me;

  /// The question to the user. There is NO callback that decides
  /// immediately: until S388 `beiAnfrage` stood here, via which a caller
  /// could return a blanket `true` (ES-10, owner decision 15.09.2026).
  final void Function(ContactRequest a)? onContactRequest;
  final void Function(Inbound)? onMessage;
  final void Function(Reaction)? onReaction;
  final void Function(Edit)? onEdit;
  final void Function(ReadMark)? onReadMark;

  /// A join restored after a restart has ended with the contact (proposal
  /// E): the issuer accepted while this process was gone, and nobody waits
  /// for the future of `MailboxInvitation.join` any more. A join of the
  /// running process ends in that future instead.
  final void Function(Contact k)? onJoinCompleted;

  /// A FORK (§4.5.4, E-A9): an envelope for a known identifier carried a
  /// chain that does not pass through the keys held for it — two successors
  /// of one key, evidence that the old keys are in other hands. Discarded in
  /// any case; this callback shows it (`mailbox_book.dart`).
  final void Function(Address held, Address claimed)? onFork;

  const MailboxDetails(
    this.directory,
    this.key, {
    this.wordSequence,
    this.me,
    this.onContactRequest,
    this.onMessage,
    this.onReaction,
    this.onEdit,
    this.onReadMark,
    this.onJoinCompleted,
    this.onFork,
  });
}

/// Opens the memory of a mailbox and fetches its post box —
/// still without a node. The host needs the post box BEFORE it can register the
/// identity at the node.
(Memory, PostBox) mailboxPrepare(
    MailboxDetails a, void Function(String)? report) {
  // Legacy data of a foreign version goes before `open` rejects it and takes the
  // service down with it (S391). NOTHING is rescued here: unlike with the
  // host, every field of this file depends on the version. The post box is
  // passed in again by the app at start (`postBoxFrom`); what is lost for
  // good is every contact's `s_AB` and day keys, the routes, the invitations
  // and their waiting requests. A contact made known again without `s_AB`
  // never reaches post box or step 3 — so the reset is REPORTED to the
  // application (owner decision W-a, `mailbox_format_reset.dart`), which
  // ends the affected contacts instead of carrying them on half.
  if (legacyDataClear(
    directory: a.directory,
    fileName: kFileMailbox,
    runningVersion: kVersionMailbox,
    key: a.key,
    report: report,
  )) {
    formatResetNote(a, FormatReset.memory);
  }
  // The secret keys are written only where this file is the one place the
  // identity lives — a node without an app. A caller that passes its
  // identity ([MailboxDetails.me]) keeps the keys itself (S401).
  final g = Memory.open(a.directory, a.key, secretKeys: a.me == null);
  lastSeenClearAtUpgrade(a.directory, a.key, g, report); // S405 V2: once, at the upgrade
  return (g, postBoxFetch(g, a.wordSequence, report, given: a.me));
}

/// How the identity comes to the start — created or loaded.
///
/// On the FIRST start it is decided here whether a device loss is a
/// lost identity: with [wordSequence] it is not, without it
/// it is. That is not a setting one catches up on later — therefore
/// it stands in one place and not in three.
///
/// [given] is the path for a caller that ALREADY HAS its identity
/// and does not want to let it arise here — the app. It
/// holds its keys itself (`IdentityContext`), and a second post box
/// drawn here would be a second identity for
/// the same human. It is adopted and saved like a
/// freshly created one; everything further notices no difference.
PostBox postBoxFetch(
  Memory memory,
  WordSequence? wordSequence,
  void Function(String)? report, {
  PostBox? given,
}) {
  if (given != null) {
    // The previous day-key seed is the delivery layer's own state (§8.2):
    // the app does not keep it, so it comes from memory while its 7 days
    // run — the same identity, the same founding key. It is ALL this path
    // reads of the stored post box, and all it writes besides the address
    // (S401): the keys come from [given] at every start.
    final kept = memory.ownKept;
    if (kept != null &&
        kept.address.sameIdentity(given.address) &&
        given.previousDaySeed == null) {
      given.previousDaySeedKeep(kept.previousDaySeed);
    }
    memory.ownPostBox = ownPostBoxOf(given);
    memory.save();
    report?.call('Post box taken over from the caller '
        '(${memory.contacts.length} contact(s))');
    return given;
  }
  final own = memory.ownPostBox;
  if (own != null) {
    report?.call('Post box loaded (${memory.contacts.length} '
        'contact(s))');
    return postBoxOutOwn(own);
  }
  if (memory.ownKept != null) {
    // A memory written for a caller that holds its identity itself: there
    // are no keys here. Drawing a fresh identity over its contacts would be
    // a second identity for the same human — refused, loudly.
    throw MemoryError('this memory holds no secret keys — it belongs to a '
        'caller that passes its identity (MailboxDetails.me), and none was '
        'passed');
  }

  // Derive from the word sequence if one is given — that is at the same time
  // the path of recovery: the same word sequence yields on a
  // new device the same identity. Without it a random one is drawn, and then
  // a lost device is a lost identity.
  final me = wordSequence == null ? PostBox.fresh() : wordSequence.postBox(0);
  if (wordSequence != null) {
    report?.call('Identity derived from the word sequence');
  }
  memory.ownPostBox = ownPostBoxOf(me);
  memory.save();
  report?.call('new post box created');
  return me;
}
