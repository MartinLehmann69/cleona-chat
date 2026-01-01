# Cleona Chat — Changelog

## V3.1 — Current Release

### Messaging
- Text, images, video, audio, files — all end-to-end encrypted via single UDP path
- Message edit/delete (15-minute window)
- Emoji reactions (KEM-encrypted, group fan-out, bottom sheet with quick reactions + picker)
- Reply/quoting with quote display in message bubble
- Voice messages (AAC) with source-side transcription (whisper.cpp)
- Clipboard paste (image/video/audio/file) and drag & drop
- URL detection with sender-side link previews (SSRF-protected, HTTPS-only)
- Image full-view (pinch-to-zoom), inline video/audio player
- Tab search filter + in-chat message search with match navigation
- Read receipts and typing indicators

### Groups & Channels
- Groups with pairwise fan-out encryption and 3-role system (admin/moderator/member)
- Public channels with DHT index, gossip-based discovery, search, language filter, content rating
- Decentralized moderation: 6 categories, jury system (5-11 jurors), 3-tier bad badge
- CSAM special procedure (3 stages, cooldown, strikes), anti-Sybil (Bloom filter, 5 hops)
- KEX gate (unknown senders silently dropped)

### Routing & Delivery (V3)
- Distance-vector routing (Bellman-Ford, split horizon, poison reverse)
- Three-layer cascade: Direct → Relay → Store-and-Forward + Erasure Coding backup
- RUDP Light: delivery receipt ACK, fragment NACK (CFNK), ACK tracker with RTT-EMA
- Multi-hop relay (max 3 hops, 300KB budget, loop prevention)
- NAT hole punch (coordinated via third party), NAT timeout probing, keepalive
- App-level fragmentation (>1200B, max 255 fragments, auto-reassembly)
- Protocol escalation: UDP → UDP+NACK → TLS (anti-censorship fallback)
- Persistent message queue (7-day TTL on route failure)
- Closed network model: HMAC on every packet, network secret rotation

### Voice & Video Calls
- 1:1 audio (Opus, jitter buffer) + video (VP8/libvpx, adaptive bitrate)
- Group calls (audio mixer, group video receiver, KEM key distribution + rotation)
- Overlay multicast tree (RTT-based, degree-constrained MST, LAN IPv6 multicast)
- PiP video layout, Android CameraX
- Notification sounds (6 ringtones), vibration (Android), ringback

### Identity & Recovery
- Multi-identity via HD wallet derivation from master seed
- 24-word seed phrase backup/restore
- Restore broadcast to contacts (one online contact suffices)
- Shamir Secret Sharing (3-of-5) guardian recovery
- DHT identity registry (erasure-coded, encrypted)
- Contact verification levels (4 tiers: unverified/seen/verified/trusted)
- NFC contact exchange (dual-purpose: pairing + peer list merge)
- Identity deletion broadcast
- Signed update manifest (DHT check, Ed25519 verification)

### DoS Protection (5 Layers)
- Proof of Work
- Per-node rate limiting (relay-exempt)
- Reputation system (good actions for all accepted packets)
- Fragment budgets
- Network banning

### Platforms
- Linux Desktop (daemon + GUI via IPC/Unix socket, system tray)
- Windows Desktop (daemon + GUI via IPC/TCP + auth token, system tray)
- Android (in-process, multi-identity, CameraX, push notifications, vibration)

### Internationalization
- 33 languages including RTL support

### Additional Features
- Media auto-archive (SMB/SFTP/FTPS/HTTP)
- Storage budget (100MB-2GB, platform-specific)
- Auto-download thresholds per media type
- Network statistics dashboard
- In-app donation screen (SEPA + BTC, Ed25519-signed)
- 9 skin themes including WCAG AAA contrast mode
- Discovery: IPv4 broadcast + multicast, IPv6 multicast, NFC, QR code, ContactSeed URI
- UPnP gateway discovery, subnet scan fallback

### Planned Features
- Calendar with multi-identity support, free/busy protocol, RSVP, recurring events
- Polls & voting (5 types, anonymous via linkable ring signatures)
- In-call collaboration (whiteboard, screen sharing, file exchange)
