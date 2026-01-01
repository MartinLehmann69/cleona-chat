/// The whisper models of this device (§21.7, owner decision D-94).
///
/// ── WHAT IS DEVICE-WIDE ──────────────────────────────────────────────────
///
/// The model files are program data of the installation under
/// `<dataDir>/models/` and are shared by every identity of the device. So is
/// everything about them: which size transcription uses (the setting below,
/// one row of `device.db`), the ONE download that may run at a time, and the
/// one-time check of a model from before the "checked" mark. Until D-94 each
/// identity's transcription service held its own download state — two
/// identities could start two downloads of the same size, and both wrote the
/// same `<model>.tmp`.
///
/// What stays with the identity: the transcription language (§24.3, twin-sync
/// Type 8) and the audio retention — both in the identity's store, area
/// `transcription_config` (`voice_transcription_config.dart`).
///
/// ── OLD AND NEW (4.2.x) ──────────────────────────────────────────────────
///
/// A 4.2 version before D-94 kept the model size in the identity's record
/// (`VoiceTranscriptionSettings.modelSize`). That field is still read and is
/// never removed: the first start without a device row takes the active
/// identity's value once as the device value (`CleonaService`), and an older
/// 4.2 version on the same profile still finds its field. Nothing of this
/// crosses the network; Type 8 never carried a model (§14.7).
///
/// ── WHERE THE STATE LIVES ────────────────────────────────────────────────
///
/// The download state lives in this process: one daemon per device on
/// Linux/Windows/macOS, the app itself on Android/iOS. Every transcription
/// service of the process listens ([WhisperModelListener]), so each identity's
/// surface hears the same download.
library;

import 'dart:async';
import 'dart:io';

import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/whisper_ffi.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/storage/device_store.dart';

/// The key of the row in `DeviceStore.areaSettings`: `{'size': 'base'}`.
const String kTranscriptionModelSettingKey = 'transcription_model';

/// The size set on this device; `null` when no row lies there (never set, or
/// no device database yet) — then the caller decides (defaults, adoption).
WhisperModelSize? transcriptionModelRead(DeviceStore? store) {
  try {
    final row =
        store?.entry(DeviceStore.areaSettings, kTranscriptionModelSettingKey);
    final name = row?['size'];
    for (final s in WhisperModelSize.values) {
      if (s.name == name) return s;
    }
    return null;
  } on Object {
    return null;
  }
}

/// Stores the size set on this device. False when there is no database to
/// write to (no master seed yet).
bool transcriptionModelWrite(DeviceStore? store, WhisperModelSize size) {
  if (store == null) return false;
  store.putEntry(DeviceStore.areaSettings, kTranscriptionModelSettingKey,
      {'size': size.name});
  return true;
}

/// The device's size at the start of an identity's service, with the
/// one-time adoption of the old per-identity value (4.2.x before D-94):
///
/// - a row in the device database wins;
/// - without one, [heldName] — the model size in this identity's record,
///   `null` when the identity never stored transcription settings — is
///   written as the device value, but only when [activeHere] (this is the
///   active identity, or none is noted); from then on the row wins;
/// - otherwise `base`, the default, and nothing is written.
///
/// [adopted] says whether the row was written now. The identity's record is
/// never changed here.
({WhisperModelSize size, bool adopted}) transcriptionModelForDevice({
  required DeviceStore? store,
  required DeviceStore? Function() storeForWrite,
  required String? heldName,
  required bool activeHere,
}) {
  final set = transcriptionModelRead(store);
  if (set != null) return (size: set, adopted: false);
  if (heldName == null || !activeHere) {
    return (size: WhisperModelSize.base, adopted: false);
  }
  final size = WhisperModelSize.values.firstWhere((s) => s.name == heldName,
      orElse: () => WhisperModelSize.base);
  return (size: size, adopted: transcriptionModelWrite(storeForWrite(), size));
}

/// Model download status.
enum ModelDownloadStatus {
  idle,
  downloading,
  completed,
  failed,

  /// The file did not match the SHA-256 fixed in the program (D-64) — a
  /// fresh download or a model already on disk — and was deleted.
  rejected,
}

/// What a transcription service hears from [WhisperModels].
class WhisperModelListener {
  final void Function(ModelDownloadStatus status) onStatus;
  final void Function(double progress) onProgress;

  /// A model of [size] was checked: [ok] after a download that passed or a
  /// one-time check that passed, `false` when it was rejected and deleted.
  final void Function(WhisperModelSize size, bool ok) onChecked;

  /// The device's set size changed.
  final void Function(WhisperModelSize size) onSizeSet;

  const WhisperModelListener({
    required this.onStatus,
    required this.onProgress,
    required this.onChecked,
    required this.onSizeSet,
  });
}

/// The models of this device: one download at a time, one check per file.
class WhisperModels {
  WhisperModels._();

  /// The one instance of the process.
  static final WhisperModels instance = WhisperModels._();

  late final CLogger _log =
      CLogger.get('voice-transcription', profileDir: AppPaths.dataDir);

  final Set<WhisperModelListener> _listeners = {};

  void listen(WhisperModelListener l) => _listeners.add(l);
  void unlisten(WhisperModelListener l) => _listeners.remove(l);

  ModelDownloadStatus _status = ModelDownloadStatus.idle;
  ModelDownloadStatus get downloadStatus => _status;

  /// Why the last download ended as [ModelDownloadStatus.failed], for the
  /// surface — never a URL (see [_errorWithoutUrl]). Cleared when a
  /// download starts.
  String? _error;
  String? get downloadError => _error;

  /// Progress of the running or last download (0.0 - 1.0).
  double _progress = 0.0;
  double get downloadProgress => _progress;

  void _setStatus(ModelDownloadStatus s) {
    _status = s;
    for (final l in List.of(_listeners)) {
      l.onStatus(s);
    }
  }

  void _reportProgress(double p) {
    _progress = p;
    for (final l in List.of(_listeners)) {
      l.onProgress(p);
    }
  }

  void _checked(WhisperModelSize size, bool ok) {
    for (final l in List.of(_listeners)) {
      l.onChecked(size, ok);
    }
  }

  /// Tells every transcription service of the process that the device's
  /// set size is now [size] (after the setting was stored).
  void announceSize(WhisperModelSize size) {
    for (final l in List.of(_listeners)) {
      l.onSizeSet(size);
    }
  }

  /// Whether the model of [size] may be used (owner decision 20.10.2026):
  ///
  /// - it carries the "checked" mark ([WhisperFFI.hasCheckedMark]) — set
  ///   when its download passed the SHA-256 check — then it is used as it
  ///   is, WITHOUT a hash, now and at every later start;
  /// - it has no mark: a model downloaded before the check existed. It is
  ///   hashed ONCE; on a match the mark is written and it is never hashed
  ///   again, on a mismatch it is DELETED and the status becomes
  ///   [ModelDownloadStatus.rejected].
  ///
  /// A rejected model is NOT downloaded again by itself: a download is a
  /// request to a third party (huggingface.co learns the IP and which
  /// model) and up to ~490 MB, possibly over mobile data — it happens only
  /// on the user's click in the settings, where the rejected model now
  /// shows as missing with its download button.
  ///
  /// Callers that ask at the same time (start, a queued job, the sender's
  /// `transcribeNow`, the services of other identities) share ONE check.
  Future<bool> ensureChecked(WhisperModelSize size) {
    if (!File(WhisperFFI.modelPath(size)).existsSync()) {
      return Future.value(false);
    }
    if (WhisperFFI.hasCheckedMark(size)) return Future.value(true);
    final path = WhisperFFI.modelPath(size);
    // Block body on purpose: `=> _checking.remove(path)` would return the
    // removed Future itself, and `whenComplete` waits for a returned Future
    // — the check would wait for itself forever.
    return _checking[path] ??= _checkOnce(size, path).whenComplete(() {
      _checking.remove(path);
    });
  }

  final Map<String, Future<bool>> _checking = {};

  Future<bool> _checkOnce(WhisperModelSize size, String path) async {
    final source = WhisperFFI.modelSource(size);
    _log.info('Model ${source.fileName} has no "checked" mark '
        '(downloaded before the check existed) — checking it once');
    if (await WhisperFFI.fileMatches(path, source)) {
      WhisperFFI.writeCheckedMark(size);
      _checked(size, true);
      return true;
    }
    _log.warn('Model ${source.fileName} does not match its fixed SHA-256 '
        '— deleted, download it again in the settings');
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      _log.warn('Rejected model ${source.fileName} not deletable: $e');
    }
    WhisperFFI.removeCheckedMark(size);
    _checked(size, false);
    _setStatus(ModelDownloadStatus.rejected);
    return false;
  }

  /// What an exception says without the URL it may carry: an
  /// [HttpException] names the (redirected, signed) URI with its query.
  static String _errorWithoutUrl(Object e) => switch (e) {
        HttpException(:final message) => 'HttpException: $message',
        SocketException(:final message, :final osError) =>
          'SocketException: ${[
            message,
            if (osError != null && osError.message != message) osError.message,
          ].where((s) => s.isNotEmpty).join(' — ')}',
        _ => e.runtimeType.toString(),
      };

  /// Download the GGML model file from its source (Hugging Face) into a
  /// temporary file, check it against the fixed SHA-256 (D-64) and only
  /// then rename it to its place. Returns true if the model is in place.
  /// While one download runs, a second one (any size, any identity) is
  /// refused.
  Future<bool> download(WhisperModelSize size) async {
    if (_status == ModelDownloadStatus.downloading) return false;

    _error = null;
    _setStatus(ModelDownloadStatus.downloading);
    _reportProgress(0.0);

    final source = WhisperFFI.modelSource(size);
    final uri = Uri.parse(source.url);
    final targetPath = WhisperFFI.modelPath(size);
    final tmpPath = '$targetPath.tmp';

    try {
      // Ensure models directory exists
      final dir = Directory(File(targetPath).parent.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // Model name and host only — no path parameters, no redirect target.
      _log.info('Downloading model ${source.fileName} from ${uri.host}');

      // HTTP GET with streaming (HttpClient follows redirects automatically)
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        _log.warn('Model download HTTP ${response.statusCode} '
            'for ${source.fileName}');
        client.close();
        _error = 'HTTP ${response.statusCode}';
        _setStatus(ModelDownloadStatus.failed);
        return false;
      }

      final expectedSize = response.contentLength;
      _log.info('Model download started: ${expectedSize > 0 ? "${(expectedSize / 1024 / 1024).toStringAsFixed(1)} MB" : "unknown size"}');
      final sink = File(tmpPath).openWrite();
      var received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (expectedSize > 0) {
          _reportProgress(received / expectedSize);
        }
      }
      await sink.close();
      client.close();

      final downloadedSize = File(tmpPath).lengthSync();
      _log.info('Model download complete: ${(downloadedSize / 1024 / 1024).toStringAsFixed(1)} MB');
      // D-64: the file reaches its place — and with it the whisper.cpp
      // parser — only if it is exactly the model the program names.
      if (!await WhisperFFI.fileMatches(tmpPath, source)) {
        _log.warn('Model ${source.fileName} does not match its fixed '
            'SHA-256 ($downloadedSize bytes, expected ${source.bytes}) '
            '— discarded, not used');
        File(tmpPath).deleteSync();
        _setStatus(ModelDownloadStatus.rejected);
        return false;
      }

      // Rename tmp to final path (atomic on same filesystem)
      // A model that is replaced must not inherit the old mark for a moment.
      WhisperFFI.removeCheckedMark(size);
      File(tmpPath).renameSync(targetPath);
      // Checked at its download — the ONLY hash this model ever gets.
      WhisperFFI.writeCheckedMark(size);

      _setStatus(ModelDownloadStatus.completed);
      _reportProgress(1.0);

      // The freshly checked model makes transcription ready only where it
      // is the SET size — each listener decides for itself.
      _checked(size, true);

      return true;
    } catch (e, st) {
      _log.warn('Model download of ${source.fileName} failed: '
          '${_errorWithoutUrl(e)}\n$st');
      // Cleanup partial download
      final tmp = File(tmpPath);
      if (tmp.existsSync()) tmp.deleteSync();

      _error = _errorWithoutUrl(e);
      _setStatus(ModelDownloadStatus.failed);
      return false;
    }
  }
}
