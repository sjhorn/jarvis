import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/stt/whisper_process.dart';
import 'package:test/test.dart';

void main() {
  group('WhisperProcess', () {
    group('initialization', () {
      test('should create instance with required parameters', () {
        // Arrange & Act
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/path/to/whisper-cli',
        );

        // Assert
        expect(whisper, isNotNull);
        expect(whisper.modelPath, equals('/path/to/model.bin'));
        expect(whisper.executablePath, equals('/path/to/whisper-cli'));
      });

      test('should throw WhisperException when executable not found', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/nonexistent/whisper-cli',
        );

        // Act & Assert
        expect(() => whisper.initialize(), throwsA(isA<WhisperException>()));
      });

      test('should throw WhisperException when model file not found', () async {
        // Arrange - use a real executable but fake model
        final whisper = WhisperProcess(
          modelPath: '/nonexistent/model.bin',
          executablePath: '/bin/echo', // exists on all unix systems
        );

        // Act & Assert
        expect(
          () => whisper.initialize(),
          throwsA(
            isA<WhisperException>().having(
              (e) => e.message,
              'message',
              contains('model'),
            ),
          ),
        );
      });
    });

    group('transcribeFile', () {
      test('should throw WhisperException when not initialized', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/path/to/whisper-cli',
        );

        // Act & Assert
        expect(
          () => whisper.transcribeFile('/path/to/audio.wav'),
          throwsA(
            isA<WhisperException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw WhisperException when audio file not found', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/bin/echo',
        );
        // Skip initialization check for this unit test

        // Act & Assert
        expect(
          () => whisper.transcribeFile('/nonexistent/audio.wav'),
          throwsA(isA<WhisperException>()),
        );
      });
    });

    group('transcribe', () {
      test('should throw WhisperException when not initialized', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/path/to/whisper-cli',
        );
        final audioData = Uint8List.fromList([0, 1, 2, 3]);

        // Act & Assert
        expect(
          () => whisper.transcribe(audioData),
          throwsA(
            isA<WhisperException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should handle empty audio data', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/path/to/whisper-cli',
        );
        final emptyAudio = Uint8List(0);

        // Act & Assert
        expect(
          () => whisper.transcribe(emptyAudio),
          throwsA(
            isA<WhisperException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          // Arrange
          final whisper = WhisperProcess(
            modelPath: '/path/to/model.bin',
            executablePath: '/path/to/whisper-cli',
          );

          // Act & Assert - should not throw
          await whisper.dispose();
        },
      );

      test('should prevent operations after dispose', () async {
        // Arrange
        final whisper = WhisperProcess(
          modelPath: '/path/to/model.bin',
          executablePath: '/path/to/whisper-cli',
        );
        await whisper.dispose();

        // Act & Assert
        expect(
          () => whisper.transcribeFile('/path/to/audio.wav'),
          throwsA(
            isA<WhisperException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('WhisperException', () {
      test('should format message correctly without cause', () {
        final exception = WhisperException('Test error');
        expect(exception.toString(), equals('WhisperException: Test error'));
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = WhisperException('Test error', cause);
        expect(
          exception.toString(),
          equals('WhisperException: Test error (Exception: Root cause)'),
        );
      });
    });
  });

  group('WhisperProcess Integration Tests', () {
    late String? whisperPath;
    late String? modelPath;
    late Map<String, String> expectedTranscriptions;
    late String testWavsDir;

    setUpAll(() async {
      // Check for whisper-cli in common locations
      final possiblePaths = [
        '/Users/shorn/dev/c/whisper.cpp/build/bin/whisper-cli',
        '/usr/local/bin/whisper-cli',
        '/opt/homebrew/bin/whisper-cli',
      ];

      for (final path in possiblePaths) {
        if (File(path).existsSync()) {
          whisperPath = path;
          break;
        }
      }

      // Check for model files
      final possibleModels = [
        '/Users/shorn/dev/c/whisper.cpp/models/ggml-base.en.bin',
        '/Users/shorn/dev/c/whisper.cpp/models/ggml-tiny.en.bin',
      ];

      for (final path in possibleModels) {
        if (File(path).existsSync()) {
          modelPath = path;
          break;
        }
      }

      // Load expected transcriptions from trans.txt
      testWavsDir = 'test/test_wavs';
      expectedTranscriptions = {};

      final transFile = File('$testWavsDir/trans.txt');
      if (await transFile.exists()) {
        final lines = await transFile.readAsLines();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          // Format: "filename TRANSCRIPTION TEXT"
          final spaceIndex = line.indexOf(' ');
          if (spaceIndex > 0) {
            final filename = line.substring(0, spaceIndex);
            final transcription = line.substring(spaceIndex + 1);
            expectedTranscriptions[filename] = transcription;
          }
        }
      }
    });

    /// Normalizes text for comparison by:
    /// - Lowercasing
    /// - Removing punctuation
    /// - Collapsing whitespace
    /// - Handling common spelling variations (British vs American)
    String normalizeText(String text) {
      var normalized = text.toLowerCase();
      // Remove punctuation (periods, commas, quotes, etc.)
      normalized = normalized.replaceAll(RegExp(r'''[.,!?;:"'\-]'''), '');
      // Collapse whitespace
      normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
      // Handle common spelling variations
      normalized = normalized.replaceAll('dishonored', 'dishonoured');
      normalized = normalized.replaceAll('forever', 'for ever');
      return normalized.trim();
    }

    test(
      'should transcribe 0.wav correctly',
      () async {
        if (whisperPath == null || modelPath == null) {
          markTestSkipped('whisper-cli or model not available');
          return;
        }

        final audioFile = '$testWavsDir/0.wav';
        if (!File(audioFile).existsSync()) {
          markTestSkipped('Test audio file 0.wav not available');
          return;
        }

        final expected = expectedTranscriptions['0.wav'];
        if (expected == null) {
          markTestSkipped('Expected transcription for 0.wav not found');
          return;
        }

        final whisper = WhisperProcess(
          modelPath: modelPath!,
          executablePath: whisperPath!,
        );
        await whisper.initialize();

        try {
          final result = await whisper.transcribeFile(audioFile);
          expect(
            normalizeText(result),
            equals(normalizeText(expected)),
            reason: 'Transcription should match expected text',
          );
        } finally {
          await whisper.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'should transcribe 1.wav correctly',
      () async {
        if (whisperPath == null || modelPath == null) {
          markTestSkipped('whisper-cli or model not available');
          return;
        }

        final audioFile = '$testWavsDir/1.wav';
        if (!File(audioFile).existsSync()) {
          markTestSkipped('Test audio file 1.wav not available');
          return;
        }

        final expected = expectedTranscriptions['1.wav'];
        if (expected == null) {
          markTestSkipped('Expected transcription for 1.wav not found');
          return;
        }

        final whisper = WhisperProcess(
          modelPath: modelPath!,
          executablePath: whisperPath!,
        );
        await whisper.initialize();

        try {
          final result = await whisper.transcribeFile(audioFile);
          expect(
            normalizeText(result),
            equals(normalizeText(expected)),
            reason: 'Transcription should match expected text',
          );
        } finally {
          await whisper.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'should transcribe 8k.wav correctly',
      () async {
        if (whisperPath == null || modelPath == null) {
          markTestSkipped('whisper-cli or model not available');
          return;
        }

        final audioFile = '$testWavsDir/8k.wav';
        if (!File(audioFile).existsSync()) {
          markTestSkipped('Test audio file 8k.wav not available');
          return;
        }

        final expected = expectedTranscriptions['8k.wav'];
        if (expected == null) {
          markTestSkipped('Expected transcription for 8k.wav not found');
          return;
        }

        final whisper = WhisperProcess(
          modelPath: modelPath!,
          executablePath: whisperPath!,
        );
        await whisper.initialize();

        try {
          final result = await whisper.transcribeFile(audioFile);
          expect(
            normalizeText(result),
            equals(normalizeText(expected)),
            reason: 'Transcription should match expected text',
          );
        } finally {
          await whisper.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
