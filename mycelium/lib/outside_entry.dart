/// The external address entry (V4.2 §11.9) — format, event, check.
///
/// ── WHAT AN ENTRY IS ─────────────────────────────────────────────────
///
/// §11.9: „what is published: the node's own address record: addresses,
/// node key, validity". An entry only says „under this address a node
/// perhaps answers" — a hint, not an authority. That is why it carries
/// NO identity: as „node key" stands the node identifier from the call
/// (16 B, rolled anew each start, call D), not the Ed25519 key
/// of an identity. An identity key next to an IP on a
/// public relay would be exactly the link person↔address that the
/// call has no longer shown since S385.
///
/// ── PAYLOAD (content of the event, base64url without padding) ─────────
/// ```
/// version (1 B, 0x01) | channel (1 B, 0x00 live, 0x01 beta, as §15.2)
/// node identifier (16 B) | expiry (u32 LE, Unix seconds)
/// number of addresses (1 B, 1..3)
/// per address: type (1 B, 4 or 6) | address (4/16 B) | port (u16 LE)
/// ```
/// The addresses as in the card (§15.2: type byte, address, port u16 LE).
/// Unknown version, unknown type, port 0, short or overlong
/// content: the whole entry is discarded, never a part read.
///
/// ── THE EVENT ──────────────────────────────────────────────────────────
/// kind 30078, tags `["d", <Stichwort>]` and `["expiration", "<Ablauf>"]`.
/// The keyword is SHA-256("mycelium-address-entry-1" ‖ channel byte) hex. It
/// is publicly derivable and only separates the channels — no secret
/// (RL-13: whoever registers is enumerable).
///
/// Signed with secp256k1 Schnorr (BIP-340) under the STABLE key
/// of the node (§11.9, version 16.09.2026: „a node with a reachable address
/// keeps one key for its records, so that a new record replaces the old one
/// and its standing is readable"). It lives in `outside_state.dart` and is
/// only used here.
///
/// UNTIL S390 this was a throwaway key per entry. Because an entry is a
/// parameterized replaceable event (kind 30078), a relay thus never
/// REPLACED anything but collected; a deletion (NIP-09) was impossible,
/// because it needs the same key; and the standing was not
/// readable. The price — the entries of a node are linkable over time —
/// is calculated in `outside_state.dart`: they were anyway,
/// via the address that stands next to it in plaintext.
///
/// Sources (NIP texts, nostr-protocol/nips, branch master):
///   * NIP-01 `01.md` — event id = SHA-256 over the serialisation
///     `[0,<pubkey>,<created_at>,<kind>,<tags>,<content>]`, `sig` =
///     Schnorr over the id; filters `kinds`, `#d`, `since`, `limit`;
///     „Addressable Events" (kind 30000–39999) a relay keeps only once
///     per `(pubkey, kind, d-Tag)` — the newest `created_at` wins.
///   * NIP-09 `09.md` — deletion request: kind 5, tag `["e", <id>]` for a
///     single event, `["a", "<kind>:<pubkey>:<d>"]` for an
///     addressable record, `["k", "<kind>"]` next to it. A relay
///     SHOULD no longer deliver afterwards; it must be signed with
///     the same key as the deleted one.
///   * NIP-40 `40.md` — tag `expiration`: relays should no longer deliver expired
///     events, readers should ignore them.
///   * NIP-78 `78.md` — kind 30078, application-specific data with `d` tag.
/// The same id computation is in `lib/core/rendezvous/nostr_provider.dart`
/// (`NostrEvent.computeId`). The serialisation is unambiguous here because
/// tags and content are pure ASCII (hex, digits, base64url) — the
/// escape rules of NIP-01 for special characters never apply.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/secp256k1_schnorr.dart'
    show schnorrSign, schnorrVerify, secp256k1PubkeyFromSecret;
import 'package:mycelium/card.dart' show CardAddress, CardAddressType;
import 'package:mycelium/node_helpers.dart' show hashFrom, hexFrom;

/// NIP-78: application-specific data.
const int kEntryKind = 30078;

/// §11.9 „lifetime of a record: 1 day" — in seconds.
const int kEntryLifetime = 86400;

/// How far the clock of a writer may run AHEAD before its entry is
/// discarded as coming from the future. Five minutes cover a usually
/// unset device clock without stretching an entry beyond its day.
const int kClockPlay = 300;

const int kEntryAddressesAtMost = 3;
const int _version = 1;

/// The `d` tag of the entries of a channel.
String entryKeyword(int channel) => hexFrom(hashFrom(
    Uint8List.fromList([...utf8.encode('mycelium-address-entry-1'), channel])));

int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class AddressRecord {
  final int channel;

  /// The node identifier (16 B, new each start) — no identity relation.
  final Uint8List node;
  final List<CardAddress> addresses;

  /// Unix seconds.
  final int expiry;

  AddressRecord({
    required this.channel,
    required this.node,
    required this.addresses,
    required this.expiry,
  }) {
    if (node.length != 16) {
      throw ArgumentError('Node identifier has 16 B, not ${node.length}');
    }
    if (addresses.isEmpty || addresses.length > kEntryAddressesAtMost) {
      throw ArgumentError('1 to $kEntryAddressesAtMost addresses, '
          'not ${addresses.length}');
    }
  }

  Uint8List pack() {
    final b = BytesBuilder()
      ..addByte(_version)
      ..addByte(channel)
      ..add(node)
      ..add((ByteData(4)..setUint32(0, expiry, Endian.little))
          .buffer
          .asUint8List())
      ..addByte(addresses.length);
    for (final a in addresses) {
      b
        ..addByte(a.kind.byteValue)
        ..add(a.address)
        ..add((ByteData(2)..setUint16(0, a.port, Endian.little))
            .buffer
            .asUint8List());
    }
    return b.toBytes();
  }

  /// `null` on any format error — all or nothing.
  static AddressRecord? read(Uint8List b) {
    var i = 0;
    Uint8List take(int n) {
      if (i + n > b.length) throw const FormatException('too short');
      final s = Uint8List.fromList(b.sublist(i, i + n));
      i += n;
      return s;
    }

    try {
      if (take(1)[0] != _version) return null;
      final channel = take(1)[0];
      final node = take(16);
      final expiry =
          ByteData.sublistView(take(4)).getUint32(0, Endian.little);
      final n = take(1)[0];
      if (n == 0 || n > kEntryAddressesAtMost) return null;
      final addresses = <CardAddress>[];
      for (var k = 0; k < n; k++) {
        final kind = CardAddressType.fromByte(take(1)[0]);
        if (kind == null) return null;
        final address = take(kind.addressLength);
        final port = ByteData.sublistView(take(2)).getUint16(0, Endian.little);
        if (port == 0) return null;
        addresses.add(CardAddress(address, port));
      }
      if (i != b.length) return null;
      return AddressRecord(
          channel: channel, node: node, addresses: addresses, expiry: expiry);
    } on Object {
      return null;
    }
  }
}

/// NIP-09: the kind of a deletion request.
const int kDeleteKind = 5;

/// The signed event for [e], under [secret] — the stable key
/// of this node (`outside_state.dart`). Same key, same
/// `d` tag, same kind: a relay thereby REPLACES the previous entry
/// of this node instead of putting a second one next to it.
Map<String, dynamic> entryEvent(AddressRecord e,
    {required Uint8List secret, int? now}) {
  final created = now ?? nowSeconds();
  final tags = [
    ['d', entryKeyword(e.channel)],
    ['expiration', '${e.expiry}'],
  ];
  return _signed(secret, kEntryKind, created, tags,
      base64Url.encode(e.pack()).replaceAll('=', ''));
}

/// The deletion request for the own entry in channel [channel] (NIP-09) — for
/// the orderly departure (§11.9: „a node leaving for good may
/// additionally delete its record, because it still holds the key").
///
/// Addressed via the `a` tag, not via `e`: the node does not necessarily know the
/// identifier of its last event (it changes with every
/// refresh), but it does know `(kind, public key, keyword)` — and
/// that is exactly the address of an addressable record.
Map<String, dynamic> deleteEvent(Uint8List secret,
    {required int channel, int? now}) {
  final pub = hexFrom(secp256k1PubkeyFromSecret(secret));
  final tags = [
    ['a', '$kEntryKind:$pub:${entryKeyword(channel)}'],
    ['k', '$kEntryKind'],
  ];
  return _signed(
      secret, kDeleteKind, now ?? nowSeconds(), tags, '');
}

Map<String, dynamic> _signed(Uint8List secret, int kind, int created,
    List<List<String>> tags, String content) {
  final pub = hexFrom(secp256k1PubkeyFromSecret(secret));
  final id = _id(pub, created, kind, tags, content);
  return {
    'id': id,
    'pubkey': pub,
    'created_at': created,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': hexFrom(schnorrSign(secret, _fromHex(id))),
  };
}

/// Checks an event from a relay and returns the entry — or
/// `null`. Discarded is: foreign kind, foreign keyword, id does not match
/// the content, signature does not hold, from the future, older than a day,
/// expired, expiry more than a day after creation, foreign channel,
/// format error. Does not throw.
AddressRecord? eventCheck(Map<String, dynamic> ev, int channel,
    {int? now}) {
  try {
    final t = now ?? nowSeconds();
    final kind = ev['kind'] as int;
    if (kind != kEntryKind) return null;
    final pub = ev['pubkey'] as String;
    final created = ev['created_at'] as int;
    final content = ev['content'] as String;
    final id = ev['id'] as String;
    final sig = ev['sig'] as String;
    final tags = [
      for (final x in ev['tags'] as List) [for (final y in x as List) y as String]
    ];
    final keyword = entryKeyword(channel);
    if (!tags.any((x) => x.length > 1 && x[0] == 'd' && x[1] == keyword)) {
      return null;
    }
    if (pub.length != 64 || sig.length != 128) return null;
    if (_id(pub, created, kind, tags, content) != id) return null;
    if (!schnorrVerify(_fromHex(pub), _fromHex(id), _fromHex(sig))) return null;
    if (created > t + kClockPlay || created < t - kEntryLifetime) {
      return null;
    }
    final e = AddressRecord.read(
        Uint8List.fromList(base64Url.decode(base64Url.normalize(content))));
    if (e == null || e.channel != channel) return null;
    if (e.expiry <= t || e.expiry > created + kEntryLifetime + kClockPlay) {
      return null;
    }
    return e;
  } on Object {
    return null;
  }
}

/// The NIP-01 filter for the entries of a channel: only kind 30078 with the
/// keyword, only from the last day, at most [limit] per relay.
Map<String, dynamic> entryFilter(int channel,
        {required int limit, int? now}) =>
    {
      'kinds': [kEntryKind],
      '#d': [entryKeyword(channel)],
      'since': (now ?? nowSeconds()) - kEntryLifetime,
      'limit': limit,
    };

String _id(String pub, int created, int kind, List<List<String>> tags,
        String content) =>
    hexFrom(hashFrom(Uint8List.fromList(utf8.encode(
        '[0,"$pub",$created,$kind,${jsonEncode(tags)},${jsonEncode(content)}]'))));

Uint8List _fromHex(String s) {
  if (s.length.isOdd) throw const FormatException('ungerade Hexlaenge');
  return Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)
  ]);
}
