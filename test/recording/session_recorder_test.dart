import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/recording/session_recorder.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late SessionRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_test_');
  });

  tearDown(() async {
    await recorder.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('SessionRecorder', () {
    group('initialization', () {
      test('should create session directory on initialize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );

        await recorder.initialize({});

        final sessionDir = Directory('${tempDir.path}/test_session');
        expect(await sessionDir.exists(), isTrue);
      });

      test('should create audio subdirectory on initialize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );

        await recorder.initialize({});

        final audioDir = Directory('${tempDir.path}/test_session/audio');
        expect(await audioDir.exists(), isTrue);
      });

      test('should create session.jsonl file on initialize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );

        await recorder.initialize({'test': 'config'});

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        expect(await jsonlFile.exists(), isTrue);
      });

      test('should write session_start event on initialize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );

        await recorder.initialize({'systemPrompt': 'Test'});
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        expect(lines.isNotEmpty, isTrue);
        final firstEvent = jsonDecode(lines.first);
        expect(firstEvent['type'], equals('session_start'));
        expect(firstEvent['config']['systemPrompt'], equals('Test'));
      });

      test('should generate session ID if not provided', () async {
        recorder = SessionRecorder(baseDir: tempDir.path);

        await recorder.initialize({});

        expect(recorder.sessionId, isNotEmpty);
        expect(recorder.sessionId, startsWith('session_'));
      });
    });

    group('wake word recording', () {
      test('should write wake_word event', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        await recorder.recordWakeWord('JARVIS');
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final wakeWordEvent = jsonDecode(lines[1]); // Second line
        expect(wakeWordEvent['type'], equals('wake_word'));
        expect(wakeWordEvent['keyword'], equals('JARVIS'));
      });
    });

    group('user audio recording', () {
      test('should save audio file with incrementing number', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        final pcmData = Uint8List.fromList(List.generate(1000, (i) => i % 256));
        final filePath = await recorder.recordUserAudio(pcmData);

        expect(filePath, equals('audio/001_user.wav'));

        final audioFile = File('${tempDir.path}/test_session/audio/001_user.wav');
        expect(await audioFile.exists(), isTrue);
      });

      test('should increment audio file number', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        final pcmData = Uint8List(100);
        await recorder.recordUserAudio(pcmData);
        final secondPath = await recorder.recordUserAudio(pcmData);

        expect(secondPath, equals('audio/002_user.wav'));
      });

      test('should write user_audio event with correct metadata', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        final pcmData = Uint8List(32000); // 1 second of audio at 16kHz 16-bit
        await recorder.recordUserAudio(pcmData);
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final audioEvent = jsonDecode(lines[1]); // Second line
        expect(audioEvent['type'], equals('user_audio'));
        expect(audioEvent['file'], equals('audio/001_user.wav'));
        expect(audioEvent['durationMs'], equals(1000)); // 1 second
        expect(audioEvent['sizeBytes'], equals(32000));
      });
    });

    group('transcription recording', () {
      test('should write transcription event', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        await recorder.recordTranscription('What time is it?', 0);
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final transcriptionEvent = jsonDecode(lines[1]);
        expect(transcriptionEvent['type'], equals('transcription'));
        expect(transcriptionEvent['text'], equals('What time is it?'));
        expect(transcriptionEvent['audioRef'], equals(0));
      });
    });

    group('response recording', () {
      test('should write response event with sentence count', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        await recorder.recordResponse('The time is 10:30. Have a nice day!', 2);
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final responseEvent = jsonDecode(lines[1]);
        expect(responseEvent['type'], equals('response'));
        expect(responseEvent['text'], equals('The time is 10:30. Have a nice day!'));
        expect(responseEvent['sentenceCount'], equals(2));
      });
    });

    group('barge-in tracking', () {
      test('should track speaking state', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        recorder.setSpeakingState(['Sentence one.', 'Sentence two.', 'Sentence three.']);

        expect(recorder.currentSentenceIndex, equals(0));
        expect(recorder.totalSentences, equals(3));
      });

      test('should advance sentence index', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        recorder.setSpeakingState(['Sentence one.', 'Sentence two.']);
        recorder.advanceSentence();

        expect(recorder.currentSentenceIndex, equals(1));
      });

      test('should record barge-in with current state', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        recorder.setSpeakingState(['First.', 'Second.', 'Third.']);
        recorder.advanceSentence(); // Now at index 1
        await recorder.recordBargeIn();
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final bargeInEvent = jsonDecode(lines[1]);
        expect(bargeInEvent['type'], equals('barge_in'));
        expect(bargeInEvent['sentenceIndex'], equals(1));
        expect(bargeInEvent['sentencesTotal'], equals(3));
        expect(bargeInEvent['partialText'], equals('First. Second.'));
      });

      test('should clear speaking state after barge-in', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        recorder.setSpeakingState(['First.', 'Second.']);
        await recorder.recordBargeIn();

        expect(recorder.currentSentenceIndex, equals(0));
        expect(recorder.totalSentences, equals(0));
      });
    });

    group('finalization', () {
      test('should write session_end event on finalize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        // Record some utterances
        await recorder.recordUserAudio(Uint8List(100));
        await recorder.recordUserAudio(Uint8List(100));
        await recorder.finalize();

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        final lastEvent = jsonDecode(lines.last);
        expect(lastEvent['type'], equals('session_end'));
        expect(lastEvent['totalUtterances'], equals(2));
        expect(lastEvent['sessionDurationMs'], isA<int>());
      });

      test('should not write events after finalize', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});
        await recorder.finalize();

        // This should be ignored
        await recorder.recordWakeWord('JARVIS');

        final jsonlFile = File('${tempDir.path}/test_session/session.jsonl');
        final lines = await jsonlFile.readAsLines();

        // Should only have session_start and session_end
        expect(lines.length, equals(2));
      });
    });

    group('error handling', () {
      test('should not throw if recording fails', () async {
        recorder = SessionRecorder(
          baseDir: tempDir.path,
          sessionId: 'test_session',
        );
        await recorder.initialize({});

        // Dispose early to cause potential issues
        await recorder.dispose();

        // Should not throw
        await expectLater(
          recorder.recordWakeWord('JARVIS'),
          completes,
        );
      });
    });
  });
}
