/// Verdict signature verification for decentralized moderation (§9.3.1a).
///
/// Verifies that jury verdicts carry enough valid hybrid signatures from
/// jurors within the tolerance set before applying badge/tombstone changes.
library;

import 'dart:typed_data';

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/moderation/jury_selection.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;

/// Result of a verdict verification.
enum VerdictVerification {
  verified,
  legacyUnproven,
  failed,
}

/// Verifies a JuryResultMsg's juror signatures against the tolerance set.
///
/// Returns [VerdictVerification.verified] if >= quorum valid **approval**
/// signatures from jurors within the tolerance set. Rejections and
/// abstentions are counted by nobody — a signature is bound to the vote it
/// was cast for (`vote` is inside [computeVerdictCoreHash]), so a genuine
/// rejection can never be re-read as consent (S368; before that fix every
/// valid signature counted, whatever it said).
///
/// The quorum bar is NEVER taken from the message's own vote counts alone:
/// those three fields are unsigned. They may raise the bar, never lower it
/// below `juryHardQuorum(juryMinSize)`.
/// Returns [VerdictVerification.legacyUnproven] if no signatures present
/// (legacy builds, Phase 1 observe-only).
/// Returns [VerdictVerification.failed] if signatures present but
/// insufficient valid ones pass verification.
VerdictVerification verifyJuryVerdict({
  required proto.JuryResultMsg result,
  required List<JurorRecord> registeredJurors,
  required ReportCategory category,
  required ModerationConfig config,
  required SodiumFFI sodium,
  required OqsFFI oqs,
}) {
  if (result.jurorSigs.isEmpty) {
    return VerdictVerification.legacyUnproven;
  }

  // The selection point H must be recomputed exactly as it was at jury
  // creation (`_createJurySession`/`_handleJuryTimeout`,
  // `channel_moderation_service.dart`): keyed on the report's
  // `ReportCategory.index`, NOT on `result.consequence`
  // (`JuryConsequence.index`). `JuryResultMsg` carries only the latter —
  // `consequenceForCategory()` is a many-to-one map (e.g. illegalDrugs,
  // illegalWeapons and illegalOther all fold onto `deleteChannel`), so a
  // caller must pass the original [category] explicitly; deriving it from
  // `result.consequence` silently produces the wrong H for exactly the
  // categories that collide, and every juror signature is then checked
  // against the wrong tolerance set. Verified against the enum orders in
  // moderation_config.dart: index equality only holds by coincidence for
  // notSafeForWork/falseContent/illegalDrugs.
  final selectionPoint = computeSelectionPoint(
    channelId: Uint8List.fromList(result.channelId),
    categoryIndex: category.index,
    epochDay: result.epochDay,
    juryRound: result.juryRound,
    sodium: sodium,
  );

  // The three count fields are the ONLY thing this message says about the
  // size of the jury — and they are NOT in the signed core:
  // `computeVerdictCoreHash` covers juryId, channelId, reportId, vote,
  // consequence, epochDay and juryRound, not the tally. Whoever presents the
  // result thus chooses them freely. They must therefore PROVE nothing;
  // at most they may raise the bar.
  final claimedTally =
      result.votesApprove + result.votesReject + result.votesAbstain;
  if (claimedTally == 0) return VerdictVerification.failed;

  // Number of APPROVALS this proof carries — not the number of
  // signatures. A signature is bound to its vote value (`vote`
  // is in the core, see below), so a rejection cannot be reinterpreted
  // as an approval; it was counted until S368 nonetheless.
  var approvalSigCount = 0;

  for (final sig in result.jurorSigs) {
    // S368: for an APPROVAL quorum only approvals count. Previously
    // at the end of this loop stood a bare `validSigCount++`: a
    // unanimously REJECTING jury thus delivered three valid signatures,
    // and an initiator who claimed `votesApprove = 3` and enclosed the same
    // unchanged rejections got `verified` — the
    // signatures never proved his claim, they only proved that
    // a vote had taken place at all. Re-measured S368 on the live
    // receive path (`handleIncomingJuryResult` logged "verdict
    // verification OK" for exactly this set).
    //
    // `JuryVote` and `JuryVoteResult` (service_types.dart) map the same
    // wire value; the coupling is held by a check in
    // `smoke_jury_verdict_verification.dart`, not only by this comment.
    if (sig.vote != JuryVote.approve.index) continue;
    if (sig.sigEd25519.isEmpty || sig.sigMlDsa.isEmpty) continue;

    final jurorRecordId = computeJurorRecordId(
        Uint8List.fromList(sig.jurorUserId), sodium);

    // Tolerance check: juror must be within top 2× jurySize
    if (!isWithinToleranceSet(
      jurorRecordId: jurorRecordId,
      selectionPoint: selectionPoint,
      registeredJurors: registeredJurors,
      toleranceFactor: config.jurorSetToleranceFactor,
      jurySize: claimedTally,
    )) {
      continue;
    }

    // Recompute the verdict core hash this juror should have signed
    final verdictCore = computeVerdictCoreHash(
      juryId: Uint8List.fromList(result.juryId),
      channelId: Uint8List.fromList(result.channelId),
      reportId: Uint8List.fromList(result.reportId),
      vote: sig.vote,
      consequence: result.consequence,
      epochDay: result.epochDay,
      juryRound: result.juryRound,
      sodium: sodium,
    );

    // Verify Ed25519 signature
    final ed25519Valid = sodium.verifyEd25519(
      verdictCore,
      Uint8List.fromList(sig.sigEd25519),
      Uint8List.fromList(sig.jurorUserId),
    );
    if (!ed25519Valid) continue;

    // Find juror's ML-DSA public key from registry
    final jurorRecord = registeredJurors.firstWhere(
      (j) => _bytesEqual(j.userPubKeyEd25519, Uint8List.fromList(sig.jurorUserId)),
      orElse: () => JurorRecord(
        recordId: Uint8List(0),
        userPubKeyEd25519: Uint8List(0),
        userPubKeyMlDsa: Uint8List(0),
        creationEpochMs: 0,
        selfSigEd25519: Uint8List(0),
        selfSigMlDsa: Uint8List(0),
      ),
    );
    if (jurorRecord.userPubKeyMlDsa.isEmpty) continue;

    final mlDsaValid = oqs.mlDsaVerify(
      verdictCore,
      Uint8List.fromList(sig.sigMlDsa),
      jurorRecord.userPubKeyMlDsa,
    );
    if (!mlDsaValid) continue;

    approvalSigCount++;
  }

  // S368, second half of the same finding: until now the bar likewise came
  // from `claimedTally`. Whoever possessed only ONE genuine approval
  // therefore claimed a jury of size 1 — `ceil(2/3 · 1) = 1` — and
  // his single proof carried the quorum. The vote value filter above alone
  // would have left this path open.
  //
  // The floor is `juryMinSize`, and it is provable, not chosen:
  // `effectiveJurySize` never returns less (moderation_config.dart),
  // a genuine jury thus has at least that many members, and
  // `_resolveJury` measures its own bar against
  // `session.jurorNodeIds.length` >= juryMinSize. A verdict that the
  // initiator accepted himself can therefore not fail at this floor
  // — the bar here stays <= the one there. Upwards it continues
  // to follow the claim: whoever claims a larger jury raises only
  // his own bar.
  final quorumBasis =
      claimedTally < config.juryMinSize ? config.juryMinSize : claimedTally;
  final quorum = config.juryHardQuorum(quorumBasis);
  if (approvalSigCount >= quorum) {
    return VerdictVerification.verified;
  }

  return VerdictVerification.failed;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
