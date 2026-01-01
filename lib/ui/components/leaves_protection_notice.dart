/// The notice "content leaves the application's protection" (v4_2 §21.4.2
/// "Content the user lets out", D-49 "one notice per function where content
/// leaves"; S432).
///
/// Five functions let content leave the encrypted store on the user's own
/// action: the application's own screenshot (§23.10), saving an attachment
/// to the device, sharing it to another application, the media archive on
/// the share (§21.6) and mirroring into the Android system calendar
/// (§18.2). What has left is outside the application's reach — it is not
/// deleted with the message and does not expire with it (§21.5.3).
///
/// §21.4.2: "At each of these functions the application says so **once** —
/// when the user first turns the function on or first uses it, never at
/// every use." The texts existed in 34 languages since S403
/// (`notice_leaves_protection_*`) without a caller; this is the caller.
///
/// ── ONCE PER DEVICE ───────────────────────────────────────────────────────
///
/// Which notices were shown lies in the GUI's device-wide row of the device
/// database (`kGuiFieldLeavesNoticeShown`, `gui_device_setting.dart`), the
/// same for every identity — the functions are the device's, not an
/// identity's. Where no service can store it yet (first setup), the notice
/// is shown again next time rather than never.
///
/// The notice informs, it does not ask: after "got it" the function runs as
/// the user started it.
library;

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/gui_device_setting.dart';
import 'package:cleona/main.dart' show CleonaAppState;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The five functions where content leaves the application's protection.
/// The name is the suffix of the i18n key `notice_leaves_protection_<name>`.
enum LeavesProtectionKind { screenshot, save, share, archive, calendar }

class LeavesProtectionNotice {
  LeavesProtectionNotice._();

  /// The i18n key of [kind]'s text.
  static String textKey(LeavesProtectionKind kind) =>
      'notice_leaves_protection_${kind.name}';

  /// Whether [kind]'s notice was already shown, read from [settings] (the
  /// service's `guiDeviceSettings`).
  static bool wasShown(Map<String, dynamic> settings, LeavesProtectionKind kind) {
    final shown = settings[kGuiFieldLeavesNoticeShown];
    return shown is List && shown.contains(kind.name);
  }

  /// Shows [kind]'s notice if it was not shown on this device before, waits
  /// until the user closed it, and records it. Returns immediately when it
  /// was shown already.
  static Future<void> showOnce(
      BuildContext context, LeavesProtectionKind kind) async {
    final service = context.read<CleonaAppState>().service;
    final settings = service?.guiDeviceSettings ?? const <String, dynamic>{};
    if (wasShown(settings, kind)) return;

    final locale = AppLocale.read(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: ValueKey('leaves-protection-notice-${kind.name}'),
        icon: const Icon(Icons.lock_open_outlined),
        content: Text(locale.get(textKey(kind))),
        actions: [
          FilledButton(
            key: const ValueKey('leaves-protection-notice-got-it'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('got_it')),
          ),
        ],
      ),
    );

    if (service == null) return;
    final current = service.guiDeviceSettings[kGuiFieldLeavesNoticeShown];
    final next = <String>{
      if (current is List) ...current.whereType<String>(),
      kind.name,
    }.toList()
      ..sort();
    await service.setGuiDeviceSetting(kGuiFieldLeavesNoticeShown, next);
  }
}
