// The invitation line: which invitations are issued, which key each
// carries, and how a revocation works (§15.3).
//
// WHY THIS FILE EXISTS. The read side (`invite_class.dart`,
// `contact_seed.dart`) could DISPLAY an invitation class until now, but
// nobody could issue one — there was no `K_inv(i)` in the tree. A class
// without a key would be exactly the lie that §15.5 excludes with
// "enforced at the issuer": the seed would claim a promise whose carrier
// is missing.
//
// WHAT LIES HERE AND WHAT DOES NOT. Here lies the ledger: index, class,
// deadline, label, revocation, generation. The derivation itself lies in
// `HdWallet.deriveInviteRoot` / `deriveInviteKey` (§15.3.1) — where all
// other HD branches lie, so that the domain separation stays readable in
// ONE place. What does not lie here is the request buffer from
// §15.3.4 (max 20 per invitation / 100 total): it needs the request
// receive path, and that does not exist in the tree yet.
library;

import 'dart:typed_data';

import 'package:cleona/core/contact/invite_class.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';

/// §15.3.2, normative: "**Decided: hard cap of 10 simultaneously open
/// invitations**".
///
/// The reasoning stands there and is a cost computation, not a matter of
/// taste: per open invitation the issuer harvests three tag lines per
/// run. (Here stood "per epoch (current + 2 previous)"; since S362
/// `harvestEpochsPlan` scans the epoch axis up to
/// `kManagementKeepEpochs` — that does not change the NUMBER of tags per
/// run, only which epoch they carry, and the cap below relies only on
/// this number.) With few invitations these disappear into the decoy
/// slots; beyond that the harvest list becomes visible as a NUMBER
/// ("this node holds several invitations open").
const int kMaxOpenInvites = 10;

/// §15.3.3: "issuer-side harvest: until exp + max TTL (31 d) + 1 epoch
/// (14 d) = exp + 45 d".
///
/// **Harvest and expiry are decoupled, and that is the point.** Whoever
/// scans on day `exp - 1 h` while the issuer is offline for three days
/// would otherwise lose his request SILENTLY — exactly the error class
/// that the explicit expiry error abolishes. The leniency sits with the
/// issuer, because only he knows the truth about his harvest window.
///
/// Note on the numerical value: §15.3.3 computes "1 epoch (14 d)", while
/// appendix A gives the liveness/storage epoch as 24 h. Here the number
/// from §15.3.3 applies, because it is computed out there; the deviation
/// is noted in the report as a documentation line to be followed up.
const Duration kInviteHarvestGrace = Duration(days: 45);

/// §15.3.3: „Old `invite_root` generations are retained for the duration
/// of the maximum TTL, so that a `g_inv` bump does not destroy pending
/// first contacts."
const Duration kInviteGenerationRetention = Duration(days: 31);

/// §15.3.3: „After a recovery **with** a bundle, the invite line is
/// re-armed: indices `0 … Highwater + 32` (window `+32`)".
const int kInviteRecoveryWindow = 32;

/// An issued invitation.
///
/// The record carries NO key. `K_inv(i)` is computed from seed, identity
/// index, generation and [index] ([InviteLedger.keyFor]) and never
/// persisted — the same rule as for UserID/DeviceID (§4.1: "Neither is
/// persisted"). A stored copy could silently drift apart from a changed
/// derivation; recomputing makes every change immediately and loudly
/// visible.
class InviteRecord {
  /// `i` from §15.3.1 — monotonic per identity and generation.
  final int index;

  /// `g_inv` at the time of issuing. A mass revocation increments the
  /// ledger's generation; records of older generations remain, so that
  /// pending first contacts can still be harvested
  /// ([kInviteGenerationRetention]).
  final int generation;

  /// §15.3.1: the issuer chooses the class AT ISSUING. It is not a
  /// property of the format but of the path — that is why it is a
  /// mandatory field here and an optional one in the seed.
  final InviteClass inviteClass;

  /// `exp` in milliseconds since epoch; `null` = unlimited (§15.3.3).
  final int? expiresAtMs;

  /// The label with which the UI shows the attribution — §15.3.3:
  /// "Every incoming request is shown attributed to the invitation (‚via
  /// invitation ‚conference' from Aug 3')".
  final String label;

  final int createdAtMs;

  /// §15.4: "QR invitations are single-use" — an invitation of the
  /// auto-acceptance class via QR revokes itself after the first
  /// accepted request.
  final bool singleUse;

  bool revoked;
  int? revokedAtMs;

  /// Invalidated by a MASS REVOCATION (`g_inv` step), not by an individual
  /// revocation.
  ///
  /// The distinction is necessary because §15.3 requires two different
  /// things in two places:
  ///
  /// - §15.3.3, individual revocation: "remove the entry from the
  ///   expectation set, **drop the harvest**, done." — the harvest stops
  ///   IMMEDIATELY.
  /// - §15.3.3, mass revocation: "Old `invite_root` generations are
  ///   **retained** for the duration of the maximum TTL, so that a
  ///   `g_inv` bump **does not destroy pending first contacts**." — the
  ///   harvest continues, otherwise every already placed request is
  ///   lost.
  ///
  /// If both were the same field, one of the two guarantees would have to
  /// break silently. Which one would be decided by the chance of the
  /// implementation.
  bool retiredByGenerationBump;

  /// §15.3.3: as long as not ALL devices have confirmed the revocation,
  /// the invitation counts as **partially revoked** and is displayed
  /// exactly that way in the UI ("revoked, synchronization in
  /// progress"). A silent intermediate state is excluded.
  ///
  /// On a single-device node the revocation is complete immediately;
  /// that is why the default is `true`.
  bool revocationSynced;

  InviteRecord({
    required this.index,
    required this.generation,
    required this.inviteClass,
    required this.expiresAtMs,
    required this.label,
    required this.createdAtMs,
    this.singleUse = false,
    this.revoked = false,
    this.revokedAtMs,
    this.revocationSynced = true,
    this.retiredByGenerationBump = false,
  });

  /// §15.3.3 — expired from the SCANNER'S point of view (`t_scan < exp`).
  bool isExpiredAt(DateTime now) {
    final e = expiresAtMs;
    if (e == null) return false;
    return now.millisecondsSinceEpoch >= e;
  }

  /// §15.3.3 — end of the ISSUER'S harvest window. `null` for an
  /// unlimited invitation: it is harvested as long as it is not
  /// revoked.
  int? harvestUntilMs() {
    final e = expiresAtMs;
    if (e == null) return null;
    return e + kInviteHarvestGrace.inMilliseconds;
  }

  /// Whether the tag line of this invitation is still being listened to.
  ///
  /// The revocation closes it IMMEDIATELY — it is the issuer's harvest
  /// readiness and needs no network (§15.3.3: "On **one** device the
  /// revocation is therefore effective immediately: remove the entry from
  /// the expectation set, drop the harvest, done.").
  bool isHarvestedAt(DateTime now) {
    if (revoked) return false;
    final until = harvestUntilMs();
    if (until == null) return true;
    return now.millisecondsSinceEpoch < until;
  }

  /// Whether this invitation can still produce NEW requests.
  ///
  /// After a mass revocation that is `false` — the issuer no longer hands
  /// out the key —, while [isHarvestedAt] keeps saying `true` for the
  /// duration of the retention: the already PLACED requests are still
  /// collected.
  bool isOfferableAt(DateTime now) =>
      !revoked && !retiredByGenerationBump && !isExpiredAt(now);

  Map<String, dynamic> toJson() => {
        'i': index,
        'g': generation,
        'cls': inviteClass.wireChar,
        if (expiresAtMs != null) 'exp': expiresAtMs,
        'label': label,
        't': createdAtMs,
        if (singleUse) 'single': true,
        if (revoked) 'revoked': true,
        if (retiredByGenerationBump) 'retired': true,
        if (revokedAtMs != null) 'revokedAt': revokedAtMs,
        if (!revocationSynced) 'revSync': false,
      };

  /// Returns `null` if the record is not readable.
  ///
  /// **An unknown class makes the record invalid instead of setting it to
  /// a default.** On the read side a missing `cls` may become `null` —
  /// there it means "the issuer said nothing". Here it is the own ledger:
  /// an invitation whose class one no longer knows has an unknown promise,
  /// and one must not keep handing that out.
  static InviteRecord? fromJson(Map<String, dynamic> j) {
    final i = j['i'];
    final g = j['g'];
    final cls = InviteClass.fromWireChar(j['cls'] as String?);
    if (i is! int || g is! int || cls == null) return null;
    final t = j['t'];
    return InviteRecord(
      index: i,
      generation: g,
      inviteClass: cls,
      expiresAtMs: j['exp'] as int?,
      label: j['label'] as String? ?? '',
      createdAtMs: t is int ? t : 0,
      singleUse: j['single'] == true,
      revoked: j['revoked'] == true,
      retiredByGenerationBump: j['retired'] == true,
      revokedAtMs: j['revokedAt'] as int?,
      revocationSynced: j['revSync'] != false,
    );
  }
}

/// Reason for which an issuing was refused. A `null` return value without
/// a reason would here be the same silent failure that §15.3.4 forbids
/// for the request buffer.
///
/// ── WHY MORE THAN ONE VALUE STANDS HERE SINCE S381 ──────────────────────
///
/// Until S381 this type carried only [capReached] — after all, the ledger
/// knows only its own cap. The other three refusals arise one layer
/// higher (`CleonaService.issueInviteForSharing`) and became `null`
/// there; the reason stayed in the log line, and the UI then GUESSED the
/// most frequent one. A guessed reason is worse than none: whoever reads
/// "cap reached" revokes invitations, although in truth the master seed
/// was missing.
///
/// They therefore stand here, in the one type that already answers this
/// question — not in a second one next to it. Two paths to one fact
/// drift apart (the same reasoning as in the header of
/// `contact_seed_invite_gate.dart`).
///
/// The mapping to wire identifier and i18n key deliberately does NOT
/// stand here but in `invite_issue_refusal.dart`: this ledger should
/// stay checkable without UI and without process boundary.
enum InviteIssueRefusal {
  /// §15.3.2: ten simultaneously open invitations are the maximum.
  capReached,

  /// §21.4: the invitation ledger is there but cannot be decrypted.
  /// A fresh ledger would be the damage here, not the rescue — it would
  /// give a second invitation the same `K_inv(i)`.
  ledgerUnreadable,

  /// §15.3.1: this identity carries no master seed / HD index
  /// (legacy profile without HD derivation). Without it there is no `K_inv(i)`.
  noMasterSeed,

  /// The UI sent a class that does not exist.
  /// A program error, not a user state — still gets its own value,
  /// because otherwise it could not be distinguished from the others.
  unknownClass,

  /// The other side named a reason this version does not know,
  /// or none at all.
  ///
  /// THIS IS THE HONEST STATE. The obvious fallback would be the most
  /// frequent neighbour ([capReached]) — exactly the defect this
  /// extension stands against.
  unknownReason,
}

class InviteIssueException implements Exception {
  final InviteIssueRefusal reason;
  const InviteIssueException(this.reason);
  @override
  String toString() => 'InviteIssueException: $reason';
}

/// The ledger of the issued invitations of ONE identity.
///
/// Purely computational, without file and without clock: every method
/// that needs a "now" gets it passed in. The persistence lies in
/// `InviteStore` (`invite_store.dart`), so that this ledger stays
/// checkable without a profile.
class InviteLedger {
  /// `g_inv` (§15.3.1). One step invalidates all open invitations at
  /// once.
  int generation;

  /// §15.3.3 "Recovery": `Highwater` is the highest index ever assigned.
  /// It is a LOCAL counter and does not come from the 24 words —
  /// that is why it stands in the recovery package ([recoveryFields]).
  int highwater;

  final List<InviteRecord> records;

  /// Withdrawn generations with the time of the mass revocation.
  /// §15.3.3: retained for the duration of the maximum TTL, so that a
  /// `g_inv` step does not destroy pending first contacts.
  final Map<int, int> retiredGenerations;

  InviteLedger({
    this.generation = 0,
    this.highwater = -1,
    List<InviteRecord>? records,
    Map<int, int>? retiredGenerations,
  })  : records = records ?? <InviteRecord>[],
        retiredGenerations = retiredGenerations ?? <int, int>{};

  /// The open invitations — those that count against [kMaxOpenInvites].
  ///
  /// Open means: current generation, not revoked, not expired. An
  /// expired invitation no longer occupies a slot; it is still harvested
  /// ([InviteRecord.isHarvestedAt]), but it can no longer produce a new
  /// request, because the scanner rejects it
  /// (§15.3.3, `SeedRefusal.inviteExpired`).
  List<InviteRecord> openAt(DateTime now) => records
      .where((r) => r.generation == generation && r.isOfferableAt(now))
      .toList();

  /// The invitations whose tag line is being listened to now — including
  /// the grace period and including withdrawn generations, as long as
  /// their retention is running.
  List<InviteRecord> harvestedAt(DateTime now) => records.where((r) {
        if (!r.isHarvestedAt(now)) return false;
        if (r.generation == generation) return true;
        final retiredAt = retiredGenerations[r.generation];
        if (retiredAt == null) return false;
        return now.millisecondsSinceEpoch <
            retiredAt + kInviteGenerationRetention.inMilliseconds;
      }).toList();

  /// Issues an invitation (§15.3.1: the issuer chooses the class).
  ///
  /// [validity] `null` means unlimited — one of the four values from
  /// §15.3.3 (`kInviteValidityChoices`). The default value is NOT set
  /// here: whoever issues says how long. A silent 90-day default at this
  /// point would be a promise the UI would never have named.
  InviteRecord issue({
    required InviteClass inviteClass,
    required Duration? validity,
    required DateTime now,
    String label = '',
    bool singleUse = false,
  }) {
    if (openAt(now).length >= kMaxOpenInvites) {
      throw const InviteIssueException(InviteIssueRefusal.capReached);
    }
    final index = highwater + 1;
    highwater = index;
    final rec = InviteRecord(
      index: index,
      generation: generation,
      inviteClass: inviteClass,
      expiresAtMs: validity == null
          ? null
          : now.add(validity).millisecondsSinceEpoch,
      label: label,
      createdAtMs: now.millisecondsSinceEpoch,
      singleUse: singleUse,
    );
    records.add(rec);
    return rec;
  }

  InviteRecord? byIndex(int index, {int? generation}) {
    final g = generation ?? this.generation;
    for (final r in records) {
      if (r.index == index && r.generation == g) return r;
    }
    return null;
  }

  /// Individual revocation (§15.3.3). Returns `false` if the invitation
  /// does not exist.
  ///
  /// [multiDevice] `true` marks the state "revoked, synchronization
  /// running" — §15.3.3 requires that exactly this is visible and does not
  /// silently disappear. On a single-device node the revocation is
  /// complete immediately.
  ///
  /// [generation] `null` means "the current one". Explicitly specifiable,
  /// because the harvest window includes WITHDRAWN generations
  /// ([harvestedAt] / §15.3.3: "Old `invite_root` generations are
  /// retained … so that a `g_inv` bump does not destroy pending first
  /// contacts"). A request that arrived under an invitation of the
  /// PREVIOUS generation must be able to hit the same invitation —
  /// otherwise [consumeSingleUse] does not find the record and the line
  /// would stay armed although it is used up.
  bool revoke(int index, DateTime now,
      {bool multiDevice = false, int? generation}) {
    final rec = byIndex(index, generation: generation);
    if (rec == null) return false;
    rec.revoked = true;
    rec.revokedAtMs = now.millisecondsSinceEpoch;
    rec.revocationSynced = !multiDevice;
    return true;
  }

  /// §15.3.3: the revocation has arrived on all devices.
  bool markRevocationSynced(int index) {
    final rec = byIndex(index);
    if (rec == null) return false;
    rec.revocationSynced = true;
    return true;
  }

  /// **Mass revocation** (§15.3.1: "`g_inv` is a generation: an increment
  /// invalidates all open invitations at once, e.g. after a mass URI
  /// leak").
  ///
  /// One step at the root, not a pass over N individual revocations:
  /// after the step [keyFor] computes for EVERY existing invitation a
  /// different key than the one that stands in the issued seeds — the old
  /// tag lines no longer have a listener.
  ///
  /// **The index counter keeps running.** `Highwater` is NOT reset,
  /// although the new generation would have index 0 free again.
  /// Reason: `Highwater` is the quantity with which a recovery re-arms
  /// the line (`0 … Highwater + 32`, §15.3.3). A reset would make the
  /// window smaller than the set of invitations ever issued, and the
  /// computation "how many indices must I expect after a recovery" would
  /// no longer add up.
  ///
  /// **The pending first contacts, and why a switch stands here.**
  /// §15.3.1 says the step invalidates all open invitations "at
  /// once". §15.3.3 says old generations are retained for the duration of
  /// the maximum TTL, so that a `g_inv` step "does not destroy pending
  /// first contacts". Both at the same time is impossible: either the old
  /// tag line is still listened to (then a flooder keeps running along
  /// for another 31 days after a mass leak) or not (then everyone who
  /// scanned yesterday before the leak silently loses his request).
  ///
  /// The default follows the MORE SPECIFIC place — §15.3.3 speaks
  /// literally about the `g_inv` step —, so harvesting continues and only
  /// nothing new is handed out any more. Whoever wants the hard stop sets
  /// [dropPendingHarvest]; the UI must then name the price
  /// ("requests that are already in transit are lost").
  ///
  /// That the contradiction exists is a documentation finding and noted
  /// in the report — here it is made visible, not silently decided.
  ///
  /// Returns the new generation.
  int revokeAll(DateTime now, {bool dropPendingHarvest = false}) {
    retiredGenerations[generation] = now.millisecondsSinceEpoch;
    generation += 1;
    for (final r in records) {
      if (r.revoked) continue;
      r.retiredByGenerationBump = true;
      if (dropPendingHarvest) {
        r.revoked = true;
        r.revokedAtMs = now.millisecondsSinceEpoch;
      }
    }
    _pruneRetired(now);
    return generation;
  }

  void _pruneRetired(DateTime now) {
    final cutoff =
        now.millisecondsSinceEpoch - kInviteGenerationRetention.inMilliseconds;
    retiredGenerations.removeWhere((_, retiredAt) => retiredAt < cutoff);
  }

  /// §15.4: "he … revokes the QR invitation himself after the first
  /// acceptance."
  ///
  /// ── WHAT `singleUse` MEANS IN THIS TREE ─────────────────────────
  ///
  /// It is the attribute of the AUTO-ACCEPTANCE CLASS, not merely a
  /// counter. §15.4 lists both as ONE property: "Auto-acceptance and
  /// single-use are **properties of the invitation at the issuer**", and
  /// §15.3.3 says which invitations it affects — "invitations of the
  /// **auto-acceptance class via QR** are single-use", while for all
  /// others: "Reuse is allowed (party QR, printed business card)".
  ///
  /// The class alone is NOT sufficient as an attribute: according to
  /// `invite_class.dart`, `confidential` also covers the 1:1 handover via
  /// a trustworthy third-party channel, and per §15.4 that runs via the
  /// ordinary accept/reject. Whoever issues the invitation, on the other
  /// hand, knows whether it is shown as a QR code — that is why the
  /// attribute stands on the record and is set when issuing
  /// (`ContactShareCard._issue`).
  ///
  /// Returns `false` if the invitation does not exist or is usable
  /// multiple times — then there is NOTHING to consume, and that is not
  /// an error.
  bool consumeSingleUse(int index, DateTime now, {int? generation}) {
    final rec = byIndex(index, generation: generation);
    if (rec == null || !rec.singleUse) return false;
    return revoke(index, now, generation: generation);
  }

  /// `K_inv(i)` for [rec] (§15.3.1).
  ///
  /// Computes over the generation OF THE RECORD, not over the current
  /// one: after a mass revocation the issuer must still be able to open
  /// the pending first contacts of the old generation
  /// ([kInviteGenerationRetention]).
  Uint8List keyFor(
    Uint8List masterSeed,
    int identityIndex,
    InviteRecord rec,
  ) {
    final root =
        HdWallet.deriveInviteRoot(masterSeed, identityIndex, rec.generation);
    return HdWallet.deriveInviteKey(root, rec.index);
  }

  /// §15.3.3, normative: "**`g_inv` and `Highwater` are part of the
  /// recovery bundle (§13).**"
  ///
  /// Without the two, after a device loss every `K_inv(i)` is wrong,
  /// every tag wrong — and every printed invitation SILENTLY dead,
  /// without an expiry error, because it has not expired after all. That
  /// is why the ledger delivers them as a small package of its own; the
  /// incorporation into the recovery package itself is §13 work and lies
  /// outside this file.
  Map<String, int> get recoveryFields =>
      {'g_inv': generation, 'highwater': highwater};

  /// After a recovery WITH package: re-arm the line
  /// (§15.3.3, window `+32`).
  ///
  /// The return value is the highest index that is expected again.
  int rearmFromRecovery(int gInv, int recoveredHighwater) {
    generation = gInv;
    highwater = recoveredHighwater;
    return recoveredHighwater + kInviteRecoveryWindow;
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'g_inv': generation,
        'highwater': highwater,
        'records': records.map((r) => r.toJson()).toList(),
        'retired': retiredGenerations
            .map((k, v) => MapEntry(k.toString(), v)),
      };

  static InviteLedger fromJson(Map<String, dynamic> j) {
    final recs = <InviteRecord>[];
    final raw = j['records'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          final r = InviteRecord.fromJson(e);
          if (r != null) recs.add(r);
        }
      }
    }
    final retired = <int, int>{};
    final rawRetired = j['retired'];
    if (rawRetired is Map) {
      rawRetired.forEach((k, v) {
        final gen = int.tryParse('$k');
        if (gen != null && v is int) retired[gen] = v;
      });
    }
    final g = j['g_inv'];
    final hw = j['highwater'];
    return InviteLedger(
      generation: g is int ? g : 0,
      highwater: hw is int ? hw : -1,
      records: recs,
      retiredGenerations: retired,
    );
  }
}
