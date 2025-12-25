import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../logging.dart';
import 'audio_output.dart';

final _log = Logger(Loggers.audio);

/// Pre-defined acknowledgment phrases for JARVIS-style responses.
class AcknowledgmentPhrases {
  static const List<String> defaults = [
    'Yes, sir.',
    'At your service, sir.',
    "I'm here, sir.",
    'Online and ready, sir.',
    'Standing by, sir.',
    'Listening, sir.',
    'How may I assist, sir?',
    'Awaiting your instructions, sir.',
    'Systems active. Yes, sir.',
    'Of course, sir.',
    'Right away, sir.',
    'Confirmed, sir.',
    'Present and accounted for, sir.',
    'Always listening, sir.',
  ];
}

/// Plays random acknowledgment audio when wake word is detected.
///
/// Loads pre-generated audio files from a directory and plays
/// a random one each time [playRandom] is called.
class AcknowledgmentPlayer {
  final String audioDirectory;
  final AudioOutput _audioOutput;
  final Random _random = Random();

  final List<_AudioFile> _audioFiles = [];
  bool _isInitialized = false;

  AcknowledgmentPlayer({
    required this.audioDirectory,
    required AudioOutput audioOutput,
  }) : _audioOutput = audioOutput;

  /// Whether acknowledgments are available.
  bool get hasAcknowledgments => _audioFiles.isNotEmpty;

  /// Number of loaded acknowledgments.
  int get count => _audioFiles.length;

  /// Initializes the player by loading audio files from the directory.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final dir = Directory(audioDirectory);
    if (!await dir.exists()) {
      _log.warning('Acknowledgment directory not found: $audioDirectory');
      _isInitialized = true;
      return;
    }

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        try {
          final bytes = await entity.readAsBytes();
          final audioData = _parseWavFile(bytes);
          if (audioData != null) {
            _audioFiles.add(audioData);
            _log.fine('Loaded acknowledgment: ${entity.path}');
          }
        } catch (e) {
          _log.warning('Failed to load ${entity.path}: $e');
        }
      }
    }

    _log.info('Loaded ${_audioFiles.length} acknowledgment audio files');
    _isInitialized = true;
  }

  /// Plays a random acknowledgment.
  ///
  /// Returns immediately if no acknowledgments are loaded.
  Future<void> playRandom() async {
    if (_audioFiles.isEmpty) {
      _log.fine('No acknowledgments available to play');
      return;
    }

    final index = _random.nextInt(_audioFiles.length);
    final audio = _audioFiles[index];

    _log.fine('Playing acknowledgment $index');
    await _audioOutput.play(audio.pcmData, audioSampleRate: audio.sampleRate);
  }

  /// Parses a WAV file and extracts PCM data and sample rate.
  _AudioFile? _parseWavFile(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // Check RIFF header
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    // Parse format chunk
    var offset = 12;
    int? sampleRate;
    int? bitsPerSample;
    int? numChannels;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bytes.buffer.asByteData().getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        numChannels = bytes.buffer.asByteData().getUint16(offset + 10, Endian.little);
        sampleRate = bytes.buffer.asByteData().getUint32(offset + 12, Endian.little);
        bitsPerSample = bytes.buffer.asByteData().getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        if (sampleRate == null || bitsPerSample == null || numChannels == null) {
          return null;
        }

        final dataStart = offset + 8;
        final dataEnd = dataStart + chunkSize;
        if (dataEnd > bytes.length) return null;

        final pcmData = bytes.sublist(dataStart, dataEnd);
        return _AudioFile(
          pcmData: pcmData,
          sampleRate: sampleRate,
          bitsPerSample: bitsPerSample,
          numChannels: numChannels,
        );
      }

      offset += 8 + chunkSize;
      if (chunkSize.isOdd) offset++; // Padding byte
    }

    return null;
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    _audioFiles.clear();
  }
}

class _AudioFile {
  final Uint8List pcmData;
  final int sampleRate;
  final int bitsPerSample;
  final int numChannels;

  _AudioFile({
    required this.pcmData,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.numChannels,
  });
}
