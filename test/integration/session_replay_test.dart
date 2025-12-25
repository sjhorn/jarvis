import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/recording/wav_writer.dart';
import 'package:test/test.dart';

/// Integration tests that replay recorded sessions to verify behavior.
///
/// These tests use recorded session data to verify that:
/// 1. Audio is correctly transcribed
/// 2. Barge-in detection works
/// 3. Follow-up listening works after barge-in
///
/// Run with: dart test test/integration/session_replay_test.dart
void main() {
  group('Session Replay', () {
    test('should parse session JSONL correctly', () async {
      // Find a session to test with
      final sessionsDir = Directory('sessions');
      if (!await sessionsDir.exists()) {
        markTestSkipped('No sessions directory found');
        return;
      }

      final sessions = await sessionsDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();

      if (sessions.isEmpty) {
        markTestSkipped('No session recordings found');
        return;
      }

      // Use the most recent session
      sessions.sort((a, b) => b.path.compareTo(a.path));
      final sessionPath = sessions.first.path;

      final jsonlFile = File('$sessionPath/session.jsonl');
      expect(await jsonlFile.exists(), isTrue);

      final lines = await jsonlFile.readAsLines();
      expect(lines, isNotEmpty);

      // Parse all events
      final events = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        events.add(jsonDecode(line) as Map<String, dynamic>);
      }

      // Verify structure
      expect(events.first['type'], equals('session_start'));
      expect(events.first['config'], isA<Map>());
    });

    test('should have valid WAV files for each user_audio event', () async {
      final sessionsDir = Directory('sessions');
      if (!await sessionsDir.exists()) {
        markTestSkipped('No sessions directory found');
        return;
      }

      final sessions = await sessionsDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();

      if (sessions.isEmpty) {
        markTestSkipped('No session recordings found');
        return;
      }

      sessions.sort((a, b) => b.path.compareTo(a.path));
      final sessionPath = sessions.first.path;

      final jsonlFile = File('$sessionPath/session.jsonl');
      final lines = await jsonlFile.readAsLines();

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;

        if (event['type'] == 'user_audio') {
          final filePath = '$sessionPath/${event['file']}';
          final audioFile = File(filePath);
          expect(await audioFile.exists(), isTrue,
              reason: 'Audio file should exist: $filePath');

          // Verify WAV header
          final bytes = await audioFile.readAsBytes();
          expect(bytes.length, greaterThan(WavWriter.headerSize));

          // Check RIFF header
          expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('RIFF'));
          expect(String.fromCharCodes(bytes.sublist(8, 12)), equals('WAVE'));

          // Verify duration matches metadata
          final pcmSize = bytes.length - WavWriter.headerSize;
          final expectedDurationMs = WavWriter.calculateDurationMs(pcmSize);
          expect(event['durationMs'], equals(expectedDurationMs));
        }
      }
    });

    test('barge-in events should have valid sentence tracking', () async {
      final sessionsDir = Directory('sessions');
      if (!await sessionsDir.exists()) {
        markTestSkipped('No sessions directory found');
        return;
      }

      final sessions = await sessionsDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();

      if (sessions.isEmpty) {
        markTestSkipped('No session recordings found');
        return;
      }

      sessions.sort((a, b) => b.path.compareTo(a.path));
      final sessionPath = sessions.first.path;

      final jsonlFile = File('$sessionPath/session.jsonl');
      final lines = await jsonlFile.readAsLines();

      String? lastResponse;
      int? lastSentenceCount;

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;

        if (event['type'] == 'response') {
          lastResponse = event['text'] as String;
          lastSentenceCount = event['sentenceCount'] as int;
        }

        if (event['type'] == 'barge_in') {
          // Verify barge-in references valid response
          expect(lastResponse, isNotNull,
              reason: 'Barge-in should follow a response');
          expect(lastSentenceCount, isNotNull);

          final sentenceIndex = event['sentenceIndex'] as int;
          final sentencesTotal = event['sentencesTotal'] as int;

          expect(sentencesTotal, equals(lastSentenceCount),
              reason: 'Barge-in sentencesTotal should match response sentenceCount');
          expect(sentenceIndex, lessThan(sentencesTotal),
              reason: 'Sentence index should be within bounds');
          expect(sentenceIndex, greaterThanOrEqualTo(0));

          // Verify partial text is subset of full response (normalize whitespace)
          final partialText = event['partialText'] as String;
          final normalizedPartial = partialText.replaceAll(RegExp(r'\s+'), ' ').trim();
          final normalizedResponse = lastResponse!.replaceAll(RegExp(r'\s+'), ' ').trim();
          expect(normalizedResponse.contains(normalizedPartial.split('.').first.trim()),
              isTrue,
              reason: 'Partial text should be part of response');
        }
      }
    });

    test('should detect missing follow-up after barge-in', () async {
      final sessionsDir = Directory('sessions');
      if (!await sessionsDir.exists()) {
        markTestSkipped('No sessions directory found');
        return;
      }

      final sessions = await sessionsDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();

      if (sessions.isEmpty) {
        markTestSkipped('No session recordings found');
        return;
      }

      sessions.sort((a, b) => b.path.compareTo(a.path));
      final sessionPath = sessions.first.path;

      final jsonlFile = File('$sessionPath/session.jsonl');
      final lines = await jsonlFile.readAsLines();

      final events = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        events.add(jsonDecode(line) as Map<String, dynamic>);
      }

      // Check for barge-ins without follow-up
      final issues = <String>[];

      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        if (event['type'] == 'barge_in') {
          // Check if this is the last event or if there's no user_audio after
          if (i == events.length - 1) {
            issues.add('Barge-in at index $i is last event (no follow-up captured)');
          } else {
            final nextEvent = events[i + 1];
            // Allow session_end after barge-in (user chose to end)
            if (nextEvent['type'] != 'user_audio' &&
                nextEvent['type'] != 'session_end' &&
                nextEvent['type'] != 'wake_word') {
              issues.add(
                  'Barge-in at index $i followed by ${nextEvent['type']} instead of user_audio');
            }
          }
        }
      }

      if (issues.isNotEmpty) {
        print('Potential barge-in issues found:');
        for (final issue in issues) {
          print('  - $issue');
        }
        // This is informational - the test passes but logs issues
      }
    });
  });

  group('Session Timing Analysis', () {
    test('should measure response-to-barge-in latency', () async {
      final sessionsDir = Directory('sessions');
      if (!await sessionsDir.exists()) {
        markTestSkipped('No sessions directory found');
        return;
      }

      final sessions = await sessionsDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();

      if (sessions.isEmpty) {
        markTestSkipped('No session recordings found');
        return;
      }

      sessions.sort((a, b) => b.path.compareTo(a.path));
      final sessionPath = sessions.first.path;

      final jsonlFile = File('$sessionPath/session.jsonl');
      final lines = await jsonlFile.readAsLines();

      DateTime? lastResponseTime;
      String? lastResponseText;

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        final timestamp = DateTime.parse(event['timestamp'] as String);

        if (event['type'] == 'response') {
          lastResponseTime = timestamp;
          lastResponseText = event['text'] as String;
        }

        if (event['type'] == 'barge_in' && lastResponseTime != null) {
          final latency = timestamp.difference(lastResponseTime!);
          final sentenceCount = event['sentencesTotal'] as int;
          final avgPerSentence = latency.inMilliseconds / sentenceCount;

          print('Response: "${lastResponseText!.substring(0, 50.clamp(0, lastResponseText!.length))}..."');
          print('  Barge-in after: ${latency.inMilliseconds}ms');
          print('  Sentences: $sentenceCount');
          print('  Avg per sentence: ${avgPerSentence.round()}ms');
          print('');

          // TTS should be roughly 1-2 seconds per sentence
          // If it's much longer, there might be an issue
          if (avgPerSentence > 3000) {
            print('  WARNING: Slow TTS detected (>3s per sentence)');
          }
        }
      }
    });
  });
}
