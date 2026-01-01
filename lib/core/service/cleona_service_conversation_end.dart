part of 'cleona_service.dart';

// A conversation leaves this profile.
//
// §16.2.2: "Leaving removes the local conversation along with the membership
// record." Deleting a contact tells the user "The chat history will be
// lost." (`delete_contact_confirm`), and the own devices reconcile that
// deletion (§14.7 type 1).
//
// Until S401 every such place removed the conversation from memory only
// (`conversations.remove`). The writer of the conversations writes what is
// in memory and the start loads every row of the table — so the row, every
// message row with its text, the full-text index, the attachment files and
// the state keyed by the messages stayed in the profile, and the next start
// showed a deleted contact's conversation again (S401, PV-1). The store's
// `deleteConversation` had no caller.
//
// ONE route for every such place: [ConversationEndOps._conversationLeavesProfile].

extension ConversationEndOps on CleonaService {
  /// THE ONE ROUTE on which a conversation leaves this profile — leaving a
  /// group or a channel, deleting a contact (here and on another own
  /// device), and the conversations an earlier build left behind
  /// ([_sweepOrphanConversations]).
  ///
  /// Gone are: the conversation in memory, its row and every message row in
  /// the store (`ON DELETE CASCADE`; `SECURE_DELETE` overwrites the pages,
  /// §21.4.1; the triggers take the words out of the full-text index), the
  /// attachment files below `$profileDir/media/` that no other message
  /// points to, the state keyed by its messages (transcripts, archive index
  /// with its preview images, sender records and announced objects of the
  /// media lanes), its polls, and what the history of the delivery layer
  /// kept of its messages (`_myceliumForget`).
  ///
  /// [openSendsStop] decides about own messages that are still on their
  /// way. `true` — the contact is deleted: nothing goes to it any more
  /// (§15.9), the sending stops and the waiting lines behind a file fall.
  /// `false` — a group or channel was left: leaving does not unsay what was
  /// said; an own post not yet acknowledged keeps its open entry in the
  /// history of the delivery layer and goes on (§9.3: only the
  /// acknowledgement or the application ends a sending).
  ///
  /// NO MARK PER MESSAGE. A message deleted on its own gets a mark, because
  /// a second copy of it would be shown again in the conversation that
  /// still stands. Here the conversation is gone and nothing opens it
  /// again for a copy: a frame from a deleted contact is discarded before
  /// the application sees it (§15.7, `_myceliumInboundAccept`), a mirror
  /// from an own device asks for the contact (`_handleTwinMessageSent`,
  /// `_handleDeliveryMirror`), and a received entry keeps its identifier in
  /// the history of the delivery layer when its content is forgotten. What
  /// keeps a deleted contact from being imported again is its own mark
  /// (`contacts_deleted`, §15.9).
  ///
  /// Called BEFORE the contact, the group or the channel is removed: the
  /// parties whose histories are asked are read from them.
  void _conversationLeavesProfile(String conversationId,
      {required bool openSendsStop}) {
    final Uint8List idBytes;
    try {
      idBytes = hexToBytes(conversationId);
    } catch (e) {
      // Not an identifier of the store: there is no row under it.
      conversations.remove(conversationId);
      return;
    }

    // What it consists of — asked of the STORE: at start a conversation
    // carries only its youngest message in memory, and a conversation of an
    // earlier build's stock may not be in memory at all.
    final messages = <String, UiMessage>{};
    try {
      for (final row in store.messagesOf(idBytes)) {
        final m = CleonaService.messageFromStoreRow(row);
        messages[m.id] = m;
      }
    } catch (e) {
      _log.warn('Conversation ${_short(conversationId)}: its rows could not '
          'be read — $e');
    }
    final shown = conversations[conversationId];
    for (final m in shown?.messages ?? const <UiMessage>[]) {
      messages.putIfAbsent(m.id, () => m);
    }
    final wire = <String>{};
    final peers = <String>{conversationId};
    final paths = <String>{};
    for (final m in messages.values) {
      wire
        ..add(m.id)
        ..addAll(m.fanoutLegs.values);
      // §16.2: reactions to a group post name its post identifier.
      if (m.postId != null) wire.add(m.postId!);
      peers.addAll(_myceliumPeersOf(conversationId, m));
      final path = m.filePath;
      if (path != null) paths.add(path);
    }

    // Memory first: the attachment check below asks every conversation that
    // is still shown, and this one must not hold its own files.
    conversations.remove(conversationId);
    if (shown != null && shown.unreadCount > 0) _updateBadgeCount();
    try {
      onCancelNotificationAndroid?.call(conversationId);
    } catch (e) {
      _log.debug('Conversation ${_short(conversationId)}: notification not '
          'cancelled — $e');
    }

    // The row; its message rows fall with it, and with them the words in
    // the full-text index.
    try {
      store.deleteConversation(idBytes);
    } catch (e) {
      _log.warn('Conversation ${_short(conversationId)}: its rows could not '
          'be removed — $e');
    }

    _eraseAttachmentsUnlessHeld(paths);
    _eraseStateOfConversation(conversationId, messages.keys.toSet(), wire,
        openSendsStop: openSendsStop);

    // The history of the delivery layer (§21.4.2: message text lives in the
    // store and nowhere else). Without an attached mailbox the identifiers
    // are kept owed in ONE mark under the conversation's identifier, and
    // the attach settles it (`_myceliumForgetOwed`) — one row, not one per
    // message.
    if (wire.isNotEmpty) {
      final told = _myceliumForget(wire,
          peersHex: peers, keepOpenOwn: !openSendsStop);
      if (!told) _markDeleted(conversationId, owed: wire.toList());
    }

    _log.event('CONVERSATION LEFT THE PROFILE ${_short(conversationId)}: '
        '${messages.length} message(s), ${paths.length} attachment path(s)');
  }

  static String _short(String hex) =>
      hex.length > 8 ? hex.substring(0, 8) : hex;

  /// Removes attachment files — each one unless another message still
  /// points to it.
  ///
  /// The media store counts no references: the send path stores a file of
  /// the same name and content ONCE, and every message that carries it
  /// points to that one path (`sendMediaMessage`). And it never reaches
  /// outside `$profileDir/media`: a path elsewhere is a file of the user.
  void _eraseAttachmentsUnlessHeld(Iterable<String> paths) {
    final own = {
      for (final p in paths)
        if (p.startsWith('$profileDir/media/')) p,
    };
    if (own.isEmpty) return;
    ensureAllLoaded();
    for (final conv in conversations.values) {
      for (final m in conv.messages) {
        own.remove(m.filePath);
      }
    }
    for (final path in own) {
      if (!MediaStore.instance.deleteEitherWay(path)) {
        _log.warn('Attachment of a deleted message could not be removed '
            '(permissions, lock or a running reader)');
      }
    }
  }

  /// The state outside the two tables that hangs on [conversationId] or on
  /// one of its messages [ids] ([wire]: their identifiers on the wire).
  ///
  /// Every step stands for itself: a part that cannot be read (a service
  /// not started, a store that refuses) must not keep the others from
  /// going.
  void _eraseStateOfConversation(
      String conversationId, Set<String> ids, Set<String> wire,
      {required bool openSendsStop}) {
    void step(String what, void Function() run) {
      try {
        run();
      } catch (e) {
        _log.warn('Conversation ${_short(conversationId)}: $what not '
            'removed — $e');
      }
    }

    // Transcripts (§21.7) — message content.
    step('transcripts', () {
      for (final id in store
          .areaKeys(VoiceTranscriptionService.kArea)
          .where(ids.contains)) {
        _voiceTranscription?.forget(id);
        store.removeEntry(VoiceTranscriptionService.kArea, id);
      }
    });
    _eraseMediaStateOfMessages(ids,
        collecting: (entry) => entry['conv'] == conversationId, step: step);
    // Polls of the group or channel (§18.3).
    step('polls', () {
      final polls = [
        for (final p in pollManager.polls.values)
          if (p.groupId == conversationId) p.pollId,
      ];
      polls.forEach(pollManager.deletePoll);
    });
    if (!openSendsStop) return;
    // Messages waiting behind a file (§9.4 "Nothing overtakes a file"): the
    // lines of this conversation hold their frames.
    step('waiting lines', () {
      _fileOrderEnsureLoaded();
      final lines = _fileOrder.keys
          .where((k) => k.startsWith('$conversationId:'))
          .toList();
      for (final key in lines) {
        for (final slot in _fileOrder[key]!) {
          if (slot['frame'] != null) _fileOrderWaiting.remove(slot['wire']);
        }
        _fileOrder[key]!.clear();
        _fileOrderSave(key);
      }
    });
    // Own messages parked before the mailbox was attached (§21.2).
    step('parked messages', () {
      var parked = 0;
      for (final id in wire) {
        if (v41Outbox.remove(id)) parked++;
      }
      if (parked > 0) saveV41Outbox();
    });
  }

  /// The three state areas that hang on the messages [ids] besides their
  /// rows and their transcripts — ONE rule for a conversation that ends and
  /// for a single message that is deleted ([_eraseStateOfMessage]).
  /// [collecting] says which entry of the announced objects belongs to
  /// them; [step] runs each part for itself.
  void _eraseMediaStateOfMessages(Set<String> ids,
      {required bool Function(Map<String, dynamic> entry) collecting,
      required void Function(String what, void Function() run) step}) {
    // ONE message costs a read on its key, not a pass over the area: an
    // expiry run deletes message by message (`_checkMessageExpiry`), and
    // the archive index holds a row per archived file.
    final one = ids.length == 1 ? ids.first : null;
    // The archive index (§21.6): share address, preview images, pin. The
    // copy on the share stays — it lies outside the profile, in the user's
    // own storage.
    step('archive index', () {
      final keys = one == null
          ? store.areaKeys(ArchiveManager.kEntriesArea)
          : store.loadAreaPrefix(ArchiveManager.kEntriesArea, one).keys;
      for (final id in keys.where(ids.contains).toList()) {
        _archiveManager?.forget(id);
        store.removeEntry(ArchiveManager.kEntriesArea, id);
      }
    });
    // Sender records of lane 2/3 with the object they keep for sending
    // (`_transferResume` drops them the same way once it finds the message
    // gone — at the next attach or edge; here it is now).
    step('sender records of the media lanes', () {
      final records = one == null
          ? store.loadArea(kMediaOutgoingArea)
          : store.loadAreaPrefix(kMediaOutgoingArea, one);
      for (final id in records.keys.where(ids.contains).toList()) {
        _transferRecordDrop(records[id]!);
      }
    });
    // Announced objects still being collected: without the entry the
    // object, when it is complete, belongs to nobody
    // (`bulkObjectArrived`) — with it, it would be written into the media
    // directory for a message that no longer exists.
    step('announced objects of the media lanes', () {
      // With the mailbox attached the entries are in memory as they are in
      // the store (`_bulkResume`, `_bulkIncomingPut`); before the attach
      // only the store has them.
      final announced = one != null && myceliumMailbox != null
          ? Map<String, Map<String, dynamic>>.of(_bulkIncoming)
          : store.loadArea(kBulkIncomingArea);
      for (final e in announced.entries) {
        if (!collecting(e.value)) continue;
        _bulkIncomingRemove(e.key);
        _streamSeeds.remove(e.key);
        myceliumMailbox?.bulkCollector.abandon(hexToBytes(e.key));
      }
    });
  }

  /// ONE message leaves the profile (§21.5.2 level 1: "Immediately and
  /// completely"): what hangs on it in the state areas goes with it. Until
  /// S403 the deletion of one message left its archive row with the preview
  /// images, its sender record with the object kept for sending, and the
  /// entry of its object in collection — the last one made the object,
  /// once complete, a file in the media directory that no message carries
  /// (S401, finding NB-18).
  void _eraseStateOfMessage(String messageId) {
    _eraseMediaStateOfMessages({messageId},
        collecting: (entry) => entry['msg'] == messageId,
        step: (what, run) {
      try {
        run();
      } catch (e) {
        _log.warn('Message ${_short(messageId)}: $what not removed — $e');
      }
    });
  }

  /// At the start: conversations whose end an earlier build did not carry
  /// into the store, and what a crash between two writes may leave.
  ///
  /// Only where the store itself says the conversation has ended — nothing
  /// is guessed:
  ///  * a group conversation whose group, a channel conversation whose
  ///    channel is not kept (the membership record is gone: left, §16.2.2);
  ///  * a direct conversation whose party carries the deletion mark and is
  ///    no contact (deleted by the user, §15.9). A contact that deleted its
  ///    identity stays a contact, marked `deleted`, and keeps its
  ///    conversation read-only (§15.8) — it is not met by this.
  ///
  /// And only against collections that were READ: a failed load of the
  /// groups, the channels or the contacts leaves them empty, and every
  /// conversation would look orphaned. Until S401 this place removed from
  /// memory only, and the same mistake cost nothing; now it would erase.
  void _sweepOrphanConversations() {
    if (!_conversationsLoaded) return;
    final orphans = <String>[];
    for (final e in conversations.entries) {
      final c = e.value;
      final orphan = c.isGroup
          ? _groupsLoaded && !_groups.containsKey(e.key)
          : c.isChannel
              ? _channelsLoaded && !_channels.containsKey(e.key)
              : _contactsLoaded &&
                  _deletedContacts.contains(e.key) &&
                  !_contacts.containsKey(e.key);
      if (orphan) orphans.add(e.key);
    }
    for (final id in orphans) {
      _conversationLeavesProfile(id, openSendsStop: true);
      _log.info('Removed a conversation that had ended: ${_short(id)}');
    }
  }
}
