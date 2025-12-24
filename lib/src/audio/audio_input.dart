import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Exception thrown by AudioInput operations.
class AudioInputException implements Exception {
  final String message;
  final Object? cause;

  AudioInputException(this.message, [this.cause]);

  @override
  String toString() =>
      'AudioInputException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Captures audio from microphone using sox rec command.
class AudioInput {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final String executablePath;

  bool _initialized = false;
  bool _disposed = false;
  bool _isRecording = false;
  Process? _recProcess;
  final _audioController = StreamController<Uint8List>.broadcast();
  final _audioBuffer = BytesBuilder();
  StreamSubscription<List<int>>? _stdoutSubscription;

  AudioInput({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.executablePath = '/opt/homebrew/bin/rec',
  });

  /// Whether currently recording.
  bool get isRecording => _isRecording;

  /// Stream of audio data chunks while recording.
  Stream<Uint8List> get audioStream => _audioController.stream;

  /// Initializes the audio input by verifying rec command exists.
  Future<void> initialize() async {
    if (_disposed) {
      throw AudioInputException('AudioInput has been disposed');
    }

    // Check rec executable exists
    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw AudioInputException('rec executable not found at: $executablePath');
    }

    _initialized = true;
  }

  /// Starts recording audio from the microphone.
  Future<void> startRecording() async {
    if (_disposed) {
      throw AudioInputException('AudioInput has been disposed');
    }
    if (!_initialized) {
      throw AudioInputException('AudioInput not initialized');
    }
    if (_isRecording) {
      throw AudioInputException('Already recording');
    }

    _audioBuffer.clear();

    try {
      // rec command to capture raw audio to stdout
      // Format: rec -t raw -b 16 -e signed -r 16000 -c 1 -
      _recProcess = await Process.start(executablePath, [
        '-q', // Quiet mode (no progress)
        '-t', 'raw', // Output raw audio
        '-b', bitsPerSample.toString(), // Bits per sample
        '-e', 'signed', // Signed encoding
        '-r', sampleRate.toString(), // Sample rate
        '-c', channels.toString(), // Channels
        '-', // Output to stdout
      ]);

      _isRecording = true;

      // Listen to stdout for audio data
      _stdoutSubscription = _recProcess!.stdout.listen(
        (data) {
          final audioData = Uint8List.fromList(data);
          _audioBuffer.add(audioData);
          _audioController.add(audioData);
        },
        onError: (Object error) {
          _audioController.addError(
            AudioInputException('Error reading audio data', error),
          );
        },
        onDone: () {
          _isRecording = false;
        },
      );

      // Also capture stderr for debugging
      _recProcess!.stderr.listen((data) {
        // Ignore stderr for now, rec may output informational messages
      });
    } on ProcessException catch (e) {
      _isRecording = false;
      throw AudioInputException('Failed to start recording', e);
    }
  }

  /// Stops recording and returns the accumulated audio data.
  Future<Uint8List> stopRecording() async {
    if (_disposed) {
      throw AudioInputException('AudioInput has been disposed');
    }
    if (!_isRecording) {
      throw AudioInputException('Not currently recording');
    }

    // Send SIGTERM to stop rec gracefully
    _recProcess?.kill(ProcessSignal.sigterm);

    // Wait a bit for process to finish
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Cancel subscription
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    _isRecording = false;
    _recProcess = null;

    // Return accumulated audio data
    return _audioBuffer.toBytes();
  }

  /// Disposes of resources.
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }

    await _audioController.close();
    _disposed = true;
    _initialized = false;
  }
}
