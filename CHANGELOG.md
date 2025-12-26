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
