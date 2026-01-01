import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/update/update_manifest.dart';

/// The carrier of the public update in the delivery layer — what the
/// app needs from it without knowing the layer (S387).
///
/// v4_2 §26.5.4 (M1+: manifest in the post box, asked at the moments
/// start, network change, app open, new neighbour — never on a tick) and
/// §26.6.1 (P1: fetch the pieces of an object from a holder; the
/// always-on nodes hold what they have). The implementation is
/// `package:mycelium/update.dart`; it is hooked in via
/// `CleonaService.updateTraeger` from the seam.
///
/// This file does not import `mycelium`: `lib/core/update/` stays independent of the
/// delivery layer, and the cover fill (§5.5) can later
/// feed the same carrier without the app changing.
abstract class UpdateCarrier {
  /// ONE moment: ask the manifest slot. A newer valid manifest
  /// comes via [onManifest].
  Future<void> manifestAsk();

  /// The manifest that the app already holds checked — for giving back into the
  /// slot (§26.5.4 "places its own copy there").
  void manifestKnown(Uint8List json);

  set onManifest(void Function(Uint8List json)? callback);

  /// Fetches the object with SHA-256 [contentHash] and [length] B. `null`: no
  /// holder delivered it.
  Future<Uint8List?> piecesFetch(
      {required Uint8List contentHash, required int length});

  /// Ends a running [piecesFetch] (Z1: a newer target).
  void fetchAbort();

  /// Keeps a complete, checked object ready for others.
  void objectHold(
      Uint8List contentHash, Future<Uint8List?> Function() read);

  void objectRelease(Uint8List contentHash);

  /// The check that a carrier needs for the manifest slot: validly
  /// signed → sequence number, otherwise `null`.
  static int? manifestSequence(Uint8List json) {
    try {
      final m = UpdateChecker().verifyManifest(utf8.decode(json));
      return m?.minMonotoneSeq;
    } on Object {
      return null;
    }
  }
}
