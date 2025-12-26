import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../logging.dart';
import 'session_event.dart';
import 'wav_writer.dart';

final _log = Logger(Loggers.recording);

/// Records session data for debugging and integration testing.
///
/// Captures audio files and events in JSONL format.
class SessionRecorder {
  /// Base directory for storing sessions.
  final String baseDir;

  /// Unique identifier for this session.
  final String sessionId;

  late final String _sessionDir;
  late final String _audioDir;
  IOSink? _jsonlSink;

  int _audioCounter = 0;
  DateTime? _sessionStart;
  bool _initialized = false;
  bool _finalized = false;
  bool _disposed = false;

  // Speaking state for barge-in tracking
  int _currentSentenceIndex = 0;
  int _totalSentences = 0;
  List<String> _currentSentences = [];

  /// Creates a new session recorder.
  ///
  /// If [sessionId] is not provided, a timestamp-based ID is generated.
  SessionRecorder({this.baseDir = './sessions', String? sessionId})
    : sessionId = sessionId ?? _generateSessionId();

  /// Generates a timestamp-based session ID.
  static String _generateSessionId() {
    final now = DateTime.now();
    final formatted = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .split('T')
        .join('_');
    return 'session_$formatted';
  }

  /// Current sentence index during speaking (for barge-in tracking).
  int get currentSentenceIndex => _currentSentenceIndex;

  /// Total number of sentences in current response.
  int get totalSentences => _totalSentences;

  /// Initializes the session recorder.
  ///
  /// Creates the session directory structure and writes the session_start event.
  Future<void> initialize(Map<String, dynamic> config) async {
    if (_initialized || _disposed) return;

    try {
      _sessionDir = '$baseDir/$sessionId';
      _audioDir = '$_sessionDir/audio';

      // Create directories
      await Directory(_sessionDir).create(recursive: true);
      await Directory(_audioDir).create(recursive: true);

      // Open JSONL file for writing
      final jsonlFile = File('$_sessionDir/session.jsonl');
      _jsonlSink = jsonlFile.openWrite(mode: FileMode.write);

      _sessionStart = DateTime.now();
      _initialized = true;

      // Write session start event
      await _writeEvent(SessionStartEvent(config: config));

      _log.info('Session recording started: $sessionId');
    } catch (e, stackTrace) {
      _log.warning('Failed to initialize session recorder', e, stackTrace);
    }
  }

  /// Records a wake word detection.
  Future<void> recordWakeWord(String keyword) async {
    await _writeEvent(WakeWordEvent(keyword: keyword));
  }

  /// Records user audio and returns the relative file path.
  ///
  /// Returns the path relative to the session directory (e.g., "audio/001_user.wav").
  Future<String> recordUserAudio(Uint8List pcmData) async {
    if (!_initialized || _finalized || _disposed) return '';

    try {
      _audioCounter++;
      final fileName = '${_audioCounter.toString().padLeft(3, '0')}_user.wav';
      final relativePath = 'audio/$fileName';
      final fullPath = '$_sessionDir/$relativePath';

      // Write WAV file
      final wavData = WavWriter.addWavHeader(pcmData);
      await File(fullPath).writeAsBytes(wavData);

      // Write event
      await _writeEvent(
        UserAudioEvent(
          file: relativePath,
          durationMs: WavWriter.calculateDurationMs(pcmData.length),
          sizeBytes: pcmData.length,
        ),
      );

      _log.fine('Recorded user audio: $relativePath');
      return relativePath;
    } catch (e, stackTrace) {
      _log.warning('Failed to record user audio', e, stackTrace);
      return '';
    }
  }

  /// Records a transcription result.
  Future<void> recordTranscription(String text, int audioRef) async {
    await _writeEvent(TranscriptionEvent(text: text, audioRef: audioRef));
  }

  /// Records an LLM response.
  Future<void> recordResponse(String text, int sentenceCount) async {
    await _writeEvent(ResponseEvent(text: text, sentenceCount: sentenceCount));
  }

  /// Sets the current speaking state for barge-in tracking.
  ///
  /// Call this before speaking starts.
  void setSpeakingState(List<String> sentences) {
    _currentSentences = List.from(sentences);
    _totalSentences = sentences.length;
    _currentSentenceIndex = 0;
  }

  /// Advances to the next sentence.
  ///
  /// Call this after each sentence finishes playing.
  void advanceSentence() {
    if (_currentSentenceIndex < _totalSentences - 1) {
      _currentSentenceIndex++;
    }
  }

  /// Records a barge-in event.
  ///
  /// Uses the current speaking state to determine which sentence was interrupted.
  Future<void> recordBargeIn() async {
    // Build partial text (sentences spoken so far, including current)
    final partialText = _currentSentences
        .take(_currentSentenceIndex + 1)
        .join(' ');

    await _writeEvent(
      BargeInEvent(
        sentenceIndex: _currentSentenceIndex,
        sentencesTotal: _totalSentences,
        partialText: partialText,
      ),
    );

    // Clear speaking state
    _currentSentences = [];
    _totalSentences = 0;
    _currentSentenceIndex = 0;
  }

  /// Finalizes the session and writes the session_end event.
  Future<void> finalize() async {
    if (!_initialized || _finalized || _disposed) return;

    try {
      final sessionDuration = _sessionStart != null
          ? DateTime.now().difference(_sessionStart!)
          : Duration.zero;

      await _writeEvent(
        SessionEndEvent(
          totalUtterances: _audioCounter,
          sessionDurationMs: sessionDuration.inMilliseconds,
        ),
      );

      await _jsonlSink?.flush();
      await _jsonlSink?.close();
      _jsonlSink = null;
      _finalized = true;

      _log.info(
        'Session recording finalized: $sessionId '
        '($_audioCounter utterances, ${sessionDuration.inSeconds}s)',
      );
    } catch (e, stackTrace) {
      _log.warning('Failed to finalize session', e, stackTrace);
    }
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (!_finalized) {
      await finalize();
    }

    try {
      await _jsonlSink?.close();
    } catch (_) {}
    _jsonlSink = null;
  }

  /// Writes an event to the JSONL file.
  Future<void> _writeEvent(SessionEvent event) async {
    if (!_initialized || _finalized || _disposed) return;

    try {
      _jsonlSink?.writeln(event.toJsonLine());
    } catch (e, stackTrace) {
      _log.warning('Failed to write event: ${event.type}', e, stackTrace);
    }
  }
}
