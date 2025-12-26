/// JARVIS Voice Assistant library.
///
/// A Dart-based voice assistant that listens for wake words,
/// transcribes speech, generates LLM responses, and speaks them back.
library;

// Main orchestrator
export 'src/voice_assistant.dart';

// Audio modules
export 'src/audio/audio_input.dart';
export 'src/audio/audio_output.dart';

// Speech-to-text
export 'src/stt/whisper_process.dart';

// LLM
export 'src/llm/llama_process.dart';

// Wake word detection
export 'src/wakeword/wake_word_detector.dart';

// Voice activity detection
export 'src/vad/voice_activity_detector.dart';

// Text-to-speech
export 'src/tts/tts_manager.dart';

// Conversation context
export 'src/context/conversation_context.dart';

// CLI utilities
export 'src/cli/config_loader.dart';
