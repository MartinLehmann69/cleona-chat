import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/update/update_manifest.dart';
import 'package:mycelium/update_trace.dart';

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

  /// [contentHash] ([length] B) is the update target (S406-UPDPKG): its
  /// partial state is opened from disk, pieces of it arriving by cover fill
  /// are kept — also while fetching is locked (§24.4.2) — and every other
  /// object's state is deleted (§26.6.1 "pieces that do not serve it are
  /// discarded").
  void objectExpect(Uint8List contentHash, int length);

  /// Fetches the target [contentHash] ([length] B) from the holders. The
  /// path of the complete object (SHA-256 checked), or `null`: no holder
  /// delivered it — the partial state stays for the next moment.
  Future<String?> objectFetch(
      {required Uint8List contentHash, required int length});

  /// The target completed outside a fetch (cover fill): its path.
  set onObjectComplete(
      void Function(Uint8List contentHash, String path)? callback);

  /// The caller has checked and moved the object's file: its state goes.
  void objectTaken(Uint8List contentHash);

  /// The object failed its check: its whole state goes, it stays the target.
  void objectDiscard(Uint8List contentHash);

  /// Ends a running [objectFetch]; the partial state stays.
  void fetchAbort();

  /// Keeps a complete, checked object ready for others. [read] returns the
  /// WHOLE object — only for small in-memory objects (probes, smokes).
  void objectHold(
      Uint8List contentHash, Future<Uint8List?> Function() read);

  /// Keeps the file at [path] ready for others as the object [contentHash]
  /// without loading it: checked by streaming, served block by block from
  /// the file (S406-OOM — a held ~200 MB APK in memory OOM-killed the
  /// bootstrap daemon).
  void objectHoldFile(Uint8List contentHash, String path);

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

/// The files in the data directory from which a node knows a manifest of
/// its own: the one placed by hand or by the release pipeline
/// (`update_manifest.json`, read by `_selfPublishManifest`) and the one
/// last accepted (`update_manifest_cache.json`).
const List<String> kOwnManifestFiles = <String>[
  'update_manifest.json',
  'update_manifest_cache.json',
];

/// Hands every manifest file in [dataDir] to [carrier]
/// ([UpdateCarrier.manifestKnown]); the carrier keeps the newest validly
/// signed one and checks each itself. Returns how many files were handed
/// over. Unreadable files are skipped and reported via [report].
///
/// S406-UPD, finding U-3: until S406 the carrier got only the cache file.
/// A node that knows the manifest only from `update_manifest.json` — the
/// bootstrap after the pipeline seeds it — never wrote a cache file
/// (`_manifestsProcess` ends early on the same version and sequence), so
/// its manifest compartment stayed empty and it never placed the manifest
/// in the post box (§26.5.4 "places its own copy there").
int ownManifestsToCarrier(String dataDir, UpdateCarrier carrier,
    {void Function(String)? report}) {
  var handed = 0;
  for (final name in kOwnManifestFiles) {
    final file = File('$dataDir${Platform.pathSeparator}$name');
    try {
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final m = _traceManifest(bytes);
      updateTrace('manifest-file',
          seq: m?.minMonotoneSeq,
          version: m?.version,
          reason: '$name (${bytes.length} B) handed to the carrier'
              '${m == null ? ' — not validly signed' : ''}');
      carrier.manifestKnown(bytes);
      handed++;
    } on Object catch (e) {
      report?.call('[update] carrier: $name unreadable: $e');
    }
  }
  return handed;
}

/// The manifest in [bytes] for a trace line only — `null` if not validly
/// signed. Checked only while the diagnosis writes ([traceOn]).
UpdateManifest? _traceManifest(Uint8List bytes) {
  if (!traceOn) return null;
  try {
    return UpdateChecker().verifyManifest(utf8.decode(bytes));
  } on Object {
    return null;
  }
}
