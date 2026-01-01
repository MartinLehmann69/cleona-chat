import 'dart:typed_data';
import 'package:cleona/core/crypto/network_secret_material.dart';
import 'package:cleona/core/config/network_channel.dart';

// `NetworkChannel` and the channel resolution moved to
// lib/core/config/network_channel.dart (AP-1a, §9.15.5): the channel is a
// build-time switch, not key material, and twelve files imported this module
// for nothing else. Not re-exported — callers import it from its new home.

/// The network secret of the V4.1 line — and what it is **not**.
///
/// The secret is derived offline from the maintainer's Ed25519 private key:
///   network_secret = HMAC-SHA256(maintainer_key, "cleona-network-" + channel + "-v" + version)[:16]
///
/// It is embedded at build time in XOR-masked fragments; the material lives in
/// `network_secret_material.dart` and is never inlined here (see there).
///
/// **What it does (§26.6, §26.7).** It is the input keying material of the
/// binary-distribution rendezvous: the lookup tag, the record encryption key
/// and the per-device publishing key all derive from it
/// (`rendezvous/rendezvous_secret.dart`). It also tags an exported peer-rescue
/// bundle (`rendezvous/peer_rescue_bundle.dart`). A build made from the
/// published source derives an all-zero secret and therefore cannot discover
/// or decrypt update records — see [hasKeyMaterial].
///
/// **What it explicitly is NOT (§22.2, §26.5.1, §26.7).** It is not an
/// admission barrier. There is **no packet HMAC** and **no network-side
/// membership filter** on this line: every build can take part in the delivery
/// layer. Identity at the wire is `L_node` (`link/node_keys.dart`) — derived
/// from the three static node keys, hence self-certifying and secret-free —
/// and authenticity is carried by the handshake init MAC and the AEAD of the
/// cell, not by a network-wide shared secret.
///
/// **Removed 06.09.2026 (S370), with owner approval.** `wrapPacket`,
/// `unwrapPacket`, `verifyPacketHmac`, `computePacketHmac`,
/// `computeNetworkTag`, `verifyNetworkTag`, `outboundSecret` and the whole
/// EPOCH_EXPIRED hint family lived here and had **zero callers** in `lib/` on
/// both branches — measured with bare-symbol sweeps, `git grep` against
/// `v4/knoten-host`, and a check that neither `dart:mirrors` nor any
/// method-name string literal could reach them. They belonged to the V3
/// closed-network wire, which this line does not have. Do not reintroduce them
/// here: a packet HMAC would contradict §22.2 and would be a membership filter
/// the architecture rules out.
///
/// **Rotation (§26.7).** Two generations are accepted at once so a node that
/// has not yet updated stays able to find the very binary that updates it
/// (`binary_rendezvous_manager.dart`, R-2). What does *not* exist is a
/// rotation **cascade** that could lock anyone out of the network — there is
/// nothing to be locked out of.
class NetworkSecret {
  /// The active channel. Resolution lives in
  /// lib/core/config/network_channel.dart; kept here as a delegating getter
  /// for the callers that need both the channel and the secret material.
  static NetworkChannel get channel => activeNetworkChannel;

  /// Current secret version. Increment when rotating secrets.
  static const int currentSecretVersion = 1;

  /// Previous secret version (0 = no previous secret / first version).
  /// Set to currentSecretVersion - 1 during transition periods.
  /// Set to 0 to disable dual-secret acceptance.
  static const int previousSecretVersion = 0;

  /// Transition period in days: how long the previous secret stays acceptable
  /// for rendezvous lookup after a rotation.
  static const int transitionDays = 90;

  // ---------------------------------------------------------------------------
  // Key material lives in network_secret_material.dart and is NEVER inlined
  // here — the publishing pipeline substitutes that file with an all-zero
  // placeholder and fails closed if any real table byte survives into the
  // public staging tree (sync-to-git.sh [3b] + [4h], dry-run check [6b]).
  //
  // When rotating to V2:
  // 1. Generate new secret: HMAC-SHA256(maintainer_key, "cleona-network-beta-v2")[:16]
  // 2. Generate V2 tables via scripts/gen_secret_table.dart, add them to
  //    network_secret_material.dart as kNetworkSecretBetaTableV2 / ...LiveTableV2
  // 3. Add a `case 2:` to _secretForVersion below
  // 4. Set currentSecretVersion = 2, previousSecretVersion = 1
  // 5. After 90 days: set previousSecretVersion = 0
  // ---------------------------------------------------------------------------

  /// Whether this build carries real key material.
  ///
  /// `false` for builds made from the published source — such a build derives
  /// an all-zero secret. It can still take part in the delivery layer (there is
  /// no membership filter, §26.5.1), but it publishes and resolves binary
  /// update records under a different tag and cannot decrypt them. Exposed so
  /// higher layers can surface that state instead of presenting it as an
  /// ordinary connectivity failure.
  static bool get hasKeyMaterial => kNetworkSecretMaterialPresent;

  static Uint8List? _cached;
  static Uint8List? _cachedPrevious;

  /// Returns the 16-byte network secret for the current version.
  /// Reassembled from XOR-masked fragments at runtime.
  static Uint8List get secret {
    if (_cached != null) return _cached!;
    _cached = _secretForVersion(currentSecretVersion);
    return _cached!;
  }

  /// Returns the previous secret (if in transition period), or null.
  static Uint8List? get previousSecret {
    if (previousSecretVersion == 0) return null;
    _cachedPrevious ??= _secretForVersion(previousSecretVersion);
    return _cachedPrevious;
  }

  /// Whether dual-secret acceptance is active.
  static bool get isInTransition => previousSecretVersion > 0;

  // S388: here stood `identitySecret`, a forwarder to
  // `kIdentityDomainBytes` for two callers that still passed `computeUserId`
  // a second argument "domain". Since "identifier = A" (v4.2 §4.1) the
  // second argument is the ML-DSA-65 key; both callers pass it,
  // and the forwarder no longer had a caller. The identity derives from
  // the public `kIdentityDomain`, never from this module —
  // `smoke_identity_secret_pin.dart` records that.

  /// Returns the secret for the given version.
  static Uint8List _secretForVersion(int version) {
    // Currently only version 1 exists.
    // When adding V2, add a case here (see rotation checklist above).
    switch (version) {
      case 1:
        return _reassemble(
          channel == NetworkChannel.live
              ? kNetworkSecretLiveTableV1
              : kNetworkSecretBetaTableV1,
        );
      default:
        throw ArgumentError('Unknown secret version: $version');
    }
  }

  static Uint8List _reassemble(List<int> table) {
    final result = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      result[kNetworkSecretPerm[i]] = table[2 * i] ^ table[2 * i + 1];
    }
    return result;
  }

  /// Clear cached secrets (for testing).
  static void clearCache() {
    _cached = null;
    _cachedPrevious = null;
  }
}
