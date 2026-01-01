import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/moderation/jury_selection.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;
import 'package:fixnum/fixnum.dart';

// ── Helper types (were private in cleona_service.dart) ──────────────

/// Internal state for an active jury session we initiated.
class JurySession {
  final String juryId;
  final String reportId;
  final String channelIdHex;
  final ReportCategory category;
  final List<String> jurorNodeIds;
  final bool isPlausibilityJury;
  final DateTime createdAt;
  final int epochDay;
  final int juryRound;
  final Uint8List eligibilitySnapshotHash;
  final Map<String, JuryVoteResult> votes = {};
  final Map<String, JurorVerdictSigData> verdictSigs = {};
  bool isComplete = false;

  JurySession({
    required this.juryId,
    required this.reportId,
    required this.channelIdHex,
    required this.category,
    required this.jurorNodeIds,
    this.isPlausibilityJury = false,
    required this.createdAt,
    required this.epochDay,
    this.juryRound = 0,
    required this.eligibilitySnapshotHash,
  });
}

class JurorVerdictSigData {
  final Uint8List sigEd25519;
  final Uint8List sigMlDsa;
  final int vote;
  JurorVerdictSigData({required this.sigEd25519, required this.sigMlDsa, required this.vote});
}

// ── ChannelModerationService ────────────────────────────────────────

/// Extracted from CleonaService: all channel moderation, jury, channel-index
/// gossip, and public-channel join logic. Pure mechanical extraction — zero
/// behavioral change.
class ChannelModerationService {
  final ServiceContext _ctx;
  final CLogger _log;

  // All moderation state (moved from CleonaService):
  ModerationConfig _moderationConfig;
  final Map<String, ChannelReport> channelReports = {};
  final Map<String, PostReport> postReports = {};
  final Map<String, JuryRequest> pendingJuryRequests = {};
  final Map<String, JurySession> _activeSessions = {};
  final Map<String, int> _dailyReportCounts = {};
  DateTime _lastReportCountReset = DateTime.now();
  final Map<String, DateTime> _csamCooldowns = {};
  final Map<String, int> _csamStrikes = {};
  final Map<String, Uint8List> moderationProofs = {};
  Timer? _channelIndexGossipTimer;
  Timer? _moderationTimer;

  // Callbacks
  void Function(JuryRequest request)? onJuryRequestReceived;

  ModerationConfig get moderationConfig => _moderationConfig;
  set moderationConfig(ModerationConfig value) {
    _moderationConfig = value;
    startModerationTimer();
  }

  ChannelModerationService(this._ctx, {ModerationConfig? config})
      : _moderationConfig = config ?? ModerationConfig.production(),
        _log = CLogger.get('moderation', profileDir: _ctx.profileDir);

  /// List of pending jury requests (for IPC/UI).
  List<JuryRequest> get pendingJuryRequestsList => pendingJuryRequests.values.toList();

  // ── Public Channel Operations ────────────────────────────────────

  Future<List<ChannelIndexEntry>> searchPublicChannels({
    String? query,
    String? language,
    bool? includeAdult,
  }) async {
    return _ctx.channelIndex.search(
      query: query,
      language: language,
      includeAdult: includeAdult ?? false,
    );
  }

  // ── Moderation: Reports ────────────────────────────────────────

  void _resetDailyReportCountsIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_lastReportCountReset).inHours >= 24) {
      _dailyReportCounts.clear();
      _lastReportCountReset = now;
    }
  }

  /// Check if the current identity meets reporter qualification requirements.
  /// Returns null if qualified, or an error message if not.
  String? _checkReporterQualification(ReportCategory category) {
    final config = moderationConfig;

    // Check identity age
    final identityAge = DateTime.now().difference(_ctx.identity.createdAt);
    if (category == ReportCategory.illegalCSAM) {
      if (identityAge < config.identityMinAgeCSAM) {
        return 'Identity too young for CSAM reports (need ${config.identityMinAgeCSAM.inDays} days)';
      }
      // CSAM requires isAdult
      if (config.csamRequiresAdult && !_ctx.identity.isAdult) {
        return 'CSAM reports require adult verification';
      }
      // CSAM: min bidirectional partners
      final bidirectional = _ctx.contacts.values.where((c) => c.status == 'accepted').length;
      if (bidirectional < config.csamMinBidirectionalPartners) {
        return 'Not enough contacts for CSAM reports (need ${config.csamMinBidirectionalPartners})';
      }
      // CSAM: min long-term contacts
      final longterm = _ctx.contacts.values.where((c) {
        if (c.status != 'accepted' || c.acceptedAt == null) return false;
        return DateTime.now().difference(c.acceptedAt!) >= config.csamLongtermContactAge;
      }).length;
      if (longterm < config.csamMinLongtermContacts) {
        return 'Not enough long-term contacts for CSAM reports (need ${config.csamMinLongtermContacts})';
      }
      // CSAM cooldown check
      final lastCsam = _csamCooldowns[_ctx.identity.userIdHex];
      if (lastCsam != null && DateTime.now().difference(lastCsam) < config.csamReporterCooldown) {
        return 'CSAM reporter cooldown active';
      }
      // CSAM strike check
      final strikes = _csamStrikes[_ctx.identity.userIdHex] ?? 0;
      if (strikes >= config.csamMaxStrikes) {
        return 'CSAM reporting permanently banned (${config.csamMaxStrikes} strikes)';
      }
    } else {
      if (identityAge < config.identityMinAge) {
        return 'Identity too young for reports (need ${config.identityMinAge.inDays} days)';
      }
    }
    return null;
  }

  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) async {
    _resetDailyReportCountsIfNeeded();

    // Rate limit
    final dailyCount = _dailyReportCounts[_ctx.identity.userIdHex] ?? 0;
    if (dailyCount >= 5) {
      _log.warn('Daily report limit reached');
      return false;
    }

    // Reporter qualification
    final cat = ReportCategory.values[category];
    final qualError = _checkReporterQualification(cat);
    if (qualError != null) {
      _log.warn('Reporter not qualified: $qualError');
      return false;
    }

    // Validate evidence (3-10 posts for channel reports)
    if (evidencePostIds.isEmpty || evidencePostIds.length > 10) {
      _log.warn('Channel report needs 1-10 evidence posts');
      return false;
    }

    final reportId = bytesToHex(SodiumFFI().randomBytes(16));

    final report = ChannelReport(
      reportId: reportId,
      channelIdHex: channelIdHex,
      reporterNodeIdHex: _ctx.identity.userIdHex,
      category: cat,
      evidencePostIds: evidencePostIds,
      description: description,
    );

    channelReports[reportId] = report;
    _dailyReportCounts[_ctx.identity.userIdHex] = dailyCount + 1;
    if (cat == ReportCategory.illegalCSAM) {
      _csamCooldowns[_ctx.identity.userIdHex] = DateTime.now();
    }
    saveModeration();

    _log.info('Channel report $reportId filed for $channelIdHex (category: ${cat.name})');

    // Check if jury threshold reached
    _checkJuryThreshold(channelIdHex);

    return true;
  }

  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description}) async {
    _resetDailyReportCountsIfNeeded();

    final dailyCount = _dailyReportCounts[_ctx.identity.userIdHex] ?? 0;
    if (dailyCount >= 5) {
      _log.warn('Daily report limit reached');
      return false;
    }

    // Reporter qualification
    final cat = ReportCategory.values[category];
    final qualError = _checkReporterQualification(cat);
    if (qualError != null) {
      _log.warn('Reporter not qualified: $qualError');
      return false;
    }

    final reportId = bytesToHex(SodiumFFI().randomBytes(16));

    final report = PostReport(
      reportId: reportId,
      channelIdHex: channelIdHex,
      postId: postId,
      reporterNodeIdHex: _ctx.identity.userIdHex,
      category: cat,
      description: description,
    );

    postReports[reportId] = report;
    _dailyReportCounts[_ctx.identity.userIdHex] = dailyCount + 1;
    if (cat == ReportCategory.illegalCSAM) {
      _csamCooldowns[_ctx.identity.userIdHex] = DateTime.now();
    }
    saveModeration();

    _log.info('Post report $reportId filed for $postId in $channelIdHex (category: ${cat.name})');
    return true;
  }

  void saveModeration() {
    try {
      final file = File('${_ctx.profileDir}/moderation.json');
      file.writeAsStringSync(jsonEncode({
        'channelReports': channelReports.map((k, v) => MapEntry(k, v.toJson())),
        'postReports': postReports.map((k, v) => MapEntry(k, v.toJson())),
        'juryRequests': pendingJuryRequests.map((k, v) => MapEntry(k, v.toJson())),
        'csamCooldowns': _csamCooldowns.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch)),
        'csamStrikes': _csamStrikes,
      }));
    } catch (e) {
      _log.warn('Failed to save moderation state: $e');
    }
  }

  void loadModeration() {
    try {
      final file = File('${_ctx.profileDir}/moderation.json');
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final reports = json['channelReports'] as Map<String, dynamic>? ?? {};
      for (final e in reports.entries) {
        channelReports[e.key] = ChannelReport.fromJson(e.value as Map<String, dynamic>);
      }

      final postReportsJson = json['postReports'] as Map<String, dynamic>? ?? {};
      for (final e in postReportsJson.entries) {
        postReports[e.key] = PostReport.fromJson(e.value as Map<String, dynamic>);
      }

      final jury = json['juryRequests'] as Map<String, dynamic>? ?? {};
      for (final e in jury.entries) {
        pendingJuryRequests[e.key] = JuryRequest.fromJson(e.value as Map<String, dynamic>);
      }

      final cooldowns = json['csamCooldowns'] as Map<String, dynamic>? ?? {};
      for (final e in cooldowns.entries) {
        _csamCooldowns[e.key] = DateTime.fromMillisecondsSinceEpoch(e.value as int);
      }
      final strikes = json['csamStrikes'] as Map<String, dynamic>? ?? {};
      for (final e in strikes.entries) {
        _csamStrikes[e.key] = e.value as int;
      }
    } catch (e) {
      _log.warn('Failed to load moderation state: $e');
    }
  }

  Map<String, dynamic> getChannelModerationInfo(String channelIdHex) {
    final channel = _ctx.channels[channelIdHex];
    final reports = channelReports.values
        .where((r) => r.channelIdHex == channelIdHex)
        .map((r) => <String, dynamic>{
          'reportId': r.reportId,
          'channelId': r.channelIdHex,
          'category': _categoryToString(r.category),
          'reporterCount': 1,
          'status': r.state.name,
          'juryResult': null,
        }).toList();

    return {
      'channelId': channelIdHex,
      'isPublic': channel?.isPublic ?? false,
      'isAdultContent': channel?.isAdult ?? false,
      'badBadgeLevel': _badgeLevelToString(channel?.badBadgeLevel ?? 0),
      if (channel?.badBadgeSince != null) 'badBadgeSince': channel!.badBadgeSince!.millisecondsSinceEpoch,
      if (channel?.correctionSubmitted == true) 'correctionSubmitted': channel!.correctionSubmitted,
      'pendingReports': reports,
      'isTempHidden': channel?.isCsamHidden ?? false,
      if (channel?.csamHiddenSince != null) 'tempHiddenSince': channel!.csamHiddenSince!.millisecondsSinceEpoch,
      'tombstoned': channel?.tombstoned ?? false,
    };
  }

  String _categoryToString(ReportCategory cat) {
    switch (cat) {
      case ReportCategory.notSafeForWork: return 'not_safe_for_work';
      case ReportCategory.falseContent: return 'false_content';
      case ReportCategory.illegalDrugs: return 'illegal_drugs';
      case ReportCategory.illegalWeapons: return 'illegal_weapons';
      case ReportCategory.illegalCSAM: return 'illegal_csam';
      case ReportCategory.illegalOther: return 'illegal_other';
    }
  }

  String _badgeLevelToString(int level) {
    switch (level) {
      case 1: return 'questionable';
      case 2: return 'repeatedly_misleading';
      case 3: return 'permanent';
      default: return 'none';
    }
  }

  Future<bool> dismissPostReport(String channelIdHex, String reportId) async {
    final report = postReports[reportId];
    if (report == null || report.channelIdHex != channelIdHex) return false;

    final channel = _ctx.channels[channelIdHex];
    if (channel == null || !_ctx.hasChannelPermission(channel, 'config')) return false;

    postReports.remove(reportId);
    saveModeration();
    _log.info('Post report $reportId dismissed');
    return true;
  }

  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription}) async {
    final channel = _ctx.channels[channelIdHex];
    if (channel == null) return false;
    if (channel.ownerNodeIdHex != _ctx.identity.userIdHex) return false;
    if (channel.badBadgeLevel <= 0 || channel.badBadgeLevel >= 3) return false; // no correction for permanent

    if (newName != null && newName.isNotEmpty) channel.name = newName;
    if (newDescription != null) channel.description = newDescription;
    channel.correctionSubmitted = true;
    _ctx.saveChannels();

    // Update index
    if (channel.isPublic) {
      _ctx.channelIndex.upsert(ChannelIndexEntry(
        channelIdHex: channelIdHex,
        name: channel.name,
        language: channel.language,
        isAdult: channel.isAdult,
        description: channel.description,
        subscriberCount: channel.members.length,
        badBadgeLevel: channel.badBadgeLevel,
        badBadgeSince: channel.badBadgeSince,
        correctionSubmitted: true,
        ownerNodeIdHex: channel.ownerNodeIdHex,
        createdAt: channel.createdAt,
      ));
      _ctx.channelIndex.save();
    }

    _log.info('Badge correction submitted for channel "${channel.name}"');
    return true;
  }

  Future<bool> contestCsamHide(String channelIdHex) async {
    final channel = _ctx.channels[channelIdHex];
    if (channel == null) return false;
    if (channel.ownerNodeIdHex != _ctx.identity.userIdHex) return false;
    if (!channel.isCsamHidden) return false;

    // Create a plausibility jury (jurors see only metadata, not content)
    final report = channelReports.values
        .where((r) => r.channelIdHex == channelIdHex && r.category == ReportCategory.illegalCSAM)
        .firstOrNull;
    if (report == null) return false;

    final juryId = bytesToHex(SodiumFFI().randomBytes(16));
    final session = _createJurySession(
      juryId: juryId,
      reportId: report.reportId,
      channelIdHex: channelIdHex,
      category: ReportCategory.illegalCSAM,
      isPlausibilityJury: true,
    );
    if (session == null) {
      _log.warn('Cannot form plausibility jury — not enough eligible jurors');
      return false;
    }

    _log.info('CSAM plausibility jury $juryId formed for channel "${channel.name}" — ${session.jurorNodeIds.length} jurors');
    return true;
  }

  // ── Channel Index Gossip ──────────────────────────────────────

  /// Start periodic channel index gossip timer.
  void startChannelIndexGossip(Duration interval) {
    _channelIndexGossipTimer?.cancel();
    _channelIndexGossipTimer = Timer.periodic(interval, (_) => doChannelIndexGossip());
  }

  /// Send channel index to up to 3 random connected peers.
  void doChannelIndexGossip() {
    final entries = _ctx.channelIndex.allEntries;
    if (entries.isEmpty) return;

    // Pick up to 3 random peers from routing table
    final allPeers = _ctx.node.routingTable.allPeers;
    if (allPeers.isEmpty) return;

    final shuffled = List<PeerInfo>.from(allPeers)..shuffle();
    final targets = shuffled.take(3);

    final exchangeMsg = proto.ChannelIndexExchange();
    for (final entry in entries) {
      exchangeMsg.entries.add(proto.ChannelIndexEntryProto()
        ..channelId = hexToBytes(entry.channelIdHex)
        ..name = entry.name
        ..language = entry.language
        ..isAdult = entry.isAdult
        ..description = entry.description ?? ''
        ..subscriberCount = entry.subscriberCount
        ..badBadgeLevel = entry.badBadgeLevel
        ..correctionSubmitted = entry.correctionSubmitted
        ..ownerNodeId = hexToBytes(entry.ownerNodeIdHex)
        ..createdAtMs = Int64(entry.createdAt.millisecondsSinceEpoch));
      if (entry.badBadgeSince != null) {
        exchangeMsg.entries.last.badBadgeSinceMs = Int64(entry.badBadgeSince!.millisecondsSinceEpoch);
      }
    }

    // V3 channel-index gossip rides InfrastructureFrame: recipients are
    // arbitrary routing-table peers (NOT necessarily contacts), and there
    // is no inner User-Sig requirement — receivers treat the entries as
    // gossip and trust nothing. Device-KEM-Decap at the recipient gates
    // delivery to addressed devices; HMAC + Outer-Device-Sig per §3.5
    // protect the wire. Architecture §10.2 + §2.3.5.
    final payload = Uint8List.fromList(exchangeMsg.writeToBuffer());
    for (final peer in targets) {
      unawaited(_ctx.node.sendInfraTo(
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_INDEX_EXCHANGE,
        innerPayload: payload,
        recipientDeviceId: peer.nodeId,
      ));
    }
  }

  /// Handle incoming channel index exchange from a peer.
  ///
  /// V3-direct: [payload] is the raw `ChannelIndexExchange` proto bytes
  /// from the InfrastructureFrame body (gossip-style, untrusted by design
  /// — handler only merges entries into `_channelIndex`). No sender
  /// argument needed — the entry payload is self-describing per channel.
  void handleChannelIndexExchange(Uint8List payload) {
    try {
      final exchange = proto.ChannelIndexExchange.fromBuffer(payload);
      var added = 0;
      for (final e in exchange.entries) {
        // Phase 1 (§9.3.1a): log unproven badge/tombstone entries.
        // Badge ≥ 1 or tombstone (badge 3) without moderation_proof_hash
        // are accepted but flagged — Phase 2 will reject them.
        final hasModerationProof = e.moderationProofHash.isNotEmpty;
        if (e.badBadgeLevel > 0 && !hasModerationProof) {
          _log.warn('Channel index gossip: badge=${e.badBadgeLevel} for '
              '${bytesToHex(Uint8List.fromList(e.channelId)).substring(0, 16)} '
              'WITHOUT moderation proof — accepted (Phase 1 observe-only)');
        }

        final entry = ChannelIndexEntry(
          channelIdHex: bytesToHex(Uint8List.fromList(e.channelId)),
          name: e.name,
          language: e.language,
          isAdult: e.isAdult,
          description: e.description.isEmpty ? null : e.description,
          subscriberCount: e.subscriberCount,
          badBadgeLevel: e.badBadgeLevel,
          badBadgeSince: e.badBadgeSinceMs.toInt() > 0
              ? DateTime.fromMillisecondsSinceEpoch(e.badBadgeSinceMs.toInt())
              : null,
          correctionSubmitted: e.correctionSubmitted,
          ownerNodeIdHex: bytesToHex(Uint8List.fromList(e.ownerNodeId)),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              e.createdAtMs.toInt() > 0 ? e.createdAtMs.toInt() : 0),
        );
        final existing = _ctx.channelIndex.get(entry.channelIdHex);
        if (existing == null || existing.subscriberCount < entry.subscriberCount ||
            existing.badBadgeLevel != entry.badBadgeLevel) {
          _ctx.channelIndex.upsert(entry);
          added++;
        }
      }
      if (added > 0) {
        _ctx.channelIndex.save();
        _log.info('Channel index gossip: merged $added entries from peer');
      }
    } catch (e) {
      _log.debug('Channel index exchange error: $e');
    }
  }

  // ── Channel Join Request (Owner-Seite) ────────────────────────

  /// Handle incoming join request for a public channel we own.
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `ChannelJoinRequest` proto bytes (V3 inner User-Sig + outer
  /// Device-Sig + KEM-decap chain verified upstream). [senderUserId] is
  /// the requesting peer's user-id (`frame.senderUserId`).
  void handleChannelJoinRequest(Uint8List payload, Uint8List senderUserId) {
    try {
      final joinReq = proto.ChannelJoinRequest.fromBuffer(payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(joinReq.channelId));
      final channel = _ctx.channels[channelIdHex];
      if (channel == null || !channel.isPublic) {
        _log.debug('Join request for unknown/private channel $channelIdHex');
        return;
      }

      // Only owner processes join requests
      if (channel.ownerNodeIdHex != _ctx.identity.userIdHex) return;

      final requesterNodeIdHex = bytesToHex(senderUserId);

      // Already a member?
      if (channel.members.containsKey(requesterNodeIdHex)) {
        _log.debug('$requesterNodeIdHex already member of channel $channelIdHex');
        return;
      }

      // Add as subscriber
      channel.members[requesterNodeIdHex] = ChannelMemberInfo(
        nodeIdHex: requesterNodeIdHex,
        displayName: joinReq.displayName,
        role: 'subscriber',
        ed25519Pk: Uint8List.fromList(joinReq.ed25519Pk),
        x25519Pk: Uint8List.fromList(joinReq.x25519Pk),
        mlKemPk: Uint8List.fromList(joinReq.mlKemPk),
      );
      _ctx.saveChannels();

      // Send CHANNEL_INVITE back with full member list
      sendChannelInviteToMember(channel, requesterNodeIdHex);

      // Update index subscriber count
      if (channel.isPublic) {
        _ctx.publishChannelToIndex(channelIdHex);
      }

      _log.info('Auto-accepted join request from ${joinReq.displayName} for channel "${channel.name}"');
      _ctx.notifyStateChanged();
    } catch (e) {
      _log.debug('Channel join request error: $e');
    }
  }

  /// Send a CHANNEL_INVITE to a specific member (used for join request responses).
  Future<void> sendChannelInviteToMember(ChannelInfo channel, String memberNodeIdHex) async {
    final memberInfo = channel.members[memberNodeIdHex];
    if (memberInfo == null) return;

    // Build invite protobuf
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(channel.channelIdHex)
      ..channelName = channel.name
      ..role = memberInfo.role
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;

    // Include full member list
    for (final m in channel.members.values) {
      final gm = proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role;
      if (m.ed25519Pk != null) gm.ed25519PublicKey = m.ed25519Pk!;
      if (m.x25519Pk != null) gm.x25519PublicKey = m.x25519Pk!;
      if (m.mlKemPk != null) gm.mlKemPublicKey = m.mlKemPk!;
      invite.members.add(gm);
    }

    // Inline _resolveMemberKeys: prefer contact keys, fallback to member keys.
    Uint8List? x25519Pk;
    Uint8List? mlKemPk;
    final contact = _ctx.contacts[memberNodeIdHex];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      x25519Pk = contact.x25519Pk!;
      mlKemPk = contact.mlKemPk!;
    } else if (memberInfo.x25519Pk != null && memberInfo.x25519Pk!.isNotEmpty &&
               memberInfo.mlKemPk != null && memberInfo.mlKemPk!.isNotEmpty) {
      x25519Pk = memberInfo.x25519Pk;
      mlKemPk = memberInfo.mlKemPk;
    }
    if (x25519Pk == null || mlKemPk == null) return;

    // V3: sendToUser handles KEM/Sig + per-device fan-out.
    await _ctx.sendToUser(
      recipientUserId: hexToBytes(memberNodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CHANNEL_INVITE,
      payload: Uint8List.fromList(invite.writeToBuffer()),
      groupId: hexToBytes(channel.channelIdHex),
    );
  }

  Future<bool> joinPublicChannel(String channelIdHex) async {
    final entry = _ctx.channelIndex.get(channelIdHex);
    if (entry == null) return false;

    // Create local channel + conversation
    if (!_ctx.channels.containsKey(channelIdHex)) {
      final channel = ChannelInfo(
        channelIdHex: channelIdHex,
        name: entry.name,
        description: entry.description,
        ownerNodeIdHex: entry.ownerNodeIdHex,
        isPublic: true,
        isAdult: entry.isAdult,
        language: entry.language,
      );
      channel.members[_ctx.identity.userIdHex] = ChannelMemberInfo(
        nodeIdHex: _ctx.identity.userIdHex,
        displayName: _ctx.displayName,
        role: 'subscriber',
        ed25519Pk: _ctx.identity.ed25519PublicKey,
        x25519Pk: _ctx.identity.x25519PublicKey,
        mlKemPk: _ctx.identity.mlKemPublicKey,
      );
      _ctx.channels[channelIdHex] = channel;
      _ctx.saveChannels();

      _ctx.conversations[channelIdHex] = Conversation(
        id: channelIdHex,
        displayName: entry.name,
        isChannel: true,
      );
      _ctx.saveConversations();
      _ctx.notifyStateChanged();
    }

    // Send join request to channel owner via V3 sendToUser. Owner is
    // (per §10.2) a contact for any public channel we discovered, so
    // sendToUser handles per-device fan-out + KEM/Sig.
    final ownerContact = _ctx.contacts[entry.ownerNodeIdHex];
    if (ownerContact?.x25519Pk != null && ownerContact?.mlKemPk != null) {
      final joinReq = proto.ChannelJoinRequest()
        ..channelId = hexToBytes(entry.channelIdHex)
        ..displayName = _ctx.displayName
        ..ed25519Pk = _ctx.identity.ed25519PublicKey
        ..x25519Pk = _ctx.identity.x25519PublicKey
        ..mlKemPk = _ctx.identity.mlKemPublicKey;
      unawaited(_ctx.sendToUser(
        recipientUserId: hexToBytes(entry.ownerNodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_JOIN_REQUEST,
        payload: Uint8List.fromList(joinReq.writeToBuffer()),
      ));
      _log.info('CHANNEL_JOIN_REQUEST sent for "${entry.name}" to owner '
          '${entry.ownerNodeIdHex.substring(0, 8)}');
    } else {
      _log.info('Joined public channel "${entry.name}" locally — owner keys not yet known');
    }
    return true;
  }

  // ── Moderation Timer ─────────────────────────────────────────

  /// Start (or restart) the periodic moderation timer.
  /// Interval adapts to config: ~1/6 of the shortest timeout, clamped to [5s, 5min].
  void startModerationTimer() {
    _moderationTimer?.cancel();
    final shortest = [
      moderationConfig.juryVoteTimeout,
      moderationConfig.badgeProbationLevel1,
      moderationConfig.csamTempHideDuration,
      moderationConfig.singlePostEscalationTimeout,
    ].reduce((a, b) => a < b ? a : b);
    var intervalMs = (shortest.inMilliseconds ~/ 6).clamp(5000, 300000);
    // For very short test timeouts (<5s), tick every second
    if (shortest.inSeconds < 5) intervalMs = 1000;
    _moderationTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) => _runModerationChecks());
    _log.debug('Moderation timer started: interval=${intervalMs}ms (shortest timeout=${shortest.inSeconds}s)');
  }

  /// Periodic check of all time-based moderation limits.
  Future<void> _runModerationChecks() async {
    final now = DateTime.now();
    final config = moderationConfig;
    var changed = false;

    // 1. Jury vote timeouts — attempt replacement jurors or resolve
    for (final session in _activeSessions.values.toList()) {
      if (session.isComplete) continue;
      if (now.difference(session.createdAt) > config.juryVoteTimeout) {
        _log.info('Moderation timer: jury ${session.juryId} timed out');
        _handleJuryTimeout(session);
        changed = true;
      }
    }

    // 2. Badge probation — remove badge after successful probation
    for (final channel in _ctx.channels.values) {
      if (channel.badBadgeLevel <= 0 || channel.badBadgeLevel >= 3) continue;
      if (!channel.correctionSubmitted) continue;
      if (channel.badBadgeSince == null) continue;

      final probation = channel.badBadgeLevel == 1
          ? config.badgeProbationLevel1
          : config.badgeProbationLevel2;
      if (now.difference(channel.badBadgeSince!) >= probation) {
        final oldLevel = channel.badBadgeLevel;
        channel.badBadgeLevel = (channel.badBadgeLevel - 1).clamp(0, 3);
        channel.correctionSubmitted = false;
        if (channel.badBadgeLevel == 0) {
          channel.badBadgeSince = null;
        }
        _log.info('Moderation timer: badge probation complete for "${channel.name}" ($oldLevel → ${channel.badBadgeLevel})');
        if (channel.isPublic) await _ctx.publishChannelToIndex(channel.channelIdHex);
        changed = true;
      }
    }

    // 3. CSAM temp-hide — lift hide after duration expires (only Stage 2)
    for (final channel in _ctx.channels.values) {
      if (!channel.isCsamHidden) continue;
      if (channel.csamStage3Active) continue; // Stage 3 manages its own lifecycle
      if (channel.csamHiddenSince == null) continue;
      if (now.difference(channel.csamHiddenSince!) >= config.csamTempHideDuration) {
        channel.isCsamHidden = false;
        channel.csamHiddenSince = null;
        _log.info('Moderation timer: CSAM temp-hide lifted for "${channel.name}"');
        if (channel.isPublic) await _ctx.publishChannelToIndex(channel.channelIdHex);
        changed = true;
      }
    }

    // 3b. CSAM Stage 3 objection window expiry → finalize tombstone
    for (final channel in _ctx.channels.values.toList()) {
      if (!channel.csamStage3Active) continue;
      if (channel.tombstoned) continue;
      if (channel.csamObjectionWindowEnd == null) continue;
      if (now.isAfter(channel.csamObjectionWindowEnd!)) {
        // Check if plausibility jury objected (resolved as NOT approved = objection succeeded)
        final juryId = channel.csamObjectionJuryId;
        if (juryId != null) {
          final session = _activeSessions[juryId];
          if (session != null && session.isComplete) {
            // Plausibility jury completed — if it was NOT approved,
            // the objection succeeded and hide should be lifted
            // (this is handled in _resolveJury already)
          }
        }
        _log.info('Moderation timer: CSAM Stage 3 objection window expired for "${channel.name}"');
        _finalizeCsamStage3(channel);
        changed = true;
      }
    }

    // 4. Single-post escalation — pending post reports escalate to channel reports
    for (final report in postReports.values.toList()) {
      if (report.state != PostReportState.pending) continue;
      if (now.difference(report.createdAt) >= config.singlePostEscalationTimeout) {
        report.state = PostReportState.escalated;
        // Create a channel-level report from the post report
        final channelReport = ChannelReport(
          reportId: report.reportId,
          channelIdHex: report.channelIdHex,
          reporterNodeIdHex: report.reporterNodeIdHex,
          category: report.category,
          evidencePostIds: [report.postId],
          description: report.description,
        );
        channelReports[report.reportId] = channelReport;
        _checkJuryThreshold(report.channelIdHex);
        _log.info('Moderation timer: post report ${report.reportId} escalated to channel report');
        changed = true;
      }
    }

    // Clean up completed jury sessions (keep for 1 hour, then discard)
    _activeSessions.removeWhere((id, s) =>
        s.isComplete && now.difference(s.createdAt) > const Duration(hours: 1));

    if (changed) {
      _ctx.saveChannels();
      saveModeration();
      _ctx.notifyStateChanged();
    }
  }

  // ── Jury-Auswahl + Verteilung ─────────────────────────────────

  /// Check if reports for a channel have reached the jury threshold.
  void _checkJuryThreshold(String channelIdHex) {
    final config = moderationConfig;
    final channel = _ctx.channels[channelIdHex];
    // Count unique reporters per category for this channel
    final reportsByCategory = <ReportCategory, Set<String>>{};
    for (final r in channelReports.values) {
      if (r.channelIdHex != channelIdHex || r.state != ReportState.pending) continue;
      reportsByCategory.putIfAbsent(r.category, () => {}).add(r.reporterNodeIdHex);
    }

    for (final entry in reportsByCategory.entries) {
      // CSAM has special procedure — no standard jury
      if (entry.key == ReportCategory.illegalCSAM) {
        if (channel == null) continue;
        final subscriberCount = channel.members.length;
        _checkCsamThresholds(channel, entry.value.length, subscriberCount);
        continue;
      }

      if (entry.value.length >= config.reportThresholdForJury) {
        // Check if jury already active for this channel+category
        final alreadyActive = _activeSessions.values.any((s) =>
            s.channelIdHex == channelIdHex && s.category == entry.key && !s.isComplete);
        if (alreadyActive) continue;

        _initiateJury(channelIdHex, entry.key);
      }
    }
  }

  /// CSAM special procedure: check Stage 2 (temp-hide) and Stage 3
  /// (extended-hide + objection window) thresholds.
  void _checkCsamThresholds(ChannelInfo channel, int uniqueReporters, int subscriberCount) {
    final config = moderationConfig;

    // Stage 3: extended-hiding + objection window → eventual tombstone
    final stage3Threshold = config.csamStage3Threshold(subscriberCount);
    if (uniqueReporters >= stage3Threshold && !channel.csamStage3Active && !channel.tombstoned) {
      _triggerCsamStage3(channel);
      return;
    }

    // Stage 2: temporary hiding
    final stage2Threshold = config.csamStage2Threshold(subscriberCount);
    if (uniqueReporters >= stage2Threshold && !channel.isCsamHidden && !channel.csamStage3Active) {
      channel.isCsamHidden = true;
      channel.csamHiddenSince = DateTime.now();
      _ctx.saveChannels();
      _log.info('CSAM Stage 2: channel "${channel.name}" temporarily hidden '
          '($uniqueReporters reporters ≥ threshold $stage2Threshold)');

      // Start plausibility jury for Stage 2
      final juryId = bytesToHex(SodiumFFI().randomBytes(16));
      final report = channelReports.values
          .where((r) => r.channelIdHex == channel.channelIdHex &&
              r.category == ReportCategory.illegalCSAM)
          .firstOrNull;
      if (report != null) {
        _createJurySession(
          juryId: juryId,
          reportId: report.reportId,
          channelIdHex: channel.channelIdHex,
          category: ReportCategory.illegalCSAM,
          isPlausibilityJury: true,
        );
      }
    }
  }

  /// CSAM Stage 3: extended-hide the channel and start the mandatory
  /// objection window (§9.3.3). Tombstone is NOT written immediately —
  /// only after the window expires without a successful objection.
  void _triggerCsamStage3(ChannelInfo channel) {
    final config = moderationConfig;

    channel.isCsamHidden = true;
    channel.csamHiddenSince ??= DateTime.now();
    channel.csamStage3Active = true;
    channel.csamObjectionWindowEnd = DateTime.now().add(config.csamObjectionWindow);

    _ctx.saveChannels();
    _log.info('CSAM Stage 3: channel "${channel.name}" extended-hidden, '
        'objection window until ${channel.csamObjectionWindowEnd}');

    // Start mandatory plausibility jury (same as Stage 2, metadata-only)
    final juryId = bytesToHex(SodiumFFI().randomBytes(16));
    channel.csamObjectionJuryId = juryId;

    final report = channelReports.values
        .where((r) => r.channelIdHex == channel.channelIdHex &&
            r.category == ReportCategory.illegalCSAM)
        .firstOrNull;
    if (report != null) {
      _createJurySession(
        juryId: juryId,
        reportId: report.reportId,
        channelIdHex: channel.channelIdHex,
        category: ReportCategory.illegalCSAM,
        isPlausibilityJury: true,
      );
      _log.info('CSAM Stage 3: plausibility jury $juryId started for "${channel.name}"');
    }

    _ctx.saveChannels();
    if (channel.isPublic) _ctx.publishChannelToIndex(channel.channelIdHex);
  }

  /// Finalize CSAM Stage 3: write Tombstone with reporter-quorum proof.
  /// Called when the objection window expires without a successful objection.
  void _finalizeCsamStage3(ChannelInfo channel) {
    // Collect CSAM reports for this channel and build quorum proof
    final csamReports = channelReports.values
        .where((r) => r.channelIdHex == channel.channelIdHex &&
            r.category == ReportCategory.illegalCSAM)
        .toList();

    final subscriberCount = channel.members.length;
    final threshold = moderationConfig.csamStage3Threshold(subscriberCount);

    // Verify we have enough unique reporters
    final uniqueReporters = csamReports.map((r) => r.reporterNodeIdHex).toSet();
    if (uniqueReporters.length < threshold) {
      _log.warn('CSAM Stage 3: cannot finalize "${channel.name}" — '
          'only ${uniqueReporters.length} reporters, need $threshold');
      channel.csamStage3Active = false;
      channel.csamObjectionWindowEnd = null;
      channel.csamObjectionJuryId = null;
      _ctx.saveChannels();
      return;
    }

    // Build reporter-quorum proof (CsamReporterQuorumProof proto)
    final proof = proto.CsamReporterQuorumProof()
      ..channelId = hexToBytes(channel.channelIdHex);
    for (final r in csamReports) {
      proof.reporterSigs.add(proto.CsamReportSig()
        ..reporterUserId = hexToBytes(r.reporterNodeIdHex)
        ..reportId = hexToBytes(r.reportId)
        ..reportedAtMs = Int64(r.createdAt.millisecondsSinceEpoch));
    }

    // Write Tombstone
    channel.tombstoned = true;
    channel.badBadgeLevel = 3;
    channel.badBadgeSince = DateTime.now();
    _ctx.channelIndex.remove(channel.channelIdHex);
    _ctx.channelIndex.save();

    // Store proof locally (served on-demand via DHT/gossip)
    final proofBytes = Uint8List.fromList(proof.writeToBuffer());
    final sodium = SodiumFFI();
    final proofHash = computeModerationProofHash(proofBytes, sodium);
    moderationProofs[channel.channelIdHex] = proofBytes;

    _ctx.saveChannels();
    _log.info('CSAM Stage 3: channel "${channel.name}" TOMBSTONED with '
        '${uniqueReporters.length}-reporter quorum proof '
        '(hash=${bytesToHex(proofHash).substring(0, 16)})');
  }

  /// Start a jury process for a channel+category.
  void _initiateJury(String channelIdHex, ReportCategory category) {
    final report = channelReports.values
        .where((r) => r.channelIdHex == channelIdHex && r.category == category)
        .firstOrNull;
    if (report == null) return;

    final juryId = bytesToHex(SodiumFFI().randomBytes(16));
    final session = _createJurySession(
      juryId: juryId,
      reportId: report.reportId,
      channelIdHex: channelIdHex,
      category: category,
    );
    if (session == null) {
      _log.warn('Cannot form jury for $channelIdHex — not enough eligible jurors');
      return;
    }

    // Mark all pending reports as jury-active
    for (final r in channelReports.values) {
      if (r.channelIdHex == channelIdHex && r.category == category && r.state == ReportState.pending) {
        r.state = ReportState.juryActive;
      }
    }
    saveModeration();
    _log.info('Jury $juryId initiated for $channelIdHex (${category.name}) — ${session.jurorNodeIds.length} jurors');
  }

  /// Create a jury session, select jurors, and send JuryRequests.
  JurySession? _createJurySession({
    required String juryId,
    required String reportId,
    required String channelIdHex,
    required ReportCategory category,
    bool isPlausibilityJury = false,
    int juryRound = 0,
  }) {
    final config = moderationConfig;
    final channel = _ctx.channels[channelIdHex];
    final sodium = SodiumFFI();
    final now = DateTime.now();
    final epochDay = utcEpochDay(now);

    // Select eligible jurors from accepted contacts
    final eligible = <ContactInfo>[];
    for (final c in _ctx.contacts.values) {
      if (c.status != 'accepted') continue;
      if (c.nodeIdHex == _ctx.identity.userIdHex) continue;
      // Skip channel members (independence)
      if (channel != null && channel.members.containsKey(c.nodeIdHex)) continue;
      // Skip reporters for this channel
      if (channelReports.values.any((r) => r.channelIdHex == channelIdHex && r.reporterNodeIdHex == c.nodeIdHex)) continue;
      eligible.add(c);
    }

    if (eligible.length < config.juryMinSize) return null;

    // Deterministic selection via DHT-style XOR distance (§9.3.1a).
    // Build JurorRecords from eligible contacts and select XOR-closest to H.
    final jurorRecords = eligible.map((c) => JurorRecord(
      recordId: computeJurorRecordId(c.ed25519Pk!, sodium),
      userPubKeyEd25519: c.ed25519Pk!,
      userPubKeyMlDsa: c.mlDsaPk ?? Uint8List(0),
      creationEpochMs: 0,
      selfSigEd25519: Uint8List(0),
      selfSigMlDsa: Uint8List(0),
    )).toList();

    final selectionPoint = computeSelectionPoint(
      channelId: hexToBytes(channelIdHex),
      categoryIndex: category.index,
      epochDay: epochDay,
      juryRound: juryRound,
      sodium: sodium,
    );

    final jurySize = config.effectiveJurySize(eligible.length);
    final selected = selectJurors(
      selectionPoint: selectionPoint,
      registeredJurors: jurorRecords,
      jurySize: jurySize,
    );

    final snapshotHash = computeEligibilitySnapshotHash(
      jurorRecords.map((j) => j.recordId).toList(),
      sodium,
    );

    final session = JurySession(
      juryId: juryId,
      reportId: reportId,
      channelIdHex: channelIdHex,
      category: category,
      jurorNodeIds: selected.map((j) => j.userIdHex).toList(),
      isPlausibilityJury: isPlausibilityJury,
      createdAt: now,
      epochDay: epochDay,
      juryRound: juryRound,
      eligibilitySnapshotHash: snapshotHash,
    );
    _activeSessions[juryId] = session;

    // Send JuryRequest to each selected juror
    for (final j in selected) {
      final contact = _ctx.contacts[j.userIdHex];
      if (contact != null) _sendJuryRequest(session, contact);
    }

    return session;
  }

  /// Send an encrypted JuryRequest to a juror.
  void _sendJuryRequest(JurySession session, ContactInfo juror) {
    final channel = _ctx.channels[session.channelIdHex];
    final juryReq = proto.JuryRequestMsg()
      ..juryId = hexToBytes(session.juryId)
      ..channelId = hexToBytes(session.channelIdHex)
      ..reportId = hexToBytes(session.reportId)
      ..category = session.category.index
      ..channelName = channel?.name ?? 'Unknown'
      ..channelLanguage = channel?.language ?? ''
      ..epochDay = session.epochDay
      ..juryRound = session.juryRound
      ..eligibilitySnapshotHash = session.eligibilitySnapshotHash;

    final report = channelReports[session.reportId];
    if (report != null) {
      juryReq.reportDescription = report.description ?? '';
      for (final eid in report.evidencePostIds) {
        juryReq.evidencePostIds.add(hexToBytes(eid));
      }
    }

    if (juror.x25519Pk == null || juror.mlKemPk == null) return;
    // V3: JURY_REQUEST routes via CHANNEL_JURY_VOTE (V3 enum has no
    // JURY_REQUEST — same Sub-Message-Bump TODO as Channel-Join).
    _ctx.sendToUser(
      recipientUserId: hexToBytes(juror.nodeIdHex),
      messageType: proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE,
      payload: Uint8List.fromList(juryReq.writeToBuffer()),
      groupId: hexToBytes(session.channelIdHex),
    );
  }

  /// Handle incoming JuryRequest (we've been selected as juror).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryRequestMsg` proto bytes (V3 receive pipeline). [senderUserId]
  /// is the jury initiator's user-id (`frame.senderUserId`) — recorded
  /// as `requesterNodeIdHex` for the vote-back routing.
  void handleIncomingJuryRequest(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.JuryRequestMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final senderHex = bytesToHex(senderUserId);

      final request = JuryRequest(
        juryId: juryId,
        reportId: reportId,
        channelIdHex: channelIdHex,
        category: ReportCategory.values[msg.category],
        channelName: msg.channelName,
        channelLanguage: msg.channelLanguage,
        reportDescription: msg.reportDescription.isNotEmpty ? msg.reportDescription : null,
        requesterNodeIdHex: senderHex,
        epochDay: msg.epochDay,
        juryRound: msg.juryRound,
      );

      pendingJuryRequests[juryId] = request;
      saveModeration();
      onJuryRequestReceived?.call(request);
      _ctx.notifyStateChanged();
      _log.info('Received jury request $juryId for channel "${msg.channelName}"');
    } catch (e) {
      _log.debug('Jury request error: $e');
    }
  }

  /// Handle vote submission — also sends vote back to requester.
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason}) async {
    final request = pendingJuryRequests[juryId];
    if (request == null) return false;

    request.vote = JuryVoteResult.values[vote];
    request.votedAt = DateTime.now();
    saveModeration();

    // Send vote back to the jury initiator
    if (request.requesterNodeIdHex != null) {
      final contact = _ctx.contacts[request.requesterNodeIdHex!];
      if (contact?.x25519Pk != null && contact?.mlKemPk != null) {
        final sodium = SodiumFFI();
        final consequence = consequenceForCategory(request.category);

        // Hybrid-sign the canonical verdict core (§9.3.1a)
        final verdictCore = computeVerdictCoreHash(
          juryId: hexToBytes(juryId),
          channelId: hexToBytes(request.channelIdHex),
          reportId: hexToBytes(reportId),
          vote: vote,
          consequence: consequence.index,
          epochDay: request.epochDay,
          juryRound: request.juryRound,
          sodium: sodium,
        );

        final voteMsg = proto.JuryVoteMsg()
          ..juryId = hexToBytes(juryId)
          ..reportId = hexToBytes(reportId)
          ..vote = vote
          ..reason = reason ?? ''
          ..sigEd25519 = sodium.signEd25519(verdictCore, _ctx.identity.ed25519SecretKey)
          ..sigMlDsa = OqsFFI().mlDsaSign(verdictCore, _ctx.identity.mlDsaSecretKey)
          ..juryRound = request.juryRound
          ..epochDay = request.epochDay;
        await _ctx.sendToUser(
          recipientUserId: hexToBytes(request.requesterNodeIdHex!),
          messageType: proto.MessageTypeV3.MTV3_CHANNEL_JURY_VOTE,
          payload: Uint8List.fromList(voteMsg.writeToBuffer()),
          groupId: hexToBytes(request.channelIdHex),
        );
      }
    }

    _log.info('Jury vote submitted for $juryId: ${JuryVoteResult.values[vote].name}');
    return true;
  }

  /// Handle incoming jury vote (we initiated this jury).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryVoteMsg` proto bytes (V3 receive pipeline). [senderUserId] is
  /// the voter's user-id (`frame.senderUserId`) — recorded in the
  /// session's vote map.
  void handleIncomingJuryVote(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.JuryVoteMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));
      final voterHex = bytesToHex(senderUserId);

      final session = _activeSessions[juryId];
      if (session == null) return;

      // Only selected jurors may vote — anyone who learns the juryId could
      // otherwise stuff the vote map and force early resolution (§9.3.1).
      if (!session.jurorNodeIds.contains(voterHex)) {
        _log.warn('Jury $juryId: vote from non-juror $voterHex dropped');
        return;
      }

      session.votes[voterHex] = JuryVoteResult.values[msg.vote];

      // Store hybrid signature for verdict proof (§9.3.1a)
      if (msg.sigEd25519.isNotEmpty && msg.sigMlDsa.isNotEmpty) {
        session.verdictSigs[voterHex] = JurorVerdictSigData(
          sigEd25519: Uint8List.fromList(msg.sigEd25519),
          sigMlDsa: Uint8List.fromList(msg.sigMlDsa),
          vote: msg.vote,
        );
      }

      _log.info('Jury $juryId: vote from $voterHex = ${JuryVoteResult.values[msg.vote].name} (sig=${msg.sigEd25519.isNotEmpty ? "yes" : "no"})');

      // Check if all votes are in
      _checkJuryCompletion(session);
    } catch (e) {
      _log.debug('Jury vote error: $e');
    }
  }

  /// Check if a jury has enough votes to reach a decision.
  void _checkJuryCompletion(JurySession session) {
    final config = moderationConfig;
    final totalJurors = session.jurorNodeIds.length;
    final voteCount = session.votes.length;

    if (voteCount < totalJurors) {
      // Check for timeout
      if (DateTime.now().difference(session.createdAt) > config.juryVoteTimeout) {
        _log.info('Jury ${session.juryId} timed out with $voteCount/$totalJurors votes');
        _handleJuryTimeout(session);
      }
      return;
    }

    _resolveJury(session);
  }

  /// Handle jury timeout — attempt deterministic replacement jurors
  /// (§9.3.1a: next-closest records to H with juryRound+1, max 2 rounds).
  void _handleJuryTimeout(JurySession session) {
    final config = moderationConfig;

    // Identify non-responding jurors
    final nonResponders = session.jurorNodeIds
        .where((id) => !session.votes.containsKey(id))
        .toList();

    if (nonResponders.isEmpty || session.juryRound >= config.juryReplacementRounds) {
      _log.info('Jury ${session.juryId}: no more replacement rounds '
          '(round=${session.juryRound}, max=${config.juryReplacementRounds}) — resolving');
      _resolveJury(session);
      return;
    }

    // Build candidate pool (same filter as _createJurySession)
    final channel = _ctx.channels[session.channelIdHex];
    final sodium = SodiumFFI();
    final eligible = <ContactInfo>[];
    for (final c in _ctx.contacts.values) {
      if (c.status != 'accepted') continue;
      if (c.nodeIdHex == _ctx.identity.userIdHex) continue;
      if (c.ed25519Pk == null) continue;
      if (channel != null && channel.members.containsKey(c.nodeIdHex)) continue;
      if (channelReports.values.any((r) =>
          r.channelIdHex == session.channelIdHex &&
          r.reporterNodeIdHex == c.nodeIdHex)) continue;
      // Exclude already-selected jurors (both responded and non-responded)
      if (session.jurorNodeIds.contains(c.nodeIdHex)) continue;
      eligible.add(c);
    }

    if (eligible.isEmpty) {
      _log.info('Jury ${session.juryId}: no replacement candidates available — resolving');
      _resolveJury(session);
      return;
    }

    // Compute new selection point with incremented round
    final nextRound = session.juryRound + 1;
    final newH = computeSelectionPoint(
      channelId: hexToBytes(session.channelIdHex),
      categoryIndex: session.category.index,
      epochDay: session.epochDay,
      juryRound: nextRound,
      sodium: sodium,
    );

    final jurorRecords = eligible.map((c) => JurorRecord(
      recordId: computeJurorRecordId(c.ed25519Pk!, sodium),
      userPubKeyEd25519: c.ed25519Pk!,
      userPubKeyMlDsa: c.mlDsaPk ?? Uint8List(0),
      creationEpochMs: 0,
      selfSigEd25519: Uint8List(0),
      selfSigMlDsa: Uint8List(0),
    )).toList();

    // Select replacements for non-responders (XOR-closest to new H)
    final replacements = selectJurors(
      selectionPoint: newH,
      registeredJurors: jurorRecords,
      jurySize: nonResponders.length,
    );

    if (replacements.isEmpty) {
      _log.info('Jury ${session.juryId}: replacement selection empty — resolving');
      _resolveJury(session);
      return;
    }

    // Swap non-responders for replacements in the session
    for (var i = 0; i < nonResponders.length && i < replacements.length; i++) {
      final oldIdx = session.jurorNodeIds.indexOf(nonResponders[i]);
      if (oldIdx >= 0) {
        session.jurorNodeIds[oldIdx] = replacements[i].userIdHex;
      }
    }

    // Update session metadata (recreate with new round via mutable fields)
    // Note: juryRound is final, so we create a replacement session
    final newSession = JurySession(
      juryId: session.juryId,
      reportId: session.reportId,
      channelIdHex: session.channelIdHex,
      category: session.category,
      jurorNodeIds: session.jurorNodeIds,
      isPlausibilityJury: session.isPlausibilityJury,
      createdAt: DateTime.now(),
      epochDay: session.epochDay,
      juryRound: nextRound,
      eligibilitySnapshotHash: session.eligibilitySnapshotHash,
    );
    // Carry over existing votes and sigs
    newSession.votes.addAll(session.votes);
    newSession.verdictSigs.addAll(session.verdictSigs);
    _activeSessions[session.juryId] = newSession;

    // Send JuryRequest to replacement jurors
    for (final j in replacements) {
      final contact = _ctx.contacts[j.userIdHex];
      if (contact != null) _sendJuryRequest(newSession, contact);
    }

    _log.info('Jury ${session.juryId}: replaced ${replacements.length} '
        'non-responders in round $nextRound '
        '(jurors: ${newSession.jurorNodeIds.length})');
    saveModeration();
  }

  /// Resolve a jury — compute result and apply consequences.
  void _resolveJury(JurySession session) {
    final config = moderationConfig;
    var approve = 0;
    var reject = 0;
    var abstain = 0;

    for (final v in session.votes.values) {
      switch (v) {
        case JuryVoteResult.approve: approve++;
        case JuryVoteResult.reject: reject++;
        case JuryVoteResult.abstain: abstain++;
      }
    }

    // Hard quorum (§9.3.4): approvals are measured against the NOMINAL
    // jury size (number of selected jurors), never against the number of
    // responders — rejections, abstentions and timeouts do not lower the
    // bar. A session that misses the quorum resolves with no consequence.
    final nominalJurySize = session.jurorNodeIds.length;
    final approved = config.juryApproved(
        approvals: approve, nominalJurySize: nominalJurySize);
    session.isComplete = true;

    _log.info('Jury ${session.juryId} resolved: approve=$approve reject=$reject abstain=$abstain quorum=${config.juryHardQuorum(nominalJurySize)}/$nominalJurySize → ${approved ? "APPROVED" : "REJECTED"}');

    if (approved) {
      _applyJuryConsequence(session);
    } else if (session.isPlausibilityJury) {
      // Plausibility jury rejected = CSAM hide was unjustified → lift hide
      final channel = _ctx.channels[session.channelIdHex];
      if (channel != null && channel.isCsamHidden) {
        channel.isCsamHidden = false;
        channel.csamHiddenSince = null;
        if (channel.badBadgeLevel > 0) {
          channel.badBadgeLevel--;
        }
        // Also cancel Stage 3 if active
        if (channel.csamStage3Active) {
          channel.csamStage3Active = false;
          channel.csamObjectionWindowEnd = null;
          channel.csamObjectionJuryId = null;
          _log.info('CSAM Stage 3 cancelled for "${channel.name}" — objection upheld');
        }
        _ctx.saveChannels();
        _log.info('CSAM hide lifted for "${channel.name}" after plausibility jury rejection');
      }
    }

    // Mark reports as resolved
    for (final r in channelReports.values) {
      if (r.channelIdHex == session.channelIdHex && r.state == ReportState.juryActive) {
        r.state = ReportState.resolved;
      }
    }
    saveModeration();

    // Send result to all jurors
    _broadcastJuryResult(session, approve, reject, abstain);
  }

  /// Apply the consequence of an approved jury verdict.
  void _applyJuryConsequence(JurySession session) {
    final channel = _ctx.channels[session.channelIdHex];
    if (channel == null) return;

    final consequence = consequenceForCategory(session.category);

    switch (consequence) {
      case JuryConsequence.reclassifyNsfw:
        channel.isAdult = true;
        channel.badBadgeLevel = (channel.badBadgeLevel + 1).clamp(0, 3);
        channel.badBadgeSince = DateTime.now();
        _log.info('Channel "${channel.name}" relabeled as NSFW, badge level ${channel.badBadgeLevel}');
        break;
      case JuryConsequence.addBadBadge:
        channel.badBadgeLevel = (channel.badBadgeLevel + 1).clamp(0, 3);
        channel.badBadgeSince = DateTime.now();
        _log.info('Channel "${channel.name}" badge escalated to level ${channel.badBadgeLevel}');
        break;
      case JuryConsequence.deleteChannel:
        channel.badBadgeLevel = 3;
        channel.badBadgeSince = DateTime.now();
        channel.tombstoned = true;
        _ctx.channelIndex.remove(session.channelIdHex);
        _ctx.channelIndex.save();
        _log.info('Channel "${channel.name}" tombstoned (permanent badge)');
        break;
      case JuryConsequence.noAction:
        _log.info('Channel "${channel.name}" no action (CSAM has special procedure)');
        break;
    }

    _ctx.saveChannels();
    // Update index
    if (channel.isPublic) {
      _ctx.publishChannelToIndex(channel.channelIdHex);
    }
  }

  /// Send jury result to all jurors.
  void _broadcastJuryResult(JurySession session, int approve, int reject, int abstain) {
    final channel = _ctx.channels[session.channelIdHex];

    final resultMsg = proto.JuryResultMsg()
      ..juryId = hexToBytes(session.juryId)
      ..reportId = hexToBytes(session.reportId)
      ..channelId = hexToBytes(session.channelIdHex)
      ..consequence = consequenceForCategory(session.category).index
      ..votesApprove = approve
      ..votesReject = reject
      ..votesAbstain = abstain
      ..newBadBadgeLevel = channel?.badBadgeLevel ?? 0
      ..eligibilitySnapshotHash = session.eligibilitySnapshotHash
      ..epochDay = session.epochDay
      ..juryRound = session.juryRound;

    // Attach collected juror verdict signatures (§9.3.1a)
    for (final entry in session.verdictSigs.entries) {
      resultMsg.jurorSigs.add(proto.JurorVerdictSig()
        ..jurorUserId = hexToBytes(entry.key)
        ..sigEd25519 = entry.value.sigEd25519
        ..sigMlDsa = entry.value.sigMlDsa
        ..vote = entry.value.vote);
    }

    final payload = Uint8List.fromList(resultMsg.writeToBuffer());
    final channelIdBytes = hexToBytes(session.channelIdHex);

    for (final jurorId in session.jurorNodeIds) {
      final contact = _ctx.contacts[jurorId];
      if (contact?.x25519Pk == null || contact?.mlKemPk == null) continue;
      _ctx.sendToUser(
        recipientUserId: hexToBytes(jurorId),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_MOD_DECISION,
        payload: payload,
        groupId: channelIdBytes,
      );
    }
  }

  /// Handle incoming jury result (we were a juror).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `JuryResultMsg` proto bytes (V3 receive pipeline). The handler only
  /// removes the local pending entry and logs the tally — no sender
  /// argument is needed (sender authenticity is already enforced by the
  /// V3 outer Device-Sig + inner User-Sig chain).
  void handleIncomingJuryResult(Uint8List payload) {
    try {
      final msg = proto.JuryResultMsg.fromBuffer(payload);
      final juryId = bytesToHex(Uint8List.fromList(msg.juryId));

      // Remove from pending requests
      pendingJuryRequests.remove(juryId);
      saveModeration();
      _ctx.notifyStateChanged();

      _log.info('Jury result for $juryId: approve=${msg.votesApprove} reject=${msg.votesReject} abstain=${msg.votesAbstain}');
    } catch (e) {
      _log.debug('Jury result error: $e');
    }
  }

  /// Handle incoming channel report (forwarded from reporter).
  ///
  /// V3-direct: [payload] is the already-decrypted+authenticated
  /// `ChannelReportMsg` proto bytes (V3 receive pipeline). [senderUserId]
  /// is the reporter's user-id (`frame.senderUserId`) — recorded as
  /// `reporterNodeIdHex` on the stored `ChannelReport`.
  void handleIncomingChannelReport(Uint8List payload, Uint8List senderUserId) {
    try {
      final msg = proto.ChannelReportMsg.fromBuffer(payload);
      final channelIdHex = bytesToHex(Uint8List.fromList(msg.channelId));
      final reportId = bytesToHex(Uint8List.fromList(msg.reportId));
      final reporterHex = bytesToHex(senderUserId);

      // reportId is sender-chosen — never let it overwrite someone else's
      // stored report (report censorship via id collision).
      final existing = channelReports[reportId];
      if (existing != null && existing.reporterNodeIdHex != reporterHex) {
        _log.warn('Channel report $reportId from $reporterHex dropped: '
            'id collision with report from ${existing.reporterNodeIdHex}');
        return;
      }

      // Evidence sanity (§9.3.1): 1-10 evidence posts, valid category.
      if (msg.evidencePostIds.isEmpty || msg.evidencePostIds.length > 10) {
        _log.warn('Channel report $reportId from $reporterHex dropped: '
            'evidence count ${msg.evidencePostIds.length} outside 1-10');
        return;
      }
      if (msg.category < 0 || msg.category >= ReportCategory.values.length) {
        _log.warn('Channel report $reportId from $reporterHex dropped: '
            'invalid category ${msg.category}');
        return;
      }

      // Anti-Sybil local reachability (§9.4.1): reporter must be known
      // to us — either as a contact or visible in the routing table.
      // A node with zero network presence is likely a Sybil identity.
      final knownContact = _ctx.contacts.containsKey(reporterHex);
      final knownPeer = _ctx.node.routingTable.getPeerByUserId(senderUserId) != null;
      if (!knownContact && !knownPeer) {
        _log.warn('Channel report $reportId from $reporterHex dropped: '
            'reporter not reachable (not in contacts or routing table)');
        return;
      }

      // Receive-side rate limit (§9.4): sender-side checks are not
      // enforceable on a remote node.
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final recentFromReporter = channelReports.values.where((r) =>
          r.reporterNodeIdHex == reporterHex &&
          r.createdAt.isAfter(cutoff)).length;
      if (recentFromReporter >= moderationConfig.maxReportsPerIdentityPerDay) {
        _log.warn('Channel report from $reporterHex dropped: '
            'daily report limit reached');
        return;
      }

      // Store the report
      final report = ChannelReport(
        reportId: reportId,
        channelIdHex: channelIdHex,
        reporterNodeIdHex: reporterHex,
        category: ReportCategory.values[msg.category],
        evidencePostIds: msg.evidencePostIds.map((e) => bytesToHex(Uint8List.fromList(e))).toList(),
        description: msg.description.isNotEmpty ? msg.description : null,
      );
      channelReports[reportId] = report;
      saveModeration();

      // Check if jury threshold is now reached
      _checkJuryThreshold(channelIdHex);

      _log.info('Received channel report $reportId for $channelIdHex from $reporterHex');
    } catch (e) {
      _log.debug('Channel report error: $e');
    }
  }

  // ── V3 Dispatch Handlers ──────────────────────────────────────

  /// §9.3.1 Bad Badge Reporting (moderation Phase 2, not yet implemented).
  void handleChannelBadBadgeReportV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}

  /// V3-direct handler for MTV3_CHANNEL_JOIN_REQUEST (Wave 2B.3, §10.2).
  /// Owner-bound AppFrame; payload is the `ChannelJoinRequest` proto
  /// already decrypted+authenticated by the V3 receive pipeline.
  void handleChannelJoinRequestV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    handleChannelJoinRequest(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
    );
  }

  /// V3-direct handler for MTV3_CHANNEL_REPORT (Wave 2B.3, §10.2). No
  /// active V3 sender today (reportChannel mutates local state only) —
  /// handler in place so future moderator-fanout can land without a
  /// silent drop. Payload is the `ChannelReportMsg` proto already
  /// decrypted+authenticated by the V3 receive pipeline.
  void handleChannelReportV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    handleIncomingChannelReport(
      Uint8List.fromList(frame.payload),
      Uint8List.fromList(frame.senderUserId),
    );
  }

  /// V3-direct InfraFrame handler for MTV3_CHANNEL_INDEX_EXCHANGE (Wave
  /// 2B.3, §10.2). Gossip-style channel-index distribution to non-contact
  /// peers; payload is untrusted by design — handler just merges entries
  /// into `_channelIndex`. No KEM-decap and no inner User-Sig (public
  /// gossip on the InfraFrame path); the outer Device-Sig is the only
  /// authenticator and is verified upstream by the V3 receive pipeline.
  void handleChannelIndexExchangeInfra(
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress sourceAddr,
    int sourcePort,
    SenderIdentitySnapshot snapshot,
  ) {
    handleChannelIndexExchange(Uint8List.fromList(frame.payload));
  }

  /// V3-direct dispatcher for MTV3_CHANNEL_JURY_VOTE. The wire-type is
  /// overloaded by the V3 sender (cleona_service Z.~5023) — it carries
  /// either a `JuryRequestMsg` (initiator → juror, "you've been selected")
  /// or a `JuryVoteMsg` (juror → initiator, "here's my vote"). Both
  /// proto-bodies share the leading `juryId` field, so we early-parse as
  /// `JuryVoteMsg` and discriminate by initiator-side state: if we hold an
  /// `_activeSessions[juryId]` entry, this incoming frame is a vote-back
  /// for that session; otherwise it's a fresh request to participate.
  void handleChannelJuryVoteV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    try {
      final payload = Uint8List.fromList(frame.payload);
      final senderUserId = Uint8List.fromList(frame.senderUserId);
      // Try parsing as JuryVoteMsg first (vote-back from juror to initiator).
      // If we hold an active session for this juryId, it's a vote; otherwise
      // parse as JuryRequestMsg (initiator → juror selection).
      try {
        final voteCandidate = proto.JuryVoteMsg.fromBuffer(payload);
        final juryIdHex = bytesToHex(Uint8List.fromList(voteCandidate.juryId));
        if (_activeSessions.containsKey(juryIdHex)) {
          handleIncomingJuryVote(payload, senderUserId);
          return;
        }
      } catch (_) {
        // Not a valid JuryVoteMsg — fall through to JuryRequestMsg parse
      }
      handleIncomingJuryRequest(payload, senderUserId);
    } catch (e) {
      _log.warn('handleChannelJuryVoteV3: dispatch fail: $e '
          '(sender=${_hexShort(Uint8List.fromList(frame.senderUserId))})');
    }
  }

  /// V3-direct handler for MTV3_CHANNEL_MOD_DECISION (jury verdict
  /// broadcast). Payload is the `JuryResultMsg` proto already
  /// decrypted+authenticated by the V3 receive pipeline. The handler is
  /// sender-agnostic (only updates local state from the result tally), so
  /// no senderUserId is forwarded.
  void handleChannelModDecisionV3(proto.ApplicationFrameV3 frame, Uint8List senderDeviceId, SenderIdentitySnapshot snapshot) {
    handleIncomingJuryResult(Uint8List.fromList(frame.payload));
  }

  /// §9.3.1a Subscribe Probe (moderation reachability check, not yet implemented).
  void handleChannelSubscribeProbeV3(proto.ApplicationFrameV3 f, Uint8List sd, SenderIdentitySnapshot s) {}

  // ── Dispose ───────────────────────────────────────────────────

  void dispose() {
    _channelIndexGossipTimer?.cancel();
    _channelIndexGossipTimer = null;
    _moderationTimer?.cancel();
    _moderationTimer = null;
  }

  // ── Private helpers ───────────────────────────────────────────

  static String _hexShort(Uint8List bytes) {
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
