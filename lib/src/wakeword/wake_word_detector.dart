import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Exception thrown when wake word detection fails.
class WakeWordException implements Exception {
  final String message;
  final Object? cause;

  WakeWordException(this.message, [this.cause]);

  @override
  String toString() =>
      'WakeWordException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Event emitted when a wake word is detected.
class WakeWordEvent {
  final String keyword;
  final DateTime timestamp;

  WakeWordEvent({required this.keyword, required this.timestamp});
}

/// Wake word detector using sherpa_onnx keyword spotter.
class WakeWordDetector {
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final List<String> keywords;
  final String? keywordsFile;
  final int sampleRate;
  final String? nativeLibPath;
  final double keywordsThreshold;
  final double keywordsScore;

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  final _eventController = StreamController<WakeWordEvent>.broadcast();

  bool _disposed = false;
  bool _initialized = false;

  WakeWordDetector({
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    this.keywords = const [],
    this.keywordsFile,
    this.sampleRate = 16000,
    this.nativeLibPath,
    this.keywordsThreshold = 0.01,
    this.keywordsScore = 2.0,
  });

  /// Whether the detector is initialized.
  bool get isInitialized => _initialized;

  /// Stream of wake word detection events.
  Stream<WakeWordEvent> get detections => _eventController.stream;

  /// Initializes the wake word detector with the configured model.
  Future<void> initialize() async {
    if (_disposed) {
      throw WakeWordException('Detector has been disposed');
    }

    // Check if keywords are provided
    if (keywords.isEmpty && keywordsFile == null) {
      throw WakeWordException(
        'No keywords specified. Provide keywords or keywordsFile',
      );
    }

    // Check if keywords file exists if provided
    if (keywordsFile != null && !File(keywordsFile!).existsSync()) {
      throw WakeWordException('Keywords file not found: $keywordsFile');
    }

    // Check if model files exist
    if (!File(encoderPath).existsSync()) {
      throw WakeWordException('Encoder file not found: $encoderPath');
    }
    if (!File(decoderPath).existsSync()) {
      throw WakeWordException('Decoder file not found: $decoderPath');
    }
    if (!File(joinerPath).existsSync()) {
      throw WakeWordException('Joiner file not found: $joinerPath');
    }
    if (!File(tokensPath).existsSync()) {
      throw WakeWordException('Tokens file not found: $tokensPath');
    }

    try {
      // Initialize sherpa_onnx bindings
      sherpa.initBindings(nativeLibPath);

      // Create transducer model config
      final transducerConfig = sherpa.OnlineTransducerModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        joiner: joinerPath,
      );

      // Create model config
      final modelConfig = sherpa.OnlineModelConfig(
        transducer: transducerConfig,
        tokens: tokensPath,
        numThreads: 2,
        provider: 'cpu',
        debug: false,
      );

      // Create feature config
      final featConfig = sherpa.FeatureConfig(
        sampleRate: sampleRate,
        featureDim: 80,
      );

      // Create keyword spotter config
      final config = sherpa.KeywordSpotterConfig(
        feat: featConfig,
        model: modelConfig,
        maxActivePaths: 4,
        numTrailingBlanks: 1,
        keywordsThreshold: keywordsThreshold,
        keywordsScore: keywordsScore,
        keywordsFile: keywordsFile ?? '',
      );

      _spotter = sherpa.KeywordSpotter(config);

      // Create stream
      _stream = _spotter!.createStream();

      _initialized = true;
    } catch (e) {
      throw WakeWordException('Failed to initialize keyword spotter', e);
    }
  }

  /// Processes an audio chunk for wake word detection.
  ///
  /// Audio should be 16-bit signed PCM, little-endian.
  void processAudio(Uint8List audioChunk) {
    if (_disposed) {
      throw WakeWordException('Detector has been disposed');
    }
    if (!_initialized || _stream == null || _spotter == null) {
      throw WakeWordException('Detector not initialized');
    }

    // Convert bytes to Float32List
    final samples = _bytesToFloat32(audioChunk);

    // Accept waveform samples
    _stream!.acceptWaveform(samples: samples, sampleRate: sampleRate);

    // Check for keyword detection
    while (_spotter!.isReady(_stream!)) {
      _spotter!.decode(_stream!);

      final result = _spotter!.getResult(_stream!);
      if (result.keyword.isNotEmpty) {
        _eventController.add(
          WakeWordEvent(keyword: result.keyword, timestamp: DateTime.now()),
        );
        // Reset after detection
        _spotter!.reset(_stream!);
      }
    }
  }

  /// Converts 16-bit PCM bytes to Float32List.
  Float32List _bytesToFloat32(Uint8List bytes) {
    final numSamples = bytes.length ~/ 2;
    final samples = Float32List(numSamples);
    final byteData = ByteData.sublistView(bytes);

    for (var i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      samples[i] = sample / 32768.0;
    }

    return samples;
  }

  /// Resets the detection state.
  void reset() {
    if (_disposed) {
      throw WakeWordException('Detector has been disposed');
    }
    if (!_initialized || _stream == null || _spotter == null) {
      throw WakeWordException('Detector not initialized');
    }

    _spotter!.reset(_stream!);
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (_stream != null) {
      _stream!.free();
      _stream = null;
    }

    if (_spotter != null) {
      _spotter!.free();
      _spotter = null;
    }

    await _eventController.close();
    _initialized = false;
  }
}
