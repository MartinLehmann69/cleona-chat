import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Renders the content of a Bug Log report (crash report, contact issue,
/// log report) in a human-readable card format instead of raw JSON. The
/// group, its +1 count and the feature-request poll are drawn by
/// `SystemChannelScreen` (§16.7).
class SystemChannelPost extends StatefulWidget {
  final String text;
  final bool isOutgoing;
  final String timestamp;

  const SystemChannelPost({
    super.key,
    required this.text,
    required this.isOutgoing,
    required this.timestamp,
  });

  @override
  State<SystemChannelPost> createState() => _SystemChannelPostState();
}

class _SystemChannelPostState extends State<SystemChannelPost> {
  Map<String, dynamic>? _cachedJson;
  bool _parseFailed = false;

  String get text => widget.text;
  bool get isOutgoing => widget.isOutgoing;
  String get timestamp => widget.timestamp;

  @override
  void initState() {
    super.initState();
    _parseJson();
  }

  @override
  void didUpdateWidget(SystemChannelPost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _parseJson();
  }

  void _parseJson() {
    try {
      _cachedJson = jsonDecode(widget.text) as Map<String, dynamic>;
      _parseFailed = false;
    } catch (_) {
      _cachedJson = null;
      _parseFailed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final json = _cachedJson;
    if (_parseFailed || json == null) {
      return _plainFallback(colorScheme);
    }

    final type = json['type'] as String?;
    if (type == 'crash_report') {
      return _buildCrashReport(context, json, colorScheme);
    }
    if (type == 'contact_issue') {
      return _buildContactIssue(context, json, colorScheme);
    }
    if (type == 'log_report') {
      return _buildLogReport(context, json, colorScheme);
    }
    return _plainFallback(colorScheme);
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
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _chip(cs, report.platform),
                _chip(cs, AppLocale.read(context).tr('issue_report_peers', {'count': '${report.peerCount}'})),
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
              AppLocale.read(context).tr('issue_report_contact_line', {
                'age': ContactIssueReport.formatDuration(report.seedAgeSeconds),
                'nat': report.natType,
                // `peerSeenInDht` keeps its report-format name (4.2.x
                // readers); in 4.2 it says whether the contact's keys are
                // known (`isPeerKnownByUserId`) — there is no DHT.
                'keys': AppLocale.read(context).get(report.peerSeenInDht
                    ? 'issue_report_keys_known'
                    : 'issue_report_keys_unknown'),
              }),
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _chip(cs, report.platform),
                _chip(cs, AppLocale.read(context).tr('issue_report_peers', {'count': '${report.peerCount}'})),
                _chip(cs, report.hasPortMapping ? 'UPnP' : AppLocale.read(context).get('upnp_none')),
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
                    AppLocale.read(context).get('log_report_title'),
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
              AppLocale.read(context).tr('issue_report_net_summary', {
                'nat': report.natType,
                'peers': '${report.peerCount}',
                'routes': '${report.routeCount}',
                'uptime':
                    ContactIssueReport.formatDuration(report.uptimeSeconds),
              }),
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
                  AppLocale.read(context)
                      .tr('log_more_lines', {'count': '${logLines.length - 8}'}),
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: cs.onSecondaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _chip(cs, report.platform),
                _chip(cs, report.hasPortMapping ? 'UPnP' : AppLocale.read(context).get('upnp_none')),
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
