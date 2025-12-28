/// Performance tests for TTS synthesis.
///
/// Run with: dart test test/tts/tts_performance_test.dart --reporter expanded
@Tags(['integration', 'performance'])
library;

import 'dart:io';

import 'package:jarvis_dart/src/tts/isolate_tts_manager.dart';
import 'package:jarvis_dart/src/tts/tts_manager.dart';
import 'package:test/test.dart';

void main() {
  group('TTS Performance Tests', () {
    late TtsManager tts;
    late String? modelPath;
    late String? tokensPath;
    late String? dataDir;
    late String? nativeLibPath;

    setUpAll(() async {
      // Try to find TTS model in common locations
      final home = Platform.environment['HOME'] ?? '.';
      final locations = [
        '$home/.jarvis/models/tts',
        './models/tts',
      ];

      for (final loc in locations) {
        if (await File('$loc/model.onnx').exists()) {
          modelPath = '$loc/model.onnx';
          tokensPath = '$loc/tokens.txt';
          dataDir = '$loc/espeak-ng-data';
          break;
        }
      }

      // Find sherpa native library
      final cacheLocations = [
        '$home/.pub-cache/hosted/pub.dev',
      ];
      for (final cache in cacheLocations) {
        final dir = Directory(cache);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is Directory &&
              entity.path.contains('sherpa_onnx_macos')) {
            final libDir = Directory('${entity.path}/macos');
            if (await libDir.exists()) {
              nativeLibPath = libDir.path;
              break;
            }
          }
        }
        if (nativeLibPath != null) break;
      }

      if (modelPath == null || nativeLibPath == null) {
        print('TTS model or native library not found, skipping tests');
        return;
      }

      print('Model: $modelPath');
      print('Native lib: $nativeLibPath');

      tts = TtsManager(
        modelPath: modelPath!,
        tokensPath: tokensPath!,
        dataDir: dataDir!,
        nativeLibPath: nativeLibPath,
      );
      await tts.initialize();
    });

    tearDownAll(() async {
      await tts.dispose();
    });

    test('measure synthesis time for various sentence lengths', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final sentences = [
        'Yes sir.',
        'I would recommend that book.',
        'For a truly insightful and well-crafted narrative, I would recommend Pride and Prejudice by Jane Austen.',
        "It's a classic for a reason, it explores complex social dynamics and character development with remarkable subtlety.",
        'Alternatively, One Hundred Years of Solitude by Gabriel Garcia Marquez offers a richly imagined and melancholic tale of a family history.',
      ];

      print('\n=== TTS Synthesis Performance ===\n');
      print('Sentence Length (chars) | Synth Time (ms) | Audio Duration (ms) | Ratio');
      print('-' * 80);

      for (final sentence in sentences) {
        final stopwatch = Stopwatch()..start();
        final result = await tts.synthesize(sentence);
        stopwatch.stop();

        final synthMs = stopwatch.elapsedMilliseconds;
        final audioMs = (result.samples.length / result.sampleRate * 1000).round();
        final ratio = (synthMs / audioMs).toStringAsFixed(2);

        print(
          '${sentence.length.toString().padLeft(22)} | '
          '${synthMs.toString().padLeft(15)} | '
          '${audioMs.toString().padLeft(19)} | '
          '${ratio}x',
        );
      }

      print('\n');
    });

    test('measure parallel synthesis capability', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final sentences = [
        'First sentence to synthesize.',
        'Second sentence to synthesize.',
        'Third sentence to synthesize.',
      ];

      print('\n=== Sequential vs Parallel Synthesis ===\n');

      // Sequential synthesis
      final seqStopwatch = Stopwatch()..start();
      for (final sentence in sentences) {
        await tts.synthesize(sentence);
      }
      seqStopwatch.stop();
      print('Sequential (3 sentences): ${seqStopwatch.elapsedMilliseconds}ms');

      // Attempt parallel synthesis (may not work due to FFI constraints)
      final parStopwatch = Stopwatch()..start();
      final futures = sentences.map((s) => tts.synthesize(s)).toList();
      await Future.wait(futures);
      parStopwatch.stop();
      print('Parallel (3 sentences): ${parStopwatch.elapsedMilliseconds}ms');

      final speedup = seqStopwatch.elapsedMilliseconds / parStopwatch.elapsedMilliseconds;
      print('Speedup: ${speedup.toStringAsFixed(2)}x');
      print('\nNote: If speedup ≈ 1.0, FFI calls are blocking and cannot parallelize.');
      print('\n');
    });

    test('measure synthesis during simulated playback', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final sentences = [
        'First sentence.',
        'Second sentence with more words.',
        'Third sentence is the longest of all three.',
      ];

      print('\n=== Pipelined Synthesis Simulation ===\n');

      // Pre-synthesize first sentence
      var synthStopwatch = Stopwatch()..start();
      var currentResult = await tts.synthesize(sentences[0]);
      synthStopwatch.stop();
      var firstSynthMs = synthStopwatch.elapsedMilliseconds;
      print('Initial synthesis (sentence 1): ${firstSynthMs}ms');

      var totalWaitMs = 0;

      for (var i = 0; i < sentences.length; i++) {
        final audioMs =
            (currentResult.samples.length / currentResult.sampleRate * 1000)
                .round();

        // Start next synthesis in parallel
        Future<TtsResult>? nextFuture;
        Stopwatch? nextStopwatch;
        if (i < sentences.length - 1) {
          nextStopwatch = Stopwatch()..start();
          nextFuture = tts.synthesize(sentences[i + 1]);
        }

        // Simulate playback with delay
        final playStart = DateTime.now();
        await Future<void>.delayed(Duration(milliseconds: audioMs));
        final playMs = DateTime.now().difference(playStart).inMilliseconds;

        // Wait for next synthesis
        if (nextFuture != null) {
          final waitStart = DateTime.now();
          currentResult = await nextFuture;
          nextStopwatch!.stop();
          final waitMs = DateTime.now().difference(waitStart).inMilliseconds;
          final synthMs = nextStopwatch.elapsedMilliseconds;

          if (waitMs > 10) {
            totalWaitMs += waitMs;
            print(
              'Sentence ${i + 1}: play=${playMs}ms, '
              'next_synth=${synthMs}ms, wait=${waitMs}ms (BLOCKED)',
            );
          } else {
            print(
              'Sentence ${i + 1}: play=${playMs}ms, '
              'next_synth=${synthMs}ms (ready)',
            );
          }
        } else {
          print('Sentence ${i + 1}: play=${playMs}ms (last)');
        }
      }

      print('\nTotal time waiting for synthesis: ${totalWaitMs}ms');
      if (totalWaitMs > 100) {
        print('WARNING: Synthesis cannot keep up with playback!');
        print('Consider: reducing TTS quality, using faster model, or async processing');
      }
      print('\n');
    });

    test('measure actual LLM response synthesis', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      // Real LLM response that was slow
      final sentences = [
        'For a truly insightful and well-crafted narrative, I would recommend Pride and Prejudice by Jane Austen.',
        "It's a classic for a reason, it explores complex social dynamics and character development with remarkable subtlety.",
        'Alternatively, One Hundred Years of Solitude by Gabriel Garcia Marquez offers a richly imagined and melancholic tale of a family history.',
        'Would you like me to elaborate on either of those, or perhaps suggest a different genre?',
      ];

      print('\n=== Real LLM Response Synthesis ===\n');
      print('Sentence | Length | Synth (ms) | Audio (ms) | Ratio');
      print('-' * 65);

      var totalSynthMs = 0;
      var totalAudioMs = 0;

      for (var i = 0; i < sentences.length; i++) {
        final sentence = sentences[i];
        final stopwatch = Stopwatch()..start();
        final result = await tts.synthesize(sentence);
        stopwatch.stop();

        final synthMs = stopwatch.elapsedMilliseconds;
        final audioMs =
            (result.samples.length / result.sampleRate * 1000).round();
        final ratio = (synthMs / audioMs).toStringAsFixed(2);

        totalSynthMs += synthMs;
        totalAudioMs += audioMs;

        print(
          '${(i + 1).toString().padLeft(8)} | '
          '${sentence.length.toString().padLeft(6)} | '
          '${synthMs.toString().padLeft(10)} | '
          '${audioMs.toString().padLeft(10)} | '
          '${ratio}x',
        );
      }

      print('-' * 65);
      print(
        '   TOTAL |        | '
        '${totalSynthMs.toString().padLeft(10)} | '
        '${totalAudioMs.toString().padLeft(10)} | '
        '${(totalSynthMs / totalAudioMs).toStringAsFixed(2)}x',
      );

      print('\nExpected playback time: ${(totalAudioMs / 1000).toStringAsFixed(1)}s');
      print('Minimum total time (pipelined): ${((totalSynthMs + totalAudioMs - sentences.length * totalAudioMs / sentences.length) / 1000).toStringAsFixed(1)}s');
      print('\n');
    });

    test('benchmark different TTS speeds', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final testSentence =
          'This is a test sentence to measure synthesis speed at different rates.';

      print('\n=== TTS Speed Parameter Impact ===\n');
      print('Speed | Synth Time (ms) | Audio Duration (ms) | Ratio');
      print('-' * 60);

      // Note: speed parameter affects output audio length, not synthesis time
      for (final speed in [0.8, 1.0, 1.2, 1.5]) {
        // Create new TTS with different speed
        final testTts = TtsManager(
          modelPath: modelPath!,
          tokensPath: tokensPath!,
          dataDir: dataDir!,
          nativeLibPath: nativeLibPath,
          speed: speed,
        );
        await testTts.initialize();

        final stopwatch = Stopwatch()..start();
        final result = await testTts.synthesize(testSentence);
        stopwatch.stop();

        final synthMs = stopwatch.elapsedMilliseconds;
        final audioMs =
            (result.samples.length / result.sampleRate * 1000).round();
        final ratio = (synthMs / audioMs).toStringAsFixed(2);

        print(
          '${speed.toStringAsFixed(1).padLeft(5)} | '
          '${synthMs.toString().padLeft(15)} | '
          '${audioMs.toString().padLeft(19)} | '
          '${ratio}x',
        );

        await testTts.dispose();
      }
      print('\n');
    });

    test('compare pre-buffer strategies', () async {
      // This test takes ~2 minutes due to simulated playback
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final sentences = [
        'For a truly insightful and well-crafted narrative, I would recommend Pride and Prejudice by Jane Austen.',
        "It's a classic for a reason, it explores complex social dynamics and character development with remarkable subtlety.",
        'Alternatively, One Hundred Years of Solitude by Gabriel Garcia Marquez offers a richly imagined and melancholic tale of a family history.',
        'Would you like me to elaborate on either of those, or perhaps suggest a different genre?',
      ];

      print('\n=== Pre-Buffer Strategy Comparison ===\n');

      // Strategy 1: Current approach (pre-synth 1, pipeline rest)
      print('Strategy 1: Pre-synth 1, pipeline rest');
      var totalStopwatch = Stopwatch()..start();

      var results = <TtsResult>[];
      results.add(await tts.synthesize(sentences[0]));
      final ttfa1 = totalStopwatch.elapsedMilliseconds;
      print('  Time-to-first-audio: ${ttfa1}ms');

      for (var i = 0; i < sentences.length; i++) {
        Future<TtsResult>? nextFuture;
        if (i < sentences.length - 1) {
          nextFuture = tts.synthesize(sentences[i + 1]);
        }

        // Simulate playback
        final audioMs =
            (results[i].samples.length / results[i].sampleRate * 1000).round();
        await Future<void>.delayed(Duration(milliseconds: audioMs));

        if (nextFuture != null) {
          results.add(await nextFuture);
        }
      }

      totalStopwatch.stop();
      print('  Total time: ${totalStopwatch.elapsedMilliseconds}ms\n');

      // Strategy 2: Pre-synth 2 sentences, pipeline rest
      print('Strategy 2: Pre-synth 2, pipeline rest');
      totalStopwatch = Stopwatch()..start();
      results = [];

      // Pre-synthesize first 2
      results.add(await tts.synthesize(sentences[0]));
      results.add(await tts.synthesize(sentences[1]));
      final ttfa2 = totalStopwatch.elapsedMilliseconds;
      print('  Time-to-first-audio: ${ttfa2}ms');

      for (var i = 0; i < sentences.length; i++) {
        Future<TtsResult>? nextFuture;
        if (i + 2 < sentences.length) {
          nextFuture = tts.synthesize(sentences[i + 2]);
        }

        // Simulate playback
        final audioMs =
            (results[i].samples.length / results[i].sampleRate * 1000).round();
        await Future<void>.delayed(Duration(milliseconds: audioMs));

        if (nextFuture != null) {
          results.add(await nextFuture);
        }
      }

      totalStopwatch.stop();
      print('  Total time: ${totalStopwatch.elapsedMilliseconds}ms\n');

      // Strategy 3: Pre-synth ALL sentences (maximum buffering)
      print('Strategy 3: Pre-synth ALL (maximum buffer)');
      totalStopwatch = Stopwatch()..start();
      results = [];

      // Pre-synthesize all
      for (final sentence in sentences) {
        results.add(await tts.synthesize(sentence));
      }
      final ttfa3 = totalStopwatch.elapsedMilliseconds;
      print('  Time-to-first-audio: ${ttfa3}ms');

      // Simulate playback (no synthesis during playback)
      for (var i = 0; i < sentences.length; i++) {
        final audioMs =
            (results[i].samples.length / results[i].sampleRate * 1000).round();
        await Future<void>.delayed(Duration(milliseconds: audioMs));
      }

      totalStopwatch.stop();
      print('  Total time: ${totalStopwatch.elapsedMilliseconds}ms\n');

      print('Analysis:');
      print('  - Strategy 1 minimizes time-to-first-audio');
      print('  - Strategy 3 minimizes total time (no CPU contention)');
      print('  - Strategy 2 is a balanced approach');
      print('\n');
    });

    test('measure synthesis overhead from concurrent operations', () async {
      if (modelPath == null) {
        markTestSkipped('TTS model not available');
        return;
      }

      final sentence =
          'This is a medium length sentence to test synthesis overhead.';

      print('\n=== Synthesis Overhead from Concurrency ===\n');

      // Measure synthesis alone
      final aloneStopwatch = Stopwatch()..start();
      await tts.synthesize(sentence);
      aloneStopwatch.stop();
      final aloneMs = aloneStopwatch.elapsedMilliseconds;
      print('Synthesis alone: ${aloneMs}ms');

      // Measure synthesis while doing CPU work (simulating audio encoding)
      final busyStopwatch = Stopwatch()..start();
      final synthFuture = tts.synthesize(sentence);

      // Simulate CPU-intensive work during synthesis
      var sum = 0.0;
      for (var i = 0; i < 10000000; i++) {
        sum += i * 0.001;
      }

      await synthFuture;
      busyStopwatch.stop();
      final busyMs = busyStopwatch.elapsedMilliseconds;
      print('Synthesis with CPU work: ${busyMs}ms');

      final overhead = ((busyMs - aloneMs) / aloneMs * 100).round();
      print('Overhead: $overhead%');
      print('(result: $sum)\n'); // Use sum to prevent optimization
    });

    test('compare isolate-based TTS parallelism', () async {
      if (modelPath == null || nativeLibPath == null) {
        markTestSkipped('TTS model or native library not available');
        return;
      }

      final sentences = [
        'For a truly insightful narrative, I would recommend Pride and Prejudice.',
        "It's a classic that explores complex social dynamics with subtlety.",
        'Would you like me to elaborate on that recommendation?',
      ];

      print('\n=== Isolate-based TTS Comparison ===\n');

      // Initialize isolate TTS
      final isolateTts = IsolateTtsManager(
        modelPath: modelPath!,
        tokensPath: tokensPath!,
        dataDir: dataDir!,
        nativeLibPath: nativeLibPath,
      );
      await isolateTts.initialize();

      // Test 1: Regular TTS with simulated playback (sequential due to FFI blocking)
      print('Regular TTS (FFI blocking):');
      var totalStopwatch = Stopwatch()..start();

      var currentResult = await tts.synthesize(sentences[0]);
      final regularTtfa = totalStopwatch.elapsedMilliseconds;

      for (var i = 0; i < sentences.length; i++) {
        Future<TtsResult>? nextFuture;
        if (i < sentences.length - 1) {
          nextFuture = tts.synthesize(sentences[i + 1]);
        }

        // Simulate playback
        final audioMs =
            (currentResult.samples.length / currentResult.sampleRate * 1000)
                .round();
        await Future<void>.delayed(Duration(milliseconds: audioMs));

        if (nextFuture != null) {
          currentResult = await nextFuture;
        }
      }

      totalStopwatch.stop();
      final regularTotal = totalStopwatch.elapsedMilliseconds;
      print('  Time-to-first-audio: ${regularTtfa}ms');
      print('  Total time: ${regularTotal}ms');

      // Test 2: Isolate TTS with simulated playback (true parallel)
      print('\nIsolate TTS (true parallel):');
      totalStopwatch = Stopwatch()..start();

      currentResult = await isolateTts.synthesize(sentences[0]);
      final isolateTtfa = totalStopwatch.elapsedMilliseconds;

      for (var i = 0; i < sentences.length; i++) {
        Future<TtsResult>? nextFuture;
        if (i < sentences.length - 1) {
          nextFuture = isolateTts.synthesize(sentences[i + 1]);
        }

        // Simulate playback - synthesis should run in parallel!
        final audioMs =
            (currentResult.samples.length / currentResult.sampleRate * 1000)
                .round();
        await Future<void>.delayed(Duration(milliseconds: audioMs));

        if (nextFuture != null) {
          currentResult = await nextFuture;
        }
      }

      totalStopwatch.stop();
      final isolateTotal = totalStopwatch.elapsedMilliseconds;
      print('  Time-to-first-audio: ${isolateTtfa}ms');
      print('  Total time: ${isolateTotal}ms');

      // Calculate improvement
      final improvement =
          ((regularTotal - isolateTotal) / regularTotal * 100).round();
      print('\nImprovement: $improvement%');

      if (improvement > 10) {
        print('SUCCESS: Isolate-based TTS provides significant speedup!');
      } else {
        print('NOTE: Limited improvement - may need further optimization.');
      }

      await isolateTts.dispose();
      print('\n');
    });
  });
}
