// Reactions in a private channel (v4_2 §16.2.4, §16.2.2, §21.5.1; D-58).
//
// WHAT HAPPENS WHERE:
//  * A subscriber's or admin's reaction — its removal and its replacement
//    too — goes as an ordinary 1:1 delivery to the OWNER only
//    ([_channelReactionSend]).
//  * The owner's device keeps per post which person holds which reaction —
//    in the post's own `reactions` in the message store — and counts from it
//    ([_channelReactionReceived]). The chips show counts only, never names
//    (`UiMessage.reactionCounts`).
//  * A received reaction alone starts a round: the totals leave no earlier
//    than [kChannelReactionRoundDelay] after the first change since the last
//    sending, then carry every change together, one 1:1 delivery per
//    subscriber and admin ([channelReactionRoundsDue]). Without a reaction
//    there is no clock and nothing is sent.
//  * Totals are a state: the receiver keeps the newest per post by the time
//    in the content ([_channelReactionTotalsReceived]); a newer sending to a
//    recipient takes the posts of the one before it that is not yet
//    acknowledged along, and the delivery layer forgets that one — it is not
//    sent again at an edge (§9.3).
//  * When ownership passes, the previous owner hands over who holds which
//    reaction ([_channelReactionHandoverSend]); a reaction that reaches a
//    device which is no longer the owner is passed on the same way.
//
// 4.2.x (D-21): an older 4.2 device does not know the two kinds
// `MT_CHANNEL_REACTION_TOTALS`/`_HANDOVER`; it discards them in
// `handleApplicationFrame` (unknown type) after its delivery layer has
// acknowledged them (`mycelium/lib/message.dart`, receipt before the
// application decides). The owner's sending therefore closes as `delivered`
// and is not sent again. Totals belong to no message in a conversation, so
// no state of theirs ever reaches the display.

part of 'cleona_service.dart';

/// The group or private channel whose reactions the owner counts (§16.2.4):
/// a private channel, or a group in announcement mode on the shared key
/// (§16.2.5, S407 group list).
class _ReactionEntity {
  final String channelIdHex;
  final String ownerNodeIdHex;
  final Map<String, ({String nodeIdHex})> members;
  _ReactionEntity(this.channelIdHex, this.ownerNodeIdHex, Iterable<String> ids)
      : members = {for (final id in ids) id: (nodeIdHex: id)};

  factory _ReactionEntity.ofChannel(ChannelInfo c) =>
      _ReactionEntity(c.channelIdHex, c.ownerNodeIdHex, c.members.keys);

  factory _ReactionEntity.ofGroup(GroupInfo g) =>
      _ReactionEntity(g.groupIdHex, g.ownerNodeIdHex, g.members.keys);
}

/// §16.2.4: the totals leave no earlier than ten minutes after the first
/// change since the last sending (owner, 13.10.2026).
const Duration kChannelReactionRoundDelay = Duration(minutes: 10);

/// The store area of the owner's pending rounds, one row per channel.
const String kChannelReactionRoundsArea = 'channel_reaction_rounds';

/// The owner's state of one channel's totals.
class ChannelReactionRound {
  /// The first change since the last sending (ms, the reaction clock); 0 =
  /// nothing changed.
  int firstChangeAtMs;

  /// The owner's identifiers of the posts changed since the last sending.
  final Set<String> changed;

  /// Per recipient the last totals sent to it: its identifier and the posts
  /// it carried. A newer sending takes these posts along while the old one is
  /// not acknowledged, and the old one is forgotten.
  final Map<String, ({String id, Set<String> posts})> sent;

  ChannelReactionRound(
      {this.firstChangeAtMs = 0,
      Set<String>? changed,
      Map<String, ({String id, Set<String> posts})>? sent})
      : changed = changed ?? {},
        sent = sent ?? {};

  Map<String, dynamic> toJson() => {
        'first': firstChangeAtMs,
        'changed': changed.toList(),
        'sent': {
          for (final e in sent.entries)
            e.key: {'id': e.value.id, 'posts': e.value.posts.toList()},
        },
      };

  static ChannelReactionRound fromJson(Map<String, dynamic> j) =>
      ChannelReactionRound(
        firstChangeAtMs: (j['first'] as num?)?.toInt() ?? 0,
        changed: ((j['changed'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toSet(),
        sent: {
          for (final e
              in ((j['sent'] as Map<String, dynamic>?) ?? const {}).entries)
            e.key: (
              id: (e.value as Map<String, dynamic>)['id'] as String,
              posts: (((e.value as Map<String, dynamic>)['posts']
                          as List<dynamic>?) ??
                      const [])
                  .map((p) => p as String)
                  .toSet(),
            ),
        },
      );
}

extension CleonaServiceChannelReactions on CleonaService {
  static String _short(String hex) =>
      hex.length > 8 ? hex.substring(0, 8) : hex;

  int get _reactionNowMs => channelReactionClock().millisecondsSinceEpoch;

  /// The private channel or group [id] as the owner's counting sees it.
  _ReactionEntity? _reactionEntityOf(String id) {
    final c = _channels[id];
    if (c != null) return _ReactionEntity.ofChannel(c);
    final g = _groups[id];
    return g == null ? null : _ReactionEntity.ofGroup(g);
  }

  /// The owner's pending rounds and last sendings — for a probe.
  @visibleForTesting
  Map<String, ChannelReactionRound> get debugChannelReactionRounds =>
      _channelReactionRounds;

  /// The display state of the delivery [idHex] as the delivery layer reports
  /// it — for a probe of the totals, which belong to no conversation.
  @visibleForTesting
  MessageStatus? debugDeliveryStatus(String idHex) =>
      _myceliumStatusFor(idHex);

  // ── Naming a post ─────────────────────────────────────────────────────

  /// The post [idHex] of [channelIdHex] as [fromHex] named it: the identifier
  /// it is kept under here, its post identifier, or the identifier of the leg
  /// this device sent it to [fromHex] under (a post without a post
  /// identifier is known to each subscriber by its own leg, §16.2).
  UiMessage? _channelPostFor(
      String channelIdHex, String idHex, String fromHex) {
    final conv = conversations[channelIdHex];
    if (conv == null) return null;
    ensureLoaded(channelIdHex);
    for (final m in conv.messages) {
      if (m.isReferredToBy(idHex) || m.fanoutLegs[fromHex] == idHex) return m;
    }
    return null;
  }

  /// How [toHex] knows [msg]: its post identifier, the leg this device sent
  /// it to [toHex] under, or — when [toHex] sent it here — the identifier it
  /// is kept under here. `null`: [toHex] knows it by nothing this device
  /// holds (a post of a third party without a post identifier).
  String? _channelPostNameFor(UiMessage msg, String toHex) =>
      msg.postId ??
      msg.fanoutLegs[toHex] ??
      (!msg.isOutgoing && msg.senderNodeIdHex == toHex ? msg.id : null);

  /// One reaction per person per message (§21.5.1) on [msg]: [emoji] replaces
  /// the person's earlier one; [remove] takes [emoji] back; an empty [emoji]
  /// takes back whatever the person holds. The change is stored here
  /// (`persistMessage`, conversation [conversationId]).
  void _reactionPersonSet(String conversationId, UiMessage msg,
      String personHex, String emoji, bool remove) {
    for (final e in msg.reactions.keys.toList()) {
      if (!remove && emoji.isNotEmpty && e == emoji) continue;
      if (remove && emoji.isNotEmpty && e != emoji) continue;
      msg.reactions[e]?.remove(personHex);
      if (msg.reactions[e]?.isEmpty ?? false) msg.reactions.remove(e);
    }
    if (!remove && emoji.isNotEmpty) {
      msg.reactions.putIfAbsent(emoji, () => {}).add(personHex);
    }
    persistMessage(conversationId, msg);
  }

  // ── A subscriber or admin reacts ──────────────────────────────────────

  /// §16.2.4: the own reaction [payloads] (removals first, then the reaction)
  /// on [msg] go to the owner of [channel] only. On the owner's own device
  /// nothing is sent; its change starts a round.
  Future<void> _channelReactionSend(_ReactionEntity channel, UiMessage? msg,
      List<Uint8List> payloads, String referredHex) async {
    final ownerHex = channel.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) {
      if (msg != null) _channelReactionChanged(channel.channelIdHex, msg.id);
      return;
    }
    if (msg != null) {
      msg.ownReactionAtMs = _reactionNowMs;
      persistMessage(channel.channelIdHex, msg);
    }
    // The name the OWNER knows the post by; the payloads carry the reference
    // identifier, which is the right one unless the post has no post
    // identifier and is not the owner's leg to us.
    final toOwner = msg == null ? referredHex : _channelPostNameFor(msg, ownerHex);
    if (toOwner == null) {
      _log.info('channel reaction on ${_short(referredHex)}: the owner knows '
          'this post by no identifier held here — counted only here');
      return;
    }
    for (final payload in payloads) {
      final r = proto.EmojiReaction.fromBuffer(payload)
        ..messageId = hexToBytes(toOwner);
      await sendToUser(
        recipientUserId: hexToBytes(ownerHex),
        messageType: proto.MessageType.MT_REACTION,
        payload: Uint8List.fromList(r.writeToBuffer()),
        groupId: hexToBytes(channel.channelIdHex),
      );
    }
  }

  // ── The owner receives a reaction ─────────────────────────────────────

  /// A reaction naming [channel] (§16.2.4). At the owner it is counted per
  /// person and starts a round; a device that is no longer the owner passes
  /// it on to the owner; anything else is dropped.
  void _channelReactionReceived(
      HarvestEvent event, _ReactionEntity channel, bool mirrored) {
    final senderHex = event.senderUserId.hex;
    final channelIdHex = channel.channelIdHex;
    if (!channel.members.containsKey(senderHex)) {
      _log.warn('channel reaction from non-member ${_short(senderHex)} in '
          '${_short(channelIdHex)} — dropped');
      return;
    }
    final proto.EmojiReaction reaction;
    try {
      reaction = proto.EmojiReaction.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('channel reaction: parse fail: $e');
      return;
    }
    if (reaction.emoji.isEmpty) return;
    final idHex = reaction.messageId.hex;
    final msg = _channelPostFor(channelIdHex, idHex, senderHex);
    if (msg == null) {
      _log.debug('channel reaction on ${_short(idHex)}: post not held here');
      return;
    }
    final ownerHex = channel.ownerNodeIdHex;
    if (ownerHex != identity.userIdHex) {
      // Ownership passed while the reaction travelled: the new owner counts
      // it (§16.2.4 "the previous owner hands over who holds which
      // reaction"). A copy mirrored by another own device is passed on by
      // the device that collected it.
      if (mirrored || ownerHex == senderHex) return;
      final name = _channelPostNameFor(msg, ownerHex);
      if (name == null) return;
      final handover = proto.ChannelReactionHandover()
        ..firstChangeAtMs = Int64(_reactionNowMs)
        ..posts.add(proto.PostReactionHolders()
          ..postId = hexToBytes(name)
          ..pending = true
          ..holders.add(proto.ReactionHolder()
            ..userId = hexToBytes(senderHex)
            ..emoji = reaction.remove ? '' : reaction.emoji));
      _detachedSend('MT_CHANNEL_REACTION_HANDOVER', sendToUser(
        recipientUserId: hexToBytes(ownerHex),
        messageType: proto.MessageType.MT_CHANNEL_REACTION_HANDOVER,
        payload: Uint8List.fromList(handover.writeToBuffer()),
        groupId: hexToBytes(channelIdHex),
      ));
      _log.info('channel reaction on ${_short(idHex)} passed on to the owner '
          '${_short(ownerHex)}');
      return;
    }
    _reactionPersonSet(channelIdHex, msg, senderHex, reaction.emoji, reaction.remove);
    onStateChanged?.call();
    _saveConversations();
    if (!mirrored) _channelReactionChanged(channelIdHex, msg.id);
  }

  // ── The round ─────────────────────────────────────────────────────────

  /// The reactions on the owner's post [msgId] changed: note it, and if it is
  /// the first change since the last sending, the round starts now.
  void _channelReactionChanged(String channelIdHex, String msgId) {
    final round = _channelReactionRounds.putIfAbsent(
        channelIdHex, () => ChannelReactionRound());
    if (round.changed.isEmpty || round.firstChangeAtMs == 0) {
      round.firstChangeAtMs = _reactionNowMs;
    }
    round.changed.add(msgId);
    _channelReactionRoundPersist(channelIdHex);
    _channelReactionRoundArm(channelIdHex);
  }

  /// One timer per channel with a pending round, set for its due time. It
  /// exists only after a reaction; it is no periodic clock.
  void _channelReactionRoundArm(String channelIdHex) {
    final round = _channelReactionRounds[channelIdHex];
    _channelReactionTimers.remove(channelIdHex)?.cancel();
    if (round == null || round.changed.isEmpty || _disposed) return;
    var waitMs = round.firstChangeAtMs +
        kChannelReactionRoundDelay.inMilliseconds -
        _reactionNowMs;
    if (waitMs < 0) waitMs = 0;
    _channelReactionTimers[channelIdHex] =
        Timer(Duration(milliseconds: waitMs), () {
      _channelReactionTimers.remove(channelIdHex);
      channelReactionRoundsDue();
    });
  }

  /// Sends every round that is due by the reaction clock: per channel one
  /// totals delivery to each subscriber and admin. Returns how many rounds
  /// left. The timer of [_channelReactionRoundArm] calls it; a probe calls it
  /// after moving the clock.
  Future<int> channelReactionRoundsDue() async {
    var rounds = 0;
    final now = _reactionNowMs;
    for (final channelIdHex in _channelReactionRounds.keys.toList()) {
      final round = _channelReactionRounds[channelIdHex];
      if (round == null || round.changed.isEmpty) continue;
      if (round.firstChangeAtMs + kChannelReactionRoundDelay.inMilliseconds >
          now) {
        continue;
      }
      if (await _channelReactionRoundSend(channelIdHex, round)) rounds++;
    }
    return rounds;
  }

  Future<bool> _channelReactionRoundSend(
      String channelIdHex, ChannelReactionRound round) async {
    final channel = _reactionEntityOf(channelIdHex);
    if (channel == null || channel.ownerNodeIdHex != identity.userIdHex) {
      _log.info('channel reaction round for ${_short(channelIdHex)} dropped '
          '— this device is not its owner (any more)');
      _channelReactionRounds.remove(channelIdHex);
      _channelReactionRoundPersist(channelIdHex);
      return false;
    }
    final conv = conversations[channelIdHex];
    if (conv == null) return false;
    ensureLoaded(channelIdHex);
    final byId = {for (final m in conv.messages) m.id: m};
    final atMs = _reactionNowMs;
    final changed = Set<String>.of(round.changed);
    round.changed.clear();
    round.firstChangeAtMs = 0;
    final channelIdBytes = hexToBytes(channelIdHex);
    var sentTo = 0;
    // §16.2.4/§16.2.5: on the shared key the totals are a post of their own —
    // deposited once and nudged — and 1:1 deliveries only to members on
    // pairwise legs. Every member names the post by its post identifier.
    Set<String>? pairwise;
    if (_skOn(channelIdHex)) {
      final totals = proto.ChannelReactionTotals()..atMs = Int64(atMs);
      for (final id in changed) {
        final msg = byId[id];
        if (msg == null) continue;
        final entry = proto.PostReactionTotals()
          ..postId = hexToBytes(msg.postId ?? msg.id);
        msg.reactionCounts(identity.userIdHex).forEach((emoji, n) {
          entry.counts.add(proto.ReactionCount()
            ..emoji = emoji
            ..count = n);
        });
        totals.posts.add(entry);
      }
      if (totals.posts.isNotEmpty) {
        pairwise = await _skServe(channelIdHex,
            type: proto.MessageType.MT_CHANNEL_REACTION_TOTALS,
            payload: Uint8List.fromList(totals.writeToBuffer()),
            messageId: SodiumFFI().randomBytes(16));
      }
    }
    for (final member in channel.members.values.toList()) {
      final toHex = member.nodeIdHex;
      if (toHex == identity.userIdHex) continue;
      if (pairwise != null && !pairwise.contains(toHex)) continue;
      final before = round.sent[toHex];
      final beforeOpen = before != null &&
          _myceliumOutbounds[before.id]?.state !=
              mycelium.DeliveryState.delivered;
      final posts = {...changed, if (beforeOpen) ...before.posts};
      final totals = proto.ChannelReactionTotals()..atMs = Int64(atMs);
      final carried = <String>{};
      for (final id in posts) {
        final msg = byId[id];
        if (msg == null) continue;
        final name = _channelPostNameFor(msg, toHex);
        if (name == null) continue;
        final entry = proto.PostReactionTotals()..postId = hexToBytes(name);
        msg.reactionCounts(identity.userIdHex).forEach((emoji, n) {
          entry.counts.add(proto.ReactionCount()
            ..emoji = emoji
            ..count = n);
        });
        totals.posts.add(entry);
        carried.add(id);
      }
      if (carried.isEmpty) continue;
      final id = SodiumFFI().randomBytes(16);
      final ok = await sendToUser(
        recipientUserId: hexToBytes(toHex),
        messageType: proto.MessageType.MT_CHANNEL_REACTION_TOTALS,
        payload: Uint8List.fromList(totals.writeToBuffer()),
        groupId: channelIdBytes,
        messageId: id,
      );
      if (!ok) continue;
      sentTo++;
      // §16.2.4 "totals that newer ones replace are not re-sent": the
      // delivery layer forgets the one before (its posts are in this one).
      if (before != null) _myceliumForget([before.id], peersHex: [toHex]);
      round.sent[toHex] = (id: bytesToHex(id), posts: carried);
    }
    _channelReactionRoundPersist(channelIdHex);
    _log.info('channel reaction totals for ${_short(channelIdHex)}: '
        '${changed.length} post(s) to $sentTo recipient(s)');
    return true;
  }

  void _channelReactionRoundPersist(String channelIdHex) {
    try {
      final round = _channelReactionRounds[channelIdHex];
      if (round == null) {
        store.removeEntry(kChannelReactionRoundsArea, channelIdHex);
      } else {
        store.putEntry(kChannelReactionRoundsArea, channelIdHex, round.toJson());
      }
    } catch (e) {
      _log.warn('channel reaction round: persist ${_short(channelIdHex)} '
          'failed: $e');
    }
  }

  /// At start: the rounds of the last run; a pending one keeps its due time.
  void _channelReactionRoundsLoad() {
    try {
      for (final e in store.loadArea(kChannelReactionRoundsArea).entries) {
        _channelReactionRounds[e.key] = ChannelReactionRound.fromJson(e.value);
        _channelReactionRoundArm(e.key);
      }
    } catch (e) {
      _log.warn('channel reaction rounds: load failed: $e');
    }
  }

  // ── A subscriber or admin receives totals ─────────────────────────────

  /// §16.2.4: totals from the owner. Per post the newest by the time in the
  /// content is kept; older ones change nothing.
  void _channelReactionTotalsReceived(HarvestEvent event) {
    final channelIdHex = event.groupId?.hex ?? '';
    final channel = _reactionEntityOf(channelIdHex);
    if (channel == null) return;
    final senderHex = event.senderUserId.hex;
    if (senderHex != channel.ownerNodeIdHex ||
        senderHex == identity.userIdHex) {
      _log.info('channel reaction totals from ${_short(senderHex)}, who is '
          'not the owner of ${_short(channelIdHex)} — dropped');
      return;
    }
    final proto.ChannelReactionTotals totals;
    try {
      totals = proto.ChannelReactionTotals.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('channel reaction totals: parse fail: $e');
      return;
    }
    final atMs = totals.atMs.toInt();
    var applied = 0;
    for (final p in totals.posts) {
      final msg = _channelPostFor(channelIdHex, p.postId.hex, senderHex);
      if (msg == null || atMs <= msg.reactionTotalsAtMs) continue;
      msg.reactionTotals = {
        for (final c in p.counts)
          if (c.emoji.isNotEmpty && c.count > 0) c.emoji: c.count,
      };
      msg.reactionTotalsAtMs = atMs;
      if (msg.ownReactionAtMs < atMs) {
        msg.ownReactionCounted = msg.reactions.entries
            .where((e) => e.value.contains(identity.userIdHex))
            .map((e) => e.key)
            .firstOrNull;
      }
      persistMessage(channelIdHex, msg);
      applied++;
    }
    if (applied > 0) {
      onStateChanged?.call();
      _saveConversations();
    }
  }

  // ── Ownership passes ──────────────────────────────────────────────────

  /// §16.2.4: the previous owner hands over to [newOwnerHex] who holds which
  /// reaction on the posts of [channel], and which posts changed since the
  /// last totals. Called where ownership leaves this device. With
  /// [keepConversation] this device goes on in the channel and keeps from
  /// now on the totals of the moment and its own reaction only.
  void _channelReactionHandoverSend(ChannelInfo channel, String newOwnerHex,
      {required bool keepConversation}) {
    final channelIdHex = channel.channelIdHex;
    final round = _channelReactionRounds.remove(channelIdHex);
    _channelReactionTimers.remove(channelIdHex)?.cancel();
    _channelReactionRoundPersist(channelIdHex);
    final conv = conversations[channelIdHex];
    if (conv == null) return;
    ensureLoaded(channelIdHex);
    final handover = proto.ChannelReactionHandover()
      ..firstChangeAtMs = Int64(round?.firstChangeAtMs ?? 0);
    final nowMs = _reactionNowMs;
    final me = identity.userIdHex;
    for (final msg in conv.messages) {
      final pending = round?.changed.contains(msg.id) ?? false;
      if (msg.reactions.isEmpty && !pending) continue;
      final name = _channelPostNameFor(msg, newOwnerHex);
      if (name != null) {
        final entry = proto.PostReactionHolders()
          ..postId = hexToBytes(name)
          ..pending = pending;
        for (final e in msg.reactions.entries) {
          for (final person in e.value) {
            entry.holders.add(proto.ReactionHolder()
              ..userId = hexToBytes(person)
              ..emoji = e.key);
          }
        }
        handover.posts.add(entry);
      }
      if (keepConversation) {
        // From now on this device knows totals, not persons.
        msg.reactionTotals = msg.reactionCounts(me);
        msg.reactionTotalsAtMs = nowMs;
        final own = msg.reactions.entries
            .where((e) => e.value.contains(me))
            .map((e) => e.key)
            .firstOrNull;
        msg.reactions = {?own: {me}};
        msg.ownReactionCounted = own;
        msg.ownReactionAtMs = 0;
        persistMessage(channelIdHex, msg);
      }
    }
    if (handover.posts.isEmpty) return;
    _detachedSend('MT_CHANNEL_REACTION_HANDOVER', sendToUser(
      recipientUserId: hexToBytes(newOwnerHex),
      messageType: proto.MessageType.MT_CHANNEL_REACTION_HANDOVER,
      payload: Uint8List.fromList(handover.writeToBuffer()),
      groupId: hexToBytes(channelIdHex),
    ));
    _log.info('channel reactions of ${_short(channelIdHex)} handed over to '
        '${_short(newOwnerHex)} (${handover.posts.length} post(s))');
  }

  /// §16.2.4: who holds which reaction, from the previous owner — or one
  /// reaction a device that is no longer the owner passed on. Taken from a
  /// member that is the owner or hands the role to this device.
  void _channelReactionHandoverReceived(HarvestEvent event, bool mirrored) {
    final channelIdHex = event.groupId?.hex ?? '';
    final channel = _channels[channelIdHex];
    if (channel == null) return;
    final senderHex = event.senderUserId.hex;
    final me = identity.userIdHex;
    final ownerHex = channel.ownerNodeIdHex;
    if (!channel.members.containsKey(senderHex) ||
        (ownerHex != me && ownerHex != senderHex)) {
      _log.info('channel reaction handover from ${_short(senderHex)} for '
          '${_short(channelIdHex)} — neither owner nor handing to this '
          'device, dropped');
      return;
    }
    final proto.ChannelReactionHandover handover;
    try {
      handover = proto.ChannelReactionHandover.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('channel reaction handover: parse fail: $e');
      return;
    }
    var pendingFrom = handover.firstChangeAtMs.toInt();
    if (pendingFrom <= 0) pendingFrom = _reactionNowMs;
    final changed = <String>[];
    for (final p in handover.posts) {
      final msg = _channelPostFor(channelIdHex, p.postId.hex, senderHex);
      if (msg == null) continue;
      for (final h in p.holders) {
        _reactionPersonSet(channelIdHex, msg, h.userId.hex, h.emoji, false);
      }
      // This device counts persons from now on; totals were a subscriber's.
      msg.reactionTotals = null;
      msg.reactionTotalsAtMs = 0;
      msg.ownReactionCounted = null;
      msg.ownReactionAtMs = 0;
      persistMessage(channelIdHex, msg);
      if (p.pending) changed.add(msg.id);
    }
    onStateChanged?.call();
    _saveConversations();
    if (mirrored || changed.isEmpty) return;
    final round = _channelReactionRounds.putIfAbsent(
        channelIdHex, () => ChannelReactionRound());
    if (round.changed.isEmpty || round.firstChangeAtMs == 0 ||
        pendingFrom < round.firstChangeAtMs) {
      round.firstChangeAtMs = pendingFrom;
    }
    round.changed.addAll(changed);
    _channelReactionRoundPersist(channelIdHex);
    _channelReactionRoundArm(channelIdHex);
  }
}
