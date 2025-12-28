## 1.0.6

- Fix audio buffering during follow-up state (prevents empty transcriptions)
- Improve sentence processing for faster TTS streaming:
  - Break on newlines for multi-line responses
  - Break on clause separators (; : — –)
  - Force break at 20 words max to prevent long pauses
- Enable Metal GPU acceleration for llama-cli (-ngl 99)
- Add VAD unit tests for follow-up listening scenarios

## 1.0.5

- Generate tuned keywords.txt on fresh install
- Add JARVIS phonetic variants for better wake word detection
- Always regenerate keywords.txt on setup to apply latest tuning
- Clean up Python venv after adding ONNX metadata (saves ~50MB)
- Generate acknowledgment audio during setup using Dart sherpa_onnx (no Python required)
- Auto-resolve audio assets from ~/.jarvis/assets when running globally
- Add timing instrumentation for performance analysis (--debug flag)
- Pipeline TTS synthesis with playback for smoother multi-sentence responses
- Generate complete config.yaml with all settings during setup
- Use isolate-based TTS for true parallel synthesis (~27% speedup)
- Add whisper-server support to keep whisper model warm between calls
- Stream LLM output to TTS for faster time-to-first-audio (reduced from 3-5s to ~1s)

## 1.0.4

- Add ONNX metadata step to TTS model setup
- Create Python venv automatically for onnx package
- Add sherpa-onnx required metadata (model_type, language, voice, sample_rate)
- Require Python 3.8+ with clear error messages

## 1.0.3

- Auto-detect whisper-cli and llama-cli executables
- Search common locations: /opt/homebrew/bin, /usr/local/bin, PATH
- Try multiple executable names (whisper-cli, whisper, llama-cli, llama)
- Show dynamic "Next steps" based on detected tools

## 1.0.2

- Fix platform-specific sherpa library detection
- Detect correct platform: macOS, Linux, or Windows
- Find sherpa_onnx_macos, sherpa_onnx_linux, or sherpa_onnx_windows
- Select latest version when multiple versions installed

## 1.0.1

- Add whisper model download to `jarvis setup`
- Download ggml-base.en.bin (~142MB) from HuggingFace
- Store in ~/.jarvis/models/whisper/
- Auto-configure whisper_model_path in generated config

## 1.0.0

- Initial release
- Global CLI install via `dart pub global activate jarvis_dart`
- `jarvis setup` command for first-time model download
- Wake word detection using sherpa-onnx
- Speech-to-text using whisper.cpp
- LLM responses using llama.cpp
- Text-to-speech using sherpa-onnx VITS
- Conversation memory across turns
- Barge-in support (interrupt while speaking)
- Follow-up listening without wake word
- Session recording for debugging
- Cross-platform audio player support (afplay, play, mpv, ffplay, aplay)
