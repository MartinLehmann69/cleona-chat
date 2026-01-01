import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_channel_records.dart'
    show SysChanVote;
import 'package:cleona/core/i18n/app_locale.dart';

/// Renders a system channel post (crash report, duplicate, contact issue,
/// log report, feature request) in a human-readable card format instead of
/// raw JSON.
class SystemChannelPost extends StatelessWidget {
  final String text;
  final bool isOutgoing;
  final String timestamp;

  /// §9.5.3 D3 (S119): FR tally (`ja`/`nein`/`egal`/`net`/`own`) + vote
  /// callback — only set for feature-request cards.
  final Map<String, int>? frTally;
  final void Function(int option)? onVote;

  const SystemChannelPost({
    super.key,
    required this.text,
    required this.isOutgoing,
    required this.timestamp,
    this.frTally,
    this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return _plainFallback(colorScheme);
    }

    final type = json['type'] as String?;
    if (type == 'crash_report') {
      return _buildCrashReport(context, json, colorScheme);
    }
    if (type == 'crash_duplicate') {
      return _buildDuplicate(context, json, colorScheme);
    }
    if (type == 'contact_issue') {
      return _buildContactIssue(context, json, colorScheme);
    }
    if (type == 'log_report') {
      return _buildLogReport(context, json, colorScheme);
    }
    if (type == 'feature_request') {
      return _buildFeatureRequest(context, json, colorScheme);
    }
    return _plainFallback(colorScheme);
  }

  /// §9.5.3 (S119 D3): Feature-Request card with the embedded auto-poll —
  /// Ja/Nein/Egal vote buttons with live counts, own vote highlighted.
  Widget _buildFeatureRequest(
      BuildContext context, Map<String, dynamic> json, ColorScheme cs) {
    final locale = AppLocale.read(context);
    final title = json['title'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final tally = frTally ?? const {'ja': 0, 'nein': 0, 'egal': 0, 'own': -1};
    final own = tally['own'] ?? -1;

    Widget voteButton(int option, String labelKey, int count) {
      final selected = own == option;
      final label = '${locale.get(labelKey)} ($count)';
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: selected
              ? FilledButton(
                  onPressed: onVote == null ? null : () => onVote!(option),
                  child: Text(label,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                )
              : OutlinedButton(
                  onPressed: onVote == null ? null : () => onVote!(option),
                  child: Text(label,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
        ),
      );
    }

    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                voteButton(SysChanVote.ja, 'feature_vote_yes',
                    tally['ja'] ?? 0),
                voteButton(SysChanVote.nein, 'feature_vote_no',
                    tally['nein'] ?? 0),
                voteButton(SysChanVote.egal, 'feature_vote_neutral',
                    tally['egal'] ?? 0),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(timestamp,
                  style: TextStyle(fontSize: 10, color: cs.outline)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrashReport(
      BuildContext context, Map<String, dynamic> json, ColorScheme cs) {
    final report = CrashReport.fromJson(json);
    if (report == null) return _plainFallback(cs);

    return Card(
      color: cs.errorContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, size: 18, color: cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    report.exceptionType,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onErrorContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'v${report.appVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onErrorContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              report.exceptionMsg,
              style: TextStyle(
                fontSize: 12,
                color: cs.onErrorContainer,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                report.stackTrace.split('\n').take(5).join('\n'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _chip(cs, report.platform),
                const SizedBox(width: 4),
                _chip(cs, '${report.peerCount} peers'),
                const Spacer(),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onErrorContainer.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDuplicate(
      BuildContext context, Map<String, dynamic> json, ColorScheme cs) {
    final dupe = CrashDuplicateReply.fromJson(json);
    if (dupe == null) return _plainFallback(cs);

    final fp = dupe.fingerprint.length > 12
        ? dupe.fingerprint.substring(0, 12)
        : dupe.fingerprint;

    return Card(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, size: 16, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '+1  (v${dupe.appVersion}, ${dupe.platform})',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            Text(
              fp,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactIssue(
      BuildContext context, Map<String, dynamic> json, ColorScheme cs) {
    final report = ContactIssueReport.fromJson(json);
    if (report == null) return _plainFallback(cs);

    return Card(
      color: cs.tertiaryContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contact_support, size: 18, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${report.contactName} (${report.contactIdShort})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onTertiaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'v${report.appVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onTertiaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Seed-Alter: ${ContactIssueReport.formatDuration(report.seedAgeSeconds)} · '
              'NAT: ${report.natType} · '
              'DHT: ${report.peerSeenInDht ? "sichtbar" : "nicht sichtbar"}',
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _chip(cs, report.platform),
                const SizedBox(width: 4),
                _chip(cs, '${report.peerCount} peers'),
                const SizedBox(width: 4),
                _chip(cs, report.hasPortMapping ? 'UPnP' : 'kein UPnP'),
                const Spacer(),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onTertiaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogReport(
      BuildContext context, Map<String, dynamic> json, ColorScheme cs) {
    final report = LogReport.fromJson(json);
    if (report == null) return _plainFallback(cs);

    final logLines = report.logTail.split('\n');

    return Card(
      color: cs.secondaryContainer.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article_outlined, size: 18, color: cs.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Log Report',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
                Text(
                  'v${report.appVersion}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'NAT: ${report.natType} · '
              '${report.peerCount} Peers · '
              '${report.routeCount} Routen · '
              'Uptime: ${ContactIssueReport.formatDuration(report.uptimeSeconds)}',
              style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                logLines.take(8).join('\n'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (logLines.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '... ${logLines.length - 8} weitere Zeilen',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                _chip(cs, report.platform),
                const SizedBox(width: 4),
                _chip(cs, report.hasPortMapping ? 'UPnP' : 'kein UPnP'),
                const Spacer(),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: cs.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _plainFallback(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: cs.onSurface),
      ),
    );
  }
}
