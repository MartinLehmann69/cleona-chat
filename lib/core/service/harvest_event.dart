import 'dart:typed_data';

import 'package:cleona/core/service/sender_identity_snapshot.dart';
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// Length of the file identifier a waiting message carries (§9.4 "Nothing
/// overtakes a file": "carries the file's identifier (8 B)").
const int kAfterFileLength = 8;

/// Length of the post identifier of a group post (§16.2: "The author draws
/// 16 random bytes per post and carries them in every leg").
const int kPostIdLength = 16;

/// Length of the DELIVERY identifier a mycelium message carries
/// (`mycelium/lib/message.dart`, `kIdentifierLength`) — the same 8 B the
/// identity's received memory keeps a row of (§20.2, `received_ids`,
/// schema 4). NOT the length of [HarvestEvent.messageId].
const int kDeliveryIdLength = 8;

/// V4 architecture §15.5.3 — the receive side of the seam.
///
/// **Normative (§15.5.3):** the application layer sees no wire frame. What a
/// handler receives is this service value type, which the network layer fills
/// from the harvested spore. A handler that carries a transport type in its
/// signature is a seam violation of the same class as a second send path
/// (§15.5).
///
/// Counterpart of [proto.MessageTypeV3]-carrying `sendToUser` on the send
/// side: `PlantOutcome` goes out, [HarvestEvent] comes in.
///
/// **Field list is measured, not designed** (migration plan §4a.4): it holds
/// exactly what the layer above the seam actually reads. Protocol version,
/// signature bytes, compression method and erasure metadata are never read
/// there, so they are absent. Sender address and port are absent for a second
/// reason as well: Plane F is address-free (§4.5, §15.5.2). A cross-check over
/// the eight files above the seam confirms this — `InternetAddress`/port occur
/// in signatures there but are never consumed; the sole consumer is the
/// `wasDirect` derivation, which happens at the seam entry itself.
class HarvestEvent {
  /// Who, as an identity.
  final Uint8List senderUserId;

  /// From which DEVICE the message came — or `null`.
  ///
  /// ── WHY OPTIONAL (B-32, S349) ─────────────────────────────────────
  ///
  /// §14.1 is unambiguous: "The DeviceID is **not an addressing means** …
  /// it is a **subject**, not a **signpost** — for authorization,
  /// revocation, and attribution." And §14.2: "One delivery serves all
  /// devices. The delivery path has **no device level**."
  ///
  /// V4.1 delivery adheres to that — `lib/core/tagline/` knows the device
  /// identifier with zero hits. A harvested cell says from which IDENTITY
  /// it comes, and nothing else. There is no field from which a device
  /// could be derived, and there shall be none.
  ///
  /// Until S349 this field was not optional, and the V4.1 receive path
  /// therefore filled it with the **UserID** — a white lie with
  /// consequences: the contact request path enters `senderDeviceId` into
  /// `ContactInfo.deviceNodeIds`, and this list serves as a ROUTING TARGET
  /// in the send path. Requests received via V4.1 thus polluted the device
  /// list with identity identifiers, and the V3 path then tried to route
  /// to a UserID.
  ///
  /// `null` now honestly means: **this path knows no device.** Whoever
  /// reads the field must handle the case — and whoever needs it for
  /// attribution (twin sync, locking, quorum) notices from the type system
  /// that the information can be missing.
  final Uint8List? senderDeviceId;

  /// **V3 transitional:** §15.5.3 specifies `MessageType`. The rename of
  /// `MessageTypeV3` is work package AP-3 (migration plan §4a.2, class A: the
  /// seam carries the message type by construction, so this is not a seam
  /// violation — it is a rename that has not happened yet).
  final proto.MessageTypeV3 type;

  /// The raw type number when THIS build's [proto.MessageTypeV3] does not
  /// know it, otherwise `null`.
  ///
  /// protobuf keeps an unknown enum value in `unknownFields` and leaves the
  /// field unset, so [type] then reads the zero value `MTV3_TEXT` (the same
  /// measurement as `twinSyncTypeIsUnknown` in `twin_sync_wire.dart`). A
  /// frame of a reserved or future type would be shown as a text message
  /// made of its payload bytes. `handleApplicationFrame` discards every event
  /// that carries a value here (S398, finding R-1: the reserved restore
  /// types 30 and 31).
  final int? unknownType;

  /// Decompressed, decrypted, signature-checked.
  final Uint8List payload;

  final Uint8List messageId;

  /// LOCAL arrival time, observed. Per §22.5.3 the only time value that
  /// display, sorting and expiry rules may rely on. The bubble of a received
  /// text, reply, channel post, lane 1 file and file announcement takes its
  /// timestamp from here (`smoke_display_time_arrival.dart`).
  final DateTime harvestedAt;

  /// The sender's own assertion, with no evidence behind it. Anyone who sorts
  /// by this sorts by something the sender is free to choose (§22.5.3).
  ///
  /// Two readers remain, neither of them display, sorting or expiry: the age
  /// of a call `INVITE` (`call_service.dart`) and the notification quiet
  /// rule of the start phase (`CleonaService._claimedSendTimeMs`).
  final DateTime? claimedSentAt;

  /// Set for group and channel traffic, `null` for direct messages.
  final Uint8List? groupId;

  /// Epoch plus roster hash (§2.5). **OPEN (§15-O-6):** whether the layer
  /// above the seam needs this at all — the deterministic `K_AB` derivation
  /// may answer "was the sender a member at that time?" without it. Two call
  /// sites read it today; decision falls with AP-4.
  final RosterVersion? rosterVersion;

  final proto.ContentMetadata? contentMetadata;

  /// Result of the signature check. Mandatory field, not a side channel: it
  /// decides whether a handler may act in a trust-elevating way (§15.5.3).
  final SenderTrust senderTrust;

  /// §9.4 "Nothing overtakes a file" (D-34, S398-W5): the message waited at
  /// the sender behind the file whose message identifier starts with these
  /// 8 bytes (same conversation, same leg). `null` for every other message.
  final Uint8List? afterFile;

  /// §16.2 "A group post carries one post identifier": the 16 bytes the
  /// author drew for this group post, the same in every leg. `null` for
  /// everything that is not a group post, and for a group post of a sender
  /// that does not carry the field — such a post is known by the identifier
  /// of its leg only.
  final Uint8List? postId;

  /// The 8-byte DELIVERY identifier of the delivery that carried this
  /// frame — drawn by the sender's mycelium per message; retries carry
  /// the same one (D-44). **NOT the 16-byte [messageId]**: that names
  /// the MESSAGE, and an edit or a deletion travels under the identifier
  /// of its target (§20.2, S403 decision 1).
  ///
  /// `null` when the layer below the seam has ALREADY kept this
  /// identifier — mycelium marks every inbound of a sender it knows
  /// (contact, group pair, or a sender the application has marked) in
  /// the identity's received memory before the callback — or when the
  /// caller has no delivery context at all (a direct call, a replay in
  /// a guard). Then the receive path checks and keeps NOTHING, by
  /// contract: no layer keeps an identifier twice, and no direct call
  /// needs a delivery to measure a handler.
  final Uint8List? deliveryId;

  const HarvestEvent({
    required this.senderUserId,
    required this.senderDeviceId,
    required this.type,
    required this.payload,
    required this.messageId,
    required this.harvestedAt,
    required this.claimedSentAt,
    required this.groupId,
    required this.rosterVersion,
    required this.contentMetadata,
    required this.senderTrust,
    this.afterFile,
    this.postId,
    this.deliveryId,
    this.unknownType,
  });

  /// [postId] as the hex form a message is kept under, or `null`.
  String? get postIdHex => postId == null ? null : bytesToHex(postId!);

  /// Returns a copy with [contentMetadata] replaced. The type is immutable by
  /// design (§15.5.3 makes the event an observation, not a mutable buffer);
  /// the one handler that needs a derived value is the VOICE_MESSAGE default,
  /// which must not write into the received frame — see
  /// `test/smoke/smoke_voice_metadata_default.dart` for why.
  HarvestEvent withContentMetadata(proto.ContentMetadata? metadata) {
    return HarvestEvent(
      senderUserId: senderUserId,
      senderDeviceId: senderDeviceId,
      type: type,
      payload: payload,
      messageId: messageId,
      harvestedAt: harvestedAt,
      claimedSentAt: claimedSentAt,
      groupId: groupId,
      rosterVersion: rosterVersion,
      contentMetadata: metadata,
      senderTrust: senderTrust,
      afterFile: afterFile,
      postId: postId,
      deliveryId: deliveryId,
      unknownType: unknownType,
    );
  }

  /// **V3 scaffolding — dies with AP-3.** Fills the event from the V3 wire
  /// frame plus the two parameters that travelled beside it. This adapter is
  /// the whole point of AP-1: it is the single place where the wire frame is
  /// read, so the layer above never sees one.
  /// [senderDeviceId] may be `null` — see the field description above.
  /// The V4.1 receive path passes `null` in here, because a harvested cell
  /// names no device; the V3 path passes in the identifier from the outer
  /// packet.
  factory HarvestEvent.fromV3Frame({
    required proto.ApplicationFrameV3 frame,
    required Uint8List? senderDeviceId,
    required SenderIdentitySnapshot snapshot,
    Uint8List? deliveryId,
  }) {
    return HarvestEvent(
      senderUserId: Uint8List.fromList(frame.senderUserId),
      senderDeviceId: senderDeviceId,
      type: frame.messageType,
      payload: Uint8List.fromList(frame.payload),
      messageId: Uint8List.fromList(frame.messageId),
      // Observed arrival: the snapshot records wall-clock at packet arrival,
      // after the timestamp-window check. That is the observation;
      // `DateTime.now()` here would be a second, later one.
      harvestedAt: snapshot.receivedAt,
      claimedSentAt: frame.timestampMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(frame.timestampMs.toInt()),
      groupId:
          frame.groupId.isEmpty ? null : Uint8List.fromList(frame.groupId),
      rosterVersion: RosterVersion.fromV3Frame(frame),
      contentMetadata: frame.hasContentMetadata() ? frame.contentMetadata : null,
      senderTrust: _trustFromV3(snapshot),
      // Exactly 8 bytes or nothing: any other length names no file.
      afterFile: frame.afterFile.length == kAfterFileLength
          ? Uint8List.fromList(frame.afterFile)
          : null,
      // Exactly 16 bytes in a frame that names a group, or nothing (§16.2):
      // only a group post carries a post identifier.
      postId: frame.postId.length == kPostIdLength && frame.groupId.isNotEmpty
          ? Uint8List.fromList(frame.postId)
          : null,
      // Exactly 8 bytes or nothing: any other length names no delivery,
      // and without one the receive path checks and keeps nothing (see
      // the field).
      deliveryId: deliveryId != null && deliveryId.length == kDeliveryIdLength
          ? Uint8List.fromList(deliveryId)
          : null,
      unknownType: _unknownFrameType(frame),
    );
  }

  /// The field number of `ApplicationFrameV3.message_type`
  /// (`proto/transport_v3.proto`).
  static const int _kFrameTypeField = 6;

  static int? _unknownFrameType(proto.ApplicationFrameV3 frame) {
    final raw = frame.unknownFields.getField(_kFrameTypeField);
    if (raw == null || raw.varints.isEmpty) return null;
    return raw.varints.last.toInt();
  }

  /// V3 has two reachable outcomes, not three.
  ///
  /// `OuterSigStatus.skippedWhitelist` is unreachable by its own
  /// documentation ("V3.0 Welle 6 chose Variant B over the Pre-Verify
  /// whitelist; this status is currently unreachable").
  ///
  /// [SenderTrust.keyChanged] has **no producer** in V3: the snapshot field
  /// meant to carry it, `newKeyDetectedForSenderUser`, is documented as "set
  /// best-effort by inner handlers" but is passed `false` at all three of its
  /// construction sites in `cleona_node.dart`, and the `withNewKeyDetected`
  /// transformer that would flip it is never called. Key-change detection
  /// does happen, but through contact-store comparison inside the
  /// contact-request handlers, not through this field. The enum value stays
  /// because §15.5.3 specifies it; the mapping does not invent a producer.
  static SenderTrust _trustFromV3(SenderIdentitySnapshot snapshot) {
    if (snapshot.newKeyDetectedForSenderUser) return SenderTrust.keyChanged;
    return snapshot.outerSigStatus == OuterSigStatus.verified
        ? SenderTrust.verified
        : SenderTrust.unknownKey;
  }
}

/// Which roster was in force: epoch plus roster hash (§2.5).
class RosterVersion {
  final int epoch;
  final Uint8List hash;

  const RosterVersion({required this.epoch, required this.hash});

  /// Returns `null` when the frame carries no membership state — an unset
  /// epoch is `0`, and a roster hash without an epoch is not a version.
  static RosterVersion? fromV3Frame(proto.ApplicationFrameV3 frame) {
    final epoch = frame.groupMembershipEpoch.toInt();
    if (epoch <= 0 || frame.groupMembershipHash.isEmpty) return null;
    return RosterVersion(
      epoch: epoch,
      hash: Uint8List.fromList(frame.groupMembershipHash),
    );
  }
}

/// Result of the signature check (§15.5.3).
enum SenderTrust {
  /// The signature checked out.
  verified,

  /// No key on file for this sender.
  unknownKey,

  /// The sender's keys differ from the ones on file. See the note on
  /// [HarvestEvent._trustFromV3]: no producer in V3.
  keyChanged,
}
