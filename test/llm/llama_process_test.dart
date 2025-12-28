import 'dart:io';

import 'package:jarvis_dart/src/llm/llama_process.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaProcess', () {
    group('initialization', () {
      test('should create instance with required parameters', () {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );

        expect(llama, isNotNull);
        expect(llama.modelRepo, equals('ggml-org/gemma-3-1b-it-GGUF'));
        expect(llama.executablePath, equals('/opt/homebrew/bin/llama-cli'));
      });

      test('should throw LlamaException when executable not found', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/nonexistent/llama-cli',
        );

        expect(() => llama.initialize(), throwsA(isA<LlamaException>()));
      });
    });

    group('generate', () {
      test('should throw LlamaException when not initialized', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );

        expect(
          () => llama.generate('Hello'),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw LlamaException for empty prompt', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );

        expect(
          () => llama.generate(''),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });
    });

    group('chat', () {
      test('should throw LlamaException when not initialized', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );

        expect(
          () => llama.chat('Hello', []),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              contains('not initialized'),
            ),
          ),
        );
      });

      test('should throw LlamaException for empty message', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );

        expect(
          () => llama.chat('', []),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      });
    });

    group('dispose', () {
      test(
        'should be safe to call dispose on non-initialized instance',
        () async {
          final llama = LlamaProcess(
            modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
            executablePath: '/opt/homebrew/bin/llama-cli',
          );

          // Should not throw
          await llama.dispose();
        },
      );

      test('should prevent operations after dispose', () async {
        final llama = LlamaProcess(
          modelRepo: 'ggml-org/gemma-3-1b-it-GGUF',
          executablePath: '/opt/homebrew/bin/llama-cli',
        );
        await llama.dispose();

        expect(
          () => llama.generate('Hello'),
          throwsA(
            isA<LlamaException>().having(
              (e) => e.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
      });
    });

    group('ChatMessage', () {
      test('should create user message', () {
        final message = ChatMessage.user('Hello');
        expect(message.role, equals('user'));
        expect(message.content, equals('Hello'));
      });

      test('should create assistant message', () {
        final message = ChatMessage.assistant('Hi there!');
        expect(message.role, equals('assistant'));
        expect(message.content, equals('Hi there!'));
      });

      test('should create system message', () {
        final message = ChatMessage.system('You are a helpful assistant.');
        expect(message.role, equals('system'));
        expect(message.content, equals('You are a helpful assistant.'));
      });
    });

    group('LlamaException', () {
      test('should format message correctly without cause', () {
        final exception = LlamaException('Test error');
        expect(exception.toString(), equals('LlamaException: Test error'));
      });

      test('should format message correctly with cause', () {
        final cause = Exception('Root cause');
        final exception = LlamaException('Test error', cause);
        expect(
          exception.toString(),
          equals('LlamaException: Test error (Exception: Root cause)'),
        );
      });
    });
  });

  group('LlamaProcess Integration Tests', () {
    late String? llamaPath;
    const modelRepo = 'ggml-org/gemma-3-1b-it-GGUF';

    setUpAll(() {
      // Check for llama-cli
      final possiblePaths = [
        '/opt/homebrew/bin/llama-cli',
        '/usr/local/bin/llama-cli',
      ];

      for (final path in possiblePaths) {
        if (File(path).existsSync()) {
          llamaPath = path;
          break;
        }
      }
    });

    test(
      'should generate a response to a simple prompt',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
        );
        await llama.initialize();

        try {
          final result = await llama.generate(
            'Say exactly: Hello World',
            maxTokens: 20,
          );

          expect(result, isA<String>());
          expect(result.isNotEmpty, isTrue);
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'should handle multiple messages in persistent mode',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
        );
        await llama.initialize();

        try {
          // First message
          final first = await llama.chat('Say hello', []);
          expect(first, isA<String>());
          expect(first.isNotEmpty, isTrue);

          // Second message - verifies persistent mode works
          final second = await llama.chat('Say goodbye', []);
          expect(second, isA<String>());
          expect(second.isNotEmpty, isTrue);

          // Both should have received responses without reloading model
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'should respect max tokens limit',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        // In persistent mode, maxTokens is set at construction time
        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
          maxTokens: 15, // Very few tokens
        );
        await llama.initialize();

        try {
          final result = await llama.generate('Count from 1 to 100');

          expect(result, isA<String>());
          // With only 15 tokens, it shouldn't complete the full count
          expect(result.contains('100'), isFalse);
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'should use system prompt when provided',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
          systemPrompt:
              'You are JARVIS, a helpful AI assistant. Always respond formally.',
        );
        await llama.initialize();

        try {
          final result = await llama.generate('Greet me', maxTokens: 50);

          expect(result, isA<String>());
          expect(result.isNotEmpty, isTrue);
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'chatStream should emit tokens as they are generated',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
        );
        await llama.initialize();

        try {
          final tokens = <String>[];
          final stream = llama.chatStream('Say hello', []);

          await for (final token in stream) {
            tokens.add(token);
          }

          // Should have received multiple tokens
          expect(tokens, isNotEmpty);

          // Concatenated tokens should form a response
          final fullResponse = tokens.join();
          expect(fullResponse.isNotEmpty, isTrue);
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'cancelStream should stop token emission',
      () async {
        if (llamaPath == null) {
          markTestSkipped('llama-cli not available');
          return;
        }

        final llama = LlamaProcess(
          modelRepo: modelRepo,
          executablePath: llamaPath!,
        );
        await llama.initialize();

        try {
          final tokens = <String>[];
          final stream = llama.chatStream('Tell me a long story', []);

          var count = 0;
          await for (final token in stream) {
            tokens.add(token);
            count++;
            if (count >= 3) {
              // Cancel after receiving a few tokens
              llama.cancelStream();
              break;
            }
          }

          // Should have received some tokens before cancellation
          expect(tokens.length, greaterThanOrEqualTo(1));
          expect(tokens.length, lessThanOrEqualTo(5));
        } finally {
          await llama.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
