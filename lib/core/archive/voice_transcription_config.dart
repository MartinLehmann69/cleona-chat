// Central configuration for on-device voice transcription.
//
// Controls: retention periods, Whisper model, language selection.
// Independent of Media Auto-Archive — both can be enabled separately.
// [VoiceTranscriptionConfig.production] provides the production values,
// [VoiceTranscriptionConfig.test] provides shortened values for tests.

import 'package:cleona/core/service/service_types.dart' show Conversation;
import 'package:cleona/core/storage/message_store.dart';

/// The area of the encrypted store for the transcription settings
/// chosen by the user (§21.4.1).
///
/// S366: until now they lay as `transcription_config.json` NAKED in the
/// profile. The chosen language is a personal attribute — it says in
/// which language this person speaks; the retention period says
/// how long their voice recordings stay on the device.
const String kTranscriptionSettingsArea = 'transcription_config';

/// The key of the ONE record. See [kArchiveConfigKey] in
/// `archive_config.dart` for the rationale.
const String kTranscriptionSettingsKey = '_';

/// The three values the UI actually sets.
///
/// Deliberately NOT the whole [VoiceTranscriptionConfig]: it carries
/// language lists, thresholds and switches that nobody changes and that
/// come from the code. Only what the user chose is stored
/// — exactly the three fields the old file carried too.
class VoiceTranscriptionSettings {
  final String defaultLanguage;
  final int audioRetentionDays;

  /// The NAME of the model size (`tiny` / `base` / `small`), not its
  /// index. That is the form the old file carried and that
  /// `settings_screen.dart` still holds in `_selectedModel` today;
  /// [VoiceTranscriptionConfig.toJson] writes an index at the same place
  /// — the two forms were never the same and must not become
  /// the same here either.
  final String modelSize;

  const VoiceTranscriptionSettings({
    this.defaultLanguage = 'auto',
    this.audioRetentionDays = 30,
    this.modelSize = 'base',
  });

  Map<String, dynamic> toJson() => {
        'defaultLanguage': defaultLanguage,
        'audioRetentionDays': audioRetentionDays,
        'modelSize': modelSize,
      };

  static VoiceTranscriptionSettings fromJson(Map<String, dynamic> j) =>
      VoiceTranscriptionSettings(
        defaultLanguage: j['defaultLanguage'] as String? ?? 'auto',
        audioRetentionDays: j['audioRetentionDays'] as int? ?? 30,
        modelSize: j['modelSize'] as String? ?? 'base',
      );

  /// Reads the setting from the store. `null` means: never changed,
  /// so the defaults apply. If the store throws, it is NOT caught —
  /// "unreadable" is something different from "never set".
  static VoiceTranscriptionSettings? readFrom(MessageStore store) {
    final j = store
        .loadArea(kTranscriptionSettingsArea)[kTranscriptionSettingsKey];
    return j == null ? null : fromJson(j);
  }

  void writeTo(MessageStore store) => store.replaceArea(
      kTranscriptionSettingsArea, {kTranscriptionSettingsKey: toJson()});
}

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

  /// Supported languages: 'auto' + all 33 Cleona UI locales (V3.1.70+ parity).
  /// Whisper tiny/base support all of these natively.
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
      'ar', 'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi',
      'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ms',
      'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sv', 'th', 'tr',
      'uk', 'vi', 'zh',
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
            const [
              'auto',
              'ar', 'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa', 'fi',
              'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'ms',
              'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sv', 'th', 'tr',
              'uk', 'vi', 'zh',
            ],
        maxAudioDurationSec: json['maxAudioDurationSec'] as int? ?? 300,
        minConfidenceThreshold:
            (json['minConfidenceThreshold'] as num?)?.toDouble() ?? 0.5,
        enabledByDefault: json['enabledByDefault'] as bool? ?? true,
        independentOfArchive: json['independentOfArchive'] as bool? ?? true,
      );
}
