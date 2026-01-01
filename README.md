# Cleona Chat

**Decentralized. Post-Quantum Secure. No Servers. No Phone Number.**

Cleona Chat is a peer-to-peer messenger without servers. Every participant is a peer; a peer that forwards for somebody else is still just a peer. Identity is purely cryptographic — no phone number, no email address, no account.

This is the **4.2** line. It is a new delivery layer and is not compatible with the 3.x releases: no migration, no shared network, no shared wire format. The full specification is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Why Cleona?

- **No servers** — peers are the network. There is no central directory, no account server and no infrastructure to seize.
- **Post-quantum encryption** — every message carries its own hybrid key encapsulation (X25519 + ML-KEM-768) and a hybrid signature (Ed25519 + ML-DSA-65). There is no session state that could desynchronize.
- **No identity required** — your identity is a keypair generated on your device, backed up by a 24-word phrase.
- **Offline delivery** — a message for an absent recipient waits in a post box held by three neighbours for up to 7 days.
- **Hard to censor** — sealed content, packets of one fixed size, a cover stream beside the traffic, and several independent paths instead of a single point to block.
- **Open for audit** — the source is public so anyone can verify the cryptography and the security claims.

## How a message travels

```
text → compress → seal (hybrid KEM, signature inside) → split into 1200-byte parts
     → all delivery ways at once, first acknowledgement wins:
         1  local network address            milliseconds
         2  public address (knocking if needed)  seconds
         3  through a neighbour, up to 3 hops    seconds
         4  post box at three neighbours         until the recipient returns
     → recipient opens the seal, checks the signature, acknowledges
```

What this costs is stated openly in the specification (§1.4) — for example, a forwarding neighbour learns that two identifiers exchange packets, though not who they are or what they say.

## Features

### Messaging
- Text, images, video, audio and files — all end-to-end encrypted
- Message editing and deletion, emoji reactions, reply/quoting, read receipts
- Voice messages with on-device transcription (whisper.cpp)
- Link previews created by the sender — the recipient makes no network request

### First contact
- Invitation cards as QR code, NFC touch or a text line; a card is built from the device's own keys and works on a device that has never reached the network
- Requests from strangers need an explicit acceptance; contacts can be verified in four levels

### Groups & Channels
- End-to-end encrypted groups with roles
- Public channels with decentralized moderation by a jury of users

### Calendar & Polls
- Encrypted calendar with recurring events (RFC 5545), RSVP, iCal import/export and CalDAV sync
- Polls, including anonymous voting with linkable ring signatures

### Calls
- 1:1 and group audio/video calls, Opus audio
- Video through the platform's hardware codecs (H.264 as the common baseline; HEVC, AV1 and VP9 when both sides support them)

### Identity, devices & recovery
- Several identities from one seed phrase
- Up to 5 devices per identity; a replaced device is simply removed from the device set
- If all devices are lost: the 24-word phrase restores the identities, and the data is rebuilt from the chats with your contacts, groups and channels

### Storage
- Messages in an encrypted SQLite database per identity (SQLite3 Multiple Ciphers), configuration in encrypted files, media encrypted on disk

### Updates
- In-network updates with a hybrid-signed manifest (Ed25519 + ML-DSA-65); an update is only offered once it is complete and verified

### Platforms & languages
- Linux, Windows, macOS, Android, iOS
- 34 languages including right-to-left scripts

## Building from Source

### Prerequisites
- Flutter SDK (stable channel) with its Dart SDK
- Native libraries: libsodium, liboqs, libzstd, Opus; Cleona's own native modules are in `native/`

### Linux
```bash
flutter build linux --release
# The daemon — `dart build cli` (not `dart compile exe`) so that the build
# hooks run and the encrypted store library is bundled:
dart build cli --target bin/cleona_daemon.dart --output build/daemon-cli
```

### Android
```bash
./scripts/build-android-libs.sh   # native libraries
flutter build apk --release
```

### Windows
```bash
flutter build windows --release
windows\scripts\compile-daemon.bat
```

### iOS
```bash
./scripts/build-ios-libs.sh    # native libraries
flutter build ipa
```

### macOS
```bash
./scripts/build-macos-libs.sh  # native libraries
./scripts/deploy-macos-app.sh  # app bundle including the daemon
```

**Note:** the key material of the official update path is not part of the published source (see `lib/core/crypto/network_secret_material.dart`). A build from this source takes part in the network like any other, but cannot find or read the official update path.

## Verifying Releases

Each release includes Ed25519-signed binaries. To verify:

1. Download the release artifact and its `.sig` file
2. Download `SHA256SUMS` and `SHA256SUMS.sig`
3. Verify the signature using the maintainer's public key (included in `assets/cleona_maintainer_public.pem`)

## License

Cleona Chat is released under a **Source Available License**. You may read, study, audit, and build the source for personal use. Redistribution, forks, and commercial use are not permitted. See [LICENSE](LICENSE) for the full terms.

The name "Cleona Chat" and its logo are protected trademarks.

## Security

Found a vulnerability? Please report it responsibly. See [SECURITY.md](SECURITY.md) for our disclosure policy.

## Support the Project

Cleona Chat has no ads, no investors, and no data monetization. Development is funded entirely by donations.

- In-app donation screen with SEPA and Bitcoin
- All donation addresses are Ed25519-signed for fork protection
