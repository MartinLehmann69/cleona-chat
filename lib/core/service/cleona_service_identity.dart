// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// Identity and device management in the service: the identity publisher,
// the trust anchor resolution, the pinning of foreign signing keys, the
// publisher's device list and the twin sync between own devices, plus
// the emergency key rotation.
//
// CLASS B: V4 explicitly continues multi-device, delegation certificates
// and key rotation (§7.5/§7.6.2, §3.5.4) — just not via 2D DHT and V3
// frames. AP-3 does NOT delete this file.
//
// Delimited against `identity_resolution/`: the 2D DHT machinery lives
// there (dropped). Here lives WHAT the service does with the results.

part of 'cleona_service.dart';

extension V3IdentityDeviceOps on CleonaService {


  // ── `_pinRecipientUserSigPks`: FALLEN (CUT, 31.08.2026) ──────────
  //
  // It pinned the self-certified user signing keys of a recipient to the
  // `pending_outgoing` contact, so that the delivery confirmation of the
  // first request is checkable at all. Its source was exclusively
  // `node.identityResolver` — cache and, if empty, a 2D DHT lookup.
  //
  // Both are §4.3, and §4.3 is REPLACED in V4.1, not renumbered
  // (paragraph bridge in CLAUDE.md). Its only caller was the first-contact
  // branch in the `sendContactRequest` of that time. (T)
  //
  // UNTIL S361 THIS SAID "which today ends at gap G-1". That branch had no
  // longer ended there since S360 — it delivered via the invitation line
  // (§15.3.2).
  //
  // S389: `sendContactRequest` has not existed since S388-BAU-KONTAKT.
  // That does not change the (T) either, it only makes it final: on V4.2
  // the request comes from an invitation card that itself carries the
  // counterpart's key bundle (§15.2, §15.5) — a lookup has no business
  // there any more.

  /// Drop TWIN_SYNC dedup entries older than 7 days (§26 Dedup TTL).
  void _pruneSyncDedup() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - CleonaService._syncDedupTtlMs;
    _processedSyncIds.removeWhere((_, ts) => ts < cutoff);
  }


  /// §7 (introduction): hand the approved device set to the publisher —
  /// WITHOUT SUBJECT since the CUT.
  ///
  /// The `IdentityPublisher` is gone (gap G-9, justification at the field
  /// `_identityPublisher` in `cleona_service.dart`). With it there is no
  /// longer an AuthManifest in which the device list would stand.
  ///
  /// THE BODY STAYS AS A NAMED REFUSAL, not as a deleted call: it has five
  /// call sites, and each of them marks a moment at which the device set
  /// changed. Whoever closes G-9 finds them all here again.
  void _syncAuthorizedDevicesToPublisher() {
    _log.debug('§7: device set (${_buildAuthorizedDeviceNodeIds().length}) '
        'not published — V4.1 has no AuthManifest (gap G-9).');
  }


  /// §7 (Einleitung): the authorised device-node-id set derived from
  /// `_devices` plus this device.
  ///
  /// Extracted from [_syncAuthorizedDevicesToPublisher] because §7.5 needs the
  /// list WITHOUT publishing it: `computeDeviceSetChangeHash` has to run over
  /// exactly the ids the manifest will carry, and it concatenates them without
  /// de-duplicating — so this must normalise the same way
  /// `IdentityPublisher.setAuthorizedDevices` does (own id first, collapsed by
  /// hex, malformed entries skipped). A list that differs by one duplicate
  /// produces a different hash, i.e. a proof the receiver reads as invalid.
  List<Uint8List> _buildAuthorizedDeviceNodeIds() {
    final byHex = <String, Uint8List>{
      bytesToHex(identity.deviceNodeId): identity.deviceNodeId,
    };
    for (final d in _devices.values) {
      final hex = d.deviceNodeIdHex;
      if (hex == null || hex.isEmpty) continue;
      try {
        byHex[hex] = hexToBytes(hex);
      } catch (e) {
        _log.warn('Skipping device ${d.deviceId} in authorized-device set: '
            'malformed deviceNodeIdHex ($e)');
      }
    }
    return byHex.values.toList();
  }


  /// §7.4: withdraw delegation and signing keys of a revoked device —
  /// WITHOUT SUBJECT since the CUT (gap G-9).
  ///
  /// They were held in the `IdentityPublisher`; without it there is nothing
  /// to withdraw. Important for whoever closes G-9: the revocation must hit
  /// BOTH sets (delegation AND signing keys) and try both candidate
  /// identifiers (`_devices` is indexed sometimes by node identifier,
  /// sometimes by UUID).
  void _retractDeviceFromPublisher(DeviceRecord? device, String deviceIdKey) {
    _log.warn('§7.4: revocation of $deviceIdKey acts only locally — the '
        'delegation and the device signature keys have no holder in V4.1 '
        'from which they could be withdrawn (gap G-9).');
  }


  void _handleTwinContactDeleted(List<int> payload) {
    try {
      final nodeIdHex = utf8.decode(payload);
      if (_contacts.containsKey(nodeIdHex)) {
        final name = _contacts[nodeIdHex]!.displayName;
        // §14.7: the deletion on the other own device took the conversation
        // with it (`deleteContact`); this device follows. Until S401 the
        // contact went here and its conversation stayed, shown and stored.
        _conversationLeavesProfile(nodeIdHex, openSendsStop: true);
        _contacts.remove(nodeIdHex);
        _deletedContacts.add(nodeIdHex);
        _saveContacts();
        _log.info('Twin-synced contact deleted: $name');
        onStateChanged?.call();
      }
    } catch (e) {
      _log.warn('Twin CONTACT_DELETED failed: $e');
    }
  }


  void _handleTwinGroupCreated(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final groupInfo = GroupInfo.fromJson(json);
      // The state of the device that created or joined is taken where this
      // device holds none, holds only the invitation, or holds an epoch that
      // is not newer. A newer state here came over the group's own protocol
      // (§16) and stays; the group pairs are taken in every case.
      final known = _groups[groupInfo.groupIdHex];
      if (known != null &&
          (!groupInfo.joined ||
              (known.joined &&
                  known.membershipEpoch > groupInfo.membershipEpoch))) {
        _ownLineGroupPairsTake(json, known);
        return;
      }
      // §16.2.2: a group THIS device left comes back only with a state
      // newer than the one it left with (`_groupMayBeHeld`) — the state of
      // another own device from before the leaving does not lift the mark.
      if (known == null &&
          !_groupMayBeHeld(groupInfo.groupIdHex,
              epoch: groupInfo.membershipEpoch,
              namesMe: groupInfo.members.containsKey(identity.userIdHex))) {
        return;
      }
      _groups[groupInfo.groupIdHex] = groupInfo;
      _saveGroups();
      _ownLineGroupPairsTake(json, groupInfo);
      final conv = conversations.putIfAbsent(
          groupInfo.groupIdHex,
          () => Conversation(
                id: groupInfo.groupIdHex,
                displayName: groupInfo.name,
                isGroup: true,
                profilePictureBase64: groupInfo.pictureBase64,
                notificationsEnabled:
                    notificationSound.settings.defaultGroupNotify,
              ));
      conv.displayName = groupInfo.name;
      _saveConversations();
      // What waited here for the invitation into this group (§16.2.2).
      if (known == null) _groupWaitingApply(groupInfo.groupIdHex);
      _log.info('Twin-synced group created: ${groupInfo.name}');
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin GROUP_CREATED failed: $e');
    }
  }

  /// Type 21 GROUP_LEFT (§14.7, S403 owner decision 03.10.2026 V1 = A):
  /// another own device left the group — or the channel — that [payload]
  /// names, so the identity left. This device removes the conversation and
  /// sets the same mark; a post the leaving device discarded is not
  /// forwarded here, so the group must not stay held either. A state this
  /// device already holds that is NEWER (the identity was re-invited and
  /// this device took the invitation) wins: that leaving is old news.
  void _handleTwinGroupLeft(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final gid = json['group'] as String;
      final epoch = (json['epoch'] as num).toInt();
      final group = _groups[gid];
      final channel = _channels[gid];
      // §16.2.2: "Recipients discard updates with an epoch ≤ their local
      // state" — here the other way round: a held membership newer than
      // the one at the leaving is a new invitation this device already
      // took, and the leaving of the other own device does not undo it.
      if (group != null && group.membershipEpoch > epoch) return;
      if (channel != null && channel.membershipEpoch > epoch) return;
      if (group != null) {
        // Like the leaving device itself (`leaveGroup`): the conversation
        // goes with the membership, the pairs with the group (B-3).
        _conversationLeavesProfile(gid, openSendsStop: false);
        myceliumMailbox?.groupPairLeave(hexToBytes(gid));
        _groups.remove(gid);
        _saveGroups();
      } else if (channel != null) {
        _conversationLeavesProfile(gid, openSendsStop: false);
        _channels.remove(gid);
        _saveChannels();
      }
      // §16.2.2: the same mark as on the leaving device — posts of the
      // group are discarded from now on, a new invitation lifts it. This
      // device held neither group nor channel: the mark is all that
      // changes.
      _groupMarkLeft(gid, epoch);
      _saveConversations();
      _log.info('Twin-synced group left: ${gid.substring(0, 8)} '
          'at epoch $epoch (§14.7 Type 21)');
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin GROUP_LEFT failed: $e');
    }
  }


  void _handleTwinProfileChanged(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (json.containsKey('displayName')) {
        displayName = json['displayName'] as String;
        _persistDisplayName(displayName);
      }
      if (json.containsKey('profilePicture')) {
        _profilePictureBase64 = json['profilePicture'] as String?;
        _saveProfilePicture();
      }
      if (json.containsKey('profileDescription')) {
        _profileDescription = json['profileDescription'] as String?;
        _saveProfileDescription();
      }
      onStateChanged?.call();
      _log.info('Twin-synced profile change');
    } catch (e) {
      _log.warn('Twin PROFILE_CHANGED failed: $e');
    }
  }


  void _handleTwinDeviceRenamed(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final deviceId = json['deviceId'] as String;
      final newName = json['deviceName'] as String;
      if (_devices.containsKey(deviceId)) {
        _devices[deviceId]!.deviceName = newName;
        _saveDevices();
        _log.info('Twin device renamed: $deviceId → $newName');
        _notifyDevicesChanged();
      }
    } catch (e) {
      _log.warn('Twin DEVICE_RENAMED failed: $e');
    }
  }


  /// Handle KEY_ROTATION_BROADCAST from a contact.
  /// Dispatches between periodic KEM rotation (legacy KeyRotation format)
  /// and emergency full rotation (KeyRotationBroadcast with dual-signature).
  /// KEY_ROTATION_BROADCAST handler (§7.4). [payload] is the already-
  /// decrypted+authenticated `KeyRotationBroadcast` proto bytes (V3 inner
  /// User-Sig + outer Device-Sig + KEM-decap chain verified upstream;
  /// for the Emergency variant on InfraFrame the inner dual-sig in the
  /// body is the canonical authenticator). [senderUserId] is the
  /// rotating peer's user-id (frame.senderUserId on AppFrame, or the
  /// inferred old-userId via `_findSenderUserIdForKeyRotation` on
  /// InfraFrame).
  ///
  /// Discriminator (defence in depth — wire-path bridges already enforce
  /// it upstream): dual-sig populated → Emergency, single-sig → Periodic.
  /// Test access to EXACTLY the production path — no second mechanism.
  /// The guard needs it, because the way there would otherwise run via a
  /// complete V4.1 frame including MAC, and thus the statement
  /// ("an applied rotation reports itself to the UI") would hang on a rig
  /// instead of on the code.
  @visibleForTesting
  void testHandleKeyRotationBroadcast(
          Uint8List payload, Uint8List senderUserId) =>
      _handleKeyRotationBroadcast(payload, senderUserId);

  void _handleKeyRotationBroadcast(Uint8List payload, Uint8List senderUserId) {
    final senderHex = bytesToHex(senderUserId);
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final broadcast = proto.KeyRotationBroadcast.fromBuffer(payload);
      // §4.5.4 "The announcement must carry the mode". Both notices carry
      // it under field 9 (`KeyRotationMode`), so it is read here for both.
      // A notice without a mode, or with one this build does not know, is
      // rejected — there is no default and no older peer to serve (4.2.1
      // is not compatible with 4.2.0). The only mode today is TAGS_VALID:
      // nothing to re-derive, the pair's codes stay as they are.
      if (broadcast.mode != proto.KeyRotationMode.KEY_ROTATION_MODE_TAGS_VALID) {
        _log.warn('KEY_ROTATION_BROADCAST from ${senderHex.substring(0, 8)} '
            'REJECTED: mode ${broadcast.mode.name} — the notice does not '
            'say whether the tags stay valid (§4.5.4). Keys unchanged.');
        return;
      }
      if (CleonaService.isEmergencyKeyRotationBody(broadcast)) {
        _handleEmergencyKeyRotation(senderUserId, contact, senderHex, broadcast);
      } else {
        // Periodic KEM rotation — delegate to legacy handler. Re-serialize
        // the parsed body so the periodic handler parses a clean
        // KeyRotation proto (the body is wire-compatible since the dual-
        // sig fields are absent).
        _handleKeyRotation(payload, senderUserId);
      }
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('KEY_ROTATION_BROADCAST', e);
    } catch (e) {
      _log.error('KEY_ROTATION_BROADCAST processing failed: $e');
    }
  }


  // S368: here stood `handleIncomingKeyRotationBroadcastInfra` (§7.4
  // emergency rotation via the InfrastructureFrame). ZERO callers in
  // `lib/`+`bin/`, on both branches.
  //
  // WHAT DOES NOT FALL WITH IT, and that is the point: key change during
  // operation is explicitly NOT compatibility and stays complete. It runs
  // via `_handleKeyRotationBroadcast` (above in this file), which
  // distinguishes the emergency from the routine rotation by the presence
  // or absence of the two signature fields and serves both paths. What
  // has fallen is solely the V3 FRAME in which it once travelled — not the
  // rotation.



  /// D1 (§4.3): trust-anchor lookup and self-healing at the resolver —
  /// FALLEN (CUT, 31.08.2026).
  ///
  /// The body attached two chained callbacks to `node.identityResolver`:
  /// `contactEd25519PkLookup` (the resolver asks the service for the stored
  /// key of a contact) and `onContactKeyMismatch` (D1 self-healing: if the
  /// stored key deviates from the bound AuthManifest, it is replaced).
  ///
  /// Both callbacks PRESUPPOSE THE RESOLVER and have no subject without it
  /// — there is nobody left who could ask. §4.3 is replaced in V4.1, not
  /// renumbered. (T)
  ///
  /// What GOES AWAY in the process and deserves to be named: D1
  /// self-healing was the way in which a stale contact key was
  /// automatically swapped for the certified one. Without a certifying
  /// instance this reconciliation no longer exists; a key change reaches
  /// the contact only via the KEY_ROTATION broadcast (and its emergency
  /// variant stands at gap G-3).
  void _wireTrustAnchorLookup() {}

  /// §2.2.4: construction of the identity publisher — FALLEN (CUT, 31.08.2026).
  ///
  /// The body built the `IdentityPublisher` (AuthManifest +
  /// LivenessRecord + DeviceKemRecord into the 2D DHT), fed it with the
  /// node's device KEM and device signing keys, attached the §7.5 proof
  /// supplier and registered with the routing table, in order to wake a
  /// parked cold-start attempt on new peers.
  ///
  /// Four preconditions, all gone: the publisher itself
  /// (`lib/core/identity_resolution/`), the routing table, the DHT RPC and
  /// the device key. **Gap G-9** for the part that was not DHT
  /// (delegations and device signing keys); the rest is (T), because §4.3
  /// is replaced.
  ///
  /// ONE LINE IN IT WAS NOT DHT and has fallen along: the callback
  /// `onPeerAdded` triggered `_retryPendingContactRequests()` when a new
  /// peer appeared. This resubmission fell with
  /// `cleona_service_v3_retry.dart`.
  ///
  /// UNTIL S361 THIS SAID "first contact itself hangs on gap G-1 anyway".
  /// That has not held since S360: first contact goes out (§15.3.2). The
  /// RESUBMISSION of a still unanswered request, however, is gone without
  /// replacement, and that is measured (S361): `_lastCrRetryPerContact` and
  /// `_crRetryCountPerContact` get a value entered at NO place in `lib/`
  /// any more (measured: no `[key] = …` assignment in the whole tree) —
  /// they are only CLEARED, by [shortenCrBackoffOnEdge]
  /// (`cleona_service_pure.dart:118`, `.remove`), by `_pruneSyncDedup`
  /// neighbours (`cleona_service_msgstate.dart:546`, `.removeWhere`) and
  /// on acceptance (`cleona_service_contact_request.dart:99`, `.remove`).
  /// Both maps are thus permanently empty, and `shortenCrBackoffOnEdge`'s
  /// own condition `if (!_lastCrRetryPerContact.containsKey(entry.key))
  /// continue;` (`cleona_service_pure.dart:125`) therefore ALWAYS applies
  /// — the method never shortens anything, because there is nothing to
  /// shorten. There is no reader that triggers a renewed request from
  /// them. The §5.1 CR edge is thus dead code, not just a waiting time
  /// nobody waits for. Listed in the gap book as a separate item
  /// (`docs/v4-redesign/S361-lueckenbuch.md`).
  void _initIdentityPublisher() {}
}
