// ==========================================================================
// CLOSED-NETWORK KEY MATERIAL — PLACEHOLDER (public source tree)
// ==========================================================================
//
// The real key material is not part of the published source. Only official
// maintainer builds carry the network secret; a build made from this source
// derives an all-zero secret.
//
// What that secret does (Architecture §26.6, §26.7): it keys the binary
// distribution path — the lookup tag, the record encryption and the Nostr
// publishing key of official updates. It admits no one: there is no packet
// HMAC and no network-side membership filter (§20, §10), and the delivery
// layer (mycelium/) does not use it. A build from this source therefore takes
// part in the network like any other, but cannot find or read the official
// update path.
//
// This is intentional and is the only part of the tree that differs from the
// official build. The derivation and the rotation logic are in
// network_secret.dart and are complete here.
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
