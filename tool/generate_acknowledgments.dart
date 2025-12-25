/// Generates acknowledgment audio files using TTS.
///
/// Usage: dart run tool/generate_acknowledgments.dart [config.yaml]
///
/// Requires environment variables or config.yaml for TTS model paths.
library;

import 'dart:io';

import 'package:jarvis/src/audio/acknowledgment_player.dart';
import 'package:jarvis/src/cli/config_loader.dart';
import 'package:jarvis/src/tts/tts_manager.dart';

Future<void> main(List<String> args) async {
  print('Generating acknowledgment audio files...\n');

  // Load config
  late AppConfig config;
  final configPath = args.isNotEmpty ? args[0] : 'config.yaml';

  try {
    if (await File(configPath).exists()) {
      print('Loading config from $configPath');
      config = await ConfigLoader.fromYamlFile(configPath);
    } else {
      print('Loading config from environment variables');
      config = ConfigLoader.fromEnvironment();
    }
  } catch (e) {
    print('Error loading config: $e');
    print('\nMake sure config.yaml exists or environment variables are set.');
    exit(1);
  }

  // Create output directory
  final outputDir = Directory('assets/acknowledgments');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
    print('Created directory: ${outputDir.path}');
  }

  // Initialize TTS
  print('Initializing TTS...');
  final tts = TtsManager(
    modelPath: config.ttsModelPath,
    tokensPath: config.ttsTokensPath,
    dataDir: config.ttsDataDir,
    nativeLibPath: config.sherpaLibPath,
  );
  await tts.initialize();
  print('TTS initialized.\n');

  // Generate audio for each phrase
  final phrases = AcknowledgmentPhrases.defaults;

  for (var i = 0; i < phrases.length; i++) {
    final phrase = phrases[i];
    final filename = 'ack_${i.toString().padLeft(2, '0')}.wav';
    final filepath = '${outputDir.path}/$filename';

    print('[$i/${phrases.length}] Generating: "$phrase"');

    try {
      final result = await tts.synthesize(phrase);
      final wavBytes = result.toWav();
      await File(filepath).writeAsBytes(wavBytes);
      print('  -> Saved: $filepath (${wavBytes.length} bytes)');
    } catch (e) {
      print('  -> Error: $e');
    }
  }

  await tts.dispose();
  print('\nDone! Generated ${phrases.length} acknowledgment files.');
}
