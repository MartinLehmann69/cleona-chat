import 'package:flutter/material.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Device Management Screen (§26) — list, rename, revoke twin devices.
class DeviceManagementScreen extends StatefulWidget {
  final ICleonaService service;
  const DeviceManagementScreen({super.key, required this.service});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<DeviceRecord> _devices = [];
  String _localDeviceId = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.service.onStateChanged = () {
      if (mounted) _refresh();
    };
  }

  void _refresh() {
    setState(() {
      _devices = widget.service.devices;
      _localDeviceId = widget.service.localDeviceId;
      // Sort: this device first, then by lastSeen descending
      _devices.sort((a, b) {
        if (a.deviceId == _localDeviceId) return -1;
        if (b.deviceId == _localDeviceId) return 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });
    });
  }

  IconData _platformIcon(String platform) {
    switch (platform) {
      case 'android': return Icons.phone_android;
      case 'ios': return Icons.phone_iphone;
      case 'linux': return Icons.computer;
      case 'windows': return Icons.desktop_windows;
      case 'macos': return Icons.laptop_mac;
      default: return Icons.devices;
    }
  }

  String _formatLastSeen(BuildContext context, DeviceRecord device) {
    final locale = AppLocale.read(context);
    if (device.deviceId == _localDeviceId) {
      return locale.get('device_online');
    }
    final diff = DateTime.now().difference(device.lastSeen);
    if (diff.inMinutes < 2) return locale.get('device_online');
    if (diff.inMinutes < 60) {
      return locale.tr('device_last_seen_minutes', {'minutes': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return locale.tr('device_last_seen_hours', {'hours': '${diff.inHours}'});
    }
    return locale.tr('device_last_seen_days', {'days': '${diff.inDays}'});
  }

  String _formatSince(BuildContext context, DateTime date) {
    final locale = AppLocale.read(context);
    final day = '${date.day}.${date.month}.${date.year}';
    return locale.tr('device_since', {'date': day});
  }

  void _showRenameDialog(DeviceRecord device) {
    final locale = AppLocale.read(context);
    final controller = TextEditingController(text: device.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('device_rename_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: locale.get('device_name_label'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != device.deviceName) {
                widget.service.renameDevice(device.deviceId, newName);
              }
              Navigator.of(ctx).pop();
              _refresh();
            },
            child: Text(locale.get('save')),
          ),
        ],
      ),
    );
  }

  void _showRevokeDialog(DeviceRecord device) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('device_revoke_title')),
        content: Text(locale.tr('device_revoke_confirm', {
          'name': device.deviceName,
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.service.revokeDevice(device.deviceId);
              _refresh();
            },
            child: Text(locale.get('device_revoke_button')),
          ),
        ],
      ),
    );
  }

  void _showKeyRotationDialog() {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error, size: 48),
        title: Text(locale.get('device_key_rotation_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locale.get('device_key_rotation_warning')),
            const SizedBox(height: 16),
            Text(locale.get('device_key_rotation_irreversible'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.error,
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _showKeyRotationConfirmDialog();
            },
            child: Text(locale.get('device_key_rotation_continue')),
          ),
        ],
      ),
    );
  }

  void _showKeyRotationConfirmDialog() {
    final locale = AppLocale.read(context);
    final controller = TextEditingController();
    final confirmWord = locale.get('device_key_rotation_confirm_word');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('device_key_rotation_confirm_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(locale.tr('device_key_rotation_type_confirm', {
                'word': confirmWord,
              })),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: confirmWord,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(locale.get('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: controller.text.trim().toUpperCase() == confirmWord.toUpperCase()
                  ? () {
                      Navigator.of(ctx).pop();
                      widget.service.rotateIdentityKeys();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(locale.get('device_key_rotation_started'))),
                      );
                    }
                  : null,
              child: Text(locale.get('device_key_rotation_execute')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('device_management_title'))),
      body: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 8),

            // Device list
            ..._devices.map((device) {
              final isThis = device.deviceId == _localDeviceId;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_platformIcon(device.platform), size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        device.deviceName,
                                        style: theme.textTheme.titleMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isThis) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          locale.get('device_this_device'),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatLastSeen(context, device),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isThis || DateTime.now().difference(device.lastSeen).inMinutes < 2
                                        ? Colors.green
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatSince(context, device.firstSeen),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'ID: ${device.deviceId.substring(0, 16)}...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _showRenameDialog(device),
                            icon: const Icon(Icons.edit, size: 16),
                            label: Text(locale.get('device_rename_button')),
                          ),
                          if (!isThis) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _showRevokeDialog(device),
                              icon: Icon(Icons.logout, size: 16,
                                  color: theme.colorScheme.error),
                              label: Text(
                                locale.get('device_revoke_button'),
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(locale.get('device_no_devices'),
                      style: theme.textTheme.bodyLarge),
                ),
              ),

            // Key Rotation section
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        locale.get('device_lost_stolen'),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _showKeyRotationDialog,
                    icon: Icon(Icons.vpn_key, color: theme.colorScheme.error),
                    label: Text(
                      locale.get('device_key_rotation_button'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    locale.get('device_key_rotation_hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
