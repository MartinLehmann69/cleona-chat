import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/storage/channel_index.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;

/// Shared context interface for extracted service modules.
///
/// CleonaService implements this and passes itself to sub-services
/// (ChannelModerationService, PollService, etc.) so they can read
/// shared state and call common operations without circular imports.
abstract class ServiceContext {
  IdentityContext get identity;
  // `CleonaNode get node;` was dropped without replacement on 31.08. (CUT).
  //
  // THERE ARE READERS, and they are all V3. Re-measured over
  // `lib/core/service/`: `channel_moderation_service.dart:444,492,1612`,
  // `poll_service.dart:418,496,516,912,920` and `call_service.dart:172`
  // access via `_ctx.node` exclusively `routingTable`,
  // `sendInfraTo` and `primaryIdentity` — three members that were deleted with
  // `lib/core/node/`. These call sites therefore die
  // anyway; the type edge here just no longer keeps them alive.
  // `calendar_protocol_service.dart` does not read `node` at all.
  //
  // The replacement is NOT `V41Node` at this place: the V4.1 delivery
  // hangs off the service (`attachV41`), not off the context, and `sendToUser`
  // below is the path the sub-services are to take.
  String get profileDir;
  String get displayName;

  Map<String, ContactInfo> get contacts;
  Map<String, Conversation> get conversations;
  Map<String, GroupInfo> get groups;
  Map<String, ChannelInfo> get channels;
  ChannelIndex get channelIndex;

  Future<bool> sendToUser({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    // S368: here stood `Uint8List? senderUserId` — the
    // override parameter of the send site. Measured with a
    // bracket-balancing counter over `lib/`, `bin/` and `test/`:
    // zero `sendToUser(...)` calls passed it.
    Uint8List? groupId,
    Uint8List? messageId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    proto.ErasureCodingMetadata? erasureMetadata,
    List<bool>? l3Result,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    // When set, bypasses per-user device resolution/cache and sends only to
    // this specific device (e.g. a DELIVERY_RECEIPT addressed back to the
    // exact device that sent the original frame, not just any known device
    // of that user).
    Uint8List? targetDeviceId,
    // When true, skips Layer 3 offline delivery (S&F + Erasure). Used for
    // ephemeral signaling (call invites) that is useless when delayed.
    bool skipL3 = false,
    // ── THE 31-DAY RETENTION CLASS (§21.1) ──────────────────────────────
    //
    // §22.5.1 specifies at this seam a `TtlClass ttl = TtlClass.standard`
    // ("14 d default, 31 d administrative"). `TtlClass` does not exist in the code
    // (`grep -rn TtlClass lib/` — zero hits, S361); [management]
    // is the minimal equivalent with exactly two values.
    //
    // It is a parameter of the SEND SITE and not a property of the
    // message type: routine and emergency rotation share
    // `MTV3_KEY_ROTATION_BROADCAST`, and only the second is
    // management class (v4_1 l. 1007-1008 against §4.5.4 "an ordinary
    // delivery"). A classifier over `messageType` would therefore be
    // demonstrably wrong.
    //
    // Effective ONLY on the Secure path — the Speed onion stores nothing
    // that would have a deadline.
    bool management = false,
    // When non-null, receives one [SendLeg] per successfully built fan-out
    // leg so the caller can retransmit the identical packet without
    // re-running the inner crypto pipeline (see [SendLeg]).
    List<SendLeg>? outLegs,
    // Key overrides for non-contact group/channel members whose KEM keys
    // were received via GROUP_INVITE but who are not in _contacts.
    // When set, these take priority over the contact-record lookup so
    // that transitive members (invited by another admin) can be reached.
    Uint8List? recipientX25519PkOverride,
    Uint8List? recipientMlKemPkOverride,
    // Ed25519 PK override for L3 mailbox anchor (S&F/Erasure).
    Uint8List? recipientEd25519PkOverride,
  });

  void saveChannels();
  void saveConversations();

  /// Loads the history of a conversation lazily (S366, stage B).
  ///
  /// After start a conversation carries only its youngest message;
  /// whoever iterates over `conversation.messages` or searches in it calls this
  /// first. Without the call the search finds nothing and reports nothing —
  /// the error would be silent.
  void ensureLoaded(String conversationId);
  void notifyStateChanged();

  Future<bool> publishChannelToIndex(String channelIdHex);

  bool hasChannelPermission(ChannelInfo channel, String action);

  bool get reducedMode;
  ModerationConfig get moderationConfig;
  FileEncryption get fileEnc;

  /// The encrypted store of this identity (§21.4.1).
  ///
  /// It carries messages, conversations and — since the second part of
  /// S366 — the collections that used to have a JSON file each.
  MessageStore get store;

  Future<void> sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  });

  void addMessageToConversation(String conversationId, UiMessage msg,
      {bool isGroup = false, bool isChannel = false});
}
