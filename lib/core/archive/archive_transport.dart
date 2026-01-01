// Abstract transport layer for Media Auto-Archive.
//
// Supports SMB, SFTP, FTPS and HTTP(S) protocols.
// Each implementation can upload/download files,
// create directories and check connectivity.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/archive/archive_config.dart';

/// Callback for upload/download progress: (bytesTransferred, totalBytes).
typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);

/// Abstract base for archive transport protocols.
abstract class ArchiveTransport {
  /// The protocol being used.
  ArchiveProtocol get protocol;

  /// Connect to the share.
  Future<void> connect({
    required String host,
    required String path,
    String? username,
    String? password,
    int? port,
  });

  /// Disconnect from the share.
  Future<void> disconnect();

  /// Check connectivity to the share.
  Future<bool> testConnectivity({Duration? timeout});

  /// Upload file to the share.
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  });

  /// Download file from the share.
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  });

  /// Create directory on the share (recursively).
  Future<void> createDirectory(String remotePath);

  /// Check whether a file exists on the share.
  Future<bool> fileExists(String remotePath);

  /// Delete file from the share.
  Future<void> deleteFile(String remotePath);

  /// List files in a directory.
  Future<List<String>> listDirectory(String remotePath);

  /// Create transport instance for a specific protocol.
  static ArchiveTransport forProtocol(ArchiveProtocol protocol) {
    switch (protocol) {
      case ArchiveProtocol.smb:
        return SmbTransport();
      case ArchiveProtocol.sftp:
        return SftpTransport();
      case ArchiveProtocol.ftps:
        return FtpsTransport();
      case ArchiveProtocol.http:
        return HttpTransport();
    }
  }
}

/// SMB/CIFS Transport (via smbclient CLI or dart:io ProcessRun).
class SmbTransport extends ArchiveTransport {
  String _host = '';
  String _basePath = '';
  String? _username;
  String? _password;

  @override
  ArchiveProtocol get protocol => ArchiveProtocol.smb;

  @override
  Future<void> connect({
    required String host,
    required String path,
    String? username,
    String? password,
    int? port,
  }) async {
    _host = host;
    _basePath = path.endsWith('/') ? path : '$path/';
    _username = username;
    _password = password;
  }

  @override
  Future<void> disconnect() async {
    // SMB: Stateless CLI-based, nothing to disconnect.
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    try {
      final result = await Process.run(
        'smbclient',
        [
          '//$_host/${_basePath.split('/').first}',
          '-N', // No password prompt
          if (_username != null) ...['-U', _username!],
          '-c', 'ls',
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
      ).timeout(effectiveTimeout);
      return result.exitCode == 0;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_upload_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await tmpFile.writeAsBytes(data);
      onProgress?.call(0, data.length);

      final share = _basePath.split('/').first;
      final dirPath = remotePath.contains('/')
          ? remotePath.substring(0, remotePath.lastIndexOf('/'))
          : '';
      final fileName = remotePath.contains('/')
          ? remotePath.substring(remotePath.lastIndexOf('/') + 1)
          : remotePath;

      final commands = StringBuffer();
      if (dirPath.isNotEmpty) {
        // Create directories recursively
        final parts = dirPath.split('/');
        var current = '';
        for (final part in parts) {
          if (part.isEmpty) continue;
          current = current.isEmpty ? part : '$current/$part';
          commands.writeln('mkdir "$current"');
        }
        commands.writeln('cd "$dirPath"');
      }
      commands.writeln('put "${tmpFile.path}" "$fileName"');

      final result = await Process.run(
        'smbclient',
        [
          '//$_host/$share',
          if (_username != null) ...['-U', _username!],
          '-N',
          '-c', commands.toString(),
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
      );

      if (result.exitCode != 0) {
        throw ArchiveTransportException('SMB upload failed: ${result.stderr}');
      }
      onProgress?.call(data.length, data.length);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_download_${DateTime.now().millisecondsSinceEpoch}');
    try {
      final share = _basePath.split('/').first;
      final result = await Process.run(
        'smbclient',
        [
          '//$_host/$share',
          if (_username != null) ...['-U', _username!],
          '-N',
          '-c', 'get "$remotePath" "${tmpFile.path}"',
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
      );

      if (result.exitCode != 0 || !tmpFile.existsSync()) {
        throw ArchiveTransportException('SMB download failed: ${result.stderr}');
      }

      final data = await tmpFile.readAsBytes();
      onProgress?.call(data.length, data.length);
      return Uint8List.fromList(data);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    final share = _basePath.split('/').first;
    final parts = remotePath.split('/');
    final commands = StringBuffer();
    var current = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      current = current.isEmpty ? part : '$current/$part';
      commands.writeln('mkdir "$current"');
    }

    await Process.run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', commands.toString()],
      environment: _password != null ? {'PASSWD': _password!} : null,
    );
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final share = _basePath.split('/').first;
    final result = await Process.run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'ls "$remotePath"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
    );
    return result.exitCode == 0 && !(result.stdout as String).contains('NT_STATUS_NO_SUCH_FILE');
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final share = _basePath.split('/').first;
    await Process.run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'rm "$remotePath"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
    );
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    final share = _basePath.split('/').first;
    final result = await Process.run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'ls "$remotePath/*"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
    );
    if (result.exitCode != 0) return [];
    final lines = (result.stdout as String).split('\n');
    return lines
        .where((l) => l.trim().isNotEmpty && !l.contains('blocks'))
        .map((l) => l.trim().split(RegExp(r'\s+')).first)
        .where((name) => name != '.' && name != '..')
        .toList();
  }
}

/// SFTP Transport (via ssh/sftp CLI).
class SftpTransport extends ArchiveTransport {
  String _host = '';
  String _basePath = '';
  String? _username;
  int _port = 22;

  @override
  ArchiveProtocol get protocol => ArchiveProtocol.sftp;

  @override
  Future<void> connect({
    required String host,
    required String path,
    String? username,
    String? password,
    int? port,
  }) async {
    _host = host;
    _basePath = path.endsWith('/') ? path : '$path/';
    _username = username;
    _port = port ?? 22;
    // SFTP prefers SSH keys, password via sshpass if needed.
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    try {
      final target = _username != null ? '$_username@$_host' : _host;
      final result = await Process.run(
        'sftp',
        ['-P', '$_port', '-oBatchMode=yes', '-oConnectTimeout=3', target],
        stdoutEncoding: SystemEncoding(),
      ).timeout(effectiveTimeout);
      // sftp returns 0 on success, but even connection test counts
      return result.exitCode == 0 || result.exitCode == 1;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_sftp_upload_${DateTime.now().millisecondsSinceEpoch}');
    final batchFile = File('${Directory.systemTemp.path}/cleona_sftp_batch_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await tmpFile.writeAsBytes(data);
      onProgress?.call(0, data.length);

      final dirPath = remotePath.contains('/')
          ? '$_basePath${remotePath.substring(0, remotePath.lastIndexOf('/'))}'
          : _basePath;

      final commands = StringBuffer();
      commands.writeln('-mkdir $dirPath');
      commands.writeln('put ${tmpFile.path} $_basePath$remotePath');

      await batchFile.writeAsString(commands.toString());

      final target = _username != null ? '$_username@$_host' : _host;
      final result = await Process.run(
        'sftp',
        ['-P', '$_port', '-b', batchFile.path, target],
      );

      if (result.exitCode != 0) {
        throw ArchiveTransportException('SFTP upload failed: ${result.stderr}');
      }
      onProgress?.call(data.length, data.length);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      if (batchFile.existsSync()) batchFile.deleteSync();
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_sftp_download_${DateTime.now().millisecondsSinceEpoch}');
    final batchFile = File('${Directory.systemTemp.path}/cleona_sftp_dbatch_${DateTime.now().millisecondsSinceEpoch}');
    try {
      final target = _username != null ? '$_username@$_host' : _host;
      await batchFile.writeAsString('get $_basePath$remotePath ${tmpFile.path}\n');

      final result = await Process.run(
        'sftp',
        ['-P', '$_port', '-b', batchFile.path, target],
      );

      if (result.exitCode != 0 || !tmpFile.existsSync()) {
        throw ArchiveTransportException('SFTP download failed: ${result.stderr}');
      }

      final data = await tmpFile.readAsBytes();
      onProgress?.call(data.length, data.length);
      return Uint8List.fromList(data);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      if (batchFile.existsSync()) batchFile.deleteSync();
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    final target = _username != null ? '$_username@$_host' : _host;
    await Process.run('ssh', ['-p', '$_port', target, 'mkdir', '-p', '$_basePath$remotePath']);
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final target = _username != null ? '$_username@$_host' : _host;
    final result = await Process.run('ssh', ['-p', '$_port', target, 'test', '-f', '$_basePath$remotePath']);
    return result.exitCode == 0;
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final target = _username != null ? '$_username@$_host' : _host;
    await Process.run('ssh', ['-p', '$_port', target, 'rm', '-f', '$_basePath$remotePath']);
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    final target = _username != null ? '$_username@$_host' : _host;
    final result = await Process.run('ssh', ['-p', '$_port', target, 'ls', '$_basePath$remotePath']);
    if (result.exitCode != 0) return [];
    return (result.stdout as String).split('\n').where((l) => l.trim().isNotEmpty).toList();
  }
}

/// FTPS Transport (via curl CLI).
class FtpsTransport extends ArchiveTransport {
  String _host = '';
  String _basePath = '';
  String? _username;
  String? _password;
  int _port = 990;

  @override
  ArchiveProtocol get protocol => ArchiveProtocol.ftps;

  @override
  Future<void> connect({
    required String host,
    required String path,
    String? username,
    String? password,
    int? port,
  }) async {
    _host = host;
    _basePath = path.endsWith('/') ? path : '$path/';
    _username = username;
    _password = password;
    _port = port ?? 990;
  }

  @override
  Future<void> disconnect() async {}

  /// Create a temporary netrc file for curl authentication.
  /// Returns null if no credentials are configured.
  /// Caller MUST delete the returned file (and its parent directory) in a
  /// finally block via [_cleanupNetrc].
  File? _createNetrcFile() {
    if (_username == null) return null;
    final tmpDir = Directory.systemTemp.createTempSync('cleona_ftps_');
    final netrcFile = File('${tmpDir.path}/.netrc');
    netrcFile.writeAsStringSync(
      'machine $_host login $_username password ${_password ?? ''}\n',
    );
    // Restrict file permissions on platforms that support chmod/icacls.
    if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync('chmod', ['600', netrcFile.path]);
    } else if (Platform.isWindows) {
      // icacls: grant only current user full control, remove inherited perms.
      Process.runSync('icacls', [netrcFile.path, '/inheritance:r',
          '/grant:r', '%USERNAME%:F']);
    }
    // Android/iOS: rely on systemTemp directory permissions (app-private).
    return netrcFile;
  }

  /// Safely remove a netrc file and its parent temp directory.
  void _cleanupNetrc(File? netrcFile) {
    if (netrcFile == null) return;
    try {
      final parentDir = netrcFile.parent;
      if (netrcFile.existsSync()) netrcFile.deleteSync();
      if (parentDir.existsSync()) parentDir.deleteSync();
    } catch (_) {
      // Swallow: must not mask the original exception in a finally block.
    }
  }

  /// Build curl args with --netrc-file (if credentials exist) prepended.
  List<String> _curlArgs(File? netrcFile, List<String> rest) {
    return [
      if (netrcFile != null) ...['--netrc-file', netrcFile.path],
      ...rest,
    ];
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--list-only', '--connect-timeout', '3',
         'ftps://$_host:$_port/$_basePath']),
      ).timeout(effectiveTimeout);
      return result.exitCode == 0;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_ftps_upload_${DateTime.now().millisecondsSinceEpoch}');
    File? netrc;
    try {
      await tmpFile.writeAsBytes(data);
      onProgress?.call(0, data.length);

      netrc = _createNetrcFile();
      final result = await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-T', tmpFile.path, '--ftp-create-dirs',
         'ftps://$_host:$_port/$_basePath$remotePath']),
      );

      if (result.exitCode != 0) {
        throw ArchiveTransportException('FTPS upload failed: ${result.stderr}');
      }
      onProgress?.call(data.length, data.length);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final tmpFile = File('${Directory.systemTemp.path}/cleona_ftps_download_${DateTime.now().millisecondsSinceEpoch}');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-o', tmpFile.path,
         'ftps://$_host:$_port/$_basePath$remotePath']),
      );

      if (result.exitCode != 0 || !tmpFile.existsSync()) {
        throw ArchiveTransportException('FTPS download failed: ${result.stderr}');
      }

      final data = await tmpFile.readAsBytes();
      onProgress?.call(data.length, data.length);
      return Uint8List.fromList(data);
    } finally {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    File? netrc;
    try {
      netrc = _createNetrcFile();
      await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-Q', 'MKD $remotePath',
         'ftps://$_host:$_port/$_basePath']),
      );
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--head', '--silent',
         'ftps://$_host:$_port/$_basePath$remotePath']),
      );
      return result.exitCode == 0;
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    File? netrc;
    try {
      netrc = _createNetrcFile();
      await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-Q', 'DELE $remotePath',
         'ftps://$_host:$_port/$_basePath']),
      );
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await Process.run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--list-only',
         'ftps://$_host:$_port/$_basePath$remotePath/']),
      );
      if (result.exitCode != 0) return [];
      return (result.stdout as String).split('\n').where((l) => l.trim().isNotEmpty).toList();
    } finally {
      _cleanupNetrc(netrc);
    }
  }
}

/// HTTP(S) Transport (via curl/HTTP PUT/GET — WebDAV-compatible).
class HttpTransport extends ArchiveTransport {
  String _baseUrl = '';
  String? _username;
  String? _password;

  @override
  ArchiveProtocol get protocol => ArchiveProtocol.http;

  @override
  Future<void> connect({
    required String host,
    required String path,
    String? username,
    String? password,
    int? port,
  }) async {
    final portPart = port != null ? ':$port' : '';
    final cleanPath = path.endsWith('/') ? path : '$path/';
    _baseUrl = 'https://$host$portPart/$cleanPath';
    _username = username;
    _password = password;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 5);
    try {
      final client = HttpClient()
        ..connectionTimeout = effectiveTimeout;
      final uri = Uri.parse(_baseUrl);
      final request = await client.headUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close().timeout(effectiveTimeout);
      client.close(force: true);
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, data.length);
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      request.headers.set('Content-Type', 'application/octet-stream');
      request.add(data);
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw ArchiveTransportException(
            'HTTP upload failed: Status ${response.statusCode}');
      }
      await response.drain<void>();
      onProgress?.call(data.length, data.length);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw ArchiveTransportException(
            'HTTP download failed: Status ${response.statusCode}');
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      final data = Uint8List.fromList(chunks);
      onProgress?.call(data.length, data.length);
      return data;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    final uri = Uri.parse('$_baseUrl$remotePath/');
    final client = HttpClient();
    try {
      final request = await client.openUrl('MKCOL', uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = HttpClient();
    try {
      final request = await client.headUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = HttpClient();
    try {
      final request = await client.deleteUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    // WebDAV PROPFIND or simple GET on directory.
    final uri = Uri.parse('$_baseUrl$remotePath/');
    final client = HttpClient();
    try {
      final request = await client.openUrl('PROPFIND', uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      request.headers.set('Depth', '1');
      final response = await request.close();
      final body = await response.transform(SystemEncoding().decoder).join();
      // Simple extraction of href entries from WebDAV XML.
      final hrefs = RegExp(r'<D:href>([^<]+)</D:href>').allMatches(body);
      return hrefs.map((m) => m.group(1)!.split('/').last).where((n) => n.isNotEmpty).toList();
    } catch (_) {
      return [];
    } finally {
      client.close(force: true);
    }
  }

  static String _basicAuth(String user, String pass) {
    // Base64-encode user:pass.
    final bytes = '$user:$pass'.codeUnits;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      result.write(chars[(b0 >> 2) & 0x3F]);
      result.write(chars[((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0F)]);
      result.write(i + 1 < bytes.length ? chars[((b1 & 0x0F) << 2) | ((b2 >> 6) & 0x03)] : '=');
      result.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return result.toString();
  }
}

/// Error during archive transport operations.
class ArchiveTransportException implements Exception {
  final String message;
  ArchiveTransportException(this.message);

  @override
  String toString() => 'ArchiveTransportException: $message';
}
