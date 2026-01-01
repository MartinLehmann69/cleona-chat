// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// The rescue bundle: restore broadcast to the contacts and the answer to
// it. Whoever recovers their identity from the seed phrase has keys but no
// data — contacts, groups and profile come back from the contacts (§6.4,
// docs/RECOVERY.md). One online contact suffices.
//
// CLASS B means: the service keeps this task, the carrier changes. V4
// continues the rescue bundle, but not via V3 frames: the `*V3` entries and
// `handleIncomingRestoreBroadcastInfra` die with the frame model, the
// domain logic underneath is rewired, not deleted.
// AP-3 does NOT delete this file — it rewrites its content.
//
// Delimited against `cleona_service_recovery.dart`: that holds the
// recovery of the IDENTITY LIST from the registry (restore index probing,
// V4 §3.5.1 / 3-M-12). Here stands the recovery of the DATA from the
// contacts. Two mechanisms, one occasion.

part of 'cleona_service.dart';

extension V3RestoreBundleOps on CleonaService {


  // ── Recovery / Restore ──────────────────────────────────────────────

  /// Handle incoming RESTORE_BROADCAST from a former contact trying to recover.
  /// We check if the sender's old_node_id matches one of our contacts,
  /// verify the signature with the old key, then send back our contact list
  /// and recent messages progressively.
  /// Test door onto [_handleRestoreBroadcast] — not a stand-in, but the
  /// same call.
  ///
  /// WHY IT IS NEEDED (S372). The acceptance limit from §13.5.4 below
  /// (lines 102-135) is a SECURITY FIX: without it the receiver accepted
  /// every resubmission of a validly signed RESTORE_BROADCAST, which cost
  /// around 30 MB of history per replay. Its guard came from a branch that
  /// still entered the receiver via `handleIncomingRestoreBroadcastInfra` —
  /// the V3 entry that the cut removed. Both living entries
  /// (`_handleRestoreBroadcast`, `_handleRestoreBroadcastV3`) are private,
  /// so a test could not reach the limit.
  ///
  /// The alternative would have been to drop the guard. A security fix
  /// without a probe has already become expensive once in this project;
  /// hence rather this one line.
  @visibleForTesting
  void handleRestoreBroadcastForTest(Uint8List payload) =>
      _handleRestoreBroadcast(payload);

  /// RESTORE_BROADCAST handler (Architecture §6.3 + §23.3 InfraFrame).
  /// [payload] is the plain `RestoreBroadcast` proto (NOT KEM-encrypted —
  /// the recovering peer's user-keys just changed, so the recipient cannot
  /// run the standard inner User-Sig path; the inner old-Ed25519 sig in
  /// the body is the canonical authenticity check). Sender lookup keys
  /// off `rb.oldNodeId` so no separate sender argument is needed.
  void _handleRestoreBroadcast(Uint8List payload) {
    try {
      // RestoreBroadcast is NOT encrypted (sender has new keys, we don't know them yet)
      // but it IS signed with the OLD key to prove ownership
      final rb = proto.RestoreBroadcast.fromBuffer(payload);
      final oldNodeIdHex = rb.oldNodeId.hex;
      final newNodeIdHex = rb.newNodeId.hex;

      // Check: is old_node_id one of our accepted contacts?
      final contact = _contacts[oldNodeIdHex];
      if (contact == null || contact.status != 'accepted') {
        _log.debug('RESTORE_BROADCAST from unknown node ${oldNodeIdHex.substring(0, 8)}, ignoring');
        return;
      }

      // H-2: verify the inner restore proof against the contact's STORED
      // keys (before we apply the broadcast's new keys). The canonical
      // bytes are the body with both signature fields empty.
      if (contact.ed25519Pk != null) {
        final dataToVerify = (proto.RestoreBroadcast()
              ..oldNodeId = rb.oldNodeId
              ..newNodeId = rb.newNodeId
              ..newEd25519Pk = rb.newEd25519Pk
              ..newX25519Pk = rb.newX25519Pk
              ..newMlKemPk = rb.newMlKemPk
              ..newMlDsaPk = rb.newMlDsaPk
              ..displayName = rb.displayName
              ..timestamp = rb.timestamp)
            .writeToBuffer();
        final edValid = SodiumFFI().verifyEd25519(
          dataToVerify,
          Uint8List.fromList(rb.signature),
          contact.ed25519Pk!,
        );
        if (!edValid) {
          _log.warn('RESTORE_BROADCAST Ed25519 signature invalid from ${oldNodeIdHex.substring(0, 8)}');
          return;
        }
        // H-2 hybrid: when the sender supplied an ML-DSA signature AND we
        // hold the contact's ML-DSA key, the PQ proof MUST verify too — a
        // classical-only forge is rejected. A missing `signature_ml_dsa`
        // (pre-H-2 sender) is accepted as legacy-classical during the
        // transition; a present-but-invalid one is a forge and rejected.
        if (rb.signatureMlDsa.isNotEmpty) {
          if (contact.mlDsaPk == null) {
            _log.warn('RESTORE_BROADCAST carries ML-DSA sig but no stored '
                'mlDsaPk for ${oldNodeIdHex.substring(0, 8)} — accepting '
                'classical proof (legacy transition)');
          } else {
            final pqValid = OqsFFI().mlDsaVerify(
              dataToVerify,
              Uint8List.fromList(rb.signatureMlDsa),
              contact.mlDsaPk!,
            );
            if (!pqValid) {
              _log.warn('RESTORE_BROADCAST ML-DSA signature INVALID from '
                  '${oldNodeIdHex.substring(0, 8)} — rejected (H-2 forge defence)');
              return;
            }
          }
        } else {
          _log.info('RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
              'is Ed25519-only (legacy-classical, pre-H-2 sender)');
        }
      }

      // ── Acceptance limit (§13.5.4) ────────────────────────────────────
      //
      // Stands DELIBERATELY behind the signature check: only a genuine
      // packet may advance the state, otherwise a stranger could lock out
      // the legitimate broadcast with an invented timestamp.
      //
      // The justification, the measurement and the deliberately open limit
      // (process-local state) stand at `_restoreBroadcastSeen` in
      // `cleona_service.dart`.
      final now = DateTime.now();
      final before = _restoreBroadcastSeen[oldNodeIdHex];
      if (rb.timestamp.toInt() >
          now.add(CleonaService.kRestoreBroadcastFutureSkew)
              .millisecondsSinceEpoch) {
        _log.warn('RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
            'lies too far in the future — discarded');
        return;
      }
      if (before != null) {
        if (rb.timestamp <= before.stamp) {
          _log.warn('RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
              'repeats an already honoured timestamp — discarded '
              '(resubmission, §13.5.4)');
          return;
        }
        if (now.difference(before.honoredAt) <
            CleonaService.kRestoreBroadcastMinGap) {
          _log.warn('RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
              'within the 5-minute window — discarded (§13.5.4)');
          return;
        }
      }
      _restoreBroadcastSeen[oldNodeIdHex] =
          (stamp: rb.timestamp, honoredAt: now);

      _log.debug('RESTORE-BROADCAST-DIAG displayName="${contact.displayName}"');
      _log.warn('RESTORE-BROADCAST-DIAG: userId migration '
          'old=${oldNodeIdHex.substring(0, 16)} → new=${newNodeIdHex.substring(0, 16)} '
          '— contact map entry will be re-keyed');

      // H-2 Part B: detect whether this restore actually CHANGES the
      // contact's identity key (new-seed re-identity or forge attempt) vs.
      // a deterministic same-seed recovery where the keys are unchanged.
      // Captured before the overwrite below.
      final identityKeyChanged = contact.ed25519Pk == null ||
          !constantTimeEquals(contact.ed25519Pk!,
              Uint8List.fromList(rb.newEd25519Pk));
      final prevVerification = contact.verificationLevel;

      // Update contact with new keys and node ID.
      // §8.3 (finding 11): the anchor is written BEFORE the contact map is
      // re-keyed. If the setter refuses, the record stays untouched under its
      // old key and the whole migration — including the RestoreResponse
      // phases that ship our contact list and message history to the
      // recovering peer — is skipped. Aborting after the `remove` would have
      // dropped the contact from the map entirely.
      if (!_setContactTrustAnchor(contact, newNodeIdHex,
          Uint8List.fromList(rb.newEd25519Pk),
          Uint8List.fromList(rb.newMlDsaPk),
          source: 'restore broadcast')) {
        _log.warn('§8.3: RESTORE_BROADCAST from ${oldNodeIdHex.substring(0, 8)} '
            '— anchor write REFUSED, migration aborted, contact unchanged');
        return;
      }
      _contacts.remove(oldNodeIdHex);
      contact.nodeId = Uint8List.fromList(rb.newNodeId);
      contact.x25519Pk = Uint8List.fromList(rb.newX25519Pk);
      contact.mlKemPk = Uint8List.fromList(rb.newMlKemPk);
      // §4.5.4/S363: observed NOW — otherwise the freshness rule
      // (`kemCopyFreshness`) keeps measuring against `acceptedAt` and
      // reports a just-recovered contact as stale.
      contact.kemRotationAt = DateTime.now();
      if (rb.displayName.isNotEmpty) contact.displayName = rb.displayName;
      // H-2 Part B (§8.3, SR-1-consistent): if the restore changed the
      // contact's identity key, run Key-Change-Detection — reset the
      // verification level so a re-identity / forge is never followed
      // silently at full trust. A deterministic same-seed recovery leaves
      // the key unchanged and keeps the verification level.
      if (identityKeyChanged) {
        contact.verificationLevel =
            onIdentityRotation(contact.verificationLevel).newLevel;
      }
      _contacts[newNodeIdHex] = contact;
      _saveContacts();

      // Update group/channel memberships
      for (final group in _groups.values) {
        final member = group.members.remove(oldNodeIdHex);
        if (member != null) {
          group.members[newNodeIdHex] = GroupMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: contact.displayName,
            role: member.role,
            ed25519Pk: contact.ed25519Pk,
            x25519Pk: contact.x25519Pk,
            mlKemPk: contact.mlKemPk,
          );
        }
        if (group.ownerNodeIdHex == oldNodeIdHex) {
          group.ownerNodeIdHex = newNodeIdHex;
        }
      }
      _saveGroups();

      for (final channel in _channels.values) {
        final member = channel.members.remove(oldNodeIdHex);
        if (member != null) {
          channel.members[newNodeIdHex] = ChannelMemberInfo(
            nodeIdHex: newNodeIdHex,
            displayName: contact.displayName,
            role: member.role,
            ed25519Pk: contact.ed25519Pk,
            x25519Pk: contact.x25519Pk,
            mlKemPk: contact.mlKemPk,
          );
        }
        if (channel.ownerNodeIdHex == oldNodeIdHex) {
          channel.ownerNodeIdHex = newNodeIdHex;
        }
      }
      _saveChannels();

      // Migrate conversation from old to new node ID
      final oldConv = conversations.remove(oldNodeIdHex);
      if (oldConv != null) {
        conversations[newNodeIdHex] = Conversation(
          id: newNodeIdHex,
          displayName: contact.displayName,
          messages: oldConv.messages,
          unreadCount: oldConv.unreadCount,
          lastActivity: oldConv.lastActivity,
          profilePictureBase64: oldConv.profilePictureBase64,
          config: oldConv.config,
          isFavorite: oldConv.isFavorite,
          notificationsEnabled: oldConv.notificationsEnabled,
          notificationSoundName: oldConv.notificationSoundName,
        );
        _saveConversations();
      }

      // Send RestoreResponse Phase 1: contact list
      _sendRestoreResponse(contact, 1);

      // Phase 2: recent messages (after short delay)
      Timer(const Duration(seconds: 2), () {
        _sendRestoreResponse(contact, 2);
      });

      // Phase 3: full history (after longer delay, in background)
      Timer(const Duration(seconds: 10), () {
        _sendRestoreResponse(contact, 3);
      });

      // H-2 Part B (§6.3.5): surface the restore to the UI. Fired for EVERY
      // accepted restore (the §6.3.5 "[Name] has set up a new device"
      // notification, now real). `identityKeyChanged` tells the UI whether
      // to escalate to a key-change warning (verification was reset above).
      _log.debug('RESTORE_BROADCAST displayName="${contact.displayName}"');
      _log.info('RESTORE_BROADCAST visibility: '
          'keyChanged=$identityKeyChanged verification '
          '$prevVerification→${contact.verificationLevel}');
      try {
        onContactRestoreDetected?.call(
            newNodeIdHex, contact.displayName, identityKeyChanged);
      } catch (e) {
        _log.warn('onContactRestoreDetected listener threw: $e');
      }

      onStateChanged?.call();
    } catch (e) {
      _log.error('RESTORE_BROADCAST processing failed: $e');
    }
  }


  /// Send RestoreResponse to a recovering contact.
  Future<void> _sendRestoreResponse(ContactInfo recipient, int phase) async {
    if (recipient.x25519Pk == null || recipient.mlKemPk == null) return;

    final response = proto.RestoreResponse()..phase = phase;

    if (phase == 1) {
      // Phase 1: Send our contact list (contacts the recovering node might want to re-add)
      for (final c in _contacts.values) {
        if (c.status != 'accepted') continue;
        final entry = proto.ContactEntry()
          ..nodeId = c.nodeId
          ..displayName = c.displayName;
        if (c.ed25519Pk != null) entry.ed25519Pk = c.ed25519Pk!;
        if (c.x25519Pk != null) entry.x25519Pk = c.x25519Pk!;
        if (c.mlKemPk != null) entry.mlKemPk = c.mlKemPk!;
        if (c.mlDsaPk != null) entry.mlDsaPk = c.mlDsaPk!;
        if (c.profilePictureBase64 != null) {
          entry.profilePicture = base64Decode(c.profilePictureBase64!);
        }
        response.contacts.add(entry);
      }

      // Also add ourselves as a contact entry
      final selfEntry = proto.ContactEntry()
        ..nodeId = identity.nodeId
        ..displayName = displayName
        ..ed25519Pk = identity.ed25519PublicKey
        ..x25519Pk = identity.x25519PublicKey
        ..mlKemPk = identity.mlKemPublicKey
        ..mlDsaPk = identity.mlDsaPublicKey;
      if (_profilePictureBase64 != null) {
        selfEntry.profilePicture = base64Decode(_profilePictureBase64!);
      }
      response.contacts.add(selfEntry);

      // Add group structures + member contacts
      for (final group in _groups.values) {
        if (!group.members.containsKey(recipient.nodeIdHex)) continue;

        // Add group structure
        final groupInfo = proto.RestoreGroupInfo()
          ..groupId = hexToBytes(group.groupIdHex)
          ..name = group.name
          ..ownerNodeIdHex = group.ownerNodeIdHex;
        if (group.description != null) groupInfo.description = group.description!;

        for (final member in group.members.values) {
          final gm = proto.RestoreGroupMember()
            ..nodeIdHex = member.nodeIdHex
            ..displayName = member.displayName
            ..role = member.role;
          if (member.ed25519Pk != null) gm.ed25519Pk = member.ed25519Pk!;
          if (member.x25519Pk != null) gm.x25519Pk = member.x25519Pk!;
          if (member.mlKemPk != null) gm.mlKemPk = member.mlKemPk!;
          groupInfo.members.add(gm);

          // Also add member as contact (dedup)
          if (!response.contacts.any((c) => c.nodeId.hex == member.nodeIdHex)) {
            final entry = proto.ContactEntry()
              ..nodeId = hexToBytes(member.nodeIdHex)
              ..displayName = member.displayName;
            if (member.ed25519Pk != null) entry.ed25519Pk = member.ed25519Pk!;
            if (member.x25519Pk != null) entry.x25519Pk = member.x25519Pk!;
            if (member.mlKemPk != null) entry.mlKemPk = member.mlKemPk!;
            response.contacts.add(entry);
          }
        }
        response.groups.add(groupInfo);
      }

      // Add channel structures + subscriber contacts
      for (final channel in _channels.values) {
        if (!channel.members.containsKey(recipient.nodeIdHex)) continue;

        final channelInfo = proto.RestoreChannelInfo()
          ..channelId = hexToBytes(channel.channelIdHex)
          ..name = channel.name
          ..ownerNodeIdHex = channel.ownerNodeIdHex
          // NSFW rating travels with the restore payload (proto field 6). Until
          // the field existed the recovering side could only fall back to the
          // ChannelInfo default, so an adult channel silently lost its flag.
          ..isAdult = channel.isAdult;
        if (channel.description != null) channelInfo.description = channel.description!;

        for (final member in channel.members.values) {
          final cm = proto.RestoreChannelMember()
            ..nodeIdHex = member.nodeIdHex
            ..displayName = member.displayName
            ..role = member.role;
          if (member.ed25519Pk != null) cm.ed25519Pk = member.ed25519Pk!;
          if (member.x25519Pk != null) cm.x25519Pk = member.x25519Pk!;
          if (member.mlKemPk != null) cm.mlKemPk = member.mlKemPk!;
          channelInfo.members.add(cm);

          if (!response.contacts.any((c) => c.nodeId.hex == member.nodeIdHex)) {
            final entry = proto.ContactEntry()
              ..nodeId = hexToBytes(member.nodeIdHex)
              ..displayName = member.displayName;
            if (member.ed25519Pk != null) entry.ed25519Pk = member.ed25519Pk!;
            if (member.x25519Pk != null) entry.x25519Pk = member.x25519Pk!;
            if (member.mlKemPk != null) entry.mlKemPk = member.mlKemPk!;
            response.contacts.add(entry);
          }
        }
        response.channels.add(channelInfo);
      }
    } else if (phase == 2 || phase == 3) {
      // Phase 2: Last 50 messages from our DM conversation
      // Phase 3: ALL messages from ALL conversations (full history)
      final convIds = phase == 3
          ? conversations.keys.toList()
          : [recipient.nodeIdHex];
      final maxMessages = phase == 3 ? null : 50;

      for (final convId in convIds) {
        final conv = conversations[convId];
        if (conv == null) continue;

        // The recovery answer carries the HISTORY — here loading everything
        // is the purpose, not an oversight (§13.5).
        ensureLoaded(convId);
        final msgs = (maxMessages != null && conv.messages.length > maxMessages)
            ? conv.messages.sublist(conv.messages.length - maxMessages)
            : conv.messages;

        for (final msg in msgs) {
          if (msg.isDeleted) continue;
          response.messages.add(proto.StoredMessage()
            ..messageId = hexToBytes(msg.id)
            ..senderId = hexToBytes(msg.senderNodeIdHex)
            ..recipientId = identity.nodeId
            ..conversationId = convId
            ..timestamp = Int64(msg.timestamp.millisecondsSinceEpoch)
            ..uiMessageType = msg.type.wireValue
            ..payload = utf8.encode(msg.text));
        }
      }
    }

    // V3 (Architecture §23.3 + §6.3): RESTORE_RESPONSE rides as an
    // ApplicationFrameV3 via sendToUser. The codec handles per-message KEM
    // (X25519 + ML-KEM-768) on the inner frame, so we hand it the raw
    // RestoreResponse protobuf as payload (no pre-encryption). Receiver-
    // side `_handleRestoreResponseV3` is wired by Cluster C4.
    //
    // Spec-note: RESTORE flow uses recipient.nodeId from the old contact
    // list and `recipient.x25519Pk`/`mlKemPk` are pre-rotation. sendToUser
    // resolves recipient → devices via 2D-DHT and uses the KEM pubkeys on
    // the contact record — best-effort. If the recipient already rotated,
    // the resolve may return new device-IDs whose decap-SK doesn't match
    // the contact-cached User-KEM-PK, and the receiver silently drops.
    // That matches §2.4.1 [10'] semantics; the broadcaster's retry on
    // RESTORE_BROADCAST will eventually reach a freshly-keyed device.
    final ok = await sendToUser(
      recipientUserId: recipient.nodeId,
      messageType: proto.MessageTypeV3.MTV3_RESTORE_RESPONSE,
      payload: Uint8List.fromList(response.writeToBuffer()),
    );

    _log.debug('RestoreResponse displayName="${recipient.displayName}"');
    _log.info('Sent RestoreResponse phase $phase '
        '(${phase == 1 ? '${response.contacts.length} contacts' : '${response.messages.length} messages'}) ok=$ok');
  }


  /// Handle incoming RESTORE_RESPONSE: restore contacts and messages.
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// RestoreResponse proto bytes (KEM-decap + inner User-Sig + outer
  /// Device-Sig already verified by the V3 receive pipeline).
  /// [senderUserId] is the recovering peer's user-id from the inbound
  /// ApplicationFrame.
  ///
  /// [senderDeviceId] is the device the answer came from — or `null` if
  /// the receive path knows none (V4.1 addresses identities,
  /// §14.1/§14.2). The parameter has EXACTLY ONE consumer in this method:
  /// the A-5 line further down, which enters it into
  /// `ContactInfo.deviceNodeIds` — i.e. into a routing target. It is
  /// therefore optional instead of filled with a substitute: if the device
  /// is missing, only this shortcut is dropped, the recovery itself does
  /// not hang on it.
  void _handleRestoreResponse(
      Uint8List payload, Uint8List senderUserId, Uint8List? senderDeviceId) {
    try {
      final response = proto.RestoreResponse.fromBuffer(payload);
      final senderHex = bytesToHex(senderUserId);
      var contactsRestored = 0;
      var messagesRestored = 0;

      if (response.phase == 1) {
        // Phase 1: Restore contacts
        for (final entry in response.contacts) {
          final nodeIdHex = entry.nodeId.hex;
          if (nodeIdHex == identity.userIdHex) continue; // Skip self
          if (_contacts.containsKey(nodeIdHex)) continue; // Already known
          if (_deletedContacts.contains(nodeIdHex)) continue; // Explicitly deleted

          _contacts[nodeIdHex] = ContactInfo(
            nodeId: Uint8List.fromList(entry.nodeId),
            displayName: entry.displayName,
            ed25519Pk: entry.ed25519Pk.isNotEmpty ? Uint8List.fromList(entry.ed25519Pk) : null,
            x25519Pk: entry.x25519Pk.isNotEmpty ? Uint8List.fromList(entry.x25519Pk) : null,
            mlKemPk: entry.mlKemPk.isNotEmpty ? Uint8List.fromList(entry.mlKemPk) : null,
            mlDsaPk: entry.mlDsaPk.isNotEmpty ? Uint8List.fromList(entry.mlDsaPk) : null,
            status: 'accepted',
            profilePictureBase64: entry.profilePicture.isNotEmpty
                ? base64Encode(entry.profilePicture)
                : null,
            acceptedAt: DateTime.now(),
          );
          contactsRestored++;
        }
        // §3.1 A-5: the A-2 central fix ran before this handler but
        // _contacts was still empty at that point. Now that contacts are
        // restored, record the sender's deviceNodeId.
        final senderContact = _contacts[senderHex];
        if (senderContact != null && senderDeviceId != null) {
          // No substitute value when the device is missing (§14.1):
          // `deviceNodeIds` is a routing target
          // (`cleona_service_v3_legacy.dart:149` sends to every entry).
          // Without a device the set stays empty and the send path goes via
          // the auth manifest.
          senderContact.deviceNodeIds.add(bytesToHex(senderDeviceId));
        }
        if (contactsRestored > 0) _saveContacts();

        // Restore groups
        var groupsRestored = 0;
        for (final gi in response.groups) {
          final groupIdHex = gi.groupId.hex;
          if (_groups.containsKey(groupIdHex)) continue;

          final members = <String, GroupMemberInfo>{};
          for (final gm in gi.members) {
            members[gm.nodeIdHex] = GroupMemberInfo(
              nodeIdHex: gm.nodeIdHex,
              displayName: gm.displayName,
              role: gm.role,
              ed25519Pk: gm.ed25519Pk.isNotEmpty ? Uint8List.fromList(gm.ed25519Pk) : null,
              x25519Pk: gm.x25519Pk.isNotEmpty ? Uint8List.fromList(gm.x25519Pk) : null,
              mlKemPk: gm.mlKemPk.isNotEmpty ? Uint8List.fromList(gm.mlKemPk) : null,
            );
          }

          _groups[groupIdHex] = GroupInfo(
            groupIdHex: groupIdHex,
            name: gi.name,
            description: gi.description.isNotEmpty ? gi.description : null,
            ownerNodeIdHex: gi.ownerNodeIdHex,
            members: members,
          );
          groupsRestored++;
        }
        if (groupsRestored > 0) _saveGroups();

        // Restore channels
        var channelsRestored = 0;
        for (final ci in response.channels) {
          final channelIdHex = ci.channelId.hex;
          if (_channels.containsKey(channelIdHex)) continue;

          final members = <String, ChannelMemberInfo>{};
          for (final cm in ci.members) {
            members[cm.nodeIdHex] = ChannelMemberInfo(
              nodeIdHex: cm.nodeIdHex,
              displayName: cm.displayName,
              role: cm.role,
              ed25519Pk: cm.ed25519Pk.isNotEmpty ? Uint8List.fromList(cm.ed25519Pk) : null,
              x25519Pk: cm.x25519Pk.isNotEmpty ? Uint8List.fromList(cm.x25519Pk) : null,
              mlKemPk: cm.mlKemPk.isNotEmpty ? Uint8List.fromList(cm.mlKemPk) : null,
            );
          }

          _channels[channelIdHex] = ChannelInfo(
            channelIdHex: channelIdHex,
            name: ci.name,
            description: ci.description.isNotEmpty ? ci.description : null,
            ownerNodeIdHex: ci.ownerNodeIdHex,
            members: members,
            // Carry the sender's NSFW rating instead of inheriting a default.
            // A sender still on the old build leaves field 6 unset and this
            // reads the protobuf default false — same as before the change.
            isAdult: ci.isAdult,
          );
          channelsRestored++;
        }
        if (channelsRestored > 0) _saveChannels();

        _log.info('Restore Phase 1: $contactsRestored contacts, $groupsRestored groups, $channelsRestored channels from ${senderHex.substring(0, 8)}');
      } else if (response.phase == 2) {
        // Phase 2: Restore recent messages
        for (final stored in response.messages) {
          final msgId = stored.messageId.hex;
          final convId = stored.conversationId;
          final senderIdHex = stored.senderId.hex;

          // Skip if already have this message
          final conv = conversations[convId];
          ensureLoaded(convId);
          if (conv != null && conv.messages.any((m) => m.id == msgId)) continue;

          final isOutgoing = senderIdHex == identity.userIdHex;
          final text = utf8.decode(stored.payload, allowMalformed: true);
          if (text.isEmpty) continue;

          final msg = UiMessage(
            id: msgId,
            conversationId: convId,
            senderNodeIdHex: senderIdHex,
            text: text,
            timestamp: DateTime.fromMillisecondsSinceEpoch(stored.timestamp.toInt()),
            type: UiMessageType.text,
            status: MessageStatus.delivered,
            isOutgoing: isOutgoing,
          );

          _addMessageToConversation(convId, msg);
          messagesRestored++;
        }
        if (messagesRestored > 0) _saveConversations();
        _log.info('Restore Phase 2: $messagesRestored messages from ${senderHex.substring(0, 8)}');
      }

      onRestoreProgress?.call(response.phase, contactsRestored, messagesRestored);
      onStateChanged?.call();
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('RESTORE_RESPONSE', e);
    } catch (e) {
      _log.error('RESTORE_RESPONSE processing failed: $e');
    }
  }


  // S368: here stood `handleIncomingRestoreBroadcastInfra` (§6.3 restore
  // broadcast via the InfrastructureFrame). ZERO callers in
  // `lib/`+`bin/`, on both branches. The header of this file has announced
  // the departure since the CUT ("the `*V3` entries and
  // `handleIncomingRestoreBroadcastInfra` die with the V3 reception").
  // `_handleRestoreBroadcast` — the domain logic that checks the old
  // Ed25519 against the stored contact key — STAYS.



  // C4 — Recovery / Identity / Profile / CR / Groups / Channels / DHT /
  //       Fragments / Peer-Store / Chat-Config / Routing / Hole-Punch /
  //       Identity-Resolution / Multi-Device / Calendar / Polls
  /// V4.1 §15.6: the broadcast IS the application path.
  ///
  /// ── THE RULE HAS REVERSED, NOT LOOSENED ────────────────
  ///
  /// Until S360 a discard stood here with the justification "V3.0 Welle 6:
  /// RESTORE_BROADCAST migrated to InfrastructureFrame (§2.3.5 selector
  /// + §6.3). An inbound ApplicationFrame with this messageType is a
  /// protocol violation — drop."
  ///
  /// In V4.1 the opposite applies, and literally. §15.6 has a table
  /// "Every operation that must reach a recipient rests on its own key
  /// relationship", and in it stands:
  ///
  ///     | Recovery (restore broadcast) | `tag(K_AB)` (§13) |
  ///
  /// §13.5 on this: "the entire remaining procedure is **ordinary
  /// traffic**. §15.6 already establishes this: the Restore Broadcast
  /// runs under the pairwise tag `tag(K_AB)` and needs no KEX-gate
  /// exception."
  ///
  /// There is also no other way any more in V4.1: the infrastructure frame
  /// has fallen with the cut. A discard here would mean that a correctly
  /// sent broadcast SILENTLY disappears at the receiver — exactly the error
  /// class that §14.4 rules out ("a visible failure instead of a silent
  /// loss").
  ///
  /// ── THE GATEKEEPER STAYS, IT JUST SITS ELSEWHERE ────────────────
  ///
  /// Nothing is accepted blindly. [_handleRestoreBroadcast] checks (a)
  /// whether `old_node_id` is an accepted contact, and (b) the H-2 hybrid
  /// signature against the keys STORED AT THE CONTACT, before anything is
  /// written (§13.5.4: "checked against the keys stored at the contact
  /// **before** data is released"). And the cell only reaches this place
  /// at all if the sender could form `K_AB` — the KEX gate protection is
  /// structural and lies in the mark derivation, not in a filter stage
  /// (§15.6, §13.5.4: "an attacker without `K_AB` cannot place a Restore
  /// Broadcast that a contact would even harvest").
  void _handleRestoreBroadcastV3(HarvestEvent event) {
    _log.info('RESTORE_BROADCAST (§15.6, tag(K_AB)) von '
        '${CleonaService._hexShort(event.senderDeviceId)}, '
        '${event.payload.length} B');
    _handleRestoreBroadcast(Uint8List.fromList(event.payload));
  }

  void _handleRestoreResponseV3(HarvestEvent event) {
    _handleRestoreResponse(
      Uint8List.fromList(event.payload),
      Uint8List.fromList(event.senderUserId),
      event.senderDeviceId,
    );
  }
}
