import 'dart:convert';

import 'package:jarvis/src/recording/session_event.dart';
import 'package:test/test.dart';

void main() {
  group('SessionEvent', () {
    group('SessionStartEvent', () {
      test('should serialize to JSON with correct type', () {
        final event = SessionStartEvent(
          config: {'systemPrompt': 'Test prompt', 'enableBargeIn': true},
        );

        final json = event.toJson();

        expect(json['type'], equals('session_start'));
        expect(json['timestamp'], isA<String>());
        expect(json['config'], equals({'systemPrompt': 'Test prompt', 'enableBargeIn': true}));
      });

      test('should produce valid single-line JSON', () {
        final event = SessionStartEvent(config: {'test': 'value'});

        final jsonLine = event.toJsonLine();

        expect(jsonLine.contains('\n'), isFalse);
        expect(() => jsonDecode(jsonLine), returnsNormally);
      });

      test('should use ISO 8601 timestamp format', () {
        final event = SessionStartEvent(config: {});

        final json = event.toJson();
        final timestamp = json['timestamp'] as String;

        // ISO 8601 format check
        expect(DateTime.tryParse(timestamp), isNotNull);
      });
    });

    group('WakeWordEvent', () {
      test('should serialize with keyword', () {
        final event = WakeWordEvent(keyword: 'JARVIS');

        final json = event.toJson();

        expect(json['type'], equals('wake_word'));
        expect(json['keyword'], equals('JARVIS'));
        expect(json['timestamp'], isA<String>());
      });
    });

    group('UserAudioEvent', () {
      test('should serialize with file path and duration', () {
        final event = UserAudioEvent(
          file: 'audio/001_user.wav',
          durationMs: 1500,
          sizeBytes: 48000,
        );

        final json = event.toJson();

        expect(json['type'], equals('user_audio'));
        expect(json['file'], equals('audio/001_user.wav'));
        expect(json['durationMs'], equals(1500));
        expect(json['sizeBytes'], equals(48000));
      });
    });

    group('TranscriptionEvent', () {
      test('should serialize with text and audio reference', () {
        final event = TranscriptionEvent(
          text: 'What time is it?',
          audioRef: 0,
        );

        final json = event.toJson();

        expect(json['type'], equals('transcription'));
        expect(json['text'], equals('What time is it?'));
        expect(json['audioRef'], equals(0));
      });
    });

    group('ResponseEvent', () {
      test('should serialize with text and sentence count', () {
        final event = ResponseEvent(
          text: 'The current time is 10:30. Would you like to set a reminder?',
          sentenceCount: 2,
        );

        final json = event.toJson();

        expect(json['type'], equals('response'));
        expect(json['text'], equals('The current time is 10:30. Would you like to set a reminder?'));
        expect(json['sentenceCount'], equals(2));
      });
    });

    group('BargeInEvent', () {
      test('should serialize with sentence index and partial text', () {
        final event = BargeInEvent(
          sentenceIndex: 1,
          sentencesTotal: 3,
          partialText: 'The current time is 10:30.',
        );

        final json = event.toJson();

        expect(json['type'], equals('barge_in'));
        expect(json['sentenceIndex'], equals(1));
        expect(json['sentencesTotal'], equals(3));
        expect(json['partialText'], equals('The current time is 10:30.'));
      });
    });

    group('SessionEndEvent', () {
      test('should serialize with session statistics', () {
        final event = SessionEndEvent(
          totalUtterances: 5,
          sessionDurationMs: 300000,
        );

        final json = event.toJson();

        expect(json['type'], equals('session_end'));
        expect(json['totalUtterances'], equals(5));
        expect(json['sessionDurationMs'], equals(300000));
      });
    });

    group('Custom timestamp', () {
      test('should allow setting custom timestamp', () {
        final customTime = DateTime(2024, 1, 15, 10, 30, 45);
        final event = WakeWordEvent(keyword: 'JARVIS', timestamp: customTime);

        final json = event.toJson();

        expect(json['timestamp'], equals('2024-01-15T10:30:45.000'));
      });
    });
  });
}
