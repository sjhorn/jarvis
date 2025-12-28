import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'tts_manager.dart';

/// Message types for isolate communication.
enum _TtsMessageType { init, synthesize, dispose }

/// Request message to the TTS isolate.
class _TtsRequest {
  final _TtsMessageType type;
  final SendPort replyPort;
  final dynamic data;

  _TtsRequest(this.type, this.replyPort, [this.data]);
}

/// Configuration for TTS isolate initialization.
class _TtsConfig {
  final String modelPath;
  final String tokensPath;
  final String dataDir;
  final double speed;
  final int speakerId;
  final String? nativeLibPath;

  _TtsConfig({
    required this.modelPath,
    required this.tokensPath,
    required this.dataDir,
    required this.speed,
    required this.speakerId,
    this.nativeLibPath,
  });
}

/// Text-to-speech manager that runs synthesis in a separate isolate.
///
/// This allows synthesis to run in parallel with audio playback since
/// FFI calls in the isolate don't block the main thread.
class IsolateTtsManager {
  final String modelPath;
  final String tokensPath;
  final String dataDir;
  final double speed;
  final int speakerId;
  final String? nativeLibPath;

  Isolate? _isolate;
  SendPort? _sendPort;
  bool _disposed = false;
  bool _initialized = false;
  int _sampleRate = 0;

  IsolateTtsManager({
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
    if (!_initialized) {
      throw TtsException('TTS not initialized');
    }
    return _sampleRate;
  }

  /// Initializes the TTS engine in a separate isolate.
  Future<void> initialize() async {
    if (_disposed) {
      throw TtsException('TTS has been disposed');
    }
    if (_initialized) return;

    // Create receive port for the isolate to send back its SendPort
    final receivePort = ReceivePort();

    // Spawn the isolate
    _isolate = await Isolate.spawn(
      _ttsIsolateEntry,
      receivePort.sendPort,
    );

    // Wait for the isolate's SendPort
    _sendPort = await receivePort.first as SendPort;
    receivePort.close();

    // Initialize TTS in the isolate
    final initCompleter = Completer<int>();
    final initReceivePort = ReceivePort();

    _sendPort!.send(_TtsRequest(
      _TtsMessageType.init,
      initReceivePort.sendPort,
      _TtsConfig(
        modelPath: modelPath,
        tokensPath: tokensPath,
        dataDir: dataDir,
        speed: speed,
        speakerId: speakerId,
        nativeLibPath: nativeLibPath,
      ),
    ));

    initReceivePort.listen((message) {
      if (message is int) {
        initCompleter.complete(message);
      } else if (message is String) {
        initCompleter.completeError(TtsException(message));
      }
      initReceivePort.close();
    });

    _sampleRate = await initCompleter.future;
    _initialized = true;
  }

  /// Synthesizes text to audio samples.
  ///
  /// This runs in a separate isolate, allowing true parallel execution
  /// with audio playback on the main thread.
  Future<TtsResult> synthesize(String text) async {
    if (text.isEmpty) {
      throw TtsException('Cannot synthesize empty text');
    }
    if (_disposed) {
      throw TtsException('TTS has been disposed');
    }
    if (!_initialized || _sendPort == null) {
      throw TtsException('TTS not initialized');
    }

    final completer = Completer<TtsResult>();
    final receivePort = ReceivePort();

    _sendPort!.send(_TtsRequest(
      _TtsMessageType.synthesize,
      receivePort.sendPort,
      text,
    ));

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        completer.complete(TtsResult(
          samples: message['samples'] as Float32List,
          sampleRate: message['sampleRate'] as int,
        ));
      } else if (message is String) {
        completer.completeError(TtsException(message));
      }
      receivePort.close();
    });

    return completer.future;
  }

  /// Disposes of resources and kills the isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    if (_sendPort != null) {
      final receivePort = ReceivePort();
      _sendPort!.send(_TtsRequest(
        _TtsMessageType.dispose,
        receivePort.sendPort,
      ));

      // Wait briefly for cleanup, then kill
      await receivePort.first.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      receivePort.close();
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initialized = false;
  }
}

/// Entry point for the TTS isolate.
void _ttsIsolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  sherpa.OfflineTts? tts;
  double speed = 1.0;
  int speakerId = 0;

  receivePort.listen((message) {
    if (message is! _TtsRequest) return;

    switch (message.type) {
      case _TtsMessageType.init:
        try {
          final config = message.data as _TtsConfig;
          speed = config.speed;
          speakerId = config.speakerId;

          sherpa.initBindings(config.nativeLibPath);

          final vitsConfig = sherpa.OfflineTtsVitsModelConfig(
            model: config.modelPath,
            tokens: config.tokensPath,
            dataDir: config.dataDir,
          );

          final modelConfig = sherpa.OfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          );

          final ttsConfig = sherpa.OfflineTtsConfig(model: modelConfig);
          tts = sherpa.OfflineTts(ttsConfig);

          message.replyPort.send(tts!.sampleRate);
        } catch (e) {
          message.replyPort.send('Failed to initialize TTS: $e');
        }

      case _TtsMessageType.synthesize:
        try {
          if (tts == null) {
            message.replyPort.send('TTS not initialized');
            return;
          }

          final text = message.data as String;
          final generated = tts!.generate(
            text: text,
            sid: speakerId,
            speed: speed,
          );

          message.replyPort.send({
            'samples': generated.samples,
            'sampleRate': generated.sampleRate,
          });
        } catch (e) {
          message.replyPort.send('Synthesis failed: $e');
        }

      case _TtsMessageType.dispose:
        tts?.free();
        tts = null;
        message.replyPort.send(true);
        receivePort.close();
    }
  });
}
