# Cleona Chat — Changelog

## V3.1 — Current Release

### Messaging
- Text, images, video, audio, files — all end-to-end encrypted via single UDP path
- Message edit (configurable window, default 60 min) and delete (unbounded — author may delete any time)
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
- System channels: Bug Log (structured crash reports, fingerprint dedup, +1 counter) and Feature Requests (auto-poll, vote sorting)
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
- Multi-device support: max 5 devices, device-node-ID routing, 14 twin-sync types, device revocation, emergency key rotation with device co-authorization quorum
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

### Calendar
- Multi-identity calendar with encrypted persistence
- 5 views: day, week, month, year, and tasks
- RFC 5545 RRULE recurrence (daily/weekly/monthly/yearly with BYDAY/BYMONTHDAY/INTERVAL/COUNT/UNTIL)
- 6 protocol messages: CALENDAR_INVITE, RSVP, UPDATE, DELETE, FREE_BUSY_REQUEST, FREE_BUSY_RESPONSE
- Free/busy 3-tier privacy (full/time-only/hidden), per-contact overrides, auto-responder
- iCal import/export, PDF print for all 4 views (A4/landscape)
- Reminder service in daemon (system notifications, snooze, dedup)
- External sync: CalDAV client (RFC 4791), Google Calendar API v3 (OAuth2 + PKCE), local CalDAV server (Thunderbird/Outlook/Apple/Evolution), Android CalendarContract bridge, local ICS file bridge

### Polls
- 5 poll types: single choice, multiple choice, date poll, scale, free text
- 6 protocol messages: POLL_CREATE, VOTE, UPDATE, SNAPSHOT, POLL_VOTE_ANONYMOUS, REVOKE
- Anonymous voting via linkable ring signatures on Ed25519 (MLSAG-style); key image deterministic per (sk, pollId) for double-vote detection, cross-poll unlinkable
- Channel broadcast optimization: subscriber votes go to creator only, creator broadcasts snapshots (O(N) instead of O(N^2))
- Date poll to calendar event bridge

### Software Distribution
- In-network binary updates via Reed-Solomon erasure-coded fragments
- Nostr binary discovery for censorship-resistant update announcements
- Embedded HTTP server with bootstrap assembler for update serving
- Invite links (Ed25519-signed) for network onboarding
- Physical transfer support (USB/LAN)
- Delta updates for bandwidth-efficient upgrades

### Platforms
- Linux Desktop (daemon + GUI via IPC/Unix socket, system tray)
- Windows Desktop (daemon + GUI via IPC/TCP + auth token, system tray)
- Android (in-process, multi-identity, CameraX, foreground service notification, vibration)
- iOS (in-process, static native libs via XCFrameworks, TestFlight distribution)
- macOS (daemon + GUI, dylibs in Contents/Frameworks, notarized DMG)

### Internationalization
- 33 languages including RTL support

### Additional Features
- Media auto-archive (SMB/SFTP/FTPS/HTTP)
- Storage budget (100MB-2GB, platform-specific)
- Auto-download thresholds per media type
- Network statistics dashboard
- In-app donation screen (SEPA + BTC, Ed25519-signed)
- 10 skin themes including WCAG AAA contrast mode
- Connection status icon (5-tier: strong/good/medium/weak/offline with pulse animation)
- Discovery: IPv4 broadcast + multicast, IPv6 multicast, NFC, QR code, ContactSeed URI
- UPnP gateway discovery, subnet scan fallback

### Planned Features
- In-call collaboration (whiteboard, screen sharing, file exchange, remote control)
