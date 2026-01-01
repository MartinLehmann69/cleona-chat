// Which of several recovery bundles counts (V4.2 §13.3.2, time of placement:
// "of several copies, the one whose keys are furthest along the rotation
// chain (§4.5.4) wins, among copies with the same keys the newest; copies
// whose chains fork are shown to the user and none is taken"; D-103).
//
// Pure functions: no service, no clock, no network. Three readers use them —
// the takeover in the recovery case (`_recoveryBundleFound`), the question
// of a fresh install (`_enrolBundleFound`) and the derivation run
// (`identityRunNewest`, §13.7) — and the retired-device check before a
// renewal (§13.3.4), which compares a found bundle with the own keys.
//
// ── WHAT A POSITION ON THE CHAIN IS ──────────────────────────────────────
//
// A key path is the list of Ed25519 signing public keys from the founding
// key to the current one: without a rotation one entry, after n rotations
// n + 1. Path B continues path A when A is a proper prefix of B; equal paths
// are the same keys; when neither is a prefix of the other, the chains fork
// (two successors of one key, §4.5.4). Every link is signed with Ed25519 AND
// ML-DSA-65 by its predecessor, and a fresh Ed25519 key is random, so the
// Ed25519 part names a link uniquely; whether a chain HOLDS is checked where
// keys are adopted (`RotationChain.holds`), not here — a bundle opens only
// under the seed, so what is compared here was written by a holder of the
// words.
//
// A copy without keys (the minimal bundle of a deleted index, §13.7) has no
// position: against it only the time decides, as before D-103.

import 'dart:typed_data';

import 'recovery_bundle_content.dart';

/// How a key path stands to another one.
enum KeyPathOrder {
  /// The same keys.
  same,

  /// One rotation or more further along the chain.
  ahead,

  /// An earlier link of the same chain.
  behind,

  /// Neither continues the other: two successors of one key.
  fork,

  /// One of the two carries no keys — only the time can decide.
  unknown,
}

/// The key path from the founding signing key to [current] along [links]
/// (each link: the key it replaced and the key that replaced it). Without
/// links: `[current]`.
List<Uint8List> keyPathOf(Uint8List current,
    Iterable<({Uint8List oldPk, Uint8List newPk})> links) {
  final list = links.toList();
  if (list.isEmpty) return [current];
  return [list.first.oldPk, for (final l in list) l.newPk];
}

/// The key path of an opened bundle; empty when it carries no keys (a
/// minimal bundle with `active = false`, §13.7).
List<Uint8List> bundleKeyPath(RecoveryBundleContent c) {
  if (c.ed25519SecretKey.length != 64) return const [];
  return keyPathOf(Uint8List.sublistView(c.ed25519SecretKey, 32), [
    for (final l in c.rotationChain)
      (oldPk: l.oldEd25519Pk, newPk: l.newEd25519Pk)
  ]);
}

/// Where [other] stands relative to [mine].
KeyPathOrder keyPathOrder(List<Uint8List> mine, List<Uint8List> other) {
  if (mine.isEmpty || other.isEmpty) return KeyPathOrder.unknown;
  final shorter = mine.length < other.length ? mine.length : other.length;
  for (var i = 0; i < shorter; i++) {
    if (!_equal(mine[i], other[i])) return KeyPathOrder.fork;
  }
  if (mine.length == other.length) return KeyPathOrder.same;
  return other.length > mine.length ? KeyPathOrder.ahead : KeyPathOrder.behind;
}

/// The copy that counts among [opened] (`null` entries are copies that did
/// not open): the one furthest along the chain, among the same keys the
/// newest. [fork]: two copies fork — then [best] is `null`, none is taken.
({RecoveryBundleContent? best, bool fork}) recoveryBundleChoose(
    Iterable<RecoveryBundleContent?> opened) {
  final all = [for (final c in opened) ?c];
  RecoveryBundleContent? best;
  for (final c in all) {
    if (best == null) {
      best = c;
      continue;
    }
    switch (keyPathOrder(bundleKeyPath(best), bundleKeyPath(c))) {
      case KeyPathOrder.ahead:
        best = c;
      case KeyPathOrder.same:
      case KeyPathOrder.unknown:
        if (c.depositedAtMs > best.depositedAtMs) best = c;
      case KeyPathOrder.behind:
      case KeyPathOrder.fork:
        break;
    }
  }
  if (best == null) return (best: null, fork: false);
  final path = bundleKeyPath(best);
  // No copy continues two forking ones, so a fork among the copies is a
  // fork against the chosen one.
  for (final c in all) {
    if (keyPathOrder(path, bundleKeyPath(c)) == KeyPathOrder.fork) {
      return (best: null, fork: true);
    }
  }
  return (best: best, fork: false);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
