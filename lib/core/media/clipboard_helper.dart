import 'dart:io';
import 'package:flutter/services.dart';

/// Content extracted from the system clipboard.
class ClipboardContent {
  final Uint8List? data;
  final String? mimeType;
  final bool isText;
  final bool isImage;
  final bool isVideo;
  final bool isAudio;
  final String? suggestedFilename;
  final String? text;
  /// Direct file path (e.g. from file manager copy via text/uri-list).
  final String? filePath;

  const ClipboardContent({
    this.data,
    this.mimeType,
    this.isText = false,
    this.isImage = false,
    this.isVideo = false,
    this.isAudio = false,
    this.suggestedFilename,
    this.text,
    this.filePath,
  });

  /// Human-readable size string (from binary data or file on disk).
  String get sizeLabel {
    int? bytes;
    if (data != null) {
      bytes = data!.length;
    } else if (filePath != null) {
      final f = File(filePath!);
      if (f.existsSync()) bytes = f.lengthSync();
    }
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isEmpty => data == null && text == null && filePath == null;
}

/// Detects clipboard tool (wl-paste / xclip) and extracts content.
///
/// Linux: uses wl-paste (Wayland) with xclip (X11) fallback.
/// Android/iOS: text-only via Flutter Clipboard API.
class ClipboardHelper {
  static String? _cachedTool;

  /// Detect which clipboard tool is available (cached).
  static Future<String?> _detectTool() async {
    if (_cachedTool != null) return _cachedTool;
    try {
      final result = await Process.run('which', ['wl-paste']);
      if (result.exitCode == 0) {
        _cachedTool = 'wl-paste';
        return _cachedTool;
      }
    } catch (_) {}
    try {
      final result = await Process.run('which', ['xclip']);
      if (result.exitCode == 0) {
        _cachedTool = 'xclip';
        return _cachedTool;
      }
    } catch (_) {}
    return null;
  }

  /// Get the current clipboard content with MIME type detection.
  static Future<ClipboardContent> getContent() async {
    if (Platform.isLinux) {
      return _getLinuxContent();
    }
    if (Platform.isMacOS) {
      return _getMacOSContent();
    }
    // Android/iOS: text only via Flutter API
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipData?.text != null && clipData!.text!.isNotEmpty) {
      return ClipboardContent(isText: true, text: clipData.text);
    }
    return const ClipboardContent();
  }

  /// macOS: text via `pbpaste` + osascript for image detection. File-manager
  /// copies (Finder "Copy") surface via NSPasteboard.public.file-url which we
  /// read via osascript → file path → filePath-based ClipboardContent.
  static Future<ClipboardContent> _getMacOSContent() async {
    // Check for file references (Finder Copy)
    try {
      final result = await Process.run('osascript', [
        '-e',
        'try',
        '-e', 'set theFiles to the clipboard as {«class furl»}',
        '-e', 'set thePaths to {}',
        '-e', 'repeat with f in theFiles',
        '-e', 'set end of thePaths to POSIX path of f',
        '-e', 'end repeat',
        '-e', 'set AppleScript\'s text item delimiters to linefeed',
        '-e', 'return thePaths as text',
        '-e', 'end try',
      ]);
      final out = (result.stdout as String?)?.trim() ?? '';
      if (out.isNotEmpty) {
        for (final raw in out.split('\n')) {
          final path = raw.trim();
          if (path.isEmpty) continue;
          final file = File(path);
          if (!file.existsSync()) continue;
          final filename = path.split('/').last;
          final mime = _mimeFromFilename(filename);
          return ClipboardContent(
            filePath: path,
            mimeType: mime,
            isImage: mime.startsWith('image/'),
            isVideo: mime.startsWith('video/'),
            isAudio: mime.startsWith('audio/'),
            suggestedFilename: filename,
          );
        }
      }
    } catch (_) {}

    // Text via pbpaste
    try {
      final result = await Process.run('pbpaste', const []);
      if (result.exitCode == 0) {
        final text = (result.stdout as String?) ?? '';
        if (text.isNotEmpty) {
          return ClipboardContent(isText: true, text: text);
        }
      }
    } catch (_) {}

    // Fallback: Flutter text API
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipData?.text != null && clipData!.text!.isNotEmpty) {
      return ClipboardContent(isText: true, text: clipData.text);
    }
    return const ClipboardContent();
  }

  static Future<ClipboardContent> _getLinuxContent() async {
    final tool = await _detectTool();
    if (tool == null) {
      // No clipboard tool — try Flutter text fallback
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipData?.text != null && clipData!.text!.isNotEmpty) {
        return ClipboardContent(isText: true, text: clipData.text);
      }
      return const ClipboardContent();
    }

    // Query available MIME types
    final types = await _listTypes(tool);

    // Check for files copied from file manager (text/uri-list)
    if (types.contains('text/uri-list')) {
      final content = await _handleUriList(tool);
      if (content != null) return content;
    }

    // Check for image content
    for (final imageType in ['image/png', 'image/jpeg', 'image/bmp', 'image/gif', 'image/webp']) {
      if (types.contains(imageType)) {
        final data = await _extractBinary(tool, imageType);
        if (data != null && data.isNotEmpty) {
          final ext = imageType.split('/').last;
          return ClipboardContent(
            data: data,
            mimeType: imageType,
            isImage: true,
            suggestedFilename: 'clipboard_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
        }
      }
    }

    // Check for video content
    for (final videoType in ['video/mp4', 'video/webm', 'video/mpeg', 'video/quicktime', 'video/x-matroska']) {
      if (types.contains(videoType)) {
        final data = await _extractBinary(tool, videoType);
        if (data != null && data.isNotEmpty) {
          final ext = _videoExtension(videoType);
          return ClipboardContent(
            data: data,
            mimeType: videoType,
            isVideo: true,
            suggestedFilename: 'clipboard_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
        }
      }
    }

    // Check for audio content
    for (final audioType in ['audio/ogg', 'audio/mpeg', 'audio/wav', 'audio/aac', 'audio/flac', 'audio/mp4']) {
      if (types.contains(audioType)) {
        final data = await _extractBinary(tool, audioType);
        if (data != null && data.isNotEmpty) {
          final ext = audioType.split('/').last;
          return ClipboardContent(
            data: data,
            mimeType: audioType,
            isAudio: true,
            suggestedFilename: 'clipboard_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
        }
      }
    }

    // Check for generic file content (application/*)
    for (final t in types) {
      if (t.startsWith('application/') && t != 'application/x-gtk-text-buffer-contents') {
        final data = await _extractBinary(tool, t);
        if (data != null && data.isNotEmpty) {
          return ClipboardContent(
            data: data,
            mimeType: t,
            suggestedFilename: 'clipboard_${DateTime.now().millisecondsSinceEpoch}',
          );
        }
      }
    }

    // Fallback: text content
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipData?.text != null && clipData!.text!.isNotEmpty) {
      return ClipboardContent(isText: true, text: clipData.text);
    }
    return const ClipboardContent();
  }

  /// Handle text/uri-list (files copied from file manager).
  /// Returns the first valid local file as ClipboardContent with filePath set.
  static Future<ClipboardContent?> _handleUriList(String tool) async {
    try {
      final data = await _extractBinary(tool, 'text/uri-list');
      if (data == null || data.isEmpty) return null;
      final uriText = String.fromCharCodes(data).trim();
      for (final line in uriText.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        // file:///path/to/file → /path/to/file
        final uri = Uri.tryParse(trimmed);
        if (uri == null || uri.scheme != 'file') continue;
        final path = uri.toFilePath();
        final file = File(path);
        if (!file.existsSync()) continue;
        final filename = path.split('/').last;
        final mime = _mimeFromFilename(filename);
        return ClipboardContent(
          filePath: path,
          mimeType: mime,
          isImage: mime.startsWith('image/'),
          isVideo: mime.startsWith('video/'),
          isAudio: mime.startsWith('audio/'),
          suggestedFilename: filename,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Guess MIME type from filename extension.
  static String _mimeFromFilename(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    const map = {
      'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4', 'webm': 'video/webm', 'mkv': 'video/x-matroska',
      'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg', 'ogg': 'audio/ogg', 'wav': 'audio/wav',
      'aac': 'audio/aac', 'flac': 'audio/flac', 'm4a': 'audio/mp4',
      'pdf': 'application/pdf', 'zip': 'application/zip',
      'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  /// Map video MIME type to file extension.
  static String _videoExtension(String mimeType) {
    const map = {
      'video/mp4': 'mp4', 'video/webm': 'webm', 'video/mpeg': 'mpg',
      'video/quicktime': 'mov', 'video/x-matroska': 'mkv',
    };
    return map[mimeType] ?? 'mp4';
  }

  /// List available MIME types in clipboard.
  static Future<List<String>> _listTypes(String tool) async {
    try {
      if (tool == 'wl-paste') {
        final result = await Process.run('wl-paste', ['--list-types']);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim().split('\n').where((s) => s.isNotEmpty).toList();
        }
      } else {
        // xclip: query targets
        final result = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'TARGETS', '-o']);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim().split('\n').where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Extract binary content for a specific MIME type.
  static Future<Uint8List?> _extractBinary(String tool, String mimeType) async {
    try {
      if (tool == 'wl-paste') {
        final result = await Process.run('wl-paste', ['--type', mimeType], stdoutEncoding: null);
        if (result.exitCode == 0) {
          return Uint8List.fromList(result.stdout as List<int>);
        }
      } else {
        final result = await Process.run(
          'xclip', ['-selection', 'clipboard', '-t', mimeType, '-o'],
          stdoutEncoding: null,
        );
        if (result.exitCode == 0) {
          return Uint8List.fromList(result.stdout as List<int>);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save clipboard content to a temporary file. Returns the file path.
  /// For file-manager copies (filePath set), returns the original path directly.
  static Future<String?> saveToTempFile(ClipboardContent content) async {
    if (content.filePath != null) return content.filePath;
    if (content.data == null) return null;
    final filename = content.suggestedFilename ?? 'clipboard_${DateTime.now().millisecondsSinceEpoch}';
    final tmpPath = '${Directory.systemTemp.path}/$filename';
    await File(tmpPath).writeAsBytes(content.data!);
    return tmpPath;
  }
}
