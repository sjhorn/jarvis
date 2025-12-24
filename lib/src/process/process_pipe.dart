import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Exception thrown by ProcessPipe operations.
class ProcessPipeException implements Exception {
  final String message;
  final Object? cause;

  ProcessPipeException(this.message, [this.cause]);

  @override
  String toString() =>
      'ProcessPipeException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Generic wrapper for managing long-running processes with stdin/stdout communication.
class ProcessPipe {
  final String executable;
  final List<String> arguments;
  final Duration responseTimeout;

  Process? _process;
  final _outputController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  Completer<int>? _exitCodeCompleter;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  ProcessPipe({
    required this.executable,
    this.arguments = const [],
    this.responseTimeout = const Duration(seconds: 30),
  });

  /// Whether the process is currently running.
  bool get isRunning => _process != null;

  /// Stream of stdout output from the process.
  Stream<String> get outputStream => _outputController.stream;

  /// Stream of stderr output from the process.
  Stream<String> get errorStream => _errorController.stream;

  /// Future that completes with the exit code when the process terminates.
  Future<int> get exitCode {
    if (_exitCodeCompleter == null) {
      throw ProcessPipeException('Process has not been started');
    }
    return _exitCodeCompleter!.future;
  }

  /// Starts the process.
  Future<void> start() async {
    if (_process != null) {
      throw ProcessPipeException('Process is already running');
    }

    try {
      _exitCodeCompleter = Completer<int>();

      _process = await Process.start(executable, arguments);

      // Set up stdout listener
      _stdoutSubscription = _process!.stdout
          .transform(utf8.decoder)
          .listen(
            (data) => _outputController.add(data),
            onError: (Object error) => _outputController.addError(error),
          );

      // Set up stderr listener
      _stderrSubscription = _process!.stderr
          .transform(utf8.decoder)
          .listen(
            (data) => _errorController.add(data),
            onError: (Object error) => _errorController.addError(error),
          );

      // Monitor process exit
      _process!.exitCode.then((code) {
        _process = null;
        if (!_exitCodeCompleter!.isCompleted) {
          _exitCodeCompleter!.complete(code);
        }
      });
    } on ProcessException catch (e) {
      _process = null;
      _exitCodeCompleter = null;
      throw ProcessPipeException('Failed to start process: ${e.message}', e);
    }
  }

  /// Sends input to the process and optionally waits for a response.
  Future<String> send(String input, {bool waitForResponse = true}) async {
    if (_process == null) {
      throw ProcessPipeException('Process is not running');
    }

    if (!waitForResponse) {
      _process!.stdin.write(input);
      await _process!.stdin.flush();
      return '';
    }

    final responseBuffer = StringBuffer();
    final completer = Completer<String>();
    StreamSubscription<String>? subscription;

    // Set up timeout
    final timer = Timer(responseTimeout, () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.completeError(
          ProcessPipeException('Response timeout after $responseTimeout'),
        );
      }
    });

    // Listen for response
    subscription = outputStream.listen((data) {
      responseBuffer.write(data);
      // Complete when we have some output (for simple cases)
      // In more complex scenarios, you'd look for specific end markers
      if (data.contains('\n')) {
        if (!completer.isCompleted) {
          timer.cancel();
          completer.complete(responseBuffer.toString());
        }
      }
    });

    // Send the input
    _process!.stdin.write(input);
    await _process!.stdin.flush();

    try {
      final result = await completer.future;
      await subscription.cancel();
      return result;
    } catch (e) {
      await subscription.cancel();
      rethrow;
    }
  }

  /// Sends raw input to the process without waiting for response.
  void sendRaw(String input) {
    if (_process == null) {
      throw ProcessPipeException('Process is not running');
    }
    _process!.stdin.write(input);
    _process!.stdin.flush();
  }

  /// Stops the process.
  Future<void> stop() async {
    if (_process == null) {
      return;
    }

    _process!.kill();

    // Wait for the process to actually terminate
    await _exitCodeCompleter?.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        // Force kill if it doesn't terminate gracefully
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _process = null;
  }

  /// Restarts the process.
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Disposes of resources. Call this when done with the ProcessPipe.
  Future<void> dispose() async {
    await stop();
    await _outputController.close();
    await _errorController.close();
  }
}
