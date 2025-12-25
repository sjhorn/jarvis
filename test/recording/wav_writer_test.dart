import 'dart:typed_data';

import 'package:jarvis/src/recording/wav_writer.dart';
import 'package:test/test.dart';

void main() {
  group('WavWriter', () {
    test('should create valid WAV header', () {
      final pcmData = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

      final wavData = WavWriter.addWavHeader(pcmData);

      // WAV header is 44 bytes
      expect(wavData.length, equals(44 + pcmData.length));

      // Check RIFF header
      expect(wavData[0], equals(0x52)); // 'R'
      expect(wavData[1], equals(0x49)); // 'I'
      expect(wavData[2], equals(0x46)); // 'F'
      expect(wavData[3], equals(0x46)); // 'F'

      // Check WAVE format
      expect(wavData[8], equals(0x57)); // 'W'
      expect(wavData[9], equals(0x41)); // 'A'
      expect(wavData[10], equals(0x56)); // 'V'
      expect(wavData[11], equals(0x45)); // 'E'
    });

    test('should set correct file size in header', () {
      final pcmData = Uint8List(1000);

      final wavData = WavWriter.addWavHeader(pcmData);

      // File size is stored at offset 4, little-endian
      final byteData = ByteData.sublistView(wavData);
      final fileSize = byteData.getUint32(4, Endian.little);

      // File size = 36 + data size (header is 44 bytes, minus 8 for RIFF+size)
      expect(fileSize, equals(36 + 1000));
    });

    test('should set correct sample rate', () {
      final pcmData = Uint8List(100);

      final wavData = WavWriter.addWavHeader(pcmData);

      // Sample rate is at offset 24, little-endian
      final byteData = ByteData.sublistView(wavData);
      final sampleRate = byteData.getUint32(24, Endian.little);

      expect(sampleRate, equals(16000));
    });

    test('should set mono channel', () {
      final pcmData = Uint8List(100);

      final wavData = WavWriter.addWavHeader(pcmData);

      // NumChannels is at offset 22, little-endian
      final byteData = ByteData.sublistView(wavData);
      final numChannels = byteData.getUint16(22, Endian.little);

      expect(numChannels, equals(1));
    });

    test('should set 16-bit samples', () {
      final pcmData = Uint8List(100);

      final wavData = WavWriter.addWavHeader(pcmData);

      // BitsPerSample is at offset 34, little-endian
      final byteData = ByteData.sublistView(wavData);
      final bitsPerSample = byteData.getUint16(34, Endian.little);

      expect(bitsPerSample, equals(16));
    });

    test('should include PCM data after header', () {
      final pcmData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final wavData = WavWriter.addWavHeader(pcmData);

      // PCM data starts at offset 44
      expect(wavData.sublist(44), equals(pcmData));
    });

    test('should handle empty PCM data', () {
      final pcmData = Uint8List(0);

      final wavData = WavWriter.addWavHeader(pcmData);

      expect(wavData.length, equals(44)); // Just header
    });

    test('should calculate duration correctly', () {
      // 16kHz, 16-bit mono = 32000 bytes per second
      final oneSecondData = Uint8List(32000);

      final durationMs = WavWriter.calculateDurationMs(oneSecondData.length);

      expect(durationMs, equals(1000));
    });

    test('should calculate duration for half second', () {
      // 16kHz, 16-bit mono = 16000 bytes per half second
      final halfSecondData = Uint8List(16000);

      final durationMs = WavWriter.calculateDurationMs(halfSecondData.length);

      expect(durationMs, equals(500));
    });
  });
}
