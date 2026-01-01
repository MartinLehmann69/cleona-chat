// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/ui/screens/donation_screen.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/whisper_ffi.dart';
import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_service.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/ui/screens/device_management_screen.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/components/form_group.dart';
import 'package:cleona/ui/components/section_card.dart';
import 'dart:convert';
import 'dart:io';

class SettingsScreen extends StatelessWidget {
  final ICleonaService service;
  const SettingsScreen({super.key, required this.service});

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
                if (newPort == service.port) {
                  Navigator.pop(ctx);
                  return;
                }
                final ok = await service.setPort(newPort);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Port $newPort nicht verfügbar')),
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

  void _showSeedPhrase(BuildContext context) {
    final locale = AppLocale.read(context);
    final identityMgr = IdentityManager();
    final words = identityMgr.loadSeedPhrase();

    if (words == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('no_recovery_phrase'))),
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
      body: ListView(
        children: [
          const SizedBox(height: 8),

          FormGroup(
            title: locale.get('section_network'),
            children: [
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text(locale.get('node_id_label')),
                subtitle: Text(
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
                subtitle: Text('${service.peerCount}'),
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: Text(locale.get('stored_fragments')),
                subtitle: Text('${service.fragmentCount}'),
              ),
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
            title: locale.get('section_backup'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: _titleWithHelp(context, 'show_recovery_phrase', 'show_recovery_phrase_help'),
                subtitle: Text(locale.get('recovery_phrase_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSeedPhrase(context),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('guardian_social_recovery'),
            dividers: false,
            children: [
              _GuardianSetupTile(service: service),
            ],
          ),

          FormGroup(
            title: locale.get('section_devices'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.devices),
                title: _titleWithHelp(context, 'device_management_title', 'device_management_help'),
                subtitle: Text(locale.get('device_management_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DeviceManagementScreen(service: service)),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_media'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.download),
                title: _titleWithHelp(context, 'media_settings_title', 'media_settings_help'),
                subtitle: Text(locale.get('media_settings_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MediaSettingsScreen(service: service)),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('notification_settings_title'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: _titleWithHelp(context, 'notification_settings_title', 'notification_settings_help'),
                subtitle: Text(locale.get('notification_settings_subtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotificationSettingsScreen(service: service)),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_archive'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: _titleWithHelp(context, 'archive_settings_title', 'archive_settings_help'),
                subtitle: const Text('SMB / SFTP / FTPS / HTTP'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ArchiveSettingsScreen(service: service)),
                ),
              ),
            ],
          ),

          FormGroup(
            title: locale.get('section_transcription'),
            dividers: false,
            children: [
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: _titleWithHelp(context, 'transcription_settings_title', 'transcription_settings_help'),
                subtitle: Text(locale.get('whisper_engine')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TranscriptionSettingsScreen(service: service)),
                ),
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
                subtitle: Text(locale.get('donate_banner_text'), maxLines: 2, overflow: TextOverflow.ellipsis),
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
              SectionRow(
                label: locale.get('version_label'),
                value: '1.0.0 (Architecture v2.0)',
              ),
              SectionRow(
                label: locale.get('encryption_label'),
                value: 'X25519 + ML-KEM-768 / Ed25519 + ML-DSA-65',
              ),
              SectionRow(
                label: locale.get('network_tag_label'),
                value: NetworkSecret.channel.name,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

}

class _GuardianSetupTile extends StatelessWidget {
  final ICleonaService service;
  const _GuardianSetupTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    if (service.isGuardianSetUp) {
      return ListTile(
        leading: const Icon(Icons.shield, color: Colors.green),
        title: Text(locale.tr('guardian_active', {'count': '5'})),
        subtitle: Text(locale.get('guardian_setup_subtitle')),
      );
    }

    return ListTile(
      leading: const Icon(Icons.group_add),
      title: _titleWithHelp(context, 'guardian_setup', 'guardian_setup_help'),
      subtitle: Text(locale.get('guardian_setup_subtitle')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showGuardianSetupDialog(context),
    );
  }

  void _showGuardianSetupDialog(BuildContext context) {
    final locale = AppLocale.read(context);
    final accepted = service.acceptedContacts;

    if (accepted.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.tr('guardian_need_5_contacts', {'count': '${accepted.length}'}))),
      );
      return;
    }

    final selected = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('guardian_setup')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(locale.get('guardian_select_5')),
                const SizedBox(height: 12),
                ...accepted.map((c) => CheckboxListTile(
                  value: selected.contains(c.nodeIdHex),
                  title: Text(c.displayName),
                  subtitle: Text(c.nodeIdHex.substring(0, 16),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        if (selected.length < 5) selected.add(c.nodeIdHex);
                      } else {
                        selected.remove(c.nodeIdHex);
                      }
                    });
                  },
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(locale.get('cancel')),
            ),
            FilledButton(
              onPressed: selected.length == 5
                  ? () async {
                      final result = await service.setupGuardians(selected.toList());
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result
                              ? locale.get('guardian_setup_complete')
                              : locale.get('guardian_setup_failed'))),
                        );
                      }
                    }
                  : null,
              child: Text('${locale.get('guardian_setup')} (${selected.length}/5)'),
            ),
          ],
        ),
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
                    child: Text(
                      locale.get('seed_phrase_warning'),
                      style: const TextStyle(fontSize: 13),
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

  String get _profileDir {
    if (widget.service is CleonaService) {
      return (widget.service as CleonaService).profileDir;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _config = _load();
    _ssidController.text = _config.allowedSSIDs.join(', ');
    _budgetController.text = '${_config.storageBudgetMB}';
    _hostController.text = _config.archiveHost;
    _pathController.text = _config.archivePath;
    _usernameController.text = _config.archiveUsername ?? '';
    _passwordController.text = _config.archivePassword ?? '';
    _portController.text = _config.archivePort?.toString() ?? '';
    _tier1Controller.text = '${_config.tier1Boundary.inDays}';
    _tier2Controller.text = '${_config.tier2Boundary.inDays}';
    _tier3Controller.text = '${_config.tier3Boundary.inDays}';
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

  ArchiveConfig _load() {
    final dir = _profileDir;
    if (dir.isEmpty) return ArchiveConfig.production();
    final file = File('$dir/archive_config.json');
    if (!file.existsSync()) return ArchiveConfig.production();
    try {
      return ArchiveConfig.fromJson(
          json.decode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return ArchiveConfig.production();
    }
  }

  void _applyTierBoundaries() {
    final t1 = int.tryParse(_tier1Controller.text);
    final t2 = int.tryParse(_tier2Controller.text);
    final t3 = int.tryParse(_tier3Controller.text);
    if (t1 == null || t2 == null || t3 == null || t1 < 1 || t2 < 1 || t3 < 1) {
      setState(() => _tierError = 'Alle Werte müssen ≥ 1 sein');
      return;
    }
    if (t1 >= t2 || t2 >= t3) {
      setState(() => _tierError = 'Original→Vorschau < Vorschau→Mini < Mini→Nur Metadaten');
      return;
    }
    setState(() => _tierError = null);
    _updateConfig((_) => _copyConfig(
      tier1Boundary: Duration(days: t1),
      tier2Boundary: Duration(days: t2),
      tier3Boundary: Duration(days: t3),
    ));
  }

  void _save() {
    final dir = _profileDir;
    if (dir.isEmpty) return;
    final file = File('$dir/archive_config.json');
    file.writeAsStringSync(json.encode(_config.toJson()));
  }

  void _updateConfig(ArchiveConfig Function(ArchiveConfig) updater) {
    setState(() {
      _config = updater(_config);
    });
    _save();
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
    String? archivePassword,
    int? archivePort,
    bool clearUsername = false,
    bool clearPassword = false,
    bool clearPort = false,
  }) {
    return ArchiveConfig(
      tier1Boundary: tier1Boundary ?? _config.tier1Boundary,
      tier2Boundary: tier2Boundary ?? _config.tier2Boundary,
      tier3Boundary: tier3Boundary ?? _config.tier3Boundary,
      storageBudgetMB: storageBudgetMB ?? _config.storageBudgetMB,
      allowedSSIDs: allowedSSIDs ?? _config.allowedSSIDs,
      defaultProtocol: defaultProtocol ?? _config.defaultProtocol,
      enabledByDefault: enabledByDefault ?? _config.enabledByDefault,
      archiveHost: archiveHost ?? _config.archiveHost,
      archivePath: archivePath ?? _config.archivePath,
      archiveUsername: clearUsername ? null : (archiveUsername ?? _config.archiveUsername),
      archivePassword: clearPassword ? null : (archivePassword ?? _config.archivePassword),
      archivePort: clearPort ? null : (archivePort ?? _config.archivePort),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _connectionTestResult = null);
    try {
      final transport = ArchiveTransport.forProtocol(_config.defaultProtocol);
      await transport.connect(
        host: _config.archiveHost,
        path: _config.archivePath,
        username: _config.archiveUsername,
        password: _config.archivePassword,
        port: _config.archivePort,
      );
      final ok = await transport.testConnectivity(timeout: const Duration(seconds: 5));
      await transport.disconnect();
      setState(() => _connectionTestResult = ok ? 'OK' : 'FAIL');
    } catch (e) {
      setState(() => _connectionTestResult = 'ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final protocolName = _config.defaultProtocol.name.toUpperCase();
    return AppBarScaffold(
      title: locale.get('archive_settings_title'),
      opaqueBody: true,
      body: ListView(
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
                ),
                onSubmitted: (v) {
                  final val = v.trim();
                  _updateConfig((_) => val.isEmpty
                      ? _copyConfig(clearPassword: true)
                      : _copyConfig(archivePassword: val));
                },
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
          FormGroup(
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
  ModelDownloadStatus _downloadStatus = ModelDownloadStatus.idle;

  VoiceTranscriptionService? get _transcriptionService {
    if (widget.service is CleonaService) {
      return (widget.service as CleonaService).voiceTranscriptionService;
    }
    return null;
  }

  String get _profileDir {
    if (widget.service is CleonaService) {
      return (widget.service as CleonaService).profileDir;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    final svc = _transcriptionService;
    if (svc != null) {
      _downloadStatus = svc.downloadStatus;
    }
    _loadTranscriptionConfig();
  }

  void _loadTranscriptionConfig() {
    final dir = _profileDir;
    if (dir.isEmpty) return;
    final file = File('$dir/transcription_config.json');
    if (!file.existsSync()) return;
    try {
      final j = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      setState(() {
        _selectedLanguage = j['defaultLanguage'] as String? ?? 'auto';
        _retentionDays = j['audioRetentionDays'] as int? ?? 30;
        _selectedModel = j['modelSize'] as String? ?? 'base';
      });
    } catch (_) {}
  }

  void _saveTranscriptionConfig() {
    final dir = _profileDir;
    if (dir.isEmpty) return;
    final file = File('$dir/transcription_config.json');
    file.writeAsStringSync(json.encode({
      'defaultLanguage': _selectedLanguage,
      'audioRetentionDays': _retentionDays,
      'modelSize': _selectedModel,
    }));
    // Update running service immediately (no restart needed).
    _transcriptionService?.defaultLanguage = _selectedLanguage;
  }

  bool _isModelDownloaded(WhisperModelSize size) {
    return WhisperFFI.isModelDownloaded(size);
  }

  WhisperModelSize _sizeFromString(String s) => switch (s) {
    'tiny' => WhisperModelSize.tiny,
    'small' => WhisperModelSize.small,
    _ => WhisperModelSize.base,
  };

  String _modelLabel(String size, AppLocale locale) => switch (size) {
    'tiny' => locale.get('transcription_model_tiny'),
    'base' => locale.get('transcription_model_base'),
    'small' => locale.get('transcription_model_small'),
    _ => size,
  };

  Future<void> _downloadModel() async {
    final svc = _transcriptionService;
    if (svc == null) return;

    svc.onDownloadProgress = (p) {
      if (mounted) setState(() => _downloadProgress = p);
    };
    svc.onDownloadStatusChanged = (s) {
      if (mounted) setState(() => _downloadStatus = s);
    };

    await svc.downloadModel(_sizeFromString(_selectedModel));
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final selectedSize = _sizeFromString(_selectedModel);
    final modelExists = _isModelDownloaded(selectedSize);
    final whisperAvailable = _transcriptionService?.isWhisperAvailable ?? false;

    return AppBarScaffold(
      title: locale.get('transcription_settings_title'),
      opaqueBody: true,
      body: ListView(
        children: [
          const SizedBox(height: 8),
          FormGroup(
            title: locale.get('whisper_status'),
            children: [
              ListTile(
                leading: Icon(
                  whisperAvailable && modelExists ? Icons.check_circle : Icons.warning,
                  color: whisperAvailable && modelExists ? Colors.green : Colors.orange,
                ),
                title: Text(whisperAvailable && modelExists
                    ? locale.get('transcription_ready')
                    : locale.get('transcription_not_ready')),
                subtitle: Text(whisperAvailable
                    ? (modelExists ? locale.get('transcription_model_loaded') : locale.get('transcription_model_missing'))
                    : locale.get('transcription_library_missing')),
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
                  items: ['auto', 'de', 'en', 'es', 'hu', 'sv'].map((l) =>
                    DropdownMenuItem(value: l, child: Text(l == 'auto' ? locale.get('language_auto') : l.toUpperCase()))
                  ).toList(),
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
                  subtitle: _isModelDownloaded(_sizeFromString(size))
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
    if (_downloadStatus == ModelDownloadStatus.downloading) {
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

    return ElevatedButton.icon(
      onPressed: _downloadModel,
      icon: const Icon(Icons.download),
      label: Text('Download ${_modelLabel(_selectedModel, locale)}'),
    );
  }
}

/// Media-Einstellungen Screen (Auto-Download Thresholds + Download-Verzeichnis).
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
    widget.service.notificationSound.stopPreview();
    super.dispose();
  }

  void _save() {
    widget.service.notificationSound.updateSettings(_settings);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    return AppBarScaffold(
      title: locale.get('notification_settings_title'),
      opaqueBody: true,
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
                            widget.service.notificationSound.previewRingtone(v);
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
