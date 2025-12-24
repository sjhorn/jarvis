import 'package:jarvis/src/context/conversation_context.dart';
import 'package:jarvis/src/llm/llama_process.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationContext', () {
    group('initialization', () {
      test('should create instance with default parameters', () {
        final context = ConversationContext();

        expect(context, isNotNull);
        expect(context.maxHistoryLength, equals(10));
        expect(context.systemPrompt, isNull);
      });

      test('should create instance with custom system prompt', () {
        final context = ConversationContext(
          systemPrompt: 'You are JARVIS, a helpful AI assistant.',
        );

        expect(
          context.systemPrompt,
          equals('You are JARVIS, a helpful AI assistant.'),
        );
      });

      test('should create instance with custom max history length', () {
        final context = ConversationContext(maxHistoryLength: 5);

        expect(context.maxHistoryLength, equals(5));
      });
    });

    group('addUserMessage', () {
      test('should add user message to history', () {
        final context = ConversationContext();

        context.addUserMessage('Hello, JARVIS');

        final history = context.getHistory();
        expect(history.length, equals(1));
        expect(history.first.role, equals('user'));
        expect(history.first.content, equals('Hello, JARVIS'));
      });

      test('should add multiple user messages', () {
        final context = ConversationContext();

        context.addUserMessage('First message');
        context.addUserMessage('Second message');

        final history = context.getHistory();
        expect(history.length, equals(2));
        expect(history[0].content, equals('First message'));
        expect(history[1].content, equals('Second message'));
      });
    });

    group('addAssistantMessage', () {
      test('should add assistant message to history', () {
        final context = ConversationContext();

        context.addAssistantMessage('Hello, how can I help you?');

        final history = context.getHistory();
        expect(history.length, equals(1));
        expect(history.first.role, equals('assistant'));
        expect(history.first.content, equals('Hello, how can I help you?'));
      });
    });

    group('message ordering', () {
      test('should maintain message order', () {
        final context = ConversationContext();

        context.addUserMessage('Hello');
        context.addAssistantMessage('Hi there!');
        context.addUserMessage('How are you?');
        context.addAssistantMessage('I am doing well.');

        final history = context.getHistory();
        expect(history.length, equals(4));
        expect(history[0].role, equals('user'));
        expect(history[0].content, equals('Hello'));
        expect(history[1].role, equals('assistant'));
        expect(history[1].content, equals('Hi there!'));
        expect(history[2].role, equals('user'));
        expect(history[2].content, equals('How are you?'));
        expect(history[3].role, equals('assistant'));
        expect(history[3].content, equals('I am doing well.'));
      });
    });

    group('max history length', () {
      test('should respect max history length with FIFO', () {
        final context = ConversationContext(maxHistoryLength: 3);

        context.addUserMessage('Message 1');
        context.addAssistantMessage('Response 1');
        context.addUserMessage('Message 2');
        context.addAssistantMessage(
          'Response 2',
        ); // This should push out Message 1

        final history = context.getHistory();
        expect(history.length, equals(3));
        // First message should be dropped
        expect(history[0].content, equals('Response 1'));
        expect(history[1].content, equals('Message 2'));
        expect(history[2].content, equals('Response 2'));
      });

      test('should allow unlimited history when maxHistoryLength is 0', () {
        final context = ConversationContext(maxHistoryLength: 0);

        for (var i = 0; i < 20; i++) {
          context.addUserMessage('Message $i');
        }

        expect(context.getHistory().length, equals(20));
      });
    });

    group('clear', () {
      test('should clear all messages from history', () {
        final context = ConversationContext();

        context.addUserMessage('Hello');
        context.addAssistantMessage('Hi');
        context.clear();

        expect(context.getHistory(), isEmpty);
      });

      test('should preserve system prompt when clearing', () {
        final context = ConversationContext(systemPrompt: 'You are JARVIS.');

        context.addUserMessage('Hello');
        context.clear();

        expect(context.getHistory(), isEmpty);
        expect(context.systemPrompt, equals('You are JARVIS.'));
      });
    });

    group('setSystemPrompt', () {
      test('should set system prompt', () {
        final context = ConversationContext();

        context.setSystemPrompt('You are a helpful assistant.');

        expect(context.systemPrompt, equals('You are a helpful assistant.'));
      });

      test('should update existing system prompt', () {
        final context = ConversationContext(systemPrompt: 'Original prompt');

        context.setSystemPrompt('Updated prompt');

        expect(context.systemPrompt, equals('Updated prompt'));
      });

      test('should allow clearing system prompt with null', () {
        final context = ConversationContext(systemPrompt: 'Some prompt');

        context.setSystemPrompt(null);

        expect(context.systemPrompt, isNull);
      });
    });

    group('getHistory', () {
      test('should return empty list when no messages', () {
        final context = ConversationContext();

        expect(context.getHistory(), isEmpty);
      });

      test('should return copy of history (not modifiable)', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');

        final history = context.getHistory();
        // Modifying the returned list should not affect internal state
        expect(() => history.add(ChatMessage.user('Test')), throwsA(anything));
      });
    });

    group('formatForLlama', () {
      test('should format empty conversation', () {
        final context = ConversationContext();

        final formatted = context.formatForLlama();

        expect(formatted, isEmpty);
      });

      test('should format single user message', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');

        final formatted = context.formatForLlama();

        expect(formatted, contains('User:'));
        expect(formatted, contains('Hello'));
      });

      test('should format conversation with user and assistant messages', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');
        context.addAssistantMessage('Hi there!');

        final formatted = context.formatForLlama();

        expect(formatted, contains('User:'));
        expect(formatted, contains('Hello'));
        expect(formatted, contains('Assistant:'));
        expect(formatted, contains('Hi there!'));
      });

      test('should include system prompt in format', () {
        final context = ConversationContext(
          systemPrompt: 'You are JARVIS, a helpful AI assistant.',
        );
        context.addUserMessage('Hello');

        final formatted = context.formatForLlama();

        expect(formatted, contains('System:'));
        expect(formatted, contains('You are JARVIS'));
      });

      test('should format messages in correct order', () {
        final context = ConversationContext(systemPrompt: 'Be helpful.');
        context.addUserMessage('First');
        context.addAssistantMessage('Second');
        context.addUserMessage('Third');

        final formatted = context.formatForLlama();

        // System prompt should come first
        final systemIndex = formatted.indexOf('System:');
        final firstUserIndex = formatted.indexOf('First');
        final assistantIndex = formatted.indexOf('Second');
        final secondUserIndex = formatted.indexOf('Third');

        expect(systemIndex, lessThan(firstUserIndex));
        expect(firstUserIndex, lessThan(assistantIndex));
        expect(assistantIndex, lessThan(secondUserIndex));
      });
    });

    group('getChatMessages', () {
      test('should return ChatMessage list for LlamaProcess', () {
        final context = ConversationContext(systemPrompt: 'You are JARVIS.');
        context.addUserMessage('Hello');
        context.addAssistantMessage('Hi!');

        final messages = context.getChatMessages();

        expect(messages.length, equals(3)); // system + user + assistant
        expect(messages[0].role, equals('system'));
        expect(messages[0].content, equals('You are JARVIS.'));
        expect(messages[1].role, equals('user'));
        expect(messages[1].content, equals('Hello'));
        expect(messages[2].role, equals('assistant'));
        expect(messages[2].content, equals('Hi!'));
      });

      test('should return messages without system prompt if not set', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');

        final messages = context.getChatMessages();

        expect(messages.length, equals(1));
        expect(messages[0].role, equals('user'));
      });
    });

    group('isEmpty', () {
      test('should return true for empty context', () {
        final context = ConversationContext();

        expect(context.isEmpty, isTrue);
      });

      test('should return false when messages exist', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');

        expect(context.isEmpty, isFalse);
      });

      test('should return true after clear', () {
        final context = ConversationContext();
        context.addUserMessage('Hello');
        context.clear();

        expect(context.isEmpty, isTrue);
      });
    });

    group('messageCount', () {
      test('should return 0 for empty context', () {
        final context = ConversationContext();

        expect(context.messageCount, equals(0));
      });

      test('should return correct count', () {
        final context = ConversationContext();
        context.addUserMessage('One');
        context.addAssistantMessage('Two');
        context.addUserMessage('Three');

        expect(context.messageCount, equals(3));
      });
    });

    group('lastMessage', () {
      test('should return null for empty context', () {
        final context = ConversationContext();

        expect(context.lastMessage, isNull);
      });

      test('should return last message', () {
        final context = ConversationContext();
        context.addUserMessage('First');
        context.addAssistantMessage('Last');

        expect(context.lastMessage?.content, equals('Last'));
        expect(context.lastMessage?.role, equals('assistant'));
      });
    });
  });
}
