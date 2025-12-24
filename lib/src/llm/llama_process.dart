import 'dart:async';
import 'dart:io';

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
      ];

      // Add system prompt if provided
      if (systemPrompt != null) {
        args.addAll(['-sys', systemPrompt!]);
      }

      // For chat with history, we use conversation mode
      if (history != null && history.isNotEmpty) {
        // Build conversation context
        // llama-cli with gemma model handles chat formatting
        args.add('-cnv');

        // Format history into prompt
        final contextPrompt = _formatHistoryAsPrompt(history, prompt);
        args.addAll(['-p', contextPrompt]);
      } else {
        args.addAll(['-p', prompt]);
      }

      final result = await Process.run(
        executablePath,
        args,
        stderrEncoding: const SystemEncoding(),
        stdoutEncoding: const SystemEncoding(),
      ).timeout(timeout);

      if (result.exitCode != 0) {
        throw LlamaException(
          'Llama process failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }

      final output = result.stdout as String;
      return _parseOutput(output, prompt);
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
  String _parseOutput(String output, String prompt) {
    final lines = output.split('\n');
    final responseLines = <String>[];
    var foundPrompt = false;
    var inResponse = false;

    for (final line in lines) {
      // Skip llama-cli UI elements and metadata
      if (line.contains('▄▄') ||
          line.contains('██') ||
          line.contains('build') ||
          line.contains('model') ||
          line.contains('modalities') ||
          line.contains('available commands') ||
          line.contains('/exit') ||
          line.contains('/regen') ||
          line.contains('/clear') ||
          line.contains('/read') ||
          line.contains('llama_') ||
          line.contains('ggml_') ||
          line.contains('Prompt:') ||
          line.contains('Generation:') ||
          line.contains('Exiting') ||
          line.contains('memory breakdown') ||
          line.trim().startsWith('>')) {
        // Mark that we've seen the prompt line
        if (line.trim().startsWith('>')) {
          foundPrompt = true;
          inResponse = true;
        }
        continue;
      }

      // Skip empty lines at the start
      if (!inResponse && line.trim().isEmpty) {
        continue;
      }

      // After the prompt marker, capture response
      if (foundPrompt || inResponse) {
        // Check for end markers
        if (line.isEmpty && responseLines.isNotEmpty) {
          continue;
        }
        responseLines.add(line);
        inResponse = true;
      }
    }

    var response = responseLines.join('\n').trim();

    // If we didn't find the prompt marker, try to extract response differently
    if (response.isEmpty && output.isNotEmpty) {
      // Look for response after the | character (llama output format)
      final pipeIndex = output.indexOf('|');
      if (pipeIndex != -1) {
        final afterPipe = output.substring(pipeIndex + 1);
        // Find the end (llama_ messages)
        final endIndex = afterPipe.indexOf('llama_');
        if (endIndex != -1) {
          response = afterPipe.substring(0, endIndex).trim();
        } else {
          response = afterPipe.trim();
        }
      }
    }

    // Clean up any remaining artifacts
    response = response
        .replaceAll(RegExp(r'\[\s*Prompt:.*?\]'), '')
        .replaceAll(RegExp(r'\[\s*Generation:.*?\]'), '')
        .trim();

    return response;
  }
}
