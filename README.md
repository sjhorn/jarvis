# JARVIS

A Dart-based voice assistant inspired by JARVIS from Iron Man. It listens for a wake word, transcribes speech, generates intelligent responses, and speaks them back using text-to-speech.

## Features

- **Wake Word Detection** - Always listening for "JARVIS" using sherpa_onnx
- **Speech-to-Text** - Transcribes user speech using whisper.cpp
- **LLM Responses** - Generates contextual responses using llama.cpp
- **Text-to-Speech** - Speaks responses naturally using sherpa_onnx VITS
- **Conversation Context** - Maintains history across conversation turns
- **Acknowledgment Audio** - Plays audio feedback when wake word is detected
- **Sentence Pacing** - Speaks responses sentence-by-sentence for natural delivery

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
│   (sox rec)   │      │    Context    │      │   (sox play)  │
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

## Requirements

### External Dependencies

- **sox** - Audio recording and playback (`brew install sox`)
- **whisper.cpp** - Speech-to-text ([github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp))
- **llama.cpp** - LLM inference (`brew install llama.cpp` or build from source)

### Models Required

- Whisper model (e.g., `ggml-base.en.bin`)
- LLM model (e.g., via `ggml-org/gemma-3-1b-it-GGUF`)
- sherpa_onnx wake word model
- sherpa_onnx TTS model (VITS)

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd jarvis

# Install Dart dependencies
dart pub get

# Copy and configure settings
cp config.yaml.example config.yaml
# Edit config.yaml with your model paths
```

## Configuration

Edit `config.yaml` to set your model paths and preferences:

```yaml
# Whisper STT
whisper_model_path: /path/to/whisper/ggml-base.en.bin
whisper_executable: /path/to/whisper-cli

# Llama LLM
llama_executable: /opt/homebrew/bin/llama-cli
llama_model: ggml-org/gemma-3-1b-it-GGUF

# Wake Word
wake_word_model_encoder: ./models/wakeword/encoder.onnx
wake_word_model_decoder: ./models/wakeword/decoder.onnx
wake_word_model_joiner: ./models/wakeword/joiner.onnx
wake_word_model_tokens: ./models/wakeword/tokens.txt
wake_word: JARVIS

# TTS
tts_model_path: ./models/tts/model.onnx
tts_tokens_path: ./models/tts/tokens.txt
tts_data_dir: ./models/tts/espeak-ng-data

# Optional
acknowledgment_dir: ./assets/acknowledgments
system_prompt: "You are JARVIS, a helpful AI assistant..."
silence_threshold: 0.01
silence_duration_ms: 800
sentence_pause_ms: 500
```

## Usage

```bash
# Run with default config
dart run bin/jarvis.dart --config config.yaml

# Run with debug logging
dart run bin/jarvis.dart --config config.yaml --debug

# Run with verbose logging
dart run bin/jarvis.dart --config config.yaml --verbose
```

## Development

This project follows Test-Driven Development (TDD) practices.

```bash
# Run all tests
dart test

# Run specific test file
dart test test/stt/whisper_process_test.dart

# Format code
dart format lib test

# Analyze code
dart analyze
```

## Project Structure

```
jarvis/
├── bin/
│   └── jarvis.dart           # CLI entry point
├── lib/src/
│   ├── audio/
│   │   ├── audio_input.dart
│   │   ├── audio_output.dart
│   │   └── acknowledgment_player.dart
│   ├── cli/
│   │   └── config_loader.dart
│   ├── context/
│   │   └── conversation_context.dart
│   ├── llm/
│   │   └── llama_process.dart
│   ├── stt/
│   │   └── whisper_process.dart
│   ├── tts/
│   │   ├── tts_manager.dart
│   │   └── text_processor.dart
│   ├── vad/
│   │   └── voice_activity_detector.dart
│   ├── wakeword/
│   │   └── wake_word_detector.dart
│   ├── logging.dart
│   └── voice_assistant.dart
├── test/                     # Unit tests
├── models/                   # Model files (not in repo)
├── assets/
│   └── acknowledgments/      # Wake word audio responses
└── config.yaml               # Configuration file
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

This project uses the following open-source dependencies:

| Component | License |
|-----------|---------|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | MIT |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | MIT |
| [sherpa_onnx](https://pub.dev/packages/sherpa_onnx) | Apache-2.0 |
| [yaml](https://pub.dev/packages/yaml) | MIT |
| [mocktail](https://pub.dev/packages/mocktail) | MIT |
| [path](https://pub.dev/packages/path) | BSD-3-Clause |
| [async](https://pub.dev/packages/async) | BSD-3-Clause |
| [logging](https://pub.dev/packages/logging) | BSD-3-Clause |
