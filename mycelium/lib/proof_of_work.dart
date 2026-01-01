import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';

/// The proof of computation before unsealing.
///
/// Bob's invitation is public: anyone who has the code can send a
/// contact request. The sender of a request sits in the seal and
/// is therefore known only AFTER unsealing — a limit per sender is
/// therefore impossible (identities are free, and before unsealing
/// there is nobody one could limit). This file instead delivers
/// a proof of computation that the recipient CHECKS BEFORE he
/// unseals: `SHA-256(code ++ randomValue ++ counter ++ timeWindow)` must
/// have [d] leading zero bits. Whoever does not provide the proof does not
/// even get an unsealing attempted.
///
/// **Property 1 — the code never stands in plaintext in the packet.** An attacker
/// who intercepts a request should not learn from it which code
/// was hit (codes can differ per contact or per channel).
/// Therefore the packet on the wire contains only [randomValue],
/// [counter] and the time window — never [code] itself. The recipient knows
/// his own codes and tries them through: [codeFind] keeps this limited to
/// at most ten SHA-256 calls, which for the recipient is
/// negligible compared to the cost the sender had to bear for ONE
/// valid proof.
///
/// **Property 2 — a solution becomes outdated after ~10 minutes.** [timeWindow]
/// enters as hash input: whoever shows a proof for an old window,
/// its hash no longer matches against the current window — so it
/// needs no separate expiry check, the time window IS part
/// of the checked condition. Within a window [RetryStore] prevents
/// the same [randomValue] from passing as new twice
/// (otherwise an intercepted valid proof could be reused arbitrarily
/// often while the window runs).
///
/// **Property 3 — a missing or wrong proof is silently
/// discarded.** This file makes no network decision on this (it opens
/// no wire), but it is built so that the caller CAN discard silently:
/// [check] returns a simple `bool`, no exception,
/// no distinguishable error text — whoever gets `false` does not unseal
/// and does not answer. An answer packet on a wrong proof would itself
/// already be a signal to the attacker and a target for a second flood.
class ProofOfWork {
  ProofOfWork._();

  /// Length of `code` in bytes.
  static const int codeLength = 16;

  /// Length of `zufallswert` in bytes.
  static const int randomValueLength = 8;

  /// Width of a time window in seconds (10 minutes).
  static const int windowSeconds = 600;

  /// Default for `hoechstzahlVersuche` in [generate] — generous: even
  /// at `d = 24` (expected value roughly 2^24 ≈ 16.8 million attempts) there
  /// remains plenty of safety margin upwards here.
  static const int maxCountAttemptsScheduled = 200000000;

  /// The current time window: Unix seconds integer-divided by
  /// [windowSeconds].
  static int windowNow() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ windowSeconds;

  /// Searches `(randomValue, counter)` such that
  /// `SHA-256(code ++ randomValue ++ counter ++ timeWindow)` has at least
  /// [d] leading zero bits. [randomValue] is drawn randomly once
  /// (it is the identifier that the retry store later checks
  /// against multiple submission); [counter] counts up from 0 until the
  /// condition holds or [maxCountAttempts] is exhausted.
  ///
  /// [timeWindow] can be overridden (tests, or a caller with
  /// its own clock); without it [windowNow] applies.
  static (Uint8List randomValue, int counter) generate(
    Uint8List code,
    int d, {
    int? timeWindow,
    int maxCountAttempts = maxCountAttemptsScheduled,
  }) {
    _codeCheck(code);
    final window = timeWindow ?? windowNow();
    final randomValue = SodiumFFI().randomBytes(randomValueLength);
    for (var counter = 0; counter < maxCountAttempts; counter++) {
      if (_fulfilled(code, randomValue, counter, window, d)) {
        return (randomValue, counter);
      }
    }
    throw ProofOfWorkAborted(
        'no proof with $d bits in $maxCountAttempts attempts');
  }

  /// Checks whether `(zufallswert, zaehler)` meets the condition for [d] against
  /// [code] and [timeWindow] (without it: [windowNow]).
  /// Exactly ONE SHA-256 call — that is the number that counts on the
  /// recipient.
  static bool check(
    Uint8List code,
    Uint8List randomValue,
    int counter,
    int d, {
    int? timeWindow,
  }) {
    _codeCheck(code);
    if (randomValue.length != randomValueLength) {
      throw ArgumentError(
          'randomValue must be $randomValueLength B, was ${randomValue.length}');
    }
    final window = timeWindow ?? windowNow();
    return _fulfilled(code, randomValue, counter, window, d);
  }

  /// What the recipient does before he unseals: tries through the own
  /// codes (at most the first ten from [ownCodes]) and returns
  /// the first against which `(zufallswert, zaehler)` meets the condition
  /// for [d] — or `null` if none fits.
  static Uint8List? codeFind(
    List<Uint8List> ownCodes,
    Uint8List randomValue,
    int counter,
    int d, {
    int? timeWindow,
  }) {
    final window = timeWindow ?? windowNow();
    for (final code in ownCodes.take(10)) {
      if (_fulfilled(code, randomValue, counter, window, d)) {
        return code;
      }
    }
    return null;
  }

  /// [codeFind] for the current AND the previous time window — v4_2 §15:
  /// "A solution ages. The time window makes it valid for about ten minutes
  /// … the current and the previous window". With the current one alone, a
  /// request computed at xx:x9:58 and checked at xx:x0:00 was silently
  /// discarded (S397-6, measured 25.09.2026); the post box checks the same
  /// two windows (`post_box_proof_of_work.dart`).
  static Uint8List? codeFindRecent(
      List<Uint8List> ownCodes, Uint8List randomValue, int counter, int d) {
    final now = windowNow();
    return codeFind(ownCodes, randomValue, counter, d, timeWindow: now) ??
        codeFind(ownCodes, randomValue, counter, d, timeWindow: now - 1);
  }

  static bool _fulfilled(
      Uint8List code, Uint8List randomValue, int counter, int window, int d) {
    final hash = SodiumFFI().sha256(_input(code, randomValue, counter, window));
    return _leadingZeroBits(hash) >= d;
  }

  static Uint8List _input(
      Uint8List code, Uint8List randomValue, int counter, int window) {
    final b = Uint8List(codeLength + randomValueLength + 8 + 8);
    var i = 0;
    b.setRange(i, i += codeLength, code);
    b.setRange(i, i += randomValueLength, randomValue);
    ByteData.sublistView(b).setUint64(i, counter, Endian.little);
    i += 8;
    ByteData.sublistView(b).setUint64(i, window, Endian.little);
    i += 8;
    return b;
  }

  static void _codeCheck(Uint8List code) {
    if (code.length != codeLength) {
      throw ArgumentError('code must be $codeLength B, was ${code.length}');
    }
  }

  /// Leading zero bits of a hash, most significant byte first.
  static int _leadingZeroBits(Uint8List hash) {
    var n = 0;
    for (final byte in hash) {
      if (byte == 0) {
        n += 8;
        continue;
      }
      var rest = byte;
      while (rest & 0x80 == 0) {
        n++;
        rest = (rest << 1) & 0xFF;
      }
      break;
    }
    return n;
  }
}

/// [ProofOfWork.generate] has exhausted [ProofOfWork.maxCountAttemptsScheduled] or
/// the passed limit without meeting the condition —
/// practically ruled out in planned use (see the doc comment
/// of the constant), therefore an exception and not a silent null value.
class ProofOfWorkAborted implements Exception {
  final String reason;
  ProofOfWorkAborted(this.reason);
  @override
  String toString() => 'NachweisAbgebrochen: $reason';
}

/// Remembers seen `randomValue`s across the current and the previous
/// time window (property 2 of the proof: a solution must not pass as new twice
/// within its validity). Every call of
/// [fresh] re-dates the memory to the passed [timeWindow]: everything
/// older than `timeWindow - 1` drops out before checking. After two
/// window changes an entry is therefore surely forgotten, regardless
/// of whether it was queried again in between.
///
/// Capped at [maxCount] entries in total, against an attacker
/// who can no longer submit a single valid proof more than once,
/// but produces enough DIFFERENT valid proofs to tie up memory
/// — at full capping the oldest entry drops first.
class RetryStore {
  final int maxCount;
  final Map<String, int> _seen = <String, int>{};

  RetryStore({this.maxCount = 1000});

  /// `true`: [randomValue] was new and is now remembered. `false`: already
  /// seen — the caller rejects the request as a repetition.
  bool fresh(Uint8List randomValue, int timeWindow) {
    _seen.removeWhere((_, window) => window < timeWindow - 1);
    final key = _hex(randomValue);
    if (_seen.containsKey(key)) {
      return false;
    }
    if (_seen.length >= maxCount) {
      _seen.remove(_seen.keys.first);
    }
    _seen[key] = timeWindow;
    return true;
  }

  /// Number of currently remembered `zufallswert`s (for smoke/probe).
  int get count => _seen.length;

  static String _hex(Uint8List b) {
    final buf = StringBuffer();
    for (final byte in b) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}
