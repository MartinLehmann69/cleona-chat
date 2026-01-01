// lib/ui/components/pending_security_dialogs.dart
//
// §7.1 LD-2 / §7.5: modal dialogs for the two "the daemon parked a security
// decision and is fully wired to receive an answer, but nothing ever asked
// the user" gaps — an incoming device-pairing request, and a Primary's
// request for a Device-Sig countersignature on an Emergency Key Rotation.
//
// Both are shown globally (via `navigatorKey`, see main.dart) so they surface
// regardless of which screen happens to be open — Settings → Devices is
// where the *persistent list* of everything still pending lives, but the
// live prompt cannot depend on the user already being on that screen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';

/// §7.1 LD-2: a device on the network is asking to be paired with this
/// (Primary) identity. Shows `deviceIdHex` in full, monospace, selectable
/// plain text — §7.1 step 2 requires the user to compare it against the
/// requesting device's own display before approving; a truncated or
/// otherwise non-literal rendering would defeat that check.
///
/// There is no reject action: declining is simply not calling
/// [ICleonaService.approvePairRequest] here. "Later" just closes the dialog —
/// the request stays queryable via [ICleonaService.getPendingPairRequests]
/// (surfaced as a list in Settings → Devices) until its display TTL elapses
/// or the requester retries.
Future<void> showIncomingPairRequestDialog({
  required BuildContext context,
  required ICleonaService service,
  required String deviceIdHex,
}) async {
  final locale = AppLocale.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.link, color: Theme.of(ctx).colorScheme.primary, size: 48),
      title: Text(locale.get('device_pending_pairing_incoming_title')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locale.get('device_pending_pairing_incoming_body')),
            const SizedBox(height: 16),
            Text(
              locale.get('device_pending_pairing_id_label'),
              style: Theme.of(ctx).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                deviceIdHex,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Theme.of(ctx).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locale.get('device_pending_pairing_verify_hint'),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              ],
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
          onPressed: () async {
            Navigator.of(ctx).pop();
            final ok = await service.approvePairRequest(deviceIdHex);
            messenger?.showSnackBar(SnackBar(content: Text(locale.get(
              ok
                  ? 'device_pending_pairing_approved_snack'
                  : 'device_pending_pairing_failed_snack',
            ))));
          },
          child: Text(locale.get('accept')),
        ),
      ],
    ),
  );
}

/// §7.5: the Primary is asking this Linked Device to countersign an
/// Emergency Key Rotation. MUST offer both accept and reject — a timeout
/// must never be read as consent, so the countdown shown here is purely
/// informational (disables the buttons at zero) and never fires an action
/// on its own; see `CleonaService._handleRotationApprovalRequest` for why.
Future<void> showRotationApprovalDialog({
  required BuildContext context,
  required ICleonaService service,
  required String rotationHashHex,
  required String requestingDeviceIdHex,
  required int expiresAtMs,
}) async {
  final locale = AppLocale.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  String requesterLabel = requestingDeviceIdHex;
  final known = service.devices
      .where((d) => d.deviceNodeIdHex == requestingDeviceIdHex)
      .toList();
  if (known.isNotEmpty) {
    requesterLabel = '${known.first.deviceName} (${requestingDeviceIdHex.substring(0, 12)}…)';
  } else if (requestingDeviceIdHex.length > 16) {
    requesterLabel = '${requestingDeviceIdHex.substring(0, 16)}…';
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RotationApprovalDialogContent(
      locale: locale,
      messenger: messenger,
      service: service,
      rotationHashHex: rotationHashHex,
      requesterLabel: requesterLabel,
      expiresAtMs: expiresAtMs,
    ),
  );
}

/// Owns the 1s countdown [Timer] for [showRotationApprovalDialog] — a plain
/// [StatefulBuilder] would re-create the timer on every tick (its `builder`
/// runs again on every `setState`), leaking one additional timer per second.
/// A real [State] creates it once in [initState] and cancels it once in
/// [dispose], which also fires on back-gesture / barrier dismissal, not only
/// on the explicit buttons below.
class _RotationApprovalDialogContent extends StatefulWidget {
  final AppLocale locale;
  final ScaffoldMessengerState? messenger;
  final ICleonaService service;
  final String rotationHashHex;
  final String requesterLabel;
  final int expiresAtMs;

  const _RotationApprovalDialogContent({
    required this.locale,
    required this.messenger,
    required this.service,
    required this.rotationHashHex,
    required this.requesterLabel,
    required this.expiresAtMs,
  });

  @override
  State<_RotationApprovalDialogContent> createState() =>
      _RotationApprovalDialogContentState();
}

class _RotationApprovalDialogContentState
    extends State<_RotationApprovalDialogContent> {
  Timer? _timer;
  late int _remainingMs =
      widget.expiresAtMs - DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = widget.expiresAtMs - DateTime.now().millisecondsSinceEpoch;
      if (left <= 0) t.cancel();
      if (mounted) setState(() => _remainingMs = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Cancels the timer and pops the dialog, then performs the caller's
  /// decision. The daemon call happens AFTER the pop so the dialog never
  /// waits on network round-trips.
  Future<void> _decide({required bool approve}) async {
    _timer?.cancel();
    Navigator.of(context).pop();
    final ok = approve
        ? await widget.service.approveRotation(widget.rotationHashHex)
        : await widget.service.rejectRotation(widget.rotationHashHex);
    widget.messenger?.showSnackBar(SnackBar(content: Text(widget.locale.get(
      ok
          ? (approve
              ? 'device_rotation_approval_approved_snack'
              : 'device_rotation_approval_rejected_snack')
          : 'device_rotation_approval_failed_snack',
    ))));
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final expired = _remainingMs <= 0;
    final totalSeconds = _remainingMs > 0 ? _remainingMs ~/ 1000 : 0;
    final mm = totalSeconds ~/ 60;
    final ss = totalSeconds % 60;
    final timeLabel = '$mm:${ss.toString().padLeft(2, '0')}';

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error, size: 48),
      title: Text(locale.get('device_rotation_approval_incoming_title')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locale.get('device_rotation_approval_incoming_body')),
            const SizedBox(height: 12),
            Text(
              locale.get('device_rotation_approval_requester_label'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(widget.requesterLabel,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 12),
            Text(
              expired
                  ? locale.get('device_rotation_approval_expired')
                  : locale.tr(
                      'device_rotation_approval_remaining', {'time': timeLabel}),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: expired
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                locale.get('device_rotation_approval_warning'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: expired
          ? [
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                child: Text(locale.get('close')),
              ),
            ]
          : [
              TextButton(
                onPressed: () => _decide(approve: false),
                child: Text(locale.get('reject')),
              ),
              FilledButton(
                onPressed: () => _decide(approve: true),
                child: Text(locale.get('accept')),
              ),
            ],
    );
  }
}
