/// Example usage of the jarvis_dart voice assistant library.
///
/// This example shows how to configure and start the JARVIS voice assistant.
/// Before running, ensure you have:
/// - whisper.cpp installed (for speech-to-text)
/// - llama.cpp installed (for LLM responses)
/// - sox installed (for audio recording/playback)
/// - Run `jarvis setup` to download required models
library;

import 'dart:io';

import 'package:jarvis_dart/jarvis_dart.dart';

/// Example configuration for JARVIS.
///
/// In production, load this from a config.yaml file using [ConfigLoader].
final exampleConfig = AppConfig(
  // Paths to required executables
  whisperCliPath: '/opt/homebrew/bin/whisper-cli',
  llamaCliPath: '/opt/homebrew/bin/llama-cli',

  // Model configurations
  whisperModelPath: '~/.jarvis/models/whisper/ggml-base.en.bin',
  llamaModelRepo: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
  ttsModelPath: '~/.jarvis/models/tts/en_US-amy-medium.onnx',
  ttsTokensPath: '~/.jarvis/models/tts/tokens.txt',
  ttsDataDir: '~/.jarvis/models/tts/espeak-ng-data',
  wakeWordModelPath: '~/.jarvis/models/kws',
  wakeWordKeywordsPath: '~/.jarvis/models/kws/keywords.txt',

  // Audio settings
  audioPlayer: AudioPlayer.afplay, // macOS default
  acknowledgmentDir: '~/.jarvis/assets/acknowledgments',
  bargeInDir: '~/.jarvis/assets/bargein',

  // Behavior settings
  enableFollowUp: true,
  enableRecording: false,
);

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

  // Example: Load config from file
  print('Loading configuration...');
  final configLoader = ConfigLoader();

  try {
    // Try to load from default config path
    final configPath = '${Platform.environment['HOME']}/.jarvis/config.yaml';
    if (await File(configPath).exists()) {
      final config = await configLoader.load(configPath);
      print('Loaded config from: $configPath');
      print('  Wake word model: ${config.wakeWordModelPath}');
      print('  Whisper model: ${config.whisperModelPath}');
      print('  LLM model: ${config.llamaModelRepo}');
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
