import 'dart:async';
import 'dart:convert';
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

/// Wrapper for llama.cpp LLM text generation via persistent interactive process.
///
/// This class keeps llama-cli running in conversation mode, communicating
/// via stdin/stdout pipes. This avoids the model reload overhead on each request.
class LlamaProcess {
  final String modelRepo;
  final String executablePath;
  final String? systemPrompt;
  final Duration timeout;
  final int maxTokens;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final _outputBuffer = StringBuffer();
  Completer<String>? _responseCompleter;
  StreamController<String>? _tokenStreamController;
  bool _initialized = false;
  bool _disposed = false;
  bool _ready = false;
  bool _isStreaming = false;

  LlamaProcess({
    required this.modelRepo,
    required this.executablePath,
    this.systemPrompt,
    this.timeout = const Duration(minutes: 2),
    this.maxTokens = 256,
  });

  /// Whether the process is initialized and ready.
  bool get isReady => _initialized && _ready && !_disposed;

  /// Initializes the llama process by starting it in conversation mode.
  Future<void> initialize() async {
    if (_disposed) {
      throw LlamaException('LlamaProcess has been disposed');
    }
    if (_initialized) return;

    // Check executable exists
    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw LlamaException('Llama executable not found at: $executablePath');
    }

    _log.info('Starting llama-cli in conversation mode...');

    try {
      final args = <String>[
        '-hf',
        modelRepo,
        '-n',
        maxTokens.toString(),
        '-ngl', '99', // Offload all layers to GPU (Metal on macOS)
        '--conversation',
        '--simple-io', // Required for subprocess compatibility
        '--no-display-prompt',
        '--no-show-timings',
      ];

      // Add system prompt if provided
      if (systemPrompt != null) {
        args.addAll(['-sys', systemPrompt!]);
      }

      _log.fine('Starting process: $executablePath ${args.join(' ')}');

      _process = await Process.start(
        executablePath,
        args,
        mode: ProcessStartMode.normal,
      );

      // Set up stdout listener
      _stdoutSubscription = _process!.stdout
          .transform(utf8.decoder)
          .listen(_onStdout);

      // Set up stderr listener (for debugging)
      _stderrSubscription = _process!.stderr
          .transform(utf8.decoder)
          .listen(_onStderr);

      // Wait for the initial prompt (">")
      _log.fine('Waiting for initial prompt...');
      await _waitForPrompt().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw LlamaException('Timeout waiting for llama-cli to start');
        },
      );

      _initialized = true;
      _ready = true;
      _log.info('Llama process ready');
    } catch (e) {
      await _cleanup();
      throw LlamaException('Failed to start llama process', e);
    }
  }

  /// Handles stdout data from the process.
  void _onStdout(String data) {
    _log.finest('stdout: $data');
    _outputBuffer.write(data);

    // Check if we've received a complete response (ends with "> " prompt)
    final content = _outputBuffer.toString();
    final isComplete = content.contains('\n> ') || content.endsWith('\n> ');

    if (_isStreaming && _tokenStreamController != null) {
      // Streaming mode: emit cleaned tokens incrementally
      if (!isComplete) {
        // Emit the new chunk (cleaned)
        final cleanedChunk = _cleanChunk(data);
        if (cleanedChunk.isNotEmpty) {
          _tokenStreamController!.add(cleanedChunk);
        }
      } else {
        // Response complete - emit final chunk and close stream
        // Extract text before the "> " prompt
        var endIndex = content.lastIndexOf('\n> ');
        if (endIndex == -1) endIndex = content.lastIndexOf('\n>');
        if (endIndex == -1) endIndex = content.length;

        // Find what we haven't emitted yet (the last chunk before prompt)
        final emittedLength = content.length - data.length;
        if (endIndex > emittedLength) {
          final remaining = content.substring(emittedLength, endIndex);
          final cleanedRemaining = _cleanChunk(remaining);
          if (cleanedRemaining.isNotEmpty) {
            _tokenStreamController!.add(cleanedRemaining);
          }
        }

        _ready = true;
        _isStreaming = false;
        _tokenStreamController!.close();
        _tokenStreamController = null;
      }
    } else if (isComplete) {
      // Blocking mode: complete the response
      _ready = true;
      if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
        _responseCompleter!.complete(content);
      }
    }
  }

  /// Cleans a chunk of output for streaming.
  String _cleanChunk(String chunk) {
    var result = chunk;

    // Strip "| " prefix (backwards compatibility with some llama versions)
    if (result.startsWith('| ')) {
      result = result.substring(2);
    } else if (result.startsWith('|')) {
      result = result.substring(1);
    }

    // Remove control characters (backspace, etc.)
    result = result.replaceAll(RegExp(r'[\b\x08]'), '');

    return result;
  }

  /// Handles stderr data from the process.
  void _onStderr(String data) {
    _log.finest('stderr: $data');
  }

  /// Waits for the initial "> " prompt indicating the model is ready.
  Future<void> _waitForPrompt() async {
    final completer = Completer<void>();

    void checkReady() {
      final content = _outputBuffer.toString();
      if (content.contains('\n> ') || content.endsWith('> ')) {
        if (!completer.isCompleted) {
          _outputBuffer.clear();
          completer.complete();
        }
      }
    }

    // Check periodically until ready
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (completer.isCompleted) {
        timer.cancel();
        return;
      }
      checkReady();
    });

    await completer.future;
  }

  /// Generates a response to a prompt.
  ///
  /// Note: [maxTokens] parameter is accepted for API compatibility but
  /// is ignored in persistent mode (token limit is set at initialization).
  Future<String> generate(String prompt, {int? maxTokens}) async {
    return chat(prompt, []);
  }

  /// Generates a response in a chat context.
  ///
  /// In persistent mode, the process maintains its own conversation history,
  /// so the [history] parameter is ignored. Just send the current message.
  /// The [maxTokens] parameter is also ignored (set at initialization).
  ///
  /// Use [clearContext] to reset the conversation if needed.
  Future<String> chat(
    String userMessage,
    List<ChatMessage> history, {
    int? maxTokens,
  }) async {
    if (userMessage.isEmpty) {
      throw LlamaException('User message is empty');
    }
    if (_disposed) {
      throw LlamaException('LlamaProcess has been disposed');
    }
    if (!_initialized || _process == null) {
      throw LlamaException('LlamaProcess not initialized');
    }
    if (!_ready) {
      throw LlamaException('LlamaProcess not ready for input');
    }

    // In persistent mode, the process maintains its own history.
    // Just send the user message directly.
    _log.fine('Sending message: $userMessage');

    try {
      // Clear buffer and set up response completer
      _outputBuffer.clear();
      _responseCompleter = Completer<String>();
      _ready = false;

      // Send the message
      _process!.stdin.writeln(userMessage);
      await _process!.stdin.flush();

      // Wait for response with timeout
      final rawOutput = await _responseCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          throw LlamaException('Response timeout after $timeout');
        },
      );

      // Parse the response
      final response = _parseResponse(rawOutput, userMessage);
      _log.fine('Response: $response');

      return response;
    } catch (e) {
      _ready = true; // Reset ready state
      if (e is LlamaException) rethrow;
      throw LlamaException('Failed to get response', e);
    }
  }

  /// Streams tokens from the LLM as they are generated.
  ///
  /// This is similar to [chat] but returns a stream of tokens instead of
  /// waiting for the complete response. Useful for pipelining to TTS.
  ///
  /// In persistent mode, the process maintains its own conversation history,
  /// so the [history] parameter is ignored.
  Stream<String> chatStream(
    String userMessage,
    List<ChatMessage> history,
  ) {
    if (userMessage.isEmpty) {
      return Stream.error(LlamaException('User message is empty'));
    }
    if (_disposed) {
      return Stream.error(LlamaException('LlamaProcess has been disposed'));
    }
    if (!_initialized || _process == null) {
      return Stream.error(LlamaException('LlamaProcess not initialized'));
    }
    if (!_ready) {
      return Stream.error(LlamaException('LlamaProcess not ready for input'));
    }

    _log.fine('Streaming message: $userMessage');

    // Create stream controller
    _tokenStreamController = StreamController<String>();
    _outputBuffer.clear();
    _ready = false;
    _isStreaming = true;

    // Send the message asynchronously
    _sendMessage(userMessage);

    return _tokenStreamController!.stream;
  }

  /// Sends a message to the process.
  Future<void> _sendMessage(String message) async {
    try {
      _process!.stdin.writeln(message);
      await _process!.stdin.flush();
    } catch (e) {
      _ready = true;
      _isStreaming = false;
      _tokenStreamController?.addError(LlamaException('Failed to send message', e));
      _tokenStreamController?.close();
      _tokenStreamController = null;
    }
  }

  /// Cancels an ongoing streaming operation.
  ///
  /// Call this when you need to interrupt streaming (e.g., on barge-in).
  void cancelStream() {
    if (_isStreaming && _tokenStreamController != null) {
      _log.fine('Cancelling stream');
      _isStreaming = false;
      _tokenStreamController!.close();
      _tokenStreamController = null;
      // Note: The process will still complete generating, but we won't emit
      // any more tokens. The next response prompt will reset state.
    }
  }

  /// Parses the response from llama-cli output.
  ///
  /// With --simple-io and --no-display-prompt, the format is:
  /// ```
  /// [response text...]
  ///
  /// >
  /// ```
  String _parseResponse(String output, String userMessage) {
    // Find the end marker ("> " prompt for next input)
    var endIndex = output.lastIndexOf('\n> ');
    if (endIndex == -1) {
      endIndex = output.lastIndexOf('\n>');
    }
    if (endIndex == -1) {
      endIndex = output.length;
    }

    var response = output.substring(0, endIndex);

    // Strip any "| " prefix (for backwards compatibility)
    final lines = response.split('\n');
    final cleanedLines = lines.map((line) {
      if (line.startsWith('| ')) {
        return line.substring(2);
      } else if (line.startsWith('|') && line.length > 1) {
        return line.substring(1).trimLeft();
      }
      return line;
    }).toList();

    response = cleanedLines.join('\n').trim();

    // Clean up any control characters (backspace, etc)
    response = response.replaceAll(RegExp(r'[\b\x08]'), '');

    return response;
  }

  /// Clears the conversation context by sending /clear command.
  Future<void> clearContext() async {
    if (!_initialized || _process == null || _disposed) return;

    _log.fine('Clearing conversation context');

    try {
      _outputBuffer.clear();
      _responseCompleter = Completer<String>();
      _ready = false;

      _process!.stdin.writeln('/clear');
      await _process!.stdin.flush();

      // Wait for confirmation
      await _responseCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => '', // Ignore timeout for /clear
      );

      _ready = true;
    } catch (e) {
      _ready = true;
      _log.warning('Failed to clear context: $e');
    }
  }

  /// Disposes of resources and stops the process.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _log.fine('Disposing llama process');

    await _cleanup();

    _initialized = false;
    _ready = false;
  }

  Future<void> _cleanup() async {
    // Close any active stream
    _isStreaming = false;
    await _tokenStreamController?.close();
    _tokenStreamController = null;

    // Cancel subscriptions
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    // Try graceful shutdown
    if (_process != null) {
      try {
        _process!.stdin.writeln('/exit');
        await _process!.stdin.flush();
        await _process!.stdin.close();

        // Give it a moment to exit gracefully
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        // Ignore errors during cleanup
      }

      // Force kill if still running
      _process!.kill(ProcessSignal.sigterm);
      _process = null;
    }

    _outputBuffer.clear();
    _responseCompleter = null;
  }
}
