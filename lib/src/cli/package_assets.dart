/// Resolves bundled package assets at runtime.
///
/// When installed via `dart pub global activate`, assets are located
/// in the pub cache. This utility finds the package root directory
/// using Dart's Isolate.resolvePackageUri.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import '../logging.dart';

final _log = Logger(Loggers.packageAssets);

/// Provides access to assets bundled with the package.
class PackageAssets {
  PackageAssets._();

  static String? _packageRoot;

  /// Gets the package root directory.
  ///
  /// Returns null if unable to resolve (e.g., running from source).
  static Future<String?> getPackageRoot() async {
    if (_packageRoot != null) return _packageRoot;

    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:jarvis_dart/'),
      );
      if (uri != null) {
        // uri points to lib/, we need the parent
        final libDir = Directory.fromUri(uri);
        _packageRoot = libDir.parent.path;
        _log.fine('Package root resolved: $_packageRoot');
      }
    } catch (e) {
      _log.warning('Failed to resolve package root: $e');
    }

    return _packageRoot;
  }

  /// Gets the path to bundled acknowledgment audio files.
  ///
  /// Returns null if assets are not found.
  static Future<String?> getAcknowledgmentsDir() async {
    final root = await getPackageRoot();
    if (root == null) return null;

    final dir = Directory('$root/assets/acknowledgments');
    if (await dir.exists()) {
      _log.fine('Found acknowledgments at: ${dir.path}');
      return dir.path;
    }

    _log.warning('Acknowledgments directory not found at: ${dir.path}');
    return null;
  }

  /// Gets the path to bundled barge-in audio files.
  ///
  /// Returns null if assets are not found.
  static Future<String?> getBargeInDir() async {
    final root = await getPackageRoot();
    if (root == null) return null;

    final dir = Directory('$root/assets/bargein');
    if (await dir.exists()) {
      _log.fine('Found bargein at: ${dir.path}');
      return dir.path;
    }

    _log.warning('Barge-in directory not found at: ${dir.path}');
    return null;
  }

  /// Checks if bundled assets are available.
  static Future<bool> hasAssets() async {
    final ackDir = await getAcknowledgmentsDir();
    final bargeInDir = await getBargeInDir();
    return ackDir != null && bargeInDir != null;
  }
}
