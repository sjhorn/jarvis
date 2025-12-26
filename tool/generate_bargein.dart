import 'dart:io';

import 'package:jarvis_dart/src/cli/config_loader.dart';
import 'package:jarvis_dart/src/tts/tts_manager.dart';

/// Generates barge-in acknowledgment audio files.
Future<void> main(List<String> args) async {
  const phrases = [
    'Sir?',
    'Yes?',
    'Here.',
    'Ready.',
    'Listening.',
  ];

  print('Generating barge-in acknowledgment audio files...\n');

  final config = await ConfigLoader.fromYamlFile('config.yaml');
  final tts = TtsManager(
    modelPath: config.ttsModelPath,
    tokensPath: config.ttsTokensPath,
    dataDir: config.ttsDataDir,
    nativeLibPath: config.sherpaLibPath,
  );

  print('Initializing TTS...');
  await tts.initialize();

  final outputDir = Directory('assets/bargein');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  for (var i = 0; i < phrases.length; i++) {
    final phrase = phrases[i];
    final filename = 'bargein_${i.toString().padLeft(2, '0')}.wav';
    final filepath = '${outputDir.path}/$filename';

    print('[$i] Generating: "$phrase"');
    final result = await tts.synthesize(phrase);
    final wavBytes = result.toWav();
    await File(filepath).writeAsBytes(wavBytes);
    print('    Saved: $filepath (${wavBytes.length} bytes)');
  }

  await tts.dispose();
  print('\nDone! Generated ${phrases.length} barge-in files.');
}
