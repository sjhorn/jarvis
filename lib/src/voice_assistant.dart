import 'dart:async';
import 'dart:typed_data';

import 'audio/audio_input.dart';
import 'audio/audio_output.dart';
import 'context/conversation_context.dart';
import 'llm/llama_process.dart';
import 'stt/whisper_process.dart';
import 'tts/tts_manager.dart';
import 'vad/voice_activity_detector.dart';
import 'wakeword/wake_word_detector.dart';

/// Exception thrown when voice assistant operations fail.
class VoiceAssistantException implements Exception {
  final String message;
  final Object? cause;

  VoiceAssistantException(this.message, [this.cause]);

  @override
  String toString() =>
      'VoiceAssistantException: $message${cause != null ? ' ($cause)' : ''}';
}

/// State of the voice assistant.
enum AssistantState {
  idle,
  listeningForWakeWord,
  listening,
  processing,
  speaking,
  error,
}

/// Configuration for the voice assistant.
class VoiceAssistantConfig {
  // Whisper settings
  final String whisperModelPath;
  final String whisperExecutablePath;

  // Llama settings
  final String llamaModelRepo;
  final String llamaExecutablePath;

  // Wake word settings
  final String wakeWordEncoderPath;
  final String wakeWordDecoderPath;
  final String wakeWordJoinerPath;
  final String wakeWordTokensPath;
  final String wakeWordKeywordsFile;

  // TTS settings
  final String ttsModelPath;
  final String ttsTokensPath;
  final String ttsDataDir;

  // Sherpa library path
  final String sherpaLibPath;

  // Optional settings
  final String? systemPrompt;
  final double silenceThreshold;
  final Duration silenceDuration;
  final int maxHistoryLength;

  VoiceAssistantConfig({
    required this.whisperModelPath,
    required this.whisperExecutablePath,
    required this.llamaModelRepo,
    required this.llamaExecutablePath,
    required this.wakeWordEncoderPath,
    required this.wakeWordDecoderPath,
    required this.wakeWordJoinerPath,
    required this.wakeWordTokensPath,
    required this.wakeWordKeywordsFile,
    required this.ttsModelPath,
    required this.ttsTokensPath,
    required this.ttsDataDir,
    required this.sherpaLibPath,
    this.systemPrompt,
    this.silenceThreshold = 0.01,
    this.silenceDuration = const Duration(milliseconds: 800),
    this.maxHistoryLength = 10,
  });
}

/// Voice assistant orchestrator that coordinates all modules.
///
/// This is the main class that ties together:
/// - Wake word detection
/// - Audio input/output
/// - Voice activity detection
/// - Speech-to-text (Whisper)
/// - LLM responses (Llama)
/// - Text-to-speech
/// - Conversation context
class VoiceAssistant {
  final VoiceAssistantConfig config;

  // State management
  AssistantState _currentState = AssistantState.idle;
  bool _isRunning = false;
  bool _isInitialized = false;
  bool _disposed = false;

  // Stream controllers
  final _stateController = StreamController<AssistantState>.broadcast();
  final _transcriptionController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();

  // Modules (initialized lazily)
  AudioInput? _audioInput;
  AudioOutput? _audioOutput;
  WakeWordDetector? _wakeWordDetector;
  VoiceActivityDetector? _vad;
  WhisperProcess? _whisper;
  LlamaProcess? _llama;
  TtsManager? _tts;

  // Conversation context
  late final ConversationContext _context;

  // Audio buffer for recording
  final List<int> _audioBuffer = [];

  // Subscriptions
  StreamSubscription? _audioSubscription;
  StreamSubscription? _wakeWordSubscription;
  StreamSubscription? _vadSubscription;

  VoiceAssistant({required this.config}) {
    _context = ConversationContext(
      systemPrompt: config.systemPrompt,
      maxHistoryLength: config.maxHistoryLength,
    );
  }

  /// Current state of the assistant.
  AssistantState get currentState => _currentState;

  /// Whether the assistant is running.
  bool get isRunning => _isRunning;

  /// Whether the assistant is initialized.
  bool get isInitialized => _isInitialized;

  /// Stream of state changes.
  Stream<AssistantState> get stateStream => _stateController.stream;

  /// Stream of transcriptions.
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  /// Stream of LLM responses.
  Stream<String> get responseStream => _responseController.stream;

  /// The conversation context.
  ConversationContext get context => _context;

  /// Initializes all modules.
  Future<void> initialize() async {
    if (_disposed) {
      throw VoiceAssistantException('Assistant has been disposed');
    }
    if (_isInitialized) return;

    try {
      // Initialize audio input
      _audioInput = AudioInput();
      await _audioInput!.initialize();

      // Initialize audio output
      _audioOutput = AudioOutput();
      await _audioOutput!.initialize();

      // Initialize wake word detector
      _wakeWordDetector = WakeWordDetector(
        encoderPath: config.wakeWordEncoderPath,
        decoderPath: config.wakeWordDecoderPath,
        joinerPath: config.wakeWordJoinerPath,
        tokensPath: config.wakeWordTokensPath,
        keywordsFile: config.wakeWordKeywordsFile,
        nativeLibPath: config.sherpaLibPath,
      );
      await _wakeWordDetector!.initialize();

      // Initialize VAD
      _vad = VoiceActivityDetector(
        silenceThreshold: config.silenceThreshold,
        silenceDuration: config.silenceDuration,
      );

      // Initialize Whisper
      _whisper = WhisperProcess(
        modelPath: config.whisperModelPath,
        executablePath: config.whisperExecutablePath,
      );
      await _whisper!.initialize();

      // Initialize Llama
      _llama = LlamaProcess(
        modelRepo: config.llamaModelRepo,
        executablePath: config.llamaExecutablePath,
      );
      await _llama!.initialize();

      // Initialize TTS
      _tts = TtsManager(
        modelPath: config.ttsModelPath,
        tokensPath: config.ttsTokensPath,
        dataDir: config.ttsDataDir,
        nativeLibPath: config.sherpaLibPath,
      );
      await _tts!.initialize();

      _isInitialized = true;
    } catch (e) {
      await _disposeModules();
      throw VoiceAssistantException('Failed to initialize assistant', e);
    }
  }

  /// Starts the voice assistant.
  Future<void> start() async {
    if (_disposed) {
      throw VoiceAssistantException('Assistant has been disposed');
    }
    if (!_isInitialized) {
      throw VoiceAssistantException('Assistant not initialized');
    }
    if (_isRunning) return;

    _isRunning = true;
    _setState(AssistantState.listeningForWakeWord);

    // Start audio input
    await _audioInput!.startRecording();

    // Set up audio processing pipeline
    _audioSubscription = _audioInput!.audioStream.listen(_processAudioChunk);

    // Set up wake word detection
    _wakeWordSubscription = _wakeWordDetector!.detections.listen(_onWakeWord);

    // Set up VAD events
    _vadSubscription = _vad!.events.listen(_onVadEvent);
  }

  /// Processes an audio chunk through the pipeline.
  void _processAudioChunk(Uint8List chunk) {
    if (!_isRunning) return;

    switch (_currentState) {
      case AssistantState.listeningForWakeWord:
        // Feed audio to wake word detector
        _wakeWordDetector?.processAudio(chunk);
        break;

      case AssistantState.listening:
        // Feed audio to VAD and buffer for transcription
        _vad?.processAudio(chunk);
        _audioBuffer.addAll(chunk);
        break;

      default:
        // Ignore audio in other states
        break;
    }
  }

  /// Handles wake word detection.
  void _onWakeWord(WakeWordEvent event) {
    if (_currentState != AssistantState.listeningForWakeWord) return;

    // Transition to listening state
    _setState(AssistantState.listening);
    _audioBuffer.clear();
    _vad?.reset();
  }

  /// Handles VAD events.
  Future<void> _onVadEvent(VADEvent event) async {
    if (_currentState != AssistantState.listening) return;

    if (event.state == VADState.silence) {
      // User stopped speaking, process the audio
      await _processUserSpeech();
    }
  }

  /// Processes user speech after silence is detected.
  Future<void> _processUserSpeech() async {
    if (_audioBuffer.isEmpty) {
      _setState(AssistantState.listeningForWakeWord);
      return;
    }

    _setState(AssistantState.processing);

    try {
      // Transcribe audio
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();

      final transcription = await _whisper!.transcribe(audioData);
      if (transcription.isEmpty) {
        _setState(AssistantState.listeningForWakeWord);
        return;
      }

      _transcriptionController.add(transcription);

      // Add to conversation context
      _context.addUserMessage(transcription);

      // Get LLM response
      final chatMessages = _context.getChatMessages();
      final response = await _llama!.chat(transcription, chatMessages);

      // Add response to context
      _context.addAssistantMessage(response);
      _responseController.add(response);

      // Speak response
      _setState(AssistantState.speaking);
      final ttsResult = await _tts!.synthesize(response);
      final pcmAudio = ttsResult.toPcm16();
      await _audioOutput!.play(pcmAudio);

      // Return to listening for wake word
      _setState(AssistantState.listeningForWakeWord);
    } catch (e) {
      _setState(AssistantState.error);
      // Recover by returning to listening state after a delay
      await Future<void>.delayed(const Duration(seconds: 1));
      _setState(AssistantState.listeningForWakeWord);
    }
  }

  /// Updates the current state and notifies listeners.
  void _setState(AssistantState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Stops the voice assistant.
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;

    // Cancel subscriptions
    await _audioSubscription?.cancel();
    await _wakeWordSubscription?.cancel();
    await _vadSubscription?.cancel();

    _audioSubscription = null;
    _wakeWordSubscription = null;
    _vadSubscription = null;

    // Stop recording
    try {
      await _audioInput?.stopRecording();
    } catch (_) {}

    // Stop any playing audio
    try {
      await _audioOutput?.stop();
    } catch (_) {}

    _audioBuffer.clear();
    _setState(AssistantState.idle);
  }

  /// Clears the conversation history.
  void clearConversation() {
    _context.clear();
  }

  /// Disposes of all resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await stop();
    await _disposeModules();

    await _stateController.close();
    await _transcriptionController.close();
    await _responseController.close();

    _currentState = AssistantState.idle;
  }

  /// Disposes of all modules.
  Future<void> _disposeModules() async {
    await _audioInput?.dispose();
    await _audioOutput?.dispose();
    await _wakeWordDetector?.dispose();
    await _whisper?.dispose();
    await _llama?.dispose();
    await _tts?.dispose();

    _audioInput = null;
    _audioOutput = null;
    _wakeWordDetector = null;
    _vad = null;
    _whisper = null;
    _llama = null;
    _tts = null;

    _isInitialized = false;
  }
}
