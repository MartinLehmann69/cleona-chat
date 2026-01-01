/// The manifest in the post box (V4.2 §26.5.4 „Manifest freshness",
/// decision M1+ of 14.09.2026). S387.
///
/// The signed manifest lies in the post box of the neighbours under a
/// FIXED public 16-B value, separated by network channel
/// ([manifestValue]). Since S391 (proposal M) private post lies under
/// day values that only the owner of the day key can collect; the
/// compartment is the exception: everyone computes its value, everyone can deposit and
/// collect, and the holder demands NO proof under it
/// (`post_box_proof.dart` [compartmentQuestion]). Authenticity is carried solely by the
/// maintainer signature of the manifest; it is checked by the caller
/// ([ManifestCompartment.check]) and by the holder ([manifestVerifier]).
///
/// Asking happens at the moments at which the node asks the
/// post box anyway — start, network change, app opened, new neighbour —
/// and NEVER on a clock. Whoever calls [ManifestCompartment.ask] is the moment; this
/// file knows no timer.
///
/// ── READ, NEVER DELETED (V-1 variant B, S388) ───────────────────────
///
/// §8.2: „deletion … except the public manifest entry of §26.5.4, which is
/// read, never deleted"; §26.5.4: „Collecting the manifest does not delete
/// it". Until S388 the holder deleted the compartment on the receipt of the collector
/// like private post, and every asker therefore put a copy back after EVERY query
/// (proof of computation d = 18 per fetch, S387-BAU-UPDATE E-2).
/// Now the holder never deletes under it ([isManifestValue],
/// `post_box_holder.dart`), the collector does not acknowledge for deleting under it
/// (`post_box_deposit.dart`), and depositing only happens according to
/// the wording: „A node holding a verified manifest newer than the one it
/// is handed, or hearing ‚nothing here', places its own copy there."
/// Measured in `smoke_update_manifest_compartment` (10).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/update/update_carrier.dart' show UpdateCarrier;
import 'package:mycelium/card_address.dart' show kChannelBeta, kChannelLive;

/// The compartment accepts nothing larger — a manifest is a few KB.
const int kManifestAtMost = 64 * 1024;

final Map<int, Uint8List> _compartments = {};

/// The public 16-B value of the manifest compartment for [channel]
/// (`kKanalLive`/`kKanalBeta` from `card_address.dart`):
/// `SHA-256("cleona-update-manifest-fach-2" ‖ kanal)[0:16]`.
/// Deterministic: every node computes the same value.
Uint8List manifestValue(int channel) => _compartments.putIfAbsent(
    channel,
    () => Uint8List.fromList(SodiumFFI()
        .sha256(Uint8List.fromList(
            [...utf8.encode('cleona-update-manifest-compartment-2'), channel & 0xFF]))
        .sublist(0, 16)));

/// Whether [value] is that of a public manifest compartment (both channels):
/// under it no holder demands a proof, never deletes, and no collector
/// acknowledges for deleting.
bool isManifestValue(Uint8List value) =>
    _manifestValues.contains(_hexFrom(value));

/// With what a HOLDER checks a piece in the public manifest compartment:
/// validly signed -> sequence number (`monotoneSeq`), otherwise `null`.
///
/// ── WHY PROCESS-WIDE AND NOT PER HOLDER (S389, decision 20) ─────────
///
/// For the same reason as [isManifestValue] is a function and not a
/// field: there is ONE maintainer key and ONE
/// network channel per process, and the holder is built deep down
/// (`Node.start` -> `PostBoxDeposit` -> `PostBoxHolder`) — passing it
/// through three constructors would only pass on a constant.
/// Pre-set with the check of the app; a probe sets
/// its own.
///
/// The compartment is the ONLY value under which a holder looks at the content.
/// §8.2 „The holder cannot read the content" applies to private
/// post; the manifest is public, every node computes its value
/// and everyone knows the key against which it is checked. Without this
/// check a stranger fills the compartment with garbage that the holder
/// passes on (finding B-2, S388).
int? Function(Uint8List json) manifestVerifier = UpdateCarrier.manifestSequence;

final Set<String> _manifestValues = {
  for (final channel in const [kChannelLive, kChannelBeta])
    _hexFrom(manifestValue(channel)),
};

String _hexFrom(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class ManifestCompartment {
  /// The value of the compartment ([manifestValue]).
  final Uint8List compartment;

  /// Checks a manifest and returns its sequence number (`monotoneSeq`),
  /// or `null` if it is not validly signed.
  final int? Function(Uint8List json) check;

  /// Fetches what lies in the compartment. `null`: it was NOT asked (no neighbour,
  /// or the post box is currently occupied) — then nothing was
  /// deleted either, and nothing is put back.
  final Future<List<Uint8List>?> Function(Uint8List compartment) collect;

  /// Deposits [content] under the value [compartment] (`NodePostBox.deposit`).
  final Future<(bool done, int acknowledged)> Function(
      Uint8List content, Uint8List compartment) deposit;

  /// A newer valid manifest has arrived.
  void Function(Uint8List json)? onManifest;
  final void Function(String)? report;

  Uint8List? _best;
  int _bestSequence = -1;
  bool _asksCurrently = false;

  ManifestCompartment({
    required this.compartment,
    required this.check,
    required this.collect,
    required this.deposit,
    this.onManifest,
    this.report,
  });

  Uint8List? get best => _best;
  int get bestSequence => _bestSequence;

  /// A manifest that the caller already knows (cache, own
  /// check). Kept if it is valid and newer; no callback.
  bool known(Uint8List json) => _take(json) != null;

  /// ONE moment: ask the compartment, report something newer — and ONLY then deposit
  /// if the own checked manifest is newer than every one handed over or
  /// nothing valid came (§26.5.4). An invalid piece is not a
  /// manifest: whoever hears only such hears „nothing here".
  Future<void> ask() async {
    if (_asksCurrently) return;
    _asksCurrently = true;
    try {
      final pieces = await collect(compartment);
      if (pieces == null) return;
      var fresh = false;
      var passed = -1;
      for (final s in pieces) {
        final before = _bestSequence;
        final sequence = _take(s);
        if (sequence == null) {
          report?.call('Manifest compartment: invalid piece (${s.length} B) '
              'discarded');
          continue;
        }
        if (sequence > passed) passed = sequence;
        if (sequence > before) fresh = true;
      }
      final best = _best;
      if (pieces.isNotEmpty && passed < 0) {
        // B-3 (S388): towards the outside this is the same as „nothing here" — the
        // own manifest is deposited, otherwise a single
        // forgery would hold up every new deposit. In the log the two cases stay
        // distinguishable; since S389 the holder rejects forgeries itself
        // (`post_box_holder.dart`), so a hit here means: the
        // counterpart does not comply.
        report?.call('Manifest compartment: only invalid items handed over '
            '(${pieces.length} piece(s)) — like „nothing here"');
      }
      if (fresh && best != null) onManifest?.call(best);
      if (best == null || _bestSequence <= passed) return;
      final (done, acknowledged) = await deposit(best, compartment);
      report?.call('Manifest compartment: sequence $_bestSequence deposited (handed: '
          '${passed < 0 ? 'nothing valid' : 'sequence $passed'}, '
          '$acknowledged receipt(s)${done ? '' : ', incomplete'})');
    } finally {
      _asksCurrently = false;
    }
  }

  int? _take(Uint8List json) {
    if (json.isEmpty || json.length > kManifestAtMost) return null;
    final sequence = check(json);
    if (sequence == null) return null;
    if (sequence > _bestSequence) {
      _best = Uint8List.fromList(json);
      _bestSequence = sequence;
    }
    return sequence;
  }
}
