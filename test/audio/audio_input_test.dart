import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/audio/audio_input.dart';
import 'package:test/test.dart';

void main() {
  group('AudioInput', () {
    group('initialization', () {
      test('should create instance with default parameters', () {
        final input = AudioInput();

        expect(input, isNotNull);
        expect(input.sampleRate, equals(16000));
        expect(input.channels, equals(1));
        expect(input.bitsPerSample, equals(16));
      });

      test('should create instance with custom parameters', () {
        final input = AudioInput(
          sampleRate: 44100,
          channels: 2,
          bitsPerSample: 24,
        );

        expect(input.sampleRate, equals(44100));
        expect(input.channels, equals(2));
        expect(input.bitsPerSample, equals(24));
      });

      test('should throw AudioInputException when rec not found', () async {
        final input = AudioInput(executablePath: '/nonexistent/rec');

        expect(() => input.initialize(), throwsA(isA<AudioInputException>()));
      });
    });

    group('recording state', () {
      test('should not be recording initially', () {
        final input = AudioInput();
        expect(input.isRecording, isFalse);
      });

      test(
        'should throw when starting recording without initialization',
        () async {
          final input = AudioInput();

          expect(
            () => input.startRecording(),
            throwsA(
              isA<AudioInputException>().having(
                (e) => e.message,
                'message',
                contains('not initialized'),
              ),
            ),
          );
        },
      );

      test('should throw when stopping recording without starting', () async {
        final input = AudioInput();

        expect(
          () => input.stopRecording(),
          throwsA(
            isA<AudioInputException>().having(
              (e) => e.message.toLowerCase(),
              'message',
              contains('not'),
            ),
          ),
        );
      });
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          final input = AudioInput();
          await input.dispose();
          // Should not throw
        },
      );

      test('should prevent operations after dispose', () async {
        final input = AudioInput();
        await input.dispose();

        expect(
          () => input.startRecording(),
          throwsA(
            isA<AudioInputException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('AudioInputException', () {
      test('should format message correctly without cause', () {
        final exception = AudioInputException('Test error');
        expect(exception.toString(), equals('AudioInputException: Test error'));
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = AudioInputException('Test error', cause);
        expect(
          exception.toString(),
          equals('AudioInputException: Test error (Exception: Root cause)'),
        );
      });
    });
  });

  group('AudioInput Integration Tests', () {
    late String? recPath;

    setUpAll(() {
      // Check for rec command
      final possiblePaths = [
        '/opt/homebrew/bin/rec',
        '/usr/local/bin/rec',
        '/usr/bin/rec',
      ];

      for (final path in possiblePaths) {
        if (File(path).existsSync()) {
          recPath = path;
          break;
        }
      }
    });

    test('should initialize successfully', () async {
      if (recPath == null) {
        markTestSkipped('rec command not available');
        return;
      }

      final input = AudioInput(executablePath: recPath!);
      await input.initialize();

      expect(input.isRecording, isFalse);

      await input.dispose();
    });

    test(
      'should record audio for a short duration',
      () async {
        if (recPath == null) {
          markTestSkipped('rec command not available');
          return;
        }

        final input = AudioInput(
          executablePath: recPath!,
          sampleRate: 16000,
          channels: 1,
        );
        await input.initialize();

        try {
          // Start recording
          await input.startRecording();
          expect(input.isRecording, isTrue);

          // Record for 500ms
          await Future<void>.delayed(const Duration(milliseconds: 500));

          // Stop and get audio
          final audioData = await input.stopRecording();
          expect(input.isRecording, isFalse);

          // Should have captured some audio data
          // At 16kHz, 16-bit mono, 500ms should be ~16000 bytes
          expect(audioData, isA<Uint8List>());
          expect(audioData.length, greaterThan(0));
        } finally {
          await input.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'should emit audio data via stream while recording',
      () async {
        if (recPath == null) {
          markTestSkipped('rec command not available');
          return;
        }

        final input = AudioInput(
          executablePath: recPath!,
          sampleRate: 16000,
          channels: 1,
        );
        await input.initialize();

        try {
          final chunks = <Uint8List>[];
          final subscription = input.audioStream.listen(chunks.add);

          await input.startRecording();

          // Record for 300ms
          await Future<void>.delayed(const Duration(milliseconds: 300));

          await input.stopRecording();
          await subscription.cancel();

          // Should have received some audio chunks
          expect(chunks, isNotEmpty);
        } finally {
          await input.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'should handle start/stop/start cycle',
      () async {
        if (recPath == null) {
          markTestSkipped('rec command not available');
          return;
        }

        final input = AudioInput(executablePath: recPath!);
        await input.initialize();

        try {
          // First recording
          await input.startRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final audio1 = await input.stopRecording();
          expect(audio1.length, greaterThan(0));

          // Second recording
          await input.startRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final audio2 = await input.stopRecording();
          expect(audio2.length, greaterThan(0));
        } finally {
          await input.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
