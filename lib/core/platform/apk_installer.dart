import 'package:flutter/services.dart';

class ApkInstaller {
  static const _channel = MethodChannel('chat.cleona/update');

  static Future<bool> canInstallPackages() async {
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod('openInstallPermissionSettings');
  }

  /// Opens install-permission settings via ActivityResultLauncher and awaits
  /// the user's return. Returns true if permission was granted.
  static Future<bool> requestInstallPermission() async {
    return await _channel.invokeMethod<bool>('requestInstallPermission') ?? false;
  }

  static Future<String> installApk(String path) async {
    final result =
        await _channel.invokeMethod<String>('installApk', {'path': path});
    return result ?? 'unknown_error';
  }
}
