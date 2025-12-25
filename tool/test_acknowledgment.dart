/// Quick test for acknowledgment playback.
import 'dart:io';

import 'package:jarvis/src/audio/acknowledgment_player.dart';
import 'package:jarvis/src/audio/audio_output.dart';
import 'package:jarvis/src/cli/config_loader.dart';

Future<void> main() async {
  print('Testing acknowledgment playback...\n');

  // Load config
  final config = await ConfigLoader.fromYamlFile('config.yaml');
  print('acknowledgmentDir from config: ${config.acknowledgmentDir}');

  if (config.acknowledgmentDir == null) {
    print('ERROR: acknowledgmentDir is null!');
    exit(1);
  }

  // Check if directory exists
  final dir = Directory(config.acknowledgmentDir!);
  print('Directory exists: ${await dir.exists()}');
  print('Absolute path: ${dir.absolute.path}');

  // List files
  if (await dir.exists()) {
    print('\nFiles in directory:');
    await for (final entity in dir.list()) {
      print('  ${entity.path}');
    }
  }

  // Initialize audio output
  print('\nInitializing audio output...');
  final audioOutput = AudioOutput();
  await audioOutput.initialize();

  // Initialize acknowledgment player
  print('Initializing acknowledgment player...');
  final player = AcknowledgmentPlayer(
    audioDirectory: config.acknowledgmentDir!,
    audioOutput: audioOutput,
  );
  await player.initialize();

  print('Loaded ${player.count} acknowledgments');
  print('Has acknowledgments: ${player.hasAcknowledgments}');

  if (player.hasAcknowledgments) {
    print('\nPlaying random acknowledgment...');
    await player.playRandom();
    print('Done!');
  } else {
    print('ERROR: No acknowledgments loaded!');
  }

  await player.dispose();
  await audioOutput.dispose();
}
