import 'dart:typed_data';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/dht/channel_index.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Shared context interface for extracted service modules.
///
/// CleonaService implements this and passes itself to sub-services
/// (ChannelModerationService, PollService, etc.) so they can read
/// shared state and call common operations without circular imports.
abstract class ServiceContext {
  IdentityContext get identity;
  CleonaNode get node;
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
    Uint8List? senderUserId,
    Uint8List? groupId,
    Uint8List? messageId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    proto.ErasureCodingMetadata? erasureMetadata,
    List<bool>? l3Result,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
  });

  void saveChannels();
  void saveConversations();
  void notifyStateChanged();

  Future<bool> publishChannelToIndex(String channelIdHex);

  bool hasChannelPermission(ChannelInfo channel, String action);

  bool get reducedMode;
  ModerationConfig get moderationConfig;
  FileEncryption get fileEnc;

  Future<void> sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  });

  void addMessageToConversation(String conversationId, UiMessage msg,
      {bool isGroup = false, bool isChannel = false});
}
