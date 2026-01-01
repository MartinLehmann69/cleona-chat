/// Link-layer replay buffer (AP-3a step 2, architecture v4 §2.6
/// "Replay (normative, E-79)"; docs/SPEC_MYZEL_NETWORK_DRAFT.md §20 E-79).
///
/// Guards the responder side of the Elligator2 handshake against a
/// captured `init` cell being replayed inside its own acceptance window.
/// §2.6 defines that window as **epoch ±1**, i.e. at most two hours
/// (E-78) — the MAC alone does not stop a replay *within* that window,
/// only a record of what has already been accepted does.
///
/// **Entry key: the 32-byte `E2(eph_pub)`**, not the decoded X25519
/// point. §2.6 fixes this explicitly ("saves the decoding before the
/// check" — E-79): the encoded bytes are already on the wire before
/// any Elligator2 decode happens, so keying on them lets the replay
/// check run before, and independent of, that decode.
///
/// **Lifetime = the full acceptance window from E-78, two hours.** Not
/// the ±1-epoch check re-derived here — the buffer only needs to
/// outlive the *longest* a captured `init` could still be accepted,
/// which is exactly that window.
///
/// **Structure and cap follow the house precedent `FrameDedupCache`**
/// (`lib/core/node/cleona_node.dart`, class `FrameDedupCache` — **historic:
/// deleted with the CUT of 2026-08-31, `lib/core/node/` holds zero files,
/// measured 2026-09-03**): a
/// [LinkedHashMap] with TTL eviction from the front plus a hard LRU cap
/// of 8,192 entries (256 KB at 32 B/entry). Entries are **never
/// refreshed on a hit** — refreshing would break the invariant that
/// insertion order equals timestamp order, which is what lets eviction
/// pop expired entries from the front in amortized O(1) instead of
/// scanning the whole map on every check. This buffer sits in the
/// handshake hot path, so that amortized O(1) is load-bearing, not an
/// optimization; a refreshed entry would silently degrade it back to
/// O(n) under sustained traffic. Do **not** "fix" a hit by touching the
/// entry — that is the one thing this class must never do.
///
/// **Not persisted — this is normative, not an oversight (E-79).**
/// Persisting entries would put replay-relevant, secret-adjacent state
/// on disk for no proportionate gain: a restart makes a previously
/// captured `init` reusable exactly once, and E-78 already bounds that
/// residual exposure to the two-hour acceptance window regardless — the
/// same cap that would apply if the buffer had survived the restart.
/// Trading disk persistence for that single-use, time-boxed gap is the
/// better trade the spec calls for.
///
/// **Caller contract — read this before wiring it up.** §2.6 requires
/// that a replay hit be **indistinguishable from a failed MAC check**:
/// silence, no separate branch, no measurable timing difference. A
/// distinguishable reaction to a replay (a different log line, a
/// different code path, a different response) would itself be the
/// measurable difference §2.6 rules out. Consequently:
///
/// - The caller MUST fold [isReplay] into the same silent-drop branch
///   used for a MAC failure. There must be no `if (isReplay) { ... }
///   else if (macFailed) { ... }` with observably different behaviour.
/// - **This class MUST NOT log.** Not on a hit, not on insertion, not
///   on eviction. A log call is I/O with its own timing footprint and
///   would be exactly the kind of side channel this section forbids.
library;

import 'dart:collection';
import 'dart:typed_data';

/// Tracks accepted `init` cells by their 32-byte `E2(eph_pub)` to reject
/// replays inside the handshake's acceptance window. See the library
/// docstring above for the full rationale (entry key, lifetime, cap,
/// non-persistence, and the caller's silent-drop obligation).
class LinkReplayBuffer {
  /// Hard LRU cap: 8,192 entries (256 KB at 32 B/entry) — E-79.
  final int maxSize;

  /// Entry lifetime: the full acceptance window from E-78, two hours.
  final Duration ttl;

  /// Keyed on the hex-encoded 32-byte `E2(eph_pub)`. Insertion order ==
  /// timestamp order because entries are never refreshed on a hit — see
  /// the library docstring for why that invariant matters here.
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  LinkReplayBuffer({
    this.maxSize = 8192,
    this.ttl = const Duration(hours: 2),
  });

  /// Returns `true` if [e2EphPub] was already accepted within [ttl] of
  /// [now] (default: wall-clock `DateTime.now()`); records it and
  /// returns `false` otherwise.
  ///
  /// [e2EphPub] MUST be exactly 32 bytes — the encoded Elligator2 point,
  /// never the decoded X25519 key.
  ///
  /// The caller MUST treat a `true` result exactly like a failed MAC
  /// check (see the library docstring's caller contract): this method
  /// itself performs no logging and takes no action beyond recording the
  /// entry, by design.
  bool isReplay(Uint8List e2EphPub, {DateTime? now}) {
    if (e2EphPub.length != 32) {
      throw ArgumentError(
          'isReplay: E2(eph_pub) must be 32 bytes, got ${e2EphPub.length}');
    }
    final effectiveNow = now ?? DateTime.now();
    final cutoff = effectiveNow.subtract(ttl);

    // TTL eviction from the front — see the house precedent
    // FrameDedupCache for why this is safe as long as entries are never
    // refreshed on a hit (insertion order == timestamp order).
    while (_seen.isNotEmpty && _seen.values.first.isBefore(cutoff)) {
      _seen.remove(_seen.keys.first);
    }

    final key = _hex(e2EphPub);
    if (_seen.containsKey(key)) {
      return true;
    }
    _seen[key] = effectiveNow;
    if (_seen.length > maxSize) {
      _seen.remove(_seen.keys.first);
    }
    return false;
  }

  /// Current entry count. Test/diagnostic use only.
  int get length => _seen.length;

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
