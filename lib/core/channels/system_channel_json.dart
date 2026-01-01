/// The system-channel values over IPC (S407 SK-4): the daemon answers the
/// commands `syschan_*` from [systemChannelServe], the GUI reads the answers
/// with the `…FromJson` functions (`ipc_client.dart`, `_IpcSystemChannels`).
/// Plain maps only — the same values the in-process interface returns.
library;

import 'package:cleona/core/channels/system_channel_api.dart';

T? _enum<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

Map<String, dynamic> statusToJson(SystemReportStatus s) => {
      'n': s.acknowledgements,
      if (s.failure != null) 'f': s.failure!.name,
      if (s.detail != null) 'd': s.detail,
    };

SystemReportStatus statusFromJson(Map<String, dynamic> j) =>
    SystemReportStatus(
      acknowledgements: (j['n'] as num?)?.toInt() ?? 0,
      failure: _enum(SystemFailureReason.values, j['f']),
      detail: j['d'] as String?,
    );

Map<String, dynamic> reportToJson(SystemReportView r) => {
      'id': r.idHex,
      'c': r.channel,
      'text': r.text,
      't': r.created.millisecondsSinceEpoch,
      'own': r.own,
      if (r.status != null) 's': statusToJson(r.status!),
      'new': r.isNew,
      'f': r.fetched,
    };

SystemReportView reportFromJson(Map<String, dynamic> j) => SystemReportView(
      idHex: j['id'] as String,
      channel: (j['c'] as num).toInt(),
      text: j['text'] as String? ?? '',
      created: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      own: j['own'] as bool? ?? false,
      status: j['s'] == null
          ? null
          : statusFromJson((j['s'] as Map).cast<String, dynamic>()),
      isNew: j['new'] as bool? ?? false,
      fetched: j['f'] as bool? ?? true,
    );

Map<String, dynamic> _r(Object? o) => (o as Map).cast<String, dynamic>();

Map<String, dynamic> groupToJson(BugLogGroupView g) => {
      'head': reportToJson(g.head),
      'variants': [for (final v in g.variants) reportToJson(v)],
      'others': g.othersSawThis,
      'ownPlusOne': g.ownPlusOne,
    };

BugLogGroupView groupFromJson(Map<String, dynamic> j) => BugLogGroupView(
      head: reportFromJson(_r(j['head'])),
      variants: [
        for (final v in (j['variants'] as List? ?? const [])) reportFromJson(_r(v))
      ],
      othersSawThis: (j['others'] as num?)?.toInt() ?? 0,
      ownPlusOne: j['ownPlusOne'] as bool? ?? false,
    );

Map<String, dynamic> requestToJson(FeatureRequestView f) => {
      'request': reportToJson(f.request),
      'yes': f.yes,
      'no': f.no,
      'dontCare': f.dontCare,
      if (f.ownVote != null) 'own': f.ownVote,
    };

FeatureRequestView requestFromJson(Map<String, dynamic> j) =>
    FeatureRequestView(
      request: reportFromJson(_r(j['request'])),
      yes: (j['yes'] as num?)?.toInt() ?? 0,
      no: (j['no'] as num?)?.toInt() ?? 0,
      dontCare: (j['dontCare'] as num?)?.toInt() ?? 0,
      ownVote: (j['own'] as num?)?.toInt(),
    );

Map<String, dynamic> draftToJson(SystemDraft d) => {
      'c': d.channel,
      'text': d.text,
      if (d.fingerprintHex != null) 'fp': d.fingerprintHex,
    };

SystemDraft draftFromJson(Map<String, dynamic> j) => SystemDraft(
    (j['c'] as num).toInt(), j['text'] as String? ?? '',
    fingerprintHex: j['fp'] as String?);

Map<String, dynamic> previewToJson(SystemDepositPreview p) => {
      'token': p.token,
      'c': p.channel,
      'publication': p.publication,
      if (p.statedUserIdHex != null) 'uid': p.statedUserIdHex,
      'contact': p.holderIsContact,
      if (p.existing != null) 'existing': reportToJson(p.existing!),
      'others': p.existingOthers,
      if (p.refusal != null) 'refusal': p.refusal!.name,
    };

SystemDepositPreview previewFromJson(Map<String, dynamic> j) =>
    SystemDepositPreview(
      token: j['token'] as String,
      channel: (j['c'] as num).toInt(),
      publication: j['publication'] as String? ?? '',
      statedUserIdHex: j['uid'] as String?,
      holderIsContact: j['contact'] as bool? ?? false,
      existing: j['existing'] == null ? null : reportFromJson(_r(j['existing'])),
      existingOthers: (j['others'] as num?)?.toInt() ?? 0,
      refusal: _enum(SystemRefusal.values, j['refusal']),
    );

Map<String, dynamic> resultToJson(SystemSendResult r) => {
      if (r.idHex != null) 'id': r.idHex,
      if (r.refusal != null) 'refusal': r.refusal!.name,
    };

SystemSendResult resultFromJson(Map<String, dynamic> j) {
  final refusal = _enum(SystemRefusal.values, j['refusal']);
  return refusal != null
      ? SystemSendResult.refused(refusal)
      : SystemSendResult.written(j['id'] as String?);
}

/// The daemon side of one `syschan_*` command: the data of the answer.
/// Throws [ArgumentError] for an unknown command or a missing parameter.
Future<Map<String, dynamic>> systemChannelServe(
    SystemChannelApi api, String command, Map<String, dynamic> p) async {
  int channel() => (p['channel'] as num).toInt();
  String s(String k) =>
      p[k] as String? ?? (throw ArgumentError('missing param: $k'));
  switch (command) {
    case 'syschan_bug_log':
      return {
        'groups': [for (final g in await api.bugLog()) groupToJson(g)]
      };
    case 'syschan_feature_requests':
      return {
        'requests': [
          for (final f in await api.featureRequests()) requestToJson(f)
        ]
      };
    case 'syschan_channel_opened':
      await api.channelOpened(channel());
      return const {};
    case 'syschan_mark_seen':
      await api.markSeen(
          channel(), (p['ids'] as List? ?? const []).cast<String>());
      return const {};
    case 'syschan_prepare':
      return previewToJson(await api.prepare(draftFromJson(_r(p['draft']))));
    case 'syschan_send':
      final choice = _enum(SystemSendChoice.values, p['choice']) ??
          (throw ArgumentError('missing param: choice'));
      return resultToJson(await api.send(s('token'), choice));
    case 'syschan_discard':
      await api.discard(s('token'));
      return const {};
    case 'syschan_vote':
      return resultToJson(
          await api.vote(s('id'), (p['option'] as num).toInt()));
    case 'syschan_retract':
      return resultToJson(await api.retract(s('id')));
    case 'syschan_holders_known':
      return {'known': await api.holdersKnown()};
  }
  throw ArgumentError('unknown command: $command');
}
