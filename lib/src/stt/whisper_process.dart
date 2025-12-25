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
  /// The audio data should be raw PCM (16-bit signed, 16kHz, mono).
  /// A WAV header will be added automatically.
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

    // Write audio to temp file with WAV header
    final tempDir = await Directory.systemTemp.createTemp('whisper_');
    final tempFile = File('${tempDir.path}/audio.wav');

    try {
      // Add WAV header to raw PCM data
      final wavData = _addWavHeader(audioData);
      await tempFile.writeAsBytes(wavData);
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

  /// Creates a WAV file from raw PCM data.
  ///
  /// Assumes 16-bit signed PCM, 16kHz, mono.
  Uint8List _addWavHeader(Uint8List pcmData) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;

    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little); // File size - 8
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, numChannels, Endian.little); // NumChannels
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, byteRate, Endian.little); // ByteRate
    header.setUint16(32, blockAlign, Endian.little); // BlockAlign
    header.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little); // Subchunk2Size

    // Combine header and PCM data
    final wavFile = Uint8List(44 + pcmData.length);
    wavFile.setRange(0, 44, header.buffer.asUint8List());
    wavFile.setRange(44, 44 + pcmData.length, pcmData);

    return wavFile;
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
