// The answer to a contact request (CONTACT_REQUEST_RESPONSE).
//
// ── WHAT NO LONGER STANDS HERE (S388-BAU-KONTAKT) ──────────────────────
//
// `_handleContactRequestV3` has been removed, together with the rate brake
// `_isCrRateLimited` and the three V3 special paths in it: "Same-Seed-
// Reinstall" (answered every request of an `accepted` contact with
// identical keys again — the duplicate CONTACT_REQUEST_RESPONSE,
// S388-BAU-NAHT B-1), "CR AUTO-ACCEPT (previously deleted)" (SILENTLY
// accepted a request after deletion and undermined the rejection) and
// "bidirectional" (silently accepted mutual requests, against §15.5 "No
// special path for simultaneous mutual requests").
//
// On V4.2 the request is package (2) of first contact in mycelium (§15.5);
// the app learns of it via `takeMyceliumContactRequest`
// (`cleona_service_mycelium.dart`) and decides there. The app message
// CONTACT_REQUEST no longer has a sender.

part of 'cleona_service.dart';

extension V3ContactRequestOps on CleonaService {
  void _handleContactRequestResponseV3(HarvestEvent event) {
    // No device identifier comes along via mycelium (§14.1/§14.2). Resolved
    // once above.
    final senderDevice = event.senderDeviceId;
    final senderDeviceHex =
        senderDevice == null ? null : bytesToHex(senderDevice);
    try {
      final resp = proto.ContactRequestResponse.fromBuffer(event.payload);
      final senderHex = event.senderUserId.hex;

      // Multi-Identity guard: the seam already enforces the recipient check
      // at every entry point, so a weaker duplicate here could never fire.
      // Removed in AP-1.
      //
      // Until S388 this said "Previously deleted contact responds: allow
      // re-contact" — the answer of a deleted contact lifted the deletion
      // mark. §15.9 lifts it only with the ACCEPTANCE of a new request; an
      // answer without a pending join is discarded below anyway.

      if (resp.accepted) {
        // Validate: we must have a pending outgoing request to this sender.
        // Without this check, a response from a wrong identity would create
        // a ghost contact. `pending` counts too if THIS node has at the same
        // time joined the other side (§15.5, mutual requests): its request
        // then stands as a question, the own join runs nonetheless.
        final existing = _contacts[senderHex];
        final expected = existing != null &&
            (existing.status == 'pending_outgoing' ||
                existing.status == 'accepted' ||
                existing.status == 'storedForDelivery' ||
                (existing.status == 'pending' &&
                    _myceliumJoinRunsTo(existing)));
        if (!expected) {
          _log.warn('CR-Response from ${senderHex.substring(0, 8)} but no pending CR — ignoring');
          return;
        }

        // Dedup on status transition: if the contact was already 'accepted',
        // this is a sender-side retry or the mycelium answer (3) came first
        // (`_myceliumJoinAccepted`). Don't flood the chat with duplicate
        // "accepted your CR" system messages or re-fire onContactAccepted —
        // just refresh name, picture and keys.
        final wasAlreadyAccepted = existing.status == 'accepted';


        // RC-1 (§8.1+§8.3): snapshot old key before overwrite
        final oldEd25519 = existing.ed25519Pk;

        // §8.3 (finding 11): the trust anchor is written BEFORE any mutation.
        // Both branches below (already-accepted / first-accept) write the
        // very same anchor out of `resp`, so one guard covers both. If the
        // setter refuses (own hosted key -> quarantine, or an incomplete
        // hybrid pair) the frame is dropped while status, seed bundle, KEM
        // keys and displayName are still untouched.
        if (!_setContactTrustAnchor(
            existing,
            senderHex,
            Uint8List.fromList(resp.ed25519PublicKey),
            Uint8List.fromList(resp.mlDsaPublicKey),
            source: wasAlreadyAccepted
                ? 'CRR/already-accepted'
                : 'CRR/first-accept')) {
          _log.warn('§8.3: CR-Response from ${senderHex.substring(0, 8)} — '
              'anchor write REFUSED, frame dropped, contact left unchanged');
          return;
        }

        final picBase64 = resp.profilePicture.isNotEmpty
            ? base64Encode(resp.profilePicture)
            : null;
        existing.status = 'accepted';
        existing.acceptedAt ??= DateTime.now();
        existing.lastAckedAt = DateTime.now();
        _crRetryCountPerContact.remove(senderHex);
        _staleWarningWrittenFor.remove(senderHex);
        // First-CR ContactSeed bootstrap is over once we have the recipient's
        // User-KEM pubkeys (filled below). Clear the seed bundle so re-contact
        // uses the User-KEM pair directly and stale Device-KEM pubkeys don't
        // outlive their TTL on disk.
        existing.seedDeviceIdHex = null;
        existing.seedDxkB64 = null;
        existing.seedDmkB64 = null;
        existing.seedEpB64 = null;

        // RC-1 (§8.1+§8.3): if already accepted AND keys changed, fire §8.3
        if (wasAlreadyAccepted) {
          final incomingEd25519 = Uint8List.fromList(resp.ed25519PublicKey);
          final identityKeyChanged = oldEd25519 == null || oldEd25519.isEmpty ||
              !constantTimeEquals(oldEd25519, incomingEd25519);

          // §8.3: the anchor (ed25519Pk + mlDsaPk) was already written by the
          // central setter above — only the KEM keys, which are not part of
          // the trust anchor, are set here.
          existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
          existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
          existing.displayName = resp.displayName;
          if (picBase64 != null) existing.profilePictureBase64 = picBase64;
          // No substitute value when the device is missing (§14.1) — the
          // list is a routing target.
          if (senderDeviceHex != null) {
            existing.deviceNodeIds.add(senderDeviceHex);
          }

          final conv = conversations[senderHex];
          if (conv != null && resp.displayName.isNotEmpty) {
            conv.displayName = resp.displayName;
            if (picBase64 != null) conv.profilePictureBase64 = picBase64;
          }

          if (identityKeyChanged) {
            final prevLevel = existing.verificationLevel;
            final keyChange = onIdentityRotation(prevLevel);
            existing.verificationLevel = keyChange.newLevel;
            _saveContacts();
            _saveConversations();
            _log.info('RC-1: CRR retry from ${senderHex.substring(0, 8)} with CHANGED keys — '
                '§8.3 reset $prevLevel→${keyChange.newLevel}');
            try {
              onContactIdentityRotated?.call(senderHex, existing.displayName, keyChange.wasVerified);
            } catch (e) {
              _log.warn('onContactIdentityRotated listener threw: $e');
            }
            onStateChanged?.call();
            return;
          }

          _saveContacts();
          _saveConversations();
          _log.debug('CR-Response retry from ${senderHex.substring(0, 8)} — keys refreshed, no system msg');
          onStateChanged?.call();
          return;
        }

        // First acceptance path
        // §8.3: the anchor (ed25519Pk + mlDsaPk) was already written by the
        // central setter above — only the KEM keys are set here.
        existing.x25519Pk = Uint8List.fromList(resp.x25519PublicKey);
        existing.mlKemPk = Uint8List.fromList(resp.mlKemPublicKey);
        existing.displayName = resp.displayName;
        if (picBase64 != null) existing.profilePictureBase64 = picBase64;
        // No substitute value when the device is missing (§14.1) — the list
        // is a routing target.
        if (senderDeviceHex != null) {
          existing.deviceNodeIds.add(senderDeviceHex);
        }

        // RC-1: first CRR acceptance — check if keys differ from pending_outgoing entry
        final identityKeyChanged = oldEd25519 != null && oldEd25519.isNotEmpty &&
            !constantTimeEquals(oldEd25519, Uint8List.fromList(resp.ed25519PublicKey));
        if (identityKeyChanged) {
          final keyChange = onIdentityRotation(existing.verificationLevel);
          existing.verificationLevel = keyChange.newLevel;
          _log.info('RC-1: CRR first-accept from ${senderHex.substring(0, 8)} with '
              'changed keys — §8.3 reset');
          try {
            onContactIdentityRotated?.call(senderHex, existing.displayName, keyChange.wasVerified);
          } catch (e) {
            _log.warn('onContactIdentityRotated listener threw: $e');
          }
        }

        _saveContacts();

        // Sync conversation displayName — the conversation may already exist
        // (e.g. text arrived before CRR) with a truncated-hash placeholder.
        final conv = conversations[senderHex];
        if (conv != null && resp.displayName.isNotEmpty) {
          conv.displayName = resp.displayName;
          if (picBase64 != null) conv.profilePictureBase64 = picBase64;
        }

        // Create conversation with system message so the contact appears
        // immediately in the "Aktuell" tab (not only in "Kontakte" tab).
        _addSystemMessage(senderHex, '${resp.displayName} accepted your contact request.',
            type: UiMessageType.identityDeleted); // system message type
        _saveConversations();

        onContactAccepted?.call(senderHex);
        _log.info('Contact accepted by ${senderHex.substring(0, 8)}');
        _log.debug('  ... displayName="${resp.displayName}"');
        // §15.5: if the other side was at the same time itself knocking at
        // our door (mutual requests), its waiting request is answered with
        // this acceptance — the same consequence as in
        // `_myceliumJoinAccepted`.
        _myceliumOwnQuestionAnswer(existing);
      } else {
        _log.info('Contact rejected by ${senderHex.substring(0, 8)}: ${resp.rejectionReason}');
      }
      onStateChanged?.call();
    } catch (e) {
      _log.error('Contact response parse error: $e (sender=${CleonaService._hexShort(Uint8List.fromList(event.senderUserId))} device=${CleonaService._hexShort(event.senderDeviceId)})');
    }
  }
}
