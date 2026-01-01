import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;

// ---------------------------------------------------------------------------
// Contact model + verification-level state machine (Architecture Section 5.5).
//
// This file deliberately contains NO contact store and NO persistence.
//
// There is exactly one contact store in the app: the encrypted `ContactInfo`
// map in `CleonaService` (`contacts.json.enc`, XSalsa20-Poly1305, audited on
// load by `_auditContactTrustAnchors()`). Every trust-anchor overwrite goes
// through the single private setter `CleonaService._setContactTrustAnchor`,
// which enforces the §8.3 guarantees (self-key rejection, hybrid-pair
// completeness, `source` provenance) and the §8.3 key-change-detection path.
//
// A former `ContactManager` in this file kept a SECOND, parallel store
// (`Map<String, Contact>` -> plaintext `contacts.json`) with its own
// trust-anchor overwrite paths that bypassed all of the above. It was
// unreachable from production code and has been removed rather than migrated:
// §8.3 permits only one overwrite path, so a migrated manager would have been
// a pure facade over CleonaService plus a second place to maintain. The
// verification-level transitions it owned survive below as pure, in-memory
// methods on [Contact] — same state machine, no store, no disk write.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Contact status enum
// ---------------------------------------------------------------------------

enum ContactStatus { pending, accepted, rejected }

// ---------------------------------------------------------------------------
// Contact verification level (Architecture Section 5.5)
// ---------------------------------------------------------------------------

/// Four levels of contact verification trust, from weakest to strongest.
///
/// The app prominently displays the verification status of each contact.
/// Unverified contacts show a subtle warning. If a contact's key changes
/// (e.g., they reinstalled the app), a prominent notification appears.
enum VerificationLevel {
  /// Contact added via Node-ID only. No key exchange completed.
  unverified,

  /// Key exchange completed successfully (contact request accepted,
  /// crypto keys received and used for at least one message).
  seen,

  /// Verified in person via QR code or NFC — fingerprints matched.
  verified,

  /// Explicitly marked as trusted by user (highest level).
  trusted,
}

// ---------------------------------------------------------------------------
// Contact model
// ---------------------------------------------------------------------------

class Contact {
  final Uint8List nodeId;
  String displayName;
  Uint8List? ed25519Pk;
  Uint8List? mlDsaPk;
  Uint8List? x25519Pk;
  Uint8List? mlKemPk;
  Uint8List? profilePicture;
  String? description;
  ContactStatus status;
  final DateTime addedAt;

  /// Verification level (Architecture Section 5.5).
  VerificationLevel verificationLevel;

  /// SHA-256 fingerprint of the contact's Ed25519 public key at verification time.
  /// Used to detect key changes after verification (key change warning).
  String? verifiedKeyFingerprint;

  Contact({
    required this.nodeId,
    required this.displayName,
    this.ed25519Pk,
    this.mlDsaPk,
    this.x25519Pk,
    this.mlKemPk,
    this.profilePicture,
    this.description,
    this.status = ContactStatus.pending,
    this.verificationLevel = VerificationLevel.unverified,
    this.verifiedKeyFingerprint,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  String get nodeIdHex => bytesToHex(nodeId);

  /// §7.1 LD-4: cached delegated signing keys from the contact's AuthManifest.
  /// Transient (not persisted) — repopulated on each AuthManifest reception.
  List<({Uint8List edPk, Uint8List mlDsaPk})> delegatedKeys = [];

  /// Whether this contact's key has changed since verification.
  /// Only meaningful for [VerificationLevel.verified] or [VerificationLevel.trusted].
  bool get hasKeyChanged {
    if (verifiedKeyFingerprint == null) return false;
    if (ed25519Pk == null) return false;
    return _computeKeyFingerprint(ed25519Pk!) != verifiedKeyFingerprint;
  }

  /// Compute the comparison fingerprint of a public key (hex-encoded).
  ///
  /// Simple SHA-256 via manual computation is not available here, so a
  /// truncated hex prefix of the key bytes is used for comparison. Callers
  /// that have SodiumFFI available pass the full SHA-256 fingerprint
  /// explicitly via the `keyFingerprint` parameter of [markVerified] /
  /// [markTrusted]; this fallback only has to be stable and collision-free
  /// enough to detect a changed key.
  static String _computeKeyFingerprint(Uint8List publicKey) {
    return bytesToHex(publicKey).substring(0, 16);
  }

  // ── Verification-level transitions (Architecture Section 5.5) ────────────
  //
  // Pure in-memory mutations of THIS contact. No store lookup, no callbacks,
  // no disk write — see the file header for why. Persisting the result is the
  // caller's job and, in production, goes through CleonaService's encrypted
  // ContactInfo store.

  /// Promote to [VerificationLevel.seen] after a successful key exchange.
  ///
  /// Never downgrades: a no-op if the contact is already at `seen` or higher.
  void promoteToSeen() {
    if (verificationLevel.index >= VerificationLevel.seen.index) return;
    verificationLevel = VerificationLevel.seen;
  }

  /// Mark as verified (in-person QR/NFC verification).
  ///
  /// Records the fingerprint of the current Ed25519 key so a later key change
  /// can be detected by [hasKeyChanged] / [checkKeyChanges].
  void markVerified({String? keyFingerprint}) {
    verificationLevel = VerificationLevel.verified;
    verifiedKeyFingerprint = keyFingerprint ??
        (ed25519Pk != null ? _computeKeyFingerprint(ed25519Pk!) : null);
  }

  /// Mark as trusted (explicit user action, highest level).
  void markTrusted({String? keyFingerprint}) {
    verificationLevel = VerificationLevel.trusted;
    verifiedKeyFingerprint = keyFingerprint ??
        (ed25519Pk != null ? _computeKeyFingerprint(ed25519Pk!) : null);
  }

  /// Reset to [VerificationLevel.unverified] and drop the pinned fingerprint.
  void resetVerification() {
    verificationLevel = VerificationLevel.unverified;
    verifiedKeyFingerprint = null;
  }

  /// §8.3 key-change reaction for a verified/trusted contact.
  ///
  /// If the pinned fingerprint no longer matches [ed25519Pk], the contact is
  /// downgraded to [VerificationLevel.seen], the pin is cleared, and the OLD
  /// fingerprint is returned so the caller can raise the key-change warning.
  /// Returns null when there is nothing to react to (level below `verified`,
  /// no pin, or key unchanged).
  String? checkKeyChanges() {
    if (verificationLevel.index < VerificationLevel.verified.index) return null;
    if (verifiedKeyFingerprint == null) return null;
    if (!hasKeyChanged) return null;
    final oldFp = verifiedKeyFingerprint!;
    verificationLevel = VerificationLevel.seen;
    verifiedKeyFingerprint = null;
    return oldFp;
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': bytesToHex(nodeId),
      'displayName': displayName,
      'ed25519Pk': ed25519Pk != null ? bytesToHex(ed25519Pk!) : null,
      'mlDsaPk': mlDsaPk != null ? bytesToHex(mlDsaPk!) : null,
      'x25519Pk': x25519Pk != null ? bytesToHex(x25519Pk!) : null,
      'mlKemPk': mlKemPk != null ? bytesToHex(mlKemPk!) : null,
      'profilePicture':
          profilePicture != null ? base64Encode(profilePicture!) : null,
      'description': description,
      'status': status.name,
      'addedAt': addedAt.millisecondsSinceEpoch,
      'verificationLevel': verificationLevel.name,
      'verifiedKeyFingerprint': verifiedKeyFingerprint,
    };
  }

  static Contact fromJson(Map<String, dynamic> json) {
    return Contact(
      nodeId: hexToBytes(json['nodeId'] as String),
      displayName: json['displayName'] as String? ?? '',
      ed25519Pk: json['ed25519Pk'] != null
          ? hexToBytes(json['ed25519Pk'] as String)
          : null,
      mlDsaPk: json['mlDsaPk'] != null
          ? hexToBytes(json['mlDsaPk'] as String)
          : null,
      x25519Pk: json['x25519Pk'] != null
          ? hexToBytes(json['x25519Pk'] as String)
          : null,
      mlKemPk: json['mlKemPk'] != null
          ? hexToBytes(json['mlKemPk'] as String)
          : null,
      profilePicture: json['profilePicture'] != null
          ? base64Decode(json['profilePicture'] as String)
          : null,
      description: json['description'] as String?,
      status: ContactStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'pending'),
        orElse: () => ContactStatus.pending,
      ),
      addedAt: DateTime.fromMillisecondsSinceEpoch(
          json['addedAt'] as int? ?? 0),
      verificationLevel: VerificationLevel.values.firstWhere(
        (e) => e.name == (json['verificationLevel'] as String? ?? 'unverified'),
        orElse: () => VerificationLevel.unverified,
      ),
      verifiedKeyFingerprint: json['verifiedKeyFingerprint'] as String?,
    );
  }

  @override
  String toString() =>
      'Contact(${nodeIdHex.substring(0, 8)}.. "$displayName" $status)';
}
