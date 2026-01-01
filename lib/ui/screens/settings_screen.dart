// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/crypto/keyring_service.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/recovery/legacy_guardian_state.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/link/data_port.dart';
import 'package:cleona/ui/screens/donation_screen.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/service/app_version.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_network.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/service/bulk_cache_setting.dart'
    show bulkCacheDefaultMb, kBulkCacheTiersMb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cleona/ui/screens/performance_screen.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/components/form_group.dart';
import 'package:cleona/ui/components/section_card.dart';
import 'package:cleona/ui/components/connection_sheet.dart';

class SettingsScreen extends StatelessWidget {
  final ICleonaService service;
  const SettingsScreen({super.key, required this.service});

  SectionRow _buildVersionRow(BuildContext context, CleonaAppState appState,
      AppLocale locale) {
    final manifest = appState.availableUpdateManifest;
    if (manifest != null) {
      return SectionRow(
        label: locale.get('version_label'),
        value: '${CleonaService.kCurrentAppVersion}  →  v${manifest.version}',
        trailing: Icon(Icons.system_update,
            size: 20,
            color: Theme.of(context).colorScheme.primary),
        onTap: () => appState.undismissUpdateBanner(),
      );
    }
    return SectionRow(
      label: locale.get('version_label'),
      // S368: here stood `(Architecture v3.0)` — as a LITERAL. The only
      // "About" line of the application thus told the user it follows an
      // architecture that this line has no longer followed since S345. The
      // version to the left of it always came correctly from the one source;
      // the parenthetical addition was a literal beside it.
      //
      // It is therefore NOT rewritten to today's correct number,
      // but DERIVED (`kAppLine`). A new literal would be the same
      // error once more, only with a number that happens to be right today.
      value: '${CleonaService.kCurrentAppVersion} (Architecture v$kAppLine)',
    );
  }

  String _buildIpAddressText() {
    final ips = <String>[];
    for (final ip in service.localIps) {
      if (ip == '127.0.0.1' || ip == '::1') continue;
      ips.add(ip);
    }
    final pub = service.publicIp;
    if (pub != null && pub.isNotEmpty && !ips.contains(pub)) {
      ips.add('$pub (WAN)');
    }
    return ips.isEmpty ? '—' : ips.join('\n');
  }

  void _showPortDialog(BuildContext context) {
    final locale = AppLocale.read(context);
    final controller = TextEditingController(text: '${service.port}');
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('port_label')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '1024–65535',
              errorText: error,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final newPort = int.tryParse(controller.text);
                if (newPort == null || newPort < 1024 || newPort > 65535) {
                  setDialogState(() => error = '1024–65535');
                  return;
                }
                // §4.5.2 invariant: the data port must never equal one of
                // the fixed LAN ports. The daemon rejects it too, but the IPC
                // error text never reaches the user (setPort returns a plain
                // bool), so the reason has to be given here.
                //
                // S376: both values, via the one place of definition. The
                // text now carries the port as a placeholder — it stood in
                // all 34 languages as the literal "41338" and would have
                // named the wrong number for 41340.
                if (DataPort.isReservedLanPort(newPort)) {
                  setDialogState(() => error = locale
                      .tr('port_reserved_discovery', {'port': '$newPort'}));
                  return;
                }
                // A browser-blocked port does not break the node — it breaks
                // its INVITATION LINKS, and only at the recipient. The link
                // is an http:// URL the recipient opens in a browser (they do
                // not have Cleona yet); a blocked port makes the browser
                // refuse locally, so no request ever reaches this node and no
                // error is ever logged here. `generateInviteLinkUrl` already
                // withholds such a link, but silently — without this message
                // the user would simply find the invitation block gone and
                // have no way to connect it to the port they just typed.
                // That is the whole reason the check is repeated here: the
                // other two paths reject correctly but cannot explain.
                if (IdentityManager.isBrowserBlockedPort(newPort)) {
                  setDialogState(() => error = locale
                      .tr('port_browser_blocked', {'port': '$newPort'}));
                  return;
                }
                if (newPort == service.port) {
                  Navigator.pop(ctx);
                  return;
                }
                final ok = await service.setPort(newPort);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(locale.tr(
                          'port_unavailable', {'port': '$newPort'}))),
                    );
                  }
                }
              },
              child: Text(locale.get('save')),
            ),
          ],
        ),
      ),
    );
  }

  /// S363, point 1 (option D): the 24 words behind the
  /// device-code lock.
  ///
  /// Why it waits asynchronously here although `loadSeedPhrase()` is synchronous:
  /// the lock asks the user, and questions are asynchronous. The
  /// system dialog comes from `KeyguardManager` (Android); on all other
  /// platforms [IdentityManager.loadSeedPhraseGated] returns the same
  /// value as before, only in a `Future`.
  ///
  /// The second reason for this version is the DISPLAY: there are three
  /// outcomes that a user cannot place without explanation —
  /// cancel, removed screen lock, and "nothing lies on this
  /// device" (the normal case after a reinstallation, because the
  /// keyring is app-bound). Before, each of them showed the same
  /// meaningless line.
  Future<void> _showSeedPhrase(BuildContext context) async {
    final locale = AppLocale.read(context);
    final identityMgr = IdentityManager();
    final access = await identityMgr.loadSeedPhraseGated(
      title: locale.get('seed_phrase_gate_title'),
      description: locale.get('seed_phrase_gate_description'),
    );
    if (!context.mounted) return;

    final words = access.words;
    if (words == null) {
      final String message;
      switch (access.outcome) {
        case GateOutcome.cancelled:
          message = locale.get('seed_phrase_gate_cancelled');
          break;
        case GateOutcome.invalidated:
          message = locale.get('seed_phrase_gate_invalidated');
          break;
        case GateOutcome.absent:
          // On a device with an app-bound keyring,
          // "nothing there" is almost always the reinstallation; otherwise it is the
          // old, terse sentence.
          // NOT `hasDeviceGate`: the statement of this sentence is "the
          // keyring falls with the app installation", and that
          // applies on BOTH mobile platforms — the device-code lock
          // exists only on Android. Two statements, two queries.
          message = access.gated || identityMgr.hasAppBoundKeyring
              ? locale.get('seed_phrase_absent_device')
              : locale.get('no_recovery_phrase');
          break;
        default:
          message = locale.get('no_recovery_phrase');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _SeedPhraseDialog(words: words),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.read(context);

    return AppBarScaffold(
      title: locale.get('settings'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      // Working rule #6 / Android edge-to-edge: `AppBarScaffold` sets
      // `SafeArea(bottom: false)` — the header is thus safe at the top, the
      // body at the bottom is NOT. Without this wrapper the gesture/
      // navigation bar eats the last row of the list.
      body: SafeArea(
        top: false,
        child: ListView(
        children: [
          const SizedBox(height: 8),

          FormGroup(
            title: locale.get('section_network'),
            children: [
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text(locale.get('node_id_label')),
                // Problem 1 (S119): Node-ID natively selectable (long-press).
                subtitle: SelectableText(
                  service.nodeIdHex,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings_ethernet),
                title: _titleWithHelp(context, 'port_label', 'port_help'),
                subtitle: Text('${service.port}'),
                trailing: const Icon(Icons.edit),
                onTap: () => _showPortDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: Text(locale.get('connected_peers')),
                // §22.7.3/§24.4.1: the partner counts carry a separate label
                // PER DIRECTION. A single number left open
                // whether it means one's own delivery or the contribution for
                // others — two different statements (§25.4).
                // S405 A-2: no subtitle where the delivery layer has no
                // such number (mycelium) — a 0 there would be a claim.
                subtitle: service.syncPartnersOutbound == null ||
                        service.syncPartnersInbound == null
                    ? null
                    : Text(
                        '${locale.get('stats_sync_partners_outbound')}: '
                        '${service.syncPartnersOutbound} · '
                        '${locale.get('stats_sync_partners_inbound')}: '
                        '${service.syncPartnersInbound}',
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showConnectionSheet(context, service),
              ),
              // The tile "stored fragments" stood here (S407-UPDATEFRAGMENTE).
              // Its number was the count of entries in the local
              // `MailboxStore` — in 4.2 only copies of the update manifest —,
              // not a count of anything the user could act on; update
              // fragments are no longer stored at all.
              // §24.4.2 — data-saving mode. It stands in the FIRST group
              // of the screen, not in a submenu: "a visible
              // state, not a setting buried in a submenu".
              _DataSaverTile(
                service: service,
                // §31.3 tier 4: "Wi-Fi, Ethernet, or VPN take precedence
                // over cellular, for all traffic." So metered means
                // cellular ONLY, not "also cellular".
                //
                // The connection type comes from `CleonaAppState`, which keeps it
                // anyway (main.dart:609, fed from
                // `Connectivity().onConnectivityChanged`). A second
                // subscription would be a second platform channel for
                // the same information — working rule #5.
                //
                // NOT via `ICleonaService`: the Linux/Windows daemon
                // is a pure `dart compile exe` binary without a
                // Flutter plugin registrant and cannot call `connectivity_plus`.
                // The suggestion is a matter of the UI
                // anyway — §24.4.2 only places the condition on ACTIVATING,
                // and that runs via the service.
                metered: appState.connectivityResults
                        .contains(ConnectivityResult.mobile) &&
                    !appState.connectivityResults
                        .contains(ConnectivityResult.wifi) &&
                    !appState.connectivityResults
                        .contains(ConnectivityResult.ethernet) &&
                    !appState.connectivityResults
                        .contains(ConnectivityResult.vpn),
              ),
              // §12.7 — the three network switches, together (S398-W4).
              // "Fewer empty cover packets" directly below the saving mode,
              // because both spend the same good.
              _LanShapingTile(service: service),
              // S388 — source 4 (§11.9): the only traffic to foreign
              // relays, therefore switchable and with its consequence below.
              _ExternalRecordsTile(service: service),
              // §12.7 "router mapping (§7.3)" — until S398 without a tile.
              _PortMappingTile(service: service),
              // §21.3.3 item 3 — what this device holds for others of
              // lane 3; a device value beside the network switches.
              _BulkCacheTile(service: service),
            ],
          ),

          FormGroup(
            title: locale.get('section_appearance'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: Text(locale.get('design_label')),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest)),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {appState.themeMode},
                  onSelectionChanged: (set) => appState.setThemeMode(set.first),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('master_mute_title'),
            dividers: false,
            children: [
              SwitchListTile(
                key: const Key('master_mute_switch'),
                secondary: const Icon(Icons.notifications_off_outlined),
                title: Text(locale.get('master_mute_title')),
                subtitle: Text(locale.get('master_mute_subtitle')),
                value: service.masterMute,
                // The client mirror calls onStateChanged on success; the
                // screen watches CleonaAppState and rebuilds from it.
                onChanged: (v) => unawaited(service.setMasterMute(v)),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_backup'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: _titleWithHelp(context, 'show_recovery_phrase', 'show_recovery_phrase_help'),
                subtitle: Text(locale.get('recovery_phrase_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_showSeedPhrase(context)),
              ),
              // §13.8 requires that the limit of recovery is communicated
              // "actively and unambiguously". It therefore stands
              // NEXT TO the phrase, not in a separate group:
              // until S361 the group was called "Social Recovery" and offered a
              // set-up path that no longer exists (gap G-8).
              _SocialRecoveryLimitTile(service: service),
            ],
          ),

          FormGroup(
            title: locale.get('section_performance'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(locale.get('performance_title')),
                subtitle: Text(locale.get('performance_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PerformanceScreen(service: service)),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_security'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(locale.get('security_hardening_title')),
                subtitle: Text(locale.get('security_hardening_subtitle')),
                trailing: const Icon(Icons.verified, color: Colors.green),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_donate'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: Text(locale.get('donate_title')),
                subtitle: Text(locale.get('donate_banner_text')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DonationScreen()),
                ),
              ),
            ],
          ),

          SectionCard(
            title: locale.get('section_info'),
            children: [
              _buildVersionRow(context, appState, locale),
              // S403 (owner decision 03.10.2026): the license texts of the
              // bundled third-party native libraries are registered with
              // Flutter's LicenseRegistry at app start (lib/main.dart); this
              // entry is the one door to Flutter's license page, which shows
              // them next to the Flutter/Dart package licenses. No own
              // screen — showLicensePage brings its own scaffold.
              SectionRow(
                label: locale.get('licenses_label'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Cleona Chat',
                  applicationVersion: CleonaService.kCurrentAppVersion,
                ),
              ),
              SectionRow(
                label: locale.get('encryption_label'),
                value: 'X25519 + ML-KEM-768\nEd25519 + ML-DSA-65',
              ),
              SectionRow(
                label: locale.get('network_tag_label'),
                value: activeNetworkChannel.name,
              ),
              SectionRow(
                label: locale.get('ip_addresses_label'),
                value: _buildIpAddressText(),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }

}

/// The limit of recovery — instead of a path that does not carry.
///
/// WHAT STOOD HERE BEFORE. `_GuardianSetupTile` offered "Set up social
/// recovery", let the user choose five contacts and called
/// `service.setupGuardians(...)`. Since the CUT the call could only
/// return `false` (`cleona_service.dart` `setupGuardians`) — the user
/// got "Guardian setup failed" after five selection clicks and
/// no explanation. And whoever had set up guardians BEFORE the CUT saw
/// the same set-up tile, because `isGuardianSetUp` hard-returned `false`:
/// the UI claimed "no backup" about a backup whose
/// state it did not know (gap G-8).
///
/// WHAT IT SAYS NOW. v4_1 §13.8 "Limits of recovery" is unambiguous:
/// "V4.1 has no social-recovery procedure. […] No set of other people can
/// restore an identity — in no number, in no combination, under no
/// threshold. […] there is no third route, and none is planned." The same
/// paragraph obliges to the notice: "this limit must be communicated to
/// the user actively and unambiguously during onboarding and at the seed
/// display." The tile is this notice; it is deliberately not
/// tappable, because there is nothing to do.
///
/// THREE STATES, NOT TWO. Additionally it is measured whether legacy stores
/// still lie on THIS device
/// (`lib/core/recovery/legacy_guardian_state.dart:36-48`). `present`
/// warns, `unknown` says "cannot be determined", `none` stays silent. The
/// expensive direction — presenting the user a "you have nothing" where the
/// state is open — thus no longer occurs.
/// The rescue bundle in the network (§13.3.4, B-1): "The bundle state
/// belongs in the UI: `Backup valid until <date>` or `Backup expires in N
/// days`. An expired bundle must not lapse silently." Three states: none in
/// the network (error colour), expiring within two days (error colour — it
/// is renewed only when the app meets the network), valid until a date.
class RecoveryBundleTile extends StatelessWidget {
  final ICleonaService service;
  const RecoveryBundleTile({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final scheme = Theme.of(context).colorScheme;
    final until = service.recoveryBundleValidUntil;
    final String text;
    var warn = true;
    if (until == null || !until.isAfter(DateTime.now())) {
      text = locale.get('recovery_bundle_none');
    } else {
      final left = until.difference(DateTime.now());
      if (left < const Duration(days: 2)) {
        text = locale
            .get('recovery_bundle_expires_days')
            .replaceAll('{days}', '${left.inHours ~/ 24 + 1}');
      } else {
        final d = until.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        text = locale
            .get('recovery_bundle_valid_until')
            .replaceAll('{date}', '${d.year}-${two(d.month)}-${two(d.day)}');
        warn = false;
      }
    }
    return ListTile(
      leading: Icon(Icons.cloud_done_outlined,
          color: warn ? scheme.error : scheme.onSurfaceVariant),
      title: Text(locale.get('recovery_bundle_title')),
      subtitle: Text(text,
          style: warn
              ? TextStyle(color: scheme.error, fontWeight: FontWeight.w600)
              : null),
    );
  }
}

class _SocialRecoveryLimitTile extends StatelessWidget {
  final ICleonaService service;
  const _SocialRecoveryLimitTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final scheme = Theme.of(context).colorScheme;
    // `profileDir` is available in both process kinds: in `CleonaService`
    // from the `ServiceContext`, in the `IpcClient` from the daemon's
    // snapshot (`service_interface.dart:106-114`). Daemon and GUI run
    // on the same machine (Unix socket or 127.0.0.1), so the directory
    // is readable. Where not, the measurement reports `unknown` — and exactly
    // that is then shown.
    final deposit = LegacyGuardianDeposit.probe(service.profileDir);

    final notes = <String>[];
    if (deposit.ownGuardians == LegacyGuardianTrace.present) {
      notes.add(locale.get('social_recovery_legacy_found'));
    } else if (deposit.ownGuardians == LegacyGuardianTrace.unknown) {
      notes.add(locale.get('social_recovery_legacy_unknown'));
    }
    if (deposit.heldShares == LegacyGuardianTrace.present) {
      notes.add(locale.get('social_recovery_legacy_shares'));
    }

    return ListTile(
      leading: Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
      title: Text(locale.get('social_recovery_gone_title')),
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(locale.get('social_recovery_gone_body')),
          for (final note in notes) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeedPhraseDialog extends StatelessWidget {
  final List<String> words;
  const _SeedPhraseDialog({required this.words});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    return AlertDialog(
      title: Text(locale.get('recovery_phrase_title')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locale.get('seed_phrase_warning'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        // Second of the two places required by v4_1 §13.8
                        // ("during onboarding and at the seed
                        // display"). The first is the initial display in
                        // `setup_screen.dart`.
                        Text(
                          locale.get('social_recovery_gone_body'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        // S363, measurement question 2: THE AVAILABILITY PRICE
                        // BELONGS BEFORE THE DECISION. The lock from
                        // point 1 makes the copy in the device fragile:
                        // a removed or changed screen lock
                        // destroys the auth-bound key and with
                        // it the 24 words. Until now this was only said
                        // afterwards (`seed_phrase_gate_invalidated`) — i.e.
                        // exactly when the user can no longer
                        // decide anything. Only on a build WITH the lock;
                        // on the desktop the sentence would be wrong.
                        if (IdentityManager().hasDeviceGate) ...[
                          const SizedBox(height: 8),
                          Text(
                            locale.get('seed_phrase_device_copy_note'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(words.length, (i) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${i + 1}. ${words[i]}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(locale.get('copy')),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: words.join(' ')));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(locale.get('copied_to_clipboard'))),
            );
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.print, size: 16),
          label: Text(locale.get('print')),
          onPressed: () async {
            final doc = pw.Document();
            doc.addPage(pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context ctx) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Cleona Recovery Phrase', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('Keep this safe!', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 20),
                  pw.Wrap(spacing: 16, runSpacing: 8, children: List.generate(words.length, (i) => pw.Container(
                    width: 120, padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                    child: pw.Text('${i + 1}. ${words[i]}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ))),
                ],
              ),
            ));
            await Printing.layoutPdf(onLayout: (format) => doc.save());
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(locale.get('close')),
        ),
      ],
    );
  }
}

/// Archive-Einstellungen Screen.
class ArchiveSettingsScreen extends StatefulWidget {
  final ICleonaService service;
  const ArchiveSettingsScreen({super.key, required this.service});

  @override
  State<ArchiveSettingsScreen> createState() => _ArchiveSettingsState();
}

class _ArchiveSettingsState extends State<ArchiveSettingsScreen> {
  late ArchiveConfig _config;
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _tier1Controller = TextEditingController();
  final TextEditingController _tier2Controller = TextEditingController();
  final TextEditingController _tier3Controller = TextEditingController();
  String? _tierError;
  String? _connectionTestResult;

  /// Share identity and "only in this network" as the SERVICE sees them
  /// (§21.6, S394) — via `archive_status` on the desktop, in-process on
  /// Android/iOS. `null` until the first answer.
  Map<String, dynamic>? _shareStatus;
  String? _networkError;

  /// The service answered [ICleonaService.getArchiveSettings]; until then
  /// the screen shows a progress mark and writes nothing.
  bool _loaded = false;

  /// Loading has failed (the store THREW, or the daemon could not be
  /// asked), and [_config] therefore carries default values instead of the
  /// real setting. The data-loss bolt: [_save] writes nothing then.
  bool _loadFailed = false;

  /// A share password is stored. The screen never holds it (§21.6, S410
  /// E10): the field stays empty and shows that one is there.
  bool _hasPassword = false;

  // ── WHERE THE SETTING LIES (S410 E10) ─────────────────────────────────
  //
  // In the service, per identity, in its encrypted store (S366, S407-E9).
  // Until S410 this screen read and wrote the store ITSELF, through
  // `widget.service is CleonaService` — which holds only in-process
  // (Android/iOS). On Linux and Windows `widget.service` is an `IpcClient`,
  // and the setting was never stored there (since the archive screen
  // appeared, d67dfa43, April 2026; no IPC write command ever existed —
  // 4010919a; gui-23 15). Now both surfaces go through the interface: read
  // without the password, write with the password only when the user typed
  // one, test where the password lies.

  @override
  void initState() {
    super.initState();
    _config = ArchiveConfig.production();
    unawaited(_load());
    unawaited(_refreshShareStatus());
  }

  void _fillFields() {
    _ssidController.text = _config.allowedSSIDs.join(', ');
    _budgetController.text = '${_config.storageBudgetMB}';
    _hostController.text = _config.archiveHost;
    _pathController.text = _config.archivePath;
    _usernameController.text = _config.archiveUsername ?? '';
    _passwordController.text = '';
    _portController.text = _config.archivePort?.toString() ?? '';
    _tier1Controller.text = '${_config.tier1Boundary.inDays}';
    _tier2Controller.text = '${_config.tier2Boundary.inDays}';
    _tier3Controller.text = '${_config.tier3Boundary.inDays}';
  }

  /// The setting from the service. `null` — unreadable store or no answer —
  /// is not "never configured": the screen shows defaults and writes
  /// nothing, so that defaults never lie down over a setting that exists.
  Future<void> _load() async {
    ArchiveSettingsView? view;
    try {
      view = await widget.service.getArchiveSettings();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (view == null) {
        _loadFailed = true;
      } else {
        _config = view.config;
        _hasPassword = view.hasPassword;
      }
      _loaded = true;
      _fillFields();
    });
  }

  Future<void> _refreshShareStatus() async {
    Map<String, dynamic>? st;
    try {
      st = await widget.service.getArchiveShareStatus();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _shareStatus = st);
  }

  Future<void> _rebindShare() async {
    await widget.service.rebindArchiveShare();
    await _refreshShareStatus();
  }

  Future<void> _captureNetwork() async {
    final n = await widget.service.captureArchiveNetwork();
    if (!mounted) return;
    setState(() => _networkError =
        n == null ? AppLocale.read(context).get('archive_network_capture_failed') : null);
    await _refreshShareStatus();
  }

  Future<void> _clearNetworks() async {
    await widget.service.clearArchiveNetworks();
    if (!mounted) return;
    setState(() => _networkError = null);
    await _refreshShareStatus();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _budgetController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _tier1Controller.dispose();
    _tier2Controller.dispose();
    _tier3Controller.dispose();
    super.dispose();
  }

  void _applyTierBoundaries() {
    final t1 = int.tryParse(_tier1Controller.text);
    final t2 = int.tryParse(_tier2Controller.text);
    final t3 = int.tryParse(_tier3Controller.text);
    if (t1 == null || t2 == null || t3 == null || t1 < 1 || t2 < 1 || t3 < 1) {
      setState(() => _tierError = AppLocale.read(context).get('archive_tier_error_min'));
      return;
    }
    if (t1 >= t2 || t2 >= t3) {
      setState(() => _tierError = AppLocale.read(context).get('archive_tier_error_order'));
      return;
    }
    setState(() => _tierError = null);
    _updateConfig((_) => _copyConfig(
      tier1Boundary: Duration(days: t1),
      tier2Boundary: Duration(days: t2),
      tier3Boundary: Duration(days: t3),
    ));
  }

  /// Hands the setting to the service, which stores it in the identity's
  /// encrypted store (S366: never `archive_config.json`, which carried the
  /// password in plain text).
  ///
  /// ── THE DATA-LOSS BOLT ─────────────────────────────────────────
  ///
  /// If loading failed, [_config] carries defaults; writing them would lay
  /// them over the real setting, host, user name and password included — the
  /// user would only have flipped a switch. So NOTHING is written then. The
  /// service holds the second half: it reads the stored record before it
  /// writes and refuses if it cannot (pin, networks and — unless [password]
  /// is given — the password come from there, never from this screen).
  void _save({String? password}) {
    if (!_loaded || _loadFailed) return;
    unawaited(widget.service
        .setArchiveSettings(_config, password: password)
        .catchError((Object _) => false));
  }

  void _updateConfig(ArchiveConfig Function(ArchiveConfig) updater,
      {String? password}) {
    setState(() {
      _config = updater(_config);
      if (password != null) _hasPassword = password.isNotEmpty;
    });
    _save(password: password);
  }

  /// Create a copy of the current config with updated fields.
  /// Preserves all fields not explicitly overridden.
  ArchiveConfig _copyConfig({
    Duration? tier1Boundary,
    Duration? tier2Boundary,
    Duration? tier3Boundary,
    int? storageBudgetMB,
    List<String>? allowedSSIDs,
    ArchiveProtocol? defaultProtocol,
    bool? enabledByDefault,
    String? archiveHost,
    String? archivePath,
    String? archiveUsername,
    int? archivePort,
    bool clearUsername = false,
    bool clearPort = false,
  }) {
    // No password here: the screen does not hold it (it goes as the
    // `password` of [_updateConfig] when the user typed one).
    return ArchiveConfig(
      tier1Boundary: tier1Boundary ?? _config.tier1Boundary,
      tier2Boundary: tier2Boundary ?? _config.tier2Boundary,
      tier3Boundary: tier3Boundary ?? _config.tier3Boundary,
      storageBudgetMB: storageBudgetMB ?? _config.storageBudgetMB,
      allowedSSIDs: allowedSSIDs ?? _config.allowedSSIDs,
      allowedNetworks: _config.allowedNetworks,
      shareIdentity: _config.shareIdentity,
      defaultProtocol: defaultProtocol ?? _config.defaultProtocol,
      enabledByDefault: enabledByDefault ?? _config.enabledByDefault,
      archiveHost: archiveHost ?? _config.archiveHost,
      archivePath: archivePath ?? _config.archivePath,
      archiveUsername: clearUsername ? null : (archiveUsername ?? _config.archiveUsername),
      archivePort: clearPort ? null : (archivePort ?? _config.archivePort),
    );
  }

  /// Tests the STORED setting where the password lies — in the service
  /// (on Linux/Windows the daemon, `archive_test_connection`).
  Future<void> _testConnection() async {
    setState(() => _connectionTestResult = null);
    try {
      final r = await widget.service.testArchiveShare();
      if (!mounted) return;
      setState(() => _connectionTestResult = r != null && r.reachable
          ? 'OK'
          : r?.identity == ShareIdentityState.mismatch
              ? AppLocale.read(context).get('archive_identity_mismatch')
              : 'FAIL');
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectionTestResult = 'ERROR: $e');
    }
  }

  /// Share identity (§21.6 security rules). Shown once the service answered.
  List<Widget> _shareIdentityGroup(AppLocale locale) {
    final st = _shareStatus;
    if (st == null) return const [];
    final state = st['identityState'] as String?;
    final pin = st['identityPin'] as String?;
    final mismatch = state == ShareIdentityState.mismatch.name;
    final error = Theme.of(context).colorScheme.error;
    final String text;
    if (mismatch) {
      text = locale.get('archive_identity_mismatch');
    } else if (pin != null) {
      text = locale.get('archive_identity_pinned').replaceAll('{pin}', pin);
    } else if (state == ShareIdentityState.unavailable.name) {
      text = locale.get('archive_identity_unavailable');
    } else {
      text = locale.get('archive_identity_unpinned');
    }
    return [
      FormGroup(
        title: locale.get('archive_identity_title'),
        children: [
          ListTile(
            leading: Icon(mismatch ? Icons.gpp_bad : Icons.verified_user,
                color: mismatch ? error : null),
            title: Text(text,
                style: mismatch ? TextStyle(color: error) : null),
            subtitle: mismatch && pin != null
                ? Text(locale.get('archive_identity_pinned').replaceAll('{pin}', pin))
                : null,
          ),
          if (mismatch || pin != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _rebindShare,
                  icon: const Icon(Icons.link_off),
                  label: Text(locale.get('archive_identity_rebind')),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  /// "Only in this network" (§21.6, optional narrowing).
  Widget _networkGroup(AppLocale locale) {
    final nets = [
      for (final j in (_shareStatus?['networks'] as List<dynamic>? ?? const []))
        ?ArchiveNetwork.fromJson(j),
    ];
    return FormGroup(
      title: locale.get('archive_network_title'),
      children: [
        if (nets.isEmpty)
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(locale.get('archive_network_none')),
          ),
        for (final n in nets)
          ListTile(
            leading: const Icon(Icons.router),
            title: Text(n.subnet),
            subtitle: n.gateway == null
                ? null
                : Text('${locale.get('archive_network_gateway')}: ${n.gateway}'),
          ),
        if (_networkError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_networkError!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _shareStatus == null ? null : _captureNetwork,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(locale.get('archive_network_capture')),
              ),
              if (nets.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _clearNetworks,
                  icon: const Icon(Icons.clear),
                  label: Text(locale.get('archive_network_clear')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final protocolName = _config.defaultProtocol.name.toUpperCase();
    return AppBarScaffold(
      title: locale.get('archive_settings_title'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      // Until the service answered, nothing is shown that could be changed
      // and then not written ([_save] waits for the load).
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          const SizedBox(height: 8),
          FormGroup(
            title: locale.get('archive_settings_title'),
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.archive),
                title: Text(locale.get('archive_enabled')),
                value: _config.enabledByDefault,
                onChanged: (v) => _updateConfig((_) => _copyConfig(enabledByDefault: v)),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('archive_protocol'),
            children: [
              ListTile(
                leading: const Icon(Icons.lan),
                title: Text(locale.get('archive_protocol')),
                subtitle: Text(protocolName),
                trailing: DropdownButton<ArchiveProtocol>(
                  value: _config.defaultProtocol,
                  items: ArchiveProtocol.values.map((p) =>
                    DropdownMenuItem(value: p, child: Text(p.name.toUpperCase()))
                  ).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _updateConfig((_) => _copyConfig(defaultProtocol: v));
                    }
                  },
                ),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('archive_connection'),
            padRows: true,
            dividers: false,
            children: [
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.dns),
                  labelText: locale.get('archive_host'),
                  hintText: 'nas.local',
                ),
                onSubmitted: (v) => _updateConfig((_) => _copyConfig(archiveHost: v.trim())),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pathController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.folder),
                  labelText: locale.get('archive_path'),
                  hintText: '/share/cleona-archive',
                ),
                onSubmitted: (v) => _updateConfig((_) => _copyConfig(archivePath: v.trim())),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person),
                  labelText: locale.get('archive_username'),
                ),
                onSubmitted: (v) {
                  final val = v.trim();
                  _updateConfig((_) => val.isEmpty
                      ? _copyConfig(clearUsername: true)
                      : _copyConfig(archiveUsername: val));
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock),
                  labelText: locale.get('archive_password'),
                  // A stored password is not shown, only that it is there.
                  hintText: _hasPassword ? '••••••••' : null,
                ),
                // Submitted empty: the stored password is removed (as before).
                onSubmitted: (v) =>
                    _updateConfig((c) => c, password: v.trim()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.settings_ethernet),
                  labelText: locale.get('archive_port'),
                  hintText: locale.get('archive_port_default'),
                ),
                onSubmitted: (v) {
                  final port = int.tryParse(v.trim());
                  _updateConfig((_) => port == null
                      ? _copyConfig(clearPort: true)
                      : _copyConfig(archivePort: port));
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _config.archiveHost.isEmpty ? null : _testConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(locale.get('archive_test_connection')),
                  ),
                  const SizedBox(width: 12),
                  if (_connectionTestResult != null)
                    Icon(
                      _connectionTestResult == 'OK' ? Icons.check_circle : Icons.error,
                      color: _connectionTestResult == 'OK' ? Colors.green : Colors.red,
                    ),
                  if (_connectionTestResult != null && _connectionTestResult != 'OK')
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          _connectionTestResult!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          ..._shareIdentityGroup(locale),
          _networkGroup(locale),
          // §21.6: the SSID list is offered only where the platform hands
          // the name over without a location permission (Linux, Windows).
          if (ssidReadableHere) FormGroup(
            title: locale.get('archive_ssid'),
            padRows: true,
            dividers: false,
            children: [
              TextField(
                controller: _ssidController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.wifi),
                  labelText: locale.get('archive_ssid'),
                  hintText: locale.get('archive_ssid_subtitle'),
                ),
                onSubmitted: (v) {
                  final ssids = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  _updateConfig((_) => _copyConfig(allowedSSIDs: ssids));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
          FormGroup(
            title: locale.get('archive_budget'),
            padRows: true,
            dividers: false,
            children: [
              TextField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.storage),
                  labelText: locale.get('archive_budget'),
                  suffixText: 'MB',
                ),
                onSubmitted: (v) {
                  final mb = int.tryParse(v);
                  if (mb != null && mb > 0) {
                    _updateConfig((_) => _copyConfig(storageBudgetMB: mb));
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
          FormGroup(
            title: locale.get('archive_tier_settings'),
            children: [
              if (_tierError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(_tierError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ),
              ListTile(
                leading: const Icon(Icons.photo_size_select_large),
                title: Text(locale.get('archive_tier1')),
                subtitle: SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _tier1Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(suffixText: locale.get('days'), isDense: true),
                    onSubmitted: (_) => _applyTierBoundaries(),
                    onEditingComplete: _applyTierBoundaries,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_size_select_small),
                title: Text(locale.get('archive_tier2')),
                subtitle: SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _tier2Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(suffixText: locale.get('days'), isDense: true),
                    onSubmitted: (_) => _applyTierBoundaries(),
                    onEditingComplete: _applyTierBoundaries,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(locale.get('archive_tier3')),
                subtitle: SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _tier3Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(suffixText: locale.get('days'), isDense: true),
                    onSubmitted: (_) => _applyTierBoundaries(),
                    onEditingComplete: _applyTierBoundaries,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Transkriptions-Einstellungen Screen.
class TranscriptionSettingsScreen extends StatefulWidget {
  final ICleonaService service;
  const TranscriptionSettingsScreen({super.key, required this.service});

  @override
  State<TranscriptionSettingsScreen> createState() => _TranscriptionSettingsState();
}

class _TranscriptionSettingsState extends State<TranscriptionSettingsScreen> {
  String _selectedModel = 'base';
  String _selectedLanguage = 'auto';
  int _retentionDays = 30;
  double _downloadProgress = 0.0;
  String _downloadStatus = 'idle';

  /// What the transcribing service reported last — `null` until it
  /// answered. S405 A-6: the screen goes ONLY through the interface; on
  /// Linux/Windows the service is the daemon behind IPC, and the former
  /// `widget.service is CleonaService` path left the screen dead there.
  TranscriptionStatus? _status;

  @override
  void initState() {
    super.initState();
    widget.service.onTranscriptionStatusChanged = _onStatus;
    _loadTranscriptionStatus();
  }

  @override
  void dispose() {
    if (widget.service.onTranscriptionStatusChanged == _onStatus) {
      widget.service.onTranscriptionStatusChanged = null;
    }
    super.dispose();
  }

  /// A status pushed while a download runs: only the download part and
  /// the list of present models — the choices on screen stay the user's.
  void _onStatus(TranscriptionStatus s) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _downloadStatus = s.downloadStatus;
      _downloadProgress = s.downloadProgress;
    });
  }

  Future<void> _loadTranscriptionStatus() async {
    final s = await widget.service.getTranscriptionStatus();
    if (s == null || !mounted) return;
    setState(() {
      _status = s;
      _selectedLanguage = s.language;
      _retentionDays = s.retentionDays;
      _selectedModel = s.modelSize;
      _downloadStatus = s.downloadStatus;
      _downloadProgress = s.downloadProgress;
    });
  }

  /// S366: the values live in the `transcription_config` area of the
  /// identity's encrypted store; the service writes them there (and sends
  /// the language to the other own devices, §14.7 Type 8).
  ///
  /// NO DATA-LOSS BOLT, and that is weighed: if the three
  /// values are lost, transcription runs again with `auto`, 30 days
  /// and `base`. Nothing is gone that the user does not re-choose in five seconds
  /// — unlike the archive, where a password hangs at the same
  /// place.
  Future<void> _saveTranscriptionConfig() async {
    await widget.service.setTranscriptionSettings(
      language: _selectedLanguage,
      modelSize: _selectedModel,
      retentionDays: _retentionDays,
    );
  }

  bool _isModelDownloaded(String size) =>
      _status?.downloadedModels.contains(size) ?? false;

  String _modelLabel(String size, AppLocale locale) => switch (size) {
    'tiny' => locale.get('transcription_model_tiny'),
    'base' => locale.get('transcription_model_base'),
    'small' => locale.get('transcription_model_small'),
    _ => size,
  };

  Future<void> _downloadModel() async {
    final started =
        await widget.service.downloadTranscriptionModel(_selectedModel);
    if (!started || !mounted) return;
    // Progress and end arrive through [_onStatus].
    setState(() {
      _downloadStatus = 'downloading';
      _downloadProgress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final modelExists = _isModelDownloaded(_selectedModel);
    final whisperAvailable = _status?.whisperAvailable ?? false;
    // `modelLoaded` speaks for the size the service holds as set; it is
    // only taken for the size selected here.
    final modelChecked = (_status?.modelLoaded ?? false) &&
        _status?.modelSize == _selectedModel;
    final ready = whisperAvailable && modelChecked;

    return AppBarScaffold(
      title: locale.get('transcription_settings_title'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          FormGroup(
            title: locale.get('whisper_status'),
            children: [
              // Ready only when the model of the SET size passed its
              // SHA-256 check (D-64) — a file on disk is not enough.
              ListTile(
                leading: Icon(
                  ready ? Icons.check_circle : Icons.warning,
                  color: ready ? Colors.green : Colors.orange,
                ),
                title: Text(ready
                    ? locale.get('transcription_ready')
                    : locale.get('transcription_not_ready')),
                subtitle: Text(!whisperAvailable
                    ? locale.get('transcription_library_missing')
                    : modelChecked
                        ? locale.get('transcription_model_loaded')
                        : modelExists
                            ? locale.get('transcription_model_checking')
                            : locale.get('transcription_model_missing')),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('transcription_language'),
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(locale.get('transcription_language')),
                subtitle: Text(_selectedLanguage == 'auto'
                    ? locale.get('transcription_language_auto')
                    : _selectedLanguage.toUpperCase()),
                trailing: DropdownButton<String>(
                  value: _selectedLanguage,
                  items: VoiceTranscriptionConfig.production()
                      .supportedLanguages
                      .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(l == 'auto'
                                ? locale.get('language_auto')
                                : l.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedLanguage = v);
                      _saveTranscriptionConfig();
                    }
                  },
                ),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('transcription_retention'),
            children: [
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text(locale.get('transcription_retention')),
                subtitle: Text('$_retentionDays ${locale.get("days")}'),
                trailing: DropdownButton<int>(
                  value: _retentionDays,
                  items: [7, 14, 30, 60, 90].map((d) =>
                    DropdownMenuItem(value: d, child: Text('$d ${locale.get("days")}'))
                  ).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _retentionDays = v);
                      _saveTranscriptionConfig();
                    }
                  },
                ),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('transcription_model'),
            children: [
              for (final size in ['tiny', 'base', 'small'])
                RadioListTile<String>(
                  value: size,
                  groupValue: _selectedModel,
                  title: Text(_modelLabel(size, locale)),
                  subtitle: _isModelDownloaded(size)
                      ? Text(locale.get('whisper_downloaded'), style: const TextStyle(color: Colors.green))
                      : null,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedModel = v);
                      _saveTranscriptionConfig();
                    }
                  },
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildDownloadWidget(modelExists, locale),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadWidget(bool modelExists, AppLocale locale) {
    if (_downloadStatus == 'downloading') {
      return Column(
        children: [
          LinearProgressIndicator(value: _downloadProgress),
          const SizedBox(height: 8),
          Text('${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    if (modelExists) {
      return const SizedBox.shrink();
    }

    final button = ElevatedButton.icon(
      onPressed: _downloadModel,
      icon: const Icon(Icons.download),
      label: Text('Download ${_modelLabel(_selectedModel, locale)}'),
    );
    // D-64: a file that did not match the fixed SHA-256 was deleted — the
    // user is told why the model is missing again. A failed download says
    // its reason (the service hands it over without any URL).
    final String? problem = switch (_downloadStatus) {
      'rejected' => locale.get('transcription_model_rejected'),
      'failed' => locale.tr('transcription_download_failed',
          {'reason': _status?.downloadError ?? '—'}),
      _ => null,
    };
    if (problem == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error),
          title: Text(problem),
        ),
        button,
      ],
    );
  }
}

/// Media settings screen (auto-download thresholds + download directory).
class MediaSettingsScreen extends StatefulWidget {
  final ICleonaService service;
  const MediaSettingsScreen({super.key, required this.service});

  @override
  State<MediaSettingsScreen> createState() => _MediaSettingsScreenState();
}

class _MediaSettingsScreenState extends State<MediaSettingsScreen> {
  late MediaSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = MediaSettings.fromJson(widget.service.mediaSettings.toJson());
  }

  void _save() {
    widget.service.updateMediaSettings(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AppBarScaffold(
      title: locale.get('media_settings_title'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          FormGroup(
            title: locale.get('media_auto_download'),
            children: [
              _ThresholdTile(
                icon: Icons.image,
                label: locale.get('media_images'),
                value: _settings.maxAutoDownloadImage,
                onChanged: (v) { setState(() => _settings.maxAutoDownloadImage = v); _save(); },
              ),
              _ThresholdTile(
                icon: Icons.videocam,
                label: locale.get('media_videos'),
                value: _settings.maxAutoDownloadVideo,
                onChanged: (v) { setState(() => _settings.maxAutoDownloadVideo = v); _save(); },
              ),
              _ThresholdTile(
                icon: Icons.insert_drive_file,
                label: locale.get('media_files'),
                value: _settings.maxAutoDownloadFile,
                onChanged: (v) { setState(() => _settings.maxAutoDownloadFile = v); _save(); },
              ),
              _ThresholdTile(
                icon: Icons.mic,
                label: locale.get('media_voice'),
                value: _settings.maxAutoDownloadVoice,
                onChanged: (v) { setState(() => _settings.maxAutoDownloadVoice = v); _save(); },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cell_tower),
                title: Text(locale.get('media_mobile_download')),
                subtitle: Text(locale.get('media_mobile_download_sub')),
                value: _settings.autoDownloadOnMobile,
                onChanged: (v) { setState(() => _settings.autoDownloadOnMobile = v); _save(); },
              ),
            ],
          ),
          FormGroup(
            title: locale.get('media_download_dir'),
            children: [
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text(locale.get('media_download_dir')),
                subtitle: Text(_settings.downloadDirectory ?? locale.get('media_download_dir_default')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_settings.downloadDirectory != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { setState(() => _settings.downloadDirectory = null); _save(); },
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  final controller = TextEditingController(text: _settings.downloadDirectory ?? '');
                  final result = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(locale.get('media_download_dir')),
                      content: TextField(
                        controller: controller,
                        decoration: InputDecoration(hintText: locale.get('media_download_dir_default')),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
                        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(locale.get('ok'))),
                      ],
                    ),
                  );
                  if (result != null) {
                    setState(() => _settings.downloadDirectory = result.isEmpty ? null : result);
                    _save();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThresholdTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _ThresholdTile({required this.icon, required this.label, required this.value, required this.onChanged});

  static const _options = [0, 1*1024*1024, 5*1024*1024, 10*1024*1024, 25*1024*1024, 50*1024*1024, 100*1024*1024];

  String _formatSize(int bytes) {
    if (bytes == 0) return 'Aus / Off';
    if (bytes < 1024 * 1024) return '${bytes ~/ 1024} KB';
    return '${bytes ~/ (1024 * 1024)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: DropdownButton<int>(
        value: _options.contains(value) ? value : _options.last,
        items: _options.map((v) => DropdownMenuItem(value: v, child: Text(_formatSize(v)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

/// Small "?" button shown next to a setting title.
/// Tapping opens a bottom-sheet (mobile-friendly, doesn't shift layout)
/// with a longer explanation. Uses i18n keys `<key>` and `<key>_help`.
class _HelpButton extends StatelessWidget {
  final String titleKey;
  final String helpKey;
  const _HelpButton({required this.titleKey, required this.helpKey});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final theme = Theme.of(context);
    return InkResponse(
      radius: 18,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locale.get(titleKey),
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(locale.get(helpKey),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(locale.get('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.help_outline,
          size: 18,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// Wraps a title String + ? help button into a Row, suitable for ListTile's
/// `title:` slot. Keeps the existing layout otherwise unchanged.
Widget _titleWithHelp(BuildContext context, String titleKey, String helpKey) {
  final locale = AppLocale.read(context);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: Text(locale.get(titleKey))),
      const SizedBox(width: 4),
      _HelpButton(titleKey: titleKey, helpKey: helpKey),
    ],
  );
}

// ── Notification Settings Screen ───────────────────────────────────

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, required this.service});
  final ICleonaService service;
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late NotificationSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.service.notificationSound.settings;
  }

  @override
  void dispose() {
    widget.service.stopRingtonePreview();
    super.dispose();
  }

  void _save() {
    widget.service.updateNotificationSettings(_settings);
    setState(() {});
  }

  /// A minute of the day in the system's time format (12 h or 24 h).
  static String _minuteLabel(BuildContext context, int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  Future<void> _pickQuietMinute(BuildContext context,
      {required bool from}) async {
    final current = from ? _settings.quietFromMinute : _settings.quietToMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    final minute = picked.hour * 60 + picked.minute;
    if (from) {
      _settings.quietFromMinute = minute;
    } else {
      _settings.quietToMinute = minute;
    }
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    return AppBarScaffold(
      title: locale.get('notification_settings_title'),
      opaqueBody: true,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          FormGroup(
            title: locale.get('notification_settings_title'),
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.volume_up),
                title: Text(locale.get('notification_sound_enabled')),
                value: _settings.soundEnabled,
                onChanged: (v) {
                  _settings.soundEnabled = v;
                  _save();
                },
              ),
              if (isAndroid)
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: Text(locale.get('notification_vibration')),
                  value: _settings.vibrationEnabled,
                  onChanged: (v) {
                    _settings.vibrationEnabled = v;
                    _save();
                  },
                ),
              SwitchListTile(
                secondary: const Icon(Icons.chat_bubble_outline),
                title: Text(locale.get('notification_message_sound')),
                value: _settings.messageSoundEnabled,
                onChanged: _settings.soundEnabled
                    ? (v) {
                        _settings.messageSoundEnabled = v;
                        _save();
                      }
                    : null,
              ),
            ],
          ),
          FormGroup(
            title: locale.get('notification_defaults_section'),
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.person),
                title: Text(locale.get('notification_default_direct')),
                value: _settings.defaultDirectNotify,
                onChanged: (v) {
                  _settings.defaultDirectNotify = v;
                  _save();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.group),
                title: Text(locale.get('notification_default_group')),
                value: _settings.defaultGroupNotify,
                onChanged: (v) {
                  _settings.defaultGroupNotify = v;
                  _save();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.campaign),
                title: Text(locale.get('notification_default_channel')),
                value: _settings.defaultChannelNotify,
                onChanged: (v) {
                  _settings.defaultChannelNotify = v;
                  _save();
                },
              ),
            ],
          ),
          FormGroup(
            title: locale.get('quiet_hours_section'),
            children: [
              SwitchListTile(
                key: const Key('quiet_hours_switch'),
                secondary: const Icon(Icons.bedtime_outlined),
                title: Text(locale.get('quiet_hours_enabled')),
                subtitle: Text(locale.get('quiet_hours_hint')),
                value: _settings.quietHoursEnabled,
                onChanged: (v) {
                  _settings.quietHoursEnabled = v;
                  _save();
                },
              ),
              ListTile(
                key: const Key('quiet_hours_from'),
                leading: const Icon(Icons.nightlight_outlined),
                title: Text(locale.get('quiet_hours_from')),
                trailing: Text(_minuteLabel(context, _settings.quietFromMinute)),
                enabled: _settings.quietHoursEnabled,
                onTap: () => _pickQuietMinute(context, from: true),
              ),
              ListTile(
                key: const Key('quiet_hours_to'),
                leading: const Icon(Icons.wb_sunny_outlined),
                title: Text(locale.get('quiet_hours_to')),
                trailing: Text(_minuteLabel(context, _settings.quietToMinute)),
                enabled: _settings.quietHoursEnabled,
                onTap: () => _pickQuietMinute(context, from: false),
              ),
            ],
          ),
          FormGroup(
            title: locale.get('notification_ringtone_section'),
            children: [
              ...Ringtone.values.map((rt) => RadioListTile<Ringtone>(
                    title: Text(rt.displayName),
                    value: rt,
                    groupValue: _settings.callRingtone,
                    onChanged: _settings.soundEnabled
                        ? (v) {
                            _settings.callRingtone = v!;
                            _save();
                            widget.service.previewRingtone(v);
                          }
                        : null,
                  )),
            ],
          ),
          FormGroup(
            title: locale.get('notification_volume'),
            padRows: true,
            dividers: false,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_mute, size: 20),
                  Expanded(
                    child: Slider(
                      value: _settings.callVolume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(_settings.callVolume * 100).round()}%',
                      onChanged: _settings.soundEnabled
                          ? (v) {
                              _settings.callVolume = v;
                              _save();
                            }
                          : null,
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 20),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}


/// §24.4.2 — the data-saving mode as a visible state.
///
/// ── WHAT THIS ROW MUST FULFIL ─────────────────────────────────
///
/// 1. "a visible state, not a setting buried in a submenu" — it stands
///    in the first group of the settings, and the state stands as a
///    word next to it (`datasaver_state_on`/`_off`), not only as a
///    switch position. §25.4 additionally lists the metric for it in the
///    network dashboard.
/// 2. The consequence ALWAYS stands below (`datasaver_consequence`), not
///    only after reaching for a question mark.
/// 3. "the app may suggest but must never activate it itself" — the
///    suggestion is a banner with a button. There is in
///    this file no path that calls [ICleonaService.setDataSaver] without
///    a press.
/// 4. If a chat is on high-secure, the switch is DEAD
///    (`onChanged: null`) and names the reason. The greying out is
///    only the courtesy — the effective bolt sits in the service
///    (`CoverSaver.request`) and holds even if this row lies.
class _DataSaverTile extends StatefulWidget {
  final ICleonaService service;

  /// Whether the active connection is metered (cellular only).
  final bool metered;

  const _DataSaverTile({required this.service, required this.metered});

  @override
  State<_DataSaverTile> createState() => _DataSaverTileState();
}

class _DataSaverTileState extends State<_DataSaverTile> {
  /// Whether the user has dismissed the suggestion for this session.
  ///
  /// Deliberately NOT persistent: the suggestion depends on the current
  /// connection, and a permanently stored "no" would be a
  /// decision about future connections that nobody has
  /// made.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final scheme = Theme.of(context).colorScheme;
    final service = widget.service;
    final locked = service.dataSaverLockedBySecure;
    final active = service.dataSaverActive;

    final line = SwitchListTile(
      secondary: Icon(
        locked ? Icons.lock_outline : Icons.data_saver_on,
        color: locked ? scheme.outline : null,
      ),
      title: Text(
        '${locale.get('datasaver_title')} — '
        '${locale.get(active ? 'datasaver_state_on' : 'datasaver_state_off')}',
      ),
      subtitle: Text(
        locked
            ? locale.get('datasaver_locked_secure')
            : locale.get('datasaver_consequence'),
        style: TextStyle(color: locked ? scheme.error : null),
      ),
      value: active,
      // DEAD as long as secure is running. The reason stands in the subtitle.
      onChanged: locked ? null : (v) => _set(v),
    );

    if (!widget.metered || active || locked || _dismissed) return line;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // THE SUGGESTION — and only a suggestion. No preselection, no
        // pre-flipping, no "will be activated in 5 s".
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.signal_cellular_alt,
                      size: 18, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locale.get('datasaver_suggest'),
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _dismissed = true),
                    child: Text(locale.get('cancel')),
                  ),
                  TextButton(
                    onPressed: () => _set(true),
                    child: Text(locale.get('datasaver_suggest_action')),
                  ),
                ],
              ),
            ],
          ),
        ),
        line,
      ],
    );
  }

  /// The ONLY way to set the mode from this file — and it
  /// depends on a user action (switch or button).
  void _set(bool to) {
    final reason = widget.service.setDataSaver(to);
    if (!mounted) return;
    setState(() => _dismissed = true);
    if (reason == kDataSaverLockedBySecure) {
      // The service has refused. The reason is SHOWN, not
      // swallowed — §24.4.2: "locked with its reason named".
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocale.read(context).get('datasaver_locked_secure')),
      ));
    }
  }
}

/// S388, V4.2 §11.9 — the fourth neighbour source switchable: external
/// address entries on public relays. "The source can be switched
/// off by the user. A node with it switched off neither reads nor
/// publishes; it finds neighbours by sources 1–3 alone."
///
/// As with the saving mode: the row names the state as a word, and the consequence
/// ALWAYS stands below (`external_records_consequence`) — when reading and
/// entering happens, and that off means no traffic to foreign relays.
/// A device value: the switch applies to the node, not per identity.
class _ExternalRecordsTile extends StatefulWidget {
  final ICleonaService service;

  const _ExternalRecordsTile({required this.service});

  @override
  State<_ExternalRecordsTile> createState() => _ExternalRecordsTileState();
}

class _ExternalRecordsTileState extends State<_ExternalRecordsTile> {
  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final to = widget.service.externalRecordsEnabled;
    return SwitchListTile(
      secondary: const Icon(Icons.travel_explore),
      title: Text(
        '${locale.get('external_records_title')} — '
        '${locale.get(to ? 'datasaver_state_on' : 'datasaver_state_off')}',
      ),
      subtitle: Text(locale.get('external_records_consequence')),
      value: to,
      // The ONLY way to set the switch — a user action.
      onChanged: (v) {
        widget.service.setExternalRecordsEnabled(v);
        if (mounted) setState(() {});
      },
    );
  }
}

/// §12.7 "fewer empty cover packets on W/LAN (§5.1)" — S398-W4.
///
/// A plain switch, default OFF (§12.7, D-7). It replaces the S373 consent
/// per segment, which wrote into the replaced V4.1 layer and never reached
/// the 4.2 cover stream (report `S398-LUECKEN-GUI.md`, B7).
///
/// 1. **Visible state.** The word names the EFFECT, not the switch
///    position: on metered mobile data the reduction never applies (§5.1),
///    and the row then says "off" although the wish is on.
/// 2. **The consequence ALWAYS stands below** (`cover_reduce_consequence`):
///    what is lost (concealment on this link), and where (only on unmetered
///    W/LAN).
/// 3. **The app never activates by itself.** No suggestion, no
///    preselection — only [SwitchListTile.onChanged] calls the setter.
class _LanShapingTile extends StatefulWidget {
  final ICleonaService service;

  const _LanShapingTile({required this.service});

  @override
  State<_LanShapingTile> createState() => _LanShapingTileState();
}

class _LanShapingTileState extends State<_LanShapingTile> {
  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final service = widget.service;
    final wish = service.coverReduceEnabled;
    final active = service.coverReduceActive;
    // The word names the EFFECT (§5.1: only on unmetered W/LAN); the switch
    // position is the wish. Switched on over mobile data they differ, and
    // the row says so instead of pretending.
    return SwitchListTile(
      key: const ValueKey('switch-cover-reduce'),
      secondary: const Icon(Icons.wifi_tethering),
      title: Text(
        '${locale.get('cover_reduce_title')} — '
        '${locale.get(active ? 'datasaver_state_on' : 'datasaver_state_off')}',
      ),
      // The consequence ALWAYS stands below, not behind a question mark.
      subtitle: Text(locale.get('cover_reduce_consequence')),
      value: wish,
      // The ONLY way to set it — a user action. Never suggested by the app.
      onChanged: (v) {
        final ok = widget.service.setCoverReduce(v);
        if (!mounted) return;
        setState(() {});
        if (!ok) _refused(context);
      },
    );
  }
}

/// §12.7 "router mapping (§7.3)" (S398-W4) — the third network switch,
/// until S398 without any surface. Default on.
class _PortMappingTile extends StatefulWidget {
  final ICleonaService service;

  const _PortMappingTile({required this.service});

  @override
  State<_PortMappingTile> createState() => _PortMappingTileState();
}

class _PortMappingTileState extends State<_PortMappingTile> {
  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final on = widget.service.portMappingEnabled;
    return SwitchListTile(
      key: const ValueKey('switch-port-mapping'),
      secondary: const Icon(Icons.router),
      title: Text(
        '${locale.get('port_mapping_title')} — '
        '${locale.get(on ? 'datasaver_state_on' : 'datasaver_state_off')}',
      ),
      subtitle: Text(locale.get('port_mapping_consequence')),
      value: on,
      onChanged: (v) async {
        final ok = await widget.service.setPortMappingEnabled(v);
        if (!mounted) return;
        setState(() {});
        if (!ok && context.mounted) _refused(context);
      },
    );
  }
}

/// §21.3.1/§21.3.3 item 3 — the size of the bulk cache (S407-MASSENCACHE):
/// what this device holds of lane 3 for others (§9.4), in the tiers of
/// `bulk_cache_setting.dart`; default desktop 1 GB, phone 100 MB (D-32).
///
/// The consequence ALWAYS stands below: pieces of others for up to 7 days,
/// and that a smaller size deletes the oldest at once. The row shows the
/// size the device answered, never an anticipated one.
class _BulkCacheTile extends StatefulWidget {
  final ICleonaService service;

  const _BulkCacheTile({required this.service});

  @override
  State<_BulkCacheTile> createState() => _BulkCacheTileState();
}

class _BulkCacheTileState extends State<_BulkCacheTile> {
  // The same source as the seam's `_mobile` (`mycelium_seam.dart`): the
  // operating system, not the theme's `defaultTargetPlatform`.
  static final int _defaultMb =
      bulkCacheDefaultMb(mobile: Platform.isAndroid || Platform.isIOS);

  String _label(AppLocale locale, int mb) {
    final size = mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';
    return mb == _defaultMb
        ? '$size (${locale.get('bulk_cache_default')})'
        : size;
  }

  Future<void> _choose(BuildContext context) async {
    final locale = AppLocale.read(context);
    final now = widget.service.bulkCacheMb;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('bulk_cache_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(locale.get('bulk_cache_consequence')),
              const SizedBox(height: 16),
              for (final mb in kBulkCacheTiersMb)
                RadioListTile<int>(
                  key: ValueKey('bulk-cache-tier-$mb'),
                  value: mb,
                  groupValue: now,
                  title: Text(_label(locale, mb)),
                  onChanged: (v) => Navigator.of(ctx).pop(v),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('cancel')),
          ),
        ],
      ),
    );
    if (picked == null || picked == now) return;
    // The ONLY way to set it — a user action.
    final ok = await widget.service.setBulkCacheMb(picked);
    if (!mounted) return;
    setState(() {});
    if (!ok && context.mounted) _refused(context);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return ListTile(
      key: const ValueKey('tile-bulk-cache'),
      leading: const Icon(Icons.sd_storage),
      title: Text('${locale.get('bulk_cache_title')} — '
          '${_label(locale, widget.service.bulkCacheMb)}'),
      subtitle: Text(locale.get('bulk_cache_consequence')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(_choose(context)),
    );
  }
}

/// A refused network switch says so instead of swallowing it: a setter that
/// silently does nothing cannot be told apart from a broken one.
void _refused(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(AppLocale.read(context).get('network_switch_not_set')),
  ));
}
