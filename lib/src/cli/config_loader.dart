import 'dart:io';

import 'package:yaml/yaml.dart';

import '../voice_assistant.dart';

/// Exception thrown when configuration loading fails.
class ConfigException implements Exception {
  final String message;
  final Object? cause;

  ConfigException(this.message, [this.cause]);

  @override
  String toString() =>
      'ConfigException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Configuration loaded from environment variables or YAML file.
class AppConfig {
  final String whisperModelPath;
  final String whisperExecutablePath;
  final String llamaModelRepo;
  final String llamaExecutablePath;
  final String wakeWordEncoderPath;
  final String wakeWordDecoderPath;
  final String wakeWordJoinerPath;
  final String wakeWordTokensPath;
  final String wakeWordKeywordsFile;
  final String ttsModelPath;
  final String ttsTokensPath;
  final String ttsDataDir;
  final String sherpaLibPath;
  final String? acknowledgmentDir;
  final String? systemPrompt;
  final double silenceThreshold;
  final Duration silenceDuration;
  final int maxHistoryLength;
  final Duration sentencePause;
  final bool enableFollowUp;
  final Duration followUpTimeout;
  final bool enableBargeIn;

  AppConfig({
    required this.whisperModelPath,
    required this.whisperExecutablePath,
    required this.llamaModelRepo,
    required this.llamaExecutablePath,
    required this.wakeWordEncoderPath,
    required this.wakeWordDecoderPath,
    required this.wakeWordJoinerPath,
    required this.wakeWordTokensPath,
    required this.wakeWordKeywordsFile,
    required this.ttsModelPath,
    required this.ttsTokensPath,
    required this.ttsDataDir,
    required this.sherpaLibPath,
    this.acknowledgmentDir,
    this.systemPrompt,
    this.silenceThreshold = 0.01,
    this.silenceDuration = const Duration(milliseconds: 800),
    this.maxHistoryLength = 10,
    this.sentencePause = const Duration(milliseconds: 300),
    this.enableFollowUp = true,
    this.followUpTimeout = const Duration(seconds: 8),
    this.enableBargeIn = true,
  });

  /// Converts to VoiceAssistantConfig for use with VoiceAssistant.
  VoiceAssistantConfig toVoiceAssistantConfig() {
    return VoiceAssistantConfig(
      whisperModelPath: whisperModelPath,
      whisperExecutablePath: whisperExecutablePath,
      llamaModelRepo: llamaModelRepo,
      llamaExecutablePath: llamaExecutablePath,
      wakeWordEncoderPath: wakeWordEncoderPath,
      wakeWordDecoderPath: wakeWordDecoderPath,
      wakeWordJoinerPath: wakeWordJoinerPath,
      wakeWordTokensPath: wakeWordTokensPath,
      wakeWordKeywordsFile: wakeWordKeywordsFile,
      ttsModelPath: ttsModelPath,
      ttsTokensPath: ttsTokensPath,
      ttsDataDir: ttsDataDir,
      sherpaLibPath: sherpaLibPath,
      acknowledgmentDir: acknowledgmentDir,
      systemPrompt: systemPrompt,
      silenceThreshold: silenceThreshold,
      silenceDuration: silenceDuration,
      maxHistoryLength: maxHistoryLength,
      sentencePause: sentencePause,
      enableFollowUp: enableFollowUp,
      followUpTimeout: followUpTimeout,
      enableBargeIn: enableBargeIn,
    );
  }
}

/// Loads configuration from various sources.
class ConfigLoader {
  /// Required environment variable names.
  static const _requiredEnvVars = [
    'WHISPER_MODEL_PATH',
    'WHISPER_EXECUTABLE',
    'LLAMA_MODEL_REPO',
    'LLAMA_EXECUTABLE',
    'WAKEWORD_ENCODER_PATH',
    'WAKEWORD_DECODER_PATH',
    'WAKEWORD_JOINER_PATH',
    'WAKEWORD_TOKENS_PATH',
    'WAKEWORD_KEYWORDS_FILE',
    'TTS_MODEL_PATH',
    'TTS_TOKENS_PATH',
    'TTS_DATA_DIR',
    'SHERPA_LIB_PATH',
  ];

  /// Required YAML field names.
  static const _requiredYamlFields = [
    'whisper_model_path',
    'whisper_executable',
    'llama_model_repo',
    'llama_executable',
    'wakeword_encoder_path',
    'wakeword_decoder_path',
    'wakeword_joiner_path',
    'wakeword_tokens_path',
    'wakeword_keywords_file',
    'tts_model_path',
    'tts_tokens_path',
    'tts_data_dir',
    'sherpa_lib_path',
  ];

  /// Loads configuration from environment variables.
  ///
  /// Pass a custom [env] map for testing, or leave null to use
  /// Platform.environment.
  static AppConfig fromEnvironment([Map<String, String>? env]) {
    final environment = env ?? Platform.environment;

    // Check for missing required variables
    final missing = <String>[];
    for (final varName in _requiredEnvVars) {
      if (environment[varName] == null || environment[varName]!.isEmpty) {
        missing.add(varName);
      }
    }

    if (missing.isNotEmpty) {
      throw ConfigException(
        'Missing required environment variables: ${missing.join(', ')}',
      );
    }

    return AppConfig(
      whisperModelPath: environment['WHISPER_MODEL_PATH']!,
      whisperExecutablePath: environment['WHISPER_EXECUTABLE']!,
      llamaModelRepo: environment['LLAMA_MODEL_REPO']!,
      llamaExecutablePath: environment['LLAMA_EXECUTABLE']!,
      wakeWordEncoderPath: environment['WAKEWORD_ENCODER_PATH']!,
      wakeWordDecoderPath: environment['WAKEWORD_DECODER_PATH']!,
      wakeWordJoinerPath: environment['WAKEWORD_JOINER_PATH']!,
      wakeWordTokensPath: environment['WAKEWORD_TOKENS_PATH']!,
      wakeWordKeywordsFile: environment['WAKEWORD_KEYWORDS_FILE']!,
      ttsModelPath: environment['TTS_MODEL_PATH']!,
      ttsTokensPath: environment['TTS_TOKENS_PATH']!,
      ttsDataDir: environment['TTS_DATA_DIR']!,
      sherpaLibPath: environment['SHERPA_LIB_PATH']!,
      acknowledgmentDir: environment['ACKNOWLEDGMENT_DIR'],
      systemPrompt: environment['SYSTEM_PROMPT'],
      silenceThreshold: _parseDouble(environment['SILENCE_THRESHOLD'], 0.01),
      silenceDuration: Duration(
        milliseconds: _parseInt(environment['SILENCE_DURATION_MS'], 800),
      ),
      maxHistoryLength: _parseInt(environment['MAX_HISTORY_LENGTH'], 10),
      sentencePause: Duration(
        milliseconds: _parseInt(environment['SENTENCE_PAUSE_MS'], 300),
      ),
      enableFollowUp: _parseBool(environment['ENABLE_FOLLOW_UP'], true),
      followUpTimeout: Duration(
        milliseconds: _parseInt(environment['FOLLOW_UP_TIMEOUT_MS'], 8000),
      ),
      enableBargeIn: _parseBool(environment['ENABLE_BARGE_IN'], true),
    );
  }

  /// Loads configuration from a YAML file.
  static Future<AppConfig> fromYamlFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ConfigException('Configuration file not found: $path');
    }

    try {
      final content = await file.readAsString();
      final yaml = loadYaml(content) as YamlMap;

      // Check for missing required fields
      final missing = <String>[];
      for (final field in _requiredYamlFields) {
        if (yaml[field] == null) {
          missing.add(field);
        }
      }

      if (missing.isNotEmpty) {
        throw ConfigException(
          'Missing required fields in config file: ${missing.join(', ')}',
        );
      }

      return AppConfig(
        whisperModelPath: yaml['whisper_model_path'] as String,
        whisperExecutablePath: yaml['whisper_executable'] as String,
        llamaModelRepo: yaml['llama_model_repo'] as String,
        llamaExecutablePath: yaml['llama_executable'] as String,
        wakeWordEncoderPath: yaml['wakeword_encoder_path'] as String,
        wakeWordDecoderPath: yaml['wakeword_decoder_path'] as String,
        wakeWordJoinerPath: yaml['wakeword_joiner_path'] as String,
        wakeWordTokensPath: yaml['wakeword_tokens_path'] as String,
        wakeWordKeywordsFile: yaml['wakeword_keywords_file'] as String,
        ttsModelPath: yaml['tts_model_path'] as String,
        ttsTokensPath: yaml['tts_tokens_path'] as String,
        ttsDataDir: yaml['tts_data_dir'] as String,
        sherpaLibPath: yaml['sherpa_lib_path'] as String,
        acknowledgmentDir: yaml['acknowledgment_dir'] as String?,
        systemPrompt: yaml['system_prompt'] as String?,
        silenceThreshold: _parseYamlDouble(yaml['silence_threshold'], 0.01),
        silenceDuration: Duration(
          milliseconds: _parseYamlInt(yaml['silence_duration_ms'], 800),
        ),
        maxHistoryLength: _parseYamlInt(yaml['max_history_length'], 10),
        sentencePause: Duration(
          milliseconds: _parseYamlInt(yaml['sentence_pause_ms'], 300),
        ),
        enableFollowUp: _parseYamlBool(yaml['enable_follow_up'], true),
        followUpTimeout: Duration(
          milliseconds: _parseYamlInt(yaml['follow_up_timeout_ms'], 8000),
        ),
        enableBargeIn: _parseYamlBool(yaml['enable_barge_in'], true),
      );
    } on YamlException catch (e) {
      throw ConfigException('Invalid YAML in config file', e);
    }
  }

  static double _parseDouble(String? value, double defaultValue) {
    if (value == null || value.isEmpty) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  static int _parseInt(String? value, int defaultValue) {
    if (value == null || value.isEmpty) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  static bool _parseBool(String? value, bool defaultValue) {
    if (value == null || value.isEmpty) return defaultValue;
    return value.toLowerCase() == 'true';
  }

  static double _parseYamlDouble(Object? value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static int _parseYamlInt(Object? value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  static bool _parseYamlBool(Object? value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return defaultValue;
  }
}
