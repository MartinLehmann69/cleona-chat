# Cleona Chat

**Decentralized. Post-Quantum Secure. No Servers. No Phone Number. No Compromise.**

Cleona Chat is a peer-to-peer messenger that operates entirely without central servers. Your messages travel directly between devices — encrypted with post-quantum cryptography that protects against both current and future threats.

## Why Cleona?

- **No servers** — All communication is peer-to-peer via a Kademlia-based DHT. There is no single point of failure, no entity that can be compelled to hand over data, and no infrastructure to seize.
- **Post-quantum encryption** — Hybrid cryptography combining classical (X25519, Ed25519, AES-256-GCM) and post-quantum (ML-KEM-768, ML-DSA-65) algorithms. If either scheme is broken, the other still protects your communication.
- **No identity required** — No phone number, no email, no personal information. Your identity is purely cryptographic — a keypair generated on your device.
- **Offline delivery** — Messages reach you even when you're offline, through erasure-coded fragments distributed across the network and store-and-forward on mutual contacts.
- **Open for audit** — The source code is publicly available so anyone can verify the cryptographic implementation and security claims.

## Features

### Messaging
- Text, images, video, audio, files — all end-to-end encrypted
- Message editing and deletion (15-minute window)
- Emoji reactions, reply/quoting, read receipts, typing indicators
- Voice messages with source-side transcription (whisper.cpp)
- Inline media preview, pinch-to-zoom, video/audio player
- URL detection with sender-side link previews (no network request by receiver)
- Clipboard paste and drag & drop for media
- Chat search with match navigation

### Groups & Channels
- Groups with pairwise fan-out encryption and 3-role system
- Public channels with DHT-based discovery and search
- Decentralized moderation with jury system
- Content rating and language filtering

### Voice & Video Calls
- 1:1 and group audio/video calls
- Opus audio codec with jitter buffer
- VP8 video with adaptive bitrate
- Overlay multicast for efficient group calls
- Picture-in-picture layout

### Network & Delivery
- Distance-vector routing with three-layer delivery cascade
- Direct → Relay → Store-and-Forward + Erasure Coding backup
- NAT hole punching with coordinated traversal
- Protocol escalation: UDP → UDP+NACK → TLS (anti-censorship fallback)
- Closed network model with HMAC authentication on every packet

### Identity & Recovery
- Multiple identities via HD wallet derivation from a single seed
- 24-word seed phrase backup
- Restore broadcast to contacts (one online contact is enough)
- Shamir Secret Sharing (3-of-5) for guardian-based recovery
- Contact verification levels (4 tiers)
- NFC contact exchange

### Privacy & Security
- Per-message KEM encryption (no session state, no desync)
- Database encryption at rest (XSalsa20-Poly1305)
- DoS protection: PoW + rate limiting + reputation system + fragment budgets + network banning
- KEX gate: unknown senders are silently dropped
- No telemetry, no analytics, no tracking

### Platforms
- Linux Desktop (.deb, .rpm, AppImage)
- Windows Desktop (installer)
- Android (APK, Google Play planned)
- iOS (planned)

### Internationalization
- 33 languages including RTL support

## Building from Source

### Prerequisites
- Flutter SDK (stable channel)
- Dart SDK
- Native libraries: libsodium, liboqs, libzstd, liberasurecode

### Linux
```bash
flutter build linux --release
# Build distribution packages (AppImage, .deb, .rpm):
./scripts/build-linux-packages.sh 3.2.0
```

### Android
```bash
flutter build apk --release
```

### Windows
```bash
flutter build windows --release
```

## Verifying Releases

Each release includes Ed25519-signed binaries. To verify:

1. Download the release artifact and its `.sig` file
2. Download `SHA256SUMS` and `SHA256SUMS.sig`
3. Verify the signature using the maintainer's public key (included in `assets/cleona_maintainer_public.pem`)

### Reproducible Builds

You can verify that official binaries match the published source:

1. Build from source using the same Flutter/Dart versions noted in the release
2. Strip the release signature from the official binary
3. Compare the unsigned binaries — they should be byte-for-byte identical

## License

Cleona Chat is released under a **Source Available License**. You may read, study, audit, and build the source for personal use. Redistribution, forks, and commercial use are not permitted. See [LICENSE](LICENSE) for the full terms.

The name "Cleona Chat" and its logo are protected trademarks.

## Security

Found a vulnerability? Please report it responsibly. See [SECURITY.md](SECURITY.md) for our disclosure policy.

## Support the Project

Cleona Chat has no ads, no investors, and no data monetization. Development is funded entirely by donations.

- In-app donation screen with SEPA and Bitcoin
- All donation addresses are Ed25519-signed for fork protection
