import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/ipc/ipc_client.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/screens/chat_screen.dart';
import 'package:cleona/ui/screens/settings_screen.dart';
import 'package:cleona/ui/components/language_selector.dart';
import 'package:cleona/ui/screens/network_stats_screen.dart';
import 'package:cleona/ui/screens/qr_contact_screen.dart';
import 'package:cleona/ui/theme/skins.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/theme_access.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/components/chat_list_tile.dart';
import 'package:cleona/ui/screens/identity_detail_screen.dart';
import 'package:cleona/ui/screens/donation_screen.dart';
import 'package:cleona/ui/screens/nfc_exchange_screen.dart';
import 'package:cleona/ui/screens/calendar_screen.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_dialog.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_router_select_screen.dart';
import 'package:cleona/ui/screens/nat_wizard/nat_wizard_instructions_screen.dart';
import 'package:cleona/core/network/router_db.dart';
import 'package:cleona/core/network/nfc_platform_bridge.dart' show isNfcAvailable;
import 'package:cleona/core/network/contact_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cleona/ui/components/skin_fab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _lastGoBackCounter = 0;
  /// Tracks `CleonaAppState.natWizardResetCounter` — bumped by the test-only
  /// `gui_action('reset_nat_wizard_latch')` to force `_natWizardShown` back
  /// to false between gui-53 tests.
  int _lastNatWizardResetCounter = 0;

  /// §27.9 NAT-Wizard: latch so the dialog never shows twice per process,
  /// even if the trigger event fires again across identity switches.
  bool _natWizardShown = false;
  /// Track which service instance we have wired our callback on, so we don't
  /// repeatedly overwrite the callback on every `build()`.
  ICleonaService? _natWizardWiredService;

  static const _tabs = ['Recent', 'Favoriten', 'Chats', 'Gruppen', 'Channels', 'Inbox'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Wire NAT-wizard callbacks once per service instance. If the service is
  /// swapped (e.g. user switches identity), re-wire on the new instance.
  ///
  /// Two distinct callbacks:
  ///   - [onNatWizardTriggered]      — auto-trigger (§27.9.1 conditions).
  ///     Guarded by `_natWizardShown` one-shot latch so a sustained
  ///     relay-only state doesn't spam the dialog.
  ///   - [onNatWizardUserRequested]  — explicit icon-tap from the user.
  ///     Bypasses the latch entirely: a deliberate tap is always allowed
  ///     to re-open the dialog, even after the user dismissed the auto
  ///     trigger earlier in the session.
  void _wireNatWizardCallback(ICleonaService service) {
    if (identical(_natWizardWiredService, service)) return;
    _natWizardWiredService = service;
    service.onNatWizardTriggered = () {
      if (_natWizardShown) return;
      _natWizardShown = true;
      if (!mounted) return;
      _showNatWizardDialog(service);
    };
    service.onNatWizardUserRequested = () {
      if (!mounted) return;
      _natWizardShown = true;
      _showNatWizardDialog(service);
    };
  }

  void _showNatWizardDialog(ICleonaService service) {
    final localIp = service.localIps.isNotEmpty ? service.localIps.first : null;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      // barrierDismissible kept `true` (was `false` originally) so a user-
      // initiated tap can be cancelled by tapping outside, matching the
      // explain-dialog UX for the other tiers.
      barrierDismissible: true,
      builder: (ctx) {
        return NatWizardDialog(
        currentPort: service.port,
        localIp: localIp,
        onShowInstructions: () async {
          Navigator.of(ctx).pop();
          final routerDb = await RouterDb.load();
          if (!mounted) return;
          final detectedInfo = service.getNetworkStats().upnpRouterInfo;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NatWizardRouterSelectScreen(
                routerDb: routerDb,
                detectedInfo: detectedInfo,
                onEntrySelected: (entry) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NatWizardInstructionsScreen(
                        entry: entry,
                        currentPort: service.port,
                        localIp: localIp,
                        onRecheck: () => service.recheckNatWizard(),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
        onLater: () {
          // +7 days.
          service.dismissNatWizard(durationSeconds: 7 * 24 * 3600);
          Navigator.of(ctx).pop();
        },
        onNeverAgain: () {
          // Forever — duration 0 is interpreted as "never again" by the service.
          service.dismissNatWizard(durationSeconds: 0);
          Navigator.of(ctx).pop();
        },
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final service = appState.service;
    if (service == null) return const SizedBox();

    // §27.9 NAT-Wizard: register single listener on the current service
    // instance (re-wires on identity switch). The latch lives in _this_ state.
    _wireNatWizardCallback(service);

    // Test-only (E2E gui-53): clear the one-shot latch when the harness
    // bumps natWizardResetCounter via `gui_action('reset_nat_wizard_latch')`.
    if (appState.natWizardResetCounter != _lastNatWizardResetCounter) {
      _lastNatWizardResetCounter = appState.natWizardResetCounter;
      _natWizardShown = false;
    }

    // Reset to "Aktuell" tab when go_back IPC is triggered
    if (appState.goBackCounter != _lastGoBackCounter) {
      _lastGoBackCounter = appState.goBackCounter;
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
    }

    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final character = theme.character;
    final isPhotoMode = character.surfaceRenderMode == SurfaceRenderMode.photo;
    final isSlateMode = character.surfaceRenderMode == SurfaceRenderMode.cssSlate;
    final needsOverlay = isPhotoMode || isSlateMode;

    // Multi-layer drop shadow for text that sits over the photo surface.
    final overlayShadows = <Shadow>[
      const Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
      const Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 2)),
    ];

    final tabLabelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: needsOverlay ? Colors.white : null,
      shadows: isPhotoMode ? overlayShadows : null,
    );
    final tabUnselectedStyle = TextStyle(
      fontSize: 12,
      color: needsOverlay ? Colors.white.withValues(alpha: 0.7) : null,
      shadows: isPhotoMode ? overlayShadows : null,
    );

    // Sort: unread first, then by lastActivity DESC
    List<Conversation> sortUnreadFirst(List<Conversation> list) {
      list.sort((a, b) {
        final aUnread = a.unreadCount > 0 ? 0 : 1;
        final bUnread = b.unreadCount > 0 ? 0 : 1;
        if (aUnread != bUnread) return aUnread.compareTo(bUnread);
        return b.lastActivity.compareTo(a.lastActivity);
      });
      return list;
    }

    // Count unreads per category
    final allConvs = sortUnreadFirst(service.sortedConversations);
    final dmConvs = sortUnreadFirst(allConvs.where((c) => !c.isGroup && !c.isChannel).toList());
    final groupConvs = sortUnreadFirst(allConvs.where((c) => c.isGroup).toList());
    final channelConvs = sortUnreadFirst(allConvs.where((c) => c.isChannel).toList());
    final favConvs = sortUnreadFirst(allConvs.where((c) => c.isFavorite).toList());

    // Contacts tab: all accepted 1:1 contacts (with or without conversation)
    final dmIds = dmConvs.map((c) => c.id).toSet();
    final contactsWithoutConv = service.acceptedContacts
        .where((c) => !dmIds.contains(c.nodeIdHex))
        .map((c) => Conversation(
              id: c.nodeIdHex,
              displayName: c.effectiveName,
              profilePictureBase64: c.profilePictureBase64,
            ))
        .toList();
    final kontakteList = [...dmConvs, ...contactsWithoutConv];

    final pendingCount = service.pendingContacts.length;
    final totalUnread = allConvs.fold<int>(0, (s, c) => s + c.unreadCount);
    final dmUnread = dmConvs.fold<int>(0, (s, c) => s + c.unreadCount);
    final groupUnread = groupConvs.fold<int>(0, (s, c) => s + c.unreadCount);
    final channelUnread = channelConvs.fold<int>(0, (s, c) => s + c.unreadCount);

    return AppBarScaffold(
      title: 'Cleona',
      subtitle: service.displayName,
      actions: [
        // Language selector
        const LanguageSelector(),
        // Connection status icon (WiFi/Mobile/Offline)
        _ConnectionStatusIcon(appState: appState),
        // Network Stats — combined health indicator + peer count, opens stats page
        IconButton(
          icon: Badge(
            label: Text('${service.peerCount}'),
            backgroundColor: service.peerCount >= 10
                ? Colors.green
                : service.peerCount >= 3
                    ? Colors.orange
                    : colorScheme.error,
            textColor: Colors.white,
            child: const Icon(Icons.bar_chart),
          ),
          tooltip: AppLocale.read(context).get('stats_title'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: appState),
                ChangeNotifierProvider.value(value: AppLocale.read(context)),
              ],
              child: Scaffold(
                appBar: AppBar(title: Text(AppLocale.read(context).get('stats_title'))),
                body: SafeArea(top: false, child: NetworkStatsScreen(service: service)),
              ),
            )),
          ),
        ),
        // Calendar (§23)
        IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: locale.get('calendar'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: appState),
                ChangeNotifierProvider.value(value: AppLocale.read(context)),
              ],
              child: const CalendarScreen(),
            )),
          ),
        ),
        // Settings
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: locale.get('settings'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: appState),
                ChangeNotifierProvider.value(value: AppLocale.read(context)),
              ],
              child: SettingsScreen(service: service),
            )),
          ),
        ),
      ],
      body: Column(
        children: [
          // Identity tabs
          SizedBox(
            height: 36,
            child: _IdentityTabBar(appState: appState),
          ),
          // Category tabs
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            labelStyle: tabLabelStyle,
            unselectedLabelStyle: tabUnselectedStyle,
            labelColor: tabLabelStyle.color,
            unselectedLabelColor: tabUnselectedStyle.color,
            tabs: [
              _tabWithBadge(locale.get('tab_recent'), totalUnread),
              Tab(text: locale.get('tab_favorites')),
              _tabWithBadge(locale.get('tab_chats'), dmUnread),
              _tabWithBadge(locale.get('tab_groups'), groupUnread),
              _tabWithBadge(locale.get('tab_channels'), channelUnread),
              _tabWithBadge(locale.get('tab_inbox'), pendingCount),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Recent: all conversations (with donation banner)
                _ConversationListView(conversations: allConvs, service: service, emptyKey: 'no_chats', showDonationBanner: true),
                // Favorites: conversations marked as favorite
                _ConversationListView(conversations: favConvs, service: service, emptyKey: 'no_favorites'),
                // Chats: all accepted 1:1 contacts (with or without conversation)
                _ConversationListView(conversations: kontakteList, service: service, emptyKey: 'no_direct_chats'),
                // Groups: only groups
                _ConversationListView(conversations: groupConvs, service: service, emptyKey: 'no_groups'),
                // Channels: sub-tabs (Subscribed | My Channels | Search)
                _ChannelTabView(channelConvs: channelConvs, service: service),
                // Inbox: pending requests
                _InboxView(service: service),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context, service),
    );
  }

  Tab _tabWithBadge(String label, int count) {
    if (count == 0) return Tab(text: label);
    return Tab(
      child: Badge(
        label: Text('$count'),
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(label),
        ),
      ),
    );
  }

  Widget? _buildFab(BuildContext context, ICleonaService service) {
    final skin = Skins.byId(IdentityManager().getActiveIdentity()?.skinId);

    switch (_tabController.index) {
      case 0: // Recent — add contact
      case 2: // Contacts — add contact
        return SkinFab(
          onPressed: () => _showAddContactDialog(context),
          icon: skin.addContactIcon,
          heroTag: 'fab_contact',
        );
      case 3: // Groups — new group
        return SkinFab(
          onPressed: () => _showCreateGroupDialog(context, service),
          icon: skin.addGroupIcon,
          heroTag: 'fab_group',
        );
      case 4: // Channels — new channel
        return SkinFab(
          onPressed: () => _showCreateChannelDialog(context, service),
          icon: skin.addChannelIcon,
          heroTag: 'fab_channel',
        );
      default:
        return null;
    }
  }

  // ── Dialogs ──────────────────────────────────────────────────────

  void _showCreateGroupDialog(BuildContext context, ICleonaService service) {
    final nameController = TextEditingController();
    final contacts = service.acceptedContacts;
    final selected = <String>{};
    final locale = AppLocale.read(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('create_group')),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: locale.get('group_name_label'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(locale.get('select_members'),
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: contacts.length,
                    itemBuilder: (_, i) {
                      final c = contacts[i];
                      return CheckboxListTile(
                        title: Text(c.displayName),
                        value: selected.contains(c.nodeIdHex),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(c.nodeIdHex);
                          } else {
                            selected.remove(c.nodeIdHex);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty || selected.isEmpty) return;
                Navigator.pop(ctx);
                await service.createGroup(name, selected.toList());
              },
              child: Text(locale.get('create')),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateChannelDialog(BuildContext context, ICleonaService service) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final contacts = service.acceptedContacts;
    final selected = <String>{};
    final locale = AppLocale.read(context);
    var isPublic = false;
    var isAdult = true; // Default: NSFW ON (must be explicitly disabled)
    var language = 'de';
    final languages = ['de', 'en', 'es', 'hu', 'sv', 'multi'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(locale.get('create_channel')),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: locale.get('channel_name_label'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: locale.get('channel_description'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Language selector
                  DropdownButtonFormField<String>(
                    value: language, // ignore: deprecated_member_use
                    decoration: InputDecoration(
                      labelText: locale.get('channel_language'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: languages.map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l == 'multi' ? locale.get('language_multi') : l.toUpperCase()),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => language = v ?? 'de'),
                  ),
                  const SizedBox(height: 8),
                  // Public/Private toggle
                  SwitchListTile(
                    title: Text(locale.get('channel_public_toggle')),
                    value: isPublic,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setDialogState(() => isPublic = v),
                  ),
                  // NSFW toggle (only for public channels)
                  if (isPublic)
                    SwitchListTile(
                      title: Text(locale.get('channel_nsfw_toggle')),
                      subtitle: Text(locale.get('channel_nsfw_default_hint'),
                          style: Theme.of(ctx).textTheme.bodySmall),
                      value: isAdult,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => isAdult = v),
                    ),
                  const Divider(),
                  if (!isPublic || contacts.isNotEmpty) ...[
                    Text(locale.get('select_subscribers'),
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (_, i) {
                          final c = contacts[i];
                          return CheckboxListTile(
                            title: Text(c.displayName),
                            value: selected.contains(c.nodeIdHex),
                            dense: true,
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(c.nodeIdHex);
                              } else {
                                selected.remove(c.nodeIdHex);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                // Private channels need subscribers; public don't
                if (!isPublic && selected.isEmpty) return;
                Navigator.pop(ctx);
                final desc = descController.text.trim();
                await service.createChannel(name, selected.toList(),
                  isPublic: isPublic,
                  isAdult: isAdult,
                  language: language,
                  description: desc.isNotEmpty ? desc : null,
                );
              },
              child: Text(locale.get('create')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    final controller = TextEditingController();
    final locale = AppLocale.read(context);
    final service = context.read<CleonaAppState>().service;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('add_contact')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: Text(locale.get('qr_show_my_code')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (service == null) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => QrShowScreen(service: service),
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(locale.get('qr_scan_contact')),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (service == null) return;
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => QrScanScreen(service: service),
                      ));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // NFC button — only visible when NFC hardware is available + enabled
            FutureBuilder<bool>(
              future: isNfcAvailable(),
              builder: (context, snapshot) {
                if (snapshot.data != true) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.nfc),
                      label: Text(locale.get('nfc_contact_exchange')),
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (service == null) return;
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => NfcExchangeScreen(service: service),
                        ));
                      },
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(locale.get('enter_node_id')),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: locale.get('node_id_hex_label'),
                hintText: 'cleona://... oder Node-ID (Hex)',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final input = controller.text.trim();
              ContactSeed? seed;

              // Try as ContactSeed URI first
              if (input.startsWith('cleona://')) {
                seed = ContactSeed.fromUri(input);
              }

              // Fall back to plain 64-char hex Node-ID
              if (seed == null && input.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(input)) {
                seed = ContactSeed(nodeIdHex: input, displayName: '');
              }

              if (seed != null && service != null) {
                // Channel mismatch check
                final localTag = NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l';
                if (!seed.isChannelCompatible(localTag)) {
                  final localName = NetworkSecret.channel == NetworkChannel.beta ? 'Beta' : 'Live';
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      content: Text(locale.tr('channel_mismatch', {
                        'contact': seed.channelDisplayName,
                        'local': localName,
                      })),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                // Register seed peers if available, wait for PONGs, then send CR
                if (seed.seedPeers.isNotEmpty || seed.ownAddresses.isNotEmpty) {
                  service.addPeersFromContactSeed(
                    seed.nodeIdHex,
                    seed.ownAddresses,
                    seed.seedPeers.map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses)).toList(),
                  );
                  Future.delayed(const Duration(seconds: 3), () {
                    service.sendContactRequest(seed!.nodeIdHex);
                  });
                } else {
                  service.sendContactRequest(seed.nodeIdHex);
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(locale.get('contact_request_sent'))),
                );
              }
            },
            child: Text(locale.get('send')),
          ),
        ],
      ),
    );
  }
}

// ── Conversation List View ─────────────────────────────────────────────

/// Channel tab with sub-tabs: Subscribed | My Channels | Search.
class _ChannelTabView extends StatefulWidget {
  final List<Conversation> channelConvs;
  final ICleonaService service;

  const _ChannelTabView({required this.channelConvs, required this.service});

  @override
  State<_ChannelTabView> createState() => _ChannelTabViewState();
}

class _ChannelTabViewState extends State<_ChannelTabView> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    // Default to Search tab (index 2) if no channels subscribed yet
    final initialIndex = widget.channelConvs.isEmpty ? 2 : 0;
    _subTabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final channels = widget.service.channels;
    final myNodeId = widget.service.nodeIdHex;

    // Split conversations
    final subscribedConvs = widget.channelConvs.where((c) {
      final ch = channels[c.id];
      return ch != null && ch.ownerNodeIdHex != myNodeId;
    }).toList();
    final ownedConvs = widget.channelConvs.where((c) {
      final ch = channels[c.id];
      return ch != null && (ch.ownerNodeIdHex == myNodeId ||
          ch.members[myNodeId]?.role == 'admin');
    }).toList();

    return Column(
      children: [
        Builder(builder: (ctx) {
          final character = Theme.of(ctx).character;
          final isPhoto = character.surfaceRenderMode == SurfaceRenderMode.photo;
          final isSlate = character.surfaceRenderMode == SurfaceRenderMode.cssSlate;
          final needsOverlay = isPhoto || isSlate;
          final shadows = isPhoto
              ? const <Shadow>[
                  Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
                  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
                ]
              : null;
          final labelColor = needsOverlay ? Colors.white : null;
          final unselectedColor = needsOverlay
              ? Colors.white.withValues(alpha: 0.7)
              : null;
          return TabBar(
            controller: _subTabController,
            labelStyle: TextStyle(fontSize: 11, color: labelColor, shadows: shadows),
            unselectedLabelStyle: TextStyle(fontSize: 11, color: unselectedColor, shadows: shadows),
            labelColor: labelColor,
            unselectedLabelColor: unselectedColor,
            tabs: [
              Tab(text: locale.get('channel_tab_subscribed')),
              Tab(text: locale.get('channel_tab_owned')),
              Tab(text: locale.get('channel_tab_search')),
            ],
          );
        }),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _ConversationListView(
                conversations: subscribedConvs,
                service: widget.service,
                emptyKey: 'no_channels',
              ),
              _ConversationListView(
                conversations: ownedConvs,
                service: widget.service,
                emptyKey: 'no_channels',
              ),
              _ChannelSearchView(service: widget.service),
            ],
          ),
        ),
      ],
    );
  }
}

/// Search view for discovering public channels.
class _ChannelSearchView extends StatefulWidget {
  final ICleonaService service;
  const _ChannelSearchView({required this.service});

  @override
  State<_ChannelSearchView> createState() => _ChannelSearchViewState();
}

class _ChannelSearchViewState extends State<_ChannelSearchView> {
  final _searchController = TextEditingController();
  List<ChannelIndexEntry> _results = [];
  bool _includeAdult = false;
  String? _filterLanguage;

  @override
  void initState() {
    super.initState();
    _doSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _doSearch() async {
    final results = await widget.service.searchPublicChannels(
      query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      language: _filterLanguage,
      includeAdult: _includeAdult,
    );
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: locale.get('channel_search_hint'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.filter_list, size: 20),
                tooltip: locale.get('channel_language'),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => StatefulBuilder(
                      builder: (ctx, setSheetState) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(locale.get('channel_language'),
                                style: Theme.of(ctx).textTheme.titleMedium),
                            Wrap(
                              spacing: 8,
                              children: [null, 'de', 'en', 'es', 'hu', 'sv', 'multi'].map((l) {
                                return ChoiceChip(
                                  label: Text(l == null ? 'Alle' : l == 'multi' ? locale.get('language_multi') : l.toUpperCase()),
                                  selected: _filterLanguage == l,
                                  onSelected: (_) {
                                    setSheetState(() => _filterLanguage = l);
                                    setState(() => _filterLanguage = l);
                                    _doSearch();
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              title: Text(locale.get('channel_nsfw_toggle')),
                              value: _includeAdult,
                              onChanged: (v) {
                                setSheetState(() => _includeAdult = v);
                                setState(() => _includeAdult = v);
                                _doSearch();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text(locale.get('channel_no_results'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final entry = _results[i];
                    final alreadyJoined = widget.service.channels.containsKey(entry.channelIdHex);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: entry.isAdult
                            ? Colors.red.shade100
                            : colorScheme.primaryContainer,
                        child: Icon(
                          entry.isAdult ? Icons.eighteen_up_rating : Icons.campaign,
                          color: entry.isAdult ? Colors.red : colorScheme.primary,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 4),
                          Text(entry.language.toUpperCase(),
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                          if (entry.badBadgeLevel > 0) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.warning, size: 14,
                                color: entry.badBadgeLevel >= 3
                                    ? Colors.red : Colors.orange),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${entry.subscriberCount} ${locale.get('role_subscriber')}${entry.description != null ? ' — ${entry.description}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: alreadyJoined
                          ? const Icon(Icons.check, color: Colors.green)
                          : FilledButton.tonal(
                              onPressed: () async {
                                await widget.service.joinPublicChannel(entry.channelIdHex);
                                _doSearch();
                              },
                              child: Text(locale.get('channel_join')),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ConversationListView extends StatefulWidget {
  final List<Conversation> conversations;
  final ICleonaService service;
  final String emptyKey;
  final bool showDonationBanner;

  const _ConversationListView({
    required this.conversations,
    required this.service,
    required this.emptyKey,
    this.showDonationBanner = false,
  });

  @override
  State<_ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<_ConversationListView> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> get _filteredConversations {
    if (_searchQuery.isEmpty) return widget.conversations;
    final q = _searchQuery.toLowerCase();
    return widget.conversations.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      if (c.messages.isNotEmpty) {
        final lastMsg = c.messages.last;
        if (!lastMsg.isDeleted && lastMsg.text.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final conversations = _filteredConversations;

    if (widget.conversations.isEmpty) {
      return _EmptyState(
        icon: Icons.chat_bubble_outline,
        text: locale.get(widget.emptyKey),
        subtext: 'Node-ID: ${widget.service.nodeIdHex.length >= 16 ? widget.service.nodeIdHex.substring(0, 16) : widget.service.nodeIdHex}...',
      );
    }

    final bannerOffset = widget.showDonationBanner ? 1 : 0;

    return Column(
      children: [
        // Search toggle row
        AnimatedCrossFade(
          firstChild: Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.search, size: 20),
              tooltip: locale.get('search_conversations'),
              onPressed: () => setState(() => _isSearching = true),
            ),
          ),
          secondChild: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: locale.get('search_conversations'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() {
                    _isSearching = false;
                    _searchController.clear();
                    _searchQuery = '';
                  }),
                ),
              ],
            ),
          ),
          crossFadeState: _isSearching ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        // List
        Expanded(
          child: conversations.isEmpty && _searchQuery.isNotEmpty
              ? Center(child: Text(locale.get('search_no_results'),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
              : ListView.builder(
      itemCount: conversations.length + bannerOffset,
      itemBuilder: (context, index) {
        if (widget.showDonationBanner && index == 0) {
          return const _DonationBanner();
        }
        final convIndex = index - bannerOffset;
        final conv = conversations[convIndex];
        final lastMsg = conv.messages.isNotEmpty ? conv.messages.last : null;
        final colorScheme = Theme.of(context).colorScheme;

        // Build avatar widget for ChatListTile.avatarOverride
        final avatarWidget = _avatar(context, conv);

        // Build context-menu trailing widget
        final contextMenu = PopupMenuButton<String>(
          iconSize: 20,
          padding: EdgeInsets.zero,
          onSelected: (action) {
            if (action == 'favorite') {
              widget.service.toggleFavorite(conv.id);
            } else if (action == 'rename_contact') {
              final contact = widget.service.getContact(conv.id);
              if (contact != null) {
                _showRenameContactDialogFromConv(context, widget.service, contact);
              }
            } else if (action == 'delete_contact') {
              _showDeleteContactDialog(context, conv, colorScheme);
            } else if (action == 'leave') {
              if (conv.isGroup) {
                _showLeaveGroupDialog(context, conv, colorScheme);
              } else if (conv.isChannel) {
                _showLeaveChannelDialog(context, conv, colorScheme);
              }
            } else if (action == 'info') {
              if (conv.isGroup) {
                _showGroupInfoDialog(context, conv.id, widget.service);
              } else if (conv.isChannel) {
                _showChannelInfoDialog(context, conv.id, widget.service);
              }
            }
          },
          itemBuilder: (_) {
            final locale = AppLocale.read(context);
            return [
              // Favorite toggle — for all types
              PopupMenuItem(value: 'favorite', child: Row(children: [
                Icon(conv.isFavorite ? Icons.star : Icons.star_border, size: 18, color: conv.isFavorite ? Colors.amber : null),
                const SizedBox(width: 8),
                Text(conv.isFavorite ? locale.get('remove_from_favorites') : locale.get('add_to_favorites')),
              ])),
              // Type-specific entries
              if (conv.isGroup) ...[
                PopupMenuItem(value: 'info', child: Row(children: [const Icon(Icons.info_outline, size: 18), const SizedBox(width: 8), Text(locale.get('group_info'))])),
                PopupMenuItem(value: 'leave', child: Row(children: [const Icon(Icons.exit_to_app, size: 18, color: Colors.red), const SizedBox(width: 8), Text(locale.get('leave'), style: const TextStyle(color: Colors.red))])),
              ],
              if (conv.isChannel) ...[
                PopupMenuItem(value: 'info', child: Row(children: [const Icon(Icons.info_outline, size: 18), const SizedBox(width: 8), Text(locale.get('channel_info'))])),
                PopupMenuItem(value: 'leave', child: Row(children: [const Icon(Icons.exit_to_app, size: 18, color: Colors.red), const SizedBox(width: 8), Text(locale.get('leave'), style: const TextStyle(color: Colors.red))])),
              ],
              if (!conv.isGroup && !conv.isChannel) ...[
                PopupMenuItem(value: 'rename_contact', child: Row(children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text(locale.get('rename_contact'))])),
                PopupMenuItem(value: 'delete_contact', child: Row(children: [const Icon(Icons.person_remove, size: 18, color: Colors.red), const SizedBox(width: 8), Text(locale.get('delete_contact'), style: const TextStyle(color: Colors.red))])),
              ],
            ];
          },
        );

        // Build preview text: prefix deleted/media/text
        final previewText = lastMsg != null
            ? _lastMessagePreview(context, lastMsg)
            : '';

        // Build timestamp string from last message or last activity
        final timestampStr = lastMsg != null
            ? _formatTime(lastMsg.timestamp)
            : _formatTime(conv.lastActivity);

        // Favourite star prefix baked into name for ChatListTile
        final displayName = conv.isFavorite
            ? '★ ${conv.displayName}'
            : conv.displayName;

        // ChatListTile has no trailing slot — overlay the context-menu button
        // via a Stack so the long-press popup is still reachable.
        return Stack(
          children: [
            ChatListTile(
              // isPeerOnline: Conversation has no online-presence field.
              // The routing layer tracks ackConfirmed per-node but does not
              // expose it at conversation level. Defaulting to false is safe —
              // Task 21 (contacts_screen) can add presence once the service
              // interface exposes it.
              isOnline: false,
              name: displayName,
              preview: previewText,
              timestamp: timestampStr,
              unreadCount: conv.unreadCount,
              avatarOverride: avatarWidget,
              onTap: () {
                conv.unreadCount = 0;
                final appState = context.read<CleonaAppState>();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: appState,
                      child: ChatScreen(
                        conversationId: conv.id,
                        displayName: conv.displayName,
                        isGroup: conv.isGroup,
                        isChannel: conv.isChannel,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Context-menu overlay — positioned at trailing edge so it doesn't
            // occlude the unread badge (badge is inside ChatListTile content row).
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerRight,
                child: contextMenu,
              ),
            ),
          ],
        );
      },
    ),
        ),
      ],
    );
  }

  void _showLeaveGroupDialog(BuildContext context, Conversation conv, ColorScheme colorScheme) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('leave_group_title')),
        content: Text(locale.tr('leave_confirm', {'name': conv.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              widget.service.leaveGroup(conv.id);
            },
            child: Text(locale.get('leave')),
          ),
        ],
      ),
    );
  }

  void _showLeaveChannelDialog(BuildContext context, Conversation conv, ColorScheme colorScheme) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('leave_channel_title')),
        content: Text(locale.tr('leave_confirm', {'name': conv.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              widget.service.leaveChannel(conv.id);
            },
            child: Text(locale.get('leave')),
          ),
        ],
      ),
    );
  }

  void _showRenameContactDialogFromConv(BuildContext context, ICleonaService service, ContactInfo contact) {
    final locale = AppLocale.read(context);
    final controller = TextEditingController(text: contact.localAlias ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('rename_contact_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${locale.get('original_name')}: ${contact.displayName}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: locale.get('rename_contact_hint'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                service.renameContact(contact.nodeIdHex, v.isEmpty ? null : v);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              service.renameContact(contact.nodeIdHex, v.isEmpty ? null : v);
              Navigator.pop(ctx);
            },
            child: Text(locale.get('save')),
          ),
        ],
      ),
    );
  }

  void _showDeleteContactDialog(BuildContext context, Conversation conv, ColorScheme colorScheme) {
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('delete_contact_title')),
        content: Text(locale.tr('delete_contact_confirm', {'name': conv.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              widget.service.deleteContact(conv.id);
            },
            child: Text(locale.get('delete')),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, Conversation conv) {
    final colorScheme = Theme.of(context).colorScheme;
    if (conv.profilePictureBase64 != null) {
      return CircleAvatar(backgroundImage: MemoryImage(base64Decode(conv.profilePictureBase64!)));
    }
    if (conv.isGroup) {
      return CircleAvatar(
        backgroundColor: colorScheme.tertiaryContainer,
        child: Icon(Icons.group, color: colorScheme.onTertiaryContainer),
      );
    }
    if (conv.isChannel) {
      return CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(Icons.campaign, color: colorScheme.onSecondaryContainer),
      );
    }
    return CircleAvatar(
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        conv.displayName.isNotEmpty ? conv.displayName[0].toUpperCase() : '?',
        style: TextStyle(color: colorScheme.onPrimaryContainer),
      ),
    );
  }

  void _showGroupInfoDialog(BuildContext context, String groupIdHex, ICleonaService service) {
    final group = service.groups[groupIdHex];
    if (group == null) return;
    final locale = AppLocale.read(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentGroup = service.groups[groupIdHex];
          if (currentGroup == null) {
            return AlertDialog(
              title: Text(locale.get('group_not_found')),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('ok')))],
            );
          }
          final myRole = currentGroup.members[service.nodeIdHex]?.role ?? 'member';
          final canManage = myRole == 'owner' || myRole == 'admin';
          final isOwner = myRole == 'owner';

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.group),
              const SizedBox(width: 8),
              Expanded(child: Text(currentGroup.name)),
            ]),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale.tr('members_count', {'count': '${currentGroup.members.length}'}),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: currentGroup.members.values.map((m) {
                        final isSelf = m.nodeIdHex == service.nodeIdHex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            m.role == 'owner' ? Icons.star : m.role == 'admin' ? Icons.shield : Icons.person,
                            size: 20,
                            color: m.role == 'owner' ? Colors.amber : m.role == 'admin' ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text('${m.displayName}${isSelf ? " ${locale.get('you_suffix')}" : ""}'),
                          subtitle: Text(
                            m.role == 'owner' ? locale.get('role_owner') : m.role == 'admin' ? locale.get('role_admin') : locale.get('role_member'),
                            style: TextStyle(fontSize: 11, color: m.role == 'owner' ? Colors.amber.shade700 : null),
                          ),
                          trailing: !isSelf && canManage
                              ? PopupMenuButton<String>(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  onSelected: (action) async {
                                    if (action == 'remove') {
                                      await service.removeMemberFromGroup(groupIdHex, m.nodeIdHex);
                                      setDialogState(() {});
                                    } else if (action.startsWith('role_')) {
                                      final newRole = action.substring(5);
                                      await service.setMemberRole(groupIdHex, m.nodeIdHex, newRole);
                                      setDialogState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (isOwner && m.role != 'admin')
                                      PopupMenuItem(value: 'role_admin', child: Row(children: [
                                        Icon(Icons.shield, size: 18), SizedBox(width: 8), Text(locale.get('make_admin')),
                                      ])),
                                    if (isOwner && m.role != 'member')
                                      PopupMenuItem(value: 'role_member', child: Row(children: [
                                        Icon(Icons.person, size: 18), SizedBox(width: 8), Text(locale.get('make_member')),
                                      ])),
                                    if (isOwner)
                                      PopupMenuItem(value: 'role_owner', child: Row(children: [
                                        Icon(Icons.star, size: 18, color: Colors.amber), SizedBox(width: 8), Text(locale.get('transfer_ownership')),
                                      ])),
                                    if (canManage)
                                      PopupMenuItem(value: 'remove', child: Row(children: [
                                        Icon(Icons.person_remove, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text(locale.get('remove'), style: TextStyle(color: Colors.red)),
                                      ])),
                                  ],
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (canManage)
                TextButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text(locale.get('invite')),
                  onPressed: () => _showInviteMemberDialog(ctx, groupIdHex, service, setDialogState),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(locale.get('close')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showInviteMemberDialog(BuildContext context, String groupIdHex, ICleonaService service, void Function(void Function()) refreshParent) {
    final group = service.groups[groupIdHex];
    if (group == null) return;
    final locale = AppLocale.read(context);

    // Show contacts not yet in the group
    final candidates = service.acceptedContacts
        .where((c) => !group.members.containsKey(c.nodeIdHex))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('all_contacts_in_group'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('invite_member')),
        content: SizedBox(
          width: 280,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(c.displayName),
                onTap: () async {
                  Navigator.pop(ctx);
                  await service.inviteToGroup(groupIdHex, c.nodeIdHex);
                  refreshParent(() {});
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
        ],
      ),
    );
  }

  void _showChannelInfoDialog(BuildContext context, String channelIdHex, ICleonaService service) {
    final channel = service.channels[channelIdHex];
    if (channel == null) return;
    final locale = AppLocale.read(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentChannel = service.channels[channelIdHex];
          if (currentChannel == null) {
            return AlertDialog(
              title: Text(locale.get('channel_not_found')),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('ok')))],
            );
          }
          final myRole = currentChannel.members[service.nodeIdHex]?.role ?? 'subscriber';
          final canManage = myRole == 'owner' || myRole == 'admin';
          final isOwner = myRole == 'owner';

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.campaign),
              const SizedBox(width: 8),
              Expanded(child: Text(currentChannel.name)),
            ]),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale.tr('subscribers_count', {'count': '${currentChannel.members.length}'}),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: currentChannel.members.values.map((m) {
                        final isSelf = m.nodeIdHex == service.nodeIdHex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            m.role == 'owner' ? Icons.star : m.role == 'admin' ? Icons.shield : Icons.person,
                            size: 20,
                            color: m.role == 'owner' ? Colors.amber : m.role == 'admin' ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text('${m.displayName}${isSelf ? " ${locale.get('you_suffix')}" : ""}'),
                          subtitle: Text(
                            m.role == 'owner' ? locale.get('role_owner') : m.role == 'admin' ? locale.get('role_admin') : locale.get('role_subscriber'),
                            style: TextStyle(fontSize: 11, color: m.role == 'owner' ? Colors.amber.shade700 : null),
                          ),
                          trailing: !isSelf && canManage
                              ? PopupMenuButton<String>(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  onSelected: (action) async {
                                    if (action == 'remove') {
                                      await service.removeFromChannel(channelIdHex, m.nodeIdHex);
                                      setDialogState(() {});
                                    } else if (action.startsWith('role_')) {
                                      final newRole = action.substring(5);
                                      await service.setChannelRole(channelIdHex, m.nodeIdHex, newRole);
                                      setDialogState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (isOwner && m.role != 'admin')
                                      PopupMenuItem(value: 'role_admin', child: Row(children: [
                                        Icon(Icons.shield, size: 18), SizedBox(width: 8), Text(locale.get('make_admin')),
                                      ])),
                                    if (isOwner && m.role != 'subscriber')
                                      PopupMenuItem(value: 'role_subscriber', child: Row(children: [
                                        Icon(Icons.person, size: 18), SizedBox(width: 8), Text(locale.get('make_subscriber')),
                                      ])),
                                    if (isOwner)
                                      PopupMenuItem(value: 'role_owner', child: Row(children: [
                                        Icon(Icons.star, size: 18, color: Colors.amber), SizedBox(width: 8), Text(locale.get('transfer_ownership')),
                                      ])),
                                    if (canManage)
                                      PopupMenuItem(value: 'remove', child: Row(children: [
                                        Icon(Icons.person_remove, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text(locale.get('remove'), style: TextStyle(color: Colors.red)),
                                      ])),
                                  ],
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (canManage)
                TextButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: Text(locale.get('invite')),
                  onPressed: () => _showInviteToChannelDialog(ctx, channelIdHex, service, setDialogState),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(locale.get('close')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showInviteToChannelDialog(BuildContext context, String channelIdHex, ICleonaService service, void Function(void Function()) refreshParent) {
    final channel = service.channels[channelIdHex];
    if (channel == null) return;
    final locale = AppLocale.read(context);

    final candidates = service.acceptedContacts
        .where((c) => !channel.members.containsKey(c.nodeIdHex))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('all_contacts_in_channel'))),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('invite_subscriber')),
        content: SizedBox(
          width: 280,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(c.displayName),
                onTap: () async {
                  Navigator.pop(ctx);
                  await service.inviteToChannel(channelIdHex, c.nodeIdHex);
                  refreshParent(() {});
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
        ],
      ),
    );
  }

  String _lastMessagePreview(BuildContext context, UiMessage msg) {
    final locale = AppLocale.read(context);
    if (msg.isDeleted) return locale.get('message_deleted');
    if (msg.isMedia) return '${msg.isOutgoing ? "${locale.get('you_prefix')} " : ""}📎 ${msg.filename ?? "Datei"}';
    if (msg.senderNodeIdHex.isEmpty) return msg.text; // System message
    return '${msg.isOutgoing ? "${locale.get('you_prefix')} " : ""}${msg.text}';
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month}.';
  }
}

// ── Inbox View (Pending Requests) ──────────────────────────────────────

class _InboxView extends StatelessWidget {
  final ICleonaService service;
  const _InboxView({required this.service});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final pending = service.pendingContacts;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final character = theme.character;
    final isPhoto = character.surfaceRenderMode == SurfaceRenderMode.photo;
    final isSlate = character.surfaceRenderMode == SurfaceRenderMode.cssSlate;
    final needsOverlay = isPhoto || isSlate;
    final overlayShadows = isPhoto
        ? const <Shadow>[
            Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
            Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
          ]
        : null;
    final titleColor = needsOverlay ? Colors.white : null;
    final subtitleColor = needsOverlay
        ? Colors.white.withValues(alpha: 0.7)
        : null;

    if (pending.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        text: locale.get('inbox_empty'),
        subtext: locale.get('contact_requests_appear_here'),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            locale.tr('contact_requests_count', {'count': '${pending.length}'}),
            style: theme.textTheme.titleSmall?.copyWith(
                  color: needsOverlay ? Colors.white : colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  shadows: overlayShadows,
                ),
          ),
        ),
        ...pending.map((c) => ListTile(
              leading: c.profilePictureBase64 != null
                  ? CircleAvatar(backgroundImage: MemoryImage(base64Decode(c.profilePictureBase64!)))
                  : CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: const Icon(Icons.person_add, color: Colors.orange),
                    ),
              title: Text(
                c.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: titleColor,
                  shadows: overlayShadows,
                ),
              ),
              subtitle: Text(
                c.nodeIdHex.substring(0, 16),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: subtitleColor,
                  shadows: overlayShadows,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.error),
                    tooltip: locale.get('reject'),
                    onPressed: () => service.deleteContact(c.nodeIdHex),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: locale.get('accept'),
                    onPressed: () => service.acceptContactRequest(c.nodeIdHex),
                  ),
                ],
              ),
            )),
      ],
    );
  }

}

// ── Empty State ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? subtext;

  const _EmptyState({required this.icon, required this.text, this.subtext});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.outline)),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(subtext!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
          ],
        ],
      ),
    );
  }
}

// ── Identity Tab Bar ──────────────────────────────────────────────────

class _IdentityTabBar extends StatelessWidget {
  final CleonaAppState appState;
  const _IdentityTabBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    final identityMgr = IdentityManager();
    final identities = identityMgr.loadIdentities();
    final activeIdentity = identityMgr.getActiveIdentity();
    return Row(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: identities.length,
            itemBuilder: (context, index) {
              final identity = identities[index];
              final isActive = activeIdentity?.id == identity.id;

              // Get unread count for this identity from IPC client
              int unread = 0;
              if (!isActive && identity.nodeIdHex != null && appState.service is IpcClient) {
                unread = (appState.service as IpcClient).identityUnreadCounts[identity.nodeIdHex!] ?? 0;
              }

              final skin = Skins.byId(identity.skinId);
              final brightness = Theme.of(context).brightness;

              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _IdentityTab(
                  name: identity.displayName,
                  isActive: isActive,
                  unreadCount: unread,
                  skinColor: skin.effectiveColor(brightness),
                  onTap: isActive
                      ? () => _openIdentityDetail(context, identity)
                      : () => appState.switchIdentity(identity),
                ),
              );
            },
          ),
        ),
        IconButton(
          onPressed: () => _showCreateDialog(context),
          icon: Icon(
            Skins.byId(IdentityManager().getActiveIdentity()?.skinId).addIdentityIcon,
            color: Skins.byId(IdentityManager().getActiveIdentity()?.skinId)
                .effectiveColor(Theme.of(context).brightness),
          ),
          iconSize: 28,
          padding: const EdgeInsets.only(right: 8),
        ),
      ],
    );
  }

  void _openIdentityDetail(BuildContext context, Identity identity) {
    final service = appState.service;
    if (service == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: AppLocale.read(context)),
          ],
          child: IdentityDetailScreen(service: service, identity: identity),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    final locale = AppLocale.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('new_identity')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: locale.get('name_label'), hintText: locale.get('identity_name_hint'), border: const OutlineInputBorder()),
          autofocus: true,
          onSubmitted: (_) {
            final name = controller.text.trim();
            if (name.isNotEmpty) { Navigator.pop(ctx); appState.createAndSwitchIdentity(name); }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(locale.get('cancel'))),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) { Navigator.pop(ctx); appState.createAndSwitchIdentity(name); }
            },
            child: Text(locale.get('create')),
          ),
        ],
      ),
    );
  }
}

// ── Single Identity Tab ───────────────────────────────────────────────

class _IdentityTab extends StatelessWidget {
  final String name;
  final bool isActive;
  final int unreadCount;
  final Color skinColor;
  final VoidCallback? onTap;

  const _IdentityTab({
    required this.name,
    required this.isActive,
    this.unreadCount = 0,
    required this.skinColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final character = theme.character;
    final isPhotoMode = character.surfaceRenderMode == SurfaceRenderMode.photo;
    final isSlateMode = character.surfaceRenderMode == SurfaceRenderMode.cssSlate;
    final overlayShadows = isPhotoMode
        ? const <Shadow>[
            Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
            Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
          ]
        : null;

    // Active: show a semi-transparent chip background so the active tab stands
    // out against photos. Inactive: no chip bg so the photo shines through.
    final activeChipColor = isPhotoMode
        ? Colors.black.withValues(alpha: 0.45)
        : colorScheme.surface;
    final inactiveTextColor = (isPhotoMode || isSlateMode)
        ? Colors.white.withValues(alpha: 0.85)
        : colorScheme.onSurfaceVariant;
    final activeTextColor = isPhotoMode ? Colors.white : skinColor;

    return InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            color: isActive ? activeChipColor : Colors.transparent,
            border: isActive
                ? Border.all(color: skinColor, width: 1.5)
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Skin color dot indicator
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: skinColor,
                ),
              ),
              Text(
                name,
                style: TextStyle(
                  color: isActive ? activeTextColor : inactiveTextColor,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                  shadows: overlayShadows,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}

// ── Connection Status Icon (P2P-aware) ──────────────────────────────
//
// Combines OS-level connectivity (connectivity_plus) with actual P2P
// reachability (confirmedPeerCount from CleonaNode). Four states:
//
//   Offline:   No network (OS reports none)
//   Searching: Network available but 0 confirmed P2P peers
//   Mobile:    Mobile data + peers reachable (cost warning)
//   WiFi:      WiFi/Ethernet/VPN + peers reachable
//
// WiFi takes priority over Mobile when both are reported (Android
// dual-connectivity). The "Searching" state uses a pulsing opacity
// animation to indicate active peer discovery.

class _ConnectionStatusIcon extends StatefulWidget {
  final CleonaAppState appState;
  const _ConnectionStatusIcon({required this.appState});

  @override
  State<_ConnectionStatusIcon> createState() => _ConnectionStatusIconState();
}

class _ConnectionStatusIconState extends State<_ConnectionStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// 5-tier connection classification (User-Mockup 2026-04-18):
  ///   strong (Hulk, green)           — WiFi + inbound reachable (Port-Mapping)
  ///   good (normal man, lime)        — WiFi + peers, no port mapping (NAT-behind but stable)
  ///   medium (yellow man)            — Mobile data / WiFi-fallback-to-mobile (CGNAT)
  ///   weak (orange man, starved)     — Network up but 0 confirmed peers (searching)
  ///   offline (skeleton)             — No network at all
  ConnectionTier _computeTier() {
    final results = widget.appState.connectivityResults;
    final confirmedPeers = widget.appState.confirmedPeerCount;
    final hasNetwork = results.isNotEmpty &&
        !results.contains(ConnectivityResult.none);
    final hasWifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn);
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final hasPortMapping = widget.appState.hasPortMapping;
    final mobileFallback = widget.appState.isMobileFallbackActive;

    if (!hasNetwork) return ConnectionTier.offline;
    if (confirmedPeers == 0) return ConnectionTier.weak;
    if (mobileFallback || (!hasWifi && hasMobile)) return ConnectionTier.medium;
    if (hasWifi) {
      return hasPortMapping ? ConnectionTier.strong : ConnectionTier.good;
    }
    return ConnectionTier.good;
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);
    final tier = _computeTier();

    final String assetPath;
    final String tooltip;
    final bool searching;

    switch (tier) {
      case ConnectionTier.offline:
        assetPath = 'assets/conn_skeleton.png';
        tooltip = locale.get('conn_offline');
        searching = false;
        break;
      case ConnectionTier.weak:
        // Network up but 0 peers — starved man (pulse to indicate "searching")
        assetPath = 'assets/conn_weak.png';
        tooltip = locale.get('conn_searching');
        searching = true;
        break;
      case ConnectionTier.medium:
        assetPath = 'assets/conn_medium.png';
        tooltip = widget.appState.isMobileFallbackActive
            ? locale.get('conn_mobile_fallback')
            : locale.get('conn_mobile');
        searching = false;
        break;
      case ConnectionTier.good:
        assetPath = 'assets/conn_good.png';
        tooltip = locale.get('conn_good');
        searching = false;
        break;
      case ConnectionTier.strong:
        assetPath = 'assets/conn_strong.png';
        tooltip = locale.get('conn_wifi');
        searching = false;
        break;
    }

    // Start/stop pulse animation for searching state
    if (searching && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!searching && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }

    final image = Image.asset(
      assetPath,
      width: 28,
      height: 28,
      filterQuality: FilterQuality.medium,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleTap(tier, locale),
          child: searching
              ? AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, child) => Opacity(
                    opacity: _pulseAnimation.value,
                    child: child,
                  ),
                  child: image,
                )
              : image,
        ),
      ),
    );
  }

  /// Tap dispatcher: if NAT-Wizard could help (WiFi behind NAT → "good" tier),
  /// open it; otherwise show an explanatory dialog so the user isn't left
  /// wondering what the icon means.
  void _handleTap(ConnectionTier tier, AppLocale locale) {
    final service = widget.appState.service;
    if (service == null) return;
    switch (tier) {
      case ConnectionTier.strong:
        // All good — no action needed. Could open NetworkStats in the future.
        return;
      case ConnectionTier.good:
        // WiFi + peers but no inbound port-mapping. Wizard can promote to
        // "strong" if the user adds a port-forward rule. Flows through the
        // dedicated [onNatWizardUserRequested] callback so the one-shot
        // auto-trigger latch in HomeScreen doesn't swallow it.
        service.requestNatWizard();
        return;
      case ConnectionTier.medium:
        // Mobile data / CGNAT — port-forward on own router can't fix this.
        _showExplainDialog(
          title: locale.get('conn_mobile'),
          body: locale.get('conn_mobile_explain'),
        );
        return;
      case ConnectionTier.weak:
        // Network up but no peers. Explain that it's normal shortly after
        // startup / after a network switch.
        _showExplainDialog(
          title: locale.get('conn_searching'),
          body: locale.get('conn_searching_explain'),
        );
        return;
      case ConnectionTier.offline:
        _showExplainDialog(
          title: locale.get('conn_offline'),
          body: locale.get('conn_offline_explain'),
        );
        return;
    }
  }

  void _showExplainDialog({required String title, required String body}) {
    final locale = AppLocale.read(context);
    // useRootNavigator: the status icon lives in an AppBar inside a nested
    // Navigator context on Android — without this flag the dialog route can
    // be pushed onto a non-visible sub-Navigator and only the barrier dim
    // reaches the screen while the AlertDialog renders in a detached tree.
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(locale.get('close')),
          ),
        ],
      ),
    );
  }
}

/// 5-tier classification for the connection-status icon.
/// Asset mapping (per user mockup 2026-04-18):
///   strong  → conn_strong.png   (green Hulk)
///   good    → conn_good.png     (normal man)
///   medium  → conn_medium.png   (yellow man)
///   weak    → conn_weak.png     (starved man, pulses)
///   offline → conn_skeleton.png (skeleton)
enum ConnectionTier { offline, weak, medium, good, strong }

/// Signal-style donation banner — subtle card at top of conversation list.
/// Dismissible for 30 days via SharedPreferences.
class _DonationBanner extends StatefulWidget {
  const _DonationBanner();

  @override
  State<_DonationBanner> createState() => _DonationBannerState();
}

class _DonationBannerState extends State<_DonationBanner> {
  bool _dismissed = true; // hidden by default until prefs loaded

  static const _prefKey = 'donation_banner_dismissed_until';

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedUntil = prefs.getInt(_prefKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mounted) {
      setState(() => _dismissed = now < dismissedUntil);
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    // Dismiss for 30 days
    final until = DateTime.now().millisecondsSinceEpoch + 30 * 24 * 60 * 60 * 1000;
    await prefs.setInt(_prefKey, until);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final locale = AppLocale.read(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        elevation: 0,
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_border, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locale.get('donate_banner_text'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _dismiss,
                    child: Text(locale.get('donate_dismiss'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DonationScreen()),
                    ),
                    child: Text(locale.get('donate_button'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
