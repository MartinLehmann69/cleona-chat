// Data types for voice transcription.
//
// VoiceTranscription: A transcribed audio with metadata.

/// A transcription result for a voice message.
class VoiceTranscription {
  final String messageId;
  final String text;
  final String language;
  final DateTime timestamp;
  final double confidence;

  VoiceTranscription({
    required this.messageId,
    required this.text,
    required this.language,
    required this.timestamp,
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'text': text,
        'language': language,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'confidence': confidence,
      };

  static VoiceTranscription fromJson(Map<String, dynamic> json) =>
      VoiceTranscription(
        messageId: json['messageId'] as String,
        text: json['text'] as String? ?? '',
        language: json['language'] as String? ?? 'auto',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            json['timestamp'] as int? ?? 0),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}
