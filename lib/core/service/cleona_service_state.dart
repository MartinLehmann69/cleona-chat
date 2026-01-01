// AP-1c step 3 (docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4c.6) — CLASS B.
//
// State information of the service to the outside: the snapshot for IPC
// and GUI, the discard counter and the question whether a peer is known
// for a UserID.
//
// CLASS B: V4 still needs this information — and more strongly, because
// §4.7 explicitly requires the readiness state `cold`/`planting`/`ready`
// to be visible "in logs, IPC and UI" and AP-5 starts exactly here. The
// content of the snapshot changes completely, the task does not.

part of 'cleona_service.dart';

extension V3StateSnapshotOps on CleonaService {


  /// Get full state snapshot for IPC.
  Map<String, dynamic> getStateSnapshot() {
    // Sync profile pictures from contacts into conversations
    for (final conv in conversations.values) {
      if (!conv.isGroup && !conv.isChannel) {
        final contact = _contacts[conv.id];
        if (contact?.profilePictureBase64 != null) {
          conv.profilePictureBase64 = contact!.profilePictureBase64;
        }
      }
      // §21.6/S392-B3: the archive state is stamped HERE, not saved — the
      // leading stock is the archive index. Without this line the UI sees
      // a message whose file the archive has taken off the device as "not
      // yet downloaded". Costs one map entry access per message and drops
      // out completely without an archive (`_archiveManager == null`).
      _archiveManager?.applyArchiveView(conv.messages);
    }
    return {
      'nodeIdHex': nodeIdHex,
      // C1: exposed to the GUI so IpcClient can satisfy ICleonaService's
      // `profileDir` getter for identity-scoped GUI-side bridges (e.g.
      // AndroidCalendarBridge) that must not fall back to the process-log.
      'profileDir': profileDir,
      'displayName': displayName,
      'port': port,
      'publicIp': publicIp,
      'publicPort': publicPort,
      'localIps': localIps,
      // §22.7/§28.7: readiness stands BEFORE the counters, because it is
      // the only quantity that speaks about deliverability. The three
      // counters below are display quantities (§22.7.3).
      'readiness': readinessState,
      // §25.4/§28.7 rule 3: the partner counts SEPARATED by direction.
      // Combined they answer neither of the two questions that §25.4 asks
      // of them — "does my own delivery hold" and "what do I contribute
      // for others".
      'syncPartnersOutbound': syncPartnersOutbound,
      'syncPartnersInbound': syncPartnersInbound,
      'independentSyncPartners': independentSyncPartners,
      // §9.2: the MEASURED responsibility set. It must cross the IPC
      // boundary, because the consent dialog from §9.3 is in the GUI and
      // the delivery layer in the daemon — without this field the display
      // on daemon platforms would compute with the nominal size and be off
      // by a factor of 6.7 in the lab.
      'reachableResponsibleRelays': reachableResponsibleRelays,
      // §24.4.2/§25.4: the data saver mode is a metric of the readiness
      // section and must cross the IPC boundary — otherwise the GUI on
      // daemon platforms would show a state that the daemon keeps and that
      // it never sees. BOTH fields: the effective state AND the reason for
      // the lock. Without the second the UI cannot distinguish "off" from
      // "locked", and §24.4.2 explicitly requires that the lock appears
      // "with its reason named".
      'dataSaverActive': dataSaverActive,
      'dataSaverLockedBySecure': dataSaverLockedBySecure,
      'peerCount': peerCount,
      'confirmedPeerCount': confirmedPeerCount,
      'reachablePeerCount': reachablePeerCount,
      'hasPortMapping': hasPortMapping,
      // AP-5a: the GUI-side `IpcClient` satisfies these two sync getters from
      // the snapshot. Before, it returned `null` resp. recomputed
      // `confirmedPeerCount > 0` locally — a live comparison is not the same
      // predicate as the daemon's monotonic latch (cleona_node.dart:577).
      'hasSessionConfirmedPeers': hasSessionConfirmedPeers,
      'nodeStartedAtMs': nodeStartedAt?.millisecondsSinceEpoch,
      // `mobileFallbackActive` came from `node.transport` (the mobile
      // substitute socket when Wi-Fi is dead). V4.1 keeps its sockets in
      // `lib/core/link_io/` and does not know this state — `false` here
      // means "this concept no longer exists" (gap G-6, together with the
      // multi-interface mode).
      'mobileFallbackActive': false,
      'fragmentCount': fragmentCount,
      'isRunning': isRunning,
      'isLinkedDevice': isLinkedDevice,
      'linkedDeviceStatus': linkedDeviceStatus.toJson(),
      'profilePicture': _profilePictureBase64,
      'profileDescription': _profileDescription,
      'isGuardianSetUp': isGuardianSetUp,
      // AP-5a: `pendingJuryRequests` is a SYNCHRONOUS interface getter, so the
      // client cannot await the existing `get_jury_requests` verb inside it.
      // It rides the snapshot that `_scheduleRefresh()` already fetches on
      // every `state_changed` — no extra round trip (Arbeitsregel 5). The verb
      // stays as the async accessor the TS-E2E client uses.
      'pendingJuryRequests':
          pendingJuryRequests.map((r) => r.toJson()).toList(),
      'groups': _groups.map((k, v) => MapEntry(k, v.toJson())),
      'channels': _channels.map((k, v) => MapEntry(k, v.toJson())),
      'conversations': conversations.map((k, v) => MapEntry(k, v.toJson())),
      'acceptedContacts': acceptedContacts.map((c) => c.toJson()).toList(),
      'pendingContacts': pendingContacts.map((c) => c.toJson()).toList(),
      'pendingOutgoingContacts': pendingOutgoingContacts.map((c) => c.toJson()).toList(),
      'storedForDeliveryContacts':
          storedForDeliveryContacts.map((c) => c.toJson()).toList(),
      'currentCall': currentCall?.toJson(),
      'isMuted': isMuted,
      'isSpeakerEnabled': isSpeakerEnabled,
      'peerSummaries': peerSummaries.map((p) => p.toJson()).toList(),
      // §11/G-11: the start-peer candidates from the entry pool. The NODE
      // holds them, the GUI's ContactSeed builder needs them — and between
      // the two lies the IPC trench under Linux/Windows/macOS. Without this
      // line a code from the GUI carries no `s=`, while the same code from
      // the daemon carries one.
      'entrySeedCandidates': [
        for (final k in entrySeedCandidates)
          {'n': k.nodeIdHex, 'a': k.addresses, 'x': k.expiryMs},
      ],
      'typingContacts': _typingTimestamps.entries
          .where((e) => DateTime.now().difference(e.value).inSeconds < 5)
          .map((e) => e.key)
          .toList(),
      'mediaSettings': _mediaSettings.toJson(),
      'multiInterfaceMode': MultiInterfaceMode.modeToString(_multiInterfaceMode),
      'notificationSettings': notificationSound.settings.toJson(),
      'devices': _devices.values.map((d) => d.toJson()).toList(),
      'localDeviceId': _localDeviceId,
      // §24.4.3 — the transition state of running device lock-outs.
      //
      // In the SNAPSHOT and explicitly NOT in the `state_changed` event
      // (ipc_server.dart:178). Two reasons, both measured on what travels
      // here: the set grows with the contact count (one entry per lock, and
      // `total` is the number of contacts over which the announcement
      // went), and the transition lasts up to 14 days (§14.4). Hanging a
      // field that hardly moves over days into an event that fires on every
      // state change would be exactly the traffic that working rule 5
      // forbids. The client fetches the snapshot at every `state_changed`
      // anyway (`_scheduleRefresh`), so the display is at most one second
      // old — for a 14-day process.
      'deviceLockouts': deviceLockoutStates(),
      'deviceNodeIdHex': deviceNodeIdHex,
      // Identity-derivation fingerprint of the DAEMON build. The GUI compares
      // it against its own and refuses to present a ContactSeed it cannot
      // vouch for (see HdWallet.identityDerivationFingerprint). Absent field
      // == daemon older than this change; the GUI treats that as "unknown".
      'identityDerivationFp': HdWallet.identityDerivationFingerprint,
      'deviceX25519PkB64': base64Encode(deviceX25519Pk),
      'deviceMlKemPkB64': base64Encode(deviceMlKemPk),
      'userEd25519PkB64': base64Encode(userEd25519Pk),
      // SR-2: founding anchor (== userEd25519Pk for never-rotated identities).
      'foundingEd25519PkB64': base64Encode(foundingEd25519Pk),
      if (_latestManifest != null &&
          UpdateChecker().isNewer(_latestManifest!.version, CleonaService.kCurrentAppVersion))
        'updateManifest': _latestManifest!.toJson(),
      if (_binaryUpdateManager != null) ...{
        'updateState': _binaryUpdateManager!.state.index,
        'updateProgress': _binaryUpdateManager!.progress,
        'updateTargetVersion': _binaryUpdateManager!.targetVersion,
      },
    };
  }


  /// Discarded packets of the rate limiting — WITHOUT SUBJECT.
  ///
  /// The limiter sat in the V3 wire layer (`node.rateLimiter`). V4.1 limits
  /// differently: the cover stream has a fixed cadence, there is no counter
  /// "discarded because of rate". `0` is the truth here, not a missing
  /// value — nothing is discarded because of overload.
  int get droppedPackets => 0;


  /// Does this node know a way to [userId]?
  ///
  /// FORMERLY: is there a `PeerInfo` with this UserID in the routing table.
  /// V4.1 has no routing table by UserID; what it has is the PAIR KEY —
  /// and that exists exactly when a contact record with founding key is
  /// present. That is the next true statement on the same question ("can I
  /// reach this user?") and not a substitute quantity from a neighbouring
  /// column: without a pair key nothing goes out on the tagline (§15.2).
  bool isPeerKnownByUserId(Uint8List userId) {
    final c = _contacts[bytesToHex(userId)];
    return c != null && c.ed25519Pk != null && c.ed25519Pk!.isNotEmpty;
  }
}
