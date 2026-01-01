// Trace of a social recovery set up BEFORE the CUT — three-valued.
//
// WHY THIS FILE EXISTS. V4.1 §13.8 ("Limits of recovery", l. 3320-3337
// of the version on `s330/ap1-naht-sanieren`) excludes social recovery
// normatively: "V4.1 has **no social-recovery procedure**. […] **No set of
// other people can restore an identity — in no number, in no combination,
// under no threshold.** […] there is no third route, and none is planned."
// The carrier was deleted with the CUT (`guardian_service.dart`, removed in
// `91b566dd`); the partial procedure `crypto/shamir_sss.dart` had zero
// callers since then and was likewise deleted in S368. There is thus no longer any
// procedure in the tree that could assemble a seed from shares.
//
// The FUNCTION is thereby settled — the DISPLAY is not. On a device that
// had set up five guardians before the CUT, the stores still lie:
// `key_migration.dart:242-243` rewrites them to this day on every
// key change (`guardian_shares.json`, `guardian_list.json`).
// `cleona_service.dart` output a hard-wired `false` for this until S361
// — the UI thus said "no backup set up" to a
// user who HAD set one up. For a recovery path that is
// the most expensive direction of the false display (gap G-8).
//
// THREE VALUES, NOT TWO. `none` here expressly only means: "in THIS
// profile directory on THIS device there is no store". It does NOT mean
// "this identity never had guardians": the guardian list was never reconciled between the
// devices — `TwinSyncType` in `proto/app_payloads.proto:985-1019`
// assigns 0-13 and 17 (14-16 are reserved, `:1006`), and none of these
// fifteen numbers carries guardian state. A second device
// of the same identity therefore regularly sees `none`, although the first device
// would have `present`. Whoever removes the third stage and maps `unknown` to `false`
// restores exactly the defect this file closes.
//
// NO FLUTTER, NO SERVICE: pure `dart:io`. The UI
// (`settings_screen.dart`) and `CleonaService` read the same measurement, so that
// GUI process and daemon do not keep two truths.

import 'dart:io';

/// What is known about a single legacy store.
enum LegacyGuardianTrace {
  /// Measured and not present — in the checked directory.
  none,

  /// Measured and present: guardian state from before the CUT lies here.
  present,

  /// NOT measured. The directory was named empty, is missing, or the
  /// operating system refused the information. Never report as `none`.
  unknown,
}

/// Traces of a guardian setup in a profile directory.
///
/// Two separate questions, because they concern two different persons:
/// [ownGuardians] is the own backup (who holds my shares),
/// [heldShares] are shares of FOREIGN identities that lie on this device.
/// The second question is not a display question of the owner, but
/// a leftover of foreign key material — it is measured and
/// reported, not cleared away automatically.
class LegacyGuardianDeposit {
  /// `guardian_list.json` — the own five guardians.
  /// The producer was `guardian_service.dart` `_saveGuardianList()`, called
  /// exclusively from `setupGuardians` (state `91b566dd^`, l. 109).
  /// The file thus exists exactly when the setup ran once.
  final LegacyGuardianTrace ownGuardians;

  /// `guardian_shares.json` — shares this device holds FOR OTHERS.
  final LegacyGuardianTrace heldShares;

  const LegacyGuardianDeposit({
    required this.ownGuardians,
    required this.heldShares,
  });

  /// The honest value when nothing could be measured at all.
  static const LegacyGuardianDeposit unmeasured = LegacyGuardianDeposit(
    ownGuardians: LegacyGuardianTrace.unknown,
    heldShares: LegacyGuardianTrace.unknown,
  );

  /// Some legacy store found for certain.
  bool get anyPresent =>
      ownGuardians == LegacyGuardianTrace.present ||
      heldShares == LegacyGuardianTrace.present;

  /// At least one of the two questions has remained open.
  bool get anyUnknown =>
      ownGuardians == LegacyGuardianTrace.unknown ||
      heldShares == LegacyGuardianTrace.unknown;

  /// Both questions measured and both empty.
  bool get measuredEmpty =>
      ownGuardians == LegacyGuardianTrace.none &&
      heldShares == LegacyGuardianTrace.none;

  /// Measures [profileDir] for legacy stores.
  ///
  /// Existence only, no decryption: the files lie under the
  /// file key of the identity (`file_encryption.dart:83` reads
  /// `$path.enc`). For the question "was there once a setup here" the
  /// directory entry suffices, and the path manages without key material.
  ///
  /// Also checked are the crash side pieces `.enc.tmp` / `.enc.old` that
  /// `file_encryption.dart:110` and `:201-203` create when writing — otherwise
  /// a crash in the middle of writing would falsely report `none`.
  static LegacyGuardianDeposit probe(String profileDir) {
    if (profileDir.trim().isEmpty) return unmeasured;
    try {
      if (!Directory(profileDir).existsSync()) return unmeasured;
    } on FileSystemException {
      return unmeasured;
    }
    return LegacyGuardianDeposit(
      ownGuardians: _traceOf(profileDir, 'guardian_list.json'),
      heldShares: _traceOf(profileDir, 'guardian_shares.json'),
    );
  }

  static LegacyGuardianTrace _traceOf(String profileDir, String name) {
    const suffixes = <String>['', '.enc', '.enc.tmp', '.enc.old'];
    try {
      for (final suffix in suffixes) {
        if (File('$profileDir/$name$suffix').existsSync()) {
          return LegacyGuardianTrace.present;
        }
      }
      return LegacyGuardianTrace.none;
    } on FileSystemException {
      return LegacyGuardianTrace.unknown;
    }
  }

  @override
  String toString() =>
      'LegacyGuardianDeposit(ownGuardians: ${ownGuardians.name}, '
      'heldShares: ${heldShares.name})';
}
