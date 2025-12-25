# JARVIS Voice Assistant - Development Plan

## Project Status: Feature Complete

All core features implemented and tested. Ready for use.

---

## Phase 1: Core Modules ✅ COMPLETE

All foundational modules implemented with TDD:

| Module | Status | Description |
|--------|--------|-------------|
| ProcessPipe | ✅ | Generic process communication wrapper |
| WhisperProcess | ✅ | Speech-to-text via whisper.cpp |
| LlamaProcess | ✅ | LLM responses via llama.cpp |
| AudioInput | ✅ | Microphone capture via sox rec |
| AudioOutput | ✅ | Audio playback via afplay |
| WakeWordDetector | ✅ | "JARVIS" keyword detection via sherpa_onnx |
| VoiceActivityDetector | ✅ | Silence detection for utterance boundaries |
| TtsManager | ✅ | Text-to-speech via sherpa_onnx VITS |
| TextProcessor | ✅ | Response cleaning and sentence splitting |
| ConversationContext | ✅ | Multi-turn conversation history |
| VoiceAssistant | ✅ | Main orchestrator with state machine |
| ConfigLoader | ✅ | YAML and environment variable config |
| AcknowledgmentPlayer | ✅ | Audio feedback on wake word |

---

## Phase 2: Conversational Enhancements ✅ COMPLETE

### Barge-in Detection ✅
- User can interrupt JARVIS by saying wake word while speaking
- Audio playback stops immediately
- Barge-in audio acknowledgment plays ("Sir?", "Yes?", etc.)
- Transitions to listening state for new input

### Follow-up Listening ✅
- After JARVIS responds, listens for follow-up without wake word
- Configurable timeout (default 4 seconds)
- Questions trigger prompt retry on timeout
- Statements allow silent timeout

### Question Detection ✅
- Detects sentences ending with "?"
- Extracts last question for prompt retry
- Integrates with follow-up listening

### State Machine

```
listeningForWakeWord ──(wake word)──► listening
         ▲                              │
         │                    (silence detected)
         │                              ▼
         │                         processing
         │                              │
         │                   (response ready)
         │                              ▼
         └──(timeout)────── speaking ◄──┘
                    │           │
          (question)│           │(wake word = barge-in)
                    ▼           ▼
           awaitingFollowUp   listening
                    │
          (timeout) │
                    ▼
               prompting ──(timeout)──► listeningForWakeWord
```

---

## Phase 3: Session Recording ✅ COMPLETE

Debug and integration testing support:

- `--record` CLI flag enables session recording
- Captures user audio as WAV files
- JSONL event log (wake word, transcription, response, barge-in)
- Session replay tool for debugging
- Barge-in position tracking by sentence index

---

## Phase 4: Audio Improvements ✅ COMPLETE

- Barge-in audio acknowledgments (5 phrases)
- Updated acknowledgment audio ("System active.")
- Audio generation tools for TTS assets

---

## Test Coverage

- **277 tests** across 18 test files
- Unit tests for all modules
- Integration tests for session replay
- TDD workflow followed throughout

---

## Future Enhancements

Potential improvements for future development:

### Performance
- [ ] Streaming STT for lower latency
- [ ] GPU acceleration for TTS
- [ ] Audio buffer optimization

### Features
- [ ] Multiple wake word support
- [ ] Voice identification (multi-user)
- [ ] Plugin/skill system
- [ ] Web interface for monitoring

### Quality
- [ ] Echo cancellation for speaker feedback
- [ ] Noise reduction preprocessing
- [ ] Adaptive silence thresholds

### Integration
- [ ] Home automation APIs
- [ ] Calendar/reminder integration
- [ ] Music/media playback control
