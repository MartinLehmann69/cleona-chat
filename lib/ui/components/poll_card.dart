import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';

/// Interactive poll card rendered inside group/channel chat bubbles (§24.6).
///
/// Looks up the poll by [pollId] on the active service and shows:
///   • question + poll type badge
///   • progress bars / date grid / scale histogram / free-text list
///   • vote / revoke / close / delete action buttons
///   • anonymity notice when [Poll.settings.anonymous] is true
class PollCard extends StatelessWidget {
  final String pollId;

  const PollCard({super.key, required this.pollId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = AppLocale.of(context);
    final appState = context.watch<CleonaAppState>();
    final service = appState.service;
    if (service == null) return const SizedBox.shrink();
    final poll = service.pollManager.polls[pollId];
    if (poll == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(locale.get('poll_unavailable'),
            style: TextStyle(fontStyle: FontStyle.italic, color: colorScheme.outline)),
      );
    }
    final tally = service.pollManager.computeTally(pollId);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, poll, colorScheme, locale),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(poll.question,
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          ),
          if (poll.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(poll.description,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.7))),
            ),
          _body(context, poll, tally, colorScheme, locale),
          if (poll.settings.anonymous) _anonymityNotice(poll, colorScheme, locale),
          _footer(context, poll, tally, colorScheme, locale),
          _actions(context, poll, colorScheme, locale),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Poll poll, ColorScheme colorScheme, AppLocale locale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.poll, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('[${locale.get(_typeLabelKey(poll.pollType))}]',
              style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (poll.closed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(locale.get('poll_closed'),
                  style: TextStyle(fontSize: 10, color: colorScheme.error)),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    switch (poll.pollType) {
      case PollType.singleChoice:
      case PollType.multipleChoice:
        return _choiceBody(context, poll, tally, colorScheme, locale);
      case PollType.datePoll:
        return _dateBody(context, poll, tally, colorScheme, locale);
      case PollType.scale:
        return _scaleBody(context, poll, tally, colorScheme, locale);
      case PollType.freeText:
        return _freeTextBody(context, poll, tally, colorScheme, locale);
    }
  }

  Widget _choiceBody(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    final total = tally.optionCounts.values.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final opt in poll.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opt.label, style: TextStyle(color: colorScheme.onSurface)),
                        const SizedBox(height: 2),
                        LinearProgressIndicator(
                          value: total == 0 ? 0.0 : (tally.optionCounts[opt.optionId] ?? 0) / total,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                          color: colorScheme.primary,
                          minHeight: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${tally.optionCounts[opt.optionId] ?? 0}',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateBody(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    String fmt(int? ms) {
      if (ms == null) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.day}.${dt.month}. ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          for (final opt in poll.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(fmt(opt.dateStart),
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
                  ),
                  for (final availability in DateAvailability.values)
                    Expanded(
                      child: Text(
                        '${_availabilityLabel(availability)} ${tally.dateCounts[opt.optionId]?[availability] ?? 0}',
                        style: TextStyle(fontSize: 12, color: _availabilityColor(availability)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _scaleBody(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    final counts = <int, int>{
      for (var i = poll.settings.scaleMin; i <= poll.settings.scaleMax; i++) i: 0,
    };
    for (final v in poll.votes.values) {
      if (counts.containsKey(v.scaleValue)) counts[v.scaleValue] = counts[v.scaleValue]! + 1;
    }
    final maxCount = counts.values.isEmpty ? 0 : counts.values.reduce(math.max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in counts.entries)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: maxCount == 0 ? 2.0 : 30.0 * (entry.value / maxCount),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: colorScheme.primary,
                  ),
                  Text('${entry.key}', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _freeTextBody(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    if (tally.freeTextResponses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(locale.get('poll_no_responses'),
            style: TextStyle(fontStyle: FontStyle.italic, color: colorScheme.outline, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final text in tally.freeTextResponses.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text('• $text',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
            ),
          if (tally.freeTextResponses.length > 5)
            Text(locale.tr('poll_more_responses',
                {'count': '${tally.freeTextResponses.length - 5}'}),
                style: TextStyle(fontSize: 11, color: colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _anonymityNotice(Poll poll, ColorScheme colorScheme, AppLocale locale) {
    final group = _estimatedRingSize(poll);
    final warn = group < 7;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(warn ? Icons.warning_amber : Icons.shield_outlined,
              size: 14, color: warn ? colorScheme.tertiary : colorScheme.primary),
          const SizedBox(width: 4),
          Text(locale.tr('poll_anonymity_set', {'count': '$group'}),
              style: TextStyle(fontSize: 11, color: colorScheme.outline)),
        ],
      ),
    );
  }

  int _estimatedRingSize(Poll poll) {
    // Best-effort estimate — the full ring is only known to the daemon, but the
    // locally cached poll includes vote count as a lower bound.
    return math.max(poll.options.length, poll.votes.length);
  }

  Widget _footer(BuildContext context, Poll poll, PollTally tally,
      ColorScheme colorScheme, AppLocale locale) {
    final lines = <String>[];
    lines.add(locale.tr('poll_total_votes', {'count': '${tally.totalVotes}'}));
    if (poll.settings.deadline > 0 && !poll.closed) {
      final dt = DateTime.fromMillisecondsSinceEpoch(poll.settings.deadline);
      lines.add(locale.tr('poll_ends_at',
          {'date': '${dt.day}.${dt.month}.${dt.year}'}));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(lines.join(' · '),
          style: TextStyle(fontSize: 11, color: colorScheme.outline)),
    );
  }

  Widget _actions(BuildContext context, Poll poll, ColorScheme colorScheme, AppLocale locale) {
    final appState = context.read<CleonaAppState>();
    final service = appState.service!;
    final isCreator = poll.createdByHex == service.nodeIdHex;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!poll.closed)
            TextButton.icon(
              icon: const Icon(Icons.how_to_vote, size: 16),
              label: Text(locale.get('poll_vote'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => _openVoteSheet(context, poll),
            ),
          if (poll.settings.anonymous && !poll.closed)
            TextButton.icon(
              icon: const Icon(Icons.undo, size: 16),
              label: Text(locale.get('poll_revoke'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => service.revokePollVoteAnonymous(poll.pollId),
            ),
          if (isCreator && !poll.closed)
            TextButton.icon(
              icon: const Icon(Icons.lock_clock, size: 16),
              label: Text(locale.get('poll_close'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => service.updatePoll(poll.pollId, close: true),
            ),
          if (isCreator)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(locale.get('poll_delete'),
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
              onPressed: () => service.updatePoll(poll.pollId, delete: true),
            ),
          if (poll.pollType == PollType.datePoll && isCreator && poll.closed)
            TextButton.icon(
              icon: const Icon(Icons.event, size: 16),
              label: Text(locale.get('poll_to_event'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () => _promoteDatePollToEvent(context, poll),
            ),
        ],
      ),
    );
  }

  Future<void> _openVoteSheet(BuildContext context, Poll poll) async {
    final service = context.read<CleonaAppState>().service!;
    final locale = AppLocale.of(context);

    switch (poll.pollType) {
      case PollType.singleChoice:
        {
          final chosen = await showModalBottomSheet<int>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final opt in poll.options)
                    ListTile(
                      title: Text(opt.label),
                      onTap: () => Navigator.pop(ctx, opt.optionId),
                    ),
                ],
              ),
            ),
          );
          if (chosen == null) return;
          if (poll.settings.anonymous) {
            await service.submitPollVoteAnonymous(
                pollId: poll.pollId, selectedOptions: [chosen]);
          } else {
            await service.submitPollVote(
                pollId: poll.pollId, selectedOptions: [chosen]);
          }
        }
        break;
      case PollType.multipleChoice:
        {
          final selected = <int>{};
          final max = poll.settings.maxChoices;
          await showModalBottomSheet(
            context: context,
            builder: (ctx) => StatefulBuilder(builder: (c, setState) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final opt in poll.options)
                      CheckboxListTile(
                        value: selected.contains(opt.optionId),
                        title: Text(opt.label),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            if (max == 0 || selected.length < max) {
                              selected.add(opt.optionId);
                            }
                          } else {
                            selected.remove(opt.optionId);
                          }
                        }),
                      ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(locale.get('poll_vote')),
                    ),
                  ],
                ),
              );
            }),
          );
          if (selected.isEmpty) return;
          if (poll.settings.anonymous) {
            await service.submitPollVoteAnonymous(
                pollId: poll.pollId, selectedOptions: selected.toList());
          } else {
            await service.submitPollVote(
                pollId: poll.pollId, selectedOptions: selected.toList());
          }
        }
        break;
      case PollType.datePoll:
        {
          final responses = <int, DateAvailability>{};
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => StatefulBuilder(builder: (c, setState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final opt in poll.options)
                        ListTile(
                          title: Text(opt.label),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              for (final a in DateAvailability.values)
                                ChoiceChip(
                                  label: Text(_availabilityLabel(a)),
                                  selected: responses[opt.optionId] == a,
                                  onSelected: (_) => setState(
                                      () => responses[opt.optionId] = a),
                                ),
                            ],
                          ),
                        ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(locale.get('poll_vote')),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
          if (responses.isEmpty) return;
          if (poll.settings.anonymous) {
            await service.submitPollVoteAnonymous(
                pollId: poll.pollId, dateResponses: responses);
          } else {
            await service.submitPollVote(
                pollId: poll.pollId, dateResponses: responses);
          }
        }
        break;
      case PollType.scale:
        {
          var value = poll.settings.scaleMin;
          final chosen = await showModalBottomSheet<int>(
            context: context,
            builder: (ctx) => StatefulBuilder(builder: (c, setState) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      min: poll.settings.scaleMin.toDouble(),
                      max: poll.settings.scaleMax.toDouble(),
                      divisions:
                          poll.settings.scaleMax - poll.settings.scaleMin,
                      value: value.toDouble(),
                      label: '$value',
                      onChanged: (v) => setState(() => value = v.round()),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, value),
                      child: Text(locale.get('poll_vote')),
                    ),
                  ],
                ),
              );
            }),
          );
          if (chosen == null) return;
          if (poll.settings.anonymous) {
            await service.submitPollVoteAnonymous(
                pollId: poll.pollId, scaleValue: chosen);
          } else {
            await service.submitPollVote(
                pollId: poll.pollId, scaleValue: chosen);
          }
        }
        break;
      case PollType.freeText:
        {
          final ctrl = TextEditingController();
          final text = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding:
                    EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: ctrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: locale.get('poll_response_hint'),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: Text(locale.get('poll_vote')),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (text == null || text.isEmpty) return;
          if (poll.settings.anonymous) {
            await service.submitPollVoteAnonymous(
                pollId: poll.pollId, freeText: text);
          } else {
            await service.submitPollVote(pollId: poll.pollId, freeText: text);
          }
        }
        break;
    }
  }

  Future<void> _promoteDatePollToEvent(BuildContext context, Poll poll) async {
    final service = context.read<CleonaAppState>().service!;
    final tally = service.pollManager.computeTally(poll.pollId);
    var bestOption = -1;
    var bestYes = -1;
    for (final entry in tally.dateCounts.entries) {
      final yes = entry.value[DateAvailability.yes] ?? 0;
      if (yes > bestYes) {
        bestYes = yes;
        bestOption = entry.key;
      }
    }
    if (bestOption < 0) return;
    await service.convertDatePollToEvent(poll.pollId, bestOption);
  }

  String _typeLabelKey(PollType t) {
    switch (t) {
      case PollType.singleChoice: return 'poll_type_single';
      case PollType.multipleChoice: return 'poll_type_multiple';
      case PollType.datePoll: return 'poll_type_date';
      case PollType.scale: return 'poll_type_scale';
      case PollType.freeText: return 'poll_type_free_text';
    }
  }

  String _availabilityLabel(DateAvailability a) {
    switch (a) {
      case DateAvailability.yes: return '✓';
      case DateAvailability.maybe: return '?';
      case DateAvailability.no: return '✗';
    }
  }

  Color _availabilityColor(DateAvailability a) {
    switch (a) {
      case DateAvailability.yes: return Colors.green;
      case DateAvailability.maybe: return Colors.orange;
      case DateAvailability.no: return Colors.red;
    }
  }
}
