import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/audio/audio_output.dart';
import 'package:test/test.dart';

void main() {
  group('AudioOutput', () {
    group('initialization', () {
      test('should create instance with default parameters', () {
        final output = AudioOutput();

        expect(output, isNotNull);
        expect(output.sampleRate, equals(16000));
        expect(output.channels, equals(1));
        expect(output.bitsPerSample, equals(16));
      });

      test('should create instance with custom parameters', () {
        final output = AudioOutput(
          sampleRate: 44100,
          channels: 2,
          bitsPerSample: 24,
        );

        expect(output.sampleRate, equals(44100));
        expect(output.channels, equals(2));
        expect(output.bitsPerSample, equals(24));
      });

      test('should throw AudioOutputException when player not found', () async {
        final output = AudioOutput(
          player: AudioPlayer.play,
          customExecutablePath: '/nonexistent/play',
        );

        expect(() => output.initialize(), throwsA(isA<AudioOutputException>()));
      });
    });

    group('playback state', () {
      test('should not be playing initially', () {
        final output = AudioOutput();
        expect(output.isPlaying, isFalse);
      });

      test('should throw when playing without initialization', () async {
        final output = AudioOutput();
        final audioData = Uint8List.fromList([0, 1, 2, 3]);

        expect(
          () => output.play(audioData),
          throwsA(
            isA<AudioOutputException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw when playing empty audio', () async {
        final output = AudioOutput();
        final emptyAudio = Uint8List(0);

        expect(
          () => output.play(emptyAudio),
          throwsA(
            isA<AudioOutputException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });
    });

    group('playFile', () {
      test('should throw when playing file without initialization', () async {
        final output = AudioOutput();

        expect(
          () => output.playFile('/path/to/audio.wav'),
          throwsA(
            isA<AudioOutputException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw when file does not exist', () async {
        final output = AudioOutput();

        expect(
          () => output.playFile('/nonexistent/audio.wav'),
          throwsA(isA<AudioOutputException>()),
        );
      });
    });

    group('stop', () {
      test('should be safe to call stop when not playing', () async {
        final output = AudioOutput();
        // Should not throw
        await output.stop();
      });
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          final output = AudioOutput();
          await output.dispose();
          // Should not throw
        },
      );

      test('should prevent operations after dispose', () async {
        final output = AudioOutput();
        await output.dispose();
        final audioData = Uint8List.fromList([0, 1, 2, 3]);

        expect(
          () => output.play(audioData),
          throwsA(
            isA<AudioOutputException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('AudioOutputException', () {
      test('should format message correctly without cause', () {
        final exception = AudioOutputException('Test error');
        expect(
          exception.toString(),
          equals('AudioOutputException: Test error'),
        );
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = AudioOutputException('Test error', cause);
        expect(
          exception.toString(),
          equals('AudioOutputException: Test error (Exception: Root cause)'),
        );
      });
    });
  });

  group('AudioOutput Integration Tests', () {
    late AudioOutput? output;

    setUpAll(() async {
      // Try to auto-detect an available player
      try {
        output = await AudioOutput.autoDetect();
        await output!.initialize();
      } catch (_) {
        output = null;
      }
    });

    tearDownAll(() async {
      await output?.dispose();
    });

    test('should initialize successfully', () async {
      if (output == null) {
        markTestSkipped('No audio player available');
        return;
      }

      expect(output!.isPlaying, isFalse);
    });

    test('should play raw audio data', () async {
      if (output == null) {
        markTestSkipped('No audio player available');
        return;
      }

      // Generate a short sine wave tone (440Hz for 100ms)
      final audioData = _generateSineWave(
        frequency: 440,
        durationMs: 100,
        sampleRate: 16000,
      );

      await output!.play(audioData);

      // Wait for playback to complete
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(output!.isPlaying, isFalse);
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('should play audio file', () async {
      if (output == null) {
        markTestSkipped('No audio player available');
        return;
      }

      // Check if test audio exists
      const testAudioPath = 'test/test_wavs/8k.wav';
      if (!File(testAudioPath).existsSync()) {
        markTestSkipped('Test audio file not available');
        return;
      }

      await output!.playFile(testAudioPath);

      // Wait for playback to start
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // It should be playing or have finished
      // (short audio may finish quickly)
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'should be able to stop playback',
      () async {
        if (output == null) {
          markTestSkipped('No audio player available');
          return;
        }

        // Create a separate output for this test since we need fresh state
        final testOutput = await AudioOutput.autoDetect();
        await testOutput.initialize();

        try {
          // Generate a longer tone
          final audioData = _generateSineWave(
            frequency: 440,
            durationMs: 2000,
            sampleRate: 16000,
          );

          // Start playing
          unawaited(testOutput.play(audioData));

          // Wait a bit then stop
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await testOutput.stop();

          expect(testOutput.isPlaying, isFalse);
        } finally {
          await testOutput.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });
}

/// Generates a sine wave for testing audio playback.
Uint8List _generateSineWave({
  required int frequency,
  required int durationMs,
  required int sampleRate,
}) {
  final numSamples = (sampleRate * durationMs / 1000).round();
  final data = ByteData(numSamples * 2); // 16-bit samples

  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    // Sine wave with amplitude 0.5 to avoid clipping
    final sample = (0.5 * 32767 * _sin(2 * 3.14159 * frequency * t)).round();
    data.setInt16(i * 2, sample, Endian.little);
  }

  return data.buffer.asUint8List();
}

double _sin(double x) {
  // Simple sin approximation for test purposes
  // Taylor series: sin(x) ≈ x - x³/6 + x⁵/120
  x = x % (2 * 3.14159);
  if (x > 3.14159) x -= 2 * 3.14159;
  final x2 = x * x;
  return x * (1 - x2 / 6 * (1 - x2 / 20));
}

/// Helper to avoid waiting for futures in tests where we want fire-and-forget.
void unawaited(Future<void> future) {}
