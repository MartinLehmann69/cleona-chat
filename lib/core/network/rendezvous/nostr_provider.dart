/// Nostr relay client implementing [RendezvousProvider].
///
/// Architecture §4.11.6 (NIP-01, NIP-33 Parameterized Replaceable Events).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/rendezvous/rendezvous_provider.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const List<String> kDefaultNostrRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
  'wss://relay.snort.social',
  'wss://nostr.wine',
];

const Duration kRelayConnectTimeout = Duration(seconds: 10);
const Duration kRelayResponseTimeout = Duration(seconds: 10);

// ---------------------------------------------------------------------------
// Nostr Event (NIP-01)
// ---------------------------------------------------------------------------

class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Compute event id = SHA-256 of the canonical serialization.
  static String computeId(String pubkey, int createdAt, int kind,
      List<List<String>> tags, String content) {
    final serialized =
        '[0,"$pubkey",$createdAt,$kind,${jsonEncode(tags)},${jsonEncode(content)}]';
    final hash = SodiumFFI()
        .sha256(Uint8List.fromList(utf8.encode(serialized)));
    return _bytesToHex(hash);
  }

  /// Build and sign a Nostr event with a throwaway secp256k1 keypair.
  static NostrEvent create({
    required int kind,
    required List<List<String>> tags,
    required String content,
    required Uint8List secretKey,
    required Uint8List publicKey,
  }) {
    final pubkeyHex = _bytesToHex(publicKey);
    final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final id = computeId(pubkeyHex, createdAt, kind, tags, content);
    final idBytes = _hexToBytes(id);
    final sig = schnorrSign(secretKey, idBytes);
    return NostrEvent(
      id: id,
      pubkey: pubkeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: _bytesToHex(sig),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };

  static NostrEvent? fromJson(Map<String, dynamic> j) {
    try {
      return NostrEvent(
        id: j['id'] as String,
        pubkey: j['pubkey'] as String,
        createdAt: j['created_at'] as int,
        kind: j['kind'] as int,
        tags: (j['tags'] as List)
            .map((t) => (t as List).map((e) => e.toString()).toList())
            .toList(),
        content: j['content'] as String,
        sig: j['sig'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// NostrProvider (§4.11.6)
// ---------------------------------------------------------------------------

class NostrProvider implements RendezvousProvider {
  final List<String> relayUris;
  final CLogger _log;

  NostrProvider({List<String>? relays, String? profileDir})
      : relayUris = relays ?? kDefaultNostrRelays,
        _log = CLogger.get('nostr', profileDir: profileDir);

  @override
  bool get isAvailable => true;

  // -------------------------------------------------------------------------
  // Publish (§4.11.6 — Publish flow)
  // -------------------------------------------------------------------------

  /// Publish with an externally provided secp256k1 secret key (deterministic).
  Future<void> publishWithKey(Uint8List lookupTag, SignedEndpointRecord record,
      Uint8List nostrSecretKey) async {
    final kp = secp256k1PubkeyFromSecret(nostrSecretKey);
    final tagHex = _bytesToHex(lookupTag);
    final contentB64 = base64Encode(record.serialize());

    final event = NostrEvent.create(
      kind: 30078,
      tags: [
        ['d', tagHex]
      ],
      content: contentB64,
      secretKey: nostrSecretKey,
      publicKey: kp,
    );

    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    var successCount = 0;

    await Future.wait(relayUris.map((uri) async {
      try {
        await _publishToRelay(uri, eventJson);
        successCount++;
      } catch (e) {
        _log.debug('Nostr publish to $uri failed: $e');
      }
    }));

    _log.info('Nostr publish: $successCount/${relayUris.length} relays '
        'for tag ${tagHex.substring(0, 8)}…');
  }

  @override
  Future<void> publish(Uint8List lookupTag, SignedEndpointRecord record) async {
    final kp = generateSecp256k1Keypair();
    final tagHex = _bytesToHex(lookupTag);
    final contentB64 = base64Encode(record.serialize());

    final event = NostrEvent.create(
      kind: 30078,
      tags: [
        ['d', tagHex]
      ],
      content: contentB64,
      secretKey: kp.secretKey,
      publicKey: kp.publicKey,
    );

    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    var successCount = 0;

    await Future.wait(relayUris.map((uri) async {
      try {
        await _publishToRelay(uri, eventJson);
        successCount++;
      } catch (e) {
        _log.debug('Nostr publish to $uri failed: $e');
      }
    }));

    _log.info('Nostr publish: $successCount/${relayUris.length} relays '
        'for tag ${tagHex.substring(0, 8)}…');
  }

  Future<void> _publishToRelay(String uri, String eventJson) async {
    final ws = await WebSocket.connect(uri).timeout(kRelayConnectTimeout);
    try {
      final okCompleter = Completer<void>();
      ws.listen((data) {
        try {
          final msg = jsonDecode(data as String) as List;
          if (msg.isNotEmpty && msg[0] == 'OK' && !okCompleter.isCompleted) {
            final accepted = msg.length > 2 && msg[2] == true;
            if (accepted) {
              okCompleter.complete();
            } else {
              final reason = msg.length > 3 ? msg[3] : 'rejected';
              okCompleter.completeError(Exception('Relay rejected: $reason'));
            }
          }
        } catch (_) {}
      }, onError: (e) {
        if (!okCompleter.isCompleted) okCompleter.completeError(e);
      }, onDone: () {
        if (!okCompleter.isCompleted) {
          okCompleter.completeError(
              const SocketException('WebSocket closed before OK'));
        }
      });

      ws.add(eventJson);
      await okCompleter.future.timeout(kRelayResponseTimeout);
    } finally {
      await ws.close().catchError((_) {});
    }
  }

  // -------------------------------------------------------------------------
  // Resolve (§4.11.6 — Resolve flow)
  // -------------------------------------------------------------------------

  @override
  Future<SignedEndpointRecord?> resolve(Uint8List lookupTag) async {
    final tagHex = _bytesToHex(lookupTag);
    _log.debug('Nostr resolve: querying tag ${tagHex.substring(0, 8)}…');

    final completer = Completer<SignedEndpointRecord?>();
    var pending = relayUris.length;
    final subscriptions = <Future<void>>[];

    for (final uri in relayUris) {
      subscriptions.add(_resolveFromRelay(uri, tagHex).then((record) {
        if (record != null && !completer.isCompleted) {
          completer.complete(record);
        }
      }).catchError((e) {
        _log.debug('Nostr resolve from $uri failed: $e');
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }));
    }

    return completer.future.timeout(
      kRelayConnectTimeout + kRelayResponseTimeout,
      onTimeout: () {
        _log.debug('Nostr resolve: timeout for tag ${tagHex.substring(0, 8)}…');
        return null;
      },
    );
  }

  Future<SignedEndpointRecord?> _resolveFromRelay(
      String uri, String tagHex) async {
    final ws = await WebSocket.connect(uri).timeout(kRelayConnectTimeout);
    try {
      final resultCompleter = Completer<SignedEndpointRecord?>();
      const subId = 'rv1';

      ws.listen((data) {
        try {
          final msg = jsonDecode(data as String) as List;
          if (msg.isEmpty) return;
          if (msg[0] == 'EVENT' && msg.length >= 3) {
            final event =
                NostrEvent.fromJson(msg[2] as Map<String, dynamic>);
            if (event != null) {
              final recordBytes = base64Decode(event.content);
              final record = SignedEndpointRecord.deserialize(
                  Uint8List.fromList(recordBytes));
              if (record != null && !resultCompleter.isCompleted) {
                resultCompleter.complete(record);
              }
            }
          } else if (msg[0] == 'EOSE') {
            if (!resultCompleter.isCompleted) {
              resultCompleter.complete(null);
            }
          }
        } catch (_) {}
      }, onError: (e) {
        if (!resultCompleter.isCompleted) resultCompleter.complete(null);
      }, onDone: () {
        if (!resultCompleter.isCompleted) resultCompleter.complete(null);
      });

      final filter = {
        '#d': [tagHex],
        'kinds': [30078],
      };
      ws.add(jsonEncode(['REQ', subId, filter]));

      final record =
          await resultCompleter.future.timeout(kRelayResponseTimeout,
              onTimeout: () => null);

      try {
        ws.add(jsonEncode(['CLOSE', subId]));
      } catch (_) {}
      return record;
    } finally {
      await ws.close().catchError((_) {});
    }
  }
}

// ---------------------------------------------------------------------------
// Hex helpers (local, no peer_info dependency)
// ---------------------------------------------------------------------------

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
