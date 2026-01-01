import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/system_channels.dart' show LogReport;
import 'package:cleona/core/channels/system_object.dart' show SystemVote;
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/platform/app_screenshot.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/components/system_channel_post.dart';
import 'package:cleona/ui/components/system_deposit_dialog.dart';
import 'package:cleona/ui/components/system_report_widgets.dart';

/// The page of a conversation from the home list: the two system channels
/// open their own screen (§16.7), every other conversation returns null and
/// opens the chat.
Widget? systemChannelPage(
  ICleonaService service,
  String conversationId,
  String title,
) {
  final channel = SystemChannel.ofConversation(conversationId);
  if (channel == null) return null;
  return SystemChannelScreen(
    channel: channel,
    title: title,
    api: service.systemChannelApi,
    buildLogReport: channel == SystemChannel.bugLog
        ? service.buildLogReport
        : null,
  );
}

/// Bug Log and Feature Requests (v4_2 §16.7): public channels without an
/// owner, read from the durable-object class — no chat, no free text in the
/// Bug Log, every deposit through the preview.
class SystemChannelScreen extends StatefulWidget {
  final int channel;
  final String title;
  final SystemChannelApi api;

  /// Builds the manual log report (Bug Log only).
  final Future<LogReport> Function()? buildLogReport;

  const SystemChannelScreen({
    super.key,
    required this.channel,
    required this.title,
    required this.api,
    this.buildLogReport,
  });

  @override
  State<SystemChannelScreen> createState() => _SystemChannelScreenState();
}

class _SystemChannelScreenState extends State<SystemChannelScreen> {
  StreamSubscription<void>? _sub;
  List<BugLogGroupView>? _groups;
  List<FeatureRequestView>? _requests;

  /// Reports that were new when this visit showed them; they keep the mark
  /// for the visit although they are marked seen at once.
  final Set<String> _newThisVisit = {};

  bool get _isBugLog => widget.channel == SystemChannel.bugLog;

  @override
  void initState() {
    super.initState();
    _sub = widget.api.changes.listen((_) => _reload());
    // §16.7: reading happens when the user opens the channel.
    unawaited(widget.api.channelOpened(widget.channel));
    _reload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      if (_isBugLog) {
        final groups = await widget.api.bugLog();
        if (!mounted) return;
        setState(() => _groups = groups);
        _noteNew([
          for (final g in groups) ...[g.head, ...g.variants],
        ]);
      } else {
        final requests = await widget.api.featureRequests();
        if (!mounted) return;
        setState(() => _requests = requests);
        _noteNew([for (final r in requests) r.request]);
      }
    } catch (e) {
      debugPrint('System channel ${widget.channel} not readable: $e');
    }
  }

  void _noteNew(List<SystemReportView> shown) {
    final fresh = [
      for (final r in shown)
        if (r.isNew && r.fetched && _newThisVisit.add(r.idHex)) r.idHex,
    ];
    if (fresh.isEmpty) return;
    unawaited(widget.api.markSeen(widget.channel, fresh));
  }

  bool _showsNew(SystemReportView r) =>
      r.isNew || _newThisVisit.contains(r.idHex);

  Future<void> _screenshot() async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await AppScreenshot.capture();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          locale.get(
            result.saved && result.uri != null
                ? 'screenshot_saved'
                : 'screenshot_failed',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AppBarScaffold(
      title: widget.title,
      subtitle: locale.get('channel_public'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      actions: [
        if (AppScreenshot.isOffered)
          IconButton(
            icon: const Icon(Icons.screenshot),
            tooltip: locale.get('screenshot_action'),
            onPressed: _screenshot,
          ),
      ],
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _isBugLog ? _bugLogList(locale) : _requestList(locale),
            ),
            _isBugLog ? _bugLogBar(locale) : _requestBar(locale),
          ],
        ),
      ),
    );
  }

  // ── Bug Log ──────────────────────────────────────────────────────────

  Widget _bugLogList(AppLocale locale) {
    final groups = _groups;
    if (groups == null) return const Center(child: CircularProgressIndicator());
    if (groups.isEmpty) {
      return Center(child: Text(locale.get('sys_empty_bug_log')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groups.length,
      itemBuilder: (context, i) => _groupCard(locale, groups[i]),
    );
  }

  Widget _groupCard(AppLocale locale, BugLogGroupView g) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('sys_group_${g.head.idHex}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _report(locale, g.head),
            if (g.othersSawThis > 0 || g.ownPlusOne)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (g.othersSawThis > 0)
                      Tooltip(
                        message: locale.get('sys_others_saw_hint'),
                        child: Text(
                          '${locale.tr('sys_others_saw', {'count': '${g.othersSawThis}'})}'
                          ' · ${locale.get('sys_others_saw_hint')}',
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ),
                    if (g.ownPlusOne)
                      Text(
                        locale.get('sys_own_plus_one'),
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                  ],
                ),
              ),
            if (g.variants.isNotEmpty)
              ExpansionTile(
                key: ValueKey('sys_variants_${g.head.idHex}'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  locale.tr('sys_variants', {'count': '${g.variants.length}'}),
                  style: const TextStyle(fontSize: 13),
                ),
                children: [for (final v in g.variants) _report(locale, v)],
              ),
          ],
        ),
      ),
    );
  }

  /// One report: content, "new" mark, own state and retraction.
  Widget _report(AppLocale locale, SystemReportView r) {
    final cs = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(context).formatShortDate(r.created);
    return Column(
      key: ValueKey('sys_report_${r.idHex}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.fetched)
          SystemChannelPost(text: r.text, isOutgoing: r.own, timestamp: date)
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              locale.get('sys_not_fetched'),
              style: TextStyle(fontStyle: FontStyle.italic, color: cs.outline),
            ),
          ),
        _reportFooter(locale, r),
      ],
    );
  }

  Widget _reportFooter(AppLocale locale, SystemReportView r) {
    final status = r.status;
    if (!_showsNew(r) && !r.own) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (_showsNew(r)) ...[
            const SystemNewBadge(),
            const SizedBox(width: 6),
          ],
          if (r.own && status != null)
            Flexible(child: SystemReportStateChip(status)),
          const Spacer(),
          if (r.own)
            PopupMenuButton<String>(
              key: ValueKey('sys_menu_${r.idHex}'),
              onSelected: (_) => _retract(r),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'retract',
                  child: Text(locale.get('sys_retract')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _retract(SystemReportView r) async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(locale.get('sys_retract_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            key: const ValueKey('sys_retract_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(locale.get('sys_retract')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = await widget.api.retract(r.idHex);
      final refusal = result.refusal;
      if (refusal != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(systemRefusalText(locale, refusal))),
        );
      }
    } catch (e) {
      debugPrint('Retract failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(locale.get('sys_action_failed'))),
      );
    }
    await _reload();
  }

  Widget _bar(List<Widget> children) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(children: children),
  );

  Widget _bugLogBar(AppLocale locale) {
    final cs = Theme.of(context).colorScheme;
    return _bar([
      Icon(Icons.info_outline, size: 16, color: cs.outline),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          locale.get('sys_bug_log_info'),
          style: TextStyle(
            fontSize: 12,
            color: cs.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      if (widget.buildLogReport != null) ...[
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('sys_publish_log'),
          onPressed: _publishLog,
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(locale.get('bug_log_publish')),
        ),
      ],
    ]);
  }

  Future<void> _publishLog() async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final LogReport report;
    try {
      report = await widget.buildLogReport!();
    } catch (e) {
      debugPrint('Log report preview unavailable: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(locale.get('bug_log_report_unavailable'))),
      );
      return;
    }
    if (!mounted) return;
    await showSystemDepositFlow(
      context: context,
      api: widget.api,
      draft: SystemDraft.log(report),
      titleKey: 'bug_log_publish_title',
      introKey: 'bug_log_publish_text',
    );
    await _reload();
  }

  // ── Feature Requests ─────────────────────────────────────────────────

  /// Sorted by net votes, ties newest first — locally (§16.7).
  static List<FeatureRequestView> sortByNet(List<FeatureRequestView> rs) =>
      List<FeatureRequestView>.from(rs)..sort((a, b) {
        if (a.net != b.net) return b.net.compareTo(a.net);
        return b.request.created.compareTo(a.request.created);
      });

  Widget _requestList(AppLocale locale) {
    final requests = _requests;
    if (requests == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (requests.isEmpty) {
      return Center(child: Text(locale.get('sys_empty_features')));
    }
    final sorted = sortByNet(requests);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sorted.length,
      itemBuilder: (context, i) => _requestCard(locale, sorted[i]),
    );
  }

  Widget _requestCard(AppLocale locale, FeatureRequestView fr) {
    final cs = Theme.of(context).colorScheme;
    final r = fr.request;
    var title = '';
    var body = '';
    if (r.fetched) {
      try {
        final j = jsonDecode(r.text) as Map<String, dynamic>;
        title = j['title'] as String? ?? '';
        body = j['body'] as String? ?? '';
      } catch (_) {
        title = r.text;
      }
    }

    Widget voteButton(int option, String labelKey, int count) {
      final label = '${locale.get(labelKey)} ($count)';
      final text = Text(
        label,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      );
      final key = ValueKey('sys_vote_${r.idHex}_$option');
      void onTap() => _vote(fr, option);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: fr.ownVote == option
              ? FilledButton(key: key, onPressed: onTap, child: text)
              : OutlinedButton(key: key, onPressed: onTap, child: text),
        ),
      );
    }

    return Card(
      key: ValueKey('sys_request_${r.idHex}'),
      color: cs.primaryContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: r.fetched
                      ? Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      : Text(
                          locale.get('sys_not_fetched'),
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: cs.outline,
                          ),
                        ),
                ),
                Text(
                  locale.tr('sys_net_votes', {'count': '${fr.net}'}),
                  key: ValueKey('sys_net_${r.idHex}'),
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 13)),
            ],
            if (r.fetched) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  voteButton(SystemVote.yes, 'feature_vote_yes', fr.yes),
                  voteButton(SystemVote.no, 'feature_vote_no', fr.no),
                  voteButton(
                    SystemVote.dontCare,
                    'feature_vote_neutral',
                    fr.dontCare,
                  ),
                ],
              ),
            ],
            _reportFooter(locale, r),
          ],
        ),
      ),
    );
  }

  Future<void> _vote(FeatureRequestView fr, int option) async {
    final locale = AppLocale.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.api.vote(fr.request.idHex, option);
      final refusal = result.refusal;
      if (refusal != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(systemRefusalText(locale, refusal))),
        );
      }
    } catch (e) {
      debugPrint('Vote failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(locale.get('sys_action_failed'))),
      );
    }
    await _reload();
  }

  Widget _requestBar(AppLocale locale) => _bar([
    Expanded(
      child: Center(
        child: FilledButton.icon(
          key: const ValueKey('sys_submit_request'),
          onPressed: _submitRequest,
          icon: const Icon(Icons.lightbulb_outline),
          label: Text(locale.get('feature_request_submit')),
        ),
      ),
    ),
  ]);

  Future<void> _submitRequest() async {
    final entered = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _RequestDialog(),
    );
    if (entered == null || !mounted) return;
    await showSystemDepositFlow(
      context: context,
      api: widget.api,
      draft: SystemDraft.featureRequest(entered.$1, entered.$2),
      titleKey: 'feature_request_submit',
      introKey: 'feature_request_options_hint',
    );
    await _reload();
  }
}

/// Title and description of an own feature request; pops (title, body).
/// Owns its controllers so they outlive the closing animation.
class _RequestDialog extends StatefulWidget {
  const _RequestDialog();

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final headingCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  @override
  void dispose() {
    headingCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final locale = AppLocale.read(ctx);
    return AlertDialog(
      title: Text(locale.get('feature_request_submit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('sys_request_heading'),
              controller: headingCtrl,
              decoration: InputDecoration(
                labelText: locale.get('feature_request_heading'),
                border: const OutlineInputBorder(),
              ),
              maxLength: 100,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sys_request_body'),
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: locale.get('feature_request_description'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            // The poll is attached automatically to every request (§16.7).
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${locale.get('feature_vote_yes')} · '
                '${locale.get('feature_vote_no')} · '
                '${locale.get('feature_vote_neutral')}\n'
                '${locale.get('feature_request_options_hint')}',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(locale.get('cancel')),
        ),
        FilledButton(
          key: const ValueKey('sys_request_next'),
          onPressed: () {
            if (headingCtrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, (headingCtrl.text, descCtrl.text));
          },
          child: Text(locale.get('feature_request_submit')),
        ),
      ],
    );
  }
}
