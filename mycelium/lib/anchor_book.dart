/// What an identity holds per identifier, and the ONE acceptance of a sender
/// (V4.2 §4.5.4 "What a receiver accepts", D-33).
///
/// ── WHY A BOOK ───────────────────────────────────────────────────────────
///
/// Since the identifier outlives a change of the signing keys (§4.1), an
/// envelope may arrive signed by keys this identity has never seen for that
/// identifier. Whether to believe them depends on what it already holds —
/// and on nothing else: the keys it holds, or keys a chain connects to them;
/// without prior state, keys a chain connects to the identifier. The book is
/// that prior state, handed to the post box by its mailbox
/// (`mailbox_book.dart`); a post box without a mailbox (probes, a node's
/// helper boxes) has [AnchorBook.none] — no prior state, which is exactly
/// the rule for a stranger.
///
/// The book is a property of the RECIPIENT's post box and not a parameter of
/// the envelope, so that no caller can open an envelope past it: every
/// sealed packet — message, receipt, pair notice, amendment, group key,
/// the three sealed packets of first contact — goes through [senderAccept].
library;

import 'dart:typed_data';

import 'package:mycelium/address.dart';
import 'package:mycelium/envelope.dart' show EnvelopeBroken;

/// The prior state of one identity about the identifiers it knows.
abstract class AnchorBook {
  /// The address (with its chain) held for [identifier], or `null`.
  Address? held(Uint8List identifier);

  /// [fresh] carries keys a checked chain connects to the held ones — it
  /// replaces them wherever this identity keeps them.
  void adopt(Address fresh);

  /// A chain that does not pass through the held keys: two successors of one
  /// key, evidence that the old keys are in other hands (§4.5.4). Shown to
  /// the user, never adopted.
  void fork(Address held, Address claimed);

  /// Has [identifier] acknowledged an envelope that carried this identity's
  /// own chain? Until then every envelope to it carries the chain (§4.5.4,
  /// the rule of the day's capsule, §4.3).
  bool chainAcked(Uint8List identifier);

  /// [from] acknowledged an envelope that carried this identity's chain —
  /// from now on envelopes to it leave the chain out (E-A7).
  void chainArrived(Address from);

  /// No prior state at all.
  static const AnchorBook none = _NoBook();
}

class _NoBook implements AnchorBook {
  const _NoBook();
  @override
  Address? held(Uint8List identifier) => null;
  @override
  void adopt(Address fresh) {}
  @override
  void fork(Address held, Address claimed) {}
  @override
  bool chainAcked(Uint8List identifier) => false;
  @override
  void chainArrived(Address from) {}
}

/// Accepts [claimed] — the sender address an envelope (or a group message)
/// names, its signatures already verified — or throws [EnvelopeBroken]:
///
///  1. [book] holds these keys for the identifier → accepted;
///  2. they are an EARLIER link than the held ones → superseded, discarded
///     (the envelope is not acknowledged — the throw prevents that);
///  3. without prior state: keys that found the identifier, or a chain
///     from the identifier to them → accepted;
///  4. a chain from the identifier to them that passes through the held
///     keys → accepted and adopted ([AnchorBook.adopt]);
///  5. a chain that does not → fork: reported, discarded;
///  6. anything else → discarded.
///
/// [chainAllowed] is `false` where no chain can travel (a group message):
/// then only 1 and the unrotated half of 3 apply.
Address senderAccept(AnchorBook book, Address claimed,
    {bool chainAllowed = true}) {
  final held = book.held(claimed.identifier);
  if (held != null) {
    if (held.sameKeys(claimed)) return claimed;
    if (held.chain.superseded(claimed.signingKeys)) {
      throw EnvelopeBroken('superseded keys');
    }
  } else if (!claimed.rotated) {
    return claimed;
  }
  if (!chainAllowed ||
      !claimed.rotated ||
      !claimed.chain.holds(claimed.identifier, claimed.signingKeys)) {
    throw EnvelopeBroken('keys not connected to the identifier');
  }
  if (held == null) return claimed;
  if (!claimed.chain.passesThrough(held.signingKeys)) {
    book.fork(held, claimed);
    throw EnvelopeBroken('fork');
  }
  book.adopt(claimed);
  return claimed;
}
