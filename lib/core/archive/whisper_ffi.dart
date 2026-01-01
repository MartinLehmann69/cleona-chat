/// FFI bindings for whisper.cpp (on-device speech-to-text).
///
/// Loads libwhisper as a shared library and provides functions
/// for model loading, audio transcription and resource cleanup.
/// Supports model sizes tiny (~40MB), base (~75MB), small (~250MB).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';

// ── whisper.cpp Native Function Types ────────────────────────────────────

// whisper_context * whisper_init_from_file(const char * path_model)
typedef _WhisperInitFromFileNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _WhisperInitFromFileDart = Pointer<Void> Function(Pointer<Utf8>);

// void whisper_free(struct whisper_context * ctx)
typedef _WhisperFreeNative = Void Function(Pointer<Void>);
typedef _WhisperFreeDart = void Function(Pointer<Void>);

// struct whisper_full_params whisper_full_default_params(enum whisper_sampling_strategy)
// We use the simple API: whisper_full()
typedef _WhisperFullNative = Int32 Function(
  Pointer<Void>, // ctx
  Pointer<Void>, // params (as opaque struct)
  Pointer<Float>, // samples (mono, 16kHz float32)
  Int32, // n_samples
);
typedef _WhisperFullDart = int Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Float>,
  int,
);

// int whisper_full_n_segments(struct whisper_context * ctx)
typedef _WhisperFullNSegmentsNative = Int32 Function(Pointer<Void>);
typedef _WhisperFullNSegmentsDart = int Function(Pointer<Void>);

// const char * whisper_full_get_segment_text(struct whisper_context * ctx, int i_segment)
typedef _WhisperFullGetSegmentTextNative = Pointer<Utf8> Function(
    Pointer<Void>, Int32);
typedef _WhisperFullGetSegmentTextDart = Pointer<Utf8> Function(
    Pointer<Void>, int);

// const char * whisper_lang_str(int id)
typedef _WhisperLangStrNative = Pointer<Utf8> Function(Int32);
typedef _WhisperLangStrDart = Pointer<Utf8> Function(int);

// int whisper_full_lang_id(struct whisper_context * ctx)
typedef _WhisperFullLangIdNative = Int32 Function(Pointer<Void>);
typedef _WhisperFullLangIdDart = int Function(Pointer<Void>);

// whisper_full_default_params — returns struct, we allocate as bytes
typedef _WhisperFullDefaultParamsNative = Pointer<Void> Function(Int32);
typedef _WhisperFullDefaultParamsDart = Pointer<Void> Function(int);

// ── Sampling Strategy Enum ───────────────────────────────────────────────

/// whisper_sampling_strategy: WHISPER_SAMPLING_GREEDY = 0.
const int whisperSamplingGreedy = 0;

// ── WhisperFFI Class ─────────────────────────────────────────────────────

/// FFI wrapper for whisper.cpp.
///
/// Usage:
/// ```dart
/// final whisper = WhisperFFI();
/// whisper.loadModel('/path/to/ggml-base.bin');
/// final result = whisper.transcribe(audioSamples);
/// whisper.dispose();
/// ```
class WhisperFFI {
  static final _log = CLogger.get('whisper-ffi');

  DynamicLibrary? _lib;
  Pointer<Void>? _ctx;
  bool _disposed = false;

  // Lazily initialized function pointers
  _WhisperInitFromFileDart? _initFromFile;
  _WhisperFreeDart? _freeCtx;
  _WhisperFullDart? _full;
  _WhisperFullNSegmentsDart? _nSegments;
  _WhisperFullGetSegmentTextDart? _getSegmentText;
  _WhisperFullLangIdDart? _langId;
  _WhisperLangStrDart? _langStr;
  _WhisperFullDefaultParamsDart? _defaultParams;

  /// Constructor: immediately loads the native library.
  /// Throws [WhisperNotAvailableException] if library cannot be loaded.
  WhisperFFI() {
    _ensureLoaded();
  }

  /// Load library. Searches in standard paths.
  void _ensureLoaded() {
    if (_lib != null) return;

    final (libName, wrapperName, ggmlLibs) = _libNamesForPlatform();
    final home = Platform.environment['HOME'];
    final searchPaths = <String>[
      libName, // bare name — linker searches system paths + jniLibs on Android
      if (Platform.isMacOS || Platform.isIOS) ...[
        '@executable_path/../Frameworks/$libName',
        '/opt/homebrew/lib/$libName',
        '/usr/local/lib/$libName',
      ] else ...[
        '/usr/lib/$libName',
        '/usr/local/lib/$libName',
      ],
      if (home != null) '$home/lib/$libName',
      'build/$libName',
    ];

    // Pre-load GGML dependencies before opening libwhisper.
    // libwhisper links against libggml*. When opened via absolute path,
    // the dynamic linker still searches system paths for transitive deps.
    // We must load them first so they're already in the process address space.
    for (final ggmlName in ggmlLibs) {
      // On Android, bare name is enough — jniLibs are on the linker path
      if (Platform.isAndroid) {
        try {
          DynamicLibrary.open(ggmlName);
          _log.info('GGML pre-loaded: $ggmlName');
          continue;
        } catch (e) {
          _log.info('GGML pre-load (bare) failed for $ggmlName: $e');
        }
      }
      for (final dir in searchPaths.map(_dirOf).whereType<String>().toSet()) {
        try {
          DynamicLibrary.open('$dir/$ggmlName');
          _log.info('GGML pre-loaded: $dir/$ggmlName');
          break;
        } catch (e) {
          _log.debug('GGML pre-load failed for $dir/$ggmlName: $e');
          continue;
        }
      }
    }

    for (final path in searchPaths) {
      try {
        _lib = DynamicLibrary.open(path);
        _log.info('Loaded whisper library from: $path');
        break;
      } catch (e) {
        _log.debug('whisper library not at $path: $e');
        continue;
      }
    }

    if (_lib == null) {
      throw WhisperNotAvailableException(
          '$libName not found. Please compile and install whisper.cpp.');
    }

    // Load wrapper library (bridges pointer-based API to whisper_full's value-based params).
    // whisper_full() takes whisper_full_params by value which Dart FFI cannot handle.
    // The wrapper provides whisper_full_from_ptr() that takes a pointer and dereferences.
    DynamicLibrary? wrapperLib;
    final wrapperSearchPaths = <String>[
      wrapperName,
      if (Platform.isMacOS || Platform.isIOS) ...[
        '@executable_path/../Frameworks/$wrapperName',
        '/opt/homebrew/lib/$wrapperName',
        '/usr/local/lib/$wrapperName',
      ] else ...[
        '/usr/lib/$wrapperName',
        '/usr/local/lib/$wrapperName',
      ],
      if (home != null) '$home/lib/$wrapperName',
    ];
    for (final path in wrapperSearchPaths) {
      try {
        wrapperLib = DynamicLibrary.open(path);
        _log.info('Loaded whisper wrapper from: $path');
        break;
      } catch (e) {
        _log.debug('whisper wrapper not at $path: $e');
        continue;
      }
    }

    _initFromFile = _lib!
        .lookupFunction<_WhisperInitFromFileNative, _WhisperInitFromFileDart>(
            'whisper_init_from_file');
    _freeCtx = _lib!.lookupFunction<_WhisperFreeNative, _WhisperFreeDart>(
        'whisper_free');
    // Use wrapper for whisper_full (struct-by-value ABI issue)
    final fullLib = wrapperLib ?? _lib!;
    final fullFnName = wrapperLib != null ? 'whisper_full_from_ptr' : 'whisper_full';
    _full = fullLib.lookupFunction<_WhisperFullNative, _WhisperFullDart>(fullFnName);
    _nSegments = _lib!.lookupFunction<_WhisperFullNSegmentsNative,
        _WhisperFullNSegmentsDart>('whisper_full_n_segments');
    _getSegmentText = _lib!.lookupFunction<_WhisperFullGetSegmentTextNative,
        _WhisperFullGetSegmentTextDart>('whisper_full_get_segment_text');
    _langId = _lib!
        .lookupFunction<_WhisperFullLangIdNative, _WhisperFullLangIdDart>(
            'whisper_full_lang_id');
    _langStr =
        _lib!.lookupFunction<_WhisperLangStrNative, _WhisperLangStrDart>(
            'whisper_lang_str');
    _defaultParams = _lib!.lookupFunction<_WhisperFullDefaultParamsNative,
        _WhisperFullDefaultParamsDart>('whisper_full_default_params_by_ref');
  }

  /// Returns (libName, wrapperName, ggmlLibs) with the correct extension
  /// for the current platform. On Android/Linux we use `.so`, on macOS `.dylib`,
  /// on Windows `.dll`.
  static (String, String, List<String>) _libNamesForPlatform() {
    if (Platform.isMacOS || Platform.isIOS) {
      // iOS reuses .dylib-Naming auch bei Static-Link via Embedded Framework
      // (DynamicLibrary.process() / executable-path lookup).
      return (
        'libwhisper.dylib',
        'libwhisper_wrapper.dylib',
        const ['libggml-base.dylib', 'libggml-cpu.dylib', 'libggml.dylib'],
      );
    }
    if (Platform.isWindows) {
      return (
        'whisper.dll',
        'whisper_wrapper.dll',
        const ['ggml-base.dll', 'ggml-cpu.dll', 'ggml.dll'],
      );
    }
    // Linux + Android
    return (
      'libwhisper.so',
      'libwhisper_wrapper.so',
      const ['libggml-base.so', 'libggml-cpu.so', 'libggml.so'],
    );
  }

  /// Load Whisper model.
  ///
  /// [modelPath]: Path to the GGML model file (e.g. ggml-base.bin).
  /// Throws [WhisperNotAvailableException] if library is not loaded.
  /// Throws [WhisperModelException] if model cannot be loaded.
  void loadModel(String modelPath) {
    _ensureLoaded();

    final pathPtr = modelPath.toNativeUtf8();
    try {
      _ctx = _initFromFile!(pathPtr);
      if (_ctx == null || _ctx == nullptr) {
        throw WhisperModelException('Model could not be loaded: $modelPath');
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Transcribe audio.
  ///
  /// [samples]: Float32 samples, mono, 16kHz.
  /// [language]: Target language ('auto' = automatic detection, 'de', 'en', etc.).
  /// [nThreads]: Number of CPU threads for inference.
  ///
  /// Returns [WhisperResult] with text, detected language and confidence.
  WhisperResult transcribe(
    Float32List samples, {
    String language = 'auto',
    int nThreads = 4,
  }) {
    if (_ctx == null || _ctx == nullptr) {
      throw WhisperModelException('No model loaded');
    }
    if (_disposed) throw WhisperModelException('WhisperFFI already disposed');

    // Get default parameters (Greedy Sampling)
    final params = _defaultParams!(whisperSamplingGreedy);
    if (params == nullptr) {
      throw WhisperModelException('Could not create default parameters');
    }

    // Set language on params struct (offset 104: const char* language).
    // whisper.cpp default is "en" — we must set it explicitly.
    final langNative = language.toNativeUtf8();
    Pointer<Pointer<Utf8>>.fromAddress(params.address + _kOffsetLanguage)
        .value = langNative;

    // Set n_threads on params struct (offset 4: int n_threads).
    Pointer<Int32>.fromAddress(params.address + _kOffsetNThreads)
        .value = nThreads;

    // Copy samples to native memory
    final nativeSamples = calloc<Float>(samples.length);
    for (var i = 0; i < samples.length; i++) {
      nativeSamples[i] = samples[i];
    }

    try {
      final rc = _full!(_ctx!, params, nativeSamples, samples.length);
      if (rc != 0) {
        return WhisperResult(text: '', language: language, confidence: 0.0);
      }

      // Read result
      final nSeg = _nSegments!(_ctx!);
      final buffer = StringBuffer();
      for (var i = 0; i < nSeg; i++) {
        final textPtr = _getSegmentText!(_ctx!, i);
        if (textPtr != nullptr) {
          buffer.write(textPtr.toDartString());
        }
      }

      // Detected language
      final detectedLangId = _langId!(_ctx!);
      final langPtr = _langStr!(detectedLangId);
      final detectedLang =
          langPtr != nullptr ? langPtr.toDartString() : language;

      return WhisperResult(
        text: buffer.toString().trim(),
        language: detectedLang,
        confidence: nSeg > 0 ? 0.85 : 0.0, // whisper.cpp does not provide per-segment confidence
      );
    } finally {
      calloc.free(nativeSamples);
      calloc.free(langNative);
    }
  }

  // whisper_full_params struct field offsets (stable across x86_64 and ARM64).
  // Verified via offsetof() against whisper.cpp include/whisper.h.
  static const int _kOffsetNThreads = 4;   // int n_threads
  static const int _kOffsetLanguage = 104;  // const char* language

  /// Whether a model is loaded.
  bool get isModelLoaded => _ctx != null && _ctx != nullptr && !_disposed;

  /// Extract directory from a library path, or null for bare names.
  static String? _dirOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : null;
  }

  /// Release resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ctx != null && _ctx != nullptr) {
      _freeCtx!(_ctx!);
      _ctx = null;
    }
  }

  /// Default model path for a given size.
  static String modelPath(WhisperModelSize size) {
    final modelName = switch (size) {
      WhisperModelSize.tiny => 'ggml-tiny.bin',
      WhisperModelSize.base => 'ggml-base.bin',
      WhisperModelSize.small => 'ggml-small.bin',
    };
    return '${AppPaths.dataDir}/models/$modelName';
  }

  /// Hugging Face download URL for a model.
  static String modelUrl(WhisperModelSize size) {
    final modelName = switch (size) {
      WhisperModelSize.tiny => 'ggml-tiny.bin',
      WhisperModelSize.base => 'ggml-base.bin',
      WhisperModelSize.small => 'ggml-small.bin',
    };
    return 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$modelName';
  }

  /// Expected model file size in bytes (approximate).
  static int modelSizeBytes(WhisperModelSize size) {
    return switch (size) {
      WhisperModelSize.tiny => 39000000,   // ~39 MB
      WhisperModelSize.base => 77700000,   // ~78 MB
      WhisperModelSize.small => 250000000, // ~250 MB
    };
  }

  /// Whether the model is downloaded.
  static bool isModelDownloaded(WhisperModelSize size) {
    return File(modelPath(size)).existsSync();
  }
}

/// Result of a transcription.
class WhisperResult {
  final String text;
  final String language;
  final double confidence;

  WhisperResult({
    required this.text,
    required this.language,
    required this.confidence,
  });

  bool get isEmpty => text.isEmpty;
}

/// whisper.cpp library not available.
class WhisperNotAvailableException implements Exception {
  final String message;
  WhisperNotAvailableException(this.message);

  @override
  String toString() => 'WhisperNotAvailableException: $message';
}

/// Model loading error.
class WhisperModelException implements Exception {
  final String message;
  WhisperModelException(this.message);

  @override
  String toString() => 'WhisperModelException: $message';
}

/// Convert PCM audio to Float32 samples (for whisper.cpp).
///
/// whisper.cpp expects: Float32, mono, 16kHz.
/// Input: Int16 PCM, mono, 16kHz (standard recording format).
Float32List pcm16ToFloat32(Uint8List pcmData) {
  final samples = Float32List(pcmData.length ~/ 2);
  final view = ByteData.view(pcmData.buffer, pcmData.offsetInBytes);
  for (var i = 0; i < samples.length; i++) {
    final int16 = view.getInt16(i * 2, Endian.little);
    samples[i] = int16 / 32768.0;
  }
  return samples;
}
