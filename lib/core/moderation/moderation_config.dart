/// Central configuration for the decentralized moderation system.
///
/// Contains all timeouts, thresholds, and tuning parameters.
/// [ModerationConfig.production] provides production values,
/// [ModerationConfig.test] provides shortened values for automated tests.
class ModerationConfig {
  // ── Jury proceedings ──────────────────────────────────────────────

  /// Timeout before a juror must respond or be replaced.
  final Duration juryVoteTimeout;

  /// Minimum jurors per jury.
  final int juryMinSize;

  /// Maximum jurors: min([juryMaxSize], available × [juryMaxPercent]).
  final int juryMaxSize;

  /// Max. percent of available jurors (0.01 = 1%).
  final double juryMaxPercent;

  /// Required majority (0.667 = 2/3).
  final double juryMajority;

  /// Fallback: double threshold when fewer than [juryMinSize] available.
  final bool juryFallbackDoubleThreshold;

  // ── Report thresholds ──────────────────────────────────────────

  /// Number of reports in a category before a jury is triggered.
  /// Dynamically scalable — this is the base threshold.
  final int reportThresholdForJury;

  /// Max. reports per identity per day (spam protection).
  final int maxReportsPerIdentityPerDay;

  /// Escalation timeout: single post report → channel report.
  final Duration singlePostEscalationTimeout;

  // ── Bad Badge System ────────────────────────────────────────────

  /// Probation period after admin correction (level 1).
  final Duration badgeProbationLevel1;

  /// Probation period after admin correction (level 2).
  final Duration badgeProbationLevel2;

  // ── CSAM special procedure ────────────────────────────────────────

  /// Threshold stage 2 (temporary hiding): max([csamStage2Min], subscriber × [csamStage2Factor]).
  final int csamStage2Min;
  final double csamStage2Factor;

  /// Threshold stage 3 (permanent deletion): max([csamStage3Min], subscriber × [csamStage3Factor]).
  final int csamStage3Min;
  final double csamStage3Factor;

  /// Duration of temporary hiding (stage 2).
  final Duration csamTempHideDuration;

  /// Reporting cooldown after CSAM report (all categories).
  final Duration csamReporterCooldown;

  /// Strikes until CSAM reporting ban becomes permanent.
  final int csamMaxStrikes;

  // ── Reporter qualification ────────────────────────────────────────

  /// Minimum age of identity for standard reports.
  final Duration identityMinAge;

  /// Minimum age of identity for CSAM reports.
  final Duration identityMinAgeCSAM;

  /// Min. bidirectional conversation partners (CSAM).
  final int csamMinBidirectionalPartners;

  /// Min. received messages (CSAM).
  final int csamMinReceivedMessages;

  /// Min. long-term contacts (CSAM).
  final int csamMinLongtermContacts;

  /// When a contact qualifies as "long-term" (CSAM).
  final Duration csamLongtermContactAge;

  /// isAdult required for CSAM reports.
  final bool csamRequiresAdult;

  // ── Juror qualification ───────────────────────────────────────

  /// Minimum age of identity to serve as juror.
  final Duration jurorMinAge;

  /// Juror must have "I am over 18" enabled.
  final bool jurorRequiresAdult;

  /// Juror must have "Review channel reports" enabled.
  final bool jurorRequiresReviewEnabled;

  // ── Deterministic jury selection (§9.3.1a) ────────────────────

  /// Tolerance factor for verdict verification: a juror is accepted
  /// if within top (toleranceFactor × jurySize) closest to H.
  final int jurorSetToleranceFactor;

  /// Max replacement rounds for non-responding jurors.
  final int juryReplacementRounds;

  /// CSAM Stage 3 objection window before Tombstone is written.
  final Duration csamObjectionWindow;

  // ── Anti-Sybil ──────────────────────────────────────────────────

  /// Social Graph Reachability Check enabled.
  final bool reachabilityEnabled;

  /// Percent of validators that must reach the reporter (0.60 = 60%).
  final double reachabilityThreshold;

  /// Max. hops for reachability check.
  final int reachabilityMaxHops;

  /// Number of validator nodes for reachability check.
  final int reachabilityValidatorCount;

  // ── Independence check ───────────────────────────────────────

  /// Threshold for "connected": max([independenceMinGroupSize], totalUsers × [independenceGroupFactor]).
  final int independenceMinGroupSize;
  final double independenceGroupFactor;

  /// Direct contacts are always considered connected.
  final bool directContactsAlwaysConnected;

  // ── Squatting protection ────────────────────────────────────────────

  /// Minimum age of identity for channel creation.
  final Duration channelCreationMinAge;

  // ── Anonymous polls (§11.4.6) ───────────────────────────────────────

  /// Max random send delay for anonymous poll votes so arrival order does
  /// not hint at the voter (timing analysis, §11.4.6). Zero disables.
  final Duration anonVoteJitterMax;

  const ModerationConfig({
    // Jury
    this.juryVoteTimeout = const Duration(days: 2),
    this.juryMinSize = 5,
    this.juryMaxSize = 11,
    this.juryMaxPercent = 0.01,
    this.juryMajority = 2.0 / 3.0,
    this.juryFallbackDoubleThreshold = true,
    // Report thresholds
    this.reportThresholdForJury = 3,
    this.maxReportsPerIdentityPerDay = 5,
    this.singlePostEscalationTimeout = const Duration(days: 7),
    // Bad Badge
    this.badgeProbationLevel1 = const Duration(days: 30),
    this.badgeProbationLevel2 = const Duration(days: 90),
    // CSAM
    this.csamStage2Min = 10,
    this.csamStage2Factor = 0.05,
    this.csamStage3Min = 20,
    this.csamStage3Factor = 0.10,
    this.csamTempHideDuration = const Duration(days: 14),
    this.csamReporterCooldown = const Duration(days: 7),
    this.csamMaxStrikes = 3,
    // Reporter qualification
    this.identityMinAge = const Duration(days: 7),
    this.identityMinAgeCSAM = const Duration(days: 30),
    this.csamMinBidirectionalPartners = 10,
    this.csamMinReceivedMessages = 100,
    this.csamMinLongtermContacts = 3,
    this.csamLongtermContactAge = const Duration(days: 14),
    this.csamRequiresAdult = true,
    // Juror qualification
    this.jurorMinAge = const Duration(days: 7),
    this.jurorRequiresAdult = true,
    this.jurorRequiresReviewEnabled = true,
    // Deterministic jury selection
    this.jurorSetToleranceFactor = 2,
    this.juryReplacementRounds = 2,
    this.csamObjectionWindow = const Duration(days: 14),
    // Anti-Sybil
    this.reachabilityEnabled = true,
    this.reachabilityThreshold = 0.60,
    this.reachabilityMaxHops = 5,
    this.reachabilityValidatorCount = 10,
    // Independence
    this.independenceMinGroupSize = 50,
    this.independenceGroupFactor = 0.05,
    this.directContactsAlwaysConnected = true,
    // Squatting
    this.channelCreationMinAge = const Duration(days: 7),
    // Anonymous polls
    this.anonVoteJitterMax = const Duration(seconds: 30),
  });

  /// Production configuration with the values from docs/CHANNELS.md.
  factory ModerationConfig.production() => const ModerationConfig();

  /// Lab configuration for the 20-node moderation lab on test-server.
  /// Realistic jury sizes and anti-Sybil enabled, but shortened timeouts
  /// and no identity-age barriers (VMs are freshly initialized).
  factory ModerationConfig.lab() => const ModerationConfig(
        juryVoteTimeout: Duration(seconds: 30),
        juryMinSize: 5,
        juryMaxSize: 9,
        juryMaxPercent: 0.50,
        juryMajority: 2.0 / 3.0,
        juryFallbackDoubleThreshold: true,
        reportThresholdForJury: 2,
        maxReportsPerIdentityPerDay: 20,
        singlePostEscalationTimeout: Duration(seconds: 30),
        badgeProbationLevel1: Duration(seconds: 60),
        badgeProbationLevel2: Duration(seconds: 120),
        csamStage2Min: 3,
        csamStage2Factor: 0.05,
        csamStage3Min: 5,
        csamStage3Factor: 0.10,
        csamTempHideDuration: Duration(seconds: 45),
        csamReporterCooldown: Duration(seconds: 10),
        csamMaxStrikes: 3,
        identityMinAge: Duration.zero,
        identityMinAgeCSAM: Duration.zero,
        csamMinBidirectionalPartners: 2,
        csamMinReceivedMessages: 0,
        csamMinLongtermContacts: 0,
        csamLongtermContactAge: Duration.zero,
        csamRequiresAdult: true,
        jurorMinAge: Duration.zero,
        jurorRequiresAdult: true,
        jurorRequiresReviewEnabled: true,
        jurorSetToleranceFactor: 2,
        juryReplacementRounds: 2,
        csamObjectionWindow: Duration(seconds: 30),
        reachabilityEnabled: true,
        reachabilityThreshold: 0.60,
        reachabilityMaxHops: 5,
        reachabilityValidatorCount: 10,
        independenceMinGroupSize: 5,
        independenceGroupFactor: 0.05,
        directContactsAlwaysConnected: true,
        channelCreationMinAge: Duration.zero,
        anonVoteJitterMax: Duration(seconds: 2),
      );

  /// Test configuration with greatly shortened timeouts and disabled barriers.
  factory ModerationConfig.test() => const ModerationConfig(
        // Jury — seconds instead of days
        juryVoteTimeout: Duration(seconds: 10),
        juryMinSize: 3,
        juryMaxSize: 5,
        juryMaxPercent: 1.0, // no upper limit in test
        juryMajority: 2.0 / 3.0,
        juryFallbackDoubleThreshold: false,
        // Report thresholds — low
        reportThresholdForJury: 1, // immediate jury on first report
        maxReportsPerIdentityPerDay: 100,
        singlePostEscalationTimeout: Duration(seconds: 15),
        // Bad Badge — seconds instead of days/months
        badgeProbationLevel1: Duration(seconds: 30),
        badgeProbationLevel2: Duration(seconds: 60),
        // CSAM — low thresholds
        csamStage2Min: 2,
        csamStage2Factor: 0.05,
        csamStage3Min: 3,
        csamStage3Factor: 0.10,
        csamTempHideDuration: Duration(seconds: 20),
        csamReporterCooldown: Duration(seconds: 5),
        csamMaxStrikes: 3,
        // Qualification — disabled
        identityMinAge: Duration.zero,
        identityMinAgeCSAM: Duration.zero,
        csamMinBidirectionalPartners: 0,
        csamMinReceivedMessages: 0,
        csamMinLongtermContacts: 0,
        csamLongtermContactAge: Duration.zero,
        csamRequiresAdult: false,
        // Jurors — simplified
        jurorMinAge: Duration.zero,
        jurorRequiresAdult: false,
        jurorRequiresReviewEnabled: false,
        // Deterministic selection — same tolerance, fast replacement
        jurorSetToleranceFactor: 2,
        juryReplacementRounds: 2,
        csamObjectionWindow: Duration(seconds: 10),
        // Anti-Sybil — disabled in test
        reachabilityEnabled: false,
        reachabilityThreshold: 0.0,
        reachabilityMaxHops: 5,
        reachabilityValidatorCount: 3,
        // Independence — simplified
        independenceMinGroupSize: 2,
        independenceGroupFactor: 0.05,
        directContactsAlwaysConnected: true,
        // Squatting — disabled
        channelCreationMinAge: Duration.zero,
        // Anonymous polls — no jitter in tests
        anonVoteJitterMax: Duration.zero,
      );

  // ── Calculation methods ─────────────────────────────────────────

  /// Calculates the independence threshold based on total user count.
  /// Groups/channels with fewer members than this value are considered "connected".
  int independenceThreshold(int totalUsers) {
    final dynamic = (totalUsers * independenceGroupFactor).ceil();
    return dynamic > independenceMinGroupSize ? dynamic : independenceMinGroupSize;
  }

  /// Calculates the max. jury size based on available jurors.
  int effectiveJurySize(int availableJurors) {
    final maxFromPercent = (availableJurors * juryMaxPercent).floor();
    final cap = maxFromPercent < juryMaxSize ? maxFromPercent : juryMaxSize;
    return cap < juryMinSize ? juryMinSize : cap;
  }

  /// Whether enough jurors are available for a jury.
  bool canFormJury(int availableJurors) => availableJurors >= juryMinSize;

  /// CSAM stage 2 threshold based on subscriber count.
  int csamStage2Threshold(int subscriberCount) {
    final dynamic = (subscriberCount * csamStage2Factor).ceil();
    return dynamic > csamStage2Min ? dynamic : csamStage2Min;
  }

  /// CSAM stage 3 threshold based on subscriber count.
  int csamStage3Threshold(int subscriberCount) {
    final dynamic = (subscriberCount * csamStage3Factor).ceil();
    return dynamic > csamStage3Min ? dynamic : csamStage3Min;
  }

  /// Whether a jury vote has the required majority.
  ///
  /// NOTE: For resolving a jury verdict, [totalVotes] must be the
  /// **nominal** jury size (number of selected jurors), never the number
  /// of responders — see [juryApproved] / architecture §9.3.4.
  bool hasJuryMajority(int votesFor, int totalVotes) {
    if (totalVotes == 0) return false;
    return votesFor / totalVotes >= juryMajority;
  }

  /// Hard quorum (architecture §9.3.4): minimum number of approvals
  /// required for a jury verdict, computed against the **nominal** jury
  /// size (number of selected jurors). Rejections, abstentions and
  /// timeouts never lower the bar.
  ///
  /// Production (majority 2/3, 5 jurors) → 4 approvals;
  /// test preset (3 jurors) → 2 approvals.
  int juryHardQuorum(int nominalJurySize) =>
      (juryMajority * nominalJurySize).ceil();

  /// Whether a jury verdict is approved under the hard quorum
  /// (architecture §9.3.4). [nominalJurySize] is the number of selected
  /// jurors, NOT the number of jurors that responded.
  bool juryApproved({required int approvals, required int nominalJurySize}) =>
      nominalJurySize > 0 && approvals >= juryHardQuorum(nominalJurySize);

  /// Whether a juror timeout has expired.
  bool isJuryVoteExpired(DateTime voteSentAt) {
    return DateTime.now().difference(voteSentAt) >= juryVoteTimeout;
  }

  /// Whether a CSAM temporary hide has expired (channel can be shown again).
  bool isCsamTempHideExpired(DateTime hiddenSince) {
    return DateTime.now().difference(hiddenSince) >= csamTempHideDuration;
  }

  /// Whether the single post escalation is due.
  bool isSinglePostEscalationDue(DateTime reportedAt) {
    return DateTime.now().difference(reportedAt) >= singlePostEscalationTimeout;
  }

  /// Whether a badge probation has expired (badge can be removed).
  bool isProbationComplete(int badgeLevel, DateTime correctionAt) {
    final probation = badgeLevel <= 1 ? badgeProbationLevel1 : badgeProbationLevel2;
    return DateTime.now().difference(correctionAt) >= probation;
  }

  @override
  String toString() => 'ModerationConfig('
      'jury: $juryMinSize-$juryMaxSize, '
      'timeout: ${juryVoteTimeout.inSeconds}s, '
      'csam2: $csamStage2Min, csam3: $csamStage3Min, '
      'reachability: ${reachabilityEnabled ? "ON" : "OFF"})';
}

/// The 6 report categories.
enum ReportCategory {
  /// Channel marked as safe for work, but contains NSFW content.
  notSafeForWork,

  /// Content does not match the channel description.
  falseContent,

  /// Offers/trade of illegal substances.
  illegalDrugs,

  /// Offers/trade of illegal weapons.
  illegalWeapons,

  /// Child sexual abuse material — special procedure (no jury).
  illegalCSAM,

  /// Other illegal content.
  illegalOther,
}

/// Jury voting options.
enum JuryVote {
  approve,
  reject,
  abstain,
}

/// Jury consequence based on category.
enum JuryConsequence {
  /// Channel is reclassified as NSFW.
  reclassifyNsfw,

  /// Channel receives Bad Badge.
  addBadBadge,

  /// Channel is deleted (tombstone).
  deleteChannel,

  /// No action.
  noAction,
}

/// Bad Badge levels.
enum BadBadgeLevel {
  /// No badge.
  none,

  /// "Content questionable" — 30-day probation.
  questionable,

  /// "Repeatedly misleading" — 90-day probation.
  repeatedlyMisleading,

  /// Permanent — cannot be removed.
  permanent,
}

/// Channel topic categories for discovery.
enum ChannelCategory {
  /// General / uncategorized.
  general,

  /// Technology & Science.
  technology,

  /// News & Politics.
  news,

  /// Entertainment & Media.
  entertainment,

  /// Gaming.
  gaming,

  /// Music & Arts.
  music,

  /// Sports & Fitness.
  sports,

  /// Education & Learning.
  education,

  /// Business & Finance.
  finance,

  /// Health & Wellness.
  health,

  /// Food & Cooking.
  food,

  /// Travel & Geography.
  travel,

  /// Humor & Memes.
  humor,

  /// Crypto & Blockchain.
  crypto,

  /// Regional / Local.
  regional,
}

/// Determines the consequence of a successful jury decision.
JuryConsequence consequenceForCategory(ReportCategory category) {
  switch (category) {
    case ReportCategory.notSafeForWork:
      return JuryConsequence.reclassifyNsfw;
    case ReportCategory.falseContent:
      return JuryConsequence.addBadBadge;
    case ReportCategory.illegalDrugs:
    case ReportCategory.illegalWeapons:
    case ReportCategory.illegalOther:
      return JuryConsequence.deleteChannel;
    case ReportCategory.illegalCSAM:
      // CSAM has special procedure, no standard jury
      return JuryConsequence.noAction;
  }
}
