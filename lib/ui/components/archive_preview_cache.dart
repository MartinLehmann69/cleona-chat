// The tier-2 previews the chat view has fetched (§21.6, S407-VORSCHAU).
//
// The mini (~2-5 KB) travels with every message (`archiveMiniBase64`); the
// preview (up to 50 KB) does not — a state snapshot carries every loaded
// message, and fifty archived photos would add 2.5 MB to each one. The tile
// therefore asks for the preview when it draws a tier-2 medium, through
// `ICleonaService.getArchivePreview` (in process on Android/iOS, the IPC
// command `archive_preview` on the desktop). Local only: the answer comes
// from the archive index, never from the share or the network.
//
// This holder is that asking, and nothing else:
//
//   * ONE request per message — a tile is rebuilt on every scroll and every
//     progress tick; asking again on each build would be a request loop.
//   * an answer of "none" is remembered as well (video, undecodable): the
//     tile then stays with the mini or the metadata form without asking again.
//   * a bounded number of previews in memory (least recently used goes); a
//     dropped one is asked for again when its tile is drawn again.
//
// Nothing here is periodic and nothing retries on its own.

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Fetches the preview of one message, `null` for "none".
///
/// **The seam.** Whoever owns the connection to the service installs one on
/// [ArchivePreviewCache.loader]; until then no preview is asked for and the
/// tile shows the mini.
typedef ArchivePreviewLoader = Future<Uint8List?> Function(String messageId);

/// Per-message tier-2 previews for the chat view.
class ArchivePreviewCache extends ChangeNotifier {
  /// The one instance the chat view reads.
  static final ArchivePreviewCache instance = ArchivePreviewCache.forTest();

  /// A fresh, unshared holder — for probes.
  ArchivePreviewCache.forTest({this.capacity = 64});

  /// Previews kept in memory: 64 x 50 KB = 3.2 MB at most.
  final int capacity;

  /// The installed fetch path; `null` until someone plugs one in.
  ArchivePreviewLoader? loader;

  // Insertion order = recency (re-inserted on every hit).
  final LinkedHashMap<String, Uint8List?> _known =
      LinkedHashMap<String, Uint8List?>();
  final Set<String> _inFlight = {};

  /// Number of fetches started — for probes.
  @visibleForTesting
  int fetches = 0;

  /// The preview of [messageId] if it is known, else `null` — and in that
  /// case the fetch is started (once). Listeners hear when it arrives.
  ///
  /// Safe to call from `build`: the fetch completes asynchronously, so no
  /// listener is notified during the build that asked.
  Uint8List? previewFor(String messageId) {
    if (_known.containsKey(messageId)) {
      final v = _known.remove(messageId);
      _known[messageId] = v;
      return v;
    }
    final load = loader;
    if (load == null || _inFlight.contains(messageId)) return null;
    _inFlight.add(messageId);
    fetches++;
    _fetch(load, messageId);
    return null;
  }

  Future<void> _fetch(ArchivePreviewLoader load, String messageId) async {
    Uint8List? bytes;
    try {
      bytes = await load(messageId);
    } catch (_) {
      // A failed fetch is "no preview": the tile keeps the mini. Not
      // remembered, so the next drawing of the tile may ask again.
      _inFlight.remove(messageId);
      return;
    }
    _inFlight.remove(messageId);
    _known[messageId] = (bytes == null || bytes.isEmpty) ? null : bytes;
    while (_known.length > capacity) {
      _known.remove(_known.keys.first);
    }
    notifyListeners();
  }

  /// Forgets everything (connection or identity changed).
  void clear() {
    _known.clear();
    _inFlight.clear();
  }
}
