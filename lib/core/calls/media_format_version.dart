// Media format versioning for the audio/video channel (V1.18).
//
// Architecture §10.3.1 (live media transport), §10.4 (voice stack), §10.6
// (video). Wire fields: `CallInvite.caller_{audio,video}_format_{min,max}`
// and `CallAnswer.selected_{audio,video}_format` in `proto/app_payloads.proto`.
//
// WHAT FOR. There is no backward compatibility with 3.1, and that stays so
// (§10.4 "Compatibility: none, by decision"). This module does not
// establish it. It exists for the reverse case: so that a FUTURE version
// (3.3, 4.0, ...) can still talk with 3.2, instead of forcing a second hard
// cut.
//
// DISTINCTION FROM THE VERSION GATE ON CALL_INVITE (field 8, V1.12/V2.1). The
// two do not overlap and neither is superfluous:
//
//   * `caller_app_major_minor` is a one-sided FLOOR on the APP version.
//     It is not negotiated, and it cannot express what the
//     other side speaks. A 3.2 client shipped today carries
//     `>= 3002` set in concrete and thus accepts every future version
//     unconditionally — it can never learn that 3.4 media are
//     undecodable for it.
//   * The media format here is NEGOTIATED and is TWO-SIDED. It
//     describes the format, not the app.
//
// Field 8 answers "can we talk at all" and rejects 3.1.x, which
// carries neither the one nor the other field. This module answers "in
// which dialect" and acts exclusively above that floor.
//
// MODEL IN THE HOUSE. `PerMessageKem.acceptKemVersions` (per_message_kem.dart:65)
// keeps the same protocol-specific counter, independent of the app version,
// and rejects unknown versions instead of waving them through. That the
// acceptance set there changed from {1} to {2} (v1 removed in V3.1.72)
// is at the same time the evidence that old formats are dropped — that is why
// the negotiation here carries a minimum and not just a maximum.
//
// Pure logic: no sockets, no proto dependency, no state. The
// wiring in `call_service.dart` together with a rejection reason visible to the user
// belongs to V2.1 (BUGFIX_CURRENT.md AV-V1.18).

/// Outcome of a format negotiation.
enum MediaFormatOutcome {
  /// Both sides have a common format. [MediaFormatDecision.selected]
  /// carries it.
  agreed,

  /// The ranges do not overlap. The call is rejected — with
  /// a reason visible to the user. §10.4: "never allowed to fail
  /// silently, which would reproduce exactly the field symptoms this rewrite
  /// removes".
  incompatible,
}

/// Result of a negotiation or of a check of the counter-choice.
class MediaFormatDecision {
  final MediaFormatOutcome outcome;

  /// The chosen format. Only meaningful for [MediaFormatOutcome.agreed].
  final int selected;

  /// Plain-text rationale for log and error report. NOT the translated
  /// text for the user — the i18n keys in all 34 locales are created by V2.1
  /// (working rule 7), together with the display.
  final String detail;

  const MediaFormatDecision._(this.outcome, this.selected, this.detail);

  bool get isAgreed => outcome == MediaFormatOutcome.agreed;

  @override
  String toString() =>
      'MediaFormatDecision(${outcome.name}, selected=$selected, $detail)';
}

/// A contiguous range of supported format versions.
///
/// Contiguous and not as a set, because the acceptance set of this
/// project has always been contiguous (see `acceptKemVersions`) and a
/// set on the wire would be more expensive than its benefit.
class MediaFormatRange {
  final int min;
  final int max;

  const MediaFormatRange(this.min, this.max);

  bool contains(int v) => v >= min && v <= max;

  @override
  String toString() => '[$min,$max]';
}

/// Policy and constants of media format versioning.
class MediaFormatVersion {
  MediaFormatVersion._();

  /// The base format: the media stack as shipped by 3.2.0.
  ///
  /// Counts up independently of the app version, just like
  /// `PerMessageKem.currentKemVersion`. A patch release does not change the format;
  /// a format change can lie in any future version.
  static const int kBaselineFormat = 1;

  /// What this build speaks in audio. Today only the base format.
  /// Rises as soon as §10.4 step 5 (Opus) changes the frame format.
  static const MediaFormatRange audio =
      MediaFormatRange(kBaselineFormat, kBaselineFormat);

  /// What this build speaks in video. Today only the base format.
  /// Rises as soon as §10.6 step 4/5 (platform hardware codec) changes the
  /// frame format.
  static const MediaFormatRange video =
      MediaFormatRange(kBaselineFormat, kBaselineFormat);

  /// Interprets a format value read from the wire.
  ///
  /// A MISSING FIELD IS A STATEMENT, NOT A GAP. proto3 delivers 0.
  /// Only a build from 3.2.0 on that was created before V1.18 can omit the field
  /// — and that one speaks exactly the base format. 0 here therefore
  /// by definition means [kBaselineFormat], not "unknown, so probably fine".
  ///
  /// That is deliberately the opposite conclusion from `caller_app_major_minor`,
  /// where 0 leads to rejection: there the 0 comes from a 3.1.x client that
  /// cannot hold a call at all, here from a 3.2.0 client that
  /// can. Same rule, different facts.
  static int normalize(int wireValue) =>
      wireValue == 0 ? kBaselineFormat : wireValue;

  /// Reads a range from the wire. Both fields are normalised individually.
  ///
  /// A range twisted by the peer (min > max) is not silently
  /// straightened out — it stays twisted and leads to rejection in [negotiate].
  /// A peer that sends nonsense gets no call, no
  /// repair.
  static MediaFormatRange rangeFromWire(int wireMin, int wireMax) =>
      MediaFormatRange(normalize(wireMin), normalize(wireMax));

  /// Callee side: chooses the highest format that BOTH speak.
  ///
  /// The highest common one and not the own highest — exactly here
  /// future backward compatibility arises. If the peer speaks more
  /// than we do, we downshift instead of rejecting it.
  ///
  /// Both directions are covered:
  ///  * peer maximum HIGHER than the own -> the own maximum is chosen
  ///    (downshifting). The actual purpose of this module.
  ///  * peer maximum LOWER than the own -> the peer maximum is
  ///    chosen, provided it does not fall below the own minimum. If it falls
  ///    below, we have dropped this format -> rejection.
  static MediaFormatDecision negotiate({
    required MediaFormatRange peer,
    required MediaFormatRange own,
    String kind = 'media',
  }) {
    if (peer.min > peer.max) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: peer range is inverted ($peer) — not a valid offer',
      );
    }
    final lo = peer.min > own.min ? peer.min : own.min;
    final hi = peer.max < own.max ? peer.max : own.max;
    if (hi < lo) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: no overlap — peer $peer, own $own',
      );
    }
    return MediaFormatDecision._(
      MediaFormatOutcome.agreed,
      hi,
      '$kind: $hi chosen from peer $peer and own $own',
    );
  }

  /// Caller side: checks the callee's choice from `CallAnswer`.
  ///
  /// It is checked against the own range AND against what was actually
  /// offered, [offered]. A defective or malicious peer can thus not force a
  /// format that we never offered — not even if
  /// we could speak it in principle.
  static MediaFormatDecision verifySelection({
    required int wireSelected,
    required MediaFormatRange own,
    required MediaFormatRange offered,
    String kind = 'media',
  }) {
    final selected = normalize(wireSelected);
    if (!own.contains(selected)) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: peer chose $selected, which this build does not speak '
        '(own $own)',
      );
    }
    if (!offered.contains(selected)) {
      return MediaFormatDecision._(
        MediaFormatOutcome.incompatible,
        0,
        '$kind: peer chose $selected, which was not offered '
        '(offered $offered)',
      );
    }
    return MediaFormatDecision._(
      MediaFormatOutcome.agreed,
      selected,
      '$kind: choice $selected confirmed',
    );
  }
}
