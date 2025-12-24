import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Exception thrown by WhisperProcess operations.
class WhisperException implements Exception {
  final String message;
  final Object? cause;

  WhisperException(this.message, [this.cause]);

  @override
  String toString() =>
      'WhisperException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Wrapper for whisper.cpp speech-to-text via process pipe.
class WhisperProcess {
  final String modelPath;
  final String executablePath;
  final Duration timeout;

  bool _initialized = false;
  bool _disposed = false;

  WhisperProcess({
    required this.modelPath,
    required this.executablePath,
    this.timeout = const Duration(minutes: 2),
  });

  /// Initializes the whisper process by validating paths.
  Future<void> initialize() async {
    if (_disposed) {
      throw WhisperException('WhisperProcess has been disposed');
    }

    // Check executable exists
    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw WhisperException(
        'Whisper executable not found at: $executablePath',
      );
    }

    // Check model exists
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw WhisperException('Whisper model not found at: $modelPath');
    }

    _initialized = true;
  }

  /// Transcribes audio data to text.
  ///
  /// The audio data should be in WAV format (16-bit PCM, 16kHz, mono).
  Future<String> transcribe(Uint8List audioData) async {
    if (audioData.isEmpty) {
      throw WhisperException('Audio data is empty');
    }
    if (_disposed) {
      throw WhisperException('WhisperProcess has been disposed');
    }
    if (!_initialized) {
      throw WhisperException('WhisperProcess not initialized');
    }

    // Write audio to temp file
    final tempDir = await Directory.systemTemp.createTemp('whisper_');
    final tempFile = File('${tempDir.path}/audio.wav');

    try {
      await tempFile.writeAsBytes(audioData);
      return await transcribeFile(tempFile.path);
    } finally {
      // Clean up temp files
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  }

  /// Transcribes an audio file to text.
  Future<String> transcribeFile(String filePath) async {
    if (_disposed) {
      throw WhisperException('WhisperProcess has been disposed');
    }
    if (!_initialized) {
      throw WhisperException('WhisperProcess not initialized');
    }

    // Check audio file exists
    final audioFile = File(filePath);
    if (!await audioFile.exists()) {
      throw WhisperException('Audio file not found at: $filePath');
    }

    try {
      // Run whisper-cli
      // Usage: whisper-cli -m model.bin audio.wav
      final result = await Process.run(
        executablePath,
        [
          '-m',
          modelPath,
          '-nt', // no timestamps
          '-np', // no prints (less verbose)
          filePath,
        ],
        stderrEncoding: const SystemEncoding(),
        stdoutEncoding: const SystemEncoding(),
      ).timeout(timeout);

      if (result.exitCode != 0) {
        throw WhisperException(
          'Whisper process failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }

      // Parse the output
      final output = result.stdout as String;
      return _parseOutput(output);
    } on TimeoutException {
      throw WhisperException('Whisper transcription timed out after $timeout');
    } on ProcessException catch (e) {
      throw WhisperException('Failed to run whisper process', e);
    }
  }

  /// Parses whisper output to extract transcription text.
  String _parseOutput(String output) {
    // Whisper outputs each segment on a line, possibly with timestamps
    // With -nt flag, we should get cleaner output
    // Clean up and return the text
    final lines = output.split('\n');
    final textLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip whisper info/debug lines (they start with various prefixes)
      if (trimmed.startsWith('whisper_') ||
          trimmed.startsWith('main:') ||
          trimmed.startsWith('system_info:') ||
          trimmed.contains('audio ctx size') ||
          trimmed.contains('processing') ||
          trimmed.contains('total time') ||
          trimmed.contains('output_') ||
          trimmed.startsWith('[')) {
        continue;
      }

      // This should be actual transcription text
      textLines.add(trimmed);
    }

    return textLines.join(' ').trim();
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    _disposed = true;
    _initialized = false;
  }
}
