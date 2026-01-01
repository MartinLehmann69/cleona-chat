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
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// Result of a verdict verification.
enum VerdictVerification {
  verified,
  legacyUnproven,
  failed,
}

/// Verifies a JuryResultMsg's juror signatures against the tolerance set.
///
/// Returns [VerdictVerification.verified] if >= quorum valid signatures
/// from jurors within the tolerance set.
/// Returns [VerdictVerification.legacyUnproven] if no signatures present
/// (legacy builds, Phase 1 observe-only).
/// Returns [VerdictVerification.failed] if signatures present but
/// insufficient valid ones pass verification.
VerdictVerification verifyJuryVerdict({
  required proto.JuryResultMsg result,
  required List<JurorRecord> registeredJurors,
  required ModerationConfig config,
  required SodiumFFI sodium,
  required OqsFFI oqs,
}) {
  if (result.jurorSigs.isEmpty) {
    return VerdictVerification.legacyUnproven;
  }

  final selectionPoint = computeSelectionPoint(
    channelId: Uint8List.fromList(result.channelId),
    categoryIndex: result.consequence,
    epochDay: result.epochDay,
    juryRound: result.juryRound,
    sodium: sodium,
  );

  final nominalJurySize = result.votesApprove + result.votesReject + result.votesAbstain;
  if (nominalJurySize == 0) return VerdictVerification.failed;

  var validSigCount = 0;

  for (final sig in result.jurorSigs) {
    if (sig.sigEd25519.isEmpty || sig.sigMlDsa.isEmpty) continue;

    final jurorRecordId = computeJurorRecordId(
        Uint8List.fromList(sig.jurorUserId), sodium);

    // Tolerance check: juror must be within top 2× jurySize
    if (!isWithinToleranceSet(
      jurorRecordId: jurorRecordId,
      selectionPoint: selectionPoint,
      registeredJurors: registeredJurors,
      toleranceFactor: config.jurorSetToleranceFactor,
      jurySize: nominalJurySize,
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

    validSigCount++;
  }

  final quorum = config.juryHardQuorum(nominalJurySize);
  if (validSigCount >= quorum) {
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
