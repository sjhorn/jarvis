import '../llm/llama_process.dart';

/// Manages conversation history and formatting for LLM interactions.
///
/// Maintains a history of user and assistant messages, formats them
/// for use with llama.cpp, and handles context window management.
class ConversationContext {
  final int maxHistoryLength;
  String? _systemPrompt;
  final List<ChatMessage> _history = [];

  ConversationContext({String? systemPrompt, this.maxHistoryLength = 10})
    : _systemPrompt = systemPrompt;

  /// The current system prompt.
  String? get systemPrompt => _systemPrompt;

  /// Whether the conversation history is empty.
  bool get isEmpty => _history.isEmpty;

  /// Number of messages in the history.
  int get messageCount => _history.length;

  /// The last message in the history, or null if empty.
  ChatMessage? get lastMessage => _history.isEmpty ? null : _history.last;

  /// Adds a user message to the conversation history.
  void addUserMessage(String content) {
    _addMessage(ChatMessage.user(content));
  }

  /// Adds an assistant message to the conversation history.
  void addAssistantMessage(String content) {
    _addMessage(ChatMessage.assistant(content));
  }

  /// Adds a message and enforces max history length.
  void _addMessage(ChatMessage message) {
    _history.add(message);

    // Enforce max history length (FIFO)
    if (maxHistoryLength > 0 && _history.length > maxHistoryLength) {
      _history.removeAt(0);
    }
  }

  /// Returns an unmodifiable copy of the conversation history.
  List<ChatMessage> getHistory() {
    return List.unmodifiable(_history);
  }

  /// Returns the conversation formatted for llama.cpp input.
  ///
  /// Format:
  /// ```
  /// System: <system prompt>
  /// User: <user message>
  /// Assistant: <assistant response>
  /// ...
  /// ```
  String formatForLlama() {
    final buffer = StringBuffer();

    // Add system prompt first if set
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      buffer.writeln('System: $_systemPrompt');
      buffer.writeln();
    }

    // Add conversation history
    for (final message in _history) {
      final roleLabel = _getRoleLabel(message.role);
      buffer.writeln('$roleLabel: ${message.content}');
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  /// Converts role to display label.
  String _getRoleLabel(String role) {
    switch (role) {
      case 'user':
        return 'User';
      case 'assistant':
        return 'Assistant';
      case 'system':
        return 'System';
      default:
        return role;
    }
  }

  /// Returns ChatMessage list including system prompt for LlamaProcess.
  ///
  /// This is useful when calling LlamaProcess.chat() directly.
  List<ChatMessage> getChatMessages() {
    final messages = <ChatMessage>[];

    // Add system prompt first if set
    if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
      messages.add(ChatMessage.system(_systemPrompt!));
    }

    // Add conversation history
    messages.addAll(_history);

    return messages;
  }

  /// Clears all messages from the history.
  ///
  /// Note: This preserves the system prompt.
  void clear() {
    _history.clear();
  }

  /// Sets or updates the system prompt.
  ///
  /// Pass null to clear the system prompt.
  void setSystemPrompt(String? prompt) {
    _systemPrompt = prompt;
  }
}
