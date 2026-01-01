/// Link-KDF — derives the link key and the two directional cell keys
/// (AP-3a step 1, docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.10 C and §4d.11;
/// architecture v4 §2.6/§2.7).
///
/// **This file freezes wire-relevant cryptography.** Guarded by
/// `test/smoke/smoke_link_kdf.dart` (golden vectors + independent
/// recomputation from primitives).
///
/// ```
/// link_key   = hkdfSha256(x25519_ss ‖ mlkem_ss,          // IKM, 32 B each
///                         salt: SHA-256("cleona-link/salt/v1"),
///                         info: utf8(kNetworkChannel),   // "cleona-beta"|"cleona-live"
///                         length: 32)
/// k_cell_init = hkdfSha256(link_key, salt: <the same>, info: utf8("cell/init"), length: 32)
/// k_cell_resp = hkdfSha256(link_key, salt: <the same>, info: utf8("cell/resp"), length: 32)
/// ```
///
/// Decisions carried by this layout (§4d.10 B/C, §4d.11):
///
/// - The network channel goes into the **info parameter**, NOT into the
///   IKM. The IKM is purely `x25519_ss ‖ mlkem_ss`, both fixed 32 bytes, so
///   the concatenation is unambiguous forever — a third channel with a
///   different name length can never make it ambiguous.
/// - The salt is `/v1`, not `/v4`: domain-separation labels version the
///   *construction*, not the architecture document (the per-message KEM of
///   the V3 line carries `/v2` for exactly this reason).
/// - `link_key` is the **root**, not the cipher key: each direction of a
///   link encrypts under its own key so the two directions never share an
///   AES-GCM nonce space. Label per key instead of splitting a 64-byte
///   block — the TLS pattern, and it keeps `link_key` intact as a named
///   root.
///
/// The implementation uses only house primitives: `hkdfSha256`
/// (lib/core/crypto/sodium_ffi.dart, RFC 5869) and `sha256`. No new
/// cryptography.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';

abstract final class LinkKdf {
  static final _sodium = SodiumFFI();

  /// HKDF salt for every link-layer derivation:
  /// `SHA-256("cleona-link/salt/v1")`. The same salt is used for the root
  /// and for both directional keys (§4d.11: "salt: `<derselbe>`").
  static final Uint8List _salt = _sodium.sha256(
    Uint8List.fromList(utf8.encode('cleona-link/salt/v1')),
  );

  /// The HKDF salt of every link-layer derivation.
  ///
  /// Public because the handshake derives `k_prov` under the same salt
  /// (§2.6, E-82). A second hand-written copy of a wire-relevant constant is
  /// the error class this project has been bitten by repeatedly — one owner,
  /// one value.
  static Uint8List get salt => Uint8List.fromList(_salt);

  /// Test-only alias, kept so existing golden-vector tests read unchanged.
  @visibleForTesting
  static Uint8List get saltForTest => salt;

  /// Info label of the initiator→responder cell key.
  static const String infoCellInit = 'cell/init';

  /// Info label of the responder→initiator cell key.
  static const String infoCellResp = 'cell/resp';

  /// Derives the 32-byte link key from the two handshake shared secrets.
  ///
  /// [x25519Ss] and [mlkemSs] are the 32-byte shared secrets of the hybrid
  /// handshake (step 2). [channel] defaults to this build's
  /// [kNetworkChannel]; tests pass it explicitly.
  /// [staticSs] is the static-static X25519 secret of the two
  /// nodes and is only present when the callee knew the caller
  /// (decision C, 2026-08-22). It makes the caller implicitly
  /// authenticated: whoever merely claims the position cannot form it
  /// and derives a different key — there is no rejection,
  /// simply nothing fits any more. Because it is CONSTANT for a pair, it may
  /// never carry alone; it is added to the two ephemeral secrets,
  /// not put in their place.
  static Uint8List deriveLinkKey({
    required Uint8List x25519Ss,
    required Uint8List mlkemSs,
    Uint8List? staticSs,
    String? channel,
  }) {
    if (x25519Ss.length != 32) {
      throw ArgumentError(
          'deriveLinkKey: x25519_ss must be 32 bytes, got ${x25519Ss.length}');
    }
    if (mlkemSs.length != 32) {
      throw ArgumentError(
          'deriveLinkKey: mlkem_ss must be 32 bytes, got ${mlkemSs.length}');
    }
    if (staticSs != null && staticSs.length != 32) {
      throw ArgumentError(
          'deriveLinkKey: static_ss must be 32 bytes, got ${staticSs.length}');
    }
    // The LENGTH already distinguishes the two cases — an
    // authenticated and an anonymous handshake can never yield the same
    // key, not even with otherwise identical inputs.
    final ikm = Uint8List(staticSs == null ? 64 : 96)
      ..setRange(0, 32, x25519Ss)
      ..setRange(32, 64, mlkemSs);
    if (staticSs != null) ikm.setRange(64, 96, staticSs);
    return _sodium.hkdfSha256(
      ikm,
      salt: _salt,
      info: Uint8List.fromList(utf8.encode(channel ?? kNetworkChannel)),
      length: 32,
    );
  }

  /// Derives the initiator→responder cell key from [linkKey].
  static Uint8List deriveCellKeyInit(Uint8List linkKey) =>
      _deriveDirectional(linkKey, infoCellInit);

  /// Label of the delivery key (AP-3a pattern, new `info` value).
  static const String infoDelivery = 'delivery/v1';

  /// Derives the key of the DELIVERY LAYER from [linkKey].
  ///
  /// Why a separate one at all: the onion (WP-3) needs one
  /// key per link, but the `link_key` itself must not leave the
  /// module — a getter for it would be a door nobody needs.
  /// It therefore gets a domain-separated child, exactly as the
  /// cell keys get one.
  ///
  /// **Does NOT change the wire format.** No bytes are added and
  /// no existing derivation changes; the golden vectors in
  /// `smoke_link_kdf.dart` remain valid.
  static Uint8List deriveDeliveryKey(Uint8List linkKey) =>
      _deriveDirectional(linkKey, infoDelivery);

  /// Derives the responder→initiator cell key from [linkKey].
  static Uint8List deriveCellKeyResp(Uint8List linkKey) =>
      _deriveDirectional(linkKey, infoCellResp);

  static Uint8List _deriveDirectional(Uint8List linkKey, String label) {
    if (linkKey.length != 32) {
      throw ArgumentError(
          'link_key must be 32 bytes, got ${linkKey.length}');
    }
    return _sodium.hkdfSha256(
      linkKey,
      salt: _salt,
      info: Uint8List.fromList(utf8.encode(label)),
      length: 32,
    );
  }
}
