import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';

class ShareCleonaDialog {
  static Future<void> show(BuildContext context, ICleonaService service) async {
    final inviteUrl = service.generateInviteLinkUrl();
    final lanIp = await _getLanIp();
    final port = service.port;
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => _ShareCleonaDialogContent(
        inviteUrl: inviteUrl,
        lanIp: lanIp,
        port: port,
      ),
    );
  }

  static Future<String?> _getLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('10.') ||
              ip.startsWith('192.168.') ||
              (ip.startsWith('172.') && _isPrivate172(ip))) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivate172(String ip) {
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? 0;
    return second >= 16 && second <= 31;
  }
}

class _ShareCleonaDialogContent extends StatelessWidget {
  final String? inviteUrl;
  final String? lanIp;
  final int port;

  const _ShareCleonaDialogContent({
    required this.inviteUrl,
    required this.lanIp,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(locale.get('share_cleona')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Platform.isAndroid) ...[
                _DirectShareTile(locale: locale, theme: theme),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
              ],
              if (inviteUrl != null) ...[
                _InviteLinkTile(
                  inviteUrl: inviteUrl!,
                  locale: locale,
                  theme: theme,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.cloud_done, size: 14,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locale.get('share_cleona_nostr_hint'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (lanIp != null) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                ],
              ],
              if (lanIp != null) ...[
                _buildExpansionSection(
                  context: context,
                  icon: Icons.android,
                  title: locale.get('share_cleona_for_android'),
                  children: [
                    _CommandBlock(
                      label: locale.get('share_cleona_http_hint'),
                      command: 'http://$lanIp:$port/cleona/binary/android',
                      copyLabel: locale.get('share_cleona_copy_link'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildExpansionSection(
                  context: context,
                  icon: Icons.computer,
                  title: locale.get('share_cleona_for_desktop'),
                  children: [
                    _CommandBlock(
                      label: 'Windows (PowerShell):',
                      command:
                          'curl.exe -o cleona-setup.exe http://$lanIp:$port/cleona/binary/windows',
                      copyLabel: locale.get('share_cleona_copy_command'),
                    ),
                    const SizedBox(height: 12),
                    _CommandBlock(
                      label: 'Linux:',
                      command:
                          'curl -o cleona http://$lanIp:$port/cleona/binary/linux && chmod +x cleona',
                      copyLabel: locale.get('share_cleona_copy_command'),
                    ),
                  ],
                ),
              ],
              if (inviteUrl == null && lanIp == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    locale.get('share_cleona_no_public_ip'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 18),
                label: Text(locale.get('share_cleona_download_link')),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                    text:
                        'https://github.com/MartinLehmann69/cleona-chat/releases/latest',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(locale.get('copied_to_clipboard'))),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locale.get('close')),
        ),
      ],
    );
  }

  Widget _buildExpansionSection({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      children: children,
    );
  }
}

class _InviteLinkTile extends StatelessWidget {
  final String inviteUrl;
  final AppLocale locale;
  final ThemeData theme;

  const _InviteLinkTile({
    required this.inviteUrl,
    required this.locale,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          locale.get('share_cleona_invite_hint'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            inviteUrl,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            maxLines: 4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: Text(locale.get('share_cleona_copy_link'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: inviteUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(locale.get('copied_to_clipboard'))),
                );
              },
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.share, size: 14),
              label: Text(locale.get('share'),
                  style: const TextStyle(fontSize: 12)),
              onPressed: () {
                Share.share(inviteUrl, subject: 'Cleona Chat');
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _DirectShareTile extends StatefulWidget {
  final AppLocale locale;
  final ThemeData theme;

  const _DirectShareTile({required this.locale, required this.theme});

  @override
  State<_DirectShareTile> createState() => _DirectShareTileState();
}

class _DirectShareTileState extends State<_DirectShareTile> {
  bool _sharing = false;

  Future<void> _shareApk() async {
    setState(() => _sharing = true);
    try {
      const channel = MethodChannel('chat.cleona/share');
      final apkPath = await channel.invokeMethod<String>('getOwnApkPath');
      if (apkPath != null && mounted) {
        await Share.shareXFiles(
          [XFile(apkPath, mimeType: 'application/vnd.android.package-archive')],
          subject: 'Cleona Chat',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: widget.theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: ListTile(
        leading: _sharing
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.share, size: 24),
        title: Text(widget.locale.get('share_cleona_direct_share')),
        subtitle: Text(
          'Bluetooth, Quick Share, ...',
          style: widget.theme.textTheme.bodySmall,
        ),
        onTap: _sharing ? null : _shareApk,
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  final String label;
  final String command;
  final String copyLabel;

  const _CommandBlock({
    required this.label,
    required this.command,
    required this.copyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            command,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: Text(copyLabel, style: const TextStyle(fontSize: 12)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocale.read(context).get('copied_to_clipboard'))),
              );
            },
          ),
        ),
      ],
    );
  }
}
