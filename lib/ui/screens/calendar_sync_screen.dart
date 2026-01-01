// ignore_for_file: deprecated_member_use
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/calendar/sync/android_calendar_bridge.dart';
import 'package:cleona/core/calendar/sync/in_process_bridge.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';

/// Calendar Sync settings screen (§23.8).
///
/// Drives the daemon-side [CalendarSyncService] through IPC — the GUI itself
/// holds no sync state. CalDAV uses Basic auth over HTTPS; Google uses the
/// Loopback OAuth2 flow: the daemon opens a browser, the user consents,
/// and the daemon fires `calendar_sync_google_connected` when done.
class CalendarSyncScreen extends StatefulWidget {
  final ICleonaService service;
  const CalendarSyncScreen({super.key, required this.service});

  @override
  State<CalendarSyncScreen> createState() => _CalendarSyncScreenState();
}

class _CalendarSyncScreenState extends State<CalendarSyncScreen> {
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _caldavServerState = {};
  bool _loading = true;
  String? _lastError;

  InProcessCalendarSyncBridge? _bridge;
  CleonaAppState? _appState;
  String? _lastIdentityKey;

  @override
  void initState() {
    super.initState();
    _initBridgeFor(widget.service);
    _refreshStatus();
    _subscribeEvents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to global identity-switch events. On Android the in-process
    // service rebinds; on Desktop the IpcClient stays the same but the
    // daemon-side active identity changes. In both cases we want to refresh
    // and (Android) re-bridge so the screen reflects the picked identity.
    final next = context.read<CleonaAppState?>();
    if (next != _appState) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = next;
      _appState?.addListener(_onAppStateChanged);
      _lastIdentityKey =
          IdentityManager().getActiveIdentity()?.nodeIdHex;
    }
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final activeKey = IdentityManager().getActiveIdentity()?.nodeIdHex;
    if (activeKey == _lastIdentityKey) return;
    _lastIdentityKey = activeKey;
    final svc = _appState?.service ?? widget.service;
    _initBridgeFor(svc);
    setState(() {
      _loading = true;
      _status = {};
      _caldavServerState = {};
      _lastError = null;
    });
    _refreshStatus();
    _subscribeEvents();
  }

  void _initBridgeFor(ICleonaService? svc) {
    _bridge?.dispose();
    _bridge = (svc is CleonaService)
        ? InProcessCalendarSyncBridge(svc)
        : null;
  }

  /// Duck-typed Calendar-Sync transport. On Desktop this is an [IpcClient];
  /// on Android it's an [InProcessCalendarSyncBridge] that mirrors the same
  /// method surface 1:1 and delegates directly to the in-process service.
  dynamic get _ipc {
    if (_bridge != null) return _bridge;
    return widget.service is IpcClient ? widget.service as IpcClient : null;
  }

  /// True when local-CalDAV-server + Google-OAuth sections should be hidden
  /// (Android has no long-running HTTP listener + no loopback browser redirect).
  bool get _isOnAndroid => _bridge?.isOnAndroid == true;

  Future<void> _refreshStatus() async {
    final ipc = _ipc;
    if (ipc == null) {
      setState(() {
        _loading = false;
        _lastError = 'Sync UI requires the IPC client (desktop GUI).';
      });
      return;
    }
    try {
      final s = await ipc.getCalendarSyncStatus();
      Map<String, dynamic> srv = const {};
      try {
        srv = await ipc.getCalDAVServerState();
      } catch (_) {
        // CalDAV server IPC callbacks may not be wired on older daemons.
        // Ignoring the error keeps the sync UI functional for users still
        // on older builds.
      }
      if (!mounted) return;
      setState(() {
        _status = s;
        _caldavServerState = srv;
        _loading = false;
        _lastError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = '$e';
      });
    }
  }

  void _subscribeEvents() {
    final ipc = _ipc;
    if (ipc == null) return;
    ipc.onCalendarSyncCompleted = (_) {
      if (mounted) _refreshStatus();
    };
    ipc.onCalendarSyncGoogleConnected = (email) {
      if (mounted) _refreshStatus();
    };
    ipc.onCalendarSyncGoogleError = (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google: $err')),
      );
    };
    ipc.onCalendarSyncConflictPending = (payload) {
      if (!mounted) return;
      _showPendingConflictDialog(payload);
    };
  }

  @override
  void dispose() {
    final ipc = _ipc;
    if (ipc != null) {
      ipc.onCalendarSyncCompleted = null;
      ipc.onCalendarSyncGoogleConnected = null;
      ipc.onCalendarSyncGoogleError = null;
      ipc.onCalendarSyncConflictPending = null;
    }
    _appState?.removeListener(_onAppStateChanged);
    _bridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final caldavConfigured = _status['caldavConfigured'] == true;
    final googleConfigured = _status['googleConfigured'] == true;
    final lastSyncMs = (_status['lastSyncMs'] as num?)?.toInt() ?? 0;
    final lastSyncOk = _status['lastSyncOk'] == true;
    final errorText = _status['lastError'] as String?;
    final count = (_status['syncedEventCount'] as num?)?.toInt() ?? 0;

    return AppBarScaffold(
      title: locale.get('calendar_sync_title'),
      opaqueBody: true,
      body: SafeArea(
        top: false,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_lastError != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_lastError!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                    ),

                  _IdentityScopeHeader(
                    captionKey: 'calendar_sync_identity_caption',
                  ),
                  const SizedBox(height: 8),

                  // ── Status Summary ────────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                lastSyncOk ? Icons.check_circle : Icons.error,
                                color: lastSyncOk
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${locale.get('calendar_sync_last_sync')}: '
                                  '${_formatLastSync(lastSyncMs, locale)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.sync),
                                tooltip: locale.get('calendar_sync_trigger_now'),
                                onPressed: (caldavConfigured || googleConfigured)
                                    ? _syncNow
                                    : null,
                              ),
                            ],
                          ),
                          if (count > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('$count event(s) synced',
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                            ),
                          if (errorText != null && errorText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(errorText,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  _buildCalDavSection(locale, caldavConfigured),
                  if (!_isOnAndroid) ...[
                    const SizedBox(height: 16),
                    _buildGoogleSection(locale, googleConfigured),
                  ],
                  const SizedBox(height: 16),
                  _buildLocalIcsSection(locale),
                  if (!_isOnAndroid) ...[
                    const SizedBox(height: 16),
                    _buildCalDAVServerSection(locale),
                  ],
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    _AndroidCalendarBridgeCard(
                      service: widget.service,
                      locale: locale,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildConflictsSection(locale),

                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      locale.get('calendar_sync_hint_app_password'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildLocalIcsSection(AppLocale locale) {
    final configured = _status['localIcsConfigured'] == true;
    final ics = _status['localIcs'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(locale.get('calendar_sync_local_ics'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  configured
                      ? locale.get('calendar_sync_configured')
                      : locale.get('calendar_sync_not_configured'),
                  style: TextStyle(
                    color: configured
                        ? Colors.green
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (configured && ics != null) ...[
              const SizedBox(height: 8),
              Text(ics['filePath'] as String? ?? '',
                  style: Theme.of(context).textTheme.bodySmall),
              Text('${locale.get('calendar_sync_direction')}: '
                  '${_directionLabel(ics['direction'] as String?, locale)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                locale.get('calendar_sync_local_ics_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (configured)
                  TextButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: Text(locale.get('calendar_sync_disconnect')),
                    onPressed: _removeLocalIcs,
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.settings),
                  label: Text(configured
                      ? locale.get('calendar_edit_event')
                      : locale.get('calendar_sync_connect')),
                  onPressed: () => _openLocalIcsDialog(
                      initial: configured
                          ? (ics?.cast<String, dynamic>() ?? {})
                          : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictsSection(AppLocale locale) {
    final resolved = (_status['conflictsResolved'] as num?)?.toInt() ?? 0;
    final pending = (_status['pendingConflicts'] as num?)?.toInt() ?? 0;
    if (resolved == 0 && pending == 0) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  pending > 0 ? Icons.warning : Icons.history,
                  color: pending > 0
                      ? Theme.of(context).colorScheme.tertiary
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(locale.get('calendar_sync_conflicts'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pending > 0)
              Text('$pending ${locale.get('calendar_sync_conflicts_pending')}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary)),
            Text('$resolved ${locale.get('calendar_sync_conflicts_resolved')}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.list),
                  label: Text(locale.get('calendar_sync_show_conflicts')),
                  onPressed: _openConflictsDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalDAVServerSection(AppLocale locale) {
    final st = _caldavServerState;
    if (st.isEmpty) {
      return const SizedBox.shrink();
    }
    final enabled = st['enabled'] == true;
    final running = st['running'] == true;
    final port = (st['port'] as num?)?.toInt() ?? 0;
    final baseUrl = st['baseUrl'] as String? ?? '';
    final token = st['token'] as String? ?? '';
    final identities = (st['identities'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .toList() ??
        const [];

    Future<void> copy(String text, String label) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label kopiert')),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(running
                    ? Icons.cloud_done
                    : (enabled ? Icons.cloud_queue : Icons.cloud_off)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locale.get('caldav_server_title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: (value) async {
                    try {
                      final s = await _ipc!.setCalDAVServerEnabled(value);
                      if (!mounted) return;
                      setState(() => _caldavServerState = s);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              locale.get('caldav_server_subtitle'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (enabled) ...[
              const SizedBox(height: 12),
              Text(
                  '${locale.get('caldav_server_status')}: '
                  '${running ? locale.get('caldav_server_running') : locale.get('caldav_server_stopped')} '
                  '(${locale.get('caldav_server_port')}: $port)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              if (baseUrl.isNotEmpty)
                _KeyValueRow(
                  label: locale.get('caldav_server_base_url'),
                  value: baseUrl,
                  onCopy: () => copy(baseUrl, locale.get('caldav_server_base_url')),
                ),
              for (final id in identities)
                _KeyValueRow(
                  label: '${id['displayName']} (${id['shortId']})',
                  value: id['calendarUrl'] as String? ?? '',
                  onCopy: () => copy(id['calendarUrl'] as String? ?? '',
                      locale.get('caldav_server_calendar_url')),
                ),
              const SizedBox(height: 8),
              _KeyValueRow(
                label: locale.get('caldav_server_password'),
                value: token.isEmpty
                    ? '—'
                    : (token.length > 8
                        ? '${token.substring(0, 8)}…'
                        : token),
                onCopy: token.isEmpty
                    ? null
                    : () => copy(token, locale.get('caldav_server_password')),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: Text(locale.get('caldav_server_regenerate')),
                    onPressed: () async {
                      try {
                        final s = await _ipc!.regenerateCalDAVServerToken();
                        if (!mounted) return;
                        setState(() => _caldavServerState = s);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalDavSection(AppLocale locale, bool configured) {
    final caldav = _status['caldav'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(locale.get('calendar_sync_caldav'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  configured
                      ? locale.get('calendar_sync_configured')
                      : locale.get('calendar_sync_not_configured'),
                  style: TextStyle(
                    color: configured
                        ? Colors.green
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (configured && caldav != null) ...[
              const SizedBox(height: 8),
              Text('${caldav['username']} @ ${caldav['serverUrl']}',
                  style: Theme.of(context).textTheme.bodySmall),
              Text('${locale.get('calendar_sync_direction')}: '
                  '${_directionLabel(caldav['direction'] as String?, locale)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (configured)
                  TextButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: Text(locale.get('calendar_sync_disconnect')),
                    onPressed: _removeCaldav,
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.settings),
                  label: Text(configured
                      ? locale.get('calendar_edit_event')
                      : locale.get('calendar_sync_connect')),
                  onPressed: () => _openCaldavDialog(
                      initial: configured
                          ? (caldav?.cast<String, dynamic>() ?? {})
                          : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleSection(AppLocale locale, bool configured) {
    final google = _status['google'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(locale.get('calendar_sync_google'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  configured
                      ? locale.get('calendar_sync_configured')
                      : locale.get('calendar_sync_not_configured'),
                  style: TextStyle(
                    color: configured
                        ? Colors.green
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (configured && google != null) ...[
              const SizedBox(height: 8),
              Text('${google['accountEmail']} · ${google['calendarId']}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (configured)
                  TextButton.icon(
                    icon: const Icon(Icons.link_off),
                    label: Text(locale.get('calendar_sync_disconnect')),
                    onPressed: _removeGoogle,
                  ),
                if (!configured)
                  FilledButton.icon(
                    icon: const Icon(Icons.login),
                    label: Text(locale.get('calendar_sync_google_signin')),
                    onPressed: _openGoogleDialog,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _directionLabel(String? dir, AppLocale locale) {
    switch (dir) {
      case 'import':
        return locale.get('calendar_sync_direction_import');
      case 'export':
        return locale.get('calendar_sync_direction_export');
      default:
        return locale.get('calendar_sync_direction_bidirectional');
    }
  }

  String _formatLastSync(int ms, AppLocale locale) {
    if (ms <= 0) return locale.get('calendar_sync_never');
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${dt.day}.${dt.month}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _syncNow() async {
    final ipc = _ipc;
    if (ipc == null) return;
    await ipc.triggerCalendarSync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocale.read(context).get('calendar_sync_trigger_now'))),
    );
  }

  Future<void> _removeCaldav() async {
    final ipc = _ipc;
    if (ipc == null) return;
    try {
      await ipc.removeCaldavSync();
    } catch (_) {/* ignore — status refresh will show */}
    if (mounted) _refreshStatus();
  }

  Future<void> _removeGoogle() async {
    final ipc = _ipc;
    if (ipc == null) return;
    try {
      await ipc.removeGoogleSync();
    } catch (_) {/* ignore */}
    if (mounted) _refreshStatus();
  }

  void _openCaldavDialog({Map<String, dynamic>? initial}) {
    showDialog(
      context: context,
      builder: (_) => _CaldavDialog(
        ipc: _ipc,
        initial: initial,
        onDone: _refreshStatus,
      ),
    );
  }

  void _openLocalIcsDialog({Map<String, dynamic>? initial}) {
    showDialog(
      context: context,
      builder: (_) => _LocalIcsDialog(
        ipc: _ipc,
        initial: initial,
        onDone: _refreshStatus,
      ),
    );
  }

  Future<void> _removeLocalIcs() async {
    final ipc = _ipc;
    if (ipc == null) return;
    try {
      await ipc.removeLocalIcsSync();
    } catch (_) {/* ignore */}
    if (mounted) _refreshStatus();
  }

  void _openConflictsDialog() {
    showDialog(
      context: context,
      builder: (_) => _ConflictsDialog(
        ipc: _ipc,
        onChanged: _refreshStatus,
      ),
    );
  }

  void _showPendingConflictDialog(Map<String, dynamic> payload) {
    showDialog(
      context: context,
      builder: (_) => _PendingConflictDialog(
        ipc: _ipc,
        conflict: payload,
        onDecided: _refreshStatus,
      ),
    );
  }

  void _openGoogleDialog() {
    showDialog(
      context: context,
      builder: (_) => _GoogleDialog(
        ipc: _ipc,
        onDone: _refreshStatus,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// CalDAV setup dialog
// ════════════════════════════════════════════════════════════════════

class _CaldavDialog extends StatefulWidget {
  // Duck-typed: IpcClient on Desktop, InProcessCalendarSyncBridge on Android.
  final dynamic ipc;
  final Map<String, dynamic>? initial;
  final VoidCallback onDone;

  const _CaldavDialog({
    required this.ipc,
    required this.initial,
    required this.onDone,
  });

  @override
  State<_CaldavDialog> createState() => _CaldavDialogState();
}

class _CaldavDialogState extends State<_CaldavDialog> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  String _direction = 'bidirectional';
  List<Map<String, dynamic>> _calendars = [];
  String? _selectedCalendarUrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _server.text = widget.initial!['serverUrl'] as String? ?? '';
      _user.text = widget.initial!['username'] as String? ?? '';
      _direction = widget.initial!['direction'] as String? ?? 'bidirectional';
      _selectedCalendarUrl = widget.initial!['calendarUrl'] as String?;
    }
    // Re-render the http-in-the-clear warning live as the user types.
    _server.addListener(_onServerUrlChanged);
  }

  void _onServerUrlChanged() {
    if (mounted) setState(() {});
  }

  /// True when the current server URL would send Basic-auth credentials
  /// in the clear to a non-loopback host.
  bool get _showHttpWarning {
    final raw = _server.text.trim();
    if (!raw.toLowerCase().startsWith('http://')) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return true;
    final host = uri.host.toLowerCase();
    return host != '127.0.0.1' && host != 'localhost' && host != '::1';
  }

  @override
  void dispose() {
    _server.removeListener(_onServerUrlChanged);
    _server.dispose();
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cals = await ipc.caldavListCalendars(
        serverUrl: _server.text.trim(),
        username: _user.text.trim(),
        password: _pw.text,
      );
      setState(() {
        _calendars = cals;
        _busy = false;
        if (_selectedCalendarUrl == null && cals.isNotEmpty) {
          _selectedCalendarUrl = cals.first['url'] as String?;
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _save() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ipc.configureCaldav(
        serverUrl: _server.text.trim(),
        username: _user.text.trim(),
        password: _pw.text,
        calendarUrl: _selectedCalendarUrl,
        direction: _direction,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AlertDialog(
      title: Text(locale.get('calendar_sync_caldav')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _server,
                decoration: InputDecoration(
                  labelText: locale.get('calendar_sync_server_url'),
                  hintText: 'https://cloud.example.com/remote.php/dav',
                ),
                keyboardType: TextInputType.url,
              ),
              if (_showHttpWarning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            locale.get('calendar_sync_http_warning'),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              TextField(
                controller: _user,
                decoration: InputDecoration(
                    labelText: locale.get('calendar_sync_username')),
              ),
              TextField(
                controller: _pw,
                decoration: InputDecoration(
                    labelText: locale.get('calendar_sync_password')),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: InputDecoration(
                    labelText: locale.get('calendar_sync_direction')),
                items: [
                  DropdownMenuItem(
                    value: 'bidirectional',
                    child: Text(locale.get(
                        'calendar_sync_direction_bidirectional')),
                  ),
                  DropdownMenuItem(
                    value: 'import',
                    child:
                        Text(locale.get('calendar_sync_direction_import')),
                  ),
                  DropdownMenuItem(
                    value: 'export',
                    child:
                        Text(locale.get('calendar_sync_direction_export')),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _direction = v ?? 'bidirectional'),
              ),
              const SizedBox(height: 8),
              if (_calendars.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedCalendarUrl,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: locale.get('calendar_sync_select_calendar')),
                  items: [
                    for (final cal in _calendars)
                      DropdownMenuItem(
                        value: cal['url'] as String?,
                        child: Text(
                          cal['displayName'] as String? ?? 'Unnamed',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedCalendarUrl = v),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(locale.get('cancel')),
        ),
        TextButton(
          onPressed: _busy ? null : _discover,
          child: Text(locale.get('calendar_sync_select_calendar')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(locale.get('save')),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Google OAuth dialog
// ════════════════════════════════════════════════════════════════════

class _GoogleDialog extends StatefulWidget {
  final dynamic ipc;
  final VoidCallback onDone;

  const _GoogleDialog({required this.ipc, required this.onDone});

  @override
  State<_GoogleDialog> createState() => _GoogleDialogState();
}

class _GoogleDialogState extends State<_GoogleDialog> {
  final _clientId = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _waiting = false;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authUrl =
          await ipc.startGoogleOauth(clientId: _clientId.text.trim());
      if (!await canLaunchUrl(Uri.parse(authUrl))) {
        throw Exception('Cannot open system browser');
      }
      await launchUrl(Uri.parse(authUrl),
          mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = true;
      });
      // Completion arrives via calendar_sync_google_connected event; the
      // parent screen handles it and refreshes status. We auto-close.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context);
          widget.onDone();
        }
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AlertDialog(
      title: Text(locale.get('calendar_sync_google')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _clientId,
              decoration: InputDecoration(
                labelText: locale.get('calendar_sync_google_client_id'),
                hintText: '1234567890-xxxxxxx.apps.googleusercontent.com',
              ),
            ),
            if (_waiting)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  locale.get('calendar_sync_google_opening_browser'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(locale.get('cancel')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.login),
          label: Text(locale.get('calendar_sync_google_signin')),
          onPressed: _busy || _clientId.text.trim().isEmpty ? null : _signIn,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Local ICS file setup dialog
// ════════════════════════════════════════════════════════════════════

class _LocalIcsDialog extends StatefulWidget {
  final dynamic ipc;
  final Map<String, dynamic>? initial;
  final VoidCallback onDone;

  const _LocalIcsDialog({
    required this.ipc,
    required this.initial,
    required this.onDone,
  });

  @override
  State<_LocalIcsDialog> createState() => _LocalIcsDialogState();
}

class _LocalIcsDialogState extends State<_LocalIcsDialog> {
  final _path = TextEditingController();
  String _direction = 'export';
  bool _askOnConflict = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _path.text = widget.initial!['filePath'] as String? ?? '';
      _direction = widget.initial!['direction'] as String? ?? 'export';
      _askOnConflict = widget.initial!['askOnConflict'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _browseSavePath() async {
    final locale = AppLocale.read(context);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: locale.get('calendar_sync_local_ics_pick_file'),
      fileName: 'cleona-calendar.ics',
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );
    if (path != null && mounted) {
      setState(() => _path.text = path);
    }
  }

  Future<void> _browseOpenPath() async {
    final locale = AppLocale.read(context);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: locale.get('calendar_sync_local_ics_pick_file'),
      type: FileType.custom,
      allowedExtensions: ['ics'],
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _path.text = result.files.first.path ?? '');
    }
  }

  Future<void> _save() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ipc.configureLocalIcs(
        filePath: _path.text.trim(),
        direction: _direction,
        askOnConflict: _askOnConflict,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AlertDialog(
      title: Text(locale.get('calendar_sync_local_ics')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ask for direction first — the file-picker dialog differs
              // for import (pick existing file) vs export (save new file).
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: InputDecoration(
                    labelText: locale.get('calendar_sync_direction')),
                items: [
                  DropdownMenuItem(
                    value: 'export',
                    child: Text(
                        locale.get('calendar_sync_direction_export')),
                  ),
                  DropdownMenuItem(
                    value: 'import',
                    child: Text(
                        locale.get('calendar_sync_direction_import')),
                  ),
                  DropdownMenuItem(
                    value: 'bidirectional',
                    child: Text(locale
                        .get('calendar_sync_direction_bidirectional')),
                  ),
                ],
                onChanged: (v) => setState(() => _direction = v ?? 'export'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _path,
                      decoration: InputDecoration(
                        labelText: locale.get('calendar_sync_local_ics_path'),
                        hintText: '/home/user/cleona-calendar.ics',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: locale.get('calendar_sync_local_ics_pick_file'),
                    onPressed: _direction == 'import'
                        ? _browseOpenPath
                        : _browseSavePath,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(locale.get('calendar_sync_ask_on_conflict')),
                subtitle:
                    Text(locale.get('calendar_sync_ask_on_conflict_hint')),
                value: _askOnConflict,
                onChanged: (v) => setState(() => _askOnConflict = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(locale.get('cancel')),
        ),
        FilledButton(
          onPressed:
              _busy || _path.text.trim().isEmpty ? null : _save,
          child: Text(locale.get('save')),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Conflict log viewer — lists recorded LWW conflicts, lets the user
// restore a losing version.
// ════════════════════════════════════════════════════════════════════

class _ConflictsDialog extends StatefulWidget {
  final dynamic ipc;
  final VoidCallback onChanged;
  const _ConflictsDialog({required this.ipc, required this.onChanged});

  @override
  State<_ConflictsDialog> createState() => _ConflictsDialogState();
}

class _ConflictsDialogState extends State<_ConflictsDialog> {
  List<Map<String, dynamic>> _conflicts = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    try {
      final data = await ipc.listCalendarConflicts();
      if (!mounted) return;
      setState(() {
        _conflicts = data['conflicts'] ?? [];
        _pending = data['pending'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(String id) async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    await ipc.restoreCalendarConflict(id);
    widget.onChanged();
    await _reload();
  }

  Future<void> _clearAll() async {
    final ipc = widget.ipc;
    if (ipc == null) return;
    await ipc.clearCalendarConflicts();
    widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    return AlertDialog(
      title: Text(locale.get('calendar_sync_conflicts')),
      content: SizedBox(
        width: 520,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_conflicts.isEmpty && _pending.isEmpty
                ? Center(
                    child: Text(locale.get('calendar_sync_conflicts_empty')))
                : ListView(
                    children: [
                      if (_pending.isNotEmpty) ...[
                        Text(
                          locale.get('calendar_sync_conflicts_pending'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final p in _pending) _pendingTile(p, locale),
                        const Divider(),
                      ],
                      for (final c in _conflicts) _resolvedTile(c, locale),
                    ],
                  )),
      ),
      actions: [
        if (_conflicts.isNotEmpty)
          TextButton(
            onPressed: _clearAll,
            child: Text(locale.get('calendar_sync_conflicts_clear')),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locale.get('close')),
        ),
      ],
    );
  }

  Widget _resolvedTile(Map<String, dynamic> c, AppLocale locale) {
    final title = c['title'] as String? ?? c['eventId'] as String? ?? '?';
    final src = c['source'] as String? ?? '?';
    final winner = c['winner'] as String? ?? '';
    final restored = c['restored'] == true;
    final when = DateTime.fromMillisecondsSinceEpoch(
        (c['detectedAtMs'] as num?)?.toInt() ?? 0);
    return ListTile(
      leading: Icon(restored ? Icons.restore : Icons.merge_type),
      title: Text(title),
      subtitle: Text('$src · ${winner == "local" ? locale.get(
            "calendar_sync_winner_local",
          ) : locale.get("calendar_sync_winner_external")} · '
          '${when.day}.${when.month}. ${when.hour.toString().padLeft(2, '0')}:'
          '${when.minute.toString().padLeft(2, '0')}'),
      trailing: restored
          ? const Icon(Icons.check, color: Colors.green)
          : TextButton(
              onPressed: () => _restore(c['id'] as String),
              child: Text(locale.get('calendar_sync_restore_losing')),
            ),
    );
  }

  Widget _pendingTile(Map<String, dynamic> p, AppLocale locale) {
    final localEvent = (p['localEvent'] as Map).cast<String, dynamic>();
    final externalEvent = (p['externalEvent'] as Map).cast<String, dynamic>();
    final title = localEvent['title'] as String? ?? '?';
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(p['source'] as String? ?? ''),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await widget.ipc?.resolvePendingCalendarConflict(
                        p['id'] as String, 'local');
                    widget.onChanged();
                    await _reload();
                  },
                  child: Text(locale.get('calendar_sync_keep_local')),
                ),
                TextButton(
                  onPressed: () async {
                    await widget.ipc?.resolvePendingCalendarConflict(
                        p['id'] as String, 'external');
                    widget.onChanged();
                    await _reload();
                  },
                  child: Text(locale.get('calendar_sync_keep_external')),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_compareLine(localEvent, externalEvent)})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _compareLine(Map<String, dynamic> a, Map<String, dynamic> b) {
    final diffs = <String>[];
    for (final k in ['title', 'description', 'location', 'startTime', 'endTime']) {
      if (a[k] != b[k]) diffs.add(k);
    }
    return diffs.isEmpty ? 'metadata' : diffs.join(', ');
  }
}

// ════════════════════════════════════════════════════════════════════
// Pending-conflict dialog — opens immediately when a provider queues
// a conflict with askOnConflict=true.
// ════════════════════════════════════════════════════════════════════

class _PendingConflictDialog extends StatelessWidget {
  final dynamic ipc;
  final Map<String, dynamic> conflict;
  final VoidCallback onDecided;

  const _PendingConflictDialog({
    required this.ipc,
    required this.conflict,
    required this.onDecided,
  });

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final local = (conflict['localEvent'] as Map).cast<String, dynamic>();
    final external =
        (conflict['externalEvent'] as Map).cast<String, dynamic>();
    return AlertDialog(
      title: Text(locale.get('calendar_sync_pending_conflict_title')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${local['title']}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('${conflict['source']}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            _sideBlock(context, locale.get('calendar_sync_winner_local'), local),
            const SizedBox(height: 8),
            _sideBlock(
                context, locale.get('calendar_sync_winner_external'), external),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ipc?.resolvePendingCalendarConflict(
                conflict['id'] as String, 'local');
            onDecided();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(locale.get('calendar_sync_keep_local')),
        ),
        FilledButton(
          onPressed: () async {
            await ipc?.resolvePendingCalendarConflict(
                conflict['id'] as String, 'external');
            onDecided();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(locale.get('calendar_sync_keep_external')),
        ),
      ],
    );
  }

  Widget _sideBlock(BuildContext context, String label, Map<String, dynamic> ev) {
    final startMs = (ev['startTime'] as num?)?.toInt() ?? 0;
    final endMs = (ev['endTime'] as num?)?.toInt() ?? 0;
    final s = DateTime.fromMillisecondsSinceEpoch(startMs);
    final e = DateTime.fromMillisecondsSinceEpoch(endMs);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${ev['title']}'),
          if ((ev['location'] as String?)?.isNotEmpty == true)
            Text('${ev['location']}'),
          Text('${s.day}.${s.month}.${s.year} '
              '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}'
              ' – ${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}'),
          if ((ev['description'] as String?)?.isNotEmpty == true)
            Text('${ev['description']}',
                maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Android-only card that mirrors the active identity's calendar into
/// the Android system calendar (Samsung/Google Calendar) via
/// CalendarContract. One-way push only — edits happen in the Cleona UI.
class _AndroidCalendarBridgeCard extends StatefulWidget {
  final ICleonaService service;
  final AppLocale locale;
  const _AndroidCalendarBridgeCard({
    required this.service,
    required this.locale,
  });

  @override
  State<_AndroidCalendarBridgeCard> createState() =>
      _AndroidCalendarBridgeCardState();
}

class _AndroidCalendarBridgeCardState
    extends State<_AndroidCalendarBridgeCard> {
  final _bridge = AndroidCalendarBridge();
  bool _hasPermission = false;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final ok = await _bridge.hasPermission();
    if (!mounted) return;
    setState(() => _hasPermission = ok);
  }

  String _shortIdFor(String fullNodeId) =>
      fullNodeId.length <= 16 ? fullNodeId : fullNodeId.substring(0, 16);

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final activeNodeId = widget.service.nodeIdHex;
      final display = widget.service.displayName;
      final calendar = widget.service.calendarManager;
      if (activeNodeId.isEmpty) {
        setState(() => _status = 'No active identity');
        return;
      }
      final result = await _bridge.syncAll(
        shortId: _shortIdFor(activeNodeId),
        displayName: display,
        calendar: calendar,
      );
      if (!mounted) return;
      if (result.needsPermission) {
        await _bridge.requestPermission();
        await _refreshPermission();
        setState(() => _status = widget.locale
            .get('android_calendar_permission_requested'));
      } else if (!result.ok) {
        setState(() => _status =
            result.error ?? widget.locale.get('android_calendar_failed'));
      } else {
        setState(() => _status =
            '${widget.locale.get('android_calendar_synced')}: '
            '${result.upserted}↑ / ${result.deleted}✕');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final activeNodeId = widget.service.nodeIdHex;
      if (activeNodeId.isEmpty) return;
      await _bridge.removeCalendar(_shortIdFor(activeNodeId));
      if (!mounted) return;
      setState(() => _status = widget.locale.get('android_calendar_removed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locale.get('android_calendar_title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              locale.get('android_calendar_subtitle'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!_hasPermission) ...[
              const SizedBox(height: 8),
              Text(
                locale.get('android_calendar_needs_permission'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontSize: 12),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.sync),
                  label: Text(locale.get('android_calendar_sync_now')),
                  onPressed: _busy ? null : _syncNow,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(locale.get('android_calendar_remove')),
                  onPressed: _busy ? null : _disable,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
              maxLines: 1,
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy',
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Identity-scope header
// ════════════════════════════════════════════════════════════════════
//
// Shows which identity the current screen is operating on and lets the
// user switch in-place. Default selection follows the active identity
// from the home tab bar; switching here calls [CleonaAppState.switchIdentity]
// so the home tab follows along (no per-screen identity override).
class _IdentityScopeHeader extends StatelessWidget {
  final String captionKey;
  const _IdentityScopeHeader({required this.captionKey});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.of(context);
    final mgr = IdentityManager();
    final identities = mgr.loadIdentities();
    final active = mgr.getActiveIdentity();
    if (active == null) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;
    final activeColor =
        Skins.byId(active.skinId).effectiveColor(brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: activeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locale.get(captionKey),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                  Text(active.displayName,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            if (identities.length > 1)
              DropdownButton<String>(
                value: active.id,
                underline: const SizedBox.shrink(),
                items: [
                  for (final id in identities)
                    DropdownMenuItem(
                      value: id.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Skins.byId(id.skinId)
                                  .effectiveColor(brightness),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(id.displayName),
                        ],
                      ),
                    ),
                ],
                onChanged: (newId) {
                  if (newId == null || newId == active.id) return;
                  final picked =
                      identities.firstWhere((i) => i.id == newId);
                  appState.switchIdentity(picked);
                },
              ),
          ],
        ),
      ),
    );
  }
}
