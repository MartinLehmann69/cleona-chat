import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/first_contact.dart' show ContactRequest;
import 'package:mycelium/memory.dart';
import 'package:mycelium/memory_enforcer.dart' show legacyDataClear;
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
  });
}

/// Opens the memory of a mailbox and fetches its post box —
/// still without a node. The host needs the post box BEFORE it can register the
/// identity at the node.
(Memory, PostBox) mailboxPrepare(
    MailboxDetails a, void Function(String)? report) {
  // Legacy data of a foreign version goes before `open` rejects it and takes the
  // service down with it (S391). NOTHING is rescued here: unlike with the
  // host, every field of this file depends on the version. What is lost in the process
  // is replaceable — post box and previous generation are passed in again by the app
  // at start (`postBoxFrom`), a contact is made known again by it
  // when sending (`contactRemember`); what remains lost are the remembered
  // routes and the remembered invitations.
  legacyDataClear(
    directory: a.directory,
    fileName: kFileMailbox,
    runningVersion: kVersionMailbox,
    key: a.key,
    report: report,
  );
  final g = Memory.open(a.directory, a.key);
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
    final parts = given.secretParts();
    memory.ownPostBox = (
      address: given.address,
      ed25519Sk: parts.ed25519Sk,
      x25519Sk: parts.x25519Sk,
      mlKemSk: parts.mlKemSk,
      mlDsaSk: parts.mlDsaSk,
      previous: parts.previous,
    );
    memory.save();
    report?.call('Post box taken over from the caller '
        '(${memory.contacts.length} contact(s))');
    return given;
  }
  final own = memory.ownPostBox;
  if (own != null) {
    report?.call('Post box loaded (${memory.contacts.length} '
        'contact(s))');
    return PostBox.outSplit(
      address: own.address,
      ed25519Sk: own.ed25519Sk,
      x25519Sk: own.x25519Sk,
      mlKemSk: own.mlKemSk,
      mlDsaSk: own.mlDsaSk,
      previous: own.previous,
    );
  }

  // Derive from the word sequence if one is given — that is at the same time
  // the path of recovery: the same word sequence yields on a
  // new device the same identity. Without it a random one is drawn, and then
  // a lost device is a lost identity.
  final me = wordSequence == null ? PostBox.fresh() : wordSequence.postBox(0);
  if (wordSequence != null) {
    report?.call('Identity derived from the word sequence');
  }
  final parts = me.secretParts();
  memory.ownPostBox = (
    address: me.address,
    ed25519Sk: parts.ed25519Sk,
    x25519Sk: parts.x25519Sk,
    mlKemSk: parts.mlKemSk,
    mlDsaSk: parts.mlDsaSk,
    previous: parts.previous,
  );
  memory.save();
  report?.call('new post box created');
  return me;
}
