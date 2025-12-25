import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.audioOutput);

/// Exception thrown by AudioOutput operations.
class AudioOutputException implements Exception {
  final String message;
  final Object? cause;

  AudioOutputException(this.message, [this.cause]);

  @override
  String toString() =>
      'AudioOutputException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Plays audio through speakers using afplay (CoreAudio).
class AudioOutput {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final String executablePath;

  bool _initialized = false;
  bool _disposed = false;
  bool _isPlaying = false;
  Process? _playProcess;

  AudioOutput({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.executablePath = '/usr/bin/afplay',
  });

  /// Whether currently playing.
  bool get isPlaying => _isPlaying;

  /// Initializes the audio output by verifying play command exists.
  Future<void> initialize() async {
    if (_disposed) {
      throw AudioOutputException('AudioOutput has been disposed');
    }

    // Check play executable exists
    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw AudioOutputException(
        'play executable not found at: $executablePath',
      );
    }

    _initialized = true;
  }

  /// Plays raw PCM audio data.
  ///
  /// If [audioSampleRate] is provided, it overrides the default sample rate.
  /// This is useful when playing audio from TTS which may use a different
  /// sample rate (e.g., 22050Hz) than the default (16000Hz).
  Future<void> play(Uint8List audioData, {int? audioSampleRate}) async {
    if (audioData.isEmpty) {
      throw AudioOutputException('Audio data is empty');
    }
    if (_disposed) {
      throw AudioOutputException('AudioOutput has been disposed');
    }
    if (!_initialized) {
      throw AudioOutputException('AudioOutput not initialized');
    }
    if (_isPlaying) {
      await stop();
    }

    final rate = audioSampleRate ?? sampleRate;

    try {
      // Convert PCM to WAV format for afplay
      final wavData = _pcmToWav(audioData, rate, channels, bitsPerSample);

      // Write WAV to temp file
      final tempDir = await Directory.systemTemp.createTemp('audio_output_');
      final tempFile = File('${tempDir.path}/audio.wav');
      await tempFile.writeAsBytes(wavData);
      _log.fine('Wrote ${wavData.length} bytes WAV to ${tempFile.path}');

      // Play using afplay (CoreAudio - waits for buffer completion)
      _log.fine('Starting: $executablePath ${tempFile.path}');

      _playProcess = await Process.start(executablePath, [tempFile.path]);
      _isPlaying = true;
      _log.fine('afplay process started (pid: ${_playProcess!.pid})');

      // Capture any stderr for debugging
      _playProcess!.stderr.listen((data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) {
          _log.warning('afplay stderr: $msg');
        }
      });

      // Wait for playback to complete (afplay waits for CoreAudio buffer)
      final exitCode = await _playProcess!.exitCode;
      _log.fine('afplay process exited with code: $exitCode');
      _isPlaying = false;
      _playProcess = null;

      // Cleanup temp file
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }

      if (exitCode != 0 && exitCode != -15 && exitCode != -9) {
        // -15 is SIGTERM, -9 is SIGKILL - expected when we stop playback
        throw AudioOutputException(
          'afplay command failed with exit code $exitCode',
        );
      }
    } on ProcessException catch (e) {
      _isPlaying = false;
      throw AudioOutputException('Failed to play audio', e);
    }
  }

  /// Converts raw PCM data to WAV format by adding header.
  Uint8List _pcmToWav(Uint8List pcmData, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // 'W'
    buffer.setUint8(9, 0x41); // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    buffer.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Copy PCM data
    final result = buffer.buffer.asUint8List();
    result.setRange(44, 44 + dataSize, pcmData);

    return result;
  }

  /// Plays an audio file.
  Future<void> playFile(String filePath) async {
    if (_disposed) {
      throw AudioOutputException('AudioOutput has been disposed');
    }
    if (!_initialized) {
      throw AudioOutputException('AudioOutput not initialized');
    }

    // Check file exists
    final audioFile = File(filePath);
    if (!await audioFile.exists()) {
      throw AudioOutputException('Audio file not found: $filePath');
    }

    if (_isPlaying) {
      await stop();
    }

    try {
      // Play file using afplay (CoreAudio - waits for buffer completion)
      _log.fine('Playing file: $filePath');
      _playProcess = await Process.start(executablePath, [filePath]);

      _isPlaying = true;

      // Wait for playback to complete
      final exitCode = await _playProcess!.exitCode;
      _isPlaying = false;
      _playProcess = null;

      if (exitCode != 0 && exitCode != -15 && exitCode != -9) {
        throw AudioOutputException(
          'afplay command failed with exit code $exitCode',
        );
      }
    } on ProcessException catch (e) {
      _isPlaying = false;
      throw AudioOutputException('Failed to play audio file', e);
    }
  }

  /// Stops playback.
  Future<void> stop() async {
    if (_playProcess != null) {
      _playProcess!.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _playProcess = null;
    }
    _isPlaying = false;
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    _initialized = false;
  }
}
