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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_types.dart';
import 'package:cleona/core/archive/whisper_ffi.dart';
import 'package:cleona/core/network/clogger.dart';

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
  static final _log = CLogger.get('voice-transcription');

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

  VoiceTranscriptionService({
    required this.config,
    required this.profileDir,
  });

  /// Effective default language (override > config).
  String get defaultLanguage => _languageOverride ?? config.defaultLanguage;

  /// Update default language at runtime (e.g. from Settings UI).
  set defaultLanguage(String lang) {
    _languageOverride = lang;
    _log.info('Transcription language set to: $lang');
  }

  // -- Lifecycle -----------------------------------------------------------

  /// Start service: load model, start cleanup timer.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _loadTranscriptions();

    // Load Whisper model (if available).
    try {
      _whisper = WhisperFFI();
      _log.info('whisper.cpp library loaded successfully');
      final modelFile = WhisperFFI.modelPath(config.modelSize);
      if (File(modelFile).existsSync()) {
        _whisper!.loadModel(modelFile);
        _modelLoaded = true;
        _log.info('Whisper model loaded: $modelFile');
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
    await _saveTranscriptions();
  }

  /// Whether the Whisper model is loaded.
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
    await _saveTranscriptions();
  }

  /// Transcribe audio file (in isolate for non-blocking).
  Future<VoiceTranscription?> _transcribeFile(_TranscriptionJob job) async {
    final file = File(job.audioFilePath);
    if (!file.existsSync()) return null;

    final audioBytes = await file.readAsBytes();
    if (audioBytes.isEmpty) return null;

    // Extract PCM data.
    // Supported formats: WAV (direct), OGG/MP3 (via ffmpeg conversion).
    Float32List samples;
    if (job.audioFilePath.endsWith('.wav')) {
      samples = _extractWavSamples(audioBytes);
    } else {
      // OGG/MP3/AAC: convert to WAV via ffmpeg.
      final wavData = await _convertToWav(job.audioFilePath);
      if (wavData == null) return null;
      samples = _extractWavSamples(wavData);
    }

    if (samples.isEmpty) return null;

    // Check duration (16kHz = 16000 samples/second).
    final durationSec = samples.length / 16000;
    if (durationSec > config.maxAudioDurationSec) return null;

    // Transcription via whisper.cpp.
    final result = _whisper!.transcribe(
      samples,
      language: job.language,
    );

    if (result.isEmpty) return null;
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
  Future<Uint8List?> _convertToWavFfmpeg(String inputPath, String outputPath) async {
    final result = await Process.run('ffmpeg', [
      '-y', '-i', inputPath,
      '-ar', '16000', '-ac', '1', '-f', 'wav',
      '-acodec', 'pcm_s16le', outputPath,
    ]);

    if (result.exitCode != 0) return null;

    final file = File(outputPath);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  }

  /// Android: decode via platform-specific audio decoder callback.
  Future<Uint8List?> _convertToWavPlatform(String inputPath, String outputPath) async {
    if (platformAudioDecoder == null) return null;
    return await platformAudioDecoder!(inputPath, outputPath);
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

      // Try to load the freshly downloaded model
      if (_whisper != null && !_modelLoaded) {
        try {
          _whisper!.loadModel(targetPath);
          _modelLoaded = true;
          _log.info('Whisper model loaded successfully: $targetPath');
        } catch (e) {
          _log.warn('Whisper model load failed after download: $e');
        }
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

    if (cleaned > 0) await _saveTranscriptions();
    return cleaned;
  }

  // -- Lifecycle management ------------------------------------------------

  void _setLifecycle(String messageId, VoiceLifecycle newState) {
    final current = _lifecycles[messageId];
    if (current != null && !VoiceTranscriptionConfig.isValidTransition(current, newState)) {
      return; // Invalid transition
    }
    _lifecycles[messageId] = newState;
    onLifecycleChanged?.call(messageId, newState);
  }

  // -- Persistence ---------------------------------------------------------

  String get _transcriptionFilePath => '$profileDir/voice_transcriptions.json';

  Future<void> _loadTranscriptions() async {
    final file = File(_transcriptionFilePath);
    if (!file.existsSync()) return;

    try {
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final items = data['transcriptions'] as Map<String, dynamic>? ?? {};
      for (final e in items.entries) {
        _transcriptions[e.key] =
            VoiceTranscription.fromJson(e.value as Map<String, dynamic>);
      }

      final lifecycles = data['lifecycles'] as Map<String, dynamic>? ?? {};
      for (final e in lifecycles.entries) {
        _lifecycles[e.key] = VoiceLifecycle.values[e.value as int];
      }
    } catch (_) {
      // Corrupt file — start fresh.
    }
  }

  Future<void> _saveTranscriptions() async {
    final data = {
      'transcriptions':
          _transcriptions.map((k, v) => MapEntry(k, v.toJson())),
      'lifecycles':
          _lifecycles.map((k, v) => MapEntry(k, v.index)),
    };
    final file = File(_transcriptionFilePath);
    await file.writeAsString(jsonEncode(data));
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
