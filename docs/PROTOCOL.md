# Cleona — Protocol & Message Format

## MessageEnvelope (Protobuf)
Jede Nachricht nutzt dasselbe Envelope-Format. Alle Nodes nutzen dasselbe Protokoll.

Wichtige Felder: version, sender_id (32B), recipient_id (32B), timestamp (ms), message_type, encrypted_payload, signature_ed25519, signature_ml_dsa, erasure_metadata, pow, kem_header, compression, network_tag, message_id (UUID v4)

## Message Types (Kurzreferenz)
**Core:** TEXT(0), IMAGE(1), VIDEO(2), EMOJI_REACTION(4), MEDIA_ANNOUNCEMENT(5), MEDIA_ACCEPT(6), MEDIA_REJECT(7), MESSAGE_EDIT(8), MESSAGE_DELETE(21), VOICE_MESSAGE(22), FILE(23)

**Keys:** KEY_ROTATION(10)

**Recovery:** RESTORE_BROADCAST(13), RESTORE_RESPONSE(14)

**Presence:** TYPING_INDICATOR(15), READ_RECEIPT(16), DELIVERY_RECEIPT(94)

**Groups:** GROUP_CREATE(17), GROUP_INVITE(18), GROUP_LEAVE(19), GROUP_KEY_UPDATE(20)

**Calls:** CALL_INVITE(30), CALL_ANSWER(31), CALL_REJECT(32), CALL_HANGUP(33), ICE_CANDIDATE(34), CALL_REJOIN(35)

**Peer Exchange (3-Step Delta):** PEER_LIST_SUMMARY(50), PEER_LIST_WANT(51), PEER_LIST_PUSH(52)

**Contacts:** CONTACT_REQUEST(62), CONTACT_REQUEST_RESPONSE(63)

**Channels:** CHANNEL_CREATE(70), CHANNEL_POST(71), CHANNEL_INVITE(72), CHANNEL_ROLE_UPDATE(73), CHANNEL_LEAVE(74)

**DHT:** DHT_PING(80), DHT_PONG(81), DHT_FIND_NODE(82/83), DHT_STORE(84/85), DHT_FIND_VALUE(86/87)

**Fragments (RUDP):** FRAGMENT_STORE(90), FRAGMENT_STORE_ACK(91), FRAGMENT_RETRIEVE(92), FRAGMENT_DELETE(93)

**Config:** CHAT_CONFIG_UPDATE(100), CHAT_CONFIG_RESPONSE(101), IDENTITY_DELETED(102), PROFILE_UPDATE(103)

**Calendar (§23):** CALENDAR_INVITE(140), CALENDAR_RSVP(141), CALENDAR_UPDATE(142), CALENDAR_DELETE(143), FREE_BUSY_REQUEST(144), FREE_BUSY_RESPONSE(145)

## Processing Order
**Outgoing:** Serialize → Compress (zstd) → Encrypt (AES-256-GCM via KEM) → Sign (Ed25519 + ML-DSA-65) → Erasure Code → PoW → Send

**Incoming:** Verify PoW → Verify Signatures → Reconstruct (Erasure) → Deduplicate (pre-Decrypt) → Decrypt → Decompress → Deserialize

## Rejection Criteria
Message wird abgelehnt wenn: network_tag mismatch, PoW ungültig, Signaturen fehlerhaft, Erasure-Metadata inkonsistent.

## Group/Channel Encryption
Group Messages: Wrapped in `ChannelPost`, gesendet als `GROUP_KEY_UPDATE` an jedes Mitglied einzeln via pairwise Per-Message KEM.
Channel Posts: `CHANNEL_POST` mit gleichem pairwise Delivery Pattern.
