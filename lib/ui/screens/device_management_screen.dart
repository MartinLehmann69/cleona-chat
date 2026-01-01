import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/main.dart' show CleonaAppState;

/// Device Management Screen (§26) — list, rename, revoke twin devices.
/// §7.1 LD-9/LD-10/LD-11: Cert-Status, Renewal, Kopplung.
class DeviceManagementScreen extends StatefulWidget {
  final ICleonaService service;
  const DeviceManagementScreen({super.key, required this.service});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  List<DeviceRecord> _devices = [];
  String _localDeviceId = '';

  /// §7.5: redraws the "time remaining" text on any pending rotation-approval
  /// card every second. Purely a display tick — [CleonaAppState] owns the
  /// actual pending-request state (see [_ticker]'s doc for why this screen
  /// does not also subscribe to the raw service callbacks).
  Timer? _ticker;

  /// The holder of the service's single `onStateChanged` slot before this
  /// screen opened — on the desktop the app's `notifyListeners`
  /// (`main.dart`). Chained while the screen is open and given back in
  /// [dispose]; without that the home screen stops redrawing after one
  /// visit here (S398, lab B-4b, finding B-1). Same pattern as
  /// `connection_sheet.dart`.
  void Function()? _previousOnStateChanged;

  @override
  void initState() {
    super.initState();
    _refresh();
    _previousOnStateChanged = widget.service.onStateChanged;
    widget.service.onStateChanged = () {
      _previousOnStateChanged?.call();
      if (mounted) _refresh();
    };
    // §7.1 LD-2 / §7.5: this screen reads the pending-pairing /
    // pending-rotation-approval lists from [CleonaAppState] (via
    // `context.watch` in build()) rather than subscribing to
    // `widget.service.onDevicePairRequest` / `onRotationApprovalRequest`
    // directly — those are single-slot callback fields already claimed by
    // [CleonaAppState] in main.dart (so the live global dialog keeps working
    // whether or not this screen happens to be open); a second assignment
    // here would silently steal the slot back while this screen is mounted.
    // A refresh on open still catches up in case this screen is opened long
    // after the last event fired, with no live event to trigger a redraw.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CleonaAppState>().refreshPendingSecurityRequests();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.service.onStateChanged = _previousOnStateChanged;
    _ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _devices = widget.service.devices;
      _localDeviceId = widget.service.localDeviceId;
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
          content: SingleChildScrollView(
           child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §4.5.4 (E-A12, E-A3): after the rotation the 24 words alone
              // restore superseded keys — the recovery bundle is required;
              // standing invitations are revoked.
              Text(locale.get('device_key_rotation_bundle_required')),
              const SizedBox(height: 12),
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

  /// B-4b (§14.6.1, D-39): "Add another device" — the 24-hour enrolment
  /// window, and its end while it is open. Behind the E7 lock the button
  /// says "not available yet" and does nothing. There is no primary
  /// device (§14.4): the V3 status section (Primary/Linked, delegation
  /// certificate) is gone.
  Widget _buildEnrolmentSection(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final view = widget.service.enrolmentView;
    final until = view.windowUntil;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_link, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(locale.get('enrol_add_device'),
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            locale.get(view.available
                ? 'enrol_add_device_subtitle'
                : 'enrol_not_available'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (until == null)
            OutlinedButton.icon(
              key: const Key('enrol_window_open'),
              onPressed: view.available
                  ? () async {
                      final ok = await widget.service.enrolmentWindowOpen();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(locale.get(ok
                              ? 'enrol_window_opened'
                              : 'enrol_not_available'))));
                      setState(() {});
                    }
                  : null,
              icon: const Icon(Icons.add_link, size: 16),
              label: Text(locale.get('enrol_add_device')),
            )
          else ...[
            Text(
              locale.tr('enrol_window_open_until', {
                'time': '${until.day}.${until.month}.${until.year} '
                    '${until.hour.toString().padLeft(2, '0')}:'
                    '${until.minute.toString().padLeft(2, '0')}'
              }),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('enrol_window_cancel'),
              onPressed: () async {
                await widget.service.enrolmentWindowCancel();
                if (context.mounted) setState(() {});
              },
              icon: const Icon(Icons.link_off, size: 16),
              label: Text(locale.get('enrol_window_cancel')),
            ),
          ],
        ],
      ),
    );
  }

  /// §7.5: persistent list of rotation-approval requests still waiting for a
  /// decision — the catch-up counterpart to the live dialog in
  /// [showRotationApprovalDialog].
  Widget _buildPendingRotationSection(BuildContext context, CleonaAppState appState) {
    final pending = appState.pendingRotationApprovals;
    if (pending.isEmpty) return const SizedBox.shrink();
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locale.get('device_rotation_approval_section_title'),
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final entry in pending)
            Builder(builder: (context) {
              final hashHex = entry['rotationHashHex'] as String;
              final requesterHex = entry['requestingDeviceIdHex'] as String;
              final expiresAtMs = entry['expiresAtMs'] as int;
              final remainingMs = expiresAtMs - nowMs;
              final expired = remainingMs <= 0;
              final totalSeconds = remainingMs > 0 ? remainingMs ~/ 1000 : 0;
              final timeLabel = '${totalSeconds ~/ 60}:'
                  '${(totalSeconds % 60).toString().padLeft(2, '0')}';
              final requesterName = _devices
                  .where((d) => d.deviceNodeIdHex == requesterHex)
                  .map((d) => d.deviceName)
                  .firstOrNull;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(locale.get('device_rotation_approval_requester_label'),
                          style: theme.textTheme.labelSmall),
                      Text(
                        requesterName != null
                            ? '$requesterName (${requesterHex.substring(0, 12)}…)'
                            : requesterHex,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expired
                            ? locale.get('device_rotation_approval_expired')
                            : locale.tr('device_rotation_approval_remaining',
                                {'time': timeLabel}),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: expired
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (!expired) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final ok = await widget.service.rejectRotation(hashHex);
                                if (!context.mounted) return;
                                await context.read<CleonaAppState>().refreshPendingSecurityRequests();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(locale.get(ok
                                      ? 'device_rotation_approval_rejected_snack'
                                      : 'device_rotation_approval_failed_snack')),
                                ));
                              },
                              child: Text(locale.get('reject')),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () async {
                                final ok = await widget.service.approveRotation(hashHex);
                                if (!context.mounted) return;
                                await context.read<CleonaAppState>().refreshPendingSecurityRequests();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(locale.get(ok
                                      ? 'device_rotation_approval_approved_snack'
                                      : 'device_rotation_approval_failed_snack')),
                                ));
                              },
                              child: Text(locale.get('accept')),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// §24.4.3 — transitional state of running and just-finished lockouts.
  ///
  /// The cards stand BEFORE the device list and not in it: the locked-out
  /// device has already disappeared from `devices` — exactly why
  /// `LockoutTransition` records its name itself
  /// (cleona_service_lockout.dart:80-82). A row in the list would have
  /// no anchor any more.
  ///
  /// It is read on every `build` directly from the service, not
  /// cached in [_refresh]: [_ticker] (1 s) and `onStateChanged`
  /// trigger the rebuild anyway, and a second copy in the state could
  /// diverge from [_devices].
  Widget _buildLockoutSection(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final lockouts = widget.service.deviceLockouts;
    if (lockouts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...lockouts.map((l) {
          final name = (l['deviceName'] as String?) ?? '';
          final total = (l['total'] as int?) ?? 0;
          final open = (l['stillOpen'] as int?) ?? 0;
          final notSent = (l['notSent'] as int?) ?? 0;
          final closed = (l['closed'] as bool?) ?? false;
          final startedAtMs = (l['startedAtMs'] as int?) ?? 0;
          final deadlineMs = (l['deadlineMs'] as int?) ?? 0;
          // §14.4: the deadline stands as a point in time in the record, not as a number
          // of days. Computing it back here keeps the display on the
          // SAME quantity with which the daemon closes; a hard-coded
          // 14 would silently diverge as soon as
          // `_lockoutDeadlineDays` changes.
          final days = deadlineMs > startedAtMs
              ? ((deadlineMs - startedAtMs) / 86400000).round()
              : 0;
          final String status;
          if (!closed) {
            status = locale.tr('device_lockout_transition',
                {'open': '$open', 'total': '$total'});
          } else if (l['closeReason'] == 'allInformed') {
            status = locale
                .tr('device_lockout_closed_informed', {'total': '$total'});
          } else {
            status = locale.tr('device_lockout_closed_deadline',
                {'days': '$days', 'open': '$open'});
          }
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(closed ? Icons.lock : Icons.lock_clock,
                          size: 24, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(status, style: theme.textTheme.bodyMedium),
                  if (!closed && total > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (total - open) / total,
                    ),
                  ],
                  // Shown separately, because "open" and "not sent"
                  // are not the same — the data side keeps them
                  // explicitly separate, so that "3 of 47 open" is not read as
                  // "3 of 47 failed"
                  // (cleona_service_lockout.dart:94-98).
                  if (!closed && notSent > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      locale
                          .tr('device_lockout_not_sent', {'count': '$notSent'}),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // §24.4.3: without this sentence the case reads like silent
                  // loss — whoever then writes to the old address waits
                  // for a receipt that never comes.
                  Text(
                    locale.get('device_lockout_old_address_hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const Divider(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    final appState = context.watch<CleonaAppState>();

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('device_management_title'))),
      // Working rule #6 (Android edge-to-edge): `top: false`, because the
      // AppBar at the top is already safe; at the bottom the gesture/nav bar
      // otherwise eats the last list entry.
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            const SizedBox(height: 8),

            _buildPendingRotationSection(context, appState),
            _buildLockoutSection(context),
            if (appState.pendingRotationApprovals.isNotEmpty)
              const Divider(height: 24),

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

            // B-4b (§14.6.1): add another device over the 24 words
            const Divider(height: 32),
            _buildEnrolmentSection(context),

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
