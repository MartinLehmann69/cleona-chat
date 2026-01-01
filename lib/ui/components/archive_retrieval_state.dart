// Which archived media are currently being fetched back (§21.6, S392/C2).
//
// The retrieval itself is S392/B4 and lives in the service process: the IPC
// command `archive_retrieve` answers immediately with `{started,
// alreadyRunning}` and then broadcasts `archive_retrieve_progress` and
// `archive_retrieve_done`. None of that is state the surface can derive — a
// tile that draws a progress ring needs to be told.
//
// This holder is that telling, and nothing else. It does not open a socket,
// does not know an IPC client and does not reach into `lib/core/archive/`;
// it is a map from message id to "a run is in flight, here is how far", plus
// the two latches that keep the surface honest:
//
//   * a second tap while a run is in flight starts nothing (the binding latch
//     sits in `ArchiveManager.retrieveToMediaStore`; this one only keeps the
//     surface from trying — `ipc_server.dart` says the same about its own
//     `isRetrieving`), and
//   * a run that is never spoken of again is dropped by the [watchdog] rather
//     than leaving a ring spinning forever. Without the two events there is
//     no other way to learn that nothing is coming.
//
// The watchdog is a ONE-SHOT timer per running retrieval, in the UI process,
// on no socket. It is not a poll and not a periodic idle timer (§1.2): it
// fires at most once per tap, and a finished retrieval cancels it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cleona/core/archive/archive_transport.dart';

/// What the service answered when asked to start a retrieval.
///
/// The distinction between the first two is not cosmetic: on
/// [ArchiveRetrievalStart.alreadyRunning] a run IS in flight in the service,
/// so the ring must stay; on [ArchiveRetrievalStart.unavailable] nothing is
/// running anywhere and the ring must go, or the tile hangs on the first
/// dropped connection.
enum ArchiveRetrievalStart {
  /// This call started the run (`{started: true}`).
  started,

  /// A run was already in flight for this message (`{alreadyRunning: true}`).
  alreadyRunning,

  /// No run exists and none was started — the command failed, the archive is
  /// off, or the daemon is gone.
  unavailable,
}

/// Sends `archive_retrieve` for one message and reports what came back.
///
/// **This is the seam.** Whoever owns the connection to the service installs
/// one of these on [ArchiveRetrievalState.sender]; until then
/// [ArchiveRetrievalState.canRequest] is false and the tile draws itself
/// without a tap target rather than offering a button that does nothing.
typedef ArchiveRetrievalSender = Future<ArchiveRetrievalStart> Function(
    String messageId);

/// Per-message retrieval state for the chat view.
class ArchiveRetrievalState extends ChangeNotifier {
  /// The one instance the chat view reads.
  ///
  /// A singleton because the two ends of this seam sit in different widgets:
  /// the tile is rebuilt per message inside a list, and the event handler that
  /// feeds [reportProgress] lives wherever the IPC events land. Threading an
  /// object between them would mean touching `main.dart`.
  static final ArchiveRetrievalState instance = ArchiveRetrievalState.forTest();

  /// A fresh, unshared holder — for probes, which must not inherit state from
  /// an earlier case.
  ArchiveRetrievalState.forTest();

  /// How long a run may stay silent before the surface stops believing in it.
  ///
  /// [ArchiveTransport.downloadTimeout] is the service's own ceiling for a
  /// single transfer (it scales with `kMaxArchivedFileBytes` and reaches well
  /// past half an hour over SMB). A watchdog shorter than that would clear a
  /// ring while the file is genuinely still coming down, which is the same
  /// class of lie as a ring that never stops. The slack covers the round trip
  /// of the `archive_retrieve_done` event.
  static Duration get watchdog =>
      ArchiveTransport.downloadTimeout + const Duration(minutes: 1);

  /// The installed command path; `null` until someone plugs one in, and
  /// setting it back to `null` removes it again (the connection dropped).
  ArchiveRetrievalSender? sender;

  final Map<String, double?> _running = {};
  final Map<String, Timer> _watchdogs = {};

  /// Whether a retrieval can be asked for at all.
  ///
  /// False means the surface has no path to `archive_retrieve`. The tile then
  /// shows the archive state and is NOT tappable — see the file header.
  bool get canRequest => sender != null;

  /// Whether a run is in flight for [messageId].
  bool isRetrieving(String messageId) => _running.containsKey(messageId);

  /// Progress 0.0–1.0 for [messageId], or `null` for "running, size unknown"
  /// and for "not running". Read it together with [isRetrieving]; the two
  /// facts are different and a single nullable double cannot carry both.
  double? progressOf(String messageId) => _running[messageId];

  /// Asks for [messageId] to be fetched back.
  ///
  /// Returns true when this call is the reason a run is in flight. A second
  /// tap during a run returns false and sends NOTHING — the surface does not
  /// lean on the service's latch to swallow the duplicate.
  Future<bool> request(String messageId) async {
    final send = sender;
    if (send == null) return false;
    if (_running.containsKey(messageId)) return false;

    // Marked BEFORE the await: the answer can take a round trip, and two taps
    // inside that window are exactly the case this latch exists for.
    _running[messageId] = null;
    _arm(messageId);
    notifyListeners();

    ArchiveRetrievalStart answer;
    try {
      answer = await send(messageId);
    } catch (_) {
      // A thrown sender is "nothing is running", never "keep spinning".
      answer = ArchiveRetrievalStart.unavailable;
    }
    if (answer == ArchiveRetrievalStart.unavailable) {
      finish(messageId);
      return false;
    }
    return answer == ArchiveRetrievalStart.started;
  }

  /// Fed from the `archive_retrieve_progress` event.
  ///
  /// A [totalBytes] of zero or less means the transfer size is not known; the ring
  /// then stays indeterminate instead of showing a made-up fraction.
  void reportProgress(String messageId, int bytesTransferred, int totalBytes) {
    if (!_running.containsKey(messageId)) return;
    final value = totalBytes <= 0
        ? null
        : (bytesTransferred / totalBytes).clamp(0.0, 1.0).toDouble();
    if (_running[messageId] == value) return;
    _running[messageId] = value;
    // Progress is proof of life: the watchdog starts over.
    _arm(messageId);
    notifyListeners();
  }

  /// Fed from the `archive_retrieve_done` event, and from the watchdog.
  ///
  /// Deliberately takes no success flag. Whether the file arrived is visible
  /// in the message itself — the tier goes back to `original` and the tile
  /// disappears. A failed retrieval leaves the tile standing, which is the
  /// truth, and the user can tap again.
  void finish(String messageId) {
    // `containsKey` and NOT the return of `remove`: a running retrieval whose
    // size is unknown is stored as a null value, so `remove` hands back null
    // for it just as it does for an unknown id. Reading the removal's result
    // would have left the ring on screen in exactly the indeterminate case.
    final wasRunning = _running.containsKey(messageId);
    _running.remove(messageId);
    _watchdogs.remove(messageId)?.cancel();
    if (wasRunning) notifyListeners();
  }

  /// Forgets every run. Called when the connection to the service drops:
  /// no event will ever arrive for those runs, so no ring may keep turning.
  void reset() {
    if (_running.isEmpty && _watchdogs.isEmpty) return;
    _running.clear();
    for (final t in _watchdogs.values) {
      t.cancel();
    }
    _watchdogs.clear();
    notifyListeners();
  }

  void _arm(String messageId) {
    _watchdogs.remove(messageId)?.cancel();
    _watchdogs[messageId] = Timer(watchdog, () => finish(messageId));
  }

  @override
  void dispose() {
    for (final t in _watchdogs.values) {
      t.cancel();
    }
    _watchdogs.clear();
    super.dispose();
  }
}
