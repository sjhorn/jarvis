import 'dart:async';
import 'dart:io';

import 'package:jarvis/src/cli/config_loader.dart';
import 'package:jarvis/src/logging.dart';
import 'package:jarvis/src/voice_assistant.dart';
import 'package:logging/logging.dart';

/// Default JARVIS system prompt.
const defaultSystemPrompt = '''
You are JARVIS, an advanced AI assistant inspired by the AI from Iron Man.
You are helpful, witty, and occasionally sarcastic but always respectful.
Keep your responses concise and conversational since they will be spoken aloud.
''';

/// Prints usage information.
void printUsage() {
  print('''
JARVIS Voice Assistant

Usage: dart run bin/jarvis.dart [options]

Options:
  -c, --config <path>   Path to YAML configuration file
  -v, --verbose         Enable verbose logging (INFO level)
  -d, --debug           Enable debug logging (FINE level, includes timing)
  --trace               Enable trace logging (FINEST level, very verbose)
  -q, --quiet           Suppress all logging output
  -h, --help            Show this help message

Environment Variables (alternative to config file):
  WHISPER_MODEL_PATH      Path to Whisper model file
  WHISPER_EXECUTABLE      Path to whisper-cli executable
  LLAMA_MODEL_REPO        Hugging Face model repo (e.g., ggml-org/gemma-3-1b-it-GGUF)
  LLAMA_EXECUTABLE        Path to llama-cli executable
  WAKEWORD_ENCODER_PATH   Path to wake word encoder ONNX model
  WAKEWORD_DECODER_PATH   Path to wake word decoder ONNX model
  WAKEWORD_JOINER_PATH    Path to wake word joiner ONNX model
  WAKEWORD_TOKENS_PATH    Path to wake word tokens file
  WAKEWORD_KEYWORDS_FILE  Path to wake word keywords file
  TTS_MODEL_PATH          Path to TTS model ONNX file
  TTS_TOKENS_PATH         Path to TTS tokens file
  TTS_DATA_DIR            Path to espeak-ng-data directory
  SHERPA_LIB_PATH         Path to sherpa-onnx native library
  SYSTEM_PROMPT           (Optional) Custom system prompt
  SILENCE_THRESHOLD       (Optional) Silence detection threshold (default: 0.01)
  SILENCE_DURATION_MS     (Optional) Silence duration in ms (default: 800)
  MAX_HISTORY_LENGTH      (Optional) Max conversation history (default: 10)

Example:
  # Using config file
  dart run bin/jarvis.dart --config config.yaml

  # Using environment variables
  export WHISPER_MODEL_PATH=/path/to/whisper.bin
  export LLAMA_MODEL_REPO=ggml-org/gemma-3-1b-it-GGUF
  # ... set other variables ...
  dart run bin/jarvis.dart
''');
}

Future<void> main(List<String> arguments) async {
  // Parse command line arguments
  String? configPath;
  var logLevel = Level.WARNING; // Default: only warnings and errors

  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '-h' || arg == '--help') {
      printUsage();
      exit(0);
    } else if (arg == '-c' || arg == '--config') {
      if (i + 1 >= arguments.length) {
        stderr.writeln('Error: --config requires a path argument');
        exit(1);
      }
      configPath = arguments[i + 1];
      i++;
    } else if (arg == '-v' || arg == '--verbose') {
      logLevel = Level.INFO;
    } else if (arg == '-d' || arg == '--debug') {
      logLevel = Level.FINE;
    } else if (arg == '--trace') {
      logLevel = Level.FINEST;
    } else if (arg == '-q' || arg == '--quiet') {
      logLevel = Level.OFF;
    }
  }

  // Initialize logging
  LogConfig.initialize(level: logLevel);

  // Load configuration
  AppConfig config;
  try {
    if (configPath != null) {
      print('Loading configuration from: $configPath');
      config = await ConfigLoader.fromYamlFile(configPath);
    } else {
      print('Loading configuration from environment variables...');
      config = ConfigLoader.fromEnvironment();
    }
  } on ConfigException catch (e) {
    stderr.writeln('Configuration error: ${e.message}');
    stderr.writeln('');
    stderr.writeln('Run with --help for usage information.');
    exit(1);
  }

  // Apply default system prompt if not set
  final assistantConfig = VoiceAssistantConfig(
    whisperModelPath: config.whisperModelPath,
    whisperExecutablePath: config.whisperExecutablePath,
    llamaModelRepo: config.llamaModelRepo,
    llamaExecutablePath: config.llamaExecutablePath,
    wakeWordEncoderPath: config.wakeWordEncoderPath,
    wakeWordDecoderPath: config.wakeWordDecoderPath,
    wakeWordJoinerPath: config.wakeWordJoinerPath,
    wakeWordTokensPath: config.wakeWordTokensPath,
    wakeWordKeywordsFile: config.wakeWordKeywordsFile,
    ttsModelPath: config.ttsModelPath,
    ttsTokensPath: config.ttsTokensPath,
    ttsDataDir: config.ttsDataDir,
    sherpaLibPath: config.sherpaLibPath,
    systemPrompt: config.systemPrompt ?? defaultSystemPrompt,
    silenceThreshold: config.silenceThreshold,
    silenceDuration: config.silenceDuration,
    maxHistoryLength: config.maxHistoryLength,
  );

  // Create voice assistant
  final assistant = VoiceAssistant(config: assistantConfig);

  // Set up graceful shutdown
  var shutdownRequested = false;
  final shutdownCompleter = Completer<void>();

  Future<void> shutdown() async {
    if (shutdownRequested) return;
    shutdownRequested = true;

    print('');
    print('Shutting down JARVIS...');

    try {
      await assistant.stop();
      await assistant.dispose();
      print('Goodbye!');
    } catch (e) {
      stderr.writeln('Error during shutdown: $e');
    }

    shutdownCompleter.complete();
  }

  // Handle SIGINT (Ctrl+C) and SIGTERM
  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  // Subscribe to state changes
  assistant.stateStream.listen((state) {
    switch (state) {
      case AssistantState.idle:
        print('[State] Idle');
      case AssistantState.listeningForWakeWord:
        print('[State] Listening for wake word...');
      case AssistantState.listening:
        print('[State] Listening to you...');
      case AssistantState.processing:
        print('[State] Processing...');
      case AssistantState.speaking:
        print('[State] Speaking...');
      case AssistantState.error:
        print('[State] Error occurred, recovering...');
    }
  });

  // Subscribe to transcriptions
  assistant.transcriptionStream.listen((transcription) {
    print('[You] $transcription');
  });

  // Subscribe to responses
  assistant.responseStream.listen((response) {
    print('[JARVIS] $response');
  });

  // Initialize and start
  try {
    print('');
    print('='.padRight(50, '='));
    print('  JARVIS Voice Assistant');
    print('='.padRight(50, '='));
    print('');
    print('Initializing...');

    await assistant.initialize();
    print('Initialization complete.');
    print('');
    print('Say the wake word to start a conversation.');
    print('Press Ctrl+C to exit.');
    print('');

    await assistant.start();

    // Wait for shutdown signal
    await shutdownCompleter.future;
  } on VoiceAssistantException catch (e) {
    stderr.writeln('');
    stderr.writeln('Failed to start JARVIS: ${e.message}');
    if (e.cause != null) {
      stderr.writeln('Cause: ${e.cause}');
    }
    stderr.writeln('');
    stderr.writeln('Please check your configuration and try again.');
    await assistant.dispose();
    exit(1);
  } catch (e, stackTrace) {
    stderr.writeln('');
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(stackTrace);
    await assistant.dispose();
    exit(1);
  }
}
