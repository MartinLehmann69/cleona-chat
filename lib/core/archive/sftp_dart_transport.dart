// SFTP for the media archive in Dart — §21.6 "Protocols: SMB/CIFS and SFTP
// (mandatory)", S423 A-1. Used on Android/iOS, which ship no `ssh`/`sftp`
// program, and on the desktop when a share password is set (the programs
// run with `BatchMode=yes` and cannot log in with a password); which one
// runs is decided in `ArchiveTransport.forProtocol`.
//
// Library: `dartssh2` 4.1.0 (pub.dev, MIT licence, pure Dart without FFI,
// 160/160 pub points; transitive: pointycastle 4.0.0 (Bouncy Castle
// licence, MIT-type), pinenacl 0.6.0 (MIT), asn1lib 1.6.8 (BSD-2-Clause);
// checked 14.11.2026).
//
// Behaviour kept equal to `SftpTransport` (the `ssh`/`sftp` programs used
// on Linux, Windows and macOS):
// * Host key: pinned per identity in the same file
//   ([archiveKnownHostsPath]); an unknown host is pinned on first contact
//   (OpenSSH `accept-new`), a CHANGED key is refused inside the key
//   exchange, BEFORE any credential is sent. Rebind = deleting that file
//   (`ArchiveManager.forgetSftpHostKey`).
// * One connection per operation, closed when it ends — like one program
//   run per operation; nothing stays open between archive runs and no
//   keep-alive is sent (§1.2 rule: nothing periodic while idle).
// * The deadlines of [ArchiveTransport] (probe / metadata / transfer).
//
// Login: the identity's own SSH key (`SftpClientKey`, kept in the identity's
// encrypted store), on the desktop also the account's default keys
// ([accountSshKeyPems]), and/or the share password (`ArchiveConfig.
// archivePassword`, same store). Neither secret is ever written anywhere
// else.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/log/clogger.dart';

/// Opens the TCP connection the SSH session runs on. The probes put a
/// connector to a local socket in its place.
typedef SshSocketConnect = Future<SSHSocket> Function(String host, int port,
    {Duration? timeout});

/// What the pin file says about a host key the server presented.
enum SshHostKeyVerdict {
  /// The presented key is the pinned one.
  known,

  /// No key is pinned for this host: pin it (OpenSSH `accept-new`).
  pinNew,

  /// Another key is pinned for this host: refuse before authenticating.
  changed,
}

/// The OpenSSH fingerprint text of a SHA-256 host-key digest:
/// `SHA256:<base64 without padding>` — the form `ssh-keygen -l` prints and
/// [sshFingerprintFromKnownHosts] returns, so pins taken by either
/// transport compare equal.
String sshFingerprintText(List<int> sha256Digest) =>
    'SHA256:${base64.encode(sha256Digest).replaceAll('=', '')}';

/// The fingerprints pinned for [host]:[port] in the pin file [text].
///
/// Reads both line forms the file can hold: the one OpenSSH writes
/// (`name keytype base64-key`, fingerprint computed) and the one
/// [DartSftpTransport] writes (`name keytype SHA256:…`; the library hands
/// out the key's digest, not the key). OpenSSH skips a line of the second
/// form as unreadable, so a file never misleads the other transport into
/// trusting a key.
List<String> pinnedSshFingerprints(String text, String host, int port) {
  final name = knownHostsName(host, port);
  final out = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('@')) continue;
    final f = line.split(RegExp(r'\s+'));
    if (f.length < 3 || !f[0].split(',').contains(name)) continue;
    if (f[2].startsWith('SHA256:')) {
      out.add(f[2]);
    } else {
      final fp = sshFingerprintFromKnownHosts('${f[0]} ${f[1]} ${f[2]}', host, port);
      if (fp != null) out.add(fp);
    }
  }
  return out;
}

/// The ONE host-key decision of [DartSftpTransport]. A host with any pinned
/// key that differs from [fingerprint] is [SshHostKeyVerdict.changed] —
/// stricter than OpenSSH, which compares per key type; the file only ever
/// holds the one key met first (`UpdateHostKeys=no` on the program side).
SshHostKeyVerdict sshHostKeyVerdict(
    String? pinFileText, String host, int port, String fingerprint) {
  final pinned = pinFileText == null
      ? const <String>[]
      : pinnedSshFingerprints(pinFileText, host, port);
  if (pinned.isEmpty) return SshHostKeyVerdict.pinNew;
  return pinned.every((p) => p == fingerprint)
      ? SshHostKeyVerdict.known
      : SshHostKeyVerdict.changed;
}

// ── One pin file, two transports (desktop, S423) ───────────────────────
//
// On the desktop both transports serve the same identity: the programs
// without a password, [DartSftpTransport] with one. The Dart transport can
// only write a fingerprint line (the library hands out the digest, not the
// key). OpenSSH does not read such a line — with `accept-new` it would treat
// the host as unknown, pin WHATEVER key answers and log in to it. So the
// program side never meets a fingerprint line unprepared: before a call it
// fetches the host's keys WITHOUT logging in (`ssh-keyscan`), and only a
// key whose fingerprint is the pinned one replaces the line, in OpenSSH
// form. A different key is a changed host; no answer leaves the line and
// runs ssh with `StrictHostKeyChecking=yes`, which refuses before login.

/// What reconciling the fingerprint lines with the host's keys found.
enum SshPinUpgrade {
  /// No fingerprint line for this host: nothing to do.
  none,

  /// Every fingerprint line was confirmed and replaced by the key.
  upgraded,

  /// The host presents keys, none of them the pinned one.
  changed,

  /// The host's keys could not be fetched; the pin stays unconfirmed.
  unconfirmed,
}

/// The fingerprint-only lines ([DartSftpTransport]'s form) for
/// [host]:[port] in the pin file [text].
List<String> fingerprintOnlyPins(String text, String host, int port) {
  final name = knownHostsName(host, port);
  return [
    for (final raw in const LineSplitter().convert(text))
      if (_fingerprintLineFor(raw.trim(), name) != null)
        _fingerprintLineFor(raw.trim(), name)!
  ];
}

String? _fingerprintLineFor(String line, String name) {
  if (line.isEmpty || line.startsWith('#') || line.startsWith('@')) return null;
  final f = line.split(RegExp(r'\s+'));
  if (f.length < 3 || !f[0].split(',').contains(name)) return null;
  return f[2].startsWith('SHA256:') ? f[2] : null;
}

/// Replaces the fingerprint lines for [host]:[port] in [text] by the key
/// from [keyscanOutput] (`ssh-keyscan` output, `null` = none) that has that
/// fingerprint. Writes nothing unless EVERY such line is confirmed.
({SshPinUpgrade result, String? text}) upgradeFingerprintPins(
    String text, String host, int port, String? keyscanOutput) {
  final name = knownHostsName(host, port);
  final pins = fingerprintOnlyPins(text, host, port);
  if (pins.isEmpty) return (result: SshPinUpgrade.none, text: null);
  // The scanned keys by fingerprint: `name type base64` per line.
  final scanned = <String, String>{};
  for (final raw in const LineSplitter().convert(keyscanOutput ?? '')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final f = line.split(RegExp(r'\s+'));
    if (f.length < 3 || !f[0].split(',').contains(name)) continue;
    final fp = sshFingerprintFromKnownHosts('$name ${f[1]} ${f[2]}', host, port);
    if (fp != null) scanned[fp] = '$name ${f[1]} ${f[2]}';
  }
  if (scanned.isEmpty) return (result: SshPinUpgrade.unconfirmed, text: null);
  if (!pins.every(scanned.containsKey)) {
    return (result: SshPinUpgrade.changed, text: null);
  }
  final out = StringBuffer();
  for (final raw in const LineSplitter().convert(text)) {
    final fp = _fingerprintLineFor(raw.trim(), name);
    out.writeln(fp == null ? raw : scanned[fp]);
  }
  return (result: SshPinUpgrade.upgraded, text: out.toString());
}

/// The operating-system account's default SSH keys that open without a
/// passphrase (`~/.ssh/id_ed25519`, `id_ecdsa`, `id_rsa` — the default
/// identity files of ssh(1)), as PEM texts. Used on the desktop when the
/// Dart transport runs (a password is set), so that the account's key login
/// keeps working there. A key with a passphrase or an unreadable file is
/// skipped — ssh runs with `BatchMode=yes` and cannot ask either; keys only
/// held by `ssh-agent` are not reached.
List<String> accountSshKeyPems({String? home}) {
  final h = home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (h == null) return const [];
  final out = <String>[];
  for (final n in const ['id_ed25519', 'id_ecdsa', 'id_rsa']) {
    final f = File('$h${Platform.pathSeparator}.ssh${Platform.pathSeparator}$n');
    try {
      if (!f.existsSync()) continue;
      final pem = f.readAsStringSync();
      if (SSHKeyPair.isEncryptedPem(pem)) continue;
      SSHKeyPair.fromPem(pem); // readable at all (format supported)
      out.add(pem);
    } catch (_) {}
  }
  return out;
}

/// SFTP through `dartssh2` (see the file comment).
class DartSftpTransport extends ArchiveTransport {
  DartSftpTransport({
    required this.knownHostsFile,
    required String profileDir,
    this._clientKey,
    this.accountKeys,
    SshSocketConnect? connectSocket,
  })  : _connectSocket = connectSocket ?? SSHSocket.connect,
        _log = CLogger.get('archive-sftp', profileDir: profileDir);

  /// The identity's pin file ([archiveKnownHostsPath]).
  final String knownHostsFile;

  /// The operating-system account's keys, read at each session — set on
  /// the desktop ([accountSshKeyPems]), `null` on Android/iOS.
  final List<String> Function()? accountKeys;

  /// Reads the identity's own SSH key at each session — a key created
  /// while the archive runs takes effect at the next operation, without
  /// rebuilding the transport.
  final String? Function()? _clientKey;

  /// The identity's own SSH key (OpenSSH PEM) as of now, or `null`.
  String? get clientKeyPem => _clientKey?.call();

  final SshSocketConnect _connectSocket;
  final CLogger _log;

  /// Bounds the TCP phase, as `ConnectTimeout=5` does for the program.
  static const Duration kConnectTimeout = Duration(seconds: 5);

  String _host = '';
  String _basePath = '';
  String? _username;
  String? _password;
  int _port = 22;

  /// Set by the host-key check of the last session: the server presented
  /// another key than the pinned one.
  bool _refusedChangedKey = false;

  /// The fingerprint the server presented in the last session.
  String? _presented;

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
    _password = (password ?? '').isEmpty ? null : password;
    _port = port ?? 22;
  }

  @override
  Future<void> disconnect() async {}

  /// Called inside the key exchange, before authentication.
  Future<bool> _verifyHostKey(String type, Uint8List digest) async {
    final fp = sshFingerprintText(digest);
    _presented = fp;
    final f = File(knownHostsFile);
    final text = f.existsSync() ? f.readAsStringSync() : null;
    switch (sshHostKeyVerdict(text, _host, _port, fp)) {
      case SshHostKeyVerdict.known:
        return true;
      case SshHostKeyVerdict.pinNew:
        f.writeAsStringSync('${knownHostsName(_host, _port)} $type $fp\n',
            mode: FileMode.append, flush: true);
        _log.info('SFTP host key pinned on first contact: $fp');
        return true;
      case SshHostKeyVerdict.changed:
        _refusedChangedKey = true;
        _log.warn('SFTP host key CHANGED ($fp) — refused before '
            'authenticating (§21.6)');
        return false;
    }
  }

  /// The keys offered for login: the identity's own, then the account's.
  List<SSHKeyPair>? _identities() {
    final out = <SSHKeyPair>[];
    final pem = clientKeyPem;
    if (pem != null && pem.isNotEmpty) {
      try {
        out.addAll(SSHKeyPair.fromPem(pem));
      } catch (e) {
        _log.warn('SFTP: the identity\'s SSH key cannot be read: '
            '${e.runtimeType}');
      }
    }
    for (final p in accountKeys?.call() ?? const <String>[]) {
      try {
        out.addAll(SSHKeyPair.fromPem(p));
      } catch (_) {}
    }
    return out.isEmpty ? null : out;
  }

  /// Runs [body] on a fresh SFTP session under [deadline] and closes the
  /// connection afterwards, whatever happens. Every failure is logged with
  /// the operation [op] — S423 A-1: a failure without a log line is not
  /// diagnosable.
  Future<T> _session<T>(String op, Duration deadline,
      Future<T> Function(SftpClient sftp) body) async {
    _refusedChangedKey = false;
    _presented = null;
    SSHClient? client;
    try {
      return await () async {
        final socket =
            await _connectSocket(_host, _port, timeout: kConnectTimeout);
        final password = _password;
        client = SSHClient(
          socket,
          username: _username ??
              Platform.environment['USER'] ??
              Platform.environment['USERNAME'] ??
              '',
          onVerifyHostKey: _verifyHostKey,
          identities: _identities(),
          onPasswordRequest: password == null ? null : () => password,
          // Servers that offer only keyboard-interactive ask for the same
          // password through it; anything beyond hidden prompts is refused.
          onUserInfoRequest: password == null
              ? null
              : (req) => req.prompts.isNotEmpty &&
                      req.prompts.every((p) => !p.echo)
                  ? List.filled(req.prompts.length, password)
                  : null,
          keepAliveInterval: null,
        );
        return await body(await client!.sftp());
      }()
          .timeout(deadline);
    } on TimeoutException {
      _log.warn('SFTP $op: no answer within ${deadline.inSeconds}s '
          '($_host:$_port)');
      rethrow;
    } catch (e) {
      _log.warn('SFTP $op failed ($_host:$_port): ${_describe(e)}');
      rethrow;
    } finally {
      // Closing the client closes the SFTP channel with it.
      try {
        await client?.close();
      } catch (_) {}
    }
  }

  /// A failure as text without credentials: dartssh2 errors carry the
  /// server's message, socket errors the OS message.
  static String _describe(Object e) {
    if (e is SSHAuthFailError) return 'login refused: ${e.message}';
    // Not a refusal: the connection ended before the login was through
    // (closed by the server, a refused host key, a network error).
    if (e is SSHAuthAbortError) {
      return '${e.message}${e.reason != null ? ' (${e.reason})' : ''}';
    }
    if (e is SftpStatusError) return 'SFTP status ${e.code}: ${e.message}';
    if (e is SocketException) return 'socket: ${e.message} ${e.osError ?? ''}';
    return '${e.runtimeType}: $e';
  }

  @override
  Future<ShareIdentityProbe> probeIdentity({required String? pinned}) async {
    try {
      await _session('identity probe', ArchiveTransport.kMetadataTimeout,
          _awaitHandshake);
    } catch (e) {
      if (_refusedChangedKey) {
        return const ShareIdentityProbe.refused(
            'ssh refused a changed host key');
      }
      return ShareIdentityProbe.unavailable('sftp: ${_describe(e)}');
    }
    final fp = _presented;
    if (fp == null) {
      return const ShareIdentityProbe.unavailable(
          'host key not seen in the key exchange');
    }
    return ShareIdentityProbe.presented(fp);
  }

  @override
  Future<bool> testConnectivity({Duration? timeout}) async {
    try {
      await _session('connection test',
          timeout ?? ArchiveTransport.kProbeTimeout, _awaitHandshake);
      return true;
    } catch (_) {
      return false; // logged in _session
    }
  }

  /// The body of a session that only proves the connection: it waits for the
  /// server's answer to "subsystem sftp" before the session closes. With an
  /// empty body the client closed while that answer was still due, and
  /// dartssh2 4.1.0 (the subsystem request of `SSHClient`, not awaited by
  /// `sftp()`) raised an unhandled
  /// `SSHStateError(SSH client closed)` — the crash dialog covered the result
  /// of "Verbindung testen" although the login had been accepted (S429 run 5,
  /// AVM 23.A01: Gen8 "Accepted password for cleona" 00:45:57;
  /// S429-RCA-L5-23A01-60A06.md).
  static Future<void> _awaitHandshake(SftpClient sftp) async {
    await sftp.handshake;
  }

  String _remote(String remotePath) => '$_basePath$remotePath';

  /// `mkdir -p`: every missing level, an existing one is not an error.
  Future<void> _mkdirs(SftpClient sftp, String dir) async {
    final abs = dir.startsWith('/');
    final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
    var cur = abs ? '' : '.';
    for (final p in parts) {
      cur = '$cur/$p';
      try {
        await sftp.mkdir(cur);
      } catch (_) {
        // Exists already (or not creatable — the write after it reports).
      }
    }
  }

  @override
  Future<void> uploadFile(
    Uint8List data,
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    requireIdentity('SFTP upload');
    final deadline = ArchiveTransport.transferTimeout(data.length);
    final target = _remote(remotePath);
    try {
      await _session('upload', deadline, (sftp) async {
        onProgress?.call(0, data.length);
        final slash = target.lastIndexOf('/');
        if (slash > 0) await _mkdirs(sftp, target.substring(0, slash));
        final file = await sftp.open(target,
            mode: SftpFileOpenMode.create |
                SftpFileOpenMode.truncate |
                SftpFileOpenMode.write);
        try {
          await file
              .write(Stream.value(data),
                  onProgress: (n) => onProgress?.call(n, data.length))
              .done;
        } finally {
          await file.close();
        }
        onProgress?.call(data.length, data.length);
      });
    } on TimeoutException {
      throw ArchiveTransportException('SFTP upload timed out after '
          '${deadline.inSeconds}s (${data.length} bytes)');
    } catch (e) {
      throw ArchiveTransportException('SFTP upload failed: ${_describe(e)}');
    }
  }

  @override
  Future<Uint8List> downloadFile(
    String remotePath, {
    ProgressCallback? onProgress,
  }) async {
    requireIdentity('SFTP download');
    final deadline = ArchiveTransport.downloadTimeout;
    try {
      return await _session('download', deadline, (sftp) async {
        final file = await sftp.open(_remote(remotePath));
        try {
          final out = BytesBuilder(copy: false);
          await for (final chunk in file.read()) {
            out.add(chunk);
          }
          final bytes = out.takeBytes();
          onProgress?.call(bytes.length, bytes.length);
          return bytes;
        } finally {
          await file.close();
        }
      });
    } on TimeoutException {
      throw ArchiveTransportException('SFTP download timed out after '
          '${deadline.inSeconds}s ($remotePath)');
    } catch (e) {
      throw ArchiveTransportException(
          'SFTP download failed: ${_describe(e)}');
    }
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    requireIdentity('SFTP mkdir');
    // As with the program: a failure is not raised here — the upload
    // after it reports.
    try {
      await _session('mkdir', ArchiveTransport.kMetadataTimeout,
          (sftp) => _mkdirs(sftp, _remote(remotePath)));
    } catch (_) {}
  }

  @override
  Future<bool> fileExists(String remotePath) async {
    requireIdentity('SFTP stat');
    try {
      return await _session('stat', ArchiveTransport.kMetadataTimeout,
          (sftp) async {
        try {
          // `test -f`: a regular file, not a directory.
          return (await sftp.stat(_remote(remotePath))).isFile;
        } on SftpStatusError catch (e) {
          if (e.code == SftpStatusCode.noSuchFile) return false;
          rethrow;
        }
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    requireIdentity('SFTP delete');
    // `rm -f`: a missing file is not an error, and as with the program the
    // outcome is not raised.
    try {
      await _session('delete', ArchiveTransport.kMetadataTimeout,
          (sftp) async {
        try {
          await sftp.remove(_remote(remotePath));
        } on SftpStatusError catch (e) {
          if (e.code != SftpStatusCode.noSuchFile) rethrow;
        }
      });
    } catch (_) {}
  }

  @override
  Future<List<String>> listDirectory(String remotePath) async {
    requireIdentity('SFTP list');
    try {
      return await _session('list', ArchiveTransport.kMetadataTimeout,
          (sftp) async {
        final names = await sftp.listdir(_remote(remotePath));
        // `ls`: no `.`/`..`, no hidden entries.
        return [
          for (final n in names)
            if (!n.filename.startsWith('.')) n.filename
        ];
      });
    } catch (_) {
      return [];
    }
  }
}
