import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:jarvis_dart/src/vad/voice_activity_detector.dart';
import 'package:test/test.dart';

void main() {
  group('VoiceActivityDetector', () {
    group('initialization', () {
      test('should create instance with default parameters', () {
        final vad = VoiceActivityDetector();

        expect(vad, isNotNull);
        expect(vad.silenceThreshold, equals(0.01));
        expect(vad.silenceDuration, equals(const Duration(milliseconds: 800)));
      });

      test('should create instance with custom parameters', () {
        final vad = VoiceActivityDetector(
          silenceThreshold: 0.05,
          silenceDuration: const Duration(milliseconds: 500),
        );

        expect(vad.silenceThreshold, equals(0.05));
        expect(vad.silenceDuration, equals(const Duration(milliseconds: 500)));
      });
    });

    group('processAudio', () {
      test('should emit speech event when loud audio is detected', () async {
        final vad = VoiceActivityDetector(silenceThreshold: 0.01);
        final events = <VADEvent>[];
        final subscription = vad.events.listen(events.add);

        // Generate loud audio (simulating speech)
        final loudAudio = _generateAudio(amplitude: 0.5, durationMs: 100);
        vad.processAudio(loudAudio);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(events, isNotEmpty);
        expect(events.first.state, equals(VADState.speech));

        await subscription.cancel();
      });

      test('should emit silence event after silence duration', () async {
        final vad = VoiceActivityDetector(
          silenceThreshold: 0.01,
          silenceDuration: const Duration(milliseconds: 100),
        );
        final events = <VADEvent>[];
        final subscription = vad.events.listen(events.add);

        // First send loud audio (speech)
        final loudAudio = _generateAudio(amplitude: 0.5, durationMs: 100);
        vad.processAudio(loudAudio);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Then send quiet audio chunks (silence) until silence duration is met
        // The VAD only checks elapsed time when processAudio is called
        final quietAudio = _generateAudio(amplitude: 0.001, durationMs: 50);
        for (var i = 0; i < 4; i++) {
          vad.processAudio(quietAudio);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        // Should have speech followed by silence
        expect(events.length, greaterThanOrEqualTo(2));
        expect(events.first.state, equals(VADState.speech));
        expect(events.last.state, equals(VADState.silence));

        await subscription.cancel();
      });

      test('should not emit duplicate events for same state', () async {
        final vad = VoiceActivityDetector(silenceThreshold: 0.01);
        final events = <VADEvent>[];
        final subscription = vad.events.listen(events.add);

        // Send multiple loud audio chunks
        final loudAudio = _generateAudio(amplitude: 0.5, durationMs: 100);
        vad.processAudio(loudAudio);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        vad.processAudio(loudAudio);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        vad.processAudio(loudAudio);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Should only have one speech event (no duplicates)
        final speechEvents = events
            .where((e) => e.state == VADState.speech)
            .toList();
        expect(speechEvents.length, equals(1));

        await subscription.cancel();
      });
    });

    group('reset', () {
      test('should reset state to silence', () async {
        final vad = VoiceActivityDetector(silenceThreshold: 0.01);
        final events = <VADEvent>[];
        final subscription = vad.events.listen(events.add);

        // Trigger speech
        final loudAudio = _generateAudio(amplitude: 0.5, durationMs: 100);
        vad.processAudio(loudAudio);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Reset
        vad.reset();

        // Clear events
        events.clear();

        // Should emit speech again after reset
        vad.processAudio(loudAudio);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(events, isNotEmpty);
        expect(events.first.state, equals(VADState.speech));

        await subscription.cancel();
      });
    });

    group('currentState', () {
      test('should start in silence state', () {
        final vad = VoiceActivityDetector();
        expect(vad.currentState, equals(VADState.silence));
      });

      test('should update state when processing audio', () async {
        final vad = VoiceActivityDetector(silenceThreshold: 0.01);

        expect(vad.currentState, equals(VADState.silence));

        // Send loud audio
        final loudAudio = _generateAudio(amplitude: 0.5, durationMs: 100);
        vad.processAudio(loudAudio);

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(vad.currentState, equals(VADState.speech));
      });
    });

    group('VADEvent', () {
      test('should have correct properties', () {
        final timestamp = DateTime.now();
        final event = VADEvent(state: VADState.speech, timestamp: timestamp);

        expect(event.state, equals(VADState.speech));
        expect(event.timestamp, equals(timestamp));
      });
    });

    group('energy calculation', () {
      test('should detect silence for zero amplitude audio', () async {
        final vad = VoiceActivityDetector(silenceThreshold: 0.01);

        // Generate silent audio (all zeros)
        final silentAudio = Uint8List(3200); // 100ms at 16kHz, 16-bit
        for (var i = 0; i < silentAudio.length; i++) {
          silentAudio[i] = 0;
        }

        vad.processAudio(silentAudio);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(vad.currentState, equals(VADState.silence));
      });
    });
  });
}

/// Generates test audio data with specified amplitude.
Uint8List _generateAudio({
  required double amplitude,
  required int durationMs,
  int sampleRate = 16000,
}) {
  final numSamples = (sampleRate * durationMs / 1000).round();
  final data = ByteData(numSamples * 2); // 16-bit samples
  final random = Random(42); // Fixed seed for reproducibility

  for (var i = 0; i < numSamples; i++) {
    // Generate noise with specified amplitude
    final sample = ((random.nextDouble() * 2 - 1) * amplitude * 32767).round();
    data.setInt16(i * 2, sample, Endian.little);
  }

  return data.buffer.asUint8List();
}
