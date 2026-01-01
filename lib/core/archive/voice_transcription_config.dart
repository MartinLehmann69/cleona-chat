// Central configuration for on-device voice transcription.
//
// Controls: retention periods, Whisper model, language selection.
// Independent of Media Auto-Archive — both can be enabled separately.
// [VoiceTranscriptionConfig.production] provides the production values,
// [VoiceTranscriptionConfig.test] provides shortened values for tests.

import 'package:cleona/core/service/service_types.dart' show Conversation;
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Whisper model size (determines quality and resource consumption).
enum WhisperModelSize {
  /// ~40 MB, fast, acceptable quality.
  tiny,

  /// ~75 MB, good trade-off between quality and speed.
  base,

  /// ~250 MB, high quality, slower.
  small,
}

/// Lifecycle phases of a voice message.
enum VoiceLifecycle {
  /// Recording in progress.
  recording,

  /// Transcription running in background.
  transcribing,

  /// Audio + transcription available (phase 1).
  complete,

  /// Audio deleted, only transcription remaining (phase 2).
  transcriptOnly,
}

class VoiceTranscriptionConfig {
  // -- Retention ------------------------------------------------------------

  /// Audio retention period in days. Audio is deleted after this.
  final int audioRetentionDays;

  /// Transcript retention period. null = permanent (default).
  final Duration? transcriptRetention;

  // -- Whisper-Engine -----------------------------------------------------

  /// Model size for whisper.cpp.
  final WhisperModelSize modelSize;

  /// Default language ('auto' = automatic detection).
  final String defaultLanguage;

  /// Supported languages (Cleona languages + auto).
  final List<String> supportedLanguages;

  /// Max audio duration for transcription in seconds.
  final int maxAudioDurationSec;

  /// Min confidence threshold for transcription result (0.0-1.0).
  final double minConfidenceThreshold;

  // -- Feature-Flags ------------------------------------------------------

  /// Transcription enabled by default.
  final bool enabledByDefault;

  /// Feature is independent of Media Archive.
  final bool independentOfArchive;

  const VoiceTranscriptionConfig({
    // Retention
    this.audioRetentionDays = 30,
    this.transcriptRetention,
    // Whisper
    this.modelSize = WhisperModelSize.base,
    this.defaultLanguage = 'auto',
    this.supportedLanguages = const [
      'auto',
      'de',
      'en',
      'es',
      'hu',
      'sv',
    ],
    this.maxAudioDurationSec = 300,
    this.minConfidenceThreshold = 0.5,
    // Flags
    this.enabledByDefault = true,
    this.independentOfArchive = true,
  });

  /// Production configuration.
  factory VoiceTranscriptionConfig.production() =>
      const VoiceTranscriptionConfig();

  /// Test configuration with short retention and small model.
  factory VoiceTranscriptionConfig.test() => const VoiceTranscriptionConfig(
        audioRetentionDays: 1,
        modelSize: WhisperModelSize.tiny,
        maxAudioDurationSec: 60,
        minConfidenceThreshold: 0.0,
      );

  // -- Calculation methods --------------------------------------------------

  /// Audio retention period as Duration.
  Duration get audioRetention => Duration(days: audioRetentionDays);

  /// Whether audio of a voice message should be deleted.
  bool shouldDeleteAudio(DateTime recordedAt) {
    return DateTime.now().difference(recordedAt) >= audioRetention;
  }

  /// Whether a transcript should be deleted. Always false (permanent).
  bool shouldDeleteTranscript(DateTime transcribedAt) {
    if (transcriptRetention == null) return false;
    return DateTime.now().difference(transcribedAt) >= transcriptRetention!;
  }

  // -- Static methods ------------------------------------------------------

  /// Whether a conversation type is eligible for transcription.
  /// DMs and groups: yes. Channels: no.
  static bool isEligible({required bool isGroup, required bool isChannel}) {
    if (isChannel) return false;
    return true;
  }

  /// Whether a conversation is eligible for transcription.
  static bool isConversationEligible(Conversation conv) {
    return isEligible(isGroup: conv.isGroup, isChannel: conv.isChannel);
  }

  /// Whether a message type is transcribable.
  static bool isTranscribable(proto.MessageType type) {
    return type == proto.MessageType.VOICE_MESSAGE;
  }

  /// Whether a lifecycle transition is valid.
  static bool isValidTransition(VoiceLifecycle from, VoiceLifecycle to) {
    switch (from) {
      case VoiceLifecycle.recording:
        return to == VoiceLifecycle.transcribing;
      case VoiceLifecycle.transcribing:
        return to == VoiceLifecycle.complete;
      case VoiceLifecycle.complete:
        return to == VoiceLifecycle.transcriptOnly;
      case VoiceLifecycle.transcriptOnly:
        return false; // Final state
    }
  }

  // -- JSON Round-Trip ----------------------------------------------------

  Map<String, dynamic> toJson() => {
        'audioRetentionDays': audioRetentionDays,
        if (transcriptRetention != null)
          'transcriptRetentionMs': transcriptRetention!.inMilliseconds,
        'modelSize': modelSize.index,
        'defaultLanguage': defaultLanguage,
        'supportedLanguages': supportedLanguages,
        'maxAudioDurationSec': maxAudioDurationSec,
        'minConfidenceThreshold': minConfidenceThreshold,
        'enabledByDefault': enabledByDefault,
        'independentOfArchive': independentOfArchive,
      };

  static VoiceTranscriptionConfig fromJson(Map<String, dynamic> json) =>
      VoiceTranscriptionConfig(
        audioRetentionDays: json['audioRetentionDays'] as int? ?? 30,
        transcriptRetention: json['transcriptRetentionMs'] != null
            ? Duration(milliseconds: json['transcriptRetentionMs'] as int)
            : null,
        modelSize: json['modelSize'] != null
            ? WhisperModelSize.values[json['modelSize'] as int]
            : WhisperModelSize.base,
        defaultLanguage: json['defaultLanguage'] as String? ?? 'auto',
        supportedLanguages: (json['supportedLanguages'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const ['auto', 'de', 'en', 'es', 'hu', 'sv'],
        maxAudioDurationSec: json['maxAudioDurationSec'] as int? ?? 300,
        minConfidenceThreshold:
            (json['minConfidenceThreshold'] as num?)?.toDouble() ?? 0.5,
        enabledByDefault: json['enabledByDefault'] as bool? ?? true,
        independentOfArchive: json['independentOfArchive'] as bool? ?? true,
      );
}
