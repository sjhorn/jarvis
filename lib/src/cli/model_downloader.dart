/// Downloads ML models required for JARVIS.
///
/// Models are downloaded to ~/.jarvis/models/ on first run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.modelDownloader);

/// Downloads and sets up ML models for JARVIS.
class ModelDownloader {
  /// Whisper model URL (base.en - good balance of speed and accuracy).
  static const whisperModelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';

  /// KWS model archive URL.
  static const kwsModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/'
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2';

  /// TTS model URL.
  static const ttsModelUrl =
      'https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/high/jarvis-high.onnx';

  /// TTS config URL.
  static const ttsConfigUrl =
      'https://huggingface.co/jgkawell/jarvis/resolve/main/en/en_GB/jarvis/high/jarvis-high.onnx.json';

  /// espeak-ng data archive URL.
  static const espeakDataUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'espeak-ng-data.tar.bz2';

  final String modelsDir;
  final void Function(String message)? onProgress;

  ModelDownloader({
    required this.modelsDir,
    this.onProgress,
  });

  void _progress(String message) {
    onProgress?.call(message);
    _log.info(message);
  }

  /// Downloads all models required for JARVIS.
  Future<void> downloadAll() async {
    await Directory(modelsDir).create(recursive: true);

    await downloadWhisperModel();
    await downloadKwsModel();
    await downloadTtsModel();
  }

  /// Downloads the Whisper speech-to-text model.
  Future<void> downloadWhisperModel() async {
    final whisperDir = '$modelsDir/whisper';
    final modelPath = '$whisperDir/ggml-base.en.bin';

    // Check if already downloaded
    if (await File(modelPath).exists()) {
      _progress('Whisper model already downloaded');
      return;
    }

    await Directory(whisperDir).create(recursive: true);

    _progress('Downloading Whisper model (base.en, ~142MB)...');
    await _downloadFile(whisperModelUrl, modelPath);
    _progress('Whisper model ready');
  }

  /// Downloads the keyword spotting model.
  Future<void> downloadKwsModel() async {
    final kwsDir = '$modelsDir/kws';
    final modelDir =
        '$kwsDir/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';

    // Check if already downloaded
    if (await Directory(modelDir).exists()) {
      _progress('KWS model already downloaded');
      return;
    }

    await Directory(kwsDir).create(recursive: true);

    _progress('Downloading KWS model...');
    final archivePath = '$kwsDir/kws-model.tar.bz2';
    await _downloadFile(kwsModelUrl, archivePath);

    _progress('Extracting KWS model...');
    await _extractTarBz2(archivePath, kwsDir);

    // Clean up archive
    await File(archivePath).delete();
    _progress('KWS model ready');
  }

  /// Downloads the TTS model and generates tokens.txt.
  Future<void> downloadTtsModel() async {
    final ttsDir = '$modelsDir/tts';
    await Directory(ttsDir).create(recursive: true);

    final modelPath = '$ttsDir/model.onnx';
    final configPath = '$ttsDir/model.onnx.json';
    final tokensPath = '$ttsDir/tokens.txt';
    final espeakDir = '$ttsDir/espeak-ng-data';
    final metadataMarker = '$ttsDir/.metadata_added';

    // Download model if not exists
    if (!await File(modelPath).exists()) {
      _progress('Downloading TTS model...');
      await _downloadFile(ttsModelUrl, modelPath);
    } else {
      _progress('TTS model already downloaded');
    }

    // Download config if not exists
    if (!await File(configPath).exists()) {
      _progress('Downloading TTS config...');
      await _downloadFile(ttsConfigUrl, configPath);
    }

    // Add ONNX metadata using Python (required for sherpa-onnx)
    if (!await File(metadataMarker).exists()) {
      _progress('Adding ONNX metadata (requires Python)...');
      await _addOnnxMetadata(ttsDir, modelPath, configPath);
      // Create marker file to indicate metadata has been added
      await File(metadataMarker).writeAsString('done');
    }

    // Generate tokens.txt from config
    if (!await File(tokensPath).exists()) {
      _progress('Generating tokens.txt...');
      await _generateTokens(configPath, tokensPath);
    }

    // Download espeak-ng-data if not exists
    if (!await Directory(espeakDir).exists()) {
      _progress('Downloading espeak-ng-data...');
      final archivePath = '$ttsDir/espeak-ng-data.tar.bz2';
      await _downloadFile(espeakDataUrl, archivePath);

      _progress('Extracting espeak-ng-data...');
      await _extractTarBz2(archivePath, ttsDir);

      await File(archivePath).delete();
    } else {
      _progress('espeak-ng-data already downloaded');
    }

    _progress('TTS model ready');
  }

  /// Downloads a file with progress reporting.
  Future<void> _downloadFile(String url, String destPath) async {
    _log.fine('Downloading: $url');
    _log.fine('Destination: $destPath');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw ModelDownloadException(
          'Failed to download: HTTP ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength ?? 0;
      final file = File(destPath);
      final sink = file.openWrite();

      var downloaded = 0;
      var lastPercent = -1;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;

        if (contentLength > 0) {
          final percent = (downloaded * 100 / contentLength).round();
          if (percent != lastPercent && percent % 10 == 0) {
            _progress('  $percent% downloaded');
            lastPercent = percent;
          }
        }
      }

      await sink.close();
      _log.fine('Download complete: $destPath');
    } finally {
      client.close();
    }
  }

  /// Extracts a tar.bz2 archive.
  Future<void> _extractTarBz2(String archivePath, String destDir) async {
    final bytes = await File(archivePath).readAsBytes();

    // Decompress bz2
    final decompressed = BZip2Decoder().decodeBytes(bytes);

    // Extract tar
    final archive = TarDecoder().decodeBytes(decompressed);

    for (final file in archive) {
      final filePath = '$destDir/${file.name}';

      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  /// Generates tokens.txt from the TTS config JSON.
  ///
  /// This ports the Python convert.py logic to Dart.
  Future<void> _generateTokens(String configPath, String tokensPath) async {
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      throw ModelDownloadException('Config file not found: $configPath');
    }

    final configJson = await configFile.readAsString();
    final config = json.decode(configJson) as Map<String, dynamic>;

    final phonemeIdMap = config['phoneme_id_map'] as Map<String, dynamic>?;
    if (phonemeIdMap == null) {
      throw ModelDownloadException('phoneme_id_map not found in config');
    }

    final buffer = StringBuffer();
    for (final entry in phonemeIdMap.entries) {
      final phoneme = entry.key;
      final ids = entry.value as List<dynamic>;
      if (ids.isNotEmpty) {
        buffer.writeln('$phoneme ${ids[0]}');
      }
    }

    await File(tokensPath).writeAsString(buffer.toString());
    _log.fine('Generated tokens.txt');
  }

  /// Adds required metadata to the TTS ONNX model using Python.
  ///
  /// sherpa-onnx requires specific metadata in the ONNX model file.
  /// This creates a Python venv, installs onnx, and runs a script.
  Future<void> _addOnnxMetadata(
    String ttsDir,
    String modelPath,
    String configPath,
  ) async {
    // Find Python 3
    final python = await _findPython();
    if (python == null) {
      throw ModelDownloadException(
        'Python 3 not found. Please install Python 3.8+ to continue.\n'
        'macOS: brew install python3\n'
        'Linux: sudo apt install python3 python3-venv',
      );
    }
    _log.fine('Found Python: $python');

    final venvDir = '$ttsDir/venv';
    final venvPython = Platform.isWindows
        ? '$venvDir/Scripts/python.exe'
        : '$venvDir/bin/python';
    final venvPip = Platform.isWindows
        ? '$venvDir/Scripts/pip.exe'
        : '$venvDir/bin/pip';

    // Create venv if not exists
    if (!await Directory(venvDir).exists()) {
      _progress('  Creating Python virtual environment...');
      final result = await Process.run(python, ['-m', 'venv', venvDir]);
      if (result.exitCode != 0) {
        throw ModelDownloadException(
          'Failed to create venv: ${result.stderr}',
        );
      }
    }

    // Install onnx if not already installed
    _progress('  Installing onnx package...');
    final pipResult = await Process.run(
      venvPip,
      ['install', '--quiet', 'onnx'],
    );
    if (pipResult.exitCode != 0) {
      throw ModelDownloadException(
        'Failed to install onnx: ${pipResult.stderr}',
      );
    }

    // Python script to add metadata
    final pythonScript = '''
import json
import onnx

model_path = "$modelPath"
config_path = "$configPath"

# Load config
with open(config_path, "r") as f:
    config = json.load(f)

# Load and modify ONNX model
model = onnx.load(model_path)

# Add sherpa-onnx required metadata
metadata = {
    "model_type": "vits",
    "comment": "piper",
    "language": config["language"]["name_english"],
    "voice": config["espeak"]["voice"],
    "has_espeak": "1",
    "n_speakers": str(config["num_speakers"]),
    "sample_rate": str(config["audio"]["sample_rate"]),
}

for key, value in metadata.items():
    meta = model.metadata_props.add()
    meta.key = key
    meta.value = value

# Save modified model
onnx.save(model, model_path)
print("Metadata added successfully")
''';

    // Write and run script
    final scriptPath = '$ttsDir/add_metadata.py';
    await File(scriptPath).writeAsString(pythonScript);

    _progress('  Adding metadata to ONNX model...');
    final scriptResult = await Process.run(venvPython, [scriptPath]);
    if (scriptResult.exitCode != 0) {
      throw ModelDownloadException(
        'Failed to add metadata: ${scriptResult.stderr}',
      );
    }
    _log.fine('ONNX metadata added: ${scriptResult.stdout}');

    // Clean up script
    await File(scriptPath).delete();
  }

  /// Finds Python 3 executable.
  Future<String?> _findPython() async {
    final candidates = Platform.isWindows
        ? ['python', 'python3', 'py']
        : ['python3', 'python'];

    for (final name in candidates) {
      try {
        final result = await Process.run(name, ['--version']);
        if (result.exitCode == 0) {
          final version = result.stdout.toString();
          // Ensure it's Python 3
          if (version.contains('Python 3')) {
            return name;
          }
        }
      } catch (_) {
        // Not found, try next
      }
    }
    return null;
  }

  /// Checks if all models are downloaded.
  Future<bool> hasAllModels() async {
    final whisperModel = File('$modelsDir/whisper/ggml-base.en.bin');
    final kwsModel = File(
      '$modelsDir/kws/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01/'
      'encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
    );
    final ttsModel = File('$modelsDir/tts/model.onnx');
    final tokens = File('$modelsDir/tts/tokens.txt');
    final espeakData = Directory('$modelsDir/tts/espeak-ng-data');

    return await whisperModel.exists() &&
        await kwsModel.exists() &&
        await ttsModel.exists() &&
        await tokens.exists() &&
        await espeakData.exists();
  }

  /// Gets model paths for configuration.
  Map<String, String> getModelPaths() {
    final whisperDir = '$modelsDir/whisper';
    final kwsDir =
        '$modelsDir/kws/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';
    final ttsDir = '$modelsDir/tts';

    return {
      'whisper_model_path': '$whisperDir/ggml-base.en.bin',
      'wakeword_encoder_path':
          '$kwsDir/encoder-epoch-12-avg-2-chunk-16-left-64.onnx',
      'wakeword_decoder_path':
          '$kwsDir/decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
      'wakeword_joiner_path':
          '$kwsDir/joiner-epoch-12-avg-2-chunk-16-left-64.onnx',
      'wakeword_tokens_path': '$kwsDir/tokens.txt',
      'wakeword_keywords_file': '$kwsDir/keywords.txt',
      'tts_model_path': '$ttsDir/model.onnx',
      'tts_tokens_path': '$ttsDir/tokens.txt',
      'tts_data_dir': '$ttsDir/espeak-ng-data',
    };
  }
}

/// Exception thrown when model download fails.
class ModelDownloadException implements Exception {
  final String message;
  final Object? cause;

  ModelDownloadException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'ModelDownloadException: $message ($cause)';
    }
    return 'ModelDownloadException: $message';
  }
}
