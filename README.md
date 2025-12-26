# JARVIS

A Dart-based voice assistant inspired by JARVIS from Iron Man. Say "JARVIS" to wake it up, speak naturally, and get intelligent spoken responses.

## Features

- **Wake Word Detection** - Always listening for "JARVIS" using sherpa_onnx
- **Speech-to-Text** - Transcribes speech using whisper.cpp
- **LLM Responses** - Generates contextual responses using llama.cpp
- **Text-to-Speech** - Natural speech synthesis using sherpa_onnx VITS
- **Conversation Memory** - Maintains context across conversation turns
- **Barge-in Support** - Interrupt JARVIS by saying the wake word while it's speaking
- **Follow-up Listening** - Responds to follow-up questions without needing the wake word
- **Session Recording** - Record sessions for debugging and analysis
- **Audio Acknowledgments** - Plays audio feedback when activated

## Quick Start

```bash
# Clone and install
git clone https://github.com/yourusername/jarvis.git
cd jarvis
dart pub get

# Configure (edit paths to your models)
cp config.yaml.example config.yaml
vim config.yaml

# Run
dart run bin/jarvis.dart --config config.yaml
```

## Requirements

### System Dependencies

#### Dart SDK

| Platform | Installation |
|----------|--------------|
| macOS | `brew install dart` |
| Linux | See [Dart install docs](https://dart.dev/get-dart) |
| Windows | `choco install dart-sdk` or `winget install Dart.Dart-SDK` |

#### Sox (Audio Recording)

| Platform | Installation |
|----------|--------------|
| macOS | `brew install sox` |
| Ubuntu/Debian | `sudo apt install sox` |
| Fedora | `sudo dnf install sox` |
| Arch | `sudo pacman -S sox` |
| Windows | Download from [SourceForge](https://sourceforge.net/projects/sox/) |

#### whisper.cpp (Speech-to-Text)

Build from source on all platforms:

```bash
git clone https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
cmake -B build
cmake --build build --config Release

# Download a model
./models/download-ggml-model.sh base.en
```

The executable will be at `build/bin/whisper-cli` (or `build/bin/Release/whisper-cli.exe` on Windows).

#### llama.cpp (LLM Inference)

| Platform | Installation |
|----------|--------------|
| macOS | `brew install llama.cpp` |
| Linux/Windows | Build from source (see below) |

**Build from source:**

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build
cmake --build build --config Release
```

The executable will be at `build/bin/llama-cli` (or `build/bin/Release/llama-cli.exe` on Windows).

#### Platform-Specific Notes

**macOS**: Uses `afplay` for audio playback (built-in).

**Linux**: Requires a command-line audio player. Install one of:
- `sudo apt install sox` (uses `play` command)
- `sudo apt install ffmpeg` (uses `ffplay`)
- `sudo apt install mpv`

**Windows**: Audio playback uses PowerShell's built-in capabilities.

### Models Required

- **Whisper** - Speech recognition model (e.g., `ggml-base.en.bin`)
- **LLM** - Language model (e.g., `gemma-3-1b-it` from Hugging Face)
- **Wake Word** - sherpa_onnx keyword spotter model
- **TTS** - sherpa_onnx VITS model with espeak-ng data

### Model Setup

Scripts are provided to download the required models:

```bash
# Download and setup TTS model (JARVIS voice)
cd models/tts
./get_model.sh
cd ../..

# Download wake word detection model
cd models/kws
./get_model.sh
cd ../..
```

The TTS script downloads:
- JARVIS voice model from HuggingFace (piper format)
- Converts to sherpa-onnx format with metadata
- espeak-ng phoneme data

**Note**: The convert script requires Python with the `onnx` package:
```bash
pip install onnx
```

## Configuration

Create `config.yaml` with your model paths:

```yaml
# Speech-to-Text (Whisper)
whisper_model_path: /path/to/ggml-base.en.bin
whisper_executable: /path/to/whisper-cli

# LLM (Llama)
llama_model_repo: ggml-org/gemma-3-1b-it-GGUF
llama_executable: /opt/homebrew/bin/llama-cli

# Wake Word Detection
wakeword_encoder_path: ./models/kws/encoder.onnx
wakeword_decoder_path: ./models/kws/decoder.onnx
wakeword_joiner_path: ./models/kws/joiner.onnx
wakeword_tokens_path: ./models/kws/tokens.txt
wakeword_keywords_file: ./models/kws/keywords.txt

# Text-to-Speech
tts_model_path: ./models/tts/jarvis-high.onnx
tts_tokens_path: ./models/tts/tokens.txt
tts_data_dir: ./models/tts/espeak-ng-data

# Sherpa Native Library
sherpa_lib_path: ~/.pub-cache/hosted/pub.dev/sherpa_onnx_macos-1.12.20/macos

# Audio Feedback
acknowledgment_dir: ./assets/acknowledgments
barge_in_dir: ./assets/bargein

# Behavior Settings
system_prompt: |
  You are JARVIS, a helpful AI assistant.
  Keep responses concise for spoken delivery.

silence_threshold: 0.01
silence_duration_ms: 800
max_history_length: 10
sentence_pause_ms: 200

# Follow-up Listening
enable_follow_up: true
follow_up_timeout_ms: 4000
statement_follow_up_timeout_ms: 4000

# Barge-in
enable_barge_in: true

# Audio Playback (optional - auto-detects if not specified)
audio_player: auto           # auto, afplay, play, mpv, ffplay, aplay
audio_player_path: /usr/bin/afplay  # optional custom path
```

### Audio Player Options

| Player | Platforms | Notes |
|--------|-----------|-------|
| `auto` | All | Auto-detect best available (default) |
| `afplay` | macOS | Built-in CoreAudio player |
| `play` | All | Sox audio player |
| `mpv` | All | Multimedia player |
| `ffplay` | All | FFmpeg player |
| `aplay` | Linux | ALSA player |

## Usage

```bash
# Basic usage
dart run bin/jarvis.dart --config config.yaml

# With debug logging
dart run bin/jarvis.dart --config config.yaml --debug

# Record session for debugging
dart run bin/jarvis.dart --config config.yaml --record

# Record to custom directory
dart run bin/jarvis.dart --config config.yaml --record-dir ./my-sessions
```

### CLI Options

| Option | Description |
|--------|-------------|
| `-c, --config <path>` | Path to YAML config file |
| `-v, --verbose` | Enable INFO level logging |
| `-d, --debug` | Enable DEBUG level logging |
| `--trace` | Enable TRACE level logging |
| `-q, --quiet` | Suppress all logging |
| `--record` | Enable session recording |
| `--record-dir <path>` | Custom session directory |
| `-h, --help` | Show help message |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      VoiceAssistant                          │
│                    (Main Orchestrator)                       │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  AudioInput   │    │ Conversation  │    │  AudioOutput  │
│   (sox rec)   │    │    Context    │    │   (afplay)    │
└───────────────┘    └───────────────┘    └───────────────┘
        │                                          ▲
        ▼                                          │
┌───────────────┐                        ┌───────────────┐
│   WakeWord    │                        │      TTS      │
│   Detector    │                        │   (sherpa)    │
└───────────────┘                        └───────────────┘
        │                                          ▲
        ▼                                          │
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│     VAD       │───►│    Whisper    │───►│     Llama     │
│   (Silence)   │    │   (STT)       │    │    (LLM)      │
└───────────────┘    └───────────────┘    └───────────────┘
```

## Tools

Utility scripts in `tool/`:

```bash
# Generate acknowledgment audio files
dart run tool/generate_acknowledgments.dart

# Generate barge-in audio files
dart run tool/generate_bargein.dart

# Regenerate a single acknowledgment
dart run tool/regenerate_ack.dart 8 "System active."

# Replay a recorded session
dart run tool/replay_session.dart ./sessions/session_* --verbose
dart run tool/replay_session.dart ./sessions/session_* --transcribe
```

## Project Structure

```
jarvis/
├── bin/
│   └── jarvis.dart              # CLI entry point
├── lib/src/
│   ├── audio/
│   │   ├── audio_input.dart     # Microphone capture
│   │   ├── audio_output.dart    # Audio playback
│   │   └── acknowledgment_player.dart
│   ├── cli/
│   │   └── config_loader.dart   # Configuration parsing
│   ├── context/
│   │   └── conversation_context.dart
│   ├── llm/
│   │   └── llama_process.dart   # LLM integration
│   ├── process/
│   │   └── process_pipe.dart    # Process communication
│   ├── recording/
│   │   ├── session_event.dart   # Event types
│   │   ├── session_recorder.dart
│   │   └── wav_writer.dart
│   ├── stt/
│   │   └── whisper_process.dart # Speech-to-text
│   ├── tts/
│   │   ├── tts_manager.dart     # Text-to-speech
│   │   └── text_processor.dart  # Response cleaning
│   ├── vad/
│   │   └── voice_activity_detector.dart
│   ├── wakeword/
│   │   └── wake_word_detector.dart
│   ├── logging.dart
│   └── voice_assistant.dart     # Main orchestrator
├── models/
│   ├── kws/
│   │   └── get_model.sh         # Download wake word model
│   └── tts/
│       ├── get_model.sh         # Download TTS model
│       └── convert.py           # Convert to sherpa format
├── test/                        # 277 tests
├── tool/                        # Utility scripts
├── assets/
│   ├── acknowledgments/         # Wake word audio
│   └── bargein/                 # Barge-in audio
└── config.yaml                  # Configuration
```

## Development

```bash
# Run all tests
dart test

# Run specific test
dart test test/voice_assistant_test.dart

# Format code
dart format lib test

# Analyze code
dart analyze
```

## Session Recording

When running with `--record`, sessions are saved to `./sessions/`:

```
sessions/
└── session_2024-01-15_10-30-45/
    ├── session.jsonl           # Event log
    └── audio/
        ├── 001_user.wav        # User utterances
        ├── 002_user.wav
        └── ...
```

Event types in JSONL:
- `session_start` - Config and metadata
- `wake_word` - Wake word detection
- `user_audio` - User speech recording
- `transcription` - STT result
- `response` - LLM response
- `barge_in` - User interruption
- `session_end` - Session summary

## License

MIT License - see [LICENSE](LICENSE)

### Third-Party Licenses

| Component | License |
|-----------|---------|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | MIT |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | MIT |
| [sherpa_onnx](https://pub.dev/packages/sherpa_onnx) | Apache-2.0 |
| [yaml](https://pub.dev/packages/yaml) | MIT |
| [logging](https://pub.dev/packages/logging) | BSD-3-Clause |
