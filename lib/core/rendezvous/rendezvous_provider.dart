/// Abstract RendezvousProvider interface + SignedEndpointRecord model.
///
/// Architecture §4.11.2 (Interface) + §4.11.5 (SignedEndpointRecord).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/util/endpoint_address.dart';

export 'package:cleona/core/util/endpoint_address.dart';

// ---------------------------------------------------------------------------
// RendezvousProvider Interface (§4.11.2)
// ---------------------------------------------------------------------------

abstract class RendezvousProvider {
  /// Publish a signed, encrypted endpoint record under the derived lookup tag.
  ///
  /// On the Nostr substrate this signs with a THROWAWAY key pair per
  /// event (`nostr_provider.dart:192-195`). That is the right construction
  /// everywhere unlinkability over time weighs — but it
  /// replaces nothing: kind 30078 with `d` tag is a NIP-33 record, and
  /// a relay only replaces with equal `(pubkey, kind, d-Tag)`. Whoever stores
  /// MULTIPLE times under the same tag accumulates instead of updating.
  /// `publishWithKey` (a caller-derived signing key) stood next to this for
  /// the binary distribution and fell with it (V9 A1, 08.10.2026).
  Future<void> publish(Uint8List lookupTag, SignedEndpointRecord record);

  /// Resolve the record under the tag. Returns null if nothing found or
  /// the channel is blocked in the current network.
  Future<SignedEndpointRecord?> resolve(Uint8List lookupTag);

  /// Whether this provider is usable in the current network context.
  bool get isAvailable;
}

// ---------------------------------------------------------------------------
// EndpointRecord (plaintext, inside AEAD)
// ---------------------------------------------------------------------------

class EndpointRecord {
  final List<EndpointAddress> addresses;
  final int seq;
  final int publishedAt;
  final Uint8List deviceId;

  const EndpointRecord({
    required this.addresses,
    required this.seq,
    required this.publishedAt,
    required this.deviceId,
  });

  Uint8List serialize() {
    final json = {
      'a': addresses.map((a) => a.toJson()).toList(),
      's': seq,
      't': publishedAt,
      'd': base64Encode(deviceId),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  static EndpointRecord? deserialize(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return EndpointRecord(
        addresses: (json['a'] as List)
            .map((e) => EndpointAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        seq: json['s'] as int,
        publishedAt: json['t'] as int,
        deviceId: base64Decode(json['d'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// SignedEndpointRecord (§4.11.5) — substrate-facing envelope
// ---------------------------------------------------------------------------

class SignedEndpointRecord {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final int seq;

  const SignedEndpointRecord({
    required this.nonce,
    required this.ciphertext,
    required this.seq,
  });

  /// Serialize for transport (base64 content on Nostr).
  Uint8List serialize() {
    // Format: [1B version][12B nonce][8B seq BE][ciphertext...]
    final bb = BytesBuilder(copy: false);
    bb.addByte(0x01); // version
    bb.add(nonce);
    final seqBytes = ByteData(8)..setUint64(0, seq);
    bb.add(seqBytes.buffer.asUint8List());
    bb.add(ciphertext);
    return bb.toBytes();
  }

  static SignedEndpointRecord? deserialize(Uint8List data) {
    // version(1) + nonce(12) + seq(8) + min ciphertext(16 tag) = 37
    if (data.length < 37) return null;
    if (data[0] != 0x01) return null;
    final nonce = Uint8List.sublistView(data, 1, 13);
    final seqBytes = ByteData.sublistView(data, 13, 21);
    final seq = seqBytes.getUint64(0);
    final ciphertext = Uint8List.sublistView(data, 21);
    return SignedEndpointRecord(nonce: nonce, ciphertext: ciphertext, seq: seq);
  }
}

// `encryptEndpointRecord` / `decryptEndpointRecord` stood here and are gone
// (S403, owner decision 5 = B of 02.10.2026). No reading of the norm needs
// them. The binary distribution, which sealed its records with its own two
// functions, no longer uses a relay at all (V9 A1, 08.10.2026; v4_2
// §26.6.4).
