import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/linkable_ring_signature.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/network/v3_frame_codec.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

class PollService {
  PollService(this._ctx);

  final ServiceContext _ctx;
  late final CLogger _log;

  late PollManager pollManager;

  // ── State ─────────────────────────────────────────────────────────
  final Map<String, Set<String>> anonymousKeyImages = {};
  Timer? _pollDeadlineTimer;
  final Map<String, Timer> _pendingAnonVoteSends = {};
  final Map<String, Completer<bool>> _anonSubmitAcks = {};

  // ── Callbacks (wired from CleonaService) ──────────────────────────
  void Function(String pollId, String groupId, String question)? onPollCreated;
  void Function(String pollId)? onPollTallyUpdated;
  void Function(String pollId)? onPollStateChanged;

  // ── Init / Dispose ────────────────────────────────────────────────

  void init() {
    _log = CLogger.get('polls', profileDir: _ctx.identity.profileDir);
    pollManager = PollManager(
      profileDir: _ctx.profileDir,
      identityId: _ctx.identity.userIdHex,
      fileEnc: _ctx.fileEnc,
    );
    pollManager.load();

    for (final poll in pollManager.polls.values) {
      for (final v in poll.votes.values) {
        if (v.anonymous) {
          anonymousKeyImages
              .putIfAbsent(poll.pollId, () => {})
              .add(v.voterIdHex);
        }
      }
    }
    _startPollDeadlineTimer();
  }

  void dispose() {
    _pollDeadlineTimer?.cancel();
    _pollDeadlineTimer = null;
    for (final t in _pendingAnonVoteSends.values) {
      t.cancel();
    }
    _pendingAnonVoteSends.clear();
  }

  // ── Utilities ─────────────────────────────────────────────────────

  Iterable<String>? _pollRecipients(String entityIdHex) {
    final group = _ctx.groups[entityIdHex];
    if (group != null) {
      return group.members.keys.where((h) => h != _ctx.identity.userIdHex);
    }
    final channel = _ctx.channels[entityIdHex];
    if (channel != null) {
      return channel.members.keys.where((h) => h != _ctx.identity.userIdHex);
    }
    return null;
  }

  List<Uint8List> _ringForEntity(String entityIdHex) {
    final members = _pollRecipients(entityIdHex)?.toList() ?? const [];
    final keys = <Uint8List>[];
    final channel = _ctx.channels[entityIdHex];
    for (final memberHex in members) {
      final c = _ctx.contacts[memberHex];
      if (c?.ed25519Pk != null) {
        keys.add(c!.ed25519Pk!);
      } else if (channel != null) {
        final m = channel.members[memberHex];
        if (m?.ed25519Pk != null) keys.add(m!.ed25519Pk!);
      }
    }
    keys.add(_ctx.identity.ed25519PublicKey);
    keys.sort((a, b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        final d = a[i] - b[i];
        if (d != 0) return d;
      }
      return a.length - b.length;
    });
    return keys;
  }

  // ── Protobuf encode/decode ────────────────────────────────────────

  proto.PollCreateMsg _encodePollCreate(Poll poll) {
    final msg = proto.PollCreateMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..question = poll.question
      ..description = poll.description
      ..pollType =
          proto.PollType.valueOf(poll.pollType.index) ?? proto.PollType.POLL_SINGLE_CHOICE
      ..groupId = hexToBytes(poll.groupId)
      ..createdBy = _ctx.identity.userId
      ..createdByName = poll.createdByName
      ..createdAt = Int64(poll.createdAt)
      ..settings = (proto.PollSettingsMsg()
        ..anonymous = poll.settings.anonymous
        ..deadline = Int64(poll.settings.deadline)
        ..allowVoteChange = poll.settings.allowVoteChange
        ..showResultsBeforeClose = poll.settings.showResultsBeforeClose
        ..maxChoices = poll.settings.maxChoices
        ..scaleMin = poll.settings.scaleMin
        ..scaleMax = poll.settings.scaleMax
        ..onlyMembersCanVote = poll.settings.onlyMembersCanVote);
    for (final o in poll.options) {
      msg.options.add(proto.PollOptionMsg()
        ..optionId = o.optionId
        ..label = o.label
        ..dateStart = Int64(o.dateStart ?? 0)
        ..dateEnd = Int64(o.dateEnd ?? 0));
    }
    return msg;
  }

  Poll _decodePollCreate(proto.PollCreateMsg msg, {required String senderHex}) {
    final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
    final groupIdHex = bytesToHex(Uint8List.fromList(msg.groupId));
    final settings = PollSettings(
      anonymous: msg.settings.anonymous,
      deadline: msg.settings.deadline.toInt(),
      allowVoteChange: msg.settings.allowVoteChange,
      showResultsBeforeClose: msg.settings.showResultsBeforeClose,
      maxChoices: msg.settings.maxChoices,
      scaleMin: msg.settings.scaleMin == 0 ? 1 : msg.settings.scaleMin,
      scaleMax: msg.settings.scaleMax == 0 ? 5 : msg.settings.scaleMax,
      onlyMembersCanVote: msg.settings.onlyMembersCanVote,
    );
    final options = msg.options
        .map((o) => PollOption(
              optionId: o.optionId,
              label: o.label,
              dateStart: o.dateStart.toInt() == 0 ? null : o.dateStart.toInt(),
              dateEnd: o.dateEnd.toInt() == 0 ? null : o.dateEnd.toInt(),
            ))
        .toList();
    return Poll(
      pollId: pollIdHex,
      identityId: _ctx.identity.userIdHex,
      question: msg.question,
      description: msg.description,
      pollType:
          PollType.values[msg.pollType.value.clamp(0, PollType.values.length - 1)],
      options: options,
      settings: settings,
      groupId: groupIdHex,
      createdByHex: senderHex,
      createdByName: msg.createdByName,
      createdAt: msg.createdAt.toInt(),
    );
  }

  proto.PollVoteMsg _encodePollVote(PollVoteRecord v, {bool stripIdentity = false}) {
    final msg = proto.PollVoteMsg()
      ..pollId = hexToBytes(v.pollId)
      ..scaleValue = v.scaleValue
      ..freeText = v.freeText
      ..votedAt = Int64(v.votedAt);
    if (!stripIdentity) {
      msg
        ..voterId = _ctx.identity.userId
        ..voterName = v.voterName;
    }
    msg.selectedOptions.addAll(v.selectedOptions);
    for (final entry in v.dateResponses.entries) {
      msg.dateResponses.add(proto.DateResponseMsg()
        ..optionId = entry.key
        ..availability = proto.DateAvailability.valueOf(entry.value.index) ??
            proto.DateAvailability.DATE_AVAIL_YES);
    }
    return msg;
  }

  PollVoteRecord _decodePollVote(
    proto.PollVoteMsg msg, {
    required String voterIdHex,
    required bool anonymous,
  }) {
    return PollVoteRecord(
      pollId: bytesToHex(Uint8List.fromList(msg.pollId)),
      voterIdHex: voterIdHex,
      voterName: msg.voterName,
      selectedOptions: msg.selectedOptions.toList(),
      dateResponses: {
        for (final r in msg.dateResponses)
          r.optionId:
              DateAvailability.values[r.availability.value.clamp(0, DateAvailability.values.length - 1)]
      },
      scaleValue: msg.scaleValue,
      freeText: msg.freeText,
      votedAt: msg.votedAt.toInt(),
      anonymous: anonymous,
    );
  }

  // ── Senders ───────────────────────────────────────────────────────

  Future<void> _fanoutToEntity(String entityIdHex, proto.MessageTypeV3 type, List<int> payload) async {
    final recipients = _pollRecipients(entityIdHex);
    if (recipients == null) return;

    final channel = _ctx.channels[entityIdHex];
    if (channel != null) {
      final channelIdBytes = hexToBytes(entityIdHex);
      for (final member in channel.members.values) {
        if (member.nodeIdHex == _ctx.identity.userIdHex) continue;
        final contact = _ctx.contacts[member.nodeIdHex];
        final x25519Pk = contact?.x25519Pk ?? member.x25519Pk;
        final mlKemPk = contact?.mlKemPk ?? member.mlKemPk;
        if (x25519Pk == null || x25519Pk.isEmpty ||
            mlKemPk == null || mlKemPk.isEmpty) continue;
        await _ctx.sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: type,
          payload: Uint8List.fromList(payload),
          groupId: channelIdBytes,
        );
      }
      return;
    }

    for (final memberHex in recipients) {
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        type,
        Uint8List.fromList(payload),
      );
    }
  }

  Future<void> _sendPollCreate(Poll poll) async {
    final payload = _encodePollCreate(poll).writeToBuffer();
    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_CREATE, payload);
    _log.info('Sent POLL_CREATE ${poll.pollId.substring(0, 8)} to entity ${poll.groupId.substring(0, 8)}');
  }

  Future<void> _sendPollVoteNonAnonymous(Poll poll, PollVoteRecord vote) async {
    final msg = _encodePollVote(vote);
    final payload = msg.writeToBuffer();

    if (_ctx.channels.containsKey(poll.groupId) &&
        poll.createdByHex != _ctx.identity.userIdHex) {
      await _ctx.sendEncryptedPayload(
        hexToBytes(poll.createdByHex),
        proto.MessageTypeV3.MTV3_POLL_VOTE,
        Uint8List.fromList(payload),
      );
    } else {
      await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_VOTE, payload);
    }
  }

  Future<void> _sendPollVoteAnonymous(Poll poll, PollVoteRecord vote) async {
    final identityIndexed = _encodePollVote(vote, stripIdentity: true);
    final voteBytes = identityIndexed.writeToBuffer();
    final ring = _ringForEntity(poll.groupId);
    final context = hexToBytes(poll.pollId);
    final signed = LinkableRingSignature.sign(
      message: Uint8List.fromList(voteBytes),
      context: context,
      ringMembers: ring,
      signerSk: _ctx.identity.ed25519SecretKey,
      signerPk: _ctx.identity.ed25519PublicKey,
    );

    final msg = proto.PollVoteAnonymousMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..encryptedChoice = voteBytes
      ..keyImage = signed.keyImage
      ..ringSignature = signed.signature
      ..votedAt = Int64(vote.votedAt);
    for (final pk in ring) {
      msg.ringMembers.add(pk);
    }

    final payload = Uint8List.fromList(msg.writeToBuffer());
    await _sendAnonViaReBroadcaster(
      poll: poll,
      messageType: proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS,
      payload: payload,
    );
  }

  Future<void> _sendPollVoteRevoke(Poll poll, Uint8List keyImage) async {
    final ring = _ringForEntity(poll.groupId);
    final context = hexToBytes(poll.pollId);
    final marker = Uint8List.fromList('revoke'.codeUnits);
    final signed = LinkableRingSignature.sign(
      message: marker,
      context: context,
      ringMembers: ring,
      signerSk: _ctx.identity.ed25519SecretKey,
      signerPk: _ctx.identity.ed25519PublicKey,
      presetKeyImage: keyImage,
    );

    final msg = proto.PollVoteRevokeMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..keyImage = keyImage
      ..ringSignature = signed.signature
      ..revokedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    for (final pk in ring) {
      msg.ringMembers.add(pk);
    }

    final payload = Uint8List.fromList(msg.writeToBuffer());
    await _sendAnonViaReBroadcaster(
      poll: poll,
      messageType: proto.MessageTypeV3.MTV3_POLL_REVOKE,
      payload: payload,
    );
  }

  // ── §11.4.8 Anonymous Vote Re-Broadcaster ────────────────────────

  Future<void> _sendAnonViaReBroadcaster({
    required Poll poll,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
  }) async {
    final recipients = _pollRecipients(poll.groupId);
    if (recipients == null || recipients.isEmpty) return;

    final isChannel = _ctx.channels.containsKey(poll.groupId);
    final effectiveRecipients = isChannel && poll.createdByHex != _ctx.identity.userIdHex
        ? [poll.createdByHex]
        : recipients.toList();

    final channel = _ctx.channels[poll.groupId];
    final entries = <proto.PollAnonSubmitEntry>[];
    for (final recipientHex in effectiveRecipients) {
      final contact = _ctx.contacts[recipientHex];
      final chMember = channel?.members[recipientHex];
      final x25519Pk = contact?.x25519Pk ?? chMember?.x25519Pk;
      final mlKemPk = contact?.mlKemPk ?? chMember?.mlKemPk;
      if (x25519Pk == null || x25519Pk.isEmpty ||
          mlKemPk == null || mlKemPk.isEmpty) continue;

      final inner = proto.ApplicationFrameV3()
        ..recipientUserId = hexToBytes(recipientHex)
        ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
        ..messageId = SodiumFFI().randomBytes(16)
        ..messageType = messageType
        ..payload = payload;

      final kemBlob = V3FrameCodec.buildDeAttributedInner(
        inner: inner,
        recipientUserX25519Pk: x25519Pk,
        recipientUserMlKemPk: mlKemPk,
      );

      final entry = proto.PollAnonSubmitEntry()
        ..recipientUserId = hexToBytes(recipientHex)
        ..kemBlob = kemBlob;
      if (contact != null && contact.deviceNodeIds.isNotEmpty) {
        for (final did in contact.deviceNodeIds) {
          entry.deviceIds.add(hexToBytes(did));
        }
      }
      entries.add(entry);
    }
    if (entries.isEmpty) return;

    final bundle = proto.PollAnonSubmitMsg()
      ..pollId = hexToBytes(poll.pollId);
    bundle.entries.addAll(entries);
    final bundleBytes = bundle.writeToBuffer();

    if (bundleBytes.length > 65536 || entries.length > 64) {
      _log.warn('Anon submit bundle too large (${bundleBytes.length}B, '
          '${entries.length} entries) — legacy fallback');
      await _sendAnonLegacy(poll, messageType, payload, effectiveRecipients);
      return;
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final r = _selectReBroadcaster(poll.groupId);
      if (r == null) {
        _log.info('No suitable re-broadcaster found — legacy fallback');
        await _sendAnonLegacy(poll, messageType, payload, effectiveRecipients);
        return;
      }

      final pollIdHex = poll.pollId;
      final completer = Completer<bool>();
      _anonSubmitAcks[pollIdHex] = completer;

      final ok = await _ctx.node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT,
        innerPayload: Uint8List.fromList(bundleBytes),
        recipientDeviceId: r.nodeId,
      );

      if (!ok) {
        _anonSubmitAcks.remove(pollIdHex);
        _log.info('Anon submit to R ${_hexShort(r.nodeId)} failed (attempt $attempt)');
        continue;
      }

      final acked = await completer.future
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      _anonSubmitAcks.remove(pollIdHex);

      if (acked) {
        _log.info('Anon vote re-broadcast OK via R ${_hexShort(r.nodeId)}');
        return;
      }
      _log.info('Anon submit ACK timeout from R ${_hexShort(r.nodeId)} '
          '(attempt $attempt)');
    }

    _log.info('All re-broadcaster attempts failed — legacy fallback');
    await _sendAnonLegacy(poll, messageType, payload, effectiveRecipients);
  }

  Future<void> _sendAnonLegacy(
    Poll poll,
    proto.MessageTypeV3 messageType,
    Uint8List payload,
    List<String> recipients,
  ) async {
    final channel = _ctx.channels[poll.groupId];
    if (channel != null) {
      final channelIdBytes = hexToBytes(poll.groupId);
      for (final memberHex in recipients) {
        final contact = _ctx.contacts[memberHex];
        final m = channel.members[memberHex];
        final x25519Pk = contact?.x25519Pk ?? m?.x25519Pk;
        final mlKemPk = contact?.mlKemPk ?? m?.mlKemPk;
        if (x25519Pk == null || x25519Pk.isEmpty ||
            mlKemPk == null || mlKemPk.isEmpty) continue;
        await _ctx.sendToUser(
          recipientUserId: hexToBytes(memberHex),
          messageType: messageType,
          payload: payload,
          groupId: channelIdBytes,
        );
      }
      return;
    }
    for (final memberHex in recipients) {
      await _ctx.sendEncryptedPayload(
        hexToBytes(memberHex),
        messageType,
        payload,
      );
    }
  }

  PeerInfo? _selectReBroadcaster(String entityIdHex) {
    final participantIds = <String>{};
    final group = _ctx.groups[entityIdHex];
    if (group != null) {
      participantIds.addAll(group.members.keys);
    }
    final channel = _ctx.channels[entityIdHex];
    if (channel != null) {
      participantIds.addAll(channel.members.keys);
    }
    participantIds.add(_ctx.identity.userIdHex);

    final contactIds = _ctx.contacts.keys.toSet();

    final candidates = _ctx.node.routingTable.allPeers.where((p) {
      final pHex = bytesToHex(p.nodeId);
      final uHex = p.userId != null ? bytesToHex(p.userId!) : null;
      if (participantIds.contains(pHex) || participantIds.contains(uHex)) return false;
      if (contactIds.contains(pHex) || contactIds.contains(uHex)) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;
    final idx = SodiumFFI().randomBytes(4);
    final v = ((idx[0] << 24) | (idx[1] << 16) | (idx[2] << 8) | idx[3]) & 0x7fffffff;
    return candidates[v % candidates.length];
  }

  void _sendAnonSubmitAck(
      Uint8List recipientDeviceId, List<int> pollId, bool accepted, String reason) {
    final ack = proto.PollAnonSubmitAckMsg()
      ..pollId = pollId
      ..accepted = accepted
      ..rejectReason = reason;
    unawaited(_ctx.node.sendInfraTo(
      messageType: proto.MessageTypeV3.MTV3_POLL_ANON_SUBMIT_ACK,
      innerPayload: Uint8List.fromList(ack.writeToBuffer()),
      recipientDeviceId: recipientDeviceId,
    ));
  }

  Future<void> _sendPollUpdate(Poll poll, proto.PollAction action,
      {List<PollOption>? addedOptions,
      List<int>? removedOptions,
      int? newDeadline}) async {
    final msg = proto.PollUpdateMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..action = action
      ..updatedBy = _ctx.identity.userId
      ..updatedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    if (addedOptions != null) {
      for (final o in addedOptions) {
        msg.addedOptions.add(proto.PollOptionMsg()
          ..optionId = o.optionId
          ..label = o.label
          ..dateStart = Int64(o.dateStart ?? 0)
          ..dateEnd = Int64(o.dateEnd ?? 0));
      }
    }
    if (removedOptions != null) msg.removedOptions.addAll(removedOptions);
    if (newDeadline != null) msg.newDeadline = Int64(newDeadline);

    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_UPDATE, msg.writeToBuffer());
  }

  Future<void> _broadcastPollSnapshot(Poll poll) async {
    final tally = pollManager.computeTally(poll.pollId);
    final msg = proto.PollSnapshotMsg()
      ..pollId = hexToBytes(poll.pollId)
      ..totalVotes = tally.totalVotes
      ..scaleAverage = tally.scaleAverage
      ..scaleCount = tally.scaleCount
      ..closed = poll.closed
      ..snapshotAt = Int64(DateTime.now().millisecondsSinceEpoch);
    if (poll.pollType == PollType.datePoll) {
      for (final entry in tally.dateCounts.entries) {
        msg.optionCounts.add(proto.OptionCountMsg()
          ..optionId = entry.key
          ..yesCount = entry.value[DateAvailability.yes] ?? 0
          ..maybeCount = entry.value[DateAvailability.maybe] ?? 0
          ..noCount = entry.value[DateAvailability.no] ?? 0);
      }
    } else {
      for (final entry in tally.optionCounts.entries) {
        msg.optionCounts.add(proto.OptionCountMsg()
          ..optionId = entry.key
          ..count = entry.value);
      }
    }
    await _fanoutToEntity(poll.groupId, proto.MessageTypeV3.MTV3_POLL_SNAPSHOT, msg.writeToBuffer());
  }

  void _startPollDeadlineTimer() {
    _pollDeadlineTimer?.cancel();
    _pollDeadlineTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final closed = pollManager.enforceDeadlines();
      for (final id in closed) {
        final poll = pollManager.polls[id];
        if (poll != null && poll.createdByHex == _ctx.identity.userIdHex) {
          _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_CLOSE);
          if (_ctx.channels.containsKey(poll.groupId)) {
            _broadcastPollSnapshot(poll);
          }
        }
        onPollStateChanged?.call(id);
      }
      if (closed.isNotEmpty) _ctx.notifyStateChanged();
    });
  }

  // ── Business Logic (public API) ───────────────────────────────────

  Future<String> createPoll({
    required String question,
    String description = '',
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('createPoll blocked: reducedMode active');
      return '';
    }
    if (_pollRecipients(groupIdHex) == null) {
      throw ArgumentError('Unknown group/channel $groupIdHex');
    }
    final channel = _ctx.channels[groupIdHex];
    if (channel != null && !_ctx.hasChannelPermission(channel, 'post')) {
      _log.warn('createPoll blocked: no post permission in channel');
      return '';
    }
    final normalisedOptions = <PollOption>[];
    for (var i = 0; i < options.length; i++) {
      normalisedOptions.add(PollOption(
        optionId: i,
        label: options[i].label,
        dateStart: options[i].dateStart,
        dateEnd: options[i].dateEnd,
      ));
    }
    final poll = Poll(
      pollId: PollManager.generateUuid(),
      identityId: _ctx.identity.userIdHex,
      question: question,
      description: description,
      pollType: pollType,
      options: normalisedOptions,
      settings: settings,
      groupId: groupIdHex,
      createdByHex: _ctx.identity.userIdHex,
      createdByName: _ctx.displayName,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    pollManager.createPoll(poll);

    if (_ctx.conversations.containsKey(groupIdHex)) {
      _ctx.addMessageToConversation(groupIdHex, UiMessage(
        id: bytesToHex(SodiumFFI().randomBytes(16)),
        conversationId: groupIdHex,
        senderNodeIdHex: _ctx.identity.userIdHex,
        text: '${_ctx.displayName}: ${poll.question}',
        timestamp: DateTime.fromMillisecondsSinceEpoch(poll.createdAt),
        type: UiMessageType.pollCreate,
        status: MessageStatus.delivered,
        isOutgoing: true,
        pollId: poll.pollId,
      ), isGroup: _ctx.groups.containsKey(groupIdHex), isChannel: _ctx.channels.containsKey(groupIdHex));
    }

    await _sendPollCreate(poll);
    onPollCreated?.call(poll.pollId, groupIdHex, poll.question);
    _ctx.notifyStateChanged();
    return poll.pollId;
  }

  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('submitPollVote blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.closed) return false;
    if (poll.settings.anonymous) {
      throw StateError('Use submitPollVoteAnonymous for anonymous polls');
    }
    final vote = PollVoteRecord(
      pollId: pollId,
      voterIdHex: _ctx.identity.userIdHex,
      voterName: _ctx.displayName,
      selectedOptions: selectedOptions ?? [],
      dateResponses: dateResponses ?? {},
      scaleValue: scaleValue ?? 0,
      freeText: freeText ?? '',
      votedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (!pollManager.recordVote(vote)) return false;
    await _sendPollVoteNonAnonymous(poll, vote);

    if (_ctx.channels.containsKey(poll.groupId) &&
        poll.createdByHex == _ctx.identity.userIdHex) {
      await _broadcastPollSnapshot(poll);
    }
    onPollTallyUpdated?.call(pollId);
    _ctx.notifyStateChanged();
    return true;
  }

  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('submitPollVoteAnonymous blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.closed) return false;
    if (!poll.settings.anonymous) {
      throw StateError('Poll is not configured as anonymous');
    }

    final vote = PollVoteRecord(
      pollId: pollId,
      voterIdHex: '',
      voterName: '',
      selectedOptions: selectedOptions ?? [],
      dateResponses: dateResponses ?? {},
      scaleValue: scaleValue ?? 0,
      freeText: freeText ?? '',
      votedAt: DateTime.now().millisecondsSinceEpoch,
      anonymous: true,
    );

    final ring = _ringForEntity(poll.groupId);
    final keyImage = LinkableRingSignature.deriveKeyImage(
      signerSk: _ctx.identity.ed25519SecretKey,
      signerPk: _ctx.identity.ed25519PublicKey,
      context: hexToBytes(pollId),
    );
    final keyImageHex = bytesToHex(keyImage);

    final seen = anonymousKeyImages.putIfAbsent(pollId, () => {});
    final pendingKey = '$pollId:$keyImageHex';
    var needsRevoke = false;
    if (seen.contains(keyImageHex)) {
      if (!poll.settings.allowVoteChange) return false;
      final pending = _pendingAnonVoteSends.remove(pendingKey);
      pending?.cancel();
      needsRevoke = pending == null;
      pollManager.revokeAnonymousVote(pollId, keyImageHex);
      seen.remove(keyImageHex);
    }

    pollManager.recordVote(PollVoteRecord(
      pollId: pollId,
      voterIdHex: keyImageHex,
      voterName: '',
      selectedOptions: vote.selectedOptions,
      dateResponses: vote.dateResponses,
      scaleValue: vote.scaleValue,
      freeText: vote.freeText,
      votedAt: vote.votedAt,
      anonymous: true,
    ));
    seen.add(keyImageHex);

    ring.length;

    Future<void> sendNow() async {
      try {
        if (needsRevoke) await _sendPollVoteRevoke(poll, keyImage);
        await _sendPollVoteAnonymous(poll, vote);
      } catch (e) {
        _log.warn('Anonymous vote send failed: $e');
      }
    }

    final jitter = _anonVoteJitter();
    if (jitter == Duration.zero) {
      await sendNow();
    } else {
      _pendingAnonVoteSends[pendingKey] = Timer(jitter, () {
        _pendingAnonVoteSends.remove(pendingKey);
        sendNow();
      });
    }
    onPollTallyUpdated?.call(pollId);
    _ctx.notifyStateChanged();
    return true;
  }

  Duration _anonVoteJitter() {
    final maxMs = _ctx.moderationConfig.anonVoteJitterMax.inMilliseconds;
    if (maxMs <= 0) return Duration.zero;
    final b = SodiumFFI().randomBytes(4);
    final v = ((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) & 0x7fffffff;
    return Duration(milliseconds: v % maxMs);
  }

  Future<bool> revokePollVoteAnonymous(String pollId) async {
    if (_ctx.reducedMode) {
      _log.warn('revokePollVoteAnonymous blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || !poll.settings.anonymous) return false;
    final keyImage = LinkableRingSignature.deriveKeyImage(
      signerSk: _ctx.identity.ed25519SecretKey,
      signerPk: _ctx.identity.ed25519PublicKey,
      context: hexToBytes(pollId),
    );
    final keyImageHex = bytesToHex(keyImage);
    if (!(anonymousKeyImages[pollId]?.contains(keyImageHex) ?? false)) {
      return false;
    }
    final pending = _pendingAnonVoteSends.remove('$pollId:$keyImageHex');
    pending?.cancel();
    if (pending == null) {
      await _sendPollVoteRevoke(poll, keyImage);
    }
    pollManager.revokeAnonymousVote(pollId, keyImageHex);
    anonymousKeyImages[pollId]?.remove(keyImageHex);
    onPollTallyUpdated?.call(pollId);
    _ctx.notifyStateChanged();
    return true;
  }

  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete = false,
  }) async {
    if (_ctx.reducedMode) {
      _log.warn('updatePoll blocked: reducedMode active');
      return false;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null) return false;
    final group = _ctx.groups[poll.groupId];
    final channel = _ctx.channels[poll.groupId];
    final role = group?.members[_ctx.identity.userIdHex]?.role ??
        channel?.members[_ctx.identity.userIdHex]?.role;
    final isCreator = poll.createdByHex == _ctx.identity.userIdHex;
    final isAdmin = role == 'owner' || role == 'admin';
    if (!isCreator && !isAdmin) return false;

    if (delete) {
      pollManager.deletePoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_DELETE);
      if (SystemChannels.isSystemChannel(poll.groupId)) {
        final conv = _ctx.conversations[poll.groupId];
        conv?.messages.removeWhere((m) => m.pollId == pollId);
      }
      onPollStateChanged?.call(pollId);
      _ctx.notifyStateChanged();
      _ctx.saveConversations();
      return true;
    }
    if (close == true) {
      pollManager.closePoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_CLOSE);
      if (_ctx.channels.containsKey(poll.groupId)) {
        await _broadcastPollSnapshot(poll);
      }
    }
    if (reopen == true) {
      pollManager.reopenPoll(pollId);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_REOPEN);
    }
    if (addOptions != null && addOptions.isNotEmpty) {
      pollManager.addOptions(pollId, addOptions);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_ADD_OPTIONS,
          addedOptions: addOptions);
    }
    if (removeOptions != null && removeOptions.isNotEmpty) {
      pollManager.removeOptions(pollId, removeOptions);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_REMOVE_OPTIONS,
          removedOptions: removeOptions);
    }
    if (newDeadline != null) {
      pollManager.extendDeadline(pollId, newDeadline);
      await _sendPollUpdate(poll, proto.PollAction.POLL_ACTION_EXTEND_DEADLINE,
          newDeadline: newDeadline);
    }
    onPollStateChanged?.call(pollId);
    _ctx.notifyStateChanged();
    return true;
  }

  // ── Infra Handlers (Re-Broadcaster) ──────────────────────────────

  void handleIncomingPollAnonSubmit(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress from,
    int port,
    SenderIdentitySnapshot snapshot,
  ) {
    final proto.PollAnonSubmitMsg bundle;
    try {
      bundle = proto.PollAnonSubmitMsg.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('POLL_ANON_SUBMIT parse error: $e');
      return;
    }

    if (frame.payload.length > 65536) {
      _log.warn('POLL_ANON_SUBMIT too large: ${frame.payload.length}B — rejected');
      _sendAnonSubmitAck(senderDeviceId, bundle.pollId, false, 'too_large');
      return;
    }
    if (bundle.entries.length > 64) {
      _log.warn('POLL_ANON_SUBMIT too many entries: ${bundle.entries.length} — rejected');
      _sendAnonSubmitAck(senderDeviceId, bundle.pollId, false, 'too_many_entries');
      return;
    }

    final myDeviceNodeId = _ctx.node.primaryIdentity.deviceNodeId;
    for (final entry in bundle.entries) {
      final recipientUserId = Uint8List.fromList(entry.recipientUserId);

      List<Uint8List> deviceIds;
      if (entry.deviceIds.isNotEmpty) {
        deviceIds = entry.deviceIds.map((d) => Uint8List.fromList(d)).toList();
      } else {
        final cached = _ctx.node.routingTable.getAllPeersForUserId(recipientUserId);
        if (cached.isEmpty) continue;
        deviceIds = cached.map((p) => p.nodeId).toList();
      }

      for (final deviceId in deviceIds) {
        final outer = V3FrameCodec.buildOuter(
          nextHopDeviceId: deviceId,
          senderDeviceId: myDeviceNodeId,
          deviceKeys: _ctx.node.deviceKeyPair,
          innerPayload: Uint8List.fromList(entry.kemBlob),
          payloadType: proto.PayloadTypeV3.PAYLOAD_APPLICATION_FRAME,
          applicationFlavor: true,
          skipPoW: true,
        );
        unawaited(_ctx.node.sendToDevice(outer, deviceId));
      }
    }

    _log.info('POLL_ANON_SUBMIT: re-originated ${bundle.entries.length} entries '
        'from ${_hexShort(senderDeviceId)}');
    _sendAnonSubmitAck(senderDeviceId, bundle.pollId, true, '');
  }

  void handleIncomingPollAnonSubmitAck(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
  ) {
    final proto.PollAnonSubmitAckMsg ack;
    try {
      ack = proto.PollAnonSubmitAckMsg.fromBuffer(frame.payload);
    } catch (e) {
      _log.warn('POLL_ANON_SUBMIT_ACK parse error: $e');
      return;
    }
    final pollIdHex = bytesToHex(Uint8List.fromList(ack.pollId));
    final completer = _anonSubmitAcks.remove(pollIdHex);
    if (completer != null && !completer.isCompleted) {
      completer.complete(ack.accepted);
      _log.info('POLL_ANON_SUBMIT_ACK from ${_hexShort(senderDeviceId)}: '
          '${ack.accepted ? "accepted" : "rejected: ${ack.rejectReason}"}');
    }
  }

  // ── V3 Application Frame Handlers ────────────────────────────────

  void handlePollCreateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollCreateMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final poll = _decodePollCreate(msg, senderHex: senderHex);

      if (_pollRecipients(poll.groupId) == null) {
        _log.debug('POLL_CREATE for unknown entity ${poll.groupId.substring(0, 8)}, ignoring');
        return;
      }

      if (pollManager.polls.containsKey(poll.pollId)) {
        _log.debug('Duplicate POLL_CREATE ${poll.pollId.substring(0, 8)}');
        return;
      }
      pollManager.createPoll(poll);

      if (_ctx.conversations.containsKey(poll.groupId)) {
        final name = _ctx.contacts[senderHex]?.displayName ?? msg.createdByName;
        _ctx.addMessageToConversation(poll.groupId, UiMessage(
          id: bytesToHex(SodiumFFI().randomBytes(16)),
          conversationId: poll.groupId,
          senderNodeIdHex: senderHex,
          text: '$name: ${poll.question}',
          timestamp: DateTime.fromMillisecondsSinceEpoch(poll.createdAt),
          type: UiMessageType.pollCreate,
          status: MessageStatus.delivered,
          isOutgoing: false,
          pollId: poll.pollId,
        ), isGroup: _ctx.groups.containsKey(poll.groupId), isChannel: _ctx.channels.containsKey(poll.groupId));
      }

      onPollCreated?.call(poll.pollId, poll.groupId, poll.question);
      _ctx.notifyStateChanged();
      _log.info('Received POLL_CREATE ${poll.pollId.substring(0, 8)} from ${senderHex.substring(0, 8)}');
    } catch (e) {
      _log.warn('handlePollCreateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handlePollVoteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) {
        _log.debug('POLL_VOTE for unknown poll $pollIdHex');
        return;
      }
      if (poll.settings.anonymous) {
        _log.warn('Ignoring non-anonymous POLL_VOTE on anonymous poll $pollIdHex');
        return;
      }
      final record = _decodePollVote(msg, voterIdHex: senderHex, anonymous: false);
      if (pollManager.recordVote(record)) {
        onPollTallyUpdated?.call(pollIdHex);
        _ctx.notifyStateChanged();

        if (_ctx.channels.containsKey(poll.groupId) &&
            poll.createdByHex == _ctx.identity.userIdHex) {
          _broadcastPollSnapshot(poll);
        }
      }
    } catch (e) {
      _log.warn('handlePollVoteV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handlePollVoteAnonymousV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteAnonymousMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;
      if (!poll.settings.anonymous) {
        _log.warn('POLL_VOTE_ANONYMOUS for non-anonymous poll, dropping');
        return;
      }

      final ring = msg.ringMembers.map((e) => Uint8List.fromList(e)).toList();
      final keyImage = Uint8List.fromList(msg.keyImage);
      final keyImageHex = bytesToHex(keyImage);
      final payload = Uint8List.fromList(msg.encryptedChoice);

      final context = hexToBytes(pollIdHex);
      final valid = LinkableRingSignature.verify(
        message: payload,
        context: context,
        keyImage: keyImage,
        ringMembers: ring,
        signature: Uint8List.fromList(msg.ringSignature),
      );
      if (!valid) {
        _log.warn('Ring signature invalid for poll $pollIdHex, dropping');
        return;
      }

      final seen = anonymousKeyImages.putIfAbsent(pollIdHex, () => {});
      if (seen.contains(keyImageHex) && !poll.settings.allowVoteChange) {
        _log.debug('Duplicate key image for $pollIdHex, dropping');
        return;
      }
      seen.add(keyImageHex);

      final voteMsg = proto.PollVoteMsg.fromBuffer(payload);
      final record = _decodePollVote(voteMsg, voterIdHex: keyImageHex, anonymous: true);
      record.voterName = '';
      pollManager.recordVote(PollVoteRecord(
        pollId: record.pollId,
        voterIdHex: keyImageHex,
        voterName: '',
        selectedOptions: record.selectedOptions,
        dateResponses: record.dateResponses,
        scaleValue: record.scaleValue,
        freeText: record.freeText,
        votedAt: record.votedAt,
        anonymous: true,
      ));
      onPollTallyUpdated?.call(pollIdHex);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handlePollVoteAnonymousV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handlePollUpdateV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollUpdateMsg.fromBuffer(frame.payload);
      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final group = _ctx.groups[poll.groupId];
      final channel = _ctx.channels[poll.groupId];
      final role = group?.members[senderHex]?.role ?? channel?.members[senderHex]?.role;
      final isCreator = senderHex == poll.createdByHex;
      final isAdmin = role == 'owner' || role == 'admin';
      if (!isCreator && !isAdmin) {
        _log.warn('POLL_UPDATE from non-privileged ${senderHex.substring(0, 8)}, ignoring');
        return;
      }

      switch (msg.action) {
        case proto.PollAction.POLL_ACTION_CLOSE:
          pollManager.closePoll(pollIdHex);
          break;
        case proto.PollAction.POLL_ACTION_REOPEN:
          pollManager.reopenPoll(pollIdHex);
          break;
        case proto.PollAction.POLL_ACTION_ADD_OPTIONS:
          pollManager.addOptions(
              pollIdHex,
              msg.addedOptions
                  .map((o) => PollOption(
                        optionId: -1,
                        label: o.label,
                        dateStart: o.dateStart.toInt() == 0 ? null : o.dateStart.toInt(),
                        dateEnd: o.dateEnd.toInt() == 0 ? null : o.dateEnd.toInt(),
                      ))
                  .toList());
          break;
        case proto.PollAction.POLL_ACTION_REMOVE_OPTIONS:
          pollManager.removeOptions(pollIdHex, msg.removedOptions.toList());
          break;
        case proto.PollAction.POLL_ACTION_EXTEND_DEADLINE:
          pollManager.extendDeadline(pollIdHex, msg.newDeadline.toInt());
          break;
        case proto.PollAction.POLL_ACTION_DELETE:
          if (SystemChannels.isSystemChannel(poll.groupId)) {
            final conv = _ctx.conversations[poll.groupId];
            conv?.messages.removeWhere((m) => m.pollId == pollIdHex);
          }
          pollManager.deletePoll(pollIdHex);
          _ctx.saveConversations();
          break;
        default:
          break;
      }
      onPollStateChanged?.call(pollIdHex);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handlePollUpdateV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handlePollSnapshotV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollSnapshotMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final senderHex = bytesToHex(Uint8List.fromList(frame.senderUserId));
      if (senderHex != poll.createdByHex) {
        _log.warn('POLL_SNAPSHOT from non-creator, ignoring');
        return;
      }

      final optionCounts = <int, int>{};
      final dateCounts = <int, Map<DateAvailability, int>>{};
      for (final oc in msg.optionCounts) {
        if (oc.yesCount + oc.maybeCount + oc.noCount > 0) {
          dateCounts[oc.optionId] = {
            DateAvailability.yes: oc.yesCount,
            DateAvailability.maybe: oc.maybeCount,
            DateAvailability.no: oc.noCount,
          };
        } else {
          optionCounts[oc.optionId] = oc.count;
        }
      }

      poll.cachedSnapshot = PollSnapshotCache(
        pollId: pollIdHex,
        totalVotes: msg.totalVotes,
        optionCounts: optionCounts,
        dateCounts: dateCounts,
        scaleAverage: msg.scaleAverage,
        scaleCount: msg.scaleCount,
        closed: msg.closed,
        snapshotAt: msg.snapshotAt.toInt(),
      );
      if (msg.closed && !poll.closed) poll.closed = true;
      poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
      pollManager.save();

      onPollTallyUpdated?.call(pollIdHex);
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.warn('handlePollSnapshotV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  void handlePollRevokeV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final msg = proto.PollVoteRevokeMsg.fromBuffer(frame.payload);
      final pollIdHex = bytesToHex(Uint8List.fromList(msg.pollId));
      final poll = pollManager.polls[pollIdHex];
      if (poll == null) return;

      final ring = msg.ringMembers.map((e) => Uint8List.fromList(e)).toList();
      final keyImage = Uint8List.fromList(msg.keyImage);
      final keyImageHex = bytesToHex(keyImage);
      final context = hexToBytes(pollIdHex);
      final marker = Uint8List.fromList('revoke'.codeUnits);
      final valid = LinkableRingSignature.verify(
        message: marker,
        context: context,
        keyImage: keyImage,
        ringMembers: ring,
        signature: Uint8List.fromList(msg.ringSignature),
      );
      if (!valid) {
        _log.warn('Revoke signature invalid for poll $pollIdHex, dropping');
        return;
      }
      if (pollManager.revokeAnonymousVote(pollIdHex, keyImageHex)) {
        anonymousKeyImages[pollIdHex]?.remove(keyImageHex);
        onPollTallyUpdated?.call(pollIdHex);
        _ctx.notifyStateChanged();
      }
    } catch (e) {
      _log.warn('handlePollRevokeV3: $e (sender=${_hexShort(Uint8List.fromList(frame.senderUserId))} device=${_hexShort(senderDeviceId)})');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────

  static String _hexShort(Uint8List bytes) {
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
