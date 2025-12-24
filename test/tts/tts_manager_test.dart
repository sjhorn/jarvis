import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/tts/tts_manager.dart';
import 'package:test/test.dart';

void main() {
  group('TtsManager', () {
    group('initialization', () {
      test('should create instance with required parameters', () {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(tts, isNotNull);
        expect(tts.modelPath, equals('models/tts/model.onnx'));
        expect(tts.tokensPath, equals('models/tts/tokens.txt'));
      });

      test('should create instance with custom parameters', () {
        final tts = TtsManager(
          modelPath: 'custom/model.onnx',
          tokensPath: 'custom/tokens.txt',
          dataDir: 'custom/espeak-ng-data',
          speed: 1.5,
          speakerId: 2,
        );

        expect(tts.speed, equals(1.5));
        expect(tts.speakerId, equals(2));
      });

      test('should have default speed of 1.0', () {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(tts.speed, equals(1.0));
      });

      test('should have default speakerId of 0', () {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(tts.speakerId, equals(0));
      });
    });

    group('initialize', () {
      test('should throw TtsException when model file not found', () async {
        final tts = TtsManager(
          modelPath: '/nonexistent/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(() => tts.initialize(), throwsA(isA<TtsException>()));
      });

      test('should throw TtsException when tokens file not found', () async {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: '/nonexistent/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(() => tts.initialize(), throwsA(isA<TtsException>()));
      });
    });

    group('synthesize', () {
      test('should throw when synthesizing without initialization', () async {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(
          () => tts.synthesize('Hello world'),
          throwsA(
            isA<TtsException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw when synthesizing empty text', () async {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );

        expect(
          () => tts.synthesize(''),
          throwsA(
            isA<TtsException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });
    });

    group('synthesizeToFile', () {
      test(
        'should throw when synthesizing to file without initialization',
        () async {
          final tts = TtsManager(
            modelPath: 'models/tts/model.onnx',
            tokensPath: 'models/tts/tokens.txt',
            dataDir: 'models/tts/espeak-ng-data',
          );

          expect(
            () => tts.synthesizeToFile('Hello', '/tmp/output.wav'),
            throwsA(
              isA<TtsException>().having(
                (e) => e.message,
                'message',
                contains('not initialized'),
              ),
            ),
          );
        },
      );
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          final tts = TtsManager(
            modelPath: 'models/tts/model.onnx',
            tokensPath: 'models/tts/tokens.txt',
            dataDir: 'models/tts/espeak-ng-data',
          );

          await tts.dispose();
          // Should not throw
        },
      );

      test('should prevent operations after dispose', () async {
        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
        );
        await tts.dispose();

        expect(
          () => tts.synthesize('Hello'),
          throwsA(
            isA<TtsException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('TtsException', () {
      test('should format message correctly without cause', () {
        final exception = TtsException('Test error');
        expect(exception.toString(), equals('TtsException: Test error'));
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = TtsException('Test error', cause);
        expect(
          exception.toString(),
          equals('TtsException: Test error (Exception: Root cause)'),
        );
      });
    });

    group('TtsResult', () {
      test('should have correct properties', () {
        final samples = Float32List.fromList([0.1, 0.2, 0.3]);
        final result = TtsResult(samples: samples, sampleRate: 22050);

        expect(result.samples, equals(samples));
        expect(result.sampleRate, equals(22050));
      });

      test('should calculate duration correctly', () {
        // 22050 samples at 22050 Hz = 1 second
        final samples = Float32List(22050);
        final result = TtsResult(samples: samples, sampleRate: 22050);

        expect(result.duration, equals(const Duration(seconds: 1)));
      });
    });
  });

  group('TtsManager Integration Tests', () {
    late String? nativeLibPath;
    late bool modelsExist;

    setUpAll(() {
      // Check for native library
      const libPath = 'native/sherpa-onnx-v1.12.20-osx-universal2-shared/lib';
      if (Directory(libPath).existsSync()) {
        nativeLibPath = libPath;
      }

      // Check for model files
      modelsExist =
          File('models/tts/model.onnx').existsSync() &&
          File('models/tts/tokens.txt').existsSync() &&
          Directory('models/tts/espeak-ng-data').existsSync();
    });

    test('should initialize successfully with valid model', () async {
      if (nativeLibPath == null || !modelsExist) {
        markTestSkipped('TTS models or native library not available');
        return;
      }

      final tts = TtsManager(
        modelPath: 'models/tts/model.onnx',
        tokensPath: 'models/tts/tokens.txt',
        dataDir: 'models/tts/espeak-ng-data',
        nativeLibPath: nativeLibPath,
      );

      try {
        await tts.initialize();
        expect(tts.isInitialized, isTrue);
        expect(tts.sampleRate, greaterThan(0));
      } finally {
        await tts.dispose();
      }
    });

    test(
      'should synthesize text to audio',
      () async {
        if (nativeLibPath == null || !modelsExist) {
          markTestSkipped('TTS models or native library not available');
          return;
        }

        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
          nativeLibPath: nativeLibPath,
        );

        try {
          await tts.initialize();

          final result = await tts.synthesize('Hello, I am Jarvis.');

          expect(result, isNotNull);
          expect(result.samples, isNotEmpty);
          expect(result.sampleRate, greaterThan(0));
          expect(result.duration.inMilliseconds, greaterThan(0));
        } finally {
          await tts.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'should synthesize to WAV file',
      () async {
        if (nativeLibPath == null || !modelsExist) {
          markTestSkipped('TTS models or native library not available');
          return;
        }

        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
          nativeLibPath: nativeLibPath,
        );

        final outputPath = '/tmp/tts_test_output.wav';

        try {
          await tts.initialize();

          await tts.synthesizeToFile('Testing audio synthesis.', outputPath);

          final outputFile = File(outputPath);
          expect(outputFile.existsSync(), isTrue);
          expect(
            outputFile.lengthSync(),
            greaterThan(44),
          ); // WAV header is 44 bytes
        } finally {
          await tts.dispose();
          // Clean up test file
          try {
            File(outputPath).deleteSync();
          } catch (_) {}
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'should respect speed parameter',
      () async {
        if (nativeLibPath == null || !modelsExist) {
          markTestSkipped('TTS models or native library not available');
          return;
        }

        final slowTts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
          nativeLibPath: nativeLibPath,
          speed: 0.5, // Half speed = longer audio
        );

        final fastTts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
          nativeLibPath: nativeLibPath,
          speed: 2.0, // Double speed = shorter audio
        );

        try {
          await slowTts.initialize();
          await fastTts.initialize();

          const testText = 'Hello world';
          final slowResult = await slowTts.synthesize(testText);
          final fastResult = await fastTts.synthesize(testText);

          // Slow should have more samples than fast
          expect(
            slowResult.samples.length,
            greaterThan(fastResult.samples.length),
          );
        } finally {
          await slowTts.dispose();
          await fastTts.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'should convert Float32 samples to 16-bit PCM',
      () async {
        if (nativeLibPath == null || !modelsExist) {
          markTestSkipped('TTS models or native library not available');
          return;
        }

        final tts = TtsManager(
          modelPath: 'models/tts/model.onnx',
          tokensPath: 'models/tts/tokens.txt',
          dataDir: 'models/tts/espeak-ng-data',
          nativeLibPath: nativeLibPath,
        );

        try {
          await tts.initialize();

          final result = await tts.synthesize('Test');
          final pcm16 = result.toPcm16();

          // Each float sample becomes 2 bytes
          expect(pcm16.length, equals(result.samples.length * 2));
        } finally {
          await tts.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
