import 'dart:io';

import 'package:jarvis/src/cli/config_loader.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigLoader', () {
    group('fromEnvironment', () {
      test('should load config from environment variables', () {
        final env = {
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          'WHISPER_EXECUTABLE': '/path/to/whisper-cli',
          'LLAMA_MODEL_REPO': 'ggml-org/gemma-3-1b-it-GGUF',
          'LLAMA_EXECUTABLE': '/path/to/llama-cli',
          'WAKEWORD_ENCODER_PATH': '/path/to/encoder.onnx',
          'WAKEWORD_DECODER_PATH': '/path/to/decoder.onnx',
          'WAKEWORD_JOINER_PATH': '/path/to/joiner.onnx',
          'WAKEWORD_TOKENS_PATH': '/path/to/tokens.txt',
          'WAKEWORD_KEYWORDS_FILE': '/path/to/keywords.txt',
          'TTS_MODEL_PATH': '/path/to/tts/model.onnx',
          'TTS_TOKENS_PATH': '/path/to/tts/tokens.txt',
          'TTS_DATA_DIR': '/path/to/tts/espeak-ng-data',
          'SHERPA_LIB_PATH': '/path/to/sherpa/lib',
        };

        final config = ConfigLoader.fromEnvironment(env);

        expect(config.whisperModelPath, equals('/path/to/whisper.bin'));
        expect(config.whisperExecutablePath, equals('/path/to/whisper-cli'));
        expect(config.llamaModelRepo, equals('ggml-org/gemma-3-1b-it-GGUF'));
        expect(config.llamaExecutablePath, equals('/path/to/llama-cli'));
        expect(config.sherpaLibPath, equals('/path/to/sherpa/lib'));
      });

      test('should load optional system prompt from environment', () {
        final env = {
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          'WHISPER_EXECUTABLE': '/path/to/whisper-cli',
          'LLAMA_MODEL_REPO': 'ggml-org/gemma-3-1b-it-GGUF',
          'LLAMA_EXECUTABLE': '/path/to/llama-cli',
          'WAKEWORD_ENCODER_PATH': '/path/to/encoder.onnx',
          'WAKEWORD_DECODER_PATH': '/path/to/decoder.onnx',
          'WAKEWORD_JOINER_PATH': '/path/to/joiner.onnx',
          'WAKEWORD_TOKENS_PATH': '/path/to/tokens.txt',
          'WAKEWORD_KEYWORDS_FILE': '/path/to/keywords.txt',
          'TTS_MODEL_PATH': '/path/to/tts/model.onnx',
          'TTS_TOKENS_PATH': '/path/to/tts/tokens.txt',
          'TTS_DATA_DIR': '/path/to/tts/espeak-ng-data',
          'SHERPA_LIB_PATH': '/path/to/sherpa/lib',
          'SYSTEM_PROMPT': 'You are JARVIS, a helpful AI assistant.',
        };

        final config = ConfigLoader.fromEnvironment(env);

        expect(
          config.systemPrompt,
          equals('You are JARVIS, a helpful AI assistant.'),
        );
      });

      test('should throw when required environment variable is missing', () {
        final env = <String, String>{
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          // Missing other required variables
        };

        expect(
          () => ConfigLoader.fromEnvironment(env),
          throwsA(isA<ConfigException>()),
        );
      });

      test('should load optional settings with defaults', () {
        final env = {
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          'WHISPER_EXECUTABLE': '/path/to/whisper-cli',
          'LLAMA_MODEL_REPO': 'ggml-org/gemma-3-1b-it-GGUF',
          'LLAMA_EXECUTABLE': '/path/to/llama-cli',
          'WAKEWORD_ENCODER_PATH': '/path/to/encoder.onnx',
          'WAKEWORD_DECODER_PATH': '/path/to/decoder.onnx',
          'WAKEWORD_JOINER_PATH': '/path/to/joiner.onnx',
          'WAKEWORD_TOKENS_PATH': '/path/to/tokens.txt',
          'WAKEWORD_KEYWORDS_FILE': '/path/to/keywords.txt',
          'TTS_MODEL_PATH': '/path/to/tts/model.onnx',
          'TTS_TOKENS_PATH': '/path/to/tts/tokens.txt',
          'TTS_DATA_DIR': '/path/to/tts/espeak-ng-data',
          'SHERPA_LIB_PATH': '/path/to/sherpa/lib',
        };

        final config = ConfigLoader.fromEnvironment(env);

        expect(config.silenceThreshold, equals(0.01));
        expect(
          config.silenceDuration,
          equals(const Duration(milliseconds: 800)),
        );
        expect(config.maxHistoryLength, equals(10));
      });

      test('should load custom silence settings from environment', () {
        final env = {
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          'WHISPER_EXECUTABLE': '/path/to/whisper-cli',
          'LLAMA_MODEL_REPO': 'ggml-org/gemma-3-1b-it-GGUF',
          'LLAMA_EXECUTABLE': '/path/to/llama-cli',
          'WAKEWORD_ENCODER_PATH': '/path/to/encoder.onnx',
          'WAKEWORD_DECODER_PATH': '/path/to/decoder.onnx',
          'WAKEWORD_JOINER_PATH': '/path/to/joiner.onnx',
          'WAKEWORD_TOKENS_PATH': '/path/to/tokens.txt',
          'WAKEWORD_KEYWORDS_FILE': '/path/to/keywords.txt',
          'TTS_MODEL_PATH': '/path/to/tts/model.onnx',
          'TTS_TOKENS_PATH': '/path/to/tts/tokens.txt',
          'TTS_DATA_DIR': '/path/to/tts/espeak-ng-data',
          'SHERPA_LIB_PATH': '/path/to/sherpa/lib',
          'SILENCE_THRESHOLD': '0.02',
          'SILENCE_DURATION_MS': '1000',
          'MAX_HISTORY_LENGTH': '20',
        };

        final config = ConfigLoader.fromEnvironment(env);

        expect(config.silenceThreshold, equals(0.02));
        expect(
          config.silenceDuration,
          equals(const Duration(milliseconds: 1000)),
        );
        expect(config.maxHistoryLength, equals(20));
      });
    });

    group('fromYamlFile', () {
      late Directory tempDir;
      late File configFile;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('jarvis_test_');
        configFile = File('${tempDir.path}/config.yaml');
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('should load config from YAML file', () async {
        await configFile.writeAsString('''
whisper_model_path: /path/to/whisper.bin
whisper_executable: /path/to/whisper-cli
llama_model_repo: ggml-org/gemma-3-1b-it-GGUF
llama_executable: /path/to/llama-cli
wakeword_encoder_path: /path/to/encoder.onnx
wakeword_decoder_path: /path/to/decoder.onnx
wakeword_joiner_path: /path/to/joiner.onnx
wakeword_tokens_path: /path/to/tokens.txt
wakeword_keywords_file: /path/to/keywords.txt
tts_model_path: /path/to/tts/model.onnx
tts_tokens_path: /path/to/tts/tokens.txt
tts_data_dir: /path/to/tts/espeak-ng-data
sherpa_lib_path: /path/to/sherpa/lib
''');

        final config = await ConfigLoader.fromYamlFile(configFile.path);

        expect(config.whisperModelPath, equals('/path/to/whisper.bin'));
        expect(config.llamaModelRepo, equals('ggml-org/gemma-3-1b-it-GGUF'));
      });

      test('should load optional settings from YAML', () async {
        await configFile.writeAsString('''
whisper_model_path: /path/to/whisper.bin
whisper_executable: /path/to/whisper-cli
llama_model_repo: ggml-org/gemma-3-1b-it-GGUF
llama_executable: /path/to/llama-cli
wakeword_encoder_path: /path/to/encoder.onnx
wakeword_decoder_path: /path/to/decoder.onnx
wakeword_joiner_path: /path/to/joiner.onnx
wakeword_tokens_path: /path/to/tokens.txt
wakeword_keywords_file: /path/to/keywords.txt
tts_model_path: /path/to/tts/model.onnx
tts_tokens_path: /path/to/tts/tokens.txt
tts_data_dir: /path/to/tts/espeak-ng-data
sherpa_lib_path: /path/to/sherpa/lib
system_prompt: "You are JARVIS, a witty AI assistant."
silence_threshold: 0.015
silence_duration_ms: 900
max_history_length: 15
''');

        final config = await ConfigLoader.fromYamlFile(configFile.path);

        expect(
          config.systemPrompt,
          equals('You are JARVIS, a witty AI assistant.'),
        );
        expect(config.silenceThreshold, equals(0.015));
        expect(
          config.silenceDuration,
          equals(const Duration(milliseconds: 900)),
        );
        expect(config.maxHistoryLength, equals(15));
      });

      test('should throw when YAML file not found', () async {
        expect(
          () => ConfigLoader.fromYamlFile('/nonexistent/config.yaml'),
          throwsA(isA<ConfigException>()),
        );
      });

      test('should throw when required field is missing in YAML', () async {
        await configFile.writeAsString('''
whisper_model_path: /path/to/whisper.bin
# Missing other required fields
''');

        expect(
          () => ConfigLoader.fromYamlFile(configFile.path),
          throwsA(isA<ConfigException>()),
        );
      });
    });

    group('toVoiceAssistantConfig', () {
      test('should convert to VoiceAssistantConfig', () {
        final env = {
          'WHISPER_MODEL_PATH': '/path/to/whisper.bin',
          'WHISPER_EXECUTABLE': '/path/to/whisper-cli',
          'LLAMA_MODEL_REPO': 'ggml-org/gemma-3-1b-it-GGUF',
          'LLAMA_EXECUTABLE': '/path/to/llama-cli',
          'WAKEWORD_ENCODER_PATH': '/path/to/encoder.onnx',
          'WAKEWORD_DECODER_PATH': '/path/to/decoder.onnx',
          'WAKEWORD_JOINER_PATH': '/path/to/joiner.onnx',
          'WAKEWORD_TOKENS_PATH': '/path/to/tokens.txt',
          'WAKEWORD_KEYWORDS_FILE': '/path/to/keywords.txt',
          'TTS_MODEL_PATH': '/path/to/tts/model.onnx',
          'TTS_TOKENS_PATH': '/path/to/tts/tokens.txt',
          'TTS_DATA_DIR': '/path/to/tts/espeak-ng-data',
          'SHERPA_LIB_PATH': '/path/to/sherpa/lib',
          'SYSTEM_PROMPT': 'You are JARVIS.',
        };

        final config = ConfigLoader.fromEnvironment(env);
        final assistantConfig = config.toVoiceAssistantConfig();

        expect(
          assistantConfig.whisperModelPath,
          equals('/path/to/whisper.bin'),
        );
        expect(
          assistantConfig.llamaModelRepo,
          equals('ggml-org/gemma-3-1b-it-GGUF'),
        );
        expect(assistantConfig.systemPrompt, equals('You are JARVIS.'));
      });
    });
  });

  group('ConfigException', () {
    test('should format message correctly', () {
      final exception = ConfigException('Missing required field');
      expect(
        exception.toString(),
        equals('ConfigException: Missing required field'),
      );
    });

    test('should format message with cause', () {
      final cause = FormatException('Invalid number');
      final exception = ConfigException('Failed to parse', cause);
      expect(
        exception.toString(),
        contains('ConfigException: Failed to parse'),
      );
      expect(exception.toString(), contains('Invalid number'));
    });
  });
}
