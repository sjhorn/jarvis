import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.audioOutput);

/// Supported audio players.
enum AudioPlayer {
  afplay, // macOS (built-in)
  play, // sox (cross-platform)
  mpv, // mpv (cross-platform)
  ffplay, // ffmpeg (cross-platform)
  aplay, // ALSA (Linux)
}

/// Exception thrown by AudioOutput operations.
class AudioOutputException implements Exception {
  final String message;
  final Object? cause;

  AudioOutputException(this.message, [this.cause]);

  @override
  String toString() =>
      'AudioOutputException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Plays audio through speakers using configurable audio player.
class AudioOutput {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final AudioPlayer player;
  final String? customExecutablePath;

  bool _initialized = false;
  bool _disposed = false;
  bool _isPlaying = false;
  Process? _playProcess;
  String? _resolvedExecutable;

  AudioOutput({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.player = AudioPlayer.afplay,
    this.customExecutablePath,
  });

  /// Creates AudioOutput with auto-detected player for current platform.
  static Future<AudioOutput> autoDetect({
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) async {
    final player = await _detectAvailablePlayer();
    _log.info('Auto-detected audio player: ${player.name}');
    return AudioOutput(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      player: player,
    );
  }

  /// Detects the best available audio player for current platform.
  static Future<AudioPlayer> _detectAvailablePlayer() async {
    // Platform-preferred order
    final List<AudioPlayer> candidates;
    if (Platform.isMacOS) {
      candidates = [
        AudioPlayer.afplay,
        AudioPlayer.play,
        AudioPlayer.mpv,
        AudioPlayer.ffplay,
      ];
    } else if (Platform.isLinux) {
      candidates = [
        AudioPlayer.play,
        AudioPlayer.aplay,
        AudioPlayer.mpv,
        AudioPlayer.ffplay,
      ];
    } else if (Platform.isWindows) {
      candidates = [AudioPlayer.ffplay, AudioPlayer.mpv, AudioPlayer.play];
    } else {
      candidates = AudioPlayer.values;
    }

    for (final player in candidates) {
      final executable = _getDefaultExecutable(player);
      if (await _isExecutableAvailable(executable)) {
        return player;
      }
    }

    // Fallback to afplay (will fail on non-macOS but gives clear error)
    return AudioPlayer.afplay;
  }

  /// Checks if an executable is available in PATH or as absolute path.
  static Future<bool> _isExecutableAvailable(String executable) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        executable,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      // Try as absolute path
      return File(executable).existsSync();
    }
  }

  /// Gets the default executable path for a player.
  static String _getDefaultExecutable(AudioPlayer player) {
    switch (player) {
      case AudioPlayer.afplay:
        return Platform.isMacOS ? '/usr/bin/afplay' : 'afplay';
      case AudioPlayer.play:
        return 'play';
      case AudioPlayer.mpv:
        return 'mpv';
      case AudioPlayer.ffplay:
        return 'ffplay';
      case AudioPlayer.aplay:
        return 'aplay';
    }
  }

  /// Gets command arguments for playing a file with the configured player.
  List<String> _getPlayArgs(String filePath) {
    switch (player) {
      case AudioPlayer.afplay:
        return [filePath];
      case AudioPlayer.play:
        return ['-q', filePath]; // -q for quiet (no progress)
      case AudioPlayer.mpv:
        return ['--no-video', '--really-quiet', filePath];
      case AudioPlayer.ffplay:
        return ['-nodisp', '-autoexit', '-loglevel', 'quiet', filePath];
      case AudioPlayer.aplay:
        return ['-q', filePath]; // -q for quiet
    }
  }

  /// Whether currently playing.
  bool get isPlaying => _isPlaying;

  /// The resolved executable path being used.
  String? get executablePath => _resolvedExecutable;

  /// Initializes the audio output by verifying player is available.
  Future<void> initialize() async {
    if (_disposed) {
      throw AudioOutputException('AudioOutput has been disposed');
    }

    // Resolve executable path
    _resolvedExecutable = customExecutablePath ?? _getDefaultExecutable(player);

    // Check executable is available
    if (!await _isExecutableAvailable(_resolvedExecutable!)) {
      throw AudioOutputException(
        'Audio player not found: $_resolvedExecutable (${player.name}). '
        'Install it or configure a different audio_player in config.yaml',
      );
    }

    _log.info('Using audio player: ${player.name} ($_resolvedExecutable)');
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
      // Convert PCM to WAV format
      final wavData = _pcmToWav(audioData, rate, channels, bitsPerSample);

      // Write WAV to temp file
      final tempDir = await Directory.systemTemp.createTemp('audio_output_');
      final tempFile = File('${tempDir.path}/audio.wav');
      await tempFile.writeAsBytes(wavData);
      _log.fine('Wrote ${wavData.length} bytes WAV to ${tempFile.path}');

      // Play using configured player
      final args = _getPlayArgs(tempFile.path);
      _log.fine('Starting: $_resolvedExecutable ${args.join(' ')}');

      _playProcess = await Process.start(_resolvedExecutable!, args);
      _isPlaying = true;
      _log.fine('${player.name} process started (pid: ${_playProcess!.pid})');

      // Capture any stderr for debugging
      _playProcess!.stderr.listen((data) {
        final msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) {
          _log.warning('${player.name} stderr: $msg');
        }
      });

      // Wait for playback to complete
      final exitCode = await _playProcess!.exitCode;
      _log.fine('${player.name} process exited with code: $exitCode');
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
          '${player.name} command failed with exit code $exitCode',
        );
      }
    } on ProcessException catch (e) {
      _isPlaying = false;
      throw AudioOutputException('Failed to play audio', e);
    }
  }

  /// Converts raw PCM data to WAV format by adding header.
  Uint8List _pcmToWav(
    Uint8List pcmData,
    int sampleRate,
    int channels,
    int bitsPerSample,
  ) {
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
      // Play file using configured player
      final args = _getPlayArgs(filePath);
      _log.fine('Playing file: $_resolvedExecutable ${args.join(' ')}');
      _playProcess = await Process.start(_resolvedExecutable!, args);

      _isPlaying = true;

      // Wait for playback to complete
      final exitCode = await _playProcess!.exitCode;
      _isPlaying = false;
      _playProcess = null;

      if (exitCode != 0 && exitCode != -15 && exitCode != -9) {
        throw AudioOutputException(
          '${player.name} command failed with exit code $exitCode',
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
