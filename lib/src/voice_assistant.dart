import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'audio/acknowledgment_player.dart';
import 'recording/session_recorder.dart';
import 'audio/audio_input.dart';
import 'audio/audio_output.dart';
import 'context/conversation_context.dart';
import 'llm/llama_process.dart';
import 'logging.dart';
import 'stt/whisper_process.dart';
import 'tts/text_processor.dart';
import 'tts/tts_manager.dart';
import 'vad/voice_activity_detector.dart';
import 'wakeword/wake_word_detector.dart';

final _log = Logger(Loggers.voiceAssistant);

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
  awaitingFollowUp,
  prompting,
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
  final String? acknowledgmentDir;
  final String? systemPrompt;
  final double silenceThreshold;
  final Duration silenceDuration;
  final int maxHistoryLength;
  final Duration sentencePause;

  // Follow-up settings
  final bool enableFollowUp;
  final Duration followUpTimeout;
  final Duration statementFollowUpTimeout;

  // Barge-in settings
  final bool enableBargeIn;
  final String? bargeInDir;

  // Session recording settings
  final bool recordingEnabled;
  final String sessionDir;

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
    this.acknowledgmentDir,
    this.systemPrompt,
    this.silenceThreshold = 0.01,
    this.silenceDuration = const Duration(milliseconds: 800),
    this.maxHistoryLength = 10,
    this.sentencePause = const Duration(milliseconds: 300),
    this.enableFollowUp = true,
    this.followUpTimeout = const Duration(seconds: 4),
    this.statementFollowUpTimeout = const Duration(seconds: 4),
    this.enableBargeIn = true,
    this.bargeInDir,
    this.recordingEnabled = false,
    this.sessionDir = './sessions',
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
  AcknowledgmentPlayer? _acknowledgmentPlayer;
  AcknowledgmentPlayer? _bargeInPlayer;
  SessionRecorder? _recorder;

  // Conversation context
  late final ConversationContext _context;

  // Text processor for TTS
  final _textProcessor = TextProcessor();

  // Audio buffer for recording
  final List<int> _audioBuffer = [];

  // Session recording counter
  int _utteranceCount = 0;

  // Subscriptions
  StreamSubscription? _audioSubscription;
  StreamSubscription? _wakeWordSubscription;
  StreamSubscription? _vadSubscription;

  // Follow-up state
  Timer? _followUpTimer;
  String? _lastQuestion;
  int _promptCount = 0;
  DateTime? _followUpStartTime;
  static const _followUpGracePeriod = Duration(milliseconds: 500);

  // Barge-in state
  bool _bargeInRequested = false;

  // Wake word cooldown to prevent duplicate detections
  DateTime? _lastWakeWordTime;
  static const _wakeWordCooldown = Duration(seconds: 2);

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

    _log.info('Initializing voice assistant...');

    try {
      // Initialize audio input
      _log.fine('Initializing audio input...');
      _audioInput = AudioInput();
      await _audioInput!.initialize();
      _log.fine('Audio input initialized');

      // Initialize audio output
      _log.fine('Initializing audio output...');
      _audioOutput = AudioOutput();
      await _audioOutput!.initialize();
      _log.fine('Audio output initialized');

      // Initialize wake word detector
      _log.fine('Initializing wake word detector...');
      _wakeWordDetector = WakeWordDetector(
        encoderPath: config.wakeWordEncoderPath,
        decoderPath: config.wakeWordDecoderPath,
        joinerPath: config.wakeWordJoinerPath,
        tokensPath: config.wakeWordTokensPath,
        keywordsFile: config.wakeWordKeywordsFile,
        nativeLibPath: config.sherpaLibPath,
      );
      await _wakeWordDetector!.initialize();
      _log.fine('Wake word detector initialized');

      // Initialize VAD
      _log.fine('Initializing VAD...');
      _vad = VoiceActivityDetector(
        silenceThreshold: config.silenceThreshold,
        silenceDuration: config.silenceDuration,
      );
      _log.fine('VAD initialized');

      // Initialize Whisper
      _log.fine('Initializing Whisper (model: ${config.whisperModelPath})...');
      _whisper = WhisperProcess(
        modelPath: config.whisperModelPath,
        executablePath: config.whisperExecutablePath,
      );
      await _whisper!.initialize();
      _log.fine('Whisper initialized');

      // Initialize Llama
      _log.fine('Initializing Llama (model: ${config.llamaModelRepo})...');
      _llama = LlamaProcess(
        modelRepo: config.llamaModelRepo,
        executablePath: config.llamaExecutablePath,
        systemPrompt: config.systemPrompt,
      );
      await _llama!.initialize();
      _log.fine('Llama initialized');

      // Initialize TTS
      _log.fine('Initializing TTS...');
      _tts = TtsManager(
        modelPath: config.ttsModelPath,
        tokensPath: config.ttsTokensPath,
        dataDir: config.ttsDataDir,
        nativeLibPath: config.sherpaLibPath,
      );
      await _tts!.initialize();
      _log.fine('TTS initialized');

      // Initialize acknowledgment player (optional)
      _log.info('Acknowledgment dir config: ${config.acknowledgmentDir}');
      if (config.acknowledgmentDir != null) {
        _log.info('Initializing acknowledgment player...');
        _acknowledgmentPlayer = AcknowledgmentPlayer(
          audioDirectory: config.acknowledgmentDir!,
          audioOutput: _audioOutput!,
        );
        await _acknowledgmentPlayer!.initialize();
        _log.info(
          'Acknowledgment player initialized '
          '(${_acknowledgmentPlayer!.count} audio files)',
        );
      } else {
        _log.info('No acknowledgment directory configured');
      }

      // Initialize barge-in player (optional)
      if (config.bargeInDir != null) {
        _log.info('Initializing barge-in player...');
        _bargeInPlayer = AcknowledgmentPlayer(
          audioDirectory: config.bargeInDir!,
          audioOutput: _audioOutput!,
        );
        await _bargeInPlayer!.initialize();
        _log.info(
          'Barge-in player initialized '
          '(${_bargeInPlayer!.count} audio files)',
        );
      }

      // Initialize session recorder if enabled
      if (config.recordingEnabled) {
        _log.info('Initializing session recorder...');
        _recorder = SessionRecorder(baseDir: config.sessionDir);
        await _recorder!.initialize(_buildSessionConfig());
        _log.info('Session recording enabled: ${_recorder!.sessionId}');
      }

      _isInitialized = true;
      _log.info('Voice assistant initialization complete');
    } catch (e, stackTrace) {
      _log.severe('Failed to initialize assistant', e, stackTrace);
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

    // Set up wake word detection (wrap async handler properly)
    _wakeWordSubscription = _wakeWordDetector!.detections.listen((event) async {
      await _onWakeWord(event);
    });

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

      case AssistantState.awaitingFollowUp:
        // Feed audio to VAD to detect if user starts speaking
        _vad?.processAudio(chunk);
        break;

      case AssistantState.speaking:
      case AssistantState.prompting:
        // Feed audio to wake word detector for barge-in detection
        if (config.enableBargeIn) {
          _wakeWordDetector?.processAudio(chunk);
        }
        break;

      default:
        // Ignore audio in other states
        break;
    }
  }

  /// Handles wake word detection.
  Future<void> _onWakeWord(WakeWordEvent event) async {
    // Ignore duplicate detections within cooldown period
    final now = DateTime.now();
    if (_lastWakeWordTime != null &&
        now.difference(_lastWakeWordTime!) < _wakeWordCooldown) {
      _log.fine('Ignoring duplicate wake word detection (cooldown)');
      return;
    }
    _lastWakeWordTime = now;

    // Handle barge-in during speaking or prompting
    if (_currentState == AssistantState.speaking ||
        _currentState == AssistantState.prompting) {
      if (config.enableBargeIn) {
        _log.info('Barge-in detected: "${event.keyword}"');
        await _handleBargeIn();
      }
      return;
    }

    if (_currentState != AssistantState.listeningForWakeWord) return;

    _log.info('Wake word detected: "${event.keyword}"');
    await _recorder?.recordWakeWord(event.keyword);

    // Play acknowledgment if available
    if (_acknowledgmentPlayer != null && _acknowledgmentPlayer!.hasAcknowledgments) {
      _log.info('Playing acknowledgment...');
      await _acknowledgmentPlayer!.playRandom();
      _log.info('Acknowledgment playback complete');
    } else {
      _log.info('No acknowledgment player available '
          '(player: ${_acknowledgmentPlayer != null}, '
          'hasAck: ${_acknowledgmentPlayer?.hasAcknowledgments})');
    }

    // Transition to listening state
    _setState(AssistantState.listening);
    _audioBuffer.clear();
    _vad?.reset();
  }

  /// Handles barge-in (user interrupts while speaking).
  Future<void> _handleBargeIn() async {
    if (_bargeInRequested) return; // Already handling barge-in
    _bargeInRequested = true;

    _cancelFollowUpTimer();

    // Transition to listening FIRST so audio immediately routes to VAD
    // (before async stop() which takes ~100ms)
    _audioBuffer.clear();
    _vad?.reset();
    _setState(AssistantState.listening);

    _log.info('Barge-in: stopping audio, now listening');

    // Stop any playing audio (async, but audio already routing to VAD)
    await _audioOutput?.stop();

    // Play barge-in acknowledgment to confirm we're listening
    if (_bargeInPlayer != null && _bargeInPlayer!.hasAcknowledgments) {
      await _bargeInPlayer!.playRandom();
    }

    // Record barge-in event
    await _recorder?.recordBargeIn();

    _bargeInRequested = false;
  }

  /// Handles VAD events.
  Future<void> _onVadEvent(VADEvent event) async {
    _log.finest('VAD event: ${event.state} (state: $_currentState)');

    // Handle VAD in awaitingFollowUp state
    if (_currentState == AssistantState.awaitingFollowUp) {
      if (event.state == VADState.speech) {
        // Ignore speech events during grace period to let audio settle
        if (_followUpStartTime != null) {
          final elapsed = DateTime.now().difference(_followUpStartTime!);
          if (elapsed < _followUpGracePeriod) {
            _log.fine('Ignoring speech during grace period (${elapsed.inMilliseconds}ms)');
            return;
          }
        }

        // User started speaking, transition to listening
        _log.info('Speech detected during follow-up, transitioning to listening');
        _cancelFollowUpTimer();
        _setState(AssistantState.listening);
        _audioBuffer.clear();
        _vad?.reset();
      }
      return;
    }

    if (_currentState != AssistantState.listening) return;

    if (event.state == VADState.silence) {
      // User stopped speaking, process the audio
      await _processUserSpeech();
    }
  }

  /// Starts the follow-up timeout timer.
  void _startFollowUpTimer(Duration timeout) {
    _cancelFollowUpTimer();
    _log.fine('Starting follow-up timer (${timeout.inMilliseconds}ms)');
    _followUpTimer = Timer(timeout, () {
      _log.fine('Follow-up timer fired');
      _onFollowUpTimeout();
    });
  }

  /// Cancels the follow-up timeout timer.
  void _cancelFollowUpTimer() {
    if (_followUpTimer != null) {
      _log.fine('Cancelling follow-up timer');
    }
    _followUpTimer?.cancel();
    _followUpTimer = null;
  }

  /// Handles follow-up timeout.
  Future<void> _onFollowUpTimeout() async {
    _log.fine('_onFollowUpTimeout called (state: $_currentState, promptCount: $_promptCount, lastQuestion: $_lastQuestion)');

    if (_currentState != AssistantState.awaitingFollowUp) {
      _log.fine('Ignoring timeout - not in awaitingFollowUp state');
      return;
    }

    if (_promptCount == 0 && _lastQuestion != null) {
      // First timeout: repeat the question
      _log.info('Follow-up timeout, repeating question');
      _promptCount++;
      await _speakPrompt(_lastQuestion!);
    } else {
      // Second timeout or no question: give up, return to wake word
      _log.info('No follow-up response, returning to wake word detection');
      _lastQuestion = null;
      _promptCount = 0;
      _followUpStartTime = null;
      _setState(AssistantState.listeningForWakeWord);
    }
  }

  /// Speaks a prompt and returns to awaitingFollowUp.
  Future<void> _speakPrompt(String text) async {
    _setState(AssistantState.prompting);

    try {
      final sentences = _textProcessor.process(text);
      for (var i = 0; i < sentences.length; i++) {
        // Check for barge-in (check state, not just flag)
        if (_currentState != AssistantState.prompting) {
          _log.fine('State changed during prompting (barge-in), stopping');
          return;
        }

        final sentence = sentences[i];
        _log.fine('Prompting: "$sentence"');
        final ttsResult = await _tts!.synthesize(sentence);
        final pcmAudio = ttsResult.toPcm16();
        await _audioOutput!.play(pcmAudio, audioSampleRate: ttsResult.sampleRate);

        if (i < sentences.length - 1 && config.sentencePause.inMilliseconds > 0) {
          await Future<void>.delayed(config.sentencePause);
        }
      }

      // Return to awaiting follow-up (use question timeout since we just prompted)
      _followUpStartTime = DateTime.now();
      _setState(AssistantState.awaitingFollowUp);
      _vad?.reset();
      _startFollowUpTimer(config.followUpTimeout);
    } catch (e, stackTrace) {
      _log.severe('Error speaking prompt', e, stackTrace);
      _setState(AssistantState.listeningForWakeWord);
    }
  }

  /// Processes user speech after silence is detected.
  Future<void> _processUserSpeech() async {
    final audioSize = _audioBuffer.length;
    _log.fine('Processing user speech (buffer size: $audioSize bytes)');

    if (_audioBuffer.isEmpty) {
      _log.fine('Audio buffer empty, returning to wake word detection');
      _setState(AssistantState.listeningForWakeWord);
      return;
    }

    _setState(AssistantState.processing);

    try {
      // Transcribe audio
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();

      // Record user audio
      final audioRef = _utteranceCount++;
      await _recorder?.recordUserAudio(audioData);

      _log.fine('Transcribing audio with Whisper...');
      final transcription = await _whisper!.transcribe(audioData);

      if (transcription.isEmpty) {
        _log.fine('Transcription empty, returning to wake word detection');
        _setState(AssistantState.listeningForWakeWord);
        return;
      }

      _log.info('Transcription: "$transcription"');
      _transcriptionController.add(transcription);

      // Record transcription
      await _recorder?.recordTranscription(transcription, audioRef);

      // Add to conversation context
      _context.addUserMessage(transcription);

      // Get LLM response
      _log.fine('Generating LLM response...');
      final chatMessages = _context.getChatMessages();
      final response = await _llama!.chat(transcription, chatMessages);
      _log.info('LLM response: "$response"');

      // Add response to context
      _context.addAssistantMessage(response);
      _responseController.add(response);

      // Speak response sentence by sentence
      _setState(AssistantState.speaking);
      final sentences = _textProcessor.process(response);
      _log.fine('Split response into ${sentences.length} sentences');

      // Record response and set speaking state for barge-in tracking
      await _recorder?.recordResponse(response, sentences.length);
      _recorder?.setSpeakingState(sentences);

      for (var i = 0; i < sentences.length; i++) {
        // Check for barge-in before each sentence (check state, not just flag)
        if (_currentState != AssistantState.speaking) {
          _log.fine('State changed during speaking (barge-in), stopping');
          return;
        }

        final sentence = sentences[i];
        _log.fine('Synthesizing sentence ${i + 1}/${sentences.length}: "$sentence"');
        final ttsResult = await _tts!.synthesize(sentence);
        final pcmAudio = ttsResult.toPcm16();
        _log.fine('Playing audio (${pcmAudio.length} bytes at ${ttsResult.sampleRate}Hz)...');
        await _audioOutput!.play(pcmAudio, audioSampleRate: ttsResult.sampleRate);

        // Advance sentence index for barge-in tracking
        _recorder?.advanceSentence();

        // Add pause between sentences (but not after the last one)
        if (i < sentences.length - 1 && config.sentencePause.inMilliseconds > 0) {
          await Future<void>.delayed(config.sentencePause);
        }
      }

      // Check if we were interrupted by barge-in during or after last sentence
      if (_currentState != AssistantState.speaking) {
        _log.fine('Barge-in detected, skipping follow-up logic');
        return;
      }

      // Always listen for follow-up if enabled
      if (config.enableFollowUp) {
        final lastQuestion = _textProcessor.extractLastQuestion(sentences);
        _lastQuestion = lastQuestion; // null if not a question
        _promptCount = 0;
        _followUpStartTime = DateTime.now();
        _setState(AssistantState.awaitingFollowUp);
        _vad?.reset();

        if (lastQuestion != null) {
          _log.info('Response ends with question, awaiting follow-up (${config.followUpTimeout.inSeconds}s)');
          _startFollowUpTimer(config.followUpTimeout);
        } else {
          _log.info('Awaiting follow-up (${config.statementFollowUpTimeout.inSeconds}s)');
          _startFollowUpTimer(config.statementFollowUpTimeout);
        }
      } else {
        _log.fine('Response complete, returning to wake word detection');
        _lastQuestion = null;
        _promptCount = 0;
        _setState(AssistantState.listeningForWakeWord);
      }
    } catch (e, stackTrace) {
      _log.severe('Error processing speech', e, stackTrace);
      _setState(AssistantState.error);
      // Recover by returning to listening state after a delay
      await Future<void>.delayed(const Duration(seconds: 1));
      _setState(AssistantState.listeningForWakeWord);
    }
  }

  /// Builds session config for recording.
  Map<String, dynamic> _buildSessionConfig() {
    return {
      'systemPrompt': config.systemPrompt,
      'enableFollowUp': config.enableFollowUp,
      'followUpTimeout': config.followUpTimeout.inMilliseconds,
      'enableBargeIn': config.enableBargeIn,
      'whisperModel': config.whisperModelPath,
      'llamaModel': config.llamaModelRepo,
    };
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

    // Cancel timers
    _cancelFollowUpTimer();

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
    _lastQuestion = null;
    _promptCount = 0;
    _followUpStartTime = null;
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
    await _acknowledgmentPlayer?.dispose();
    await _bargeInPlayer?.dispose();
    await _recorder?.dispose();

    _audioInput = null;
    _audioOutput = null;
    _wakeWordDetector = null;
    _vad = null;
    _whisper = null;
    _llama = null;
    _tts = null;
    _acknowledgmentPlayer = null;
    _bargeInPlayer = null;
    _recorder = null;

    _isInitialized = false;
  }
}
