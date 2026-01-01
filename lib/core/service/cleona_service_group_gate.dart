part of 'cleona_service.dart';

// A frame that names a group this device does not hold.
//
// §16.2.2, "Leaving & ownership transfer": "A device that left a group keeps
// a mark of the group identifier; a post for a group it left is discarded,
// and a new invitation lifts the mark. A post for a group the device does not
// hold yet is buffered and applied when the invitation arrives (§21.5.4)."
//
// Until S403 the membership check answered "no objection" for a group this
// device did not hold, and a text, a reply, a file or a voice message from a
// contact then opened a conversation in the shape of a direct one, named
// after the first eight characters of the group identifier — after leaving
// as well as before the invitation, and the invitation never turned it into
// the group (S401, finding NB-15).
//
// ONE gate in front of the dispatcher ([GroupGateOps._groupGate]) decides
// for every frame that names an identifier this device holds neither as a
// group nor as a channel:
//
//  * the identifier carries the mark of a group this device left or was
//    removed from — the frame is discarded, whatever its kind. Five kinds
//    pass: the membership update (it is the invitation that may lift the
//    mark, decided where it is read), the same for a channel, the creation
//    of a group or channel and the acknowledgement of an own post that was
//    still on its way when the device left (it belongs to the pair,
//    §16.2.2);
//  * no mark, and the frame is one of the kinds a member sends INTO a group
//    ([kGroupWaitingKinds]) — it waits in the identity's store, without a
//    count or size limit (§21.5.4 "without a count limit"), and is handed
//    to the dispatcher when the invitation arrives, in the order and with
//    the arrival time it came with;
//  * anything else passes as before.
//
// BOTH LIVE IN THE IDENTITY'S STORE AND NOWHERE ELSE (§21.4.2). The mark is
// the identifier, the moment and the membership epoch — no name, no member,
// no content. A waiting post carries content, so it lies in `messages.db`
// like every message; it is not held in memory, because the delivery layer
// has acknowledged it by then (§9.2) and its sender will not send it again —
// a restart must not lose it. Nothing here keeps a second copy in memory:
// every question is asked of the store, and only for an identifier this
// device does not hold.

/// The state area of the marks of groups this device left. Key: the group
/// identifier (hex).
const String kGroupsLeftArea = 'groups_left';

/// At most this many marks (§20.2). A mark is set by the user's own leaving
/// and by nothing else, so the bound is no defence against another party; it
/// keeps the area from growing without end. At the bound the oldest mark is
/// dropped — a post for that group then waits like one for a group not yet
/// held ([kGroupPostsWaitingArea]) and opens nothing.
const int kGroupsLeftAtMost = 1024;

/// The state area of the posts that wait for their invitation. Key:
/// `group:arrival:message:kind:bytes` — the group identifier (hex), the
/// arrival in milliseconds (15 digits, so that the keys of one group sort by
/// arrival), the message identifier (hex), the kind's number and the size of
/// the payload. Nothing here bounds what waits any more (§21.5.4: posts and
/// settings for a group the device does not hold yet are buffered "without a
/// count limit"); once the group is held, its auto-delete timer applies to
/// what arrived — the frames become ordinary messages of the conversation.
const String kGroupPostsWaitingArea = 'group_posts_waiting';

/// The kinds a member sends into a group (§16.2.2 "The group types a group
/// pair may send"): group post, reaction, edit, deletion, poll and vote,
/// calendar entry of a group event, leave. §21.5.4: "Posts for a group the
/// device does not hold yet, AND SETTINGS FOR IT, are buffered" — the
/// settings change waits with the posts. Not here: the membership update
/// (it is the invitation), the read mark (it names an own post, and a device
/// that does not hold the group has none) and the acknowledgement of the
/// pair.
const Set<proto.MessageTypeV3> kGroupWaitingKinds = {
  proto.MessageTypeV3.MTV3_TEXT,
  proto.MessageTypeV3.MTV3_REPLY,
  proto.MessageTypeV3.MTV3_MEDIA_INLINE,
  proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
  proto.MessageTypeV3.MTV3_MEDIA_HOLDERS,
  proto.MessageTypeV3.MTV3_MEDIA_ABORT,
  proto.MessageTypeV3.MTV3_VOICE_MESSAGE,
  proto.MessageTypeV3.MTV3_REACTION,
  proto.MessageTypeV3.MTV3_EDIT,
  proto.MessageTypeV3.MTV3_DELETE,
  proto.MessageTypeV3.MTV3_POLL_CREATE,
  proto.MessageTypeV3.MTV3_POLL_VOTE,
  proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS,
  proto.MessageTypeV3.MTV3_POLL_UPDATE,
  proto.MessageTypeV3.MTV3_POLL_SNAPSHOT,
  proto.MessageTypeV3.MTV3_POLL_REVOKE,
  proto.MessageTypeV3.MTV3_CALENDAR_INVITE,
  proto.MessageTypeV3.MTV3_CALENDAR_UPDATE,
  proto.MessageTypeV3.MTV3_CALENDAR_DELETE,
  proto.MessageTypeV3.MTV3_CALENDAR_RSVP,
  proto.MessageTypeV3.MTV3_GROUP_LEAVE,
  proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE,
};

/// What the gate decided about a frame.
enum GroupGateVerdict {
  /// Handed to the dispatcher, as before.
  pass,

  /// For a group this device left, or not storable: nothing is done with it.
  discarded,

  /// For a group this device does not hold yet: it waits in the store.
  waits,
}

/// The mark of a group this device left.
class GroupLeftMark {
  /// When this device left.
  final int atMs;

  /// The membership epoch this device held when it left (§16.2.2
  /// "Membership consistency"). A membership state with an epoch that is
  /// not greater is older than the leaving — a second copy, a resend — and
  /// not a new invitation: "Recipients discard updates with an epoch ≤
  /// their local state."
  final int epoch;

  /// Whether this device was REMOVED by an owner or an admin (§16.2.2)
  /// instead of leaving on its own. Both marks behave the same towards
  /// other members' posts (discarded, a new invitation lifts the mark);
  /// only the conversation differs: a removed device keeps it readable,
  /// marked as removed, a device that left does not show it at all.
  final bool removed;

  const GroupLeftMark(
      {required this.atMs, required this.epoch, this.removed = false});

  Map<String, dynamic> toJson() =>
      {'at': atMs, 'epoch': epoch, if (removed) 'removed': true};

  static GroupLeftMark fromJson(Map<String, dynamic> j) => GroupLeftMark(
      atMs: (j['at'] as num).toInt(),
      epoch: (j['epoch'] as num).toInt(),
      removed: j['removed'] == true);
}

/// The key of a waiting post, read back.
class _WaitingKey {
  final String key;
  final String group;
  final int atMs;
  final String messageId;
  final int kind;
  final int bytes;
  const _WaitingKey(
      this.key, this.group, this.atMs, this.messageId, this.kind, this.bytes);

  static String build(
          String group, int atMs, String messageId, int kind, int bytes) =>
      '$group:${atMs.toString().padLeft(15, '0')}:$messageId:$kind:$bytes';

  static _WaitingKey? parse(String key) {
    final parts = key.split(':');
    if (parts.length != 5) return null;
    final at = int.tryParse(parts[1]);
    final kind = int.tryParse(parts[3]);
    final bytes = int.tryParse(parts[4]);
    if (at == null || kind == null || bytes == null || parts[0].isEmpty) {
      return null;
    }
    return _WaitingKey(key, parts[0], at, parts[2], kind, bytes);
  }
}

extension GroupGateOps on CleonaService {
  static String _short(String hex) =>
      hex.length > 8 ? hex.substring(0, 8) : hex;

  // ── The gate ──────────────────────────────────────────────────────────

  /// Decides about [event] before the dispatcher sees it. Everything that
  /// names no group, or a group or channel this device holds, passes without
  /// a question to the store.
  GroupGateVerdict _groupGate(HarvestEvent event) {
    final named = event.groupId;
    if (named == null) return GroupGateVerdict.pass;
    final gid = bytesToHex(named);
    if (_groups.containsKey(gid) ||
        _channels.containsKey(gid) ||
        SystemChannels.isSystemChannel(gid)) {
      return GroupGateVerdict.pass;
    }
    final sender = _short(bytesToHex(event.senderUserId));
    if (_groupLeftMark(gid) != null) {
      // §16.2.2: "a new invitation lifts the mark" — also for a channel
      // the device left ("The same mark is kept for a channel the device
      // left"), so the channel's invitation and creation pass as well.
      if (event.type == proto.MessageTypeV3.MTV3_GROUP_INVITE ||
          event.type == proto.MessageTypeV3.MTV3_GROUP_CREATE ||
          event.type == proto.MessageTypeV3.MTV3_CHANNEL_INVITE ||
          event.type == proto.MessageTypeV3.MTV3_CHANNEL_CREATE ||
          event.type == proto.MessageTypeV3.MTV3_DELIVERY_RECEIPT) {
        return GroupGateVerdict.pass;
      }
      _log.info('${event.type.name} from $sender for the group '
          '${_short(gid)}, which this device left — discarded (§16.2.2)');
      return GroupGateVerdict.discarded;
    }
    if (!kGroupWaitingKinds.contains(event.type)) return GroupGateVerdict.pass;
    if (!_groupWaitingPut(gid, event)) return GroupGateVerdict.discarded;
    _log.info('${event.type.name} from $sender for the group ${_short(gid)}, '
        'which this device does not hold yet — it waits for the invitation '
        '(§16.2.2)');
    return GroupGateVerdict.waits;
  }

  // ── The mark of a left group ──────────────────────────────────────────

  /// The mark of [gid], or `null`. A store that cannot be read answers
  /// `null`: the frame then waits instead of being discarded, and opens
  /// nothing either way.
  GroupLeftMark? _groupLeftMark(String gid) {
    try {
      final row = store.loadAreaPrefix(kGroupsLeftArea, gid)[gid];
      return row == null ? null : GroupLeftMark.fromJson(row);
    } catch (e) {
      _log.warn('Mark of the left group ${_short(gid)} unreadable: $e');
      return null;
    }
  }

  /// This device left [gid], holding the membership [epoch] — or was removed
  /// from it ([removed], §16.2.2). What waited for the group goes with it.
  void _groupMarkLeft(String gid, int epoch, {bool removed = false}) {
    try {
      store.putEntry(
          kGroupsLeftArea,
          gid,
          GroupLeftMark(
                  atMs: DateTime.now().millisecondsSinceEpoch,
                  epoch: epoch,
                  removed: removed)
              .toJson());
      store.removeAreaPrefix(kGroupPostsWaitingArea, '$gid:');
      if (store.areaKeys(kGroupsLeftArea).length <= kGroupsLeftAtMost) return;
      final marks = store.loadArea(kGroupsLeftArea);
      int at(String key) => (marks[key]?['at'] as num?)?.toInt() ?? 0;
      final oldestFirst = marks.keys.toList()
        ..sort((x, y) => at(x).compareTo(at(y)));
      for (var i = 0; i < oldestFirst.length - kGroupsLeftAtMost; i++) {
        store.removeEntry(kGroupsLeftArea, oldestFirst[i]);
      }
    } catch (e) {
      _log.warn('Mark of the left group ${_short(gid)} not written: $e');
    }
  }

  /// This device was removed from [gid] by the owner or an admin
  /// (§16.2.2, owner decision 03.10.2026, V2 = B). Unlike a leaving
  /// ([CleonaService.leaveGroup]) the conversation STAYS, readable: the
  /// device keeps it, marked as removed, blocks writing and discards later
  /// posts of the group. Writing is blocked by not holding the group any
  /// more — every send path asks `_groups` first — and later posts by the
  /// mark. The pairs with the co-members end here as well; the histories of
  /// the delivery layer are reached through them, which is why the
  /// conversation is NOT taken through [_conversationLeavesProfile]: its
  /// own posts stay readable.
  void _groupRemovedFrom(String gid, int epoch) {
    myceliumMailbox?.groupPairLeave(hexToBytes(gid));
    _groups.remove(gid);
    _saveGroups();
    _groupMarkLeft(gid, epoch, removed: true);
    _saveConversations();
    onStateChanged?.call();
    _log.info('Removed from the group ${_short(gid)} — the conversation '
        'stays, marked as removed (§16.2.2)');
  }

  /// The groups this device was REMOVED from (§16.2.2, S403 V2), as
  /// identifiers — for the IPC state snapshot: the GUI's chat screen gates
  /// writing on the mark, and over the IPC trench only the snapshot
  /// crosses, not the store.
  Iterable<String> _groupsRemovedFrom() {
    try {
      return [
        for (final e in store.loadArea(kGroupsLeftArea).entries)
          if (e.value['removed'] == true) e.key,
      ];
    } catch (e) {
      _log.warn('Marks of removed-from groups unreadable: $e');
      return const [];
    }
  }

  /// Whether a membership state of [gid] that names this identity as a
  /// member ([namesMe]) at [epoch] may make this device hold the group.
  /// Without a mark: yes. With one: only a state newer than the one this
  /// device left with — that is the new invitation, and it lifts the mark;
  /// anything else is a state from before the leaving and is discarded.
  bool _groupMayBeHeld(String gid, {required int epoch, required bool namesMe}) {
    final mark = _groupLeftMark(gid);
    if (mark == null) return true;
    if (!namesMe || epoch <= mark.epoch) {
      _log.info('Membership state (epoch $epoch) of the group ${_short(gid)}, '
          'which this device left at epoch ${mark.epoch} — not a new '
          'invitation, discarded (§16.2.2)');
      return false;
    }
    try {
      store.removeEntry(kGroupsLeftArea, gid);
    } catch (e) {
      _log.warn('Mark of the left group ${_short(gid)} not lifted: $e');
    }
    _log.info('New invitation into the group ${_short(gid)}: the mark of the '
        'leaving is lifted (§16.2.2)');
    return true;
  }

  // ── Posts that wait for their invitation ──────────────────────────────

  /// Puts [event] into the store under [gid]. `false`: it could not be kept
  /// and is discarded (named in the log). There is no size refusal any more:
  /// §21.5.4 buffers posts "without a count limit", and the age bound is
  /// the group conversation's auto-delete timer once the group is held
  /// (§21.5.3) — nothing bounds what waits.
  bool _groupWaitingPut(String gid, HarvestEvent event) {
    final bytes = event.payload.length;
    final id = bytesToHex(event.messageId);
    final roster = event.rosterVersion;
    // The delivery layer's acknowledgement of a file announcement is held
    // back until its object decodes (§9.4, D-29); the identifier it is sent
    // under waits with the announcement.
    final receipt = event.type == proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE
        ? _bulkReceiptsHeld.remove(id)
        : null;
    try {
      store.putEntry(
          kGroupPostsWaitingArea,
          _WaitingKey.build(gid, event.harvestedAt.millisecondsSinceEpoch, id,
              event.type.value, bytes),
          {
            'from': bytesToHex(event.senderUserId),
            'payload': base64Encode(event.payload),
            'trust': event.senderTrust.name,
            if (event.claimedSentAt != null)
              'claimed': event.claimedSentAt!.millisecondsSinceEpoch,
            if (roster != null) 'epoch': roster.epoch,
            if (roster != null) 'hash': bytesToHex(roster.hash),
            if (event.contentMetadata != null)
              'meta': base64Encode(event.contentMetadata!.writeToBuffer()),
            if (event.afterFile != null) 'after': bytesToHex(event.afterFile!),
            if (event.postId != null) 'post': bytesToHex(event.postId!),
            'receipt': ?receipt,
          });
      return true;
    } catch (e) {
      _log.warn('${event.type.name} for the group ${_short(gid)} could not '
          'be kept waiting — discarded: $e');
      return false;
    }
  }

  /// The group [gid] is held now: what waited for it is handed to the
  /// dispatcher, in the order it came. Every handler checks the frame as it
  /// checks one that arrives now — a post of a party that is no member is
  /// dropped there (§16.2.2 "Posts from non-members are silently
  /// discarded").
  ///
  /// A row leaves the store only after its frame was handled: a process
  /// that ends in between finds the rest at the next start
  /// ([_groupWaitingAtStart]), and a frame handled twice is recognised by
  /// its identifier like any second copy.
  void _groupWaitingApply(String gid) {
    final Map<String, Map<String, dynamic>> rows;
    try {
      rows = store.loadAreaPrefix(kGroupPostsWaitingArea, '$gid:');
    } catch (e) {
      _log.warn('Posts waiting for the group ${_short(gid)} unreadable: $e');
      return;
    }
    if (rows.isEmpty) return;
    final keys = rows.keys.toList()..sort();
    var applied = 0;
    for (final key in keys) {
      final w = _WaitingKey.parse(key);
      final event = w == null ? null : _groupWaitingEvent(w, rows[key]!);
      if (event != null) {
        final receipt = rows[key]!['receipt'];
        if (receipt is String) _bulkReceiptsHeld[w!.messageId] = receipt;
        try {
          _applicationEventDispatch(event, wasDirect: false);
          _fileOrderReceived(event);
          applied++;
        } catch (e) {
          _log.warn('${event.type.name} that waited for the group '
              '${_short(gid)} could not be applied: $e');
        }
      }
      try {
        store.removeEntry(kGroupPostsWaitingArea, key);
      } catch (e) {
        _log.warn('Waiting post of the group ${_short(gid)} not removed: $e');
      }
    }
    _log.event('GROUP ${_short(gid)} is held: $applied of ${keys.length} '
        'frame(s) that waited for the invitation applied (§16.2.2)');
  }

  /// The frame a waiting row was made from, or `null` if the row cannot be
  /// read.
  HarvestEvent? _groupWaitingEvent(_WaitingKey w, Map<String, dynamic> row) {
    try {
      final kind = proto.MessageTypeV3.valueOf(w.kind);
      if (kind == null) return null;
      final epoch = row['epoch'];
      final hash = row['hash'];
      final meta = row['meta'];
      final claimed = row['claimed'];
      final after = row['after'];
      final post = row['post'];
      return HarvestEvent(
        senderUserId: hexToBytes(row['from'] as String),
        // The delivery layer addresses identities, not devices (§14.2).
        senderDeviceId: null,
        type: kind,
        payload: base64Decode(row['payload'] as String),
        messageId: hexToBytes(w.messageId),
        // §22.5.3: the LOCAL arrival time — the moment the frame came, not
        // the moment its invitation did.
        harvestedAt: DateTime.fromMillisecondsSinceEpoch(w.atMs),
        claimedSentAt: claimed is int
            ? DateTime.fromMillisecondsSinceEpoch(claimed)
            : null,
        groupId: hexToBytes(w.group),
        rosterVersion: epoch is int && hash is String
            ? RosterVersion(epoch: epoch, hash: hexToBytes(hash))
            : null,
        contentMetadata: meta is String
            ? proto.ContentMetadata.fromBuffer(base64Decode(meta))
            : null,
        senderTrust: SenderTrust.values.byName(row['trust'] as String),
        afterFile: after is String ? hexToBytes(after) : null,
        postId: post is String ? hexToBytes(post) : null,
      );
    } catch (e) {
      _log.warn('Waiting post ${_short(w.messageId)} of the group '
          '${_short(w.group)} unreadable, dropped: $e');
      return null;
    }
  }

  /// At the start: what a run that ended in the middle of
  /// [_groupWaitingApply] left for a group or channel this device holds.
  void _groupWaitingAtStart() {
    try {
      if (!_groupsLoaded) return;
      final held = <String>{
        for (final key in store.areaKeys(kGroupPostsWaitingArea))
          if (_WaitingKey.parse(key) case final w?)
            if (_groups.containsKey(w.group) ||
                _channels.containsKey(w.group)) w.group,
      };
      held.forEach(_groupWaitingApply);
    } catch (e) {
      _log.warn('Posts waiting for an invitation: start check failed: $e');
    }
  }
}
