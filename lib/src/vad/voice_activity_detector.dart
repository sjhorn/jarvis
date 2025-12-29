import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.vad);

/// State of voice activity.
enum VADState { silence, speech }

/// Event emitted when voice activity state changes.
class VADEvent {
  final VADState state;
  final DateTime timestamp;

  VADEvent({required this.state, required this.timestamp});
}

/// Energy-based voice activity detector.
///
/// Detects speech vs silence based on audio energy levels.
/// Emits events when transitioning between speech and silence states.
class VoiceActivityDetector {
  final double silenceThreshold;
  final Duration silenceDuration;

  VADState _currentState = VADState.silence;
  DateTime? _silenceStartTime;
  final _eventController = StreamController<VADEvent>.broadcast();

  VoiceActivityDetector({
    this.silenceThreshold = 0.01,
    this.silenceDuration = const Duration(milliseconds: 800),
  });

  /// Current VAD state.
  VADState get currentState => _currentState;

  /// Stream of VAD events (emitted on state changes).
  Stream<VADEvent> get events => _eventController.stream;

  /// Processes an audio chunk and updates VAD state.
  ///
  /// Audio should be 16-bit signed PCM, little-endian.
  void processAudio(Uint8List audioChunk) {
    final energy = _calculateEnergy(audioChunk);
    final isSpeech = energy > silenceThreshold;

    // Log energy periodically (every ~500ms worth of audio at 16kHz)
    _chunkCount++;
    if (_chunkCount % 25 == 0) {
      _log.finest(
        'VAD energy: ${energy.toStringAsFixed(4)}, '
        'threshold: $silenceThreshold, '
        'state: $_currentState, '
        'isSpeech: $isSpeech',
      );
    }

    if (isSpeech) {
      _silenceStartTime = null;

      if (_currentState != VADState.speech) {
        _log.fine(
          'VAD: silence -> speech (energy: ${energy.toStringAsFixed(4)})',
        );
        _currentState = VADState.speech;
        _eventController.add(
          VADEvent(state: VADState.speech, timestamp: DateTime.now()),
        );
      }
    } else {
      // Silence detected
      if (_currentState == VADState.speech) {
        // We were in speech, start silence timer
        _silenceStartTime ??= DateTime.now();

        final silenceTime = DateTime.now().difference(_silenceStartTime!);
        if (silenceTime >= silenceDuration) {
          _log.fine(
            'VAD: speech -> silence after ${silenceTime.inMilliseconds}ms '
            '(energy: ${energy.toStringAsFixed(4)})',
          );
          _currentState = VADState.silence;
          _eventController.add(
            VADEvent(state: VADState.silence, timestamp: DateTime.now()),
          );
          _silenceStartTime = null;
        }
      }
    }
  }

  int _chunkCount = 0;

  /// Calculates the RMS energy of an audio chunk.
  ///
  /// Returns normalized energy value between 0 and 1.
  double _calculateEnergy(Uint8List audioChunk) {
    if (audioChunk.isEmpty) return 0.0;

    // Interpret as 16-bit signed samples
    final numSamples = audioChunk.length ~/ 2;
    if (numSamples == 0) return 0.0;

    final byteData = ByteData.sublistView(audioChunk);
    var sumSquares = 0.0;

    for (var i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      // Normalize to -1..1 range
      final normalizedSample = sample / 32768.0;
      sumSquares += normalizedSample * normalizedSample;
    }

    // RMS energy
    final rms = sqrt(sumSquares / numSamples);
    return rms;
  }

  /// Resets the detector state to silence.
  void reset() {
    _log.fine('VAD: reset to silence');
    _currentState = VADState.silence;
    _silenceStartTime = null;
    _chunkCount = 0;
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await _eventController.close();
  }
}
