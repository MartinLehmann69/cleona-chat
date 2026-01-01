import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex, hexToBytes;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// A shared file entry in the call.
class SharedFileEntry {
  final Uint8List fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final Uint8List? thumbnailData;
  final String sharedByHex;
  final String sharedByName;
  final DateTime sharedAt;

  /// Download state for this file.
  FileDownloadState downloadState;

  /// Local path after download.
  String? localPath;

  SharedFileEntry({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.thumbnailData,
    required this.sharedByHex,
    required this.sharedByName,
    required this.sharedAt,
    this.downloadState = FileDownloadState.available,
    this.localPath,
  });

  String get fileIdHex => bytesToHex(fileId);

  /// Human-readable file size.
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

enum FileDownloadState { available, downloading, completed, failed }

/// A clipboard exchange entry.
class ClipboardEntry {
  final String senderIdHex;
  final String senderName;
  final String contentType; // "text" or "image"
  final String? textContent;
  final Uint8List? imageData;
  final DateTime timestamp;

  ClipboardEntry({
    required this.senderIdHex,
    required this.senderName,
    required this.contentType,
    this.textContent,
    this.imageData,
    required this.timestamp,
  });
}

/// Manages file sharing and clipboard exchange during calls (Architecture S10.5.3).
///
/// - 50 MB max file size
/// - Max 20 concurrent shared files
/// - File metadata announced via Overlay Multicast Tree
/// - Actual download via existing Two-Stage Media (S5.7) encrypted with call key
class CallFileManager {
  final String ownUserIdHex;
  final String ownDisplayName;
  final String profileDir;
  final CLogger _log;

  /// Max file size: 50 MB.
  static const int maxFileSize = 50 * 1024 * 1024;

  /// Max concurrent files.
  static const int maxFiles = 20;

  /// All shared files.
  final List<SharedFileEntry> sharedFiles = [];

  /// Clipboard history.
  final List<ClipboardEntry> clipboardHistory = [];

  /// Callback to send to all call participants.
  void Function(proto.MessageTypeV3 type, Uint8List payload)? onSendToAll;

  /// UI callback when a file is shared.
  void Function(SharedFileEntry file)? onFileShared;

  /// UI callback when clipboard content is received.
  void Function(ClipboardEntry entry)? onClipboardReceived;

  CallFileManager({
    required this.ownUserIdHex,
    required this.ownDisplayName,
    required this.profileDir,
  }) : _log = CLogger.get('call-files', profileDir: profileDir);

  /// Share a file with all call participants.
  /// Returns null if limits exceeded.
  SharedFileEntry? shareFile({
    required String fileName,
    required int fileSize,
    required String mimeType,
    Uint8List? thumbnailData,
  }) {
    if (fileSize > maxFileSize) {
      _log.warn('File too large: $fileSize > $maxFileSize');
      return null;
    }
    if (sharedFiles.length >= maxFiles) {
      _log.warn('Max files reached: ${sharedFiles.length}');
      return null;
    }

    final fileId = SodiumFFI().randomBytes(16);
    final entry = SharedFileEntry(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      thumbnailData: thumbnailData,
      sharedByHex: ownUserIdHex,
      sharedByName: ownDisplayName,
      sharedAt: DateTime.now(),
    );

    sharedFiles.add(entry);

    final share = proto.CallFileShare()
      ..fileId = fileId
      ..fileName = fileName
      ..fileSize = Int64(fileSize)
      ..mimeType = mimeType
      ..sharedBy = hexToBytes(ownUserIdHex)
      ..sharedByName = ownDisplayName
      ..action = 0; // ANNOUNCE
    if (thumbnailData != null) {
      share.thumbnailData = thumbnailData;
    }

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_FILE_EXCHANGE,
      share.writeToBuffer(),
    );

    onFileShared?.call(entry);
    _log.info('File shared: $fileName ($fileSize bytes)');
    return entry;
  }

  /// Handle incoming file share announcement.
  void handleRemoteFileShare(proto.CallFileShare share) {
    final senderHex = bytesToHex(Uint8List.fromList(share.sharedBy));
    if (senderHex == ownUserIdHex) return; // Ignore own echo

    if (share.action == 0) {
      // ANNOUNCE
      final entry = SharedFileEntry(
        fileId: Uint8List.fromList(share.fileId),
        fileName: share.fileName,
        fileSize: share.fileSize.toInt(),
        mimeType: share.mimeType,
        thumbnailData: share.thumbnailData.isEmpty
            ? null
            : Uint8List.fromList(share.thumbnailData),
        sharedByHex: senderHex,
        sharedByName: share.sharedByName,
        sharedAt: DateTime.now(),
      );

      if (sharedFiles.length < maxFiles) {
        sharedFiles.add(entry);
        onFileShared?.call(entry);
        _log.info('Remote file: ${share.fileName} from '
            '${senderHex.substring(0, 8)}');
      }
    }
  }

  /// Share clipboard content (text or image) with all participants.
  void shareClipboard({String? text, Uint8List? imageData}) {
    final contentType = text != null ? 'text' : 'image';
    final entry = ClipboardEntry(
      senderIdHex: ownUserIdHex,
      senderName: ownDisplayName,
      contentType: contentType,
      textContent: text,
      imageData: imageData,
      timestamp: DateTime.now(),
    );

    clipboardHistory.add(entry);

    final exchange = proto.CallClipboardExchange()
      ..senderId = hexToBytes(ownUserIdHex)
      ..senderName = ownDisplayName
      ..contentType = contentType
      ..timestamp = Int64(entry.timestamp.millisecondsSinceEpoch);
    if (text != null) exchange.textContent = text;
    if (imageData != null) exchange.imageData = imageData;

    onSendToAll?.call(
      proto.MessageTypeV3.MTV3_CLIPBOARD_EXCHANGE,
      exchange.writeToBuffer(),
    );

    _log.debug('Clipboard shared: $contentType');
  }

  /// Handle incoming clipboard exchange.
  void handleRemoteClipboard(proto.CallClipboardExchange exchange) {
    final senderHex = bytesToHex(Uint8List.fromList(exchange.senderId));
    if (senderHex == ownUserIdHex) return;

    final entry = ClipboardEntry(
      senderIdHex: senderHex,
      senderName: exchange.senderName,
      contentType: exchange.contentType,
      textContent:
          exchange.textContent.isEmpty ? null : exchange.textContent,
      imageData: exchange.imageData.isEmpty
          ? null
          : Uint8List.fromList(exchange.imageData),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          exchange.timestamp.toInt()),
    );

    clipboardHistory.add(entry);
    onClipboardReceived?.call(entry);
    _log.debug('Clipboard from ${senderHex.substring(0, 8)}: '
        '${exchange.contentType}');
  }

  void dispose() {
    sharedFiles.clear();
    clipboardHistory.clear();
  }
}
