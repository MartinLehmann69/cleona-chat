// Abstract transport layer for Media Auto-Archive.
//
// Supports SMB, SFTP, FTPS and HTTP(S) protocols.
// Each implementation can upload/download files,
// create directories and check connectivity.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/platform/process_runner.dart';

/// Callback for upload/download progress: (bytesTransferred, totalBytes).
typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);

/// How a transport starts its helper process — [ProcessRunner.run] in
/// operation; the probes put a recorder in its place.
typedef ArchiveProcessRun = Future<ProcessResult?> Function(
  String executable,
  List<String> args, {
  required Duration timeout,
  Map<String, String>? environment,
});

Future<ProcessResult?> _defaultRun(String executable, List<String> args,
        {required Duration timeout, Map<String, String>? environment}) =>
    ProcessRunner.run(executable, args,
        timeout: timeout, environment: environment);

/// The file that pins the SFTP host key — one per identity, in its profile
/// (§21.6: "SFTP: the host key"). Not the user's `~/.ssh/known_hosts`: that
/// belongs to the operating-system account, not to this identity.
String archiveKnownHostsPath(String profileDir) =>
    '$profileDir${Platform.pathSeparator}archive_known_hosts';

/// Abstract base for archive transport protocols.
abstract class ArchiveTransport {
  // --- Deadlines -----------------------------------------------------------
  //
  // Every share operation needs a deadline: a NAS that accepts the connection
  // and then no longer answers (frozen SMB service,
  // spun-down NAS, firewall that switches to DROP after session setup) lets
  // smbclient/sftp/ssh/curl hang — none of these tools sets a time limit
  // by default. A FLAT limit, however, would be a new bug: it
  // would cut off large media uploads. Hence three classes.

  /// Connection probes (`testConnectivity`): reachability only, no data.
  static const Duration kProbeTimeout = Duration(seconds: 10);

  /// Metadata operations (mkdir, ls, stat, rm): one round trip plus
  /// connection setup, independent of payload.
  static const Duration kMetadataTimeout = Duration(seconds: 30);

  /// Largest possible payload that can ever land in the archive — derived from
  /// the send limit in `CleonaService.sendMediaMessage` (500 MB). Needed as
  /// the deadline basis for downloads, because there the size is still unknown
  /// at the start of the operation.
  static const int kMaxArchivedFileBytes = 500 * 1024 * 1024;

  /// Data transfer is proportional to size. A flat budget would cut off large
  /// media uploads, so the deadline is derived from the payload
  /// — floor throughput 256 KB/s (realistic worst case: 2.4 GHz Wi-Fi
  /// at the edge of range), 60 s base for connection setup, 2 h ceiling, so that
  /// a stalled transfer never hangs indefinitely. ASSUMPTION about the environment —
  /// correct it here on a field finding, do not guess anew.
  static Duration transferTimeout(int bytes) {
    final sec = 60 + (bytes / (256 * 1024)).ceil();
    return Duration(seconds: sec.clamp(60, 7200));
  }

  /// Deadline for downloads. The payload size is unknown at the start
  /// (the share only delivers it with the headers or not at all), therefore
  /// the largest possible payload is assumed ([kMaxArchivedFileBytes]) —
  /// ~34 min, stays below the 2 h ceiling.
  static Duration get downloadTimeout => transferTimeout(kMaxArchivedFileBytes);

  /// The protocol being used.
  ArchiveProtocol get protocol;

  // --- Share identity (§21.6 security rules, S394) -------------------------

  String? _boundIdentity;

  /// The identity established for this share in this session, or `null`.
  String? get boundIdentity => _boundIdentity;

  /// Records that the share presented [pin] and it was accepted
  /// (confirmed or newly pinned). Call ONLY after [probeIdentity] and
  /// [decideShareIdentity]; `null` withdraws it. TLS transports enforce the
  /// bound pin on every connection.
  void bindIdentity(String? pin) => _boundIdentity = pin;

  /// Every operation that authenticates to the share and moves or changes
  /// data calls this first: without an established identity it refuses —
  /// §21.6 "never write to an unidentified share".
  @protected
  void requireIdentity(String operation) {
    if (_boundIdentity == null) {
      throw ArchiveTransportException('$operation refused: the share '
          'identity is not established (§21.6)');
    }
  }

  /// Asks the share who it is — without moving any archive data.
  ///
  /// [pinned] is the pin in force (`null` = unpinned). SMB uses it to decide
  /// whether a missing marker may be created (unpinned) or is a mismatch
  /// (pinned). The DECISION is [decideShareIdentity], not the transport.
  Future<ShareIdentityProbe> probeIdentity({required String? pinned});

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
  ///
  /// [profileDir] is required: the SFTP host key is pinned in a file of the
  /// identity's profile ([archiveKnownHostsPath]).
  static ArchiveTransport forProtocol(ArchiveProtocol protocol,
      {required String profileDir}) {
    switch (protocol) {
      case ArchiveProtocol.smb:
        return SmbTransport();
      case ArchiveProtocol.sftp:
        return SftpTransport(knownHostsFile: archiveKnownHostsPath(profileDir));
      case ArchiveProtocol.ftps:
        return FtpsTransport();
      case ArchiveProtocol.http:
        return HttpTransport();
    }
  }
}

/// "Test connection" for the settings surface and `archive_test_connection`.
///
/// If the configured share is pinned, its identity is checked FIRST, and a
/// mismatch answers "not reachable" without the reachability probe — so
/// FTPS/HTTPS/SFTP send no credentials to the foreign machine (SMB has
/// already logged in to read the marker; see `SmbTransport`). An unpinned
/// share is tested as before and not pinned here — pinning is the run's
/// job, on first use.
Future<({bool reachable, ShareIdentityState? identity})> testArchiveConnection(
    ArchiveConfig config,
    {required String profileDir,
    Duration timeout = const Duration(seconds: 5)}) async {
  final t = ArchiveTransport.forProtocol(config.defaultProtocol,
      profileDir: profileDir);
  await t.connect(
    host: config.archiveHost,
    path: config.archivePath,
    username: config.archiveUsername,
    password: config.archivePassword,
    port: config.archivePort,
  );
  try {
    final pinned = config.activeShareIdentity;
    ShareIdentityState? identity;
    if (pinned != null) {
      identity = decideShareIdentity(
          pinned: pinned, probe: await t.probeIdentity(pinned: pinned));
      if (identity != ShareIdentityState.confirmed) {
        return (reachable: false, identity: identity);
      }
      t.bindIdentity(pinned);
    }
    return (
      reachable: await t.testConnectivity(timeout: timeout),
      identity: identity
    );
  } finally {
    await t.disconnect();
  }
}

/// SMB/CIFS Transport (via smbclient CLI or dart:io ProcessRun).
///
/// ── WHAT THE MARKER DOES AND DOES NOT DO (§21.6, S394) ─────────────────
///
/// SMB has no host key. The share is identified by the marker file
/// [kShareMarkerPath] (32 random bytes). To READ it, smbclient must log in —
/// so, unlike SFTP/FTPS/HTTPS, the NTLM exchange with the configured
/// credentials has already happened when the marker turns out wrong. What
/// the marker prevents: that a foreign machine answering under the address
/// receives any archived FILE, and that the run deletes an original on its
/// word. What it does not prevent: the foreign machine sees the login
/// attempt (user name, NTLMv2 response — attackable offline), and a machine
/// that relays to the real share passes. The marker is checked once per run
/// and per retrieval, not per smbclient call.
class SmbTransport extends ArchiveTransport {
  SmbTransport({ArchiveProcessRun? run}) : _run = run ?? _defaultRun;

  final ArchiveProcessRun _run;
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

  List<String> _smbArgs(String share, String commands) => [
        '//$_host/$share',
        if (_username != null) ...['-U', _username!],
        '-N',
        '-c',
        commands,
      ];

  Map<String, String>? get _smbEnv =>
      _password != null ? {'PASSWD': _password!} : null;

  File _tmp(String tag) => File('${Directory.systemTemp.path}/cleona_smb_'
      '${tag}_${DateTime.now().microsecondsSinceEpoch}');

  /// Reads the marker: its hex, `''` when the share says it is not there,
  /// `null` when the share could not be asked (login, reachability).
  Future<String?> _readMarker(String share) async {
    final tmp = _tmp('id');
    try {
      final r = await _run('smbclient',
          _smbArgs(share, 'get "$kShareMarkerPath" "${tmp.path}"'),
          environment: _smbEnv, timeout: ArchiveTransport.kMetadataTimeout);
      if (r == null) return null;
      if (r.exitCode == 0 && tmp.existsSync()) {
        final b = tmp.readAsBytesSync();
        if (b.length != kShareMarkerBytes) return null;
        return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      }
      final out = '${r.stdout}${r.stderr}';
      if (out.contains('NT_STATUS_OBJECT_NAME_NOT_FOUND') ||
          out.contains('NT_STATUS_OBJECT_PATH_NOT_FOUND') ||
          out.contains('NT_STATUS_NO_SUCH_FILE')) {
        return '';
      }
      return null;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  @override
  Future<ShareIdentityProbe> probeIdentity({required String? pinned}) async {
    final share = _basePath.split('/').first;
    final found = await _readMarker(share);
    if (found == null) {
      return const ShareIdentityProbe.unavailable(
          'SMB share did not answer the marker read');
    }
    if (found.isNotEmpty) return ShareIdentityProbe.presented('smb:$found');
    // No marker on the share.
    if (pinned != null) {
      return const ShareIdentityProbe.refused(
          'the pinned marker $kShareMarkerPath is missing on this share');
    }
    // Unpinned: this is first use — lay the marker down, then read it back.
    final rnd = Random.secure();
    final tmp = _tmp('new');
    try {
      tmp.writeAsBytesSync(
          List<int>.generate(kShareMarkerBytes, (_) => rnd.nextInt(256)));
      final dir = kShareMarkerPath.substring(0, kShareMarkerPath.indexOf('/'));
      await _run('smbclient', _smbArgs(share, 'mkdir "$dir"'),
          environment: _smbEnv, timeout: ArchiveTransport.kMetadataTimeout);
      await _run('smbclient',
          _smbArgs(share, 'put "${tmp.path}" "$kShareMarkerPath"'),
          environment: _smbEnv, timeout: ArchiveTransport.kMetadataTimeout);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
    final back = await _readMarker(share);
    if (back == null || back.isEmpty) {
      return const ShareIdentityProbe.unavailable(
          'SMB marker could not be written');
    }
    return ShareIdentityProbe.presented('smb:$back', detail: 'marker created');
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? ArchiveTransport.kProbeTimeout;
    try {
      final result = await _run(
        'smbclient',
        [
          '//$_host/${_basePath.split('/').first}',
          '-N', // No password prompt
          if (_username != null) ...['-U', _username!],
          '-c', 'ls',
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
        timeout: effectiveTimeout,
      );
      // null = deadline expired (child was killed) or start failed.
      return result != null && result.exitCode == 0;
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
    requireIdentity('SMB upload');
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

      final deadline = ArchiveTransport.transferTimeout(data.length);
      final result = await _run(
        'smbclient',
        [
          '//$_host/$share',
          if (_username != null) ...['-U', _username!],
          '-N',
          '-c', commands.toString(),
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('SMB upload timed out after '
            '${deadline.inSeconds}s (${data.length} bytes)');
      }
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
    requireIdentity('SMB download');
    final tmpFile = File('${Directory.systemTemp.path}/cleona_download_${DateTime.now().millisecondsSinceEpoch}');
    try {
      final share = _basePath.split('/').first;
      final deadline = ArchiveTransport.downloadTimeout;
      final result = await _run(
        'smbclient',
        [
          '//$_host/$share',
          if (_username != null) ...['-U', _username!],
          '-N',
          '-c', 'get "$remotePath" "${tmpFile.path}"',
        ],
        environment: _password != null ? {'PASSWD': _password!} : null,
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('SMB download timed out after '
            '${deadline.inSeconds}s ($remotePath)');
      }
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
    requireIdentity('SMB mkdir');
    final share = _basePath.split('/').first;
    final parts = remotePath.split('/');
    final commands = StringBuffer();
    var current = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      current = current.isEmpty ? part : '$current/$part';
      commands.writeln('mkdir "$current"');
    }

    // null (deadline) is treated like an exit code != 0: the caller
    // learns of the failure at the next put/ls, just as before.
    await _run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', commands.toString()],
      environment: _password != null ? {'PASSWD': _password!} : null,
      timeout: ArchiveTransport.kMetadataTimeout,
    );
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    requireIdentity('SMB stat');
    final share = _basePath.split('/').first;
    final result = await _run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'ls "$remotePath"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
      timeout: ArchiveTransport.kMetadataTimeout,
    );
    if (result == null) return false; // Deadline == "not demonstrably there"
    return result.exitCode == 0 && !(result.stdout as String).contains('NT_STATUS_NO_SUCH_FILE');
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    requireIdentity('SMB delete');
    final share = _basePath.split('/').first;
    await _run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'rm "$remotePath"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
      timeout: ArchiveTransport.kMetadataTimeout,
    );
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    requireIdentity('SMB list');
    final share = _basePath.split('/').first;
    final result = await _run(
      'smbclient',
      ['//$_host/$share', if (_username != null) ...['-U', _username!], '-N', '-c', 'ls "$remotePath/*"'],
      environment: _password != null ? {'PASSWD': _password!} : null,
      timeout: ArchiveTransport.kMetadataTimeout,
    );
    if (result == null || result.exitCode != 0) return [];
    final lines = (result.stdout as String).split('\n');
    return lines
        .where((l) => l.trim().isNotEmpty && !l.contains('blocks'))
        .map((l) => l.trim().split(RegExp(r'\s+')).first)
        .where((name) => name != '.' && name != '..')
        .toList();
  }
}

/// SFTP Transport (via ssh/sftp CLI).
///
/// The host key is pinned in [knownHostsFile] — one file per identity
/// (§21.6). Every ssh/sftp call carries [_hostKeyArgs]: an unknown host is
/// pinned on first contact (`accept-new`), a CHANGED key makes ssh refuse
/// BEFORE authenticating ("Host key verification failed"). "Rebind" is
/// deleting that file.
class SftpTransport extends ArchiveTransport {
  SftpTransport({required this.knownHostsFile, ArchiveProcessRun? run})
      : _run = run ?? _defaultRun;

  final String knownHostsFile;
  final ArchiveProcessRun _run;
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

  /// The host-key options on EVERY ssh/sftp call.
  ///
  /// * The path is quoted: ssh splits an unquoted option value on blanks
  ///   (`UserKnownHostsFile` takes a list), and profile paths on Windows
  ///   carry them. Measured 24.09.2026, OpenSSH 9.6p1: `ssh -G -o
  ///   'UserKnownHostsFile="/tmp/a b/kh"'` → `userknownhostsfile /tmp/a b/kh`.
  ///   Forward slashes, because the ssh option parser takes `\` as escape.
  /// * `GlobalKnownHostsFile` points at the same file, so that an entry in
  ///   `/etc/ssh/ssh_known_hosts` neither decides nor keeps ssh from
  ///   writing the pin into this identity's file.
  /// * `HashKnownHosts=no`, so the pin can be read back for display;
  ///   `CheckHostIP=no` and `UpdateHostKeys=no`, so the file holds exactly
  ///   the one key ssh met first.
  List<String> get _hostKeyArgs {
    final f = knownHostsFile.replaceAll('\\', '/');
    return [
      '-oUserKnownHostsFile="$f"',
      '-oGlobalKnownHostsFile="$f"',
      '-oStrictHostKeyChecking=accept-new',
      '-oHashKnownHosts=no',
      '-oCheckHostIP=no',
      '-oUpdateHostKeys=no',
    ];
  }

  @override
  Future<ShareIdentityProbe> probeIdentity({required String? pinned}) async {
    final r = await _run('ssh', _sshArgs(['exit', '0']),
        timeout: ArchiveTransport.kMetadataTimeout);
    if (r == null) {
      return const ShareIdentityProbe.unavailable('ssh did not answer');
    }
    final err = '${r.stderr}';
    if (err.contains('REMOTE HOST IDENTIFICATION HAS CHANGED') ||
        err.contains('Host key verification failed')) {
      return const ShareIdentityProbe.refused(
          'ssh refused a changed host key');
    }
    if (r.exitCode != 0) {
      return ShareIdentityProbe.unavailable('ssh exit ${r.exitCode}');
    }
    final f = File(knownHostsFile);
    final fp = f.existsSync()
        ? sshFingerprintFromKnownHosts(f.readAsStringSync(), _host, _port)
        : null;
    if (fp == null) {
      return const ShareIdentityProbe.unavailable(
          'host key not found in the archive known_hosts');
    }
    return ShareIdentityProbe.presented(fp);
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? ArchiveTransport.kProbeTimeout;
    try {
      final target = _username != null ? '$_username@$_host' : _host;
      final result = await _run(
        'sftp',
        ['-P', '$_port', '-oBatchMode=yes', '-oConnectTimeout=3', ..._hostKeyArgs, target],
        timeout: effectiveTimeout,
      );
      if (result == null) return false;
      // sftp returns 0 on success, but even connection test counts
      return result.exitCode == 0 || result.exitCode == 1;
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
    requireIdentity('SFTP upload');
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
      final deadline = ArchiveTransport.transferTimeout(data.length);
      final result = await _run(
        'sftp',
        ['-P', '$_port', ..._hostKeyArgs, '-b', batchFile.path, target],
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('SFTP upload timed out after '
            '${deadline.inSeconds}s (${data.length} bytes)');
      }
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
    requireIdentity('SFTP download');
    final tmpFile = File('${Directory.systemTemp.path}/cleona_sftp_download_${DateTime.now().millisecondsSinceEpoch}');
    final batchFile = File('${Directory.systemTemp.path}/cleona_sftp_dbatch_${DateTime.now().millisecondsSinceEpoch}');
    try {
      final target = _username != null ? '$_username@$_host' : _host;
      await batchFile.writeAsString('get $_basePath$remotePath ${tmpFile.path}\n');

      final deadline = ArchiveTransport.downloadTimeout;
      final result = await _run(
        'sftp',
        ['-P', '$_port', ..._hostKeyArgs, '-b', batchFile.path, target],
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('SFTP download timed out after '
            '${deadline.inSeconds}s ($remotePath)');
      }
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

  /// Build `ssh` args for a one-shot remote command.
  ///
  /// `BatchMode=yes` is not cosmetics: without the option ssh may wait for a
  /// passphrase or host key confirmation, and such a process
  /// can only be ended via SIGKILL instead of cleanly. `ConnectTimeout=5`
  /// bounds the TCP phase, so that the 30 s metadata deadline benefits the actual
  /// command and not a mute port.
  List<String> _sshArgs(List<String> command) {
    final target = _username != null ? '$_username@$_host' : _host;
    return [
      '-p', '$_port',
      '-oBatchMode=yes',
      '-oConnectTimeout=5',
      ..._hostKeyArgs,
      target,
      ...command,
    ];
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    requireIdentity('SFTP mkdir');
    // null (deadline) is treated like an exit code != 0 — as before,
    // the exit code is not evaluated here.
    await _run(
      'ssh',
      _sshArgs(['mkdir', '-p', '$_basePath$remotePath']),
      timeout: ArchiveTransport.kMetadataTimeout,
    );
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    requireIdentity('SFTP stat');
    final result = await _run(
      'ssh',
      _sshArgs(['test', '-f', '$_basePath$remotePath']),
      timeout: ArchiveTransport.kMetadataTimeout,
    );
    return result != null && result.exitCode == 0;
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    requireIdentity('SFTP delete');
    await _run(
      'ssh',
      _sshArgs(['rm', '-f', '$_basePath$remotePath']),
      timeout: ArchiveTransport.kMetadataTimeout,
    );
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    requireIdentity('SFTP list');
    final result = await _run(
      'ssh',
      _sshArgs(['ls', '$_basePath$remotePath']),
      timeout: ArchiveTransport.kMetadataTimeout,
    );
    if (result == null || result.exitCode != 0) return [];
    return (result.stdout as String).split('\n').where((l) => l.trim().isNotEmpty).toList();
  }
}

/// FTPS Transport (via curl CLI).
///
/// Implicit TLS (`ftps://`, default port 990) — the only mode this
/// transport speaks; there is no explicit `AUTH TLS` path, so the identity
/// probe opens TLS directly as well. The server key is pinned on first use
/// ([tlsPinOf]) and every curl call carries `--pinnedpubkey`, which curl
/// checks after the handshake and BEFORE it sends `USER`/`PASS`. curl's CA
/// check stays as it was (§21.6 asks for the pin, not for dropping it).
class FtpsTransport extends ArchiveTransport {
  FtpsTransport({ArchiveProcessRun? run, this._context})
      : _run = run ?? _defaultRun;

  final ArchiveProcessRun _run;
  final SecurityContext? _context;
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

  /// Build curl args with --netrc-file (if credentials exist) and the
  /// bound pin prepended. Every curl call of this class goes through here.
  List<String> _curlArgs(File? netrcFile, List<String> rest) {
    final pin = boundIdentity;
    return [
      if (pin != null) ...['--pinnedpubkey', pin],
      if (netrcFile != null) ...['--netrc-file', netrcFile.path],
      ...rest,
    ];
  }

  @override
  Future<ShareIdentityProbe> probeIdentity({required String? pinned}) =>
      probeTlsIdentity(_host, _port, _context);

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? ArchiveTransport.kProbeTimeout;
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--list-only', '--connect-timeout', '3',
         'ftps://$_host:$_port/$_basePath']),
        timeout: effectiveTimeout,
      );
      return result != null && result.exitCode == 0;
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
    requireIdentity('FTPS upload');
    final tmpFile = File('${Directory.systemTemp.path}/cleona_ftps_upload_${DateTime.now().millisecondsSinceEpoch}');
    File? netrc;
    try {
      await tmpFile.writeAsBytes(data);
      onProgress?.call(0, data.length);

      netrc = _createNetrcFile();
      final deadline = ArchiveTransport.transferTimeout(data.length);
      final result = await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-T', tmpFile.path, '--ftp-create-dirs',
         'ftps://$_host:$_port/$_basePath$remotePath']),
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('FTPS upload timed out after '
            '${deadline.inSeconds}s (${data.length} bytes)');
      }
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
    requireIdentity('FTPS download');
    final tmpFile = File('${Directory.systemTemp.path}/cleona_ftps_download_${DateTime.now().millisecondsSinceEpoch}');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final deadline = ArchiveTransport.downloadTimeout;
      final result = await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-o', tmpFile.path,
         'ftps://$_host:$_port/$_basePath$remotePath']),
        timeout: deadline,
      );

      if (result == null) {
        throw ArchiveTransportException('FTPS download timed out after '
            '${deadline.inSeconds}s ($remotePath)');
      }
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
    requireIdentity('FTPS mkdir');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      // null (deadline) is treated like an exit code != 0 — as before,
      // the exit code is not evaluated here.
      await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-Q', 'MKD $remotePath',
         'ftps://$_host:$_port/$_basePath']),
        timeout: ArchiveTransport.kMetadataTimeout,
      );
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    requireIdentity('FTPS stat');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--head', '--silent',
         'ftps://$_host:$_port/$_basePath$remotePath']),
        timeout: ArchiveTransport.kMetadataTimeout,
      );
      return result != null && result.exitCode == 0;
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    requireIdentity('FTPS delete');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '-Q', 'DELE $remotePath',
         'ftps://$_host:$_port/$_basePath']),
        timeout: ArchiveTransport.kMetadataTimeout,
      );
    } finally {
      _cleanupNetrc(netrc);
    }
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    requireIdentity('FTPS list');
    File? netrc;
    try {
      netrc = _createNetrcFile();
      final result = await _run(
        'curl',
        _curlArgs(netrc, ['--ssl-reqd', '--list-only',
         'ftps://$_host:$_port/$_basePath$remotePath/']),
        timeout: ArchiveTransport.kMetadataTimeout,
      );
      if (result == null || result.exitCode != 0) return [];
      return (result.stdout as String).split('\n').where((l) => l.trim().isNotEmpty).toList();
    } finally {
      _cleanupNetrc(netrc);
    }
  }
}

/// Opens TLS to [host]:[port] and reports the server's key pin
/// ([tlsPinOf]). Sends nothing over the connection — no credentials, no
/// request. The CA check is the platform default, unchanged (a certificate
/// the trust store rejects ends as "unavailable", not as a pin).
Future<ShareIdentityProbe> probeTlsIdentity(
    String host, int port, SecurityContext? context) async {
  SecureSocket? s;
  try {
    s = await SecureSocket.connect(host, port,
        context: context, timeout: ArchiveTransport.kProbeTimeout);
    final pin = tlsPinOf(s.peerCertificate);
    return pin == null
        ? const ShareIdentityProbe.unavailable('no parsable certificate')
        : ShareIdentityProbe.presented(pin);
  } catch (e) {
    return ShareIdentityProbe.unavailable('TLS: $e');
  } finally {
    s?.destroy();
  }
}

/// HTTP(S) Transport (via curl/HTTP PUT/GET — WebDAV-compatible).
///
/// dart:io, not curl. The pin is enforced in [HttpClient.connectionFactory]:
/// the TLS socket is opened here, its key compared with the bound pin, and
/// only a matching socket is handed to the client — a mismatch throws
/// before a single HTTP byte (and the `Authorization` header) leaves.
class HttpTransport extends ArchiveTransport {
  HttpTransport({this._context});

  final SecurityContext? _context;
  String _host = '';
  int _port = 443;
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
    _host = host;
    _port = port ?? 443;
    _baseUrl = 'https://$host$portPart/$cleanPath';
    _username = username;
    _password = password;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<ShareIdentityProbe> probeIdentity({required String? pinned}) =>
      probeTlsIdentity(_host, _port, _context);

  /// Every HttpClient of this class. With a bound pin, the connection is
  /// made here and checked before the client may use it.
  ///
  /// With a pin the connection is DIRECT: the factory opens TLS to the
  /// share itself, which a proxy tunnel (CONNECT) would bypass. Without a pin
  /// the dart:io default (proxy from the environment) stays.
  HttpClient _client(Duration connectionTimeout) {
    final c = HttpClient(context: _context)
      ..connectionTimeout = connectionTimeout;
    final pin = boundIdentity;
    if (pin != null) {
      c.findProxy = (_) => 'DIRECT';
      c.connectionFactory = (uri, proxyHost, proxyPort) async {
        final task = await SecureSocket.startConnect(uri.host, uri.port,
            context: _context);
        return ConnectionTask.fromSocket(
            task.socket.then((sock) {
              final got = tlsPinOf(sock.peerCertificate);
              if (got != pin) {
                sock.destroy();
                throw ShareIdentityMismatchException(
                    'HTTPS server key $got is not the pinned $pin');
              }
              return sock;
            }),
            task.cancel);
      };
    }
    return c;
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? ArchiveTransport.kProbeTimeout;
    try {
      final client = _client(effectiveTimeout);
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
    requireIdentity('HTTP upload');
    onProgress?.call(0, data.length);
    final uri = Uri.parse('$_baseUrl$remotePath');
    final deadline = ArchiveTransport.transferTimeout(data.length);
    // connectionTimeout only covers the TCP/TLS phase; a WebDAV server that
    // accepts the connection and then stays mute additionally needs a
    // deadline on request.close(). client.close(force: true) in the finally tears
    // down the socket — the HTTP counterpart of SIGKILL for child processes.
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.putUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      request.headers.set('Content-Type', 'application/octet-stream');
      request.add(data);
      final response = await request.close().timeout(deadline);
      if (response.statusCode >= 400) {
        throw ArchiveTransportException(
            'HTTP upload failed: Status ${response.statusCode}');
      }
      await response.drain<void>().timeout(ArchiveTransport.kMetadataTimeout);
      onProgress?.call(data.length, data.length);
    } on TimeoutException {
      throw ArchiveTransportException('HTTP upload timed out after '
          '${deadline.inSeconds}s (${data.length} bytes)');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    requireIdentity('HTTP download');
    final uri = Uri.parse('$_baseUrl$remotePath');
    final deadline = ArchiveTransport.downloadTimeout;
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.getUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response = await request.close().timeout(deadline);
      if (response.statusCode >= 400) {
        throw ArchiveTransportException(
            'HTTP download failed: Status ${response.statusCode}');
      }
      // Reading the body needs its own deadline: request.close()
      // already returns after the response headers, the hang of a
      // mute server only happens here.
      final chunks = await response
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
          .timeout(deadline);
      final data = Uint8List.fromList(chunks);
      onProgress?.call(data.length, data.length);
      return data;
    } on TimeoutException {
      throw ArchiveTransportException('HTTP download timed out after '
          '${deadline.inSeconds}s ($remotePath)');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    requireIdentity('HTTP mkdir');
    final uri = Uri.parse('$_baseUrl$remotePath/');
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.openUrl('MKCOL', uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response =
          await request.close().timeout(ArchiveTransport.kMetadataTimeout);
      await response.drain<void>().timeout(ArchiveTransport.kMetadataTimeout);
    } on TimeoutException {
      // Like an error status: the exit of this operation is — as before —
      // not evaluated, the failure shows at the next PUT.
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    requireIdentity('HTTP stat');
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.headUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response =
          await request.close().timeout(ArchiveTransport.kMetadataTimeout);
      await response.drain<void>().timeout(ArchiveTransport.kMetadataTimeout);
      return response.statusCode == 200;
    } catch (_) {
      // Also covers TimeoutException: deadline == "not demonstrably there".
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    requireIdentity('HTTP delete');
    final uri = Uri.parse('$_baseUrl$remotePath');
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.deleteUrl(uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      final response =
          await request.close().timeout(ArchiveTransport.kMetadataTimeout);
      await response.drain<void>().timeout(ArchiveTransport.kMetadataTimeout);
    } on TimeoutException {
      // Like an error status: the exit of this operation was not evaluated
      // before either.
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    requireIdentity('HTTP list');
    // WebDAV PROPFIND or simple GET on directory.
    final uri = Uri.parse('$_baseUrl$remotePath/');
    final client = _client(ArchiveTransport.kProbeTimeout);
    try {
      final request = await client.openUrl('PROPFIND', uri);
      if (_username != null) {
        request.headers.set('Authorization',
            'Basic ${_basicAuth(_username!, _password ?? '')}');
      }
      request.headers.set('Depth', '1');
      final response =
          await request.close().timeout(ArchiveTransport.kMetadataTimeout);
      // The body too needs its own deadline — request.close() returns
      // already after the headers.
      final body = await response
          .transform(SystemEncoding().decoder)
          .join()
          .timeout(ArchiveTransport.kMetadataTimeout);
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
