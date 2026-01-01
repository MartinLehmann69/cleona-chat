import 'package:flutter/material.dart';

import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/ui/components/system_deposit_dialog.dart';

/// The opt-in popup after a crash (§16.7: "Crash reports only after an
/// opt-in popup with a preview of the exact publication").
///
/// The device asks the chosen holder about the crash fingerprint first; a
/// known crash shows the existing report and offers "+1" or "send my report
/// as a variant" — the user decides, never the device (a forged twin cannot
/// silence a real report). Returns null when nothing was sent.
Future<SystemSendResult?> showCrashReportDialog({
  required BuildContext context,
  required SystemChannelApi api,
  required CrashReport report,
}) =>
    showSystemDepositFlow(
      context: context,
      api: api,
      draft: SystemDraft.crash(report),
      titleKey: 'crash_dialog_title',
      introKey: 'sys_crash_intro',
    );
