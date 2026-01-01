/// Service for on-device voice transcription.
///
/// Manages the lifecycle of voice messages:
/// 1. recording -> transcribing -> complete -> transcriptOnly
/// 2. Audio retention: deletion after configurable period
/// 3. Transcript retention: permanent (never delete)
///
/// Independent of Media Auto-Archive — both can be enabled separately.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_types.dart';
import 'package:cleona/core/archive/whisper_ffi.dart';
import 'package:cleona/core/media/media_store.dart';
import 'package:cleona/core/media/media_vault.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/storage/message_store.dart';

/// Callback when a transcription is completed.
typedef TranscriptionCompleteCallback = void Function(
    String messageId, VoiceTranscription transcription);

/// Callback when the lifecycle status changes.
typedef LifecycleChangedCallback = void Function(
    String messageId, VoiceLifecycle lifecycle);

/// Platform-specific audio decoder: converts audio file to WAV.
/// Returns WAV file bytes, or null on failure.
/// Set by the platform layer (e.g. Android MethodChannel) before start().
typedef AudioDecoderCallback = Future<Uint8List?> Function(
    String inputPath, String outputPath);

/// Service for on-device speech recognition via whisper.cpp.
class VoiceTranscriptionService {
  final CLogger _log;

  final VoiceTranscriptionConfig config;
  final String profileDir;

  /// Override for defaultLanguage (set at runtime via Settings UI).
  String? _languageOverride;

  /// Platform-specific audio decoder (Android: MediaCodec via MethodChannel).
  /// If set, used instead of ffmpeg for audio conversion on Android.
  AudioDecoderCallback? platformAudioDecoder;

  WhisperFFI? _whisper;
  bool _modelLoaded = false;
  Timer? _cleanupTimer;
  bool _running = false;

  /// Current lifecycle states per message.
  final Map<String, VoiceLifecycle> _lifecycles = {};

  /// Stored transcriptions.
  final Map<String, VoiceTranscription> _transcriptions = {};

  /// Queue for pending transcriptions.
  final List<_TranscriptionJob> _queue = [];
  bool _processing = false;

  /// Callbacks.
  TranscriptionCompleteCallback? onTranscriptionComplete;
  LifecycleChangedCallback? onLifecycleChanged;

  /// Called when model download progress changes (0.0 - 1.0).
  void Function(double progress)? onDownloadProgress;

  /// Called when model download status changes.
  void Function(ModelDownloadStatus status)? onDownloadStatusChanged;

  /// Current download status.
  ModelDownloadStatus _downloadStatus = ModelDownloadStatus.idle;
  ModelDownloadStatus get downloadStatus => _downloadStatus;

  /// Whether the whisper library is available (independent of model).
  bool get isWhisperAvailable => _whisper != null;

  // `final FileEncryption fileEnc` stood here — the S362 path that placed the
  // wording of spoken messages encrypted in
  // `voice_transcriptions.json.enc`. This file no longer
  // exists (S366); the wording lies in the area `voice_transcriptions`
  // of the store and thus under its key. A field that only
  // carries a rationale for a removed write path does not
  // stay — otherwise the next reader reads it as "a
  // file is written here".

  /// Encrypted store (S366). As with [PollManager] optional: the
  /// UI process builds the same service as a proxy without
  /// its own store, and then NOTHING is written and NOTHING read.
  final MessageStore? _store;

  /// Area for transcripts. One entry per message, the key is
  /// the `messageId`, value `{'t': <transkript>, 'l': <lebenslauf-index>}`.
  ///
  /// WHY ONE ENTRY PER MESSAGE and not the whole stock in one
  /// row: the file header says "transcript retention: permanent (never
  /// delete)" — the collection explicitly grows without a cap. Whoever writes it
  /// as a whole brings back exactly the full rewrite
  /// that the state table is built against.
  static const String kArea = 'voice_transcriptions';

  /// Whether [_loadTranscriptions] ran through. Carries the
  /// data-loss latch: as long as nothing was loaded, nothing is
  /// written that could overwrite an existing stock.
  bool _loaded = false;

  // Was `static final` -> one logger for all identities, constructed
  // before any profileDir was known. Now an instance field: profileDir
  // is a constructor parameter (per identity) -> directly usable.
  VoiceTranscriptionService({
    required this.config,
    required this.profileDir,
    this._store,
  })  : _log = CLogger.get('voice-transcription', profileDir: profileDir);

  /// Effective default language (override > config).
  String get defaultLanguage => _languageOverride ?? config.defaultLanguage;

  /// Update default language at runtime (e.g. from Settings UI).
  set defaultLanguage(String lang) {
    _languageOverride = lang;
    _log.info('Transcription language set to: $lang');
  }

  // -- Lifecycle -----------------------------------------------------------

  /// Start service: probe whisper availability, start cleanup timer.
  ///
  /// The model itself is NEVER loaded in the main isolate: transcription
  /// runs in a per-job worker isolate (_transcribeFile) that loads and
  /// frees its own context. A resident main-isolate context would pin the
  /// full model (~144 MB for ggml-base) plus untouched compute buffers in
  /// memory for the process lifetime without ever transcribing.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _loadTranscriptions();

    // Probe whisper.cpp library + model file presence (no model load).
    try {
      _whisper = WhisperFFI();
      _log.info('whisper.cpp library loaded successfully');
      final modelFile = WhisperFFI.modelPath(config.modelSize);
      if (File(modelFile).existsSync()) {
        _modelLoaded = true;
        _log.info('Whisper model available: $modelFile');
      } else {
        _log.info('Whisper model not found: $modelFile (download via Settings)');
      }
    } on WhisperNotAvailableException catch (e) {
      _log.info('whisper.cpp not available: $e');
      _whisper = null;
    } catch (e, st) {
      _log.warn('Whisper initialization failed: $e\n$st');
      _whisper = null;
      _modelLoaded = false;
    }

    // Cleanup timer: delete old audio files hourly.
    _cleanupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => runCleanup(),
    );
  }

  /// Stop service.
  Future<void> stop() async {
    _running = false;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _whisper?.dispose();
    _whisper = null;
    _modelLoaded = false;
    // S366: here stood `await _saveTranscriptions()` — the full writer
    // of the whole collection. Every change is already stored individually
    // (`_persistMessage`), there is nothing to catch up on. The call was
    // moreover the most dangerous in the service: after a
    // failed load it laid the empty stock over the
    // full one.
  }

  /// Whether the Whisper model file is available for transcription
  /// (library loadable + model file present; loaded per-job in a worker).
  bool get isModelLoaded => _modelLoaded;

  /// Whether the service is running.
  bool get isRunning => _running;

  // -- Transcription -------------------------------------------------------

  /// Enqueue voice message for transcription.
  ///
  /// [messageId]: ID of the message.
  /// [audioFilePath]: Path to the audio file (OGG/MP3/WAV).
  /// [language]: Language or 'auto' for automatic detection.
  Future<void> enqueueTranscription({
    required String messageId,
    required String audioFilePath,
    String? language,
  }) async {
    if (!_running) return;
    if (_transcriptions.containsKey(messageId)) return; // Already transcribed

    _setLifecycle(messageId, VoiceLifecycle.recording);

    // Check audio duration.
    final file = File(audioFilePath);
    if (!file.existsSync()) return;

    final job = _TranscriptionJob(
      messageId: messageId,
      audioFilePath: audioFilePath,
      language: language ?? defaultLanguage,
    );

    _queue.add(job);
    _setLifecycle(messageId, VoiceLifecycle.transcribing);
    _processQueue();
  }

  /// Retrieve transcription for a message.
  VoiceTranscription? getTranscription(String messageId) =>
      _transcriptions[messageId];

  /// Lifecycle status of a message.
  VoiceLifecycle getLifecycle(String messageId) =>
      _lifecycles[messageId] ?? VoiceLifecycle.recording;

  /// All transcriptions.
  Map<String, VoiceTranscription> get transcriptions =>
      Map.unmodifiable(_transcriptions);

  /// Transcribe an audio file immediately (blocking, no queue).
  /// Used by sender to transcribe before sending.
  Future<VoiceTranscription?> transcribeNow(
    String audioFilePath, {
    String? language,
  }) async {
    if (!_modelLoaded || _whisper == null) return null;
    final job = _TranscriptionJob(
      messageId: '',
      audioFilePath: audioFilePath,
      language: language ?? defaultLanguage,
    );
    return _transcribeFile(job);
  }

  // -- Queue Processing ----------------------------------------------------

  Future<void> _processQueue() async {
    if (_processing || _queue.isEmpty) return;
    if (!_modelLoaded) {
      // Model not available — discard jobs.
      for (final job in _queue) {
        _setLifecycle(job.messageId, VoiceLifecycle.complete);
      }
      _queue.clear();
      return;
    }

    _processing = true;

    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      try {
        final result = await _transcribeFile(job);
        if (result != null) {
          _transcriptions[job.messageId] = result;
          // S366: first store, then set the lifecycle — both
          // write the same row, and in this order the wording
          // is already in it after the first write.
          _persistMessage(job.messageId);
          _setLifecycle(job.messageId, VoiceLifecycle.complete);
          onTranscriptionComplete?.call(job.messageId, result);
        } else {
          _setLifecycle(job.messageId, VoiceLifecycle.complete);
        }
      } catch (_) {
        _setLifecycle(job.messageId, VoiceLifecycle.complete);
      }
    }

    _processing = false;
    // S366: no full writer at the end of the loop anymore — every message
    // was stored individually above.
  }

  /// Transcribe audio file in a separate Isolate to avoid blocking the
  /// main event loop (FFI whisper_full() is synchronous and can take seconds).
  Future<VoiceTranscription?> _transcribeFile(_TranscriptionJob job) async {
    // S362: the voice message lies encrypted in the store.
    if (!MediaStore.instance.existsEitherWay(job.audioFilePath)) return null;

    final audioBytes = MediaStore.instance.readAll(job.audioFilePath);
    if (audioBytes == null || audioBytes.isEmpty) return null;

    Float32List samples;
    if (job.audioFilePath.endsWith('.wav')) {
      samples = _extractWavSamples(audioBytes);
    } else {
      final wavData = await _convertToWav(job.audioFilePath);
      if (wavData == null) return null;
      samples = _extractWavSamples(wavData);
    }

    if (samples.isEmpty) return null;

    final durationSec = samples.length / 16000;
    if (durationSec > config.maxAudioDurationSec) return null;

    final modelFile = WhisperFFI.modelPath(config.modelSize);
    if (!File(modelFile).existsSync()) return null;

    // Run transcription in a fresh Isolate — FFI pointers cannot cross
    // isolate boundaries, so we load the model inside the worker.
    final result = await Isolate.run(() {
      final w = WhisperFFI();
      try {
        w.loadModel(modelFile);
        final r = w.transcribe(samples, language: job.language);
        return (text: r.text, language: r.language, confidence: r.confidence);
      } finally {
        w.dispose();
      }
    });

    if (result.text.isEmpty) return null;
    if (result.confidence < config.minConfidenceThreshold) return null;

    return VoiceTranscription(
      messageId: job.messageId,
      text: result.text,
      language: result.language,
      timestamp: DateTime.now(),
      confidence: result.confidence,
    );
  }

  // -- Audio conversion ----------------------------------------------------

  /// OGG/MP3/AAC → WAV (16kHz, Mono, PCM16).
  /// Linux: via ffmpeg. Android: via MediaCodec MethodChannel.
  Future<Uint8List?> _convertToWav(String inputPath) async {
    final outputPath = '$profileDir/tmp_whisper_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      Uint8List? result;
      if (platformAudioDecoder != null) {
        _log.info('Converting audio via platform decoder: $inputPath');
        result = await _convertToWavPlatform(inputPath, outputPath);
      } else {
        _log.info('Converting audio via ffmpeg: $inputPath');
        result = await _convertToWavFfmpeg(inputPath, outputPath);
      }
      if (result == null) {
        _log.warn('Audio conversion returned null for $inputPath');
      } else {
        _log.info('Audio converted: ${result.length} bytes WAV');
      }
      return result;
    } catch (e) {
      _log.warn('Audio conversion failed: $e');
      return null;
    } finally {
      final tmpFile = File(outputPath);
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    }
  }

  /// Linux: convert via ffmpeg CLI.
  ///
  /// **S362: `ffmpeg` gets an `http://127.0.0.1` source, not a path.**
  /// The attachment lies framed and encrypted on disk; `ffmpeg` never
  /// learns to read a `.cmenc`, but takes any HTTP source. If the
  /// reader is not running (or the attachment still lies as not yet transferred
  /// plaintext), the path stays — then it is also readable.
  Future<Uint8List?> _convertToWavFfmpeg(String inputPath, String outputPath) async {
    final source = MediaVault.instance.urlFor(inputPath) ?? inputPath;
    final result = await Process.run('ffmpeg', [
      '-y', '-i', source,
      '-ar', '16000', '-ac', '1', '-f', 'wav',
      '-acodec', 'pcm_s16le', outputPath,
    ]);

    if (result.exitCode != 0) return null;

    final file = File(outputPath);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  }

  /// Android: decode via platform-specific audio decoder callback.
  ///
  /// **S362:** as in the ffmpeg branch, an `http://127.0.0.1` source goes
  /// in. On the other side is `MediaExtractor.setDataSource(String)`
  /// (`MainActivity.kt:928`), and according to the Android contract it takes "a file
  /// path or an http URL" — the Kotlin side stays unchanged.
  Future<Uint8List?> _convertToWavPlatform(String inputPath, String outputPath) async {
    if (platformAudioDecoder == null) return null;
    final source = MediaVault.instance.urlFor(inputPath) ?? inputPath;
    return await platformAudioDecoder!(source, outputPath);
  }

  /// Parse WAV header and extract PCM samples as Float32.
  Float32List _extractWavSamples(Uint8List wavData) {
    // WAV header: at least 44 bytes
    if (wavData.length < 44) return Float32List(0);

    // Check "RIFF" signature
    if (wavData[0] != 0x52 || wavData[1] != 0x49 ||
        wavData[2] != 0x46 || wavData[3] != 0x46) {
      // Not WAV — try as raw PCM16 data
      return pcm16ToFloat32(wavData);
    }

    // Search for "data" chunk
    var dataOffset = 12;
    while (dataOffset < wavData.length - 8) {
      final chunkId = String.fromCharCodes(wavData.sublist(dataOffset, dataOffset + 4));
      final view = ByteData.view(wavData.buffer, wavData.offsetInBytes + dataOffset + 4);
      final chunkSize = view.getUint32(0, Endian.little);

      if (chunkId == 'data') {
        final pcmStart = dataOffset + 8;
        final pcmEnd = pcmStart + chunkSize;
        final pcmData = wavData.sublist(pcmStart, pcmEnd.clamp(pcmStart, wavData.length));
        return pcm16ToFloat32(Uint8List.fromList(pcmData));
      }

      dataOffset += 8 + chunkSize;
      if (chunkSize.isOdd) dataOffset++; // Padding
    }

    return Float32List(0);
  }

  // -- Model Download -------------------------------------------------------

  /// Download the GGML model file from Hugging Face.
  /// Returns true if download succeeded, false on failure.
  Future<bool> downloadModel(WhisperModelSize size) async {
    if (_downloadStatus == ModelDownloadStatus.downloading) return false;

    _downloadStatus = ModelDownloadStatus.downloading;
    onDownloadStatusChanged?.call(_downloadStatus);
    onDownloadProgress?.call(0.0);

    final url = WhisperFFI.modelUrl(size);
    final targetPath = WhisperFFI.modelPath(size);
    final tmpPath = '$targetPath.tmp';

    try {
      // Ensure models directory exists
      final dir = Directory(File(targetPath).parent.path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _log.info('Downloading model from $url → $targetPath');

      // HTTP GET with streaming (HttpClient follows redirects automatically)
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        _log.warn('Model download HTTP ${response.statusCode} for $url');
        client.close();
        _downloadStatus = ModelDownloadStatus.failed;
        onDownloadStatusChanged?.call(_downloadStatus);
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
          onDownloadProgress?.call(received / expectedSize);
        }
      }
      await sink.close();
      client.close();

      // Validate file size (basic sanity check)
      final downloadedSize = File(tmpPath).lengthSync();
      _log.info('Model download complete: ${(downloadedSize / 1024 / 1024).toStringAsFixed(1)} MB');
      if (downloadedSize < 1000000) {
        // Less than 1 MB — clearly broken
        _log.warn('Model download too small ($downloadedSize bytes) — discarding');
        File(tmpPath).deleteSync();
        _downloadStatus = ModelDownloadStatus.failed;
        onDownloadStatusChanged?.call(_downloadStatus);
        return false;
      }

      // Rename tmp to final path (atomic on same filesystem)
      File(tmpPath).renameSync(targetPath);

      _downloadStatus = ModelDownloadStatus.completed;
      onDownloadStatusChanged?.call(_downloadStatus);
      onDownloadProgress?.call(1.0);

      // Mark the freshly downloaded model as available (loaded per-job in
      // the worker isolate, never resident in the main isolate).
      if (_whisper != null && !_modelLoaded) {
        _modelLoaded = true;
        _log.info('Whisper model available: $targetPath');
      }

      return true;
    } catch (e, st) {
      _log.warn('Model download failed: $e\n$st');
      // Cleanup partial download
      final tmp = File(tmpPath);
      if (tmp.existsSync()) tmp.deleteSync();

      _downloadStatus = ModelDownloadStatus.failed;
      onDownloadStatusChanged?.call(_downloadStatus);
      return false;
    }
  }

  // -- Cleanup (audio retention) -------------------------------------------

  /// Delete old audio files (based on retention configuration).
  Future<int> runCleanup() async {
    var cleaned = 0;

    for (final entry in _transcriptions.entries) {
      final transcription = entry.value;
      final messageId = entry.key;
      final lifecycle = getLifecycle(messageId);

      // Only process complete status (audio + transcription present).
      if (lifecycle != VoiceLifecycle.complete) continue;

      if (config.shouldDeleteAudio(transcription.timestamp)) {
        // Audio file can be deleted — only transcript remains.
        _setLifecycle(messageId, VoiceLifecycle.transcriptOnly);
        cleaned++;
      }
    }

    // S366: `_setLifecycle` stores every changed message itself.
    // The collective writer that used to be here rewrote, for ONE
    // expired audio track piece, the whole — permanently growing —
    // stock.
    return cleaned;
  }

  // -- Lifecycle management ------------------------------------------------

  void _setLifecycle(String messageId, VoiceLifecycle newState) {
    final current = _lifecycles[messageId];
    if (current != null && !VoiceTranscriptionConfig.isValidTransition(current, newState)) {
      return; // Invalid transition
    }
    _lifecycles[messageId] = newState;
    _persistMessage(messageId);
    onLifecycleChanged?.call(messageId, newState);
  }

  // -- Persistence ---------------------------------------------------------

  /// S366: from the store (area `voice_transcriptions`) instead of from
  /// `voice_transcriptions.json`. S362 had at least encrypted the wording;
  /// but the WHOLE collection kept being written,
  /// and according to the file header it grows permanently ("never delete").
  Future<void> _loadTranscriptions() async {
    final s = _store;
    if (s == null) {
      // Proxy mode: nothing to load, nothing to write.
      _loaded = true;
      return;
    }
    try {
      for (final e in s.loadArea(kArea).entries) {
        final t = e.value['t'];
        if (t is Map<String, dynamic>) {
          try {
            _transcriptions[e.key] = VoiceTranscription.fromJson(t);
          } catch (_) {/* damaged entry — only this one is lost */}
        }
        final l = e.value['l'];
        if (l is int && l >= 0 && l < VoiceLifecycle.values.length) {
          _lifecycles[e.key] = VoiceLifecycle.values[l];
        }
      }
      _loaded = true;
      _log.info('Loaded ${_transcriptions.length} transcriptions, '
          '${_lifecycles.length} lifecycles');
    } catch (e) {
      // NOT `_loaded = true`. Whoever falls through here has NOT seen a
      // possibly full stock — and therefore must not
      // touch it either (latch below).
      _log.warn('Failed to load transcriptions: $e');
    }
  }

  /// Writes EXACTLY ONE message. That is the only write path.
  ///
  /// THE DATA-LOSS LATCH. Until S366 a failed load
  /// (`catch` -> "start fresh") ended with the full writer laying the empty stock
  /// over the full one on shutdown. The latch
  /// now asks the STORE and not the file — never
  /// written again after the switchover: as long as nothing was loaded and the
  /// store holds something, nothing is written. If the store is not
  /// readable, it fails CLOSED.
  void _persistMessage(String messageId) {
    final s = _store;
    if (s == null) return;
    if (!_loaded) {
      int present;
      try {
        present = s.countArea(kArea);
      } catch (e) {
        _log.warn('REFUSED to persist transcription — store unreadable: $e');
        return;
      }
      if (present > 0) {
        _log.warn('REFUSED to persist transcription $messageId — load '
            'failed but the store still holds $present entries. '
            'Data loss risk!');
        return;
      }
    }
    final transcription = _transcriptions[messageId];
    final lifecycle = _lifecycles[messageId];
    try {
      if (transcription == null && lifecycle == null) {
        s.removeEntry(kArea, messageId);
        return;
      }
      s.putEntry(kArea, messageId, {
        if (transcription != null) 't': transcription.toJson(),
        if (lifecycle != null) 'l': lifecycle.index,
      });
    } catch (e) {
      _log.warn('Failed to persist transcription $messageId: $e');
    }
  }
}

/// Internal job for the transcription queue.
class _TranscriptionJob {
  final String messageId;
  final String audioFilePath;
  final String language;

  _TranscriptionJob({
    required this.messageId,
    required this.audioFilePath,
    required this.language,
  });
}

/// Model download status.
enum ModelDownloadStatus {
  idle,
  downloading,
  completed,
  failed,
}
