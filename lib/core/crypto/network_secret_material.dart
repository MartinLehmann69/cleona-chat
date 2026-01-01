// ==========================================================================
// CLOSED-NETWORK KEY MATERIAL — PLACEHOLDER (public source tree)
// ==========================================================================
//
// The real key material is not part of the published source. See Architecture
// 4.10 (Closed Network Model): only official maintainer builds carry the
// network secret, and a build made from this source therefore derives an
// all-zero secret. Such a build cannot join the official Cleona network — its
// packets carry an HMAC no official node accepts, and its node IDs land in a
// disjoint DHT address space.
//
// This is intentional and is the only part of the tree that differs from the
// official build. Everything relevant to auditing the cryptography — the
// derivation, the HMAC construction, the rotation logic — is in
// network_secret.dart and is complete here.
//
// ==========================================================================

/// Whether this file carries real key material. Always `false` in public source.
const bool kNetworkSecretMaterialPresent = false;

/// Placeholder — see the file header.
const List<int> kNetworkSecretBetaTableV1 = [
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
];

/// Placeholder — see the file header.
const List<int> kNetworkSecretLiveTableV1 = [
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
];

/// Position permutation applied during reassembly. Structural, not secret.
const List<int> kNetworkSecretPerm = [
  11, 4, 14, 1, 8, 13, 2, 7, 15, 6, 9, 0, 5, 10, 3, 12, //
];
