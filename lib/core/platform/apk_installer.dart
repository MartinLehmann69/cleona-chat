import 'package:flutter/services.dart';

class ApkInstaller {
  static const _channel = MethodChannel('chat.cleona/update');

  static Future<bool> canInstallPackages() async {
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod('openInstallPermissionSettings');
  }

  static Future<String> installApk(String path) async {
    final result =
        await _channel.invokeMethod<String>('installApk', {'path': path});
    return result ?? 'unknown_error';
  }
}
