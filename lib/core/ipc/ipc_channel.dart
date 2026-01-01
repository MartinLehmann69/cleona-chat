// The protected connection between daemon and GUI (S403, step 2;
// v4_2 §22.1 "IPC protection", §23.10, Appendix D D-52).
//
// "The connection is authenticated in both directions and encrypted, on
// every desktop platform alike. Its secret — 32 random bytes — is drawn
// once, when the device database is created, and lives there (§21.4.1);
// daemon and GUI both read it from the database. On connecting, both sides
// send 32 random bytes and derive one key per direction from the secret and
// both values; the secret itself never travels. From then on every request,
// response and event is sealed, and a side that cannot open the first
// sealed line closes the connection. There is no unencrypted mode, in no
// build; tools and tests connect through the same exchange."
//
// ── THE BUILDING BLOCKS — NOTHING OF OUR OWN ──────────────────────────────
//
// Two primitives the project already uses, both from libsodium
// (`sodium_ffi.dart`):
//
//  * HKDF-SHA256 (RFC 5869) derives the two direction keys:
//      okm = HKDF(ikm = secret, salt = nonce_client ‖ nonce_server,
//                 info = "cleona-ipc-v1", 64 bytes)
//      key client→daemon = okm[0..32), key daemon→client = okm[32..64).
//    Fresh nonces of BOTH sides make the keys of every connection new: a
//    line recorded on one connection opens on no other.
//  * XSalsa20-Poly1305 (`crypto_secretbox`, the same AEAD as the files of
//    form 2, §4.5.3) seals each line. The nonce is a counter per direction
//    (8 bytes little endian, 16 zero bytes); the receiver expects exactly
//    the next value. A repeated, dropped or reordered line does not open,
//    and the connection is closed.
//
// ── THE EXCHANGE ──────────────────────────────────────────────────────────
//
//   client → daemon   {"cleona_ipc":1,"nonce":"<32 bytes, base64>"}     open
//   daemon → client   {"cleona_ipc":1,"nonce":"<32 bytes, base64>"}     open
//   daemon → client   seal({"type":"ready","cleona_ipc":1})            proof of the daemon
//   client → daemon   seal(<first request>)                              proof of the client
//   …                 every further line sealed, in both directions
//
// Lines stay lines: a sealed line is the base64 of the box, ended by "\n",
// so the framing of both programs is unchanged. The daemon executes nothing
// before a sealed line opened, and the client sends nothing before the
// daemon's first sealed line opened — each side has proven the secret to
// the other before it acts on what the other says.
//
// The open hello carries no secret and nothing about one. It does tell a
// caller that a Cleona daemon listens — which `ipc_probe.dart` uses for the
// question "is this port mine?" without needing the secret.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// Version of the exchange; carried in the open hello.
const int kIpcProtocolVersion = 1;

const String _kdfInfo = 'cleona-ipc-v1';
const int _nonceLength = 32;
const int _secretLength = 32;

/// The line the daemon seals first — the proof that it holds the secret.
const String kIpcReadyLine = '{"type":"ready","cleona_ipc":1}';

class IpcChannelException implements Exception {
  final String message;
  const IpcChannelException(this.message);
  @override
  String toString() => 'IpcChannelException: $message';
}

/// The open hello of either side.
class IpcHello {
  IpcHello._();

  /// 32 fresh random bytes.
  static Uint8List freshNonce() => SodiumFFI().randomBytes(_nonceLength);

  /// The hello line for [nonce], without the line end.
  static String line(Uint8List nonce) =>
      jsonEncode({'cleona_ipc': kIpcProtocolVersion, 'nonce': base64Encode(nonce)});

  /// The nonce of a hello line, or `null` if [line] is not one of this
  /// version.
  static Uint8List? parse(String line) {
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;
      if (json['cleona_ipc'] != kIpcProtocolVersion) return null;
      final nonce = base64Decode(json['nonce'] as String);
      return nonce.length == _nonceLength ? nonce : null;
    } catch (_) {
      return null;
    }
  }
}

/// One direction of a connection: its key and its counter.
class IpcDirection {
  final Uint8List _key;
  int _counter = 0;

  IpcDirection(this._key);

  static Uint8List _nonceOf(int counter) {
    final n = Uint8List(24);
    ByteData.sublistView(n).setUint64(0, counter, Endian.little);
    return n;
  }

  /// Seals ONE line (without its line end) and returns it as base64.
  String seal(String plainLine) {
    final box = SodiumFFI().secretBoxEncrypt(
        Uint8List.fromList(utf8.encode(plainLine)), _key, _nonceOf(_counter));
    _counter++;
    return base64Encode(box);
  }

  /// Opens ONE received line. Throws [IpcChannelException] if it does not
  /// open under the next counter value — tampered, replayed, reordered or
  /// sealed under another key.
  String open(String sealedLine) {
    final Uint8List box;
    try {
      box = base64Decode(sealedLine.trim());
    } catch (_) {
      throw const IpcChannelException('a line that is not sealed');
    }
    try {
      final plain = SodiumFFI().secretBoxDecrypt(box, _key, _nonceOf(_counter));
      _counter++;
      return utf8.decode(plain);
    } on SodiumException {
      throw IpcChannelException(
          'line $_counter does not open — another secret, or a line '
          'replayed, dropped or changed');
    }
  }
}

/// The two direction keys of one connection.
({Uint8List clientToDaemon, Uint8List daemonToClient}) ipcDeriveKeys(
    Uint8List secret, Uint8List clientNonce, Uint8List daemonNonce) {
  if (secret.length != _secretLength) {
    throw IpcChannelException(
        'the connection secret has ${secret.length} bytes, not $_secretLength');
  }
  final okm = SodiumFFI().hkdfSha256(secret,
      salt: Uint8List.fromList([...clientNonce, ...daemonNonce]),
      info: Uint8List.fromList(utf8.encode(_kdfInfo)),
      length: 64);
  return (
    clientToDaemon: Uint8List.fromList(okm.sublist(0, 32)),
    daemonToClient: Uint8List.fromList(okm.sublist(32, 64)),
  );
}

/// The daemon's side of ONE connection.
class IpcDaemonSession {
  final Uint8List Function() _secret;
  IpcDirection? _send;
  IpcDirection? _receive;
  bool _proven = false;

  /// [secret] is asked when the client's hello arrives — once per
  /// connection, so that a device database created anew (and with it a new
  /// secret) applies to every connection made after it.
  IpcDaemonSession(this._secret);

  /// Whether the client has proven the secret (one sealed line opened).
  bool get proven => _proven;

  /// Feeds ONE received line. Returns the opened request line, or `null`
  /// when the line was the hello; [writeRaw] gets every line this side must
  /// send in answer, ready for the socket (line end included). Throws
  /// [IpcChannelException] when the connection must be closed.
  String? receive(String line, void Function(String raw) writeRaw) {
    final receive = _receive;
    if (receive == null) {
      final clientNonce = IpcHello.parse(line);
      if (clientNonce == null) {
        throw const IpcChannelException(
            'the first line is not the hello of this version — an '
            'unencrypted client is not served');
      }
      final daemonNonce = IpcHello.freshNonce();
      final keys = ipcDeriveKeys(_secret(), clientNonce, daemonNonce);
      _receive = IpcDirection(keys.clientToDaemon);
      final send = _send = IpcDirection(keys.daemonToClient);
      writeRaw('${IpcHello.line(daemonNonce)}\n');
      writeRaw('${send.seal(kIpcReadyLine)}\n');
      return null;
    }
    final plain = receive.open(line);
    _proven = true;
    return plain;
  }

  /// Seals ONE line for the client, line end included. Only after the
  /// client has proven the secret: nothing of the daemon's state goes to a
  /// connection that has not.
  String? sealForClient(String plainLine) {
    final send = _send;
    if (send == null || !_proven) return null;
    return '${send.seal(plainLine.trimRight())}\n';
  }
}

/// ONE request over a fresh protected connection on [socket]: the exchange,
/// the request [requestLine] sealed, and the opened response whose `id` is
/// [id] — events in between are skipped. `null` if the exchange fails, the
/// connection ends or [timeout] passes. The socket is closed afterwards.
///
/// For tools and tests that ask one thing; the GUI keeps its connection
/// (`IpcClient`).
Future<String?> ipcRequestOnce(
    {required Socket socket,
    required Uint8List secret,
    required String requestLine,
    required int id,
    Duration timeout = const Duration(seconds: 5)}) async {
  IpcSecureLink? link;
  try {
    link = await IpcSecureLink.open(socket, secret, timeout: timeout);
    final answer = link.lines.firstWhere((line) {
      try {
        final msg = jsonDecode(line);
        return msg is Map && msg['type'] == 'response' && msg['id'] == id;
      } catch (_) {
        return false;
      }
    });
    link.send(requestLine);
    return await answer.timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    if (link != null) {
      link.close();
    } else {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }
}

/// The client's side: a connected socket after the exchange.
class IpcSecureLink {
  final Socket socket;
  final IpcDirection _send;
  final StreamController<String> _lines;

  IpcSecureLink._(this.socket, this._send, this._lines);

  /// The opened lines from the daemon. The stream ends (with an error, if a
  /// line did not open) when the connection ends.
  Stream<String> get lines => _lines.stream;

  /// Seals and sends ONE line.
  void send(String plainLine) =>
      socket.write('${_send.seal(plainLine.trimRight())}\n');

  void close() {
    try {
      socket.destroy();
    } catch (_) {}
  }

  /// Runs the exchange on [socket] with [secret] and returns the link once
  /// the daemon has proven the secret. Throws [IpcChannelException] (and
  /// closes the socket) if it does not within [timeout].
  static Future<IpcSecureLink> open(Socket socket, Uint8List secret,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final clientNonce = IpcHello.freshNonce();
    final lines = StreamController<String>();
    final ready = Completer<IpcSecureLink>();
    IpcDirection? receive;
    IpcSecureLink? link;
    var buffer = '';

    void fail(Object error) {
      if (!ready.isCompleted) {
        ready.completeError(error is IpcChannelException
            ? error
            : IpcChannelException('$error'));
      } else if (!lines.isClosed) {
        lines.addError(error);
        lines.close();
      }
      try {
        socket.destroy();
      } catch (_) {}
    }

    void onLine(String line) {
      if (receive == null) {
        final daemonNonce = IpcHello.parse(line);
        if (daemonNonce == null) {
          fail(const IpcChannelException(
              'the daemon did not answer with the hello of this version'));
          return;
        }
        final keys = ipcDeriveKeys(secret, clientNonce, daemonNonce);
        receive = IpcDirection(keys.daemonToClient);
        link = IpcSecureLink._(socket, IpcDirection(keys.clientToDaemon), lines);
        return;
      }
      final String plain;
      try {
        plain = receive!.open(line);
      } catch (e) {
        fail(e);
        return;
      }
      if (!ready.isCompleted) {
        if (plain != kIpcReadyLine) {
          fail(const IpcChannelException(
              'the first sealed line of the daemon is not the ready line'));
          return;
        }
        ready.complete(link!);
        return;
      }
      lines.add(plain);
    }

    socket.cast<List<int>>().transform(utf8.decoder).listen(
      (chunk) {
        buffer += chunk;
        var at = buffer.indexOf('\n');
        while (at >= 0) {
          final line = buffer.substring(0, at).trim();
          buffer = buffer.substring(at + 1);
          if (line.isNotEmpty) onLine(line);
          if (ready.isCompleted && lines.isClosed) return;
          at = buffer.indexOf('\n');
        }
      },
      onError: fail,
      onDone: () {
        if (!ready.isCompleted) {
          fail(const IpcChannelException(
              'the daemon closed the connection during the exchange — '
              'another secret?'));
        } else if (!lines.isClosed) {
          lines.close();
        }
      },
      cancelOnError: true,
    );

    socket.write('${IpcHello.line(clientNonce)}\n');
    return ready.future.timeout(timeout, onTimeout: () {
      fail(const IpcChannelException('no answer to the hello in time'));
      throw const IpcChannelException('no answer to the hello in time');
    });
  }
}
