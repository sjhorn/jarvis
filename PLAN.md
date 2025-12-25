# Voice Assistant Development Plan

## Current Status

**Phase 1 Complete**: All core modules implemented and tested (see README.md for details).

---

## Phase 2: Conversational Enhancements

### Overview

Add three key conversational features to make JARVIS more natural:

1. **Barge-in Detection** - Allow user to interrupt JARVIS while speaking
2. **Question Detection** - Detect when JARVIS asks a question
3. **Follow-up Listening** - Listen for answer without requiring wake word, with one prompt retry

### New State Machine

```
                                    ┌─────────────────────────────┐
                                    │                             │
                                    ▼                             │
idle → listeningForWakeWord ──────────────────────────────────────┤
              │                                                   │
              │ (wake word)                                       │
              ▼                                                   │
         listening                                                │
              │                                                   │
              │ (silence/VAD)                                     │
              ▼                                                   │
        processing                                                │
              │                                                   │
              │ (LLM response ready)                              │
              ▼                                                   │
         speaking ◄───────────────────────────────────────────────┤
              │         │                                         │
              │         │ (wake word = barge-in)                  │
              │         └──────────► listening                    │
              │                                                   │
              │ (finished speaking)                               │
              ├──────────────────────────────────────────────────►│ (no question)
              │                                                   │
              │ (ends with question)                              │
              ▼                                                   │
    awaitingFollowUp ─────────────────────────────────────────────┤
              │         │                                         │
              │         │ (timeout, no speech)                    │
              │         └──► prompting (repeat question)          │
              │                     │                             │
              │                     │ (finished prompting)        │
              │                     ▼                             │
              │              awaitingFollowUp ───────────────────►│ (2nd timeout)
              │                     │                             │
              │                     │ (speech detected)           │
              │                     └──────────┐                  │
              │                                │                  │
              │ (speech detected)              │                  │
              └────────────► listening ◄───────┘                  │
```

---

### Module 2.1: Question Detection & Follow-up Listening

**Purpose**: After JARVIS speaks, if response ended with a question, wait for user answer without requiring wake word.

**Files**:
- `lib/src/tts/text_processor.dart`
- `lib/src/voice_assistant.dart`
- `test/tts/text_processor_test.dart`
- `test/voice_assistant_test.dart`

**New States**:
- `awaitingFollowUp` - Waiting for user response to a question
- `prompting` - Repeating the question as a prompt

**Interface Changes**:
```dart
// TextProcessor additions
bool endsWithQuestion(String text);
String? extractLastQuestion(List<String> sentences);

// New AssistantState values
enum AssistantState {
  idle,
  listeningForWakeWord,
  listening,
  processing,
  speaking,
  awaitingFollowUp,  // NEW
  prompting,          // NEW
  error,
}
```

**Behavior**:
1. After speaking, check if last sentence was a question
2. If question detected, enter `awaitingFollowUp` state
3. Wait 8 seconds for user speech (no wake word required)
4. If timeout with no speech: enter `prompting`, repeat question
5. Wait another 8 seconds
6. If second timeout: return to `listeningForWakeWord`
7. If speech detected at any point: transition to `listening`

**Tests**:
- [ ] `endsWithQuestion` returns true for "How are you?"
- [ ] `endsWithQuestion` returns false for "Hello there."
- [ ] `extractLastQuestion` returns last question from sentences
- [ ] State transitions to `awaitingFollowUp` when response ends with question
- [ ] Timeout triggers `prompting` state with question repeat
- [ ] Second timeout returns to `listeningForWakeWord`
- [ ] Speech in `awaitingFollowUp` transitions to `listening`

---

### Module 2.2: Barge-in Detection

**Purpose**: Allow user to say wake word while JARVIS is speaking to interrupt.

**Files**:
- `lib/src/audio/audio_output.dart`
- `lib/src/voice_assistant.dart`
- `test/audio/audio_output_test.dart`
- `test/voice_assistant_test.dart`

**Interface Changes**:
```dart
// AudioOutput additions
Future<void> cancel();
bool get isCancelled;
```

**Behavior**:
1. During `speaking` state, continue processing audio for wake word detection
2. If wake word detected while speaking: cancel audio playback
3. Transition immediately to `listening` state
4. Play acknowledgment sound

**Tests**:
- [ ] AudioOutput.cancel() stops playback
- [ ] Wake word during speaking triggers barge-in
- [ ] Barge-in cancels current audio
- [ ] State transitions to listening after barge-in
- [ ] Audio buffer is cleared on barge-in

---

### Module 2.3: Config & Integration

**Files**:
- `lib/src/cli/config_loader.dart`
- `config.yaml`
- `test/cli/config_loader_test.dart`

**New Config Options**:
```yaml
# Follow-up listening
enable_follow_up: true
follow_up_timeout_ms: 8000

# Barge-in
enable_barge_in: true
```

**Tests**:
- [ ] Config loader parses new options
- [ ] Defaults work when options not specified
- [ ] VoiceAssistantConfig includes new fields

---

## Implementation Order

1. **TextProcessor.endsWithQuestion()** - TDD: tests first, then implementation
2. **TextProcessor.extractLastQuestion()** - TDD
3. **New AssistantState values** - Add enum values
4. **awaitingFollowUp state logic** - State transitions and timeout
5. **prompting state logic** - Repeat question and return to awaitingFollowUp
6. **Config additions** - New config options for follow-up
7. **AudioOutput.cancel()** - TDD: cancellation support
8. **Barge-in detection** - Wake word processing during speaking
9. **Config additions** - Barge-in config
10. **Integration testing** - Full flow tests

---

## Success Criteria

1. **Question detection**: Correctly identifies sentences ending with "?"
2. **Follow-up listening**: User can respond to questions without wake word
3. **Prompt retry**: Question repeated once if no response within 8 seconds
4. **Barge-in**: User can interrupt JARVIS by saying wake word
5. **Graceful fallback**: Returns to normal wake word mode after 2nd timeout
6. **Config toggles**: Both features can be enabled/disabled via config

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Wake word false positive during speaking | May need to increase detection threshold during playback |
| Audio feedback loop (speaker → mic) | Test with headphones vs speakers, consider echo cancellation |
| Question detection too simple | Start with "?" detection, can add NLP later if needed |
| Follow-up timeout too long/short | Made configurable (8 seconds default) |
