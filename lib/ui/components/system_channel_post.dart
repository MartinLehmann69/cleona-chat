import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cleona/core/channels/system_channels.dart';

/// Renders a system channel post (crash report or duplicate) in a
/// human-readable card format instead of raw JSON.
class SystemChannelPost extends StatelessWidget {
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
