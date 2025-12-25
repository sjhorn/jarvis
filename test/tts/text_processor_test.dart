import 'package:test/test.dart';
import 'package:jarvis/src/tts/text_processor.dart';

void main() {
  late TextProcessor processor;

  setUp(() {
    processor = TextProcessor();
  });

  group('TextProcessor clean()', () {
    test('should remove bold markdown', () {
      expect(processor.clean('This is **bold** text'), equals('This is bold text'));
    });

    test('should remove italic markdown', () {
      expect(processor.clean('This is *italic* text'), equals('This is italic text'));
    });

    test('should remove code blocks', () {
      expect(
        processor.clean('Here is code:\n```dart\nprint("hello");\n```\nDone.'),
        equals('Here is code: Done.'),
      );
    });

    test('should remove inline code', () {
      expect(processor.clean('Use `print()` function'), equals('Use print() function'));
    });

    test('should remove header markers', () {
      expect(processor.clean('# Header\nContent'), equals('Header Content'));
    });

    test('should remove bullet point markers', () {
      expect(
        processor.clean('Items:\n- First\n- Second'),
        equals('Items: First Second'),
      );
    });

    test('should keep link text but remove URL', () {
      expect(
        processor.clean('Check [this link](http://example.com)'),
        equals('Check this link'),
      );
    });

    test('should remove image markdown', () {
      expect(processor.clean('Here is ![alt text](image.png)'), equals('Here is'));
    });

    test('should replace & with and', () {
      expect(processor.clean('Tom & Jerry'), equals('Tom and Jerry'));
    });

    test('should replace % with percent', () {
      expect(processor.clean('100% complete'), equals('100 percent complete'));
    });

    test('should replace @ with at', () {
      expect(processor.clean('email@test.com'), equals('email at test.com'));
    });

    test('should remove URLs', () {
      expect(
        processor.clean('Visit https://example.com for more'),
        equals('Visit for more'),
      );
    });

    test('should normalize whitespace', () {
      expect(processor.clean('Too   many    spaces'), equals('Too many spaces'));
    });

    test('should handle complex markdown', () {
      final input = '''
# Welcome

Here is **important** info:

- First *point*
- Second `code` point

Check [docs](http://docs.com) & enjoy!
''';
      final result = processor.clean(input);
      expect(result, contains('Welcome'));
      expect(result, contains('important'));
      expect(result, contains('First point'));
      expect(result, contains('and enjoy'));
      expect(result, isNot(contains('http')));
      expect(result, isNot(contains('**')));
      expect(result, isNot(contains('#')));
    });
  });

  group('TextProcessor splitSentences()', () {
    test('should split on period', () {
      expect(
        processor.splitSentences('First sentence. Second sentence.'),
        equals(['First sentence.', 'Second sentence.']),
      );
    });

    test('should split on question mark', () {
      expect(
        processor.splitSentences('How are you? I am fine.'),
        equals(['How are you?', 'I am fine.']),
      );
    });

    test('should split on exclamation mark', () {
      expect(
        processor.splitSentences('Wow! That is great.'),
        equals(['Wow!', 'That is great.']),
      );
    });

    test('should handle abbreviations correctly', () {
      expect(
        processor.splitSentences('Mr. Smith went home. He was tired.'),
        equals(['Mr. Smith went home.', 'He was tired.']),
      );
    });

    test('should handle Dr. abbreviation', () {
      expect(
        processor.splitSentences('Dr. Jones called. She left a message.'),
        equals(['Dr. Jones called.', 'She left a message.']),
      );
    });

    test('should handle decimal numbers', () {
      expect(
        processor.splitSentences('The value is 3.14. That is pi.'),
        equals(['The value is 3.14.', 'That is pi.']),
      );
    });

    test('should handle empty string', () {
      expect(processor.splitSentences(''), equals([]));
    });

    test('should handle single sentence without period', () {
      expect(
        processor.splitSentences('Hello world'),
        equals(['Hello world']),
      );
    });

    test('should handle multiple abbreviations', () {
      expect(
        processor.splitSentences('Dr. Smith and Mrs. Jones met. They talked.'),
        equals(['Dr. Smith and Mrs. Jones met.', 'They talked.']),
      );
    });

    test('should handle etc. abbreviation', () {
      expect(
        processor.splitSentences('Apples, oranges, etc. are fruits.'),
        equals(['Apples, oranges, etc. are fruits.']),
      );
    });
  });

  group('TextProcessor process()', () {
    test('should clean and split text', () {
      final input = '**Hello** world. How are you?';
      final result = processor.process(input);
      expect(result, equals(['Hello world.', 'How are you?']));
    });

    test('should handle markdown with multiple sentences', () {
      final input = '''
# Title

First *paragraph*. Second **paragraph**.

- Point one.
- Point two.
''';
      final result = processor.process(input);
      expect(result.length, greaterThan(1));
      expect(result[0], contains('Title'));
      expect(result.any((s) => s.contains('paragraph')), isTrue);
    });

    test('should handle LLM-style response', () {
      final input = '''
I'd be happy to help! Here are some suggestions:

1. **Use clear names** - This improves readability.
2. **Add comments** - They help others understand your code.

Let me know if you need more info!
''';
      final result = processor.process(input);
      expect(result.length, greaterThan(0));
      expect(result.any((s) => s.contains('happy to help')), isTrue);
      expect(result.any((s) => s.contains('Use clear names')), isTrue);
    });
  });

  group('TextProcessor endsWithQuestion()', () {
    test('should return true for text ending with question mark', () {
      expect(processor.endsWithQuestion('How are you?'), isTrue);
    });

    test('should return true for question with trailing whitespace', () {
      expect(processor.endsWithQuestion('How are you?  '), isTrue);
    });

    test('should return false for text ending with period', () {
      expect(processor.endsWithQuestion('Hello there.'), isFalse);
    });

    test('should return false for text ending with exclamation', () {
      expect(processor.endsWithQuestion('Hello there!'), isFalse);
    });

    test('should return false for empty string', () {
      expect(processor.endsWithQuestion(''), isFalse);
    });

    test('should return false for whitespace only', () {
      expect(processor.endsWithQuestion('   '), isFalse);
    });

    test('should handle question in middle but not at end', () {
      expect(processor.endsWithQuestion('How are you? I am fine.'), isFalse);
    });
  });

  group('TextProcessor extractLastQuestion()', () {
    test('should return last sentence if it is a question', () {
      final sentences = ['Hello.', 'How are you?'];
      expect(processor.extractLastQuestion(sentences), equals('How are you?'));
    });

    test('should return null if last sentence is not a question', () {
      final sentences = ['How are you?', 'I am fine.'];
      expect(processor.extractLastQuestion(sentences), isNull);
    });

    test('should return null for empty list', () {
      expect(processor.extractLastQuestion([]), isNull);
    });

    test('should handle single question sentence', () {
      final sentences = ['What is your name?'];
      expect(processor.extractLastQuestion(sentences), equals('What is your name?'));
    });

    test('should handle whitespace in last sentence', () {
      final sentences = ['Hello.', 'How are you?  '];
      expect(processor.extractLastQuestion(sentences), equals('How are you?'));
    });
  });
}
