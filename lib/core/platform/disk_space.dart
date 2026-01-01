import 'dart:io';

import 'package:cleona/core/network/clogger.dart';

/// Platform-aware free disk space detection.
///
/// Linux/macOS: uses `df` command.
/// Android: uses a callback set by the Flutter app (Platform Channel to StatFs).
/// Fallback: returns 0 (caller uses minBudget).
class DiskSpace {
  static final _log = CLogger.get('disk-space');

  /// Optional platform query function set by Flutter GUI on Android.
  /// Signature: `Future<int> queryFn(String path)` returning free bytes.
  /// Set this from main.dart or wherever Flutter services are initialized.
  static Future<int> Function(String path)? platformQueryFn;

  /// Get free disk space in bytes for the given path.
  /// Returns 0 on failure (caller should use fallback budget).
  static Future<int> getFreeDiskSpace(String path) async {
    try {
      if (Platform.isAndroid) {
        return await _getAndroidFreeSpace(path);
      }
      if (Platform.isWindows) {
        return await _getWindowsFreeSpace(path);
      }
      return await _getLinuxFreeSpace(path);
    } catch (e) {
      _log.debug('Failed to get free disk space for $path: $e');
      return 0;
    }
  }

  /// Linux/macOS: parse `df -B1 --output=avail <path>`.
  static Future<int> _getLinuxFreeSpace(String path) async {
    final result = await Process.run('df', ['-B1', '--output=avail', path]);
    if (result.exitCode != 0) {
      _log.debug('df failed (exit ${result.exitCode}): ${result.stderr}');
      return 0;
    }
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return 0;
    final bytes = int.tryParse(lines[1].trim());
    if (bytes != null && bytes > 0) {
      _log.debug('Free disk space at $path: ${(bytes / (1024 * 1024)).round()} MB');
    }
    return bytes ?? 0;
  }

  /// Windows: parse PowerShell Get-PSDrive output.
  static Future<int> _getWindowsFreeSpace(String path) async {
    // Extract drive letter from path (e.g., "C" from "C:\Users\...")
    final drive = path.isNotEmpty && path.length >= 2 && path[1] == ':'
        ? path[0].toUpperCase()
        : 'C';
    final result = await Process.run('powershell', [
      '-NoProfile', '-Command',
      '(Get-PSDrive $drive).Free',
    ]);
    if (result.exitCode != 0) return 0;
    final bytes = int.tryParse((result.stdout as String).trim());
    if (bytes != null && bytes > 0) {
      _log.debug('Free disk space at $path: ${(bytes / (1024 * 1024)).round()} MB');
    }
    return bytes ?? 0;
  }

  /// Android: use platform query function set by Flutter app.
  static Future<int> _getAndroidFreeSpace(String path) async {
    final queryFn = platformQueryFn;
    if (queryFn == null) {
      _log.debug('No platform query function set — using default budget');
      return 0;
    }
    return await queryFn(path);
  }
}
