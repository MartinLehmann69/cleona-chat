# Cleona Chat — Privacy Policy

**Last updated:** June 25, 2026

## Summary

Cleona Chat is a fully decentralized peer-to-peer messenger. There are no servers, no accounts, and no data collection of any kind. Your messages, contacts, and media stay exclusively on your device.

## Data We Collect

**None.** Cleona Chat does not collect, transmit, or store any personal data on any server. There is no server infrastructure.

## How Cleona Chat Works

- **Peer-to-peer architecture:** Messages travel directly between devices over an encrypted P2P network. No central server routes or stores your data.
- **No account required:** Your identity is a cryptographic key pair on your device. No email, phone number, or personal info required.
- **End-to-end encryption:** Hybrid post-quantum crypto (X25519 + ML-KEM-768, AES-256-GCM). Only the intended recipient can decrypt.
- **Local storage only:** Encrypted local database (XSalsa20-Poly1305). No cloud backup.

## Offline Message Delivery

Store-and-Forward via mutual contacts + Reed-Solomon erasure coding on DHT peers. Intermediaries cannot read message content.

## Network Discovery

Local broadcast/multicast only. No external discovery servers. Contact exchange via QR, NFC, or URI — all user-initiated.

## Third-Party Services

**None.** No SDKs, analytics, ads, or crash reporting.

## Encryption Details

See the [Security Whitepaper](docs/SECURITY_WHITEPAPER.md).

## Data Retention

No server = no retention. All data is on your device, under your control.

## Children's Privacy

No data collected from anyone, including children under 13.

## Contact

- Email: info@kmx-care.de
- GitHub: https://github.com/MartinLehmann69/cleona-chat
