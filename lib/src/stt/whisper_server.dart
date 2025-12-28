import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.whisper);

/// Exception thrown by WhisperServer operations.
class WhisperServerException implements Exception {
  final String message;
  final Object? cause;

  WhisperServerException(this.message, [this.cause]);

  @override
  String toString() =>
      'WhisperServerException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Whisper server manager that keeps the model loaded for fast transcription.
///
/// Unlike WhisperProcess which spawns a new process for each transcription
/// (loading the model each time), WhisperServer starts a persistent server
/// that keeps the model in memory.
class WhisperServer {
  final String modelPath;
  final String serverExecutablePath;
  final String host;
  final int port;
  final Duration startupTimeout;

  Process? _serverProcess;
  bool _initialized = false;
  bool _disposed = false;
  late final String _baseUrl;

  WhisperServer({
    required this.modelPath,
    required this.serverExecutablePath,
    this.host = '127.0.0.1',
    this.port = 8178, // Non-standard port to avoid conflicts
    this.startupTimeout = const Duration(seconds: 30),
  }) {
    _baseUrl = 'http://$host:$port';
  }

  /// Whether the server is initialized and running.
  bool get isInitialized => _initialized;

  /// Initializes by starting the whisper server.
  Future<void> initialize() async {
    if (_disposed) {
      throw WhisperServerException('WhisperServer has been disposed');
    }
    if (_initialized) return;

    // Check executable exists
    if (!await File(serverExecutablePath).exists()) {
      throw WhisperServerException(
        'Whisper server executable not found at: $serverExecutablePath',
      );
    }

    // Check model exists
    if (!await File(modelPath).exists()) {
      throw WhisperServerException('Whisper model not found at: $modelPath');
    }

    _log.info('Starting whisper server on $host:$port...');

    try {
      // Start the server process
      _serverProcess = await Process.start(
        serverExecutablePath,
        [
          '--model', modelPath,
          '--host', host,
          '--port', port.toString(),
          '--inference-path', '/v1/audio/transcriptions',
          '--convert', // Auto-convert audio formats
        ],
      );

      // Log stderr for debugging
      _serverProcess!.stderr.transform(utf8.decoder).listen((line) {
        _log.fine('[whisper-server] $line');
      });

      // Wait for server to be ready
      final ready = await _waitForServer();
      if (!ready) {
        await _killServer();
        throw WhisperServerException(
          'Whisper server failed to start within $startupTimeout',
        );
      }

      _initialized = true;
      _log.info('Whisper server started successfully');
    } catch (e) {
      await _killServer();
      if (e is WhisperServerException) rethrow;
      throw WhisperServerException('Failed to start whisper server', e);
    }
  }

  /// Waits for the server to be ready to accept requests.
  Future<bool> _waitForServer() async {
    final deadline = DateTime.now().add(startupTimeout);
    final client = http.Client();

    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await client
            .get(Uri.parse('$_baseUrl/'))
            .timeout(const Duration(seconds: 1));
        if (response.statusCode == 200) {
          client.close();
          return true;
        }
      } catch (_) {
        // Server not ready yet
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    client.close();
    return false;
  }

  /// Transcribes audio data to text.
  ///
  /// The audio data should be raw PCM (16-bit signed, 16kHz, mono).
  Future<String> transcribe(Uint8List audioData) async {
    if (audioData.isEmpty) {
      return '';
    }
    if (_disposed) {
      throw WhisperServerException('WhisperServer has been disposed');
    }
    if (!_initialized) {
      throw WhisperServerException('WhisperServer not initialized');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Add WAV header to raw PCM data
      final wavData = _addWavHeader(audioData);
      final audioDurationMs = audioData.length ~/ 32; // 16kHz * 2 bytes = 32 bytes/ms

      // Send to server using multipart form
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/v1/audio/transcriptions'),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        wavData,
        filename: 'audio.wav',
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      stopwatch.stop();

      if (response.statusCode != 200) {
        throw WhisperServerException(
          'Transcription failed with status ${response.statusCode}: ${response.body}',
        );
      }

      // Parse JSON response
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (json['text'] as String? ?? '').trim();

      _log.info(
        '[TIMING] Whisper transcription: ${stopwatch.elapsedMilliseconds}ms '
        '(audio: ${audioDurationMs}ms, '
        'speed: ${(audioDurationMs / stopwatch.elapsedMilliseconds).toStringAsFixed(1)}x realtime)',
      );

      return text;
    } catch (e) {
      if (e is WhisperServerException) rethrow;
      throw WhisperServerException('Failed to transcribe audio', e);
    }
  }

  /// Creates a WAV file from raw PCM data.
  Uint8List _addWavHeader(Uint8List pcmData) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;

    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    // Combine header and PCM data
    final wavFile = Uint8List(44 + pcmData.length);
    wavFile.setRange(0, 44, header.buffer.asUint8List());
    wavFile.setRange(44, 44 + pcmData.length, pcmData);

    return wavFile;
  }

  /// Kills the server process.
  Future<void> _killServer() async {
    if (_serverProcess != null) {
      _serverProcess!.kill(ProcessSignal.sigterm);
      // Wait briefly for graceful shutdown
      try {
        await _serverProcess!.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Force kill if timeout
        _serverProcess!.kill(ProcessSignal.sigkill);
      }
      _serverProcess = null;
    }
  }

  /// Disposes of resources and stops the server.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;

    _log.info('Stopping whisper server...');
    await _killServer();
    _log.info('Whisper server stopped');
  }
}
