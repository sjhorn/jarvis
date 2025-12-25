import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.llama);

/// Exception thrown by LlamaProcess operations.
class LlamaException implements Exception {
  final String message;
  final Object? cause;

  LlamaException(this.message, [this.cause]);

  @override
  String toString() =>
      'LlamaException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Represents a message in a chat conversation.
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  /// Creates a user message.
  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);

  /// Creates an assistant message.
  factory ChatMessage.assistant(String content) =>
      ChatMessage(role: 'assistant', content: content);

  /// Creates a system message.
  factory ChatMessage.system(String content) =>
      ChatMessage(role: 'system', content: content);
}

/// Wrapper for llama.cpp LLM text generation via process.
class LlamaProcess {
  final String modelRepo;
  final String executablePath;
  final String? systemPrompt;
  final Duration timeout;

  bool _initialized = false;
  bool _disposed = false;

  LlamaProcess({
    required this.modelRepo,
    required this.executablePath,
    this.systemPrompt,
    this.timeout = const Duration(minutes: 2),
  });

  /// Initializes the llama process by validating the executable exists.
  Future<void> initialize() async {
    if (_disposed) {
      throw LlamaException('LlamaProcess has been disposed');
    }

    // Check executable exists
    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw LlamaException('Llama executable not found at: $executablePath');
    }

    _initialized = true;
  }

  /// Generates a response to a prompt.
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    if (prompt.isEmpty) {
      throw LlamaException('Prompt is empty');
    }
    if (_disposed) {
      throw LlamaException('LlamaProcess has been disposed');
    }
    if (!_initialized) {
      throw LlamaException('LlamaProcess not initialized');
    }

    return _runLlama(prompt, maxTokens: maxTokens);
  }

  /// Generates a response in a chat context with history.
  Future<String> chat(
    String userMessage,
    List<ChatMessage> history, {
    int maxTokens = 256,
  }) async {
    if (userMessage.isEmpty) {
      throw LlamaException('User message is empty');
    }
    if (_disposed) {
      throw LlamaException('LlamaProcess has been disposed');
    }
    if (!_initialized) {
      throw LlamaException('LlamaProcess not initialized');
    }

    // The chat template is handled by llama-cli with -cnv flag
    // We pass the current message as the prompt and history via conversation
    // For simplicity, we'll use single-turn with formatted context
    return _runLlama(userMessage, history: history, maxTokens: maxTokens);
  }

  /// Clears the conversation context.
  void clearContext() {
    // For single-turn mode, there's no persistent context to clear
    // This is a no-op but kept for interface compatibility
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    _disposed = true;
    _initialized = false;
  }

  /// Runs llama-cli with the given prompt.
  Future<String> _runLlama(
    String prompt, {
    List<ChatMessage>? history,
    required int maxTokens,
  }) async {
    try {
      final args = <String>[
        '-hf',
        modelRepo,
        '-n',
        maxTokens.toString(),
        '--single-turn',
        '--no-show-timings',
      ];

      // Add system prompt if provided
      if (systemPrompt != null) {
        args.addAll(['-sys', systemPrompt!]);
      }

      // Build the prompt with history context
      String fullPrompt;
      if (history != null && history.isNotEmpty) {
        fullPrompt = _formatHistoryAsPrompt(history, prompt);
      } else {
        fullPrompt = prompt;
      }
      args.addAll(['-p', fullPrompt]);

      _log.fine('Running llama-cli with prompt: $fullPrompt');

      final result = await Process.run(
        executablePath,
        args,
        stderrEncoding: const SystemEncoding(),
        stdoutEncoding: const SystemEncoding(),
      ).timeout(timeout);

      _log.finest('llama-cli stdout:\n${result.stdout}');
      _log.finest('llama-cli stderr:\n${result.stderr}');

      if (result.exitCode != 0) {
        throw LlamaException(
          'Llama process failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }

      final output = result.stdout as String;
      final response = _parseOutput(output);
      _log.fine('Parsed response: $response');
      return response;
    } on TimeoutException {
      throw LlamaException('Llama generation timed out after $timeout');
    } on ProcessException catch (e) {
      throw LlamaException('Failed to run llama process', e);
    }
  }

  /// Formats chat history as a prompt string for context.
  String _formatHistoryAsPrompt(
    List<ChatMessage> history,
    String currentMessage,
  ) {
    // For gemma model, the history context helps the model understand
    // We'll pass just the current message and let the model's chat template work
    // But include key context from history in the prompt
    final buffer = StringBuffer();

    for (final msg in history) {
      if (msg.role == 'user') {
        buffer.writeln('User: ${msg.content}');
      } else if (msg.role == 'assistant') {
        buffer.writeln('Assistant: ${msg.content}');
      }
    }
    buffer.writeln('User: $currentMessage');

    return buffer.toString();
  }

  /// Parses llama-cli output to extract the response.
  ///
  /// The llama-cli output format is:
  /// ```
  /// [banner/metadata...]
  /// > [user prompt]
  ///
  /// | [response text]
  /// Exiting...
  /// ```
  String _parseOutput(String output) {
    final lines = output.split('\n');
    final responseLines = <String>[];
    var foundPromptMarker = false;

    for (final line in lines) {
      // Look for the prompt marker line (starts with ">")
      if (line.trim().startsWith('>')) {
        foundPromptMarker = true;
        continue;
      }

      // After finding the prompt, look for response lines starting with "|"
      if (foundPromptMarker) {
        // Stop at "Exiting..." or metadata lines
        if (line.trim() == 'Exiting...' ||
            line.contains('llama_') ||
            line.contains('ggml_')) {
          break;
        }

        // Response lines start with "| "
        if (line.startsWith('| ')) {
          responseLines.add(line.substring(2)); // Remove "| " prefix
        } else if (line.startsWith('|')) {
          // Handle case where there's no space after pipe
          responseLines.add(line.substring(1).trimLeft());
        } else if (responseLines.isNotEmpty && line.trim().isNotEmpty) {
          // Continuation lines (multi-line responses)
          responseLines.add(line);
        }
      }
    }

    var response = responseLines.join('\n').trim();

    // Clean up any backspace sequences (spinner artifacts)
    response = response.replaceAll(RegExp(r'[\b]'), '');

    // If we still have no response, try a fallback approach
    if (response.isEmpty) {
      // Look for text between "| " and "Exiting" or "llama_"
      final pipeMatch = RegExp(r'\|\s*(.+?)(?=Exiting|llama_|\n\n|$)', dotAll: true)
          .firstMatch(output);
      if (pipeMatch != null) {
        response = pipeMatch.group(1)?.trim() ?? '';
      }
    }

    return response;
  }
}
