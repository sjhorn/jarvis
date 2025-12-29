/// Example usage of the jarvis_dart voice assistant library.
///
/// This example shows how to load configuration for the JARVIS voice assistant.
/// Before running, ensure you have:
/// - whisper.cpp installed (for speech-to-text)
/// - llama.cpp installed (for LLM responses)
/// - sox installed (for audio recording/playback)
/// - Run `jarvis setup` to download required models
library;

import 'dart:io';

import 'package:jarvis_dart/jarvis_dart.dart';

void main() async {
  print('JARVIS Voice Assistant Example');
  print('==============================');
  print('');
  print('This example demonstrates the JARVIS voice assistant library.');
  print('');
  print('To run the full assistant:');
  print('  1. Install dependencies: whisper.cpp, llama.cpp, sox');
  print('  2. Run: dart pub global activate jarvis_dart');
  print('  3. Run: jarvis setup');
  print('  4. Run: jarvis');
  print('');

  // Example: Load config from YAML file
  print('Loading configuration...');

  try {
    // Try to load from default config path
    final configPath = '${Platform.environment['HOME']}/.jarvis/config.yaml';
    if (await File(configPath).exists()) {
      final config = await ConfigLoader.fromYamlFile(configPath);
      print('Loaded config from: $configPath');
      print('  Whisper model: ${config.whisperModelPath}');
      print('  LLM model: ${config.llamaModelRepo}');
      print('  TTS model: ${config.ttsModelPath}');
    } else {
      print('No config found at $configPath');
      print('Run "jarvis setup" to create one.');
    }
  } catch (e) {
    print('Error loading config: $e');
  }

  print('');
  print('For full usage, see: https://pub.dev/packages/jarvis_dart');
}
