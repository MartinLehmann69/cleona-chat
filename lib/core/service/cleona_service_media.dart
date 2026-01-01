// Media reception helpers: MIME detection and the entry of a lane 2/3
// announcement (§9.4). The lanes themselves are `cleona_service_bulk.dart`,
// `cleona_service_stream.dart` and `cleona_service_transfer.dart`.
//
// S399 P2: the V3 fetch path (`MTV3_MEDIA_REQUEST` / `MEDIA_CHUNK` /
// `MEDIA_COMPLETE` / `MEDIA_REJECT`) and the detached V4.1 bulk lane handlers
// are gone — §9.4 knows no fetch on request, and "a file is never sent
// again" (§9.3, D-34).

part of 'cleona_service.dart';

extension V3MediaReceiveOps on CleonaService {


  String _guessMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'mp4': return 'video/mp4';
      case 'webm': return 'video/webm';
      case 'mov': return 'video/quicktime';
      case 'mkv': return 'video/x-matroska';
      case 'mpeg': case 'mpg': return 'video/mpeg';
      case 'mp3': return 'audio/mpeg';
      case 'ogg': case 'oga': return 'audio/ogg';
      case 'wav': return 'audio/wav';
      case 'm4a': case 'aac': return 'audio/aac';
      case 'flac': return 'audio/flac';
      case 'opus': return 'audio/opus';
      case 'pdf': return 'application/pdf';
      case 'txt': return 'text/plain';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }


  /// True iff [mimeType] denotes a voice/audio recording (audio/*).
  /// V3 send-paths use this for transcription/voice-payload branching.
  bool _isVoiceFromMime(String mimeType) => mimeType.startsWith('audio/');


  /// MEDIA_ANNOUNCE: the announcement of lane 3 (§9.4, S398 P2b) —
  /// `cleona_service_bulk.dart`. The V3 two-stage announcement (empty
  /// payload, MEDIA_REQUEST) and the V4.1 offer (`BulkAnnounce`) are no
  /// longer read: 4.2 has no compatibility branch (D-21).
  void _handleMediaAnnounceV3(HarvestEvent event) {
    try {
      _bulkAnnounceReceived(event);
    } catch (e) {
      _logHandlerErrorEvent('handleMediaAnnounceV3', e, event, messageType: 'failed');
    }
  }
}
