/// Processes text from LLM for speech synthesis.
///
/// Handles:
/// - Removing markdown formatting
/// - Removing symbols that don't speak well
/// - Splitting text into sentences
class TextProcessor {
  /// Patterns for markdown that should keep the text content.
  static final _keepTextPatterns = [
    RegExp(r'\*\*\*(.+?)\*\*\*'), // Bold+italic
    RegExp(r'\*\*(.+?)\*\*'), // Bold
    RegExp(r'(?<!\*)\*([^\*]+)\*(?!\*)'), // Italic (not part of bold)
    RegExp(r'__(.+?)__'), // Bold
    RegExp(r'(?<!_)_([^_]+)_(?!_)'), // Italic (not part of bold)
    RegExp(r'~~(.+?)~~'), // Strikethrough
    RegExp(r'`([^`]+)`'), // Inline code
    RegExp(r'\[([^\]]+)\]\([^)]+\)'), // Links
  ];

  /// Symbols that should be removed or replaced.
  static final _symbolReplacements = {
    // Remove these completely
    '*': '',
    '#': '',
    '`': '',
    '~': '',
    '|': '',
    '>': '',
    '<': '',
    '{': '',
    '}': '',
    '[': '',
    ']': '',
    '\\': '',
    // Replace with spoken equivalents
    '&': ' and ',
    '%': ' percent ',
    '+': ' plus ',
    '=': ' equals ',
    '@': ' at ',
    '/': ' slash ',
    '...': ', ',
    '..': ', ',
  };

  /// Cleans text by removing markdown and problematic symbols.
  String clean(String text) {
    var result = text;

    // Remove code blocks FIRST (before inline code pattern matches them)
    result = result.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // Remove image markdown BEFORE symbol replacement removes !
    result = result.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), '');

    // Apply replacements that keep text content (using capture group 1)
    for (final pattern in _keepTextPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (match) => match.group(1) ?? '',
      );
    }

    // Remove headers markers but keep text
    result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // Remove list markers but keep text
    result = result.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Remove block quotes
    result = result.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');

    // Remove horizontal rules
    result = result.replaceAll(RegExp(r'^-{3,}$', multiLine: true), '');

    // Remove table formatting
    result = result.replaceAll(RegExp(r'\|'), ' ');

    // Remove URLs BEFORE symbol replacements (so / doesn't become " slash ")
    result = result.replaceAll(
      RegExp(r'https?://[^\s]+'),
      '',
    );

    // Apply symbol replacements
    _symbolReplacements.forEach((symbol, replacement) {
      result = result.replaceAll(symbol, replacement);
    });

    // Normalize whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // Remove leading/trailing whitespace from each line
    result = result
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ');

    return result.trim();
  }

  /// Splits text into sentences.
  ///
  /// Handles:
  /// - Period, question mark, exclamation mark endings
  /// - Abbreviations (Mr., Dr., etc.)
  /// - Numbers with decimals
  List<String> splitSentences(String text) {
    if (text.isEmpty) return [];

    // Common abbreviations that shouldn't end sentences
    const abbreviations = [
      'Mr',
      'Mrs',
      'Ms',
      'Dr',
      'Prof',
      'Sr',
      'Jr',
      'vs',
      'etc',
      'e.g',
      'i.e',
      'St',
      'Ave',
      'Blvd',
      'Inc',
      'Ltd',
      'Corp',
    ];

    final sentences = <String>[];
    final buffer = StringBuffer();
    final chars = text.split('');

    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];
      buffer.write(char);

      // Check for sentence-ending punctuation
      if (char == '.' || char == '?' || char == '!') {
        // Look ahead for space or end of text
        final isEndOfText = i == chars.length - 1;
        final hasSpaceAfter =
            i < chars.length - 1 && (chars[i + 1] == ' ' || chars[i + 1] == '\n');

        if (isEndOfText || hasSpaceAfter) {
          // Check if it's an abbreviation
          final currentText = buffer.toString().trim();
          final lastWord = currentText.split(' ').last.replaceAll('.', '');

          final isAbbreviation = abbreviations.any(
            (abbr) => lastWord.toLowerCase() == abbr.toLowerCase(),
          );

          // Check if it's a decimal number (e.g., "3.14")
          final isDecimal = char == '.' &&
              i > 0 &&
              i < chars.length - 1 &&
              RegExp(r'\d').hasMatch(chars[i - 1]) &&
              RegExp(r'\d').hasMatch(chars[i + 1]);

          if (!isAbbreviation && !isDecimal) {
            final sentence = buffer.toString().trim();
            if (sentence.isNotEmpty) {
              sentences.add(sentence);
            }
            buffer.clear();
          }
        }
      }
    }

    // Add remaining text as final sentence
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      sentences.add(remaining);
    }

    return sentences;
  }

  /// Cleans text and splits into sentences.
  List<String> process(String text) {
    final cleaned = clean(text);
    return splitSentences(cleaned);
  }

  /// Returns true if the text ends with a question mark.
  bool endsWithQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.endsWith('?');
  }

  /// Extracts the last sentence if it is a question, otherwise returns null.
  String? extractLastQuestion(List<String> sentences) {
    if (sentences.isEmpty) return null;
    final last = sentences.last.trim();
    return last.endsWith('?') ? last : null;
  }
}
