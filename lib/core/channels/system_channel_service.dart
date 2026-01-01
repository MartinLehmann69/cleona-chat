/// The system channels as ONE identity sees and uses them (v4_2 §16.7;
/// S407 SK-4): [SystemChannelApi] over the device's [SystemChannelHub],
/// signed by this identity's report pseudonym ([SystemObjectAuthor]).
///
/// Nothing here sends on its own: a deposit leaves only when the user
/// sends, votes or retracts; the hub deposits again at the edges of §16.0.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/system_channel_hub.dart';
import 'package:cleona/core/channels/system_object.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex, hexToBytes;
import 'package:mycelium/durable_id.dart';

class _Prepared {
  final int channel;
  final Uint8List report;
  final Uint8List? fingerprint;
  const _Prepared(this.channel, this.report, this.fingerprint);
}

class SystemChannelService implements SystemChannelApi {
  final SystemChannelHub hub;
  final SystemObjectAuthor author;
  final CLogger _log;
  final Map<String, _Prepared> _prepared = {};
  final Random _random = Random.secure();

  SystemChannelService(this.hub, this.author, {String? profileDir})
      : _log = CLogger.get('syschan', profileDir: profileDir);

  Uint8List get _me => author.pseudonym.publicKey;

  bool _own(SystemObject o) => _same(o.pseudonym, _me);

  @override
  Stream<void> get changes => hub.changes;

  // ── Views ───────────────────────────────────────────────────────────

  SystemReportView _view(SystemObject o) {
    final h = o.hash;
    final own = _own(o);
    final hex = bytesToHex(h);
    return SystemReportView(
      idHex: hex,
      channel: o.channel,
      text: o.text,
      created: DateTime.fromMillisecondsSinceEpoch(
          o.createdMinutes * Duration.millisecondsPerMinute),
      own: own,
      // No row: written on another device of this identity — its state
      // lives there.
      status: own ? hub.statusOf(hex) : null,
      isNew: !hub.store.isSeen(o.channel, h) && !own,
    );
  }

  /// A phone's identifier learned at an edge, not yet fetched.
  SystemReportView _unfetched(DurableId id) => SystemReportView(
        idHex: bytesToHex(id.hash),
        channel: id.channel,
        text: '',
        created: DateTime.now().subtract(Duration(hours: id.ageHours)),
        isNew: true,
        fetched: false,
      );

  List<SystemObject> _reports(int channel) => [
        ...hub.store.reports(channel),
        for (final o in hub.ownOutsideStore(channel))
          if (o.kind == SystemObjectKind.report) o,
      ];

  Iterable<DurableId> _learnedReports(int channel) => hub
      .learned(channel)
      .where((i) => i.kindSize >> 4 == SystemObjectKind.report);

  @override
  Future<List<BugLogGroupView>> bugLog() async {
    final out = <(DateTime, BugLogGroupView)>[];
    final grouped = <String>{};
    for (final r in _reports(kChannelBugLog)) {
      final fp = r.fingerprint;
      final g = fp == null ? null : hub.store.group(fp);
      if (fp == null || g == null) {
        out.add((_view(r).created, BugLogGroupView(head: _view(r))));
        continue;
      }
      if (!grouped.add(bytesToHex(fp))) continue;
      final all = [g.head, ...g.variants];
      final newest = all
          .map((o) => o.createdMinutes)
          .reduce(max);
      out.add((
        DateTime.fromMillisecondsSinceEpoch(
            newest * Duration.millisecondsPerMinute),
        BugLogGroupView(
          head: _view(g.head),
          variants: [for (final v in g.variants) _view(v)],
          othersSawThis: g.plusOnes,
          ownPlusOne: hub.store.hasPlusOne(fp, _me),
        )
      ));
    }
    for (final id in _learnedReports(kChannelBugLog)) {
      final v = _unfetched(id);
      out.add((v.created, BugLogGroupView(head: v)));
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final e in out) e.$2];
  }

  @override
  Future<List<FeatureRequestView>> featureRequests() async {
    final out = <FeatureRequestView>[];
    for (final r in _reports(kChannelFeatureRequests)) {
      final t = hub.store.tally(r.hash);
      out.add(FeatureRequestView(
        request: _view(r),
        yes: t.yes,
        no: t.no,
        dontCare: t.dontCare,
        ownVote: hub.store.voteOf(r.hash, _me)?.option,
      ));
    }
    for (final id in _learnedReports(kChannelFeatureRequests)) {
      out.add(FeatureRequestView(request: _unfetched(id)));
    }
    return out;
  }

  @override
  Future<void> channelOpened(int channel) async => hub.channelOpened(channel);

  @override
  Future<void> markSeen(int channel, List<String> idHexes) async =>
      hub.seen(channel, [for (final h in idHexes) hexToBytes(h)]);

  @override
  Future<bool> holdersKnown() async => hub.holders().isNotEmpty;

  // ── Preview and send ────────────────────────────────────────────────

  @override
  Future<SystemDepositPreview> prepare(SystemDraft draft) async {
    final fpHex = draft.fingerprintHex;
    final fp = fpHex != null && fpHex.length == 64 ? hexToBytes(fpHex) : null;
    final bytes = author.report(draft.channel, draft.text, fingerprint: fp);
    final refusal = _refusal(hub.store.ownCheck(bytes), draft.channel);
    final holders = hub.holders();
    SystemObject? existing;
    if (fp != null && refusal == null) {
      // §16.7: the own read cache first, the chosen holder only when it
      // finds nothing.
      existing = hub.store.group(fp)?.head;
      final t = hub.transport;
      if (existing == null && t != null && holders.isNotEmpty) {
        final a = await t.askFingerprint(kChannelBugLog, fp);
        final head = a.head == null ? null : SystemObject.parse(a.head!);
        if (head != null &&
            head.verifies &&
            head.fingerprint != null &&
            _same(head.fingerprint!, fp)) {
          existing = head;
        }
      }
    }
    final token = List.generate(16, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (refusal == null) {
      _prepared[token] = _Prepared(draft.channel, bytes, fp);
    }
    final uid = author.userId;
    return SystemDepositPreview(
      token: token,
      channel: draft.channel,
      publication: draft.text,
      statedUserIdHex: author.network == NetworkChannel.beta && uid != null
          ? bytesToHex(uid)
          : null,
      // Decision 13.10.2026 (1): non-contacts first, contacts fill up to
      // three — the line appears when a contact's device is AMONG them.
      holderIsContact: holders.any(hub.isContact),
      existing: existing == null ? null : _view(existing),
      existingOthers: fp == null ? 0 : hub.store.plusOneCount(fp),
      refusal: refusal,
    );
  }

  @override
  Future<SystemSendResult> send(String token, SystemSendChoice choice) async {
    final p = _prepared.remove(token);
    if (p == null) return const SystemSendResult.refused(SystemRefusal.tooLarge);
    if (choice == SystemSendChoice.plusOne) {
      final fp = p.fingerprint;
      if (fp == null) {
        return const SystemSendResult.refused(SystemRefusal.tooLarge);
      }
      if (hub.store.hasPlusOne(fp, _me)) {
        return const SystemSendResult.written(null); // sent before
      }
      return _submit(author.plusOne(fp), p.channel);
    }
    // A report and a variant are the same object: the group attaches it.
    return _submit(p.report, p.channel);
  }

  @override
  Future<void> discard(String token) async => _prepared.remove(token);

  @override
  Future<SystemSendResult> vote(String requestIdHex, int option) async {
    final target = hexToBytes(requestIdHex);
    final at = hub.store.nextVoteTime(target, _me);
    return _submit(author.vote(target, option, at: at), kChannelFeatureRequests);
  }

  @override
  Future<SystemSendResult> retract(String idHex) async {
    final target = hexToBytes(idHex);
    final channel = hub.store.channelOf(target);
    if (channel == null) {
      return const SystemSendResult.refused(SystemRefusal.tooLarge);
    }
    return _submit(author.retract(channel, target), channel);
  }

  SystemSendResult _submit(Uint8List bytes, int channel) {
    final a = hub.submit(bytes);
    if (a.kept) return SystemSendResult.written(bytesToHex(objectHash(bytes)));
    _log.warn('syschan: own object refused by the own store — ${a.reason}');
    return SystemSendResult.refused(
        _refusal(a.reason, channel) ?? SystemRefusal.tooLarge);
  }

  /// The own store's reason as the preview names it (§16.7 limits).
  static SystemRefusal? _refusal(String? reason, int channel) {
    switch (reason) {
      case null:
        return null;
      case 'rate per hour':
        return SystemRefusal.perHour;
      case 'rate per day':
        return channel == kChannelBugLog
            ? SystemRefusal.perDay
            : SystemRefusal.featurePerDay;
      case 'pseudonym share full':
        return SystemRefusal.share;
      default:
        return SystemRefusal.tooLarge;
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
