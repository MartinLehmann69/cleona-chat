// The lock of the set request (§11.1 step 3).
//
// ══════════════════════════════════════════════════════════════════════
// WHY THIS IS A CLASS OF ITS OWN (S376, P4-3)
// ══════════════════════════════════════════════════════════════════════
//
// It was a `bool` in the node, set at one place
// (`requestEntrySet`) and cleared at a second (`_learnEntry`,
// on learning a record). The release thus hung on an
// ANSWER WITH CONTENT — and exactly that fails to come in three situations:
//
//   1. The asked partner has nothing. `delivery_node.dart` in that
//      case handed out no frame at all ("keine Eintrittsdaten zum
//      Weitergeben"), the lock stood forever afterwards.
//   2. The control queue overflows. `cover_stream._pushControl`
//      discards a whole GROUP on overflow; in the field on 07.09.2026
//      measured on `.201`: 120/120 frames, 180 discarded. A frame
//      that never went out cannot be answered.
//   3. The partner breaks off before it answers.
//
// In each of the three situations the neighbourhood extension of the node
// was blocked until RESTART. `V41Node.entrySetSettled()` existed as a
// way out — with zero callers in `lib/`.
//
// As a class of its own the lock has a state that can be
// measured, and a place where the expiry stands. It counts in SLOTS
// and not in seconds: the clock is the time axis of this layer (one
// cell per slot), and a wall clock would, with a throttled cover clock
// (`CoverSaver.slotFactor`), measure something other than the network does.
library;

/// Lock against two simultaneously open set requests.
///
/// A request costs one slot; nobody would need two at once.
/// Without expiry such a lock is not a cap, but a
/// latch — therefore [expire] belongs to it inseparably.
final class EntrySetLatch {
  /// After how many slots without an answer the lock falls by itself.
  final int timeoutSlots;

  bool _open = false;
  int _sinceSlot = 0;

  /// How often a lock expired instead of being answered.
  ///
  /// A number, not a log: it says how often the neighbourhood extension
  /// ran into the void, and that belongs in the status and not only in a
  /// line nobody reads.
  int expired = 0;

  EntrySetLatch({required this.timeoutSlots})
      : assert(timeoutSlots > 0, 'a lock without expiry is a bolt');

  bool get open => _open;

  /// May we ask now? Sets the lock if yes.
  ///
  /// Returns `false` as long as a request is pending — the caller
  /// then sends nothing.
  bool tryOpen(int slot) {
    if (_open) return false;
    _open = true;
    _sinceSlot = slot;
    return true;
  }

  /// The answer is there — the next one may go.
  ///
  /// This is called on EVERY `entryResponse`, even an EMPTY one:
  /// "I have nothing" is an answer and ends the waiting. Not
  /// only on learning a record — that was the error.
  void settle() => _open = false;

  /// Drops a lock that has stood too long.
  ///
  /// Returns whether it fell in this call — the caller
  /// can report that. For a closed lock and for one that
  /// is still within the deadline, nothing happens.
  bool expire(int slot) {
    if (!_open) return false;
    if (slot - _sinceSlot < timeoutSlots) return false;
    _open = false;
    expired++;
    return true;
  }
}
