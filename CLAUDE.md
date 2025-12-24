# CLAUDE.md - Claude Code Instructions

## Project Context

You are developing a Dart-based voice assistant application that will sound and think a bit like JARVIS from Iron Man. Its prompts should note this when we get to that stage with the LLM. When developing we will use **Test-Driven Development (TDD)** with a modular approach, completing and testing each module before moving to the next. We will also leverage git to track our progress in a local repo. 

**Key Technologies**:
- **Dart** as the programming language
- **sherpa_onnx** package for wake word detection and TTS
- **whisper.cpp** via process pipe for speech-to-text
- **llama.cpp** via process pipe for LLM responses
- **sox** using play and rec 
- **mocktail** for mocking in tests

## TDD Workflow

For each module, follow this strict order:

### 1. Write Tests First
```bash
# Create test file before implementation
touch test/[module]/[module]_test.dart
```

Write failing tests that define the expected behavior:
```dart
import 'package:test/test.dart';
import 'package:voice_assistant/src/[module]/[module].dart';

void main() {
  group('[ModuleName]', () {
    test('should [expected behavior]', () {
      // Arrange
      // Act  
      // Assert
      fail('Not implemented yet');
    });
  });
}
```

### 2. Run Tests (They Should Fail)
```bash
dart test test/[module]/[module]_test.dart
```

Confirm tests fail for the right reasons (missing implementation, not syntax errors).

### 3. Implement Minimum Code to Pass
Write only enough code to make the current test pass. Resist adding extra functionality.

### 4. Run Tests (They Should Pass)
```bash
dart test test/[module]/[module]_test.dart
```

### 5. Refactor
Clean up code while keeping tests green. Run tests after each refactor.

### 6. Repeat
Add the next test case and repeat the cycle. Also ensure we git commit here with a meaningful comment to track out progress. 

## Module Development Order

Follow this sequence from PLAN.md:

1. **Process Pipe Manager** (`lib/src/process/process_pipe.dart`)
2. **Whisper Process** (`lib/src/stt/whisper_process.dart`)
3. **Llama Process** (`lib/src/llm/llama_process.dart`)
4. **Audio Input** (`lib/src/audio/audio_input.dart`)
5. **Audio Output** (`lib/src/audio/audio_output.dart`)
6. **Wake Word Detector** (`lib/src/wakeword/wake_word_detector.dart`)
7. **Voice Activity Detector** (`lib/src/vad/voice_activity_detector.dart`)
8. **TTS Manager** (`lib/src/tts/tts_manager.dart`)
9. **Conversation Context** (`lib/src/context/conversation_context.dart`)
10. **Voice Assistant Orchestrator** (`lib/src/voice_assistant.dart`)

**Do not start a new module until all tests pass for the current module.**

## Code Style Guidelines

### File Structure
```dart
// 1. Imports (dart:, package:, relative)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:async/async.dart';

import '../other/file.dart';

// 2. Class documentation
/// Brief description of the class.
/// 
/// Longer description if needed.
class MyClass {
  // 3. Static/const fields
  static const defaultTimeout = Duration(seconds: 30);
  
  // 4. Instance fields
  final String _path;
  Process? _process;
  
  // 5. Constructor
  MyClass({required String path}) : _path = path;
  
  // 6. Public methods
  Future<void> initialize() async { ... }
  
  // 7. Private methods
  void _handleError(Object error) { ... }
}
```

### Naming Conventions
- Classes: `PascalCase`
- Methods/variables: `camelCase`
- Constants: `camelCase` or `SCREAMING_SNAKE_CASE` for truly constant values
- Private members: `_prefixedWithUnderscore`
- Test descriptions: `'should [action] when [condition]'`

### Error Handling
```dart
// Define custom exceptions for each module
class WhisperException implements Exception {
  final String message;
  final Object? cause;
  
  WhisperException(this.message, [this.cause]);
  
  @override
  String toString() => 'WhisperException: $message${cause != null ? ' ($cause)' : ''}';
}

// Use try-catch with specific handling
try {
  await _process.start();
} on ProcessException catch (e) {
  throw WhisperException('Failed to start process', e);
}
```

### Async Patterns
```dart
// Use async/await over .then()
Future<String> transcribe(Uint8List audio) async {
  final result = await _sendToProcess(audio);
  return result;
}

// Use StreamController for event streams
final _eventController = StreamController<Event>.broadcast();
Stream<Event> get events => _eventController.stream;

// Always clean up in dispose
Future<void> dispose() async {
  await _eventController.close();
  await _process?.kill();
}
```

## Testing Patterns

### Basic Test Structure
```dart
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// Mock classes at top of file
class MockProcess extends Mock implements Process {}

void main() {
  // Group by functionality
  group('ProcessPipe', () {
    late ProcessPipe pipe;
    late MockProcess mockProcess;
    
    // Setup before each test
    setUp(() {
      mockProcess = MockProcess();
      pipe = ProcessPipe(process: mockProcess);
    });
    
    // Teardown after each test
    tearDown(() async {
      await pipe.dispose();
    });
    
    // Descriptive test names
    test('should start process successfully', () async {
      // Arrange
      when(() => mockProcess.start()).thenAnswer((_) async {});
      
      // Act
      await pipe.start();
      
      // Assert
      expect(pipe.isRunning, isTrue);
      verify(() => mockProcess.start()).called(1);
    });
    
    test('should throw ProcessException when start fails', () async {
      // Arrange
      when(() => mockProcess.start()).thenThrow(Exception('Failed'));
      
      // Act & Assert
      expect(
        () => pipe.start(),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}
```

### Testing Streams
```dart
test('should emit events when wake word detected', () async {
  // Arrange
  final detector = WakeWordDetector(modelPath: 'test/fixtures/model');
  await detector.initialize();
  
  // Act
  detector.processAudio(wakeWordAudio);
  
  // Assert
  await expectLater(
    detector.detections,
    emits(isA<WakeWordEvent>().having(
      (e) => e.keyword,
      'keyword',
      equals('hey assistant'),
    )),
  );
});
```

### Testing with Fixtures
```dart
// Load test fixtures
late Uint8List testAudio;

setUpAll(() async {
  testAudio = await File('test/fixtures/audio/test_phrase.wav').readAsBytes();
});

test('should transcribe audio file', () async {
  final result = await whisper.transcribe(testAudio);
  expect(result.toLowerCase(), contains('hello'));
});
```

## Process Pipe Communication Protocol

### Whisper.cpp Integration
```bash
# Expected whisper.cpp command
./main -m model.bin -f audio.wav --output-txt

# For streaming (if supported)
./main -m model.bin --stdin --output-txt
```

Design the wrapper to:
1. Write audio to temp file
2. Call whisper.cpp with file path
3. Read output from stdout
4. Clean up temp file

### Llama.cpp Integration
```bash
# Expected llama.cpp command (interactive mode)
./main -m model.gguf -i --prompt "User: Hello\nAssistant:"

# For single response
./main -m model.gguf -p "User: Hello\nAssistant:" -n 256
```

Design the wrapper to:
1. Keep process running in interactive mode
2. Send formatted prompts via stdin
3. Read response until end marker
4. Maintain context within the process

## Common Commands

```bash
# Create new module structure
mkdir -p lib/src/[module] test/[module]

# Run all tests
dart test

# Run specific test file
dart test test/[module]/[module]_test.dart

# Run tests with coverage
dart test --coverage=coverage

# Format code
dart format lib test

# Analyze code
dart analyze

# Get dependencies
dart pub get
```

## Checklist Before Moving to Next Module

- [ ] All planned test cases written and passing
- [ ] Edge cases handled (null, empty, error states)
- [ ] Code formatted (`dart format`)
- [ ] No analyzer warnings (`dart analyze`)
- [ ] Public API documented with doc comments
- [ ] dispose/cleanup methods implemented
- [ ] Error types defined and used consistently

## Debugging Tips

### Process Issues
```dart
// Log process stderr for debugging
_process.stderr.transform(utf8.decoder).listen((line) {
  print('[STDERR] $line');
});
```

### Audio Issues
```dart
// Save audio to file for inspection
await File('debug_audio.wav').writeAsBytes(audioData);
```

### Test Isolation
```dart
// Ensure each test is independent
setUp(() {
  // Fresh instance for each test
  sut = MyClass();
});

tearDown(() async {
  // Clean up completely
  await sut.dispose();
});
```

## Communication Style

When working on this project:

1. **Ask clarifying questions** before implementing if requirements are unclear
2. **Show test code first** before implementation when starting a new feature
3. **Run tests frequently** and share results
4. **Explain trade-offs** when multiple approaches exist
5. **Pause at module boundaries** for user confirmation before proceeding

## Getting Started Command

When the user is ready to begin development:

```bash
# Initialize project
mkdir -p voice_assistant && cd voice_assistant
dart create -t package voice_assistant
cd voice_assistant

# Add dependencies to pubspec.yaml
# Then run:
dart pub get

# Create first test
mkdir -p test/process
touch test/process/process_pipe_test.dart

# Start with Module 1: Process Pipe Manager
```

Begin with the first failing test for ProcessPipe, then iterate through the TDD cycle.
