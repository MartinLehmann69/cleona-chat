import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// A single ephemeral in-call chat message.
class CallChatEntry {
  final Uint8List messageId;
  final String senderIdHex;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final Uint8List? replyToId;

  CallChatEntry({
    required this.messageId,
    required this.senderIdHex,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.replyToId,
  });

  String get messageIdHex => bytesToHex(messageId);
}

/// Manages ephemeral in-call chat (Architecture S10.5.3.2).
///
/// - NOT persisted after call ends (unless explicitly saved)
/// - Does NOT flow through S&F/Mailbox
/// - Encrypted with call key, distributed via Overlay Multicast Tree
class CallChatManager {
  final String ownUserIdHex;
  final String ownDisplayName;
  final String profileDir;
  final CLogger _log;

  /// All chat messages in order.
  final List<CallChatEntry> messages = [];

  /// Callback to send to all call participants.
  void Function(proto.MessageTypeV3 type, Uint8List payload)? onSendToAll;

  /// UI callback when a new message arrives.
  void Function(CallChatEntry message)? onMessageReceived;

  /// Unread count (reset by UI when chat is viewed).
  int unreadCount = 0;

  CallChatManager({
    required this.ownUserIdHex,
    required this.ownDisplayName,
    required this.profileDir,
  }) : _log = CLogger.get('call-chat', profileDir: profileDir);

  /// Send a chat message to all call participants.
  void sendMessage(String text, {Uint8List? replyToId}) {
    if (text.trim().isEmpty) return;

    final messageId = SodiumFFI().randomBytes(16);
    final entry = CallChatEntry(
      messageId: messageId,
      senderIdHex: ownUserIdHex,
      senderName: ownDisplayName,
      text: text.trim(),
      timestamp: DateTime.now(),
      replyToId: replyToId,
    );

    messages.add(entry);

    final msg = proto.CallChatMessage()
      ..messageId = messageId
      ..senderId = hexToBytes(ownUserIdHex)
      ..senderName = ownDisplayName
      ..text = text.trim()
      ..timestamp = Int64(entry.timestamp.millisecondsSinceEpoch);
    if (replyToId != null && replyToId.isNotEmpty) {
      msg.replyToId = replyToId;
    }

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_CALL_CHAT,
      msg.writeToBuffer(),
    );

    onMessageReceived?.call(entry);
    _log.debug('Chat sent: ${text.substring(0, text.length.clamp(0, 40))}');
  }

  /// Handle incoming chat message from a remote participant.
  void handleRemoteMessage(proto.CallChatMessage msg) {
    final senderHex = bytesToHex(Uint8List.fromList(msg.senderId));

    // Ignore own echoed messages
    if (senderHex == ownUserIdHex) return;

    final entry = CallChatEntry(
      messageId: Uint8List.fromList(msg.messageId),
      senderIdHex: senderHex,
      senderName: msg.senderName,
      text: msg.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestamp.toInt()),
      replyToId:
          msg.replyToId.isEmpty ? null : Uint8List.fromList(msg.replyToId),
    );

    messages.add(entry);
    unreadCount++;
    onMessageReceived?.call(entry);
    _log.debug('Chat received from ${senderHex.substring(0, 8)}: '
        '${msg.text.substring(0, msg.text.length.clamp(0, 40))}');
  }

  /// Find a message by its ID (for reply display).
  CallChatEntry? findMessage(Uint8List messageId) {
    final hex = bytesToHex(messageId);
    for (final m in messages) {
      if (m.messageIdHex == hex) return m;
    }
    return null;
  }

  /// Clear all messages (call ended).
  void dispose() {
    messages.clear();
    unreadCount = 0;
  }
}
