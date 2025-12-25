import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jarvis/src/recording/wav_writer.dart';
import 'package:jarvis/src/stt/whisper_process.dart';

/// Replays a recorded session for debugging and verification.
///
/// Usage: dart run tool/replay_session.dart <session_path> [options]
///
/// Options:
///   --transcribe    Re-transcribe audio and compare with recorded
///   --play          Play back audio files
///   --verbose       Show detailed event data
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: dart run tool/replay_session.dart <session_path> [options]');
    print('');
    print('Options:');
    print('  --transcribe    Re-transcribe audio and compare with recorded');
    print('  --play          Play back audio files');
    print('  --verbose       Show detailed event data');
    exit(1);
  }

  final sessionPath = arguments[0];
  final transcribe = arguments.contains('--transcribe');
  final playAudio = arguments.contains('--play');
  final verbose = arguments.contains('--verbose');

  final sessionDir = Directory(sessionPath);
  if (!await sessionDir.exists()) {
    stderr.writeln('Error: Session directory not found: $sessionPath');
    exit(1);
  }

  final jsonlFile = File('$sessionPath/session.jsonl');
  if (!await jsonlFile.exists()) {
    stderr.writeln('Error: session.jsonl not found in $sessionPath');
    exit(1);
  }

  print('='.padRight(60, '='));
  print('Session Replay: ${sessionPath.split('/').last}');
  print('='.padRight(60, '='));
  print('');

  // Parse events
  final lines = await jsonlFile.readAsLines();
  final events = <Map<String, dynamic>>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    events.add(jsonDecode(line) as Map<String, dynamic>);
  }

  print('Total events: ${events.length}');
  print('');

  // Initialize Whisper if transcribing
  WhisperProcess? whisper;
  if (transcribe) {
    final configFile = File('config.yaml');
    if (!await configFile.exists()) {
      stderr.writeln('Error: config.yaml not found (needed for --transcribe)');
      exit(1);
    }

    // Simple config parsing for whisper paths
    final configContent = await configFile.readAsString();
    final whisperModel = _extractYamlValue(configContent, 'whisper_model_path');
    final whisperExec = _extractYamlValue(configContent, 'whisper_executable');

    if (whisperModel == null || whisperExec == null) {
      stderr.writeln('Error: whisper_model_path or whisper_executable not found in config');
      exit(1);
    }

    print('Initializing Whisper...');
    whisper = WhisperProcess(
      modelPath: whisperModel,
      executablePath: whisperExec,
    );
    await whisper.initialize();
    print('Whisper ready.');
    print('');
  }

  // Track conversation flow
  var utteranceCount = 0;
  var bargeInCount = 0;
  DateTime? sessionStart;
  DateTime? lastEventTime;

  // Process events
  for (var i = 0; i < events.length; i++) {
    final event = events[i];
    final type = event['type'] as String;
    final timestamp = DateTime.parse(event['timestamp'] as String);

    // Calculate time delta
    String timeDelta = '';
    if (lastEventTime != null) {
      final delta = timestamp.difference(lastEventTime!);
      timeDelta = ' (+${delta.inMilliseconds}ms)';
    }
    lastEventTime = timestamp;

    switch (type) {
      case 'session_start':
        sessionStart = timestamp;
        print('[$i] SESSION START$timeDelta');
        if (verbose) {
          final config = event['config'] as Map<String, dynamic>;
          print('    Follow-up: ${config['enableFollowUp']}');
          print('    Barge-in: ${config['enableBargeIn']}');
          print('    Whisper: ${config['whisperModel']}');
          print('    LLM: ${config['llamaModel']}');
        }

      case 'wake_word':
        final keyword = event['keyword'] as String;
        print('[$i] WAKE WORD: "$keyword"$timeDelta');

      case 'user_audio':
        utteranceCount++;
        final file = event['file'] as String;
        final durationMs = event['durationMs'] as int;
        final sizeBytes = event['sizeBytes'] as int;
        print('[$i] USER AUDIO #$utteranceCount: $file (${durationMs}ms, ${sizeBytes}B)$timeDelta');

        if (transcribe && whisper != null) {
          final audioFile = File('$sessionPath/$file');
          if (await audioFile.exists()) {
            final wavData = await audioFile.readAsBytes();
            // Strip WAV header to get PCM
            final pcmData = Uint8List.sublistView(wavData, WavWriter.headerSize);

            print('    Transcribing...');
            final result = await whisper.transcribe(pcmData);
            print('    Re-transcribed: "$result"');
          } else {
            print('    Audio file not found!');
          }
        }

        if (playAudio) {
          final audioFile = File('$sessionPath/$file');
          if (await audioFile.exists()) {
            print('    Playing...');
            final result = await Process.run('afplay', [audioFile.path]);
            if (result.exitCode != 0) {
              print('    Playback failed: ${result.stderr}');
            }
          }
        }

      case 'transcription':
        final text = event['text'] as String;
        final audioRef = event['audioRef'] as int;
        print('[$i] TRANSCRIPTION (ref:$audioRef): "$text"$timeDelta');

      case 'response':
        final text = event['text'] as String;
        final sentenceCount = event['sentenceCount'] as int;
        print('[$i] RESPONSE ($sentenceCount sentences): "$text"$timeDelta');

      case 'barge_in':
        bargeInCount++;
        final sentenceIndex = event['sentenceIndex'] as int;
        final sentencesTotal = event['sentencesTotal'] as int;
        final partialText = event['partialText'] as String;
        print('[$i] BARGE-IN #$bargeInCount: sentence ${sentenceIndex + 1}/$sentencesTotal$timeDelta');
        if (verbose) {
          print('    Partial: "$partialText"');
        }

      case 'session_end':
        final totalUtterances = event['totalUtterances'] as int;
        final sessionDurationMs = event['sessionDurationMs'] as int;
        print('[$i] SESSION END: $totalUtterances utterances, ${sessionDurationMs}ms$timeDelta');

      default:
        print('[$i] $type$timeDelta');
        if (verbose) {
          print('    $event');
        }
    }
  }

  print('');
  print('-'.padRight(60, '-'));
  print('Summary:');
  print('  Utterances: $utteranceCount');
  print('  Barge-ins: $bargeInCount');
  if (sessionStart != null && lastEventTime != null) {
    final duration = lastEventTime!.difference(sessionStart!);
    print('  Duration: ${duration.inSeconds}s');
  }
  print('-'.padRight(60, '-'));

  // Cleanup
  await whisper?.dispose();
}

/// Extracts a simple string value from YAML content.
String? _extractYamlValue(String yaml, String key) {
  final pattern = RegExp('^$key:\\s*(.+)\$', multiLine: true);
  final match = pattern.firstMatch(yaml);
  if (match != null) {
    return match.group(1)?.trim();
  }
  return null;
}
