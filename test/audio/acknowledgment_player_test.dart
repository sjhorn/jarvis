import 'dart:io';
import 'dart:typed_data';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:jarvis/src/audio/acknowledgment_player.dart';
import 'package:jarvis/src/audio/audio_output.dart';

class MockAudioOutput extends Mock implements AudioOutput {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  group('AcknowledgmentPhrases', () {
    test('should have default phrases', () {
      expect(AcknowledgmentPhrases.defaults, isNotEmpty);
      expect(AcknowledgmentPhrases.defaults.length, equals(14));
    });

    test('most default phrases should include sir', () {
      final phrasesWithSir = AcknowledgmentPhrases.defaults
          .where((p) => p.toLowerCase().contains('sir'))
          .length;
      // Most phrases include "sir" but some like "System active." don't
      expect(phrasesWithSir, greaterThanOrEqualTo(12));
    });
  });

  group('AcknowledgmentPlayer', () {
    late MockAudioOutput mockAudioOutput;
    late Directory tempDir;

    setUp(() async {
      mockAudioOutput = MockAudioOutput();
      tempDir = await Directory.systemTemp.createTemp('ack_test_');

      // Setup mock
      when(() => mockAudioOutput.play(any(), audioSampleRate: any(named: 'audioSampleRate')))
          .thenAnswer((_) async {});
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('should initialize with empty directory', () async {
      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();

      expect(player.hasAcknowledgments, isFalse);
      expect(player.count, equals(0));
    });

    test('should load WAV files from directory', () async {
      // Create a test WAV file
      final wavFile = File('${tempDir.path}/test.wav');
      await wavFile.writeAsBytes(_createTestWav());

      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();

      expect(player.hasAcknowledgments, isTrue);
      expect(player.count, equals(1));
    });

    test('should ignore non-WAV files', () async {
      // Create a non-WAV file
      final txtFile = File('${tempDir.path}/test.txt');
      await txtFile.writeAsString('not a wav file');

      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();

      expect(player.hasAcknowledgments, isFalse);
      expect(player.count, equals(0));
    });

    test('should play random acknowledgment', () async {
      // Create test WAV files
      await File('${tempDir.path}/test1.wav').writeAsBytes(_createTestWav());
      await File('${tempDir.path}/test2.wav').writeAsBytes(_createTestWav());

      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();
      await player.playRandom();

      verify(() => mockAudioOutput.play(any(), audioSampleRate: any(named: 'audioSampleRate')))
          .called(1);
    });

    test('should not throw when playing with no acknowledgments', () async {
      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();

      // Should not throw
      await player.playRandom();

      verifyNever(() => mockAudioOutput.play(any(), audioSampleRate: any(named: 'audioSampleRate')));
    });

    test('should handle non-existent directory gracefully', () async {
      final player = AcknowledgmentPlayer(
        audioDirectory: '/nonexistent/path',
        audioOutput: mockAudioOutput,
      );

      // Should not throw
      await player.initialize();

      expect(player.hasAcknowledgments, isFalse);
    });

    test('should dispose cleanly', () async {
      await File('${tempDir.path}/test.wav').writeAsBytes(_createTestWav());

      final player = AcknowledgmentPlayer(
        audioDirectory: tempDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();
      expect(player.count, equals(1));

      await player.dispose();
      expect(player.count, equals(0));
    });
  });

  group('AcknowledgmentPlayer integration', () {
    test('should load actual acknowledgment files if they exist', () async {
      final ackDir = Directory('assets/acknowledgments');
      if (!await ackDir.exists()) {
        // Skip if acknowledgments haven't been generated
        return;
      }

      final mockAudioOutput = MockAudioOutput();
      when(() => mockAudioOutput.play(any(), audioSampleRate: any(named: 'audioSampleRate')))
          .thenAnswer((_) async {});

      final player = AcknowledgmentPlayer(
        audioDirectory: ackDir.path,
        audioOutput: mockAudioOutput,
      );

      await player.initialize();

      expect(player.hasAcknowledgments, isTrue);
      expect(player.count, equals(14));
    });
  });
}

/// Creates a minimal valid WAV file for testing.
Uint8List _createTestWav() {
  const sampleRate = 22050;
  const numSamples = 100;
  const bitsPerSample = 16;
  const numChannels = 1;
  const dataSize = numSamples * numChannels * bitsPerSample ~/ 8;
  const fileSize = 36 + dataSize;

  final buffer = ByteData(44 + dataSize);
  var offset = 0;

  // RIFF header
  buffer.setUint8(offset++, 0x52); // R
  buffer.setUint8(offset++, 0x49); // I
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  buffer.setUint8(offset++, 0x57); // W
  buffer.setUint8(offset++, 0x41); // A
  buffer.setUint8(offset++, 0x56); // V
  buffer.setUint8(offset++, 0x45); // E

  // fmt chunk
  buffer.setUint8(offset++, 0x66); // f
  buffer.setUint8(offset++, 0x6D); // m
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x20); // (space)
  buffer.setUint32(offset, 16, Endian.little);
  offset += 4;
  buffer.setUint16(offset, 1, Endian.little); // PCM
  offset += 2;
  buffer.setUint16(offset, numChannels, Endian.little);
  offset += 2;
  buffer.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  buffer.setUint32(offset, sampleRate * numChannels * bitsPerSample ~/ 8, Endian.little);
  offset += 4;
  buffer.setUint16(offset, numChannels * bitsPerSample ~/ 8, Endian.little);
  offset += 2;
  buffer.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;

  // data chunk
  buffer.setUint8(offset++, 0x64); // d
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  // Fill with silence
  for (var i = 0; i < dataSize; i++) {
    buffer.setUint8(offset++, 0);
  }

  return buffer.buffer.asUint8List();
}
