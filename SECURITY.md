# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Cleona Chat, please report it responsibly.

### How to Report

**Email:** security@cleona.chat

**Encryption:** If possible, encrypt your report using the maintainer's public key available in `assets/cleona_maintainer_public.pem`.

**GitHub:** For non-critical issues, you may open a GitHub Security Advisory on this repository.

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected component (crypto, network, protocol, UI)
- Potential impact assessment
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment:** Within 48 hours
- **Assessment:** Within 7 days
- **Fix (critical):** As soon as possible, typically within 14 days
- **Fix (non-critical):** Within the next release cycle
- **Public disclosure:** Coordinated with the reporter, typically 90 days after report

### Scope

The following areas are in scope for security research:

- Cryptographic implementation (per-message KEM, key derivation, signatures)
- Network protocol (DHT, routing, relay, RUDP)
- Message delivery and storage (erasure coding, store-and-forward)
- Identity management (HD wallet, seed phrase, recovery)
- DoS protection mechanisms
- Database encryption
- IPC security (daemon-GUI communication)
- Closed network model (HMAC, network secret)

### Out of Scope

- Social engineering attacks
- Physical device access attacks
- Denial of service through network flooding (covered by DoS protection layers)
- Issues in third-party dependencies (report these upstream, but notify us)

### Safe Harbor

We consider security research conducted in good faith to be authorized. We will not pursue legal action against researchers who:

- Act in good faith and follow this disclosure policy
- Avoid privacy violations, data destruction, and service disruption
- Do not exploit vulnerabilities beyond what is necessary to demonstrate them
- Report findings before any public disclosure

### Cryptographic Design

For details about Cleona Chat's cryptographic architecture, see `docs/SECURITY_WHITEPAPER.md`.

## Supported Versions

Security updates are provided for the latest release version only.
