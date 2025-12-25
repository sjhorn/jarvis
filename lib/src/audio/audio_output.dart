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

/// Plays audio through speakers using sox play command.
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
    this.executablePath = '/opt/homebrew/bin/play',
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

  /// Plays raw audio data.
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
      // Write audio data to temp file
      final tempDir = await Directory.systemTemp.createTemp('audio_output_');
      final tempFile = File('${tempDir.path}/audio.raw');
      await tempFile.writeAsBytes(audioData);
      _log.fine('Wrote ${audioData.length} bytes to ${tempFile.path}');

      // Play using sox play command
      // Format: play -t raw -b 16 -e signed -r <rate> -c 1 audio.raw
      final args = [
        '-q', // Quiet mode
        '-t', 'raw', // Input format raw
        '-b', bitsPerSample.toString(), // Bits per sample
        '-e', 'signed', // Signed encoding
        '-r', rate.toString(), // Sample rate
        '-c', channels.toString(), // Channels
        tempFile.path,
      ];
      _log.fine('Starting: $executablePath ${args.join(' ')}');

      _playProcess = await Process.start(executablePath, args);
      _isPlaying = true;
      _log.fine('Play process started (pid: ${_playProcess!.pid})');

      // Capture any stderr for debugging
      _playProcess!.stderr.listen((data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) {
          _log.warning('sox stderr: $msg');
        }
      });

      // Wait for playback to complete
      final exitCode = await _playProcess!.exitCode;
      _log.fine('Play process exited with code: $exitCode');
      _isPlaying = false;
      _playProcess = null;

      // Cleanup temp file
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }

      if (exitCode != 0 && exitCode != -15) {
        // -15 is SIGTERM which is expected when we stop playback
        throw AudioOutputException(
          'play command failed with exit code $exitCode',
        );
      }
    } on ProcessException catch (e) {
      _isPlaying = false;
      throw AudioOutputException('Failed to play audio', e);
    }
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
      // Play file directly - sox can detect format from extension
      _playProcess = await Process.start(executablePath, ['-q', filePath]);

      _isPlaying = true;

      // Wait for playback to complete
      final exitCode = await _playProcess!.exitCode;
      _isPlaying = false;
      _playProcess = null;

      if (exitCode != 0 && exitCode != -15) {
        throw AudioOutputException(
          'play command failed with exit code $exitCode',
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
