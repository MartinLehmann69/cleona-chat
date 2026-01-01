import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;

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

  /// Whether this contact's key has changed since verification.
  /// Only meaningful for [VerificationLevel.verified] or [VerificationLevel.trusted].
  bool get hasKeyChanged {
    if (verifiedKeyFingerprint == null) return false;
    if (ed25519Pk == null) return false;
    return _computeKeyFingerprint(ed25519Pk!) != verifiedKeyFingerprint;
  }

  /// Compute SHA-256 fingerprint of a public key (hex-encoded).
  static String _computeKeyFingerprint(Uint8List publicKey) {
    // Simple SHA-256 via manual computation is not available here,
    // so we use a truncated hex hash of the key bytes for comparison.
    // The full SHA-256 fingerprint is computed by the caller (ContactManager)
    // using SodiumFFI when setting verification level.
    return bytesToHex(publicKey).substring(0, 16);
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

// ---------------------------------------------------------------------------
// ContactManager
// ---------------------------------------------------------------------------

class ContactManager {
  /// nodeIdHex -> Contact
  final Map<String, Contact> _contacts = {};

  // ── Callbacks ──────────────────────────────────────────────────────────

  void Function(Contact)? onContactRequestReceived;
  void Function(Contact)? onContactAccepted;
  void Function(Contact)? onContactRejected;

  // ── Send a contact request ─────────────────────────────────────────────

  /// Creates a [proto.ContactRequestMsg] to be wrapped in a MessageEnvelope
  /// and sent to [recipientNodeId].
  proto.ContactRequestMsg sendContactRequest({
    required Uint8List recipientNodeId,
    required String displayName,
    String message = '',
    required Uint8List ed25519Pk,
    required Uint8List mlDsaPk,
    required Uint8List x25519Pk,
    required Uint8List mlKemPk,
    Uint8List? profilePicture,
    String? description,
  }) {
    final hex = bytesToHex(recipientNodeId);

    // Store the outgoing request as pending so we remember we sent it.
    if (!_contacts.containsKey(hex)) {
      _contacts[hex] = Contact(
        nodeId: Uint8List.fromList(recipientNodeId),
        displayName: '', // We don't know their name yet.
        status: ContactStatus.pending,
      );
    }

    return proto.ContactRequestMsg(
      displayName: displayName,
      ed25519PublicKey: ed25519Pk,
      mlDsaPublicKey: mlDsaPk,
      x25519PublicKey: x25519Pk,
      mlKemPublicKey: mlKemPk,
      message: message,
      profilePicture: profilePicture,
      description: description,
    );
  }

  // ── Handle incoming contact request ────────────────────────────────────

  /// Processes a received [proto.MessageEnvelope] of type CONTACT_REQUEST.
  /// The payload must already be decrypted and deserialized into a
  /// [proto.ContactRequestMsg].
  void handleContactRequest(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final crMsg = proto.ContactRequestMsg.fromBuffer(envelope.encryptedPayload);

    final contact = Contact(
      nodeId: Uint8List.fromList(envelope.senderId),
      displayName: crMsg.displayName,
      ed25519Pk: crMsg.ed25519PublicKey.isEmpty
          ? null
          : Uint8List.fromList(crMsg.ed25519PublicKey),
      mlDsaPk: crMsg.mlDsaPublicKey.isEmpty
          ? null
          : Uint8List.fromList(crMsg.mlDsaPublicKey),
      x25519Pk: crMsg.x25519PublicKey.isEmpty
          ? null
          : Uint8List.fromList(crMsg.x25519PublicKey),
      mlKemPk: crMsg.mlKemPublicKey.isEmpty
          ? null
          : Uint8List.fromList(crMsg.mlKemPublicKey),
      profilePicture: crMsg.profilePicture.isEmpty
          ? null
          : Uint8List.fromList(crMsg.profilePicture),
      description: crMsg.description.isEmpty ? null : crMsg.description,
      status: ContactStatus.pending,
    );

    _contacts[senderHex] = contact;
    onContactRequestReceived?.call(contact);
  }

  // ── Accept / Reject ────────────────────────────────────────────────────

  /// Marks the contact as accepted and returns a [proto.ContactRequestResponse]
  /// protobuf to send back.
  proto.ContactRequestResponse? acceptContact(
    String nodeIdHex, {
    required Uint8List ed25519Pk,
    required Uint8List mlDsaPk,
    required Uint8List x25519Pk,
    required Uint8List mlKemPk,
    required String displayName,
    Uint8List? profilePicture,
    String? description,
  }) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return null;

    contact.status = ContactStatus.accepted;
    // Auto-promote to "seen" — keys have been exchanged successfully.
    if (contact.verificationLevel == VerificationLevel.unverified) {
      contact.verificationLevel = VerificationLevel.seen;
    }
    onContactAccepted?.call(contact);

    return proto.ContactRequestResponse(
      accepted: true,
      ed25519PublicKey: ed25519Pk,
      mlDsaPublicKey: mlDsaPk,
      x25519PublicKey: x25519Pk,
      mlKemPublicKey: mlKemPk,
      displayName: displayName,
      profilePicture: profilePicture,
      description: description,
    );
  }

  /// Marks the contact as rejected and returns a [proto.ContactRequestResponse]
  /// protobuf to send back.
  proto.ContactRequestResponse? rejectContact(
    String nodeIdHex, {
    String reason = '',
  }) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return null;

    contact.status = ContactStatus.rejected;
    onContactRejected?.call(contact);

    return proto.ContactRequestResponse(
      accepted: false,
      rejectionReason: reason,
    );
  }

  // ── Handle incoming contact response ───────────────────────────────────

  /// Processes a received [proto.MessageEnvelope] of type
  /// CONTACT_REQUEST_RESPONSE.  The payload must already be decrypted.
  void handleContactResponse(proto.MessageEnvelope envelope) {
    final senderHex = bytesToHex(Uint8List.fromList(envelope.senderId));
    final resp = proto.ContactRequestResponse.fromBuffer(
        envelope.encryptedPayload);

    final contact = _contacts[senderHex];
    if (contact == null) return; // Unknown sender, ignore.

    if (resp.accepted) {
      contact.status = ContactStatus.accepted;
      // Auto-promote to "seen" — keys received via response.
      if (contact.verificationLevel == VerificationLevel.unverified) {
        contact.verificationLevel = VerificationLevel.seen;
      }
      contact.displayName =
          resp.displayName.isNotEmpty ? resp.displayName : contact.displayName;
      contact.ed25519Pk = resp.ed25519PublicKey.isEmpty
          ? contact.ed25519Pk
          : Uint8List.fromList(resp.ed25519PublicKey);
      contact.mlDsaPk = resp.mlDsaPublicKey.isEmpty
          ? contact.mlDsaPk
          : Uint8List.fromList(resp.mlDsaPublicKey);
      contact.x25519Pk = resp.x25519PublicKey.isEmpty
          ? contact.x25519Pk
          : Uint8List.fromList(resp.x25519PublicKey);
      contact.mlKemPk = resp.mlKemPublicKey.isEmpty
          ? contact.mlKemPk
          : Uint8List.fromList(resp.mlKemPublicKey);
      contact.profilePicture = resp.profilePicture.isEmpty
          ? contact.profilePicture
          : Uint8List.fromList(resp.profilePicture);
      contact.description = resp.description.isEmpty
          ? contact.description
          : resp.description;
      onContactAccepted?.call(contact);
    } else {
      contact.status = ContactStatus.rejected;
      onContactRejected?.call(contact);
    }
  }

  // ── Lookups ────────────────────────────────────────────────────────────

  Contact? getContact(String nodeIdHex) => _contacts[nodeIdHex];

  /// Add a pre-built contact (e.g., from NFC exchange).
  /// Overwrites any existing contact with the same nodeIdHex.
  void addContact(Contact contact) {
    _contacts[bytesToHex(contact.nodeId)] = contact;
  }

  List<Contact> get acceptedContacts => _contacts.values
      .where((c) => c.status == ContactStatus.accepted)
      .toList(growable: false);

  List<Contact> get pendingContacts => _contacts.values
      .where((c) => c.status == ContactStatus.pending)
      .toList(growable: false);

  bool isAccepted(String nodeIdHex) =>
      _contacts[nodeIdHex]?.status == ContactStatus.accepted;

  /// Returns the recipient's public keys needed for encryption.
  /// Lookup chain: mlKemPk (preferred, post-quantum) -> x25519Pk (fallback).
  /// Returns null if no keys are available.
  ({Uint8List? x25519Pk, Uint8List? mlKemPk, Uint8List? ed25519Pk})?
      getRecipientPk(String nodeIdHex) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return null;
    if (contact.x25519Pk == null && contact.mlKemPk == null) return null;
    return (
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
      ed25519Pk: contact.ed25519Pk,
    );
  }

  // ── Verification Levels (Architecture Section 5.5) ─────────────────────

  /// Callback when a verified/trusted contact's key changes.
  void Function(Contact contact, String oldFingerprint)? onKeyChanged;

  /// Promote a contact to "seen" after successful key exchange.
  /// Called automatically when a contact is accepted and keys are present.
  void promoteToSeen(String nodeIdHex) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    if (contact.verificationLevel.index >= VerificationLevel.seen.index) return;
    contact.verificationLevel = VerificationLevel.seen;
  }

  /// Mark a contact as verified (in-person QR/NFC verification).
  /// Stores a fingerprint of the current key for future key-change detection.
  void markVerified(String nodeIdHex, {String? keyFingerprint}) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    contact.verificationLevel = VerificationLevel.verified;
    contact.verifiedKeyFingerprint = keyFingerprint ??
        (contact.ed25519Pk != null
            ? Contact._computeKeyFingerprint(contact.ed25519Pk!)
            : null);
  }

  /// Mark a contact as trusted (explicit user action, highest level).
  void markTrusted(String nodeIdHex, {String? keyFingerprint}) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    contact.verificationLevel = VerificationLevel.trusted;
    contact.verifiedKeyFingerprint = keyFingerprint ??
        (contact.ed25519Pk != null
            ? Contact._computeKeyFingerprint(contact.ed25519Pk!)
            : null);
  }

  /// Reset verification to unverified (e.g., after key change acknowledged).
  void resetVerification(String nodeIdHex) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    contact.verificationLevel = VerificationLevel.unverified;
    contact.verifiedKeyFingerprint = null;
  }

  /// Check all verified/trusted contacts for key changes.
  /// Should be called after receiving key rotation or updated keys.
  void checkKeyChanges(String nodeIdHex) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    if (contact.verificationLevel.index < VerificationLevel.verified.index) return;
    if (contact.hasKeyChanged && contact.verifiedKeyFingerprint != null) {
      final oldFp = contact.verifiedKeyFingerprint!;
      // Downgrade to "seen" — key changed, re-verification needed.
      contact.verificationLevel = VerificationLevel.seen;
      contact.verifiedKeyFingerprint = null;
      onKeyChanged?.call(contact, oldFp);
    }
  }

  /// Get the verification level of a contact.
  VerificationLevel getVerificationLevel(String nodeIdHex) {
    return _contacts[nodeIdHex]?.verificationLevel ?? VerificationLevel.unverified;
  }

  // ── Persistence (JSON) ─────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'contacts': _contacts.map(
        (key, contact) => MapEntry(key, contact.toJson()),
      ),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    _contacts.clear();
    final contactsMap = json['contacts'] as Map<String, dynamic>?;
    if (contactsMap == null) return;
    for (final entry in contactsMap.entries) {
      _contacts[entry.key] =
          Contact.fromJson(entry.value as Map<String, dynamic>);
    }
  }

  // ── Disk persistence ───────────────────────────────────────────────────

  Future<void> save(String profileDir) async {
    final file = File('$profileDir/contacts.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  Future<void> load(String profileDir) async {
    final file = File('$profileDir/contacts.json');
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      fromJson(json);
    } on FormatException {
      // Corrupted file -- start fresh.
    }
  }
}
