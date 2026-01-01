/// What a holder says to a deposit (`0x31`, `0x37`) and what it notes about
/// the deposits it does not take (v4_2 §8.2, §11.3a).
///
/// Split off from `post_box_holder.dart` (S407) for the line budget; the
/// holder decides, this file builds the answer packets and keeps the log.
///
/// **Answered or silent.** A deposit without a valid proof of work is not a
/// collector's request and is discarded silently (§8.2, row "a holder
/// answers"); so is one too short to carry a proof (§11.6). Every other
/// deposit the holder does not take is answered with `0x37` — a silent
/// refusal of a valid request is silence to the sender, and silence is
/// repeated (§11.3a). A manifest deposit of the sequence the holder already
/// holds is acknowledged (`0x31`): the holder holds that piece, the receipt
/// is true.
///
/// **Logged, bounded, without a clock.** Every discard is counted by reason
/// ([HolderLog.counts]); a line is written for the 1st, 2nd, 3rd, 10th,
/// 100th, … of a reason — a flood writes a handful of lines, never one per
/// packet (§20.2). No content, only the sender's address (redacted by the
/// app's log sink like every address) and the reason.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/post_box_disk.dart' show kIdLength, kValueLength;
import 'package:mycelium/post_box_proof.dart' show kRequestIdLength;
import 'package:mycelium/post_box_proof_of_work.dart' show kProofOfWorkLength;
import 'package:mycelium/post_box_runs.dart' show neighbourKey;
import 'package:mycelium/update_manifest_compartment.dart' show manifestVerifier;

/// A neighbour: only its network address — the neighbour sees only day values
/// and opaque bytes, the caller does not need more here either.
typedef Neighbour = (InternetAddress address, int port);

/// Sends [packet] to [target]. What it returns — in the node the splitter's
/// [SendEnd] — only the hand-out waits for (§8.2); everybody else fires and
/// forgets.
typedef Send = FutureOr<void> Function(Uint8List packet, Neighbour target);

/// Header of a 0x30 before the content: kind 1 + id 8 + day value 16 +
/// proof of computation 16 = 41 B. The one place where that is written.
const int kDepositHeader = 1 + kIdLength + kValueLength + kProofOfWorkLength;

/// Header of a 0x33 before the content: kind 1 + day value 16 + id 8 + count 1
/// + request identifier 8.
const int kHereItIsHeader = 1 + kValueLength + kIdLength + 1 + kRequestIdLength;

/// Length of the node identifier in `0x31` and `0x35` (text in the call).
const int kNodeIdentifierLength = 16;

/// 0x31 `Sorte | id | Knotenkennung 16 | Anfragekennung 8` — the deposited
/// receipt; the node identifier (B1, S388) counts one node under two
/// addresses once. It answers a deposit, not a question: the request
/// identifier is carried as zero (§8.2).
Uint8List receiptPacket(Uint8List id, Uint8List node) => (BytesBuilder()
      ..addByte(kinds.kDeposited)..add(id)..add(node)..add(Uint8List(kRequestIdLength)))
    .toBytes();

/// `0x37 | value | request` (§8.2): not handed out, or not taken. To a proof
/// [request] is the question's identifier; to a deposit it is the deposit's
/// id, by which the sender finds its run (`post_box_deposit.dart`).
Uint8List refusalPacket(Uint8List value, Uint8List request) =>
    (BytesBuilder()..addByte(kinds.kRefused)..add(value)..add(request)).toBytes();

/// Why a holder did not take a deposit.
enum DepositDiscard {
  /// Shorter than the deposit header — silent (§11.6).
  length('shorter than its header (§11.6)', silent: true),

  /// No valid proof of work for the holder's current or previous window —
  /// silent (§8.2).
  proofOfWork('no valid proof of work (§8.2)', silent: true),

  /// Its id is held under another value: a known id is never bent.
  idElsewhere('id already held under another value'),

  /// Under the public manifest value, but not a validly signed manifest.
  manifestInvalid('not a validly signed manifest'),

  /// Under the public manifest value, older than the one held.
  manifestOlder('manifest older than the one held');

  final String text;
  final bool silent;
  const DepositDiscard(this.text, {this.silent = false});
}

/// Whether the [n]th event of a kind gets a line: 1, 2, 3, 10, 100, 1000, …
bool lineFor(int n) {
  if (n <= 3) return true;
  while (n % 10 == 0) {
    n ~/= 10;
  }
  return n == 1;
}

/// The holder's notes on the deposits it does not take — counted always,
/// written by [lineFor].
class HolderLog {
  final void Function(String)? report;
  HolderLog(this.report);

  /// Discards by reason, since the start — diagnostics, read only.
  final Map<DepositDiscard, int> counts = {};

  /// Manifest deposits of the held sequence, acknowledged without storing.
  int sameManifest = 0;

  /// Saves of the held stock that took [kSlowSave] or longer.
  int slowSaves = 0;

  /// A deposit from [from] was not taken for [why]. [detail]: computed only
  /// when a line is written (it may cost a few hashes).
  void discarded(DepositDiscard why, Neighbour from,
      {String Function()? detail}) {
    final n = counts[why] = (counts[why] ?? 0) + 1;
    if (report == null || !lineFor(n)) return;
    final more = detail?.call() ?? '';
    report!('holder: deposit from ${neighbourKey(from)} not taken — ${why.text}'
        '${more.isEmpty ? '' : ' ($more)'}; '
        '${why.silent ? 'silent' : 'refused with 0x37'} '
        '— $n so far');
  }

  /// A manifest deposit of the sequence already held was acknowledged.
  void sameHeld(Neighbour from) {
    final n = ++sameManifest;
    if (report == null || !lineFor(n)) return;
    report!('holder: manifest deposit from ${neighbourKey(from)} of the sequence '
        'already held — acknowledged, nothing stored — $n so far');
  }

  /// One save of the held stock took [ms] for [entries] entries.
  void saved(int ms, int entries) {
    if (ms < kSlowSave.inMilliseconds) return;
    final n = ++slowSaves;
    if (report == null || !lineFor(n)) return;
    report!('holder: saving $entries held packet(s) took $ms ms '
        '— $n slow save(s) so far');
  }
}

/// From this duration on a save of a held packet is noted: it runs on the
/// node's event loop, and a receipt waits behind it.
const Duration kSlowSave = Duration(milliseconds: 250);

/// What a manifest piece is against the ONE held entry (decision 20).
enum Admit { yes, same, older, invalid }

/// [content] against [held] (`null`: nothing held), both checked by
/// [manifestVerifier], recomputed, never remembered. [orSame]: the held
/// sequence counts as admitted (the node renewing its own, §26.5.4).
Admit manifestAgainst(Uint8List content, Uint8List? held, {bool orSame = false}) {
  final sequence = manifestVerifier(content);
  if (sequence == null) return Admit.invalid;
  final old = held == null ? null : manifestVerifier(held);
  if (old == null || sequence > old) return Admit.yes;
  if (sequence < old) return Admit.older;
  return orSame ? Admit.yes : Admit.same;
}
