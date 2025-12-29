/// Processes text from LLM for speech synthesis.
///
/// Handles:
/// - Removing markdown formatting
/// - Removing symbols that don't speak well
/// - Splitting text into sentences
/// - Breaking on newlines, semicolons, colons, and em-dashes
/// - Forcing breaks on long sentences (max words limit)
class TextProcessor {
  /// Maximum words before forcing a sentence break.
  /// This prevents long pauses while waiting for a natural break point.
  static const int maxWordsPerChunk = 20;

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
    result = result.replaceAll(RegExp(r'https?://[^\s]+'), '');

    // Apply symbol replacements
    _symbolReplacements.forEach((symbol, replacement) {
      result = result.replaceAll(symbol, replacement);
    });

    // Normalize whitespace within lines (preserve newlines for sentence breaking)
    result = result.replaceAll(RegExp(r'[^\S\n]+'), ' ');

    // Collapse multiple newlines into single newline
    result = result.replaceAll(RegExp(r'\n+'), '\n');

    // Remove leading/trailing whitespace from each line
    result = result
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');

    return result.trim();
  }

  /// Splits text into sentences.
  ///
  /// Handles:
  /// - Period, question mark, exclamation mark endings
  /// - Newlines as sentence breaks
  /// - Clause separators (; : —) followed by space
  /// - Word limit (max 20 words per chunk)
  /// - Abbreviations (Mr., Dr., etc.)
  /// - Numbers with decimals
  List<String> splitSentences(String text) {
    if (text.isEmpty) return [];

    final sentences = <String>[];
    var remaining = text;

    // Use extractCompleteSentence repeatedly to split
    while (remaining.isNotEmpty) {
      final (sentence, rest) = extractCompleteSentence(remaining);
      if (sentence != null) {
        sentences.add(sentence);
        remaining = rest;
      } else {
        // No more complete sentences, add remaining as final chunk
        final cleaned = clean(remaining);
        if (cleaned.isNotEmpty) {
          sentences.add(cleaned);
        }
        break;
      }
    }

    return sentences;
  }

  /// Cleans text and splits into sentences.
  List<String> process(String text) {
    final cleaned = clean(text);
    return splitSentences(cleaned);
  }

  /// Extracts the first complete sentence from a buffer.
  ///
  /// Returns a record of (completeSentence, remainingBuffer).
  /// If no complete sentence is found, returns (null, originalBuffer).
  ///
  /// Breaks on:
  /// - Sentence-ending punctuation (. ! ?) followed by whitespace or end
  /// - Newlines
  /// - Clause separators (; : —) followed by whitespace
  /// - Word limit exceeded (breaks at last space before limit)
  ///
  /// Handles abbreviations (Mr., Dr., etc.) and decimal numbers.
  (String?, String) extractCompleteSentence(String buffer) {
    if (buffer.isEmpty) return (null, buffer);

    // Clean the buffer first (removes markdown, etc.)
    final cleaned = clean(buffer);
    if (cleaned.isEmpty) return (null, buffer);

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

    final chars = cleaned.split('');
    var wordCount = 0;
    var lastSpaceIndex = -1;

    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];

      // Track word boundaries for max word limit
      if (char == ' ') {
        lastSpaceIndex = i;
        wordCount++;

        // Check if we've exceeded max words
        if (wordCount >= maxWordsPerChunk && lastSpaceIndex > 0) {
          // Break at the last space
          final sentence = cleaned.substring(0, lastSpaceIndex).trim();
          final remainder = cleaned.substring(lastSpaceIndex + 1).trim();
          if (sentence.isNotEmpty) {
            return (sentence, remainder);
          }
        }
      }

      // Check for newline (strong break)
      if (char == '\n') {
        final sentence = cleaned.substring(0, i).trim();
        final remainder = cleaned.substring(i + 1).trim();
        if (sentence.isNotEmpty) {
          return (sentence, remainder);
        }
      }

      // Check for clause separators (; : —) followed by space
      if ((char == ';' || char == ':' || char == '—' || char == '–') &&
          i < chars.length - 1 &&
          chars[i + 1] == ' ') {
        // Include the separator in the sentence
        final sentence = cleaned.substring(0, i + 1).trim();
        final remainder = cleaned.substring(i + 2).trim();
        if (sentence.isNotEmpty) {
          return (sentence, remainder);
        }
      }

      // Check for sentence-ending punctuation
      if (char == '.' || char == '?' || char == '!') {
        // Look ahead for space or end of text
        final isEndOfText = i == chars.length - 1;
        final hasSpaceAfter =
            i < chars.length - 1 &&
            (chars[i + 1] == ' ' || chars[i + 1] == '\n');

        if (isEndOfText || hasSpaceAfter) {
          // Get text up to and including this punctuation
          final textUpToHere = cleaned.substring(0, i + 1).trim();
          final lastWord = textUpToHere.split(' ').last.replaceAll('.', '');

          // Check if it's an abbreviation
          final isAbbreviation = abbreviations.any(
            (abbr) => lastWord.toLowerCase() == abbr.toLowerCase(),
          );

          // Check if it's a decimal number (e.g., "3.14")
          final isDecimal =
              char == '.' &&
              i > 0 &&
              i < chars.length - 1 &&
              RegExp(r'\d').hasMatch(chars[i - 1]) &&
              RegExp(r'\d').hasMatch(chars[i + 1]);

          if (!isAbbreviation && !isDecimal) {
            // Found a complete sentence!
            final sentence = textUpToHere;
            // Remainder is everything after the punctuation (skip the space if present)
            var remainderStart = i + 1;
            if (hasSpaceAfter) remainderStart++;
            final remainder = cleaned.substring(remainderStart).trim();
            return (sentence, remainder);
          }
        }
      }
    }

    // No complete sentence found
    return (null, buffer);
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
