import 'dart:io';

import 'package:jarvis/src/cli/config_loader.dart';
import 'package:jarvis/src/tts/tts_manager.dart';

/// Regenerates a single acknowledgment file.
///
/// Usage: dart run tool/regenerate_ack.dart <index> "<phrase>"
/// Example: dart run tool/regenerate_ack.dart 8 "System active."
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run tool/regenerate_ack.dart <index> "<phrase>"');
    print('Example: dart run tool/regenerate_ack.dart 8 "System active."');
    exit(1);
  }

  final index = int.parse(args[0]);
  final phrase = args[1];
  final filename = 'ack_${index.toString().padLeft(2, '0')}.wav';
  final filepath = 'assets/acknowledgments/$filename';

  print('Regenerating: "$phrase" -> $filepath');

  final config = await ConfigLoader.fromYamlFile('config.yaml');
  final tts = TtsManager(
    modelPath: config.ttsModelPath,
    tokensPath: config.ttsTokensPath,
    dataDir: config.ttsDataDir,
    nativeLibPath: config.sherpaLibPath,
  );

  print('Initializing TTS...');
  await tts.initialize();

  final result = await tts.synthesize(phrase);
  final wavBytes = result.toWav();
  await File(filepath).writeAsBytes(wavBytes);
  print('Saved: $filepath (${wavBytes.length} bytes)');

  await tts.dispose();
  print('Done!');
}
