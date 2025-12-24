import 'dart:async';

import 'package:jarvis/src/voice_assistant.dart';
import 'package:test/test.dart';

void main() {
  group('VoiceAssistantConfig', () {
    test('should create config with all required paths', () {
      final config = VoiceAssistantConfig(
        whisperModelPath: '/path/to/whisper.bin',
        whisperExecutablePath: '/path/to/whisper-cli',
        llamaModelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
        llamaExecutablePath: '/path/to/llama-cli',
        wakeWordEncoderPath: '/path/to/encoder.onnx',
        wakeWordDecoderPath: '/path/to/decoder.onnx',
        wakeWordJoinerPath: '/path/to/joiner.onnx',
        wakeWordTokensPath: '/path/to/tokens.txt',
        wakeWordKeywordsFile: '/path/to/keywords.txt',
        ttsModelPath: '/path/to/tts/model.onnx',
        ttsTokensPath: '/path/to/tts/tokens.txt',
        ttsDataDir: '/path/to/tts/espeak-ng-data',
        sherpaLibPath: '/path/to/sherpa/lib',
      );

      expect(config.whisperModelPath, equals('/path/to/whisper.bin'));
      expect(config.llamaModelRepo, equals('ggml-org/gemma-3-1b-it-GGUF'));
    });

    test('should have optional system prompt', () {
      final config = VoiceAssistantConfig(
        whisperModelPath: '/path/to/whisper.bin',
        whisperExecutablePath: '/path/to/whisper-cli',
        llamaModelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
        llamaExecutablePath: '/path/to/llama-cli',
        wakeWordEncoderPath: '/path/to/encoder.onnx',
        wakeWordDecoderPath: '/path/to/decoder.onnx',
        wakeWordJoinerPath: '/path/to/joiner.onnx',
        wakeWordTokensPath: '/path/to/tokens.txt',
        wakeWordKeywordsFile: '/path/to/keywords.txt',
        ttsModelPath: '/path/to/tts/model.onnx',
        ttsTokensPath: '/path/to/tts/tokens.txt',
        ttsDataDir: '/path/to/tts/espeak-ng-data',
        sherpaLibPath: '/path/to/sherpa/lib',
        systemPrompt: 'You are JARVIS.',
      );

      expect(config.systemPrompt, equals('You are JARVIS.'));
    });

    test('should have configurable silence settings', () {
      final config = VoiceAssistantConfig(
        whisperModelPath: '/path/to/whisper.bin',
        whisperExecutablePath: '/path/to/whisper-cli',
        llamaModelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
        llamaExecutablePath: '/path/to/llama-cli',
        wakeWordEncoderPath: '/path/to/encoder.onnx',
        wakeWordDecoderPath: '/path/to/decoder.onnx',
        wakeWordJoinerPath: '/path/to/joiner.onnx',
        wakeWordTokensPath: '/path/to/tokens.txt',
        wakeWordKeywordsFile: '/path/to/keywords.txt',
        ttsModelPath: '/path/to/tts/model.onnx',
        ttsTokensPath: '/path/to/tts/tokens.txt',
        ttsDataDir: '/path/to/tts/espeak-ng-data',
        sherpaLibPath: '/path/to/sherpa/lib',
        silenceThreshold: 0.02,
        silenceDuration: const Duration(milliseconds: 1000),
      );

      expect(config.silenceThreshold, equals(0.02));
      expect(
        config.silenceDuration,
        equals(const Duration(milliseconds: 1000)),
      );
    });

    test('should have default values for optional parameters', () {
      final config = VoiceAssistantConfig(
        whisperModelPath: '/path/to/whisper.bin',
        whisperExecutablePath: '/path/to/whisper-cli',
        llamaModelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
        llamaExecutablePath: '/path/to/llama-cli',
        wakeWordEncoderPath: '/path/to/encoder.onnx',
        wakeWordDecoderPath: '/path/to/decoder.onnx',
        wakeWordJoinerPath: '/path/to/joiner.onnx',
        wakeWordTokensPath: '/path/to/tokens.txt',
        wakeWordKeywordsFile: '/path/to/keywords.txt',
        ttsModelPath: '/path/to/tts/model.onnx',
        ttsTokensPath: '/path/to/tts/tokens.txt',
        ttsDataDir: '/path/to/tts/espeak-ng-data',
        sherpaLibPath: '/path/to/sherpa/lib',
      );

      expect(config.systemPrompt, isNull);
      expect(config.silenceThreshold, equals(0.01));
      expect(config.silenceDuration, equals(const Duration(milliseconds: 800)));
      expect(config.maxHistoryLength, equals(10));
    });
  });

  group('AssistantState', () {
    test('should have all expected states', () {
      expect(AssistantState.values, contains(AssistantState.idle));
      expect(
        AssistantState.values,
        contains(AssistantState.listeningForWakeWord),
      );
      expect(AssistantState.values, contains(AssistantState.listening));
      expect(AssistantState.values, contains(AssistantState.processing));
      expect(AssistantState.values, contains(AssistantState.speaking));
      expect(AssistantState.values, contains(AssistantState.error));
    });
  });

  group('VoiceAssistant', () {
    late VoiceAssistantConfig testConfig;

    setUp(() {
      testConfig = VoiceAssistantConfig(
        whisperModelPath: '/nonexistent/whisper.bin',
        whisperExecutablePath: '/nonexistent/whisper-cli',
        llamaModelRepo: 'test-model',
        llamaExecutablePath: '/nonexistent/llama-cli',
        wakeWordEncoderPath: '/nonexistent/encoder.onnx',
        wakeWordDecoderPath: '/nonexistent/decoder.onnx',
        wakeWordJoinerPath: '/nonexistent/joiner.onnx',
        wakeWordTokensPath: '/nonexistent/tokens.txt',
        wakeWordKeywordsFile: '/nonexistent/keywords.txt',
        ttsModelPath: '/nonexistent/model.onnx',
        ttsTokensPath: '/nonexistent/tokens.txt',
        ttsDataDir: '/nonexistent/espeak-ng-data',
        sherpaLibPath: '/nonexistent/lib',
      );
    });

    group('initialization', () {
      test('should create instance with config', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant, isNotNull);
        expect(assistant.config, equals(testConfig));
      });

      test('should start in idle state', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.currentState, equals(AssistantState.idle));
      });

      test('should not be running initially', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.isRunning, isFalse);
      });

      test('should not be initialized initially', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.isInitialized, isFalse);
      });
    });

    group('streams', () {
      test('should provide state stream', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.stateStream, isA<Stream<AssistantState>>());
      });

      test('should provide transcription stream', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.transcriptionStream, isA<Stream<String>>());
      });

      test('should provide response stream', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.responseStream, isA<Stream<String>>());
      });
    });

    group('start/stop without initialization', () {
      test('should throw when starting without initialization', () async {
        final assistant = VoiceAssistant(config: testConfig);

        expect(
          () => assistant.start(),
          throwsA(
            isA<VoiceAssistantException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should be safe to stop when not running', () async {
        final assistant = VoiceAssistant(config: testConfig);

        await assistant.stop();
        // Should not throw
      });
    });

    group('dispose', () {
      test('should be safe to dispose non-initialized instance', () async {
        final assistant = VoiceAssistant(config: testConfig);

        await assistant.dispose();
        // Should not throw
      });

      test('should prevent operations after dispose', () async {
        final assistant = VoiceAssistant(config: testConfig);
        await assistant.dispose();

        expect(
          () => assistant.start(),
          throwsA(
            isA<VoiceAssistantException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });

      test('should set state to idle on dispose', () async {
        final assistant = VoiceAssistant(config: testConfig);
        await assistant.dispose();

        expect(assistant.currentState, equals(AssistantState.idle));
      });
    });

    group('conversation context', () {
      test('should have conversation context', () {
        final assistant = VoiceAssistant(config: testConfig);

        expect(assistant.context, isNotNull);
      });

      test('should initialize context with system prompt from config', () {
        final configWithPrompt = VoiceAssistantConfig(
          whisperModelPath: '/path/to/whisper.bin',
          whisperExecutablePath: '/path/to/whisper-cli',
          llamaModelRepo: 'test-model',
          llamaExecutablePath: '/path/to/llama-cli',
          wakeWordEncoderPath: '/path/to/encoder.onnx',
          wakeWordDecoderPath: '/path/to/decoder.onnx',
          wakeWordJoinerPath: '/path/to/joiner.onnx',
          wakeWordTokensPath: '/path/to/tokens.txt',
          wakeWordKeywordsFile: '/path/to/keywords.txt',
          ttsModelPath: '/path/to/model.onnx',
          ttsTokensPath: '/path/to/tokens.txt',
          ttsDataDir: '/path/to/espeak-ng-data',
          sherpaLibPath: '/path/to/lib',
          systemPrompt: 'You are JARVIS.',
        );

        final assistant = VoiceAssistant(config: configWithPrompt);

        expect(assistant.context.systemPrompt, equals('You are JARVIS.'));
      });

      test('should be able to clear conversation', () {
        final assistant = VoiceAssistant(config: testConfig);
        assistant.context.addUserMessage('Test');

        assistant.clearConversation();

        expect(assistant.context.isEmpty, isTrue);
      });
    });

    group('VoiceAssistantException', () {
      test('should format message correctly without cause', () {
        final exception = VoiceAssistantException('Test error');
        expect(
          exception.toString(),
          equals('VoiceAssistantException: Test error'),
        );
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = VoiceAssistantException('Test error', cause);
        expect(
          exception.toString(),
          equals('VoiceAssistantException: Test error (Exception: Root cause)'),
        );
      });
    });
  });
}
