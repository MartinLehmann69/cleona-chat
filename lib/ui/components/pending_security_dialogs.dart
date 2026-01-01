// lib/ui/components/pending_security_dialogs.dart
//
// §7.5: the modal dialog for "the daemon parked a security decision and is
// fully wired to receive an answer, but nothing ever asked the user" — a
// request for a Device-Sig countersignature on an Emergency Key Rotation.
// (The V3 device-pairing dialog is gone with B-4b: an enrolment request is
// decided in the Requests tab, §14.6.1.)
//
// Both are shown globally (via `navigatorKey`, see main.dart) so they surface
// regardless of which screen happens to be open — Settings → Devices is
// where the *persistent list* of everything still pending lives, but the
// live prompt cannot depend on the user already being on that screen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';

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
  int? expiresAtMs,
  Listenable? pendingChanged,
  bool Function()? stillPending,
}) async {
  final locale = AppLocale.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  String requesterLabel = requestingDeviceIdHex;
  // S422: the requesting device is named by its DeviceID (Type 12 on the
  // own line); a record keyed by its node id is matched as before.
  final known = service.devices
      .where((d) =>
          d.deviceId == requestingDeviceIdHex ||
          d.deviceNodeIdHex == requestingDeviceIdHex)
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
      pendingChanged: pendingChanged,
      stillPending: stillPending,
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

  /// `null` (S422): the request waits without a clock — no countdown.
  final int? expiresAtMs;

  const _RotationApprovalDialogContent({
    required this.locale,
    required this.messenger,
    required this.service,
    required this.rotationHashHex,
    required this.requesterLabel,
    required this.expiresAtMs,
    this.pendingChanged,
    this.stillPending,
  });

  /// §14.8 (S422): fires when the list of open requests changed; with
  /// [stillPending] `false` the request was withdrawn by the device that
  /// asked, and the dialog closes without an answer.
  final Listenable? pendingChanged;
  final bool Function()? stillPending;

  @override
  State<_RotationApprovalDialogContent> createState() =>
      _RotationApprovalDialogContentState();
}

class _RotationApprovalDialogContentState
    extends State<_RotationApprovalDialogContent> {
  Timer? _timer;
  late int _remainingMs = widget.expiresAtMs == null
      ? 1
      : widget.expiresAtMs! - DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    widget.pendingChanged?.addListener(_withdrawnCheck);
    final until = widget.expiresAtMs;
    if (until == null) return; // S422: no clock, no countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = until - DateTime.now().millisecondsSinceEpoch;
      if (left <= 0) t.cancel();
      if (mounted) setState(() => _remainingMs = left);
    });
  }

  @override
  void dispose() {
    widget.pendingChanged?.removeListener(_withdrawnCheck);
    _timer?.cancel();
    super.dispose();
  }

  bool _closed = false;

  /// §14.8: a withdrawn request is no longer shown — the dialog closes.
  void _withdrawnCheck() {
    final still = widget.stillPending;
    if (_closed || !mounted || still == null || still()) return;
    _closed = true;
    _timer?.cancel();
    Navigator.of(context).pop();
  }

  /// Cancels the timer and pops the dialog, then performs the caller's
  /// decision. The daemon call happens AFTER the pop so the dialog never
  /// waits on network round-trips.
  Future<void> _decide({required bool approve}) async {
    if (_closed) return;
    _closed = true;
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
            if (widget.expiresAtMs != null) ...[
              const SizedBox(height: 12),
              Text(
                expired
                    ? locale.get('device_rotation_approval_expired')
                    : locale.tr('device_rotation_approval_remaining',
                        {'time': timeLabel}),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: expired
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
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
