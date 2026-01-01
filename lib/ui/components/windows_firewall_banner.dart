// v4_2 §22.x "Windows Desktop" (owner 14.10.2026 A): "At every start the
// application checks the rule; when it is missing or a blocking rule stands
// — the setup ran without consent, or the Windows prompt was declined — it
// says so and offers 'Allow in firewall', which sets the same rule after one
// consent. Inbound reachability is not a condition for one's own delivery
// (§22.5.2), it is the contribution to others and the prerequisite for
// incoming calls. The UI text states the rule exactly that way."
//
// The daemon checks (it knows its own program path, and reading the rules
// needs no rights); this banner asks it once when the home screen is built,
// runs the elevated helper of the bundle on the click and asks the daemon to
// check again. No timer, no polling.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/windows_firewall.dart';

class WindowsFirewallBanner extends StatefulWidget {
  final IpcClient client;
  const WindowsFirewallBanner({super.key, required this.client});

  @override
  State<WindowsFirewallBanner> createState() => _WindowsFirewallBannerState();
}

class _WindowsFirewallBannerState extends State<WindowsFirewallBanner> {
  WindowsFirewallState _state = WindowsFirewallState.unknown;
  String? _exe;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(recheck: false);
  }

  Future<void> _load({required bool recheck}) async {
    final r = await widget.client.windowsFirewall(recheck: recheck);
    if (!mounted) return;
    final name = r['state'] as String?;
    setState(() {
      _exe = r['exe'] as String?;
      _state = WindowsFirewallState.values
              .where((s) => s.name == name)
              .firstOrNull ??
          WindowsFirewallState.unknown;
    });
  }

  Future<void> _allow(AppLocale locale) async {
    final exe = _exe;
    if (exe == null) return;
    setState(() => _busy = true);
    final helper =
        '${AppPaths.bundleDir}${Platform.pathSeparator}${WindowsFirewall.helperFileName}';
    final code = File(helper).existsSync()
        ? await WindowsFirewall.allow(helper: helper, exe: exe)
        : -1;
    await _load(recheck: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code != 0 || _state != WindowsFirewallState.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locale.get('win_fw_not_set'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state != WindowsFirewallState.missing &&
        _state != WindowsFirewallState.blocked) {
      return const SizedBox.shrink();
    }
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    return Material(
      key: const Key('windows_firewall_banner'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locale.get('win_fw_blocked'),
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('windows_firewall_allow'),
                onPressed: _busy ? null : () => _allow(locale),
                child: Text(locale.get('win_fw_allow')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
