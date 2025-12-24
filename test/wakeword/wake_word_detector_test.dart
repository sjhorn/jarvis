import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:jarvis/src/wakeword/wake_word_detector.dart';
import 'package:test/test.dart';

void main() {
  group('WakeWordDetector', () {
    group('initialization', () {
      test('should create instance with required parameters', () {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        expect(detector, isNotNull);
        expect(detector.keywords, equals(['HEY JARVIS']));
      });

      test('should create instance with multiple keywords', () {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS', 'HELLO JARVIS', 'OK JARVIS'],
        );

        expect(detector.keywords.length, equals(3));
      });

      test('should have default sample rate of 16000', () {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        expect(detector.sampleRate, equals(16000));
      });
    });

    group('initialize', () {
      test('should throw WakeWordException when encoder not found', () async {
        final detector = WakeWordDetector(
          encoderPath: '/nonexistent/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        expect(() => detector.initialize(), throwsA(isA<WakeWordException>()));
      });

      test('should throw WakeWordException when tokens not found', () async {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: '/nonexistent/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        expect(() => detector.initialize(), throwsA(isA<WakeWordException>()));
      });

      test('should throw WakeWordException with empty keywords', () async {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: [],
        );

        expect(
          () => detector.initialize(),
          throwsA(
            isA<WakeWordException>().having(
              (e) => e.message,
              'message',
              contains('keyword'),
            ),
          ),
        );
      });
    });

    group('processAudio', () {
      test('should throw when processing without initialization', () async {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        final audio = Uint8List(3200); // 100ms at 16kHz

        expect(
          () => detector.processAudio(audio),
          throwsA(
            isA<WakeWordException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });
    });

    group('reset', () {
      test('should throw when resetting without initialization', () async {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );

        expect(
          () => detector.reset(),
          throwsA(
            isA<WakeWordException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          final detector = WakeWordDetector(
            encoderPath: 'models/kws/encoder.onnx',
            decoderPath: 'models/kws/decoder.onnx',
            joinerPath: 'models/kws/joiner.onnx',
            tokensPath: 'models/kws/tokens.txt',
            keywords: ['HEY JARVIS'],
          );

          await detector.dispose();
          // Should not throw
        },
      );

      test('should prevent operations after dispose', () async {
        final detector = WakeWordDetector(
          encoderPath: 'models/kws/encoder.onnx',
          decoderPath: 'models/kws/decoder.onnx',
          joinerPath: 'models/kws/joiner.onnx',
          tokensPath: 'models/kws/tokens.txt',
          keywords: ['HEY JARVIS'],
        );
        await detector.dispose();

        final audio = Uint8List(3200);

        expect(
          () => detector.processAudio(audio),
          throwsA(
            isA<WakeWordException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('WakeWordException', () {
      test('should format message correctly without cause', () {
        final exception = WakeWordException('Test error');
        expect(exception.toString(), equals('WakeWordException: Test error'));
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = WakeWordException('Test error', cause);
        expect(
          exception.toString(),
          equals('WakeWordException: Test error (Exception: Root cause)'),
        );
      });
    });

    group('WakeWordEvent', () {
      test('should have correct properties', () {
        final timestamp = DateTime.now();
        final event = WakeWordEvent(
          keyword: 'HEY JARVIS',
          timestamp: timestamp,
        );

        expect(event.keyword, equals('HEY JARVIS'));
        expect(event.timestamp, equals(timestamp));
      });
    });
  });

  group('WakeWordDetector Integration Tests', () {
    late String? nativeLibPath;
    late bool modelExists;
    late String modelDir;

    setUpAll(() {
      // Check for native library
      const libPath = 'native/sherpa-onnx-v1.12.20-osx-universal2-shared/lib';
      if (Directory(libPath).existsSync()) {
        nativeLibPath = libPath;
      }

      // Check for model files
      modelDir =
          'models/kws/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';
      modelExists =
          File(
            '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          ).existsSync() &&
          File(
            '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          ).existsSync() &&
          File(
            '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
          ).existsSync() &&
          File('$modelDir/tokens.txt').existsSync();
    });

    test('should initialize successfully with valid model', () async {
      if (nativeLibPath == null || !modelExists) {
        markTestSkipped('KWS models or native library not available');
        return;
      }

      final detector = WakeWordDetector(
        encoderPath: '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
        decoderPath: '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
        joinerPath: '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
        tokensPath: '$modelDir/tokens.txt',
        keywordsFile: '$modelDir/keywords.txt',
        nativeLibPath: nativeLibPath,
      );

      try {
        await detector.initialize();
        expect(detector.isInitialized, isTrue);
      } finally {
        await detector.dispose();
      }
    });

    test(
      'should process audio without errors',
      () async {
        if (nativeLibPath == null || !modelExists) {
          markTestSkipped('KWS models or native library not available');
          return;
        }

        // Check for test wav file
        final testWavPath = '$modelDir/test_wavs/0.wav';
        if (!File(testWavPath).existsSync()) {
          markTestSkipped('Test WAV file not available');
          return;
        }

        final detector = WakeWordDetector(
          encoderPath: '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          decoderPath: '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          joinerPath: '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
          tokensPath: '$modelDir/tokens.txt',
          keywordsFile: '$modelDir/keywords.txt',
          nativeLibPath: nativeLibPath,
        );

        try {
          await detector.initialize();

          final events = <WakeWordEvent>[];
          final subscription = detector.detections.listen(events.add);

          // Load test audio
          final audioBytes = await File(testWavPath).readAsBytes();
          // Skip WAV header (44 bytes)
          final audioData = audioBytes.sublist(44);

          // Process audio in chunks - should not throw
          const chunkSize = 3200; // 100ms at 16kHz, 16-bit
          for (var i = 0; i < audioData.length; i += chunkSize) {
            final end = (i + chunkSize).clamp(0, audioData.length);
            final chunk = Uint8List.fromList(audioData.sublist(i, end));
            detector.processAudio(chunk);
          }

          // Give time for processing
          await Future<void>.delayed(const Duration(milliseconds: 500));

          await subscription.cancel();

          // Test passes if no errors - detection depends on audio content
          // The test audio may or may not contain keywords
          expect(detector.isInitialized, isTrue);
        } finally {
          await detector.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'should not emit event for non-matching audio',
      () async {
        if (nativeLibPath == null || !modelExists) {
          markTestSkipped('KWS models or native library not available');
          return;
        }

        final detector = WakeWordDetector(
          encoderPath: '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          decoderPath: '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
          joinerPath: '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
          tokensPath: '$modelDir/tokens.txt',
          keywordsFile: '$modelDir/keywords.txt',
          nativeLibPath: nativeLibPath,
        );

        try {
          await detector.initialize();

          final events = <WakeWordEvent>[];
          final subscription = detector.detections.listen(events.add);

          // Generate random noise (not wake word)
          final noise = _generateNoise(durationMs: 500, sampleRate: 16000);
          detector.processAudio(noise);

          // Give time for processing
          await Future<void>.delayed(const Duration(milliseconds: 300));

          await subscription.cancel();

          // Should not detect any keyword
          expect(events, isEmpty);
        } finally {
          await detector.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('should reset detection state', () async {
      if (nativeLibPath == null || !modelExists) {
        markTestSkipped('KWS models or native library not available');
        return;
      }

      final detector = WakeWordDetector(
        encoderPath: '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
        decoderPath: '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
        joinerPath: '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
        tokensPath: '$modelDir/tokens.txt',
        keywordsFile: '$modelDir/keywords.txt',
        nativeLibPath: nativeLibPath,
      );

      try {
        await detector.initialize();

        // Process some audio
        final noise = _generateNoise(durationMs: 100, sampleRate: 16000);
        detector.processAudio(noise);

        // Reset
        detector.reset();

        // Should not throw and should continue to work
        detector.processAudio(noise);
      } finally {
        await detector.dispose();
      }
    });
  });
}

/// Generates random noise audio data.
Uint8List _generateNoise({required int durationMs, required int sampleRate}) {
  final numSamples = (sampleRate * durationMs / 1000).round();
  final data = ByteData(numSamples * 2); // 16-bit samples
  final random = Random(42); // Fixed seed for reproducibility

  for (var i = 0; i < numSamples; i++) {
    // Generate low amplitude noise
    final sample = ((random.nextDouble() * 2 - 1) * 0.1 * 32767).round();
    data.setInt16(i * 2, sample, Endian.little);
  }

  return data.buffer.asUint8List();
}
