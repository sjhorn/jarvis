import 'dart:convert';

/// Base class for session recording events.
abstract class SessionEvent {
  final String type;
  final DateTime timestamp;

  SessionEvent({required this.type, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Converts the event to a JSON map.
  Map<String, dynamic> toJson();

  /// Converts the event to a single-line JSON string.
  String toJsonLine() => jsonEncode(toJson());
}

/// Event recorded when a session starts.
class SessionStartEvent extends SessionEvent {
  final Map<String, dynamic> config;

  SessionStartEvent({required this.config, super.timestamp})
      : super(type: 'session_start');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'config': config,
      };
}

/// Event recorded when wake word is detected.
class WakeWordEvent extends SessionEvent {
  final String keyword;

  WakeWordEvent({required this.keyword, super.timestamp})
      : super(type: 'wake_word');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'keyword': keyword,
      };
}

/// Event recorded when user audio is saved.
class UserAudioEvent extends SessionEvent {
  final String file;
  final int durationMs;
  final int sizeBytes;

  UserAudioEvent({
    required this.file,
    required this.durationMs,
    required this.sizeBytes,
    super.timestamp,
  }) : super(type: 'user_audio');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'file': file,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
      };
}

/// Event recorded when transcription is complete.
class TranscriptionEvent extends SessionEvent {
  final String text;
  final int audioRef;

  TranscriptionEvent({
    required this.text,
    required this.audioRef,
    super.timestamp,
  }) : super(type: 'transcription');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'text': text,
        'audioRef': audioRef,
      };
}

/// Event recorded when LLM response is generated.
class ResponseEvent extends SessionEvent {
  final String text;
  final int sentenceCount;

  ResponseEvent({
    required this.text,
    required this.sentenceCount,
    super.timestamp,
  }) : super(type: 'response');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'text': text,
        'sentenceCount': sentenceCount,
      };
}

/// Event recorded when user interrupts (barge-in).
class BargeInEvent extends SessionEvent {
  final int sentenceIndex;
  final int sentencesTotal;
  final String partialText;

  BargeInEvent({
    required this.sentenceIndex,
    required this.sentencesTotal,
    required this.partialText,
    super.timestamp,
  }) : super(type: 'barge_in');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'sentenceIndex': sentenceIndex,
        'sentencesTotal': sentencesTotal,
        'partialText': partialText,
      };
}

/// Event recorded when session ends.
class SessionEndEvent extends SessionEvent {
  final int totalUtterances;
  final int sessionDurationMs;

  SessionEndEvent({
    required this.totalUtterances,
    required this.sessionDurationMs,
    super.timestamp,
  }) : super(type: 'session_end');

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'totalUtterances': totalUtterances,
        'sessionDurationMs': sessionDurationMs,
      };
}
