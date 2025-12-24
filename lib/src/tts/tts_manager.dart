import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Exception thrown when TTS operations fail.
class TtsException implements Exception {
  final String message;
  final Object? cause;

  TtsException(this.message, [this.cause]);

  @override
  String toString() =>
      'TtsException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Result of text-to-speech synthesis.
class TtsResult {
  final Float32List samples;
  final int sampleRate;

  TtsResult({required this.samples, required this.sampleRate});

  /// Duration of the generated audio.
  Duration get duration {
    if (sampleRate == 0) return Duration.zero;
    return Duration(
      microseconds: (samples.length / sampleRate * 1000000).round(),
    );
  }

  /// Converts Float32 samples to 16-bit signed PCM.
  Uint8List toPcm16() {
    final pcmData = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      // Clamp to -1.0 to 1.0 range and convert to 16-bit
      final clampedSample = samples[i].clamp(-1.0, 1.0);
      final intSample = (clampedSample * 32767).round();
      pcmData.setInt16(i * 2, intSample, Endian.little);
    }
    return pcmData.buffer.asUint8List();
  }
}

/// Text-to-speech manager using sherpa_onnx VITS model.
class TtsManager {
  final String modelPath;
  final String tokensPath;
  final String dataDir;
  final double speed;
  final int speakerId;
  final String? nativeLibPath;

  sherpa.OfflineTts? _tts;
  bool _disposed = false;
  bool _initialized = false;

  TtsManager({
    required this.modelPath,
    required this.tokensPath,
    required this.dataDir,
    this.speed = 1.0,
    this.speakerId = 0,
    this.nativeLibPath,
  });

  /// Whether the TTS engine is initialized.
  bool get isInitialized => _initialized;

  /// Sample rate of the TTS model.
  int get sampleRate {
    if (!_initialized || _tts == null) {
      throw TtsException('TTS not initialized');
    }
    return _tts!.sampleRate;
  }

  /// Initializes the TTS engine with the configured model.
  Future<void> initialize() async {
    if (_disposed) {
      throw TtsException('TTS has been disposed');
    }

    // Check if model files exist
    if (!File(modelPath).existsSync()) {
      throw TtsException('Model file not found: $modelPath');
    }
    if (!File(tokensPath).existsSync()) {
      throw TtsException('Tokens file not found: $tokensPath');
    }
    if (!Directory(dataDir).existsSync()) {
      throw TtsException('Data directory not found: $dataDir');
    }

    try {
      // Initialize sherpa_onnx bindings
      sherpa.initBindings(nativeLibPath);

      // Create TTS config for VITS model
      final vitsConfig = sherpa.OfflineTtsVitsModelConfig(
        model: modelPath,
        tokens: tokensPath,
        dataDir: dataDir,
      );

      final modelConfig = sherpa.OfflineTtsModelConfig(
        vits: vitsConfig,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      );

      final config = sherpa.OfflineTtsConfig(model: modelConfig);

      _tts = sherpa.OfflineTts(config);
      _initialized = true;
    } catch (e) {
      throw TtsException('Failed to initialize TTS', e);
    }
  }

  /// Synthesizes text to audio samples.
  Future<TtsResult> synthesize(String text) async {
    if (text.isEmpty) {
      throw TtsException('Cannot synthesize empty text');
    }
    if (_disposed) {
      throw TtsException('TTS has been disposed');
    }
    if (!_initialized || _tts == null) {
      throw TtsException('TTS not initialized');
    }

    try {
      final generated = _tts!.generate(
        text: text,
        sid: speakerId,
        speed: speed,
      );

      return TtsResult(
        samples: generated.samples,
        sampleRate: generated.sampleRate,
      );
    } catch (e) {
      throw TtsException('Failed to synthesize text', e);
    }
  }

  /// Synthesizes text and saves to a WAV file.
  Future<void> synthesizeToFile(String text, String outputPath) async {
    if (_disposed) {
      throw TtsException('TTS has been disposed');
    }
    if (!_initialized) {
      throw TtsException('TTS not initialized');
    }

    final result = await synthesize(text);

    // Write WAV file
    final wavData = _createWavFile(result.samples, result.sampleRate);
    await File(outputPath).writeAsBytes(wavData);
  }

  /// Creates a WAV file from Float32 samples.
  Uint8List _createWavFile(Float32List samples, int sampleRate) {
    final numChannels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = samples.length * blockAlign;
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
    buffer.setUint8(13, 0x6d); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size
    buffer.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
    buffer.setUint16(22, numChannels, Endian.little);
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

    // Write audio data
    for (var i = 0; i < samples.length; i++) {
      final clampedSample = samples[i].clamp(-1.0, 1.0);
      final intSample = (clampedSample * 32767).round();
      buffer.setInt16(44 + i * 2, intSample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (_tts != null) {
      _tts!.free();
      _tts = null;
    }
    _initialized = false;
  }
}
