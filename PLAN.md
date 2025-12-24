# Voice Assistant Development Plan

## Project Overview

A Dart-based voice assistant application that:
1. Listens for a wake word using sherpa_onnx
2. Records audio until silence is detected
3. Transcribes speech using whisper.cpp (via process pipe)
4. Generates responses using llama.cpp (via process pipe)
5. Converts response to speech using sherpa_onnx TTS
6. Maintains conversation context across turns

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VoiceAssistant                           │
│                      (Orchestrator/Main)                        │
└─────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│  AudioInput   │      │ Conversation  │      │  AudioOutput  │
│    Module     │      │    Context    │      │    Module     │
└───────────────┘      └───────────────┘      └───────────────┘
        │                                              ▲
        ▼                                              │
┌───────────────┐                            ┌───────────────┐
│  WakeWord     │                            │     TTS       │
│  Detector     │                            │   (sherpa)    │
│  (sherpa)     │                            └───────────────┘
└───────────────┘                                      ▲
        │                                              │
        ▼                                              │
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│    VAD /      │      │   Whisper     │      │    Llama      │
│   Silence     │ ───▶ │   Process     │ ───▶ │   Process     │
│  Detection    │      │   (pipe)      │      │   (pipe)      │
└───────────────┘      └───────────────┘      └───────────────┘
```

## Module Breakdown

### Module 1: Process Pipe Manager
**Purpose**: Generic wrapper for managing long-running processes with stdin/stdout communication.

**Files**:
- `lib/src/process/process_pipe.dart`
- `test/process/process_pipe_test.dart`

**Interface**:
```dart
abstract class ProcessPipe {
  Future<void> start();
  Future<String> send(String input);
  Future<void> stop();
  bool get isRunning;
  Stream<String> get outputStream;
}
```

**Tests**:
- [ ] Can start a simple process (e.g., `cat`)
- [ ] Can send input and receive output
- [ ] Can handle process restart
- [ ] Can detect process termination
- [ ] Properly cleans up on stop
- [ ] Handles timeout scenarios
- [ ] Handles process errors gracefully

---

### Module 2: Whisper Process Wrapper
**Purpose**: Wrap whisper.cpp for speech-to-text via process pipe.

**Details**:
whisper.cpp lives in /Users/shorn/dev.c/whisper.cpp and has its cli built in /Users/shorn/dev.c/whisper.cpp/build/bin/whisper-cli


**Files**:
- `lib/src/stt/whisper_process.dart`
- `test/stt/whisper_process_test.dart`

**Interface**:
```dart
class WhisperProcess {
  WhisperProcess({required String modelPath, required String executablePath});
  Future<void> initialize();
  Future<String> transcribe(Uint8List audioData);
  Future<String> transcribeFile(String filePath);
  Future<void> dispose();
}
```

**Tests**:
- [ ] Can initialize with valid model path
- [ ] Fails gracefully with invalid model path
- [ ] Can transcribe a known audio file
- [ ] Returns empty string for silence
- [ ] Handles concurrent transcription requests
- [ ] Properly disposes resources

---

### Module 3: Llama Process Wrapper
**Purpose**: Wrap llama.cpp for text generation via process pipe with context management.

**Details**:
llama.cpp cli was installed by brew and lives in /opt/homebrew/bin/llama-cli, it can be call with llama-cli and the llm ggml-org/gemma-3-1b-it-GGUF. A sample of using it this way from bash is below, we will do this with dart:

```bash
# Create a named pipe
mkfifo /tmp/llm_input

# Run llama-cli reading from the pipe (in background or another terminal)
llama-cli -hf ggml-org/gemma-3-1b-it-GGUF -cnv -p - < /tmp/llm_input &

# Send messages to it
echo "Hello, who are you?" > /tmp/llm_input
echo "What can you help me with?" > /tmp/llm_input

# Clean up when done
rm /tmp/llm_input
```


**Files**:
- `lib/src/llm/llama_process.dart`
- `test/llm/llama_process_test.dart`

**Interface**:
```dart
class LlamaProcess {
  LlamaProcess({required String modelPath, required String executablePath});
  Future<void> initialize();
  Future<String> generate(String prompt, {int maxTokens = 256});
  Future<String> chat(String userMessage, List<ChatMessage> history);
  void clearContext();
  Future<void> dispose();
}

class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
}
```

**Tests**:
- [ ] Can initialize with valid model path
- [ ] Fails gracefully with invalid model path
- [ ] Can generate response to simple prompt
- [ ] Maintains context across multiple calls
- [ ] Can clear context
- [ ] Handles long responses (streaming)
- [ ] Respects max token limit
- [ ] Properly disposes resources

---

### Module 4: Audio Input Manager
**Purpose**: Capture audio from microphone with configurable sample rate and format.

**Details**: Use the rec command from sox for recording audio. 

**Files**:
- `lib/src/audio/audio_input.dart`
- `test/audio/audio_input_test.dart`

**Interface**:
```dart
class AudioInput {
  AudioInput({int sampleRate = 16000, int channels = 1});
  Future<void> initialize();
  Stream<Uint8List> get audioStream;
  Future<void> startRecording();
  Future<Uint8List> stopRecording();
  Future<void> dispose();
}
```

**Tests**:
- [ ] Can initialize audio input
- [ ] Can list available devices
- [ ] Can start/stop recording
- [ ] Audio stream emits data while recording
- [ ] Returns accumulated audio on stop
- [ ] Handles device disconnection
- [ ] Properly disposes resources

---

### Module 5: Wake Word Detector
**Purpose**: Detect wake word using sherpa_onnx keyword spotter.

**Files**:
- `lib/src/wakeword/wake_word_detector.dart`
- `test/wakeword/wake_word_detector_test.dart`

**Interface**:
```dart
class WakeWordDetector {
  WakeWordDetector({required String modelPath, List<String> keywords});
  Future<void> initialize();
  void processAudio(Uint8List audioChunk);
  Stream<WakeWordEvent> get detections;
  Future<void> dispose();
}

class WakeWordEvent {
  final String keyword;
  final double confidence;
  final DateTime timestamp;
}
```

**Tests**:
- [ ] Can initialize with valid model
- [ ] Detects configured wake word
- [ ] Does not false-trigger on similar words
- [ ] Provides confidence scores
- [ ] Works with streaming audio
- [ ] Properly disposes resources

---

### Module 6: Voice Activity Detector (Silence Detection)
**Purpose**: Detect when user stops speaking to know when to process audio.

**Files**:
- `lib/src/vad/voice_activity_detector.dart`
- `test/vad/voice_activity_detector_test.dart`

**Interface**:
```dart
class VoiceActivityDetector {
  VoiceActivityDetector({
    double silenceThreshold = 0.01,
    Duration silenceDuration = const Duration(milliseconds: 800),
  });
  
  void processAudio(Uint8List audioChunk);
  Stream<VADEvent> get events;
  void reset();
}

enum VADState { silence, speech }

class VADEvent {
  final VADState state;
  final DateTime timestamp;
}
```

**Tests**:
- [ ] Detects speech onset
- [ ] Detects silence after speech
- [ ] Respects silence duration threshold
- [ ] Handles varying volume levels
- [ ] Can adjust sensitivity
- [ ] Resets state correctly

---

### Module 7: TTS Manager
**Purpose**: Convert text to speech using sherpa_onnx TTS.

**Details**: The model for sherpa_onnx tts is in ./models/tts in model.onnx, tokens.txt and in the espeak-ng-data directory. 

**Files**:
- `lib/src/tts/tts_manager.dart`
- `test/tts/tts_manager_test.dart`

**Interface**:
```dart
class TTSManager {
  TTSManager({required String modelPath});
  Future<void> initialize();
  Future<Uint8List> synthesize(String text);
  Future<void> speak(String text); // Synthesize and play
  Future<void> stop();
  Future<void> dispose();
}
```

**Tests**:
- [ ] Can initialize with valid model
- [ ] Synthesizes text to audio bytes
- [ ] Handles empty string
- [ ] Handles long text (chunking if needed)
- [ ] Can stop playback mid-speech
- [ ] Properly disposes resources

---

### Module 8: Audio Output Manager
**Purpose**: Play audio through speakers.

**Details**:Use the play command from sox for playing back audio. 

**Files**:
- `lib/src/audio/audio_output.dart`
- `test/audio/audio_output_test.dart`

**Interface**:
```dart
class AudioOutput {
  AudioOutput({int sampleRate = 22050});
  Future<void> initialize();
  Future<void> play(Uint8List audioData);
  Future<void> stop();
  bool get isPlaying;
  Future<void> dispose();
}
```

**Tests**:
- [ ] Can initialize audio output
- [ ] Can play audio data
- [ ] Can stop playback
- [ ] Handles queue of audio chunks
- [ ] Properly disposes resources

---

### Module 9: Conversation Context Manager
**Purpose**: Maintain conversation history and format for LLM.

**Files**:
- `lib/src/context/conversation_context.dart`
- `test/context/conversation_context_test.dart`

**Interface**:
```dart
class ConversationContext {
  ConversationContext({String? systemPrompt, int maxHistoryLength = 10});
  
  void addUserMessage(String content);
  void addAssistantMessage(String content);
  List<ChatMessage> getHistory();
  String formatForLlama();
  void clear();
  void setSystemPrompt(String prompt);
}
```

**Tests**:
- [ ] Adds messages correctly
- [ ] Maintains order
- [ ] Respects max history length (FIFO)
- [ ] Formats correctly for llama.cpp
- [ ] Clears history
- [ ] Includes system prompt in format

---

### Module 10: Voice Assistant Orchestrator
**Purpose**: Main controller that coordinates all modules.

**Files**:
- `lib/src/voice_assistant.dart`
- `test/voice_assistant_test.dart`

**Interface**:
```dart
class VoiceAssistant {
  VoiceAssistant({required VoiceAssistantConfig config});
  
  Future<void> initialize();
  Future<void> start();
  Future<void> stop();
  Stream<AssistantState> get stateStream;
  Stream<String> get transcriptionStream;
  Stream<String> get responseStream;
  Future<void> dispose();
}

enum AssistantState {
  idle,
  listeningForWakeWord,
  listening,
  processing,
  speaking,
  error,
}

class VoiceAssistantConfig {
  final String whisperModelPath;
  final String whisperExecutablePath;
  final String llamaModelPath;
  final String llamaExecutablePath;
  final String wakeWordModelPath;
  final String ttsModelPath;
  final String wakeWord;
  final String? systemPrompt;
}
```

**Tests**:
- [ ] Initializes all modules
- [ ] Transitions through states correctly
- [ ] Handles wake word → listening → processing → speaking cycle
- [ ] Maintains conversation context
- [ ] Can be stopped and restarted
- [ ] Handles errors gracefully
- [ ] Properly disposes all resources

---

## Development Phases

### Phase 1: Foundation (Modules 1-3)
**Goal**: Establish process communication with whisper.cpp and llama.cpp

1. **Module 1**: Process Pipe Manager
   - Start with simple echo test using `cat`
   - Add timeout and error handling
   
2. **Module 2**: Whisper Process Wrapper
   - Test with pre-recorded audio files
   - Validate transcription accuracy
   
3. **Module 3**: Llama Process Wrapper
   - Test with simple prompts
   - Validate context maintenance

**Milestone**: Can transcribe audio file and get LLM response via CLI test

---

### Phase 2: Audio I/O (Modules 4, 8)
**Goal**: Capture and play audio

4. **Module 4**: Audio Input Manager
   - Test microphone capture
   - Validate audio format (16kHz, mono, 16-bit)
   
5. **Module 8**: Audio Output Manager
   - Test speaker playback
   - Validate audio format handling

**Milestone**: Can record and playback audio

---

### Phase 3: Detection (Modules 5-6)
**Goal**: Wake word and silence detection

6. **Module 5**: Wake Word Detector
   - Integrate sherpa_onnx keyword spotter
   - Test with configured wake word
   
7. **Module 6**: Voice Activity Detector
   - Implement energy-based VAD
   - Test silence detection timing

**Milestone**: Can detect wake word and silence in audio stream

---

### Phase 4: Speech Synthesis (Module 7)
**Goal**: Text-to-speech output

8. **Module 7**: TTS Manager
   - Integrate sherpa_onnx TTS
   - Test synthesis quality

**Milestone**: Can speak generated text

---

### Phase 5: Context & Integration (Modules 9-10)
**Goal**: Full conversation loop

9. **Module 9**: Conversation Context Manager
   - Test context formatting
   - Test history management
   
10. **Module 10**: Voice Assistant Orchestrator
    - Integrate all modules
    - Test full conversation flow

**Milestone**: Complete voice assistant working end-to-end

---

## Testing Strategy

### Unit Tests
- Each module has isolated unit tests
- Mock dependencies where appropriate
- Use test fixtures (pre-recorded audio, etc.)

### Integration Tests
- Test module pairs (e.g., AudioInput → Whisper)
- Test full pipeline with recorded audio
- Test error recovery scenarios

### Manual Testing
- Live microphone testing
- Subjective quality assessment
- Latency measurement

### Test Fixtures Needed
- `test/fixtures/audio/` - Sample audio files
  - `wake_word.wav` - Recording of wake word
  - `short_phrase.wav` - Short test phrase
  - `silence.wav` - Pure silence
  - `noise.wav` - Background noise
- `test/fixtures/models/` - Test models (or mocks)

---

## Dependencies

### Dart Packages
```yaml
dependencies:
  sherpa_onnx: ^latest  # Wake word, VAD, TTS
  path: ^latest
  async: ^latest

dev_dependencies:
  test: ^latest
  mocktail: ^latest
```

### External Binaries
- `whisper.cpp` - Compiled with main example
- `llama.cpp` - Compiled with main example
- Model files for each

---

## Configuration

### Environment Variables
```bash
WHISPER_MODEL_PATH=/path/to/whisper/model.bin
WHISPER_EXECUTABLE=/path/to/whisper/main
LLAMA_MODEL_PATH=/path/to/llama/model.gguf
LLAMA_EXECUTABLE=/path/to/llama/main
WAKEWORD_MODEL_PATH=/path/to/sherpa/keyword/model
TTS_MODEL_PATH=/path/to/sherpa/tts/model
```

### Config File (Optional)
```yaml
# config.yaml
wake_word: "hey assistant"
silence_threshold: 0.01
silence_duration_ms: 800
max_response_tokens: 256
system_prompt: "You are a helpful voice assistant. Keep responses concise."
```

---

## File Structure

```
voice_assistant/
├── PLAN.md
├── CLAUDE.md
├── pubspec.yaml
├── lib/
│   ├── voice_assistant.dart          # Main export
│   └── src/
│       ├── process/
│       │   └── process_pipe.dart
│       ├── stt/
│       │   └── whisper_process.dart
│       ├── llm/
│       │   └── llama_process.dart
│       ├── audio/
│       │   ├── audio_input.dart
│       │   └── audio_output.dart
│       ├── wakeword/
│       │   └── wake_word_detector.dart
│       ├── vad/
│       │   └── voice_activity_detector.dart
│       ├── tts/
│       │   └── tts_manager.dart
│       ├── context/
│       │   └── conversation_context.dart
│       └── voice_assistant.dart
├── test/
│   ├── process/
│   │   └── process_pipe_test.dart
│   ├── stt/
│   │   └── whisper_process_test.dart
│   ├── llm/
│   │   └── llama_process_test.dart
│   ├── audio/
│   │   ├── audio_input_test.dart
│   │   └── audio_output_test.dart
│   ├── wakeword/
│   │   └── wake_word_detector_test.dart
│   ├── vad/
│   │   └── voice_activity_detector_test.dart
│   ├── tts/
│   │   └── tts_manager_test.dart
│   ├── context/
│   │   └── conversation_context_test.dart
│   ├── voice_assistant_test.dart
│   └── fixtures/
│       ├── audio/
│       └── models/
└── bin/
    └── main.dart                      # CLI entry point
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| sherpa_onnx Dart bindings issues | Have fallback to process-based approach |
| Audio latency too high | Profile and optimize, consider buffering strategies |
| Model loading slow | Load models at startup, keep processes warm |
| Context grows too large | Implement context summarization or sliding window |
| Wake word false positives | Tune threshold, add confirmation phrase option |

---

## Success Criteria

1. **Wake word detection**: < 500ms response time, < 5% false positive rate
2. **Transcription**: > 90% accuracy on clear speech
3. **Response generation**: < 3s for typical response
4. **TTS**: Natural sounding, < 500ms latency to first audio
5. **Full loop**: < 5s from end of speech to start of response audio
6. **Stability**: Can run for 1+ hour without crashes or memory leaks
