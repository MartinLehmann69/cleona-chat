/// ContactSeed: encodes node identity + reachability into a URI for QR codes.
///
/// Format: `cleona://<nodeIdHex>?n=<name>&c=<b|l>&a=<ip:port+ip:port>&s=<nodeId1@ip1:port1+ip2:port2,...>`
///
/// - nodeIdHex: 64-char hex of the node's 32-byte ID
/// - n: display name (URL-encoded)
/// - c: network channel ('b' = beta, 'l' = live) — 1 char, for cross-channel detection
/// - a: own addresses (multi-address separated by +, encoded as %2B in URI)
/// - s: seed peers (up to 5, each: nodeIdHex@ip:port+ip:port)
class ContactSeed {
  final String nodeIdHex;
  final String displayName;
  final List<String> ownAddresses; // ip:port pairs
  final List<SeedPeer> seedPeers;
  final String? channelTag; // 'b' or 'l' (null = legacy QR without channel)

  ContactSeed({
    required this.nodeIdHex,
    required this.displayName,
    this.ownAddresses = const [],
    this.seedPeers = const [],
    this.channelTag,
  });

  /// Build the URI string for QR code encoding.
  String toUri() {
    final sb = StringBuffer('cleona://$nodeIdHex');
    sb.write('?n=${Uri.encodeComponent(displayName)}');

    // Channel tag: 1 char ('b' = beta, 'l' = live)
    if (channelTag != null) {
      sb.write('&c=$channelTag');
    }

    if (ownAddresses.isNotEmpty) {
      // Join with + but encode as %2B in URI
      final joined = ownAddresses.join('+');
      sb.write('&a=${joined.replaceAll('+', '%2B')}');
    }

    if (seedPeers.isNotEmpty) {
      final peers = seedPeers.take(5).map((p) {
        final addrs = p.addresses.take(2).join('+');
        return '${p.nodeIdHex}@${addrs.replaceAll('+', '%2B')}';
      }).join(',');
      sb.write('&s=$peers');
    }

    return sb.toString();
  }

  /// Parse a ContactSeed URI.
  /// Returns null if the URI is malformed.
  static ContactSeed? fromUri(String uri) {
    try {
      if (!uri.startsWith('cleona://')) return null;

      final withoutScheme = uri.substring('cleona://'.length);
      final qIdx = withoutScheme.indexOf('?');
      if (qIdx < 0) return null;

      final nodeIdHex = withoutScheme.substring(0, qIdx);
      if (nodeIdHex.length != 64) return null;

      final queryString = withoutScheme.substring(qIdx + 1);
      final params = _parseQuery(queryString);

      final name = params['n'] ?? '';

      // Parse own addresses
      final ownAddrs = <String>[];
      final aParam = params['a'];
      if (aParam != null && aParam.isNotEmpty) {
        ownAddrs.addAll(aParam.split('+').where((a) => a.isNotEmpty));
      }

      // Parse seed peers
      final seedPeers = <SeedPeer>[];
      final sParam = params['s'];
      if (sParam != null && sParam.isNotEmpty) {
        for (final peerStr in sParam.split(',')) {
          final atIdx = peerStr.indexOf('@');
          if (atIdx < 0) continue;
          final peerNodeId = peerStr.substring(0, atIdx);
          final addrs = peerStr.substring(atIdx + 1).split('+').where((a) => a.isNotEmpty).toList();
          seedPeers.add(SeedPeer(nodeIdHex: peerNodeId, addresses: addrs));
        }
      }

      return ContactSeed(
        nodeIdHex: nodeIdHex,
        displayName: name,
        ownAddresses: ownAddrs,
        seedPeers: seedPeers,
        channelTag: params['c'],
      );
    } catch (_) {
      return null;
    }
  }

  /// Manual query string parser that handles %2B → + correctly.
  static Map<String, String> _parseQuery(String query) {
    final params = <String, String>{};
    for (final part in query.split('&')) {
      final eqIdx = part.indexOf('=');
      if (eqIdx < 0) continue;
      final key = part.substring(0, eqIdx);
      var value = part.substring(eqIdx + 1);
      // Decode %2B back to + BEFORE URI decoding
      value = value.replaceAll('%2B', '+');
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {
        // Keep raw value if decode fails (e.g., malformed percent-encoding)
      }
      params[key] = value;
    }
    return params;
  }

  /// Check if this seed's channel matches the local channel.
  /// Returns true if compatible (same channel or legacy QR without tag).
  bool isChannelCompatible(String localChannelTag) {
    if (channelTag == null || channelTag!.isEmpty) return true; // legacy
    return channelTag == localChannelTag;
  }

  /// Human-readable channel name for error messages.
  String get channelDisplayName {
    if (channelTag == 'b') return 'Beta';
    if (channelTag == 'l') return 'Live';
    return '?';
  }
}

/// A seed peer with node ID and reachable addresses.
class SeedPeer {
  final String nodeIdHex;
  final List<String> addresses; // ip:port pairs

  const SeedPeer({required this.nodeIdHex, this.addresses = const []});
}
