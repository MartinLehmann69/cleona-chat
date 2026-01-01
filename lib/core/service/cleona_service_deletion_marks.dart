part of 'cleona_service.dart';

// The mark of a deleted message.
//
// §21.5.2, level 1: "The message disappears from the user's own profile.
// Immediately and completely." No row "message deleted" stays in the
// conversation, and no row stays in the store (owner decision 01.10.2026).
//
// What stays is a mark OUTSIDE the conversation — the identifier and the
// time of the deletion, the pattern of the calendar's delete marker
// (§18.1.3 rule 3): deletion dominates, and a copy of the message that
// arrives afterwards must not bring it back. Copies do arrive afterwards:
// the same message lies with up to three holders (§8.2), is mirrored to the
// own devices (§14.2), and there is no transport order (§18.1.3 "Problem") —
// the deletion itself can be the first of the two to arrive.
//
// How long: for as long as the identity exists — §21.5.2 level 1 "It is
// kept for as long as the identity exists (§20.2)", §20.2 "none — kept as
// long as the identity exists", "nothing is evicted" (owner decision Z-1 =
// A, 02.10.2026). A copy can arrive at any later time: a party sends again
// what this device missed when it catches up after an absence (§9.5). No
// clock removes a mark and no cap evicts one, also not the mark of a
// deletion that came before its message ("The marker is set whether or not
// the message is held"). The marks fall with the identity's store.

/// The state area that holds the marks of deleted messages.
const String kDeletedMessagesArea = 'deleted_messages';

class DeletionMark {
  /// When the deletion took effect on this device.
  final int atMs;

  /// Who asked for the deletion — set only where this device did not know
  /// the message, so that authorship ("only the author may delete", §21.5.1)
  /// is checked when the message arrives. null: the message was here and the
  /// deletion was checked against it.
  final String? byHex;

  /// The wire identifiers of the message that the history of the delivery
  /// layer still has to forget (`_myceliumForget`): the message identifier
  /// and, for an own group message, the one of every leg. Set only where
  /// the deletion happened before the mailbox was attached; null once the
  /// history has forgotten them — the ordinary case from the start.
  final List<String>? owed;

  /// An OWN message the user deleted: who it went to, and the identifier
  /// each of them holds it under (UserID hex → identifier hex) — the message
  /// identifier 1:1, the identifier of the member's leg in a group (§16.2).
  /// §9.5: a party that was away longer than its post box keeps a packet
  /// never got the deletion; when it asks for what it missed, the answer
  /// names "the identifiers of its messages deleted in that time", and only
  /// to the party that held the message. null: not an own deletion (a
  /// received message, an expired one) — nothing to name to anybody.
  final Map<String, String>? held;

  const DeletionMark({required this.atMs, this.byHex, this.owed, this.held});

  /// The same mark, with [owed] in place of what it owed.
  DeletionMark owing(List<String>? owed) =>
      DeletionMark(atMs: atMs, byHex: byHex, owed: owed, held: held);

  Map<String, dynamic> toJson() => {
        'at': atMs,
        if (byHex != null) 'by': byHex,
        if (owed != null) 'owed': owed,
        if (held != null) 'held': held,
      };

  static DeletionMark fromJson(Map<String, dynamic> j) => DeletionMark(
      atMs: j['at'] as int,
      byHex: j['by'] as String?,
      owed: (j['owed'] as List?)?.cast<String>(),
      held: (j['held'] as Map?)?.cast<String, String>());
}

extension DeletionMarkOps on CleonaService {
  /// Loads the marks on first access, every one of them, whatever its age.
  /// One path for the started service and for everything else.
  void _ensureDeletionMarksLoaded() {
    if (_deletionMarksLoaded) return;
    try {
      for (final e in store.loadArea(kDeletedMessagesArea).entries) {
        try {
          _deletionMarks[e.key] = DeletionMark.fromJson(e.value);
        } catch (err) {
          _log.warn('Deletion mark ${e.key} unreadable, skipped: $err');
        }
      }
      // Only after the read: a failed read must not count as "no marks".
      _deletionMarksLoaded = true;
    } catch (e) {
      _log.warn('Deletion marks: loading failed: $e');
    }
  }

  /// Records that [messageId] is deleted. [byHex] only where this device
  /// does not know the message (see [DeletionMark.byHex]). A mark that
  /// already stands is kept as it is. [owed]: what the history of the
  /// delivery layer could not be told yet (see [DeletionMark.owed]) — a
  /// standing mark takes that on. [held]: see [DeletionMark.held].
  void _markDeleted(String messageId,
      {String? byHex,
      DateTime? now,
      List<String>? owed,
      Map<String, String>? held}) {
    if (messageId.isEmpty) return;
    _ensureDeletionMarksLoaded();
    final at = now ?? DateTime.now();
    final standing = _deletionMarks[messageId];
    // A checked deletion replaces an unchecked claim, never the reverse.
    if (standing != null && (standing.byHex == null || byHex != null)) {
      if (owed == null) return;
      _deletionMarks[messageId] =
          standing.owing({...?standing.owed, ...owed}.toList());
      _persistDeletionMark(messageId);
      return;
    }
    final mark = DeletionMark(
        atMs: at.millisecondsSinceEpoch, byHex: byHex, owed: owed, held: held);
    _deletionMarks.remove(messageId);
    _deletionMarks[messageId] = mark;
    _persistDeletionMark(messageId);
  }

  /// The mark for [msg], which has just left the store, and the same
  /// deletion in the history of the delivery layer (§21.5.2 level 1:
  /// "completely" — that history holds the content of every message sent
  /// and received, `mycelium/lib/history.dart`). Without an attached
  /// mailbox the mark carries what is owed, and the attach settles it
  /// ([_myceliumForgetOwed]).
  ///
  /// [byAuthor]: the user deleted an own message (here or on another own
  /// device) — the mark keeps who held it under which identifier
  /// ([DeletionMark.held]), for a party that asks later (§9.5). Not for an
  /// expired message: its expiry runs per copy (§21.5.3) and deletes nothing
  /// at the recipient.
  void _markDeletedAndForget(String conversationId, UiMessage msg,
      {bool byAuthor = false}) {
    // The post identifier too (§16.2): a reaction to a group post names it,
    // and `_myceliumForget` finds a reaction by the identifier it names.
    final wire = [msg.id, ...msg.fanoutLegs.values, ?msg.postId];
    final told = _myceliumForget(wire,
        peersHex: _myceliumPeersOf(conversationId, msg));
    Map<String, String>? held;
    if (byAuthor && msg.isOutgoing) {
      if (msg.fanoutLegs.isNotEmpty) {
        held = Map.of(msg.fanoutLegs);
      } else if (_contacts.containsKey(conversationId)) {
        held = {conversationId: msg.id};
      }
    }
    _markDeleted(msg.id, owed: told ? null : wire, held: held);
  }

  /// At the attach of the mailbox: what was deleted before it was there
  /// leaves the history of the delivery layer now, and the marks owe
  /// nothing any more. Without such a mark this reads the marks and
  /// touches no history.
  void _myceliumForgetOwed() {
    _ensureDeletionMarksLoaded();
    final owing = [
      for (final e in _deletionMarks.entries)
        if (e.value.owed != null) e.key,
    ];
    if (owing.isEmpty) return;
    final wire = [for (final id in owing) ..._deletionMarks[id]!.owed!];
    if (!_myceliumForget(wire)) return;
    for (final id in owing) {
      _deletionMarks[id] = _deletionMarks[id]!.owing(null);
      _persistDeletionMark(id);
    }
  }

  /// Whether a message [messageId] sent by [senderHex] is held back by a
  /// mark. A mark somebody else than the author asked for holds nothing back
  /// and is dropped — the message has arrived and shows who wrote it.
  bool _deletionMarkHolds(String messageId, String senderHex) {
    _ensureDeletionMarksLoaded();
    final mark = _deletionMarks[messageId];
    if (mark == null) return false;
    if (mark.byHex == null || mark.byHex == senderHex) return true;
    _deletionMarks.remove(messageId);
    _persistDeletionMark(messageId);
    return false;
  }

  /// Writes exactly one mark — or removes it if it no longer stands.
  void _persistDeletionMark(String messageId) {
    if (_disposed || !_deletionMarksLoaded) return;
    try {
      final mark = _deletionMarks[messageId];
      if (mark == null) {
        store.removeEntry(kDeletedMessagesArea, messageId);
      } else {
        store.putEntry(kDeletedMessagesArea, messageId, mark.toJson());
      }
    } catch (e) {
      _log.warn('Deletion mark ${messageId.substring(0, 8)}: saving failed: $e');
    }
  }

/// A row an earlier build left in the store: the message itself, emptied
  /// and flagged, where now a mark stands. It leaves on the same terms as a
  /// deletion. Called with the conversation already loaded — the attachment
  /// check walks every history.
  void _sweepFlaggedRows(List<UiMessage> flagged) {
    for (final m in flagged) {
      forgetMessage(m.id);
      _markDeletedAndForget(m.conversationId, m);
      _voiceTranscription?.forget(m.id);
      final path = m.filePath;
      if (path != null) _eraseAttachmentUnlessHeld(path);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// The mark of an edit that waits for its message (§21.5.1).
//
// "Without transport ordering, the gap between original and edit on the
// receiver side is not determined by a send delay but by arrival order
// (§7, §8); an edit can arrive before the original. The receiver
// therefore evaluates only the timestamps in the content, never the
// arrival order — the same rule as for the calendar (§18.1.3) —, and an
// edit to a still-unknown message is buffered instead of discarded."
//
// The pattern is the one of the deletion mark above: what cannot be
// checked yet — authorship, the edit window — is checked at the moment
// the message is held (`_pendingEditApply`), and until then the mark
// carries the content, not a copy of the message. The text of the edit
// is content in the store and nowhere else (§21.4.2); the store area is
// the same encrypted `messages.db` the waiting group posts lie in
// (`cleona_service_group_gate.dart`).
// ═══════════════════════════════════════════════════════════════════════

/// The state area that holds the edits waiting for their message.
const String kPendingEditsArea = 'pending_edits';

/// How long a buffered edit is held: the same term as a deletion mark
/// ([kDeletionMarkRetention]) — it covers the longest a copy of the
/// message can still be under way (§9.3, §8.2). §20.2: every buffer has
/// a declared limit and a declared behaviour; the limit is this term, the
/// behaviour is the sweep.
const Duration kPendingEditRetention = Duration(days: 31);

/// At most this many buffered edits for messages this device has never
/// seen. Such a mark costs its sender one message and this device one
/// row; the cap is that of the unseen deletion marks
/// ([kUnseenDeletionMarksAtMost]). The oldest drops.
const int kUnseenEditMarksAtMost = 4096;

class PendingEditMark {
  /// When the edit arrived here — the retention runs on it.
  final int atMs;

  /// The conversation the message will land in: the group or channel
  /// identifier, or the sender's user identifier for a direct message.
  final String conversationId;

  /// The new text of the edit, from the content (§21.5.1 "No edit
  /// history. Only the current version exists").
  final String newText;

  /// The moment of the edit, from the content — never the arrival order.
  final int editAtMs;

  /// Who asked for the edit — the author check ("only the author may
  /// edit", §21.5.1) runs against it when the message is held.
  final String byHex;

  const PendingEditMark({
    required this.atMs,
    required this.conversationId,
    required this.newText,
    required this.editAtMs,
    required this.byHex,
  });

  bool expired(DateTime now) =>
      now.millisecondsSinceEpoch - atMs >= kPendingEditRetention.inMilliseconds;

  Map<String, dynamic> toJson() => {
        'at': atMs,
        'conv': conversationId,
        'text': newText,
        'edit': editAtMs,
        'by': byHex,
      };

  static PendingEditMark fromJson(Map<String, dynamic> j) => PendingEditMark(
        atMs: j['at'] as int,
        conversationId: j['conv'] as String,
        newText: j['text'] as String,
        editAtMs: j['edit'] as int,
        byHex: j['by'] as String,
      );
}

extension PendingEditOps on CleonaService {
  /// Loads the buffered edits on first access and drops what has run out.
  /// One path for the started service and for everything else.
  void _ensurePendingEditsLoaded() {
    if (_pendingEditsLoaded) return;
    try {
      final now = DateTime.now();
      for (final e in store.loadArea(kPendingEditsArea).entries) {
        try {
          final mark = PendingEditMark.fromJson(e.value);
          if (mark.expired(now)) {
            store.removeEntry(kPendingEditsArea, e.key);
          } else {
            _pendingEdits[e.key] = mark;
          }
        } catch (err) {
          _log.warn('Pending edit ${e.key} unreadable, skipped: $err');
        }
      }
      // Only after the read: a failed read must not count as "no marks".
      _pendingEditsLoaded = true;
    } catch (e) {
      _log.warn('Pending edits: loading failed: $e');
    }
  }

  /// Buffers the edit of a message this device does not hold (§21.5.1).
  /// A buffered edit stands only until its message is held — the author
  /// check and the edit window run there (`_pendingEditApply`), and until
  /// then the newest edit from the content wins: "No edit history. Only
  /// the current version exists."
  void _markEdited(String messageId,
      {required String conversationId,
      required String newText,
      required int editAtMs,
      required String byHex,
      DateTime? now}) {
    if (messageId.isEmpty) return;
    _ensurePendingEditsLoaded();
    final at = now ?? DateTime.now();
    _sweepPendingEdits(at);
    final standing = _pendingEdits[messageId];
    // A later edit replaces an earlier one; a replayed older one does not
    // set the text back (the receiver evaluates the timestamps in the
    // content, never the arrival order).
    if (standing != null && standing.editAtMs >= editAtMs) return;
    _pendingEdits[messageId] = PendingEditMark(
        atMs: at.millisecondsSinceEpoch,
        conversationId: conversationId,
        newText: newText,
        editAtMs: editAtMs,
        byHex: byHex);
    _persistPendingEdit(messageId);
    // §20.2: a declared bound on the edits for messages never seen —
    // the oldest drops, never the newest arrival is blocked.
    final unseen = _pendingEdits.keys.toList();
    for (var i = 0; i < unseen.length - kUnseenEditMarksAtMost; i++) {
      _pendingEdits.remove(unseen[i]);
      _persistPendingEdit(unseen[i]);
    }
  }

  /// Applies the buffered edit of [msg], which has just been inserted
  /// into [conversationId] — the moment the author check and the edit
  /// window can run (§21.5.1). A mark of somebody else than the author,
  /// one of another conversation, or one whose edit is out of the window
  /// falls away unapplied.
  void _pendingEditApply(UiMessage msg, String conversationId) {
    _ensurePendingEditsLoaded();
    final mark = _pendingEdits[msg.id];
    if (mark == null) return;
    // The mark leaves in every case: the message it waited for is held,
    // and a second copy of it is recognised by its identifier like any
    // replay.
    _pendingEdits.remove(msg.id);
    _persistPendingEdit(msg.id);
    // Dual-Enforcement: only the author may edit — repeated here because
    // it was impossible before the message was held. A mark of a
    // non-author falls away unapplied, and so does one that waited for
    // another conversation.
    if (msg.senderNodeIdHex != mark.byHex ||
        mark.conversationId != conversationId) {
      _log.warn('Buffered edit of ${msg.id.substring(0, 8)} not applied: '
          'asked by ${mark.byHex.substring(0, 8)}, author is '
          '${msg.senderNodeIdHex.isEmpty ? '-' : msg.senderNodeIdHex.substring(0, 8)}');
      return;
    }
    final conv = conversations[conversationId];
    final editWindowMs = conv?.config.editWindowMs ??
        CleonaService._receiverEditToleranceMs;
    if (editWindowMs == 0) {
      _log.warn('Buffered edit of ${msg.id.substring(0, 8)} not applied: '
          'editing disabled for $conversationId');
      return;
    }
    // The tolerance is measured against the moment of the message as
    // this device holds it, never against the arrival of the edit — the
    // same yardstick as the direct path above uses; a buffered edit is
    // content-older than the message it names, so the wide tolerance
    // takes it (§21.5.1 "the receiver-side tolerance is set wide").
    if (editWindowMs > 0 &&
        mark.editAtMs - msg.timestamp.millisecondsSinceEpoch >
            editWindowMs) {
      _log.warn('Buffered edit of ${msg.id.substring(0, 8)} not applied: '
          'out of the edit window');
      return;
    }
    msg.text = mark.newText;
    msg.editedAt = DateTime.fromMillisecondsSinceEpoch(mark.editAtMs);
    // Stored here, not only by the caller that inserted the message: an
    // edit reaches the store where it is applied (the coverage guard reads
    // each method on its own), and the rare second write costs nothing.
    persistMessage(conversationId, msg);
    _log.debug('Buffered edit applied to ${msg.id.substring(0, 8)} in '
        '$conversationId');
  }

  /// Drops the buffered edits whose retention has run out (§20.2).
  void _sweepPendingEdits(DateTime now) {
    _ensurePendingEditsLoaded();
    final out = [
      for (final e in _pendingEdits.entries)
        if (e.value.expired(now)) e.key,
    ];
    for (final id in out) {
      _pendingEdits.remove(id);
      _persistPendingEdit(id);
    }
  }

  /// Writes exactly one buffered edit — or removes it if it no longer
  /// stands.
  void _persistPendingEdit(String messageId) {
    if (_disposed || !_pendingEditsLoaded) return;
    try {
      final mark = _pendingEdits[messageId];
      if (mark == null) {
        store.removeEntry(kPendingEditsArea, messageId);
      } else {
        store.putEntry(kPendingEditsArea, messageId, mark.toJson());
      }
    } catch (e) {
      _log.warn('Pending edit ${messageId.substring(0, 8)}: saving failed: $e');
    }
  }

  /// The sweep of [_sweepPendingEdits] at a moment the guard chooses
  /// (`test/smoke/smoke_group_post_findings_run.dart`).
  @visibleForTesting
  void debugSweepPendingEdits({required DateTime now}) =>
      _sweepPendingEdits(now);
}
