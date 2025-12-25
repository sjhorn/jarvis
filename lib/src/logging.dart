import 'dart:io';

import 'package:logging/logging.dart';

/// Configures logging for the JARVIS application.
///
/// This module sets up hierarchical logging with configurable levels
/// and formatted output to stderr (to keep stdout clean for user output).
class LogConfig {
  static bool _initialized = false;

  /// Initializes logging with the specified level.
  ///
  /// Call this once at application startup before any logging occurs.
  /// Logs are written to stderr to keep stdout available for user interaction.
  ///
  /// Levels (from most to least verbose):
  /// - Level.ALL / Level.FINEST: Trace-level debugging
  /// - Level.FINER: Detailed debugging
  /// - Level.FINE: Debug information
  /// - Level.CONFIG: Configuration information
  /// - Level.INFO: Informational messages (default)
  /// - Level.WARNING: Warnings
  /// - Level.SEVERE: Errors
  /// - Level.SHOUT: Critical errors
  /// - Level.OFF: Disable all logging
  static void initialize({
    Level level = Level.INFO,
    bool includeTimestamp = true,
    bool includeLevel = true,
    bool includeLoggerName = true,
  }) {
    if (_initialized) return;
    _initialized = true;

    // Enable hierarchical logging
    hierarchicalLoggingEnabled = true;

    // Set root logger level
    Logger.root.level = level;

    // Set up log handler
    Logger.root.onRecord.listen((record) {
      final buffer = StringBuffer();

      if (includeTimestamp) {
        buffer.write(_formatTime(record.time));
        buffer.write(' ');
      }

      if (includeLevel) {
        buffer.write('[${_levelToString(record.level)}] ');
      }

      if (includeLoggerName && record.loggerName.isNotEmpty) {
        buffer.write('${record.loggerName}: ');
      }

      buffer.write(record.message);

      if (record.error != null) {
        buffer.write(' - ${record.error}');
      }

      if (record.stackTrace != null) {
        buffer.writeln();
        buffer.write(record.stackTrace);
      }

      // Write to stderr to keep stdout clean for user interaction
      stderr.writeln(buffer.toString());
    });
  }

  /// Sets the logging level for a specific logger.
  ///
  /// Use this to enable verbose logging for specific modules:
  /// ```dart
  /// LogConfig.setLevel('jarvis.whisper', Level.FINE);
  /// ```
  static void setLevel(String loggerName, Level level) {
    Logger(loggerName).level = level;
  }

  /// Sets the root logging level.
  static void setRootLevel(Level level) {
    Logger.root.level = level;
  }

  static String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  static String _levelToString(Level level) {
    if (level == Level.FINEST) return 'TRACE';
    if (level == Level.FINER) return 'DEBUG';
    if (level == Level.FINE) return 'DEBUG';
    if (level == Level.CONFIG) return 'CONFIG';
    if (level == Level.INFO) return 'INFO';
    if (level == Level.WARNING) return 'WARN';
    if (level == Level.SEVERE) return 'ERROR';
    if (level == Level.SHOUT) return 'FATAL';
    return level.name;
  }
}

/// Logger names used throughout the application.
///
/// Use these constants when creating loggers to ensure consistency:
/// ```dart
/// final _log = Logger(Loggers.voiceAssistant);
/// ```
class Loggers {
  static const String root = 'jarvis';
  static const String voiceAssistant = 'jarvis.assistant';
  static const String audio = 'jarvis.audio';
  static const String audioInput = 'jarvis.audio.input';
  static const String audioOutput = 'jarvis.audio.output';
  static const String whisper = 'jarvis.whisper';
  static const String llama = 'jarvis.llama';
  static const String wakeWord = 'jarvis.wakeword';
  static const String vad = 'jarvis.vad';
  static const String tts = 'jarvis.tts';
  static const String config = 'jarvis.config';
}
