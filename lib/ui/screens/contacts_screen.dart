import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/components/contact_issue_dialog.dart';
import 'package:cleona/ui/components/contact_name.dart';
import 'package:cleona/ui/components/contact_tile.dart';
import 'package:cleona/ui/components/profile_avatar.dart';
import 'package:cleona/ui/date_format.dart' as df;
import 'package:cleona/ui/screens/chat_screen.dart';

/// S367 §3.1: this used to be the app's only carrier of the four
/// verification levels and the §9.5.2a contact-issue-report path, but had
/// zero callers — the tab actually shown for "Kontakte" was built inline in
/// `home_screen.dart` (`kontakteList`), recycling the chat tile and knowing
/// neither verification levels nor the report dialog. Since S367 this
/// screen (as the tab body — no own AppBar/title, it is hosted inside
/// home_screen's existing TabBarView) IS the "Kontakte" tab; the inline
/// build was removed there. The merge below reproduces exactly what that
/// inline build could do (DM-conversation merge, sort, context menu,
/// search, favorites, tap-to-chat) so nothing it offered is lost.
class ContactsScreen extends StatefulWidget {
  final ICleonaService service;
  const ContactsScreen({super.key, required this.service});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Maps the string-based verificationLevel from ContactInfo to the
  /// ContactVerification enum used by ContactTile.
  static ContactVerification _mapVerification(String level) {
    switch (level) {
      case 'seen':
        return ContactVerification.seen;
      case 'verified':
        return ContactVerification.verified;
      case 'trusted':
        return ContactVerification.trusted;
      default:
        return ContactVerification.unverified;
    }
  }

  /// Same rendering as `home_screen.dart`'s `_lastMessagePreview` (the
  /// inline tab this screen replaces) — kept in sync deliberately rather
  /// than shared, since that method is private to `_ConversationListView`,
  /// which still serves the other tabs (Recent/Favorites/Groups).
  static String _previewText(AppLocale locale, UiMessage msg) {
    if (msg.isDeleted) return locale.get('message_deleted');
    if (msg.isMedia) {
      return '${msg.isOutgoing ? "${locale.get('you_prefix')} " : ""}📎 ${msg.filename ?? locale.get('file_fallback')}';
    }
    if (msg.senderNodeIdHex.isEmpty) return msg.text; // System message
    return '${msg.isOutgoing ? "${locale.get('you_prefix')} " : ""}${msg.text}';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final locale = AppLocale.of(context);
    final svc = appState.service ?? widget.service;
    final accepted = svc.acceptedContacts;
    final pending = svc.pendingContacts;
    final pendingOutgoing = svc.pendingOutgoingContacts;
    final storedForDelivery = svc.storedForDeliveryContacts;

    // ── "Kontakte" tab merge (was inline in home_screen.dart's kontakteList
    // until S367) ────────────────────────────────────────────────────────
    // Contacts with a running DM conversation show last-message preview,
    // timestamp and unread badge and sort unread-first/newest-first;
    // contacts without one keep the accepted-list order, appended after —
    // unchanged from the inline version this screen replaces.
    final acceptedById = {for (final c in accepted) c.nodeIdHex: c};
    final dmConvs = svc.sortedConversations
        .where((c) => !c.isGroup && !c.isChannel)
        .toList()
      ..sort((a, b) {
        final aUnread = a.unreadCount > 0 ? 0 : 1;
        final bUnread = b.unreadCount > 0 ? 0 : 1;
        if (aUnread != bUnread) return aUnread.compareTo(bUnread);
        return b.lastActivity.compareTo(a.lastActivity);
      });
    final dmIds = dmConvs.map((c) => c.id).toSet();
    final contactsWithoutConv =
        accepted.where((c) => !dmIds.contains(c.nodeIdHex)).toList();

    // Search scope matches the inline tab's: name and last-message text of
    // the merged accepted-contacts list only (the other sections below —
    // pending/pendingOutgoing/storedForDelivery — are unaffected, exactly
    // as in the inline tab, which never covered them at all).
    final query = _searchQuery.trim().toLowerCase();
    bool matches(String name, Conversation? conv) {
      if (query.isEmpty) return true;
      if (name.toLowerCase().contains(query)) return true;
      final lastMsg =
          (conv != null && conv.messages.isNotEmpty) ? conv.messages.last : null;
      if (lastMsg != null &&
          !lastMsg.isDeleted &&
          lastMsg.text.toLowerCase().contains(query)) {
        return true;
      }
      return false;
    }

    final acceptedRows = <Widget>[];
    for (final conv in dmConvs) {
      final contact = acceptedById[conv.id] ?? svc.getContact(conv.id);
      if (contact == null) continue; // defensive: every DM has a contact record
      if (!matches(contact.effectiveName, conv)) continue;
      acceptedRows.add(_buildAcceptedTile(context, svc, contact, conv));
    }
    for (final contact in contactsWithoutConv) {
      if (!matches(contact.effectiveName, null)) continue;
      acceptedRows.add(_buildAcceptedTile(context, svc, contact, null));
    }

    // Hosted inside home_screen's TabBarView, which already wraps its
    // children in `SafeArea(top: false, ...)` via AppBarScaffold — this
    // second one is a no-op once that one has claimed the padding, and
    // keeps this screen correct if it is ever pushed as its own route.
    return SafeArea(
      top: false,
      child: ListView(
        children: [
          // Own info card
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale.get('my_node_id'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          svc.nodeIdHex,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: svc.nodeIdHex));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(locale.get('copied_to_clipboard'))),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // §22.7.3: the contact list is a display surface
                    // of the partner count — and from §25.4 on that is
                    // split by direction (out/in).
                    'Port: ${svc.port} | '
                    '↗ ${svc.syncPartnersOutbound} '
                    '↙ ${svc.syncPartnersInbound}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          // Pending contact requests
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                locale.tr('contact_requests_count', {'count': '${pending.length}'}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...pending.map((contact) => ContactTile(
                  name: shownContactName(contact.displayName, locale),
                  status: contact.nodeIdHex.substring(0, 16),
                  verificationLevel: _mapVerification(contact.verificationLevel),
                  avatarOverride: ProfileAvatar(
                    base64: contact.profilePictureBase64,
                    radius: 22,
                    fallback: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: const Icon(Icons.person_add, color: Colors.white),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: 'Ablehnen',
                        onPressed: () => _confirmDelete(context, svc, contact.nodeIdHex, contact.displayName),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        tooltip: 'Annehmen',
                        onPressed: () => svc.acceptContactRequest(contact.nodeIdHex),
                      ),
                    ],
                  ),
                )),
            const Divider(),
          ],

          // Pending outgoing contacts (waiting for response)
          if (pendingOutgoing.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${locale.get('contact_issue_waiting')} (${pendingOutgoing.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...pendingOutgoing.map((contact) => ContactTile(
                  name: shownContactName(contact.displayName, locale),
                  status: locale.get('contact_issue_waiting_status'),
                  verificationLevel: _mapVerification(contact.verificationLevel),
                  avatarOverride: ProfileAvatar(
                    base64: contact.profilePictureBase64,
                    radius: 22,
                    fallback: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(color: Colors.blueGrey, shape: BoxShape.circle),
                      child: const Icon(Icons.hourglass_top, color: Colors.white, size: 22),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'report') {
                        _showContactIssueReport(context, svc, contact);
                      } else if (value == 'delete') {
                        _confirmDelete(context, svc, contact.nodeIdHex, contact.displayName);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'report', child: Row(children: [
                        Icon(Icons.contact_support, size: 18, color: Theme.of(context).colorScheme.tertiary),
                        const SizedBox(width: 8),
                        Text(locale.get('contact_issue_report_menu')),
                      ])),
                      PopupMenuItem(value: 'delete', child: Text(locale.get('contact_delete'))),
                    ],
                  ),
                )),
            const Divider(),
          ],

          // §5.5b / §8.1.1 step 3 (Arch:3665): outgoing CRs a seed peer has
          // confirmed storing. These are NOT lost and NOT still retrying —
          // the seed peer has taken over and will hand the CR to the
          // recipient when they come online. Before S299 this status had no
          // section at all, so a successful store made the contact vanish.
          if (storedForDelivery.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${locale.get('contact_stored_header')} (${storedForDelivery.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...storedForDelivery.map((contact) => ContactTile(
                  name: shownContactName(contact.displayName, locale),
                  status: locale.get('contact_stored_status'),
                  verificationLevel: _mapVerification(contact.verificationLevel),
                  avatarOverride: ProfileAvatar(
                    base64: contact.profilePictureBase64,
                    radius: 22,
                    fallback: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                      child: const Icon(Icons.cloud_done, color: Colors.white, size: 22),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'report') {
                        _showContactIssueReport(context, svc, contact);
                      } else if (value == 'delete') {
                        _confirmDelete(context, svc, contact.nodeIdHex, contact.displayName);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'report', child: Row(children: [
                        Icon(Icons.contact_support, size: 18, color: Theme.of(context).colorScheme.tertiary),
                        const SizedBox(width: 8),
                        Text(locale.get('contact_issue_report_menu')),
                      ])),
                      PopupMenuItem(value: 'delete', child: Text(locale.get('contact_delete'))),
                    ],
                  ),
                )),
            const Divider(),
          ],

          // Accepted contacts (merged with their DM conversation, if any)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    locale.tr('contacts_count', {'count': '${accepted.length}'}),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (accepted.isNotEmpty)
                  IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search, size: 20),
                    tooltip: locale.get('search_conversations'),
                    onPressed: () => setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchController.clear();
                        _searchQuery = '';
                      }
                    }),
                  ),
              ],
            ),
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          if (accepted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(locale.get('no_contacts_yet'))),
            )
          else if (acceptedRows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  locale.get('search_no_results'),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ...acceptedRows,
        ],
      ),
    );
  }

  /// One row of the merged accepted-contacts section — either backed by a
  /// running DM conversation (`conv` non-null: shows last-message preview,
  /// timestamp, unread badge) or not (`conv` null: shows the birthday-based
  /// subtitle `_contactSubtitle` always showed). Both branches get the same
  /// menu: favorite, rename, birthday, delete, so no capability differs by
  /// whether a conversation happens to exist yet.
  Widget _buildAcceptedTile(
    BuildContext context,
    ICleonaService svc,
    ContactInfo contact,
    Conversation? conv,
  ) {
    final locale = AppLocale.of(context);
    final String statusLine;
    if (conv != null) {
      final lastMsg = conv.messages.isNotEmpty ? conv.messages.last : null;
      final timestampStr = lastMsg != null
          ? df.formatConversationTime(lastMsg.timestamp, locale)
          : df.formatConversationTime(conv.lastActivity, locale);
      final previewText = lastMsg != null ? _previewText(locale, lastMsg) : null;
      statusLine = (previewText != null && previewText.isNotEmpty)
          ? '$previewText  ·  $timestampStr'
          : timestampStr;
    } else {
      statusLine = _contactSubtitle(contact);
    }

    final isFav = conv?.isFavorite ?? false;
    final baseName = shownContactName(contact.effectiveName, locale);
    final favName = isFav ? '★ $baseName' : baseName;
    final tileName =
        contact.isDeleted ? '$favName${locale.get('contact_deleted_suffix')}' : favName;
    final unread = conv?.unreadCount ?? 0;

    return ContactTile(
      name: tileName,
      status: statusLine,
      verificationLevel: _mapVerification(contact.verificationLevel),
      avatarOverride: ProfileAvatar(
        base64: contact.profilePictureBase64,
        radius: 22,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unread > 0) ...[
            Badge(
              label: Text('$unread'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
          ],
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'favorite':
                  svc.toggleFavorite(contact.nodeIdHex);
                case 'rename':
                  _showRenameDialog(context, svc, contact);
                case 'birthday':
                  _showBirthdayDialog(context, svc, contact);
                case 'never_fixed_neighbour':
                  _showNeverFixedNeighbourDialog(context, svc, contact);
                case 'delete':
                  _confirmDelete(context, svc, contact.nodeIdHex, contact.effectiveName);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'favorite', child: Row(children: [
                Icon(isFav ? Icons.star : Icons.star_border, size: 18, color: isFav ? Colors.amber : null),
                const SizedBox(width: 8),
                Text(isFav ? locale.get('remove_from_favorites') : locale.get('add_to_favorites')),
              ])),
              PopupMenuItem(value: 'rename', child: Row(children: [
                const Icon(Icons.edit, size: 18),
                const SizedBox(width: 8),
                Text(locale.get('rename_contact')),
              ])),
              PopupMenuItem(value: 'birthday', child: Row(children: [
                const Icon(Icons.cake, size: 18),
                const SizedBox(width: 8),
                Text(locale.get('contact_birthday')),
              ])),
              PopupMenuItem(value: 'never_fixed_neighbour', child: Row(children: [
                Icon(
                  contact.neverFixedNeighbour
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(locale.get('contact_never_fixed_neighbour'))),
              ])),
              PopupMenuItem(value: 'delete', child: Text(locale.get('delete_contact'))),
            ],
          ),
        ],
      ),
      onTap: () {
        final navState = context.read<CleonaAppState>();
        navState.service?.markConversationRead(contact.nodeIdHex);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: contact.nodeIdHex,
              displayName: contact.effectiveName,
            ),
          ),
        );
      },
    );
  }

  String _contactSubtitle(ContactInfo contact) {
    if (contact.birthdayMonth != null && contact.birthdayDay != null) {
      final m = contact.birthdayMonth!.toString().padLeft(2, '0');
      final d = contact.birthdayDay!.toString().padLeft(2, '0');
      final y = contact.birthdayYear != null ? '.${contact.birthdayYear}' : '';
      return '${contact.nodeIdHex.substring(0, 10)} · 🎂 $d.$m$y';
    }
    return contact.nodeIdHex.substring(0, 16);
  }

  void _showBirthdayDialog(BuildContext context, ICleonaService svc, ContactInfo contact) {
    showDialog(
      context: context,
      builder: (_) => _BirthdayDialog(
        contact: contact,
        onSave: (m, d, y) {
          svc.setContactBirthday(
            contact.nodeIdHex,
            month: m,
            day: d,
            year: y,
          );
        },
      ),
    );
  }

  /// §15.10 (D2 = a): "never use as a fixed neighbour". A property of the
  /// contact, not a send mode (§3.3) — the switch applies at once, like the
  /// other contact properties in this menu.
  void _showNeverFixedNeighbourDialog(
      BuildContext context, ICleonaService svc, ContactInfo contact) {
    final locale = AppLocale.of(context);
    var never = contact.neverFixedNeighbour;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(shownContactName(contact.effectiveName, locale)),
          content: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: never,
            title: Text(locale.get('contact_never_fixed_neighbour')),
            subtitle: Text(locale.get('contact_never_fixed_neighbour_hint')),
            onChanged: (v) {
              setDialogState(() => never = v);
              svc.setContactNeverFixedNeighbour(contact.nodeIdHex, v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(locale.get('close')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ICleonaService svc, ContactInfo contact) {
    final locale = AppLocale.of(context);
    final controller = TextEditingController(text: contact.localAlias ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('rename_contact_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${locale.get('original_name')}: ${contact.displayName}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.outline,
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
                svc.renameContact(contact.nodeIdHex, v.isEmpty ? null : v);
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
              svc.renameContact(contact.nodeIdHex, v.isEmpty ? null : v);
              Navigator.pop(ctx);
            },
            child: Text(locale.get('save')),
          ),
        ],
      ),
    );
  }

  void _showContactIssueReport(BuildContext context, ICleonaService svc, ContactInfo contact) async {
    final report = await svc.buildContactIssueReport(contact.nodeIdHex);
    if (report == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.of(context).get('contact_issue_report_error'))),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final result = await showContactIssueDialog(
      context: context,
      service: svc,
      report: report,
      contactNodeIdHex: contact.nodeIdHex,
    );

    if (!context.mounted) return;
    final locale = AppLocale.of(context);
    if (result == ContactIssueDialogResult.exported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('contact_issue_exported'))),
      );
    } else if (result == ContactIssueDialogResult.posted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locale.get('contact_issue_posted'))),
      );
    }
  }

  void _confirmDelete(BuildContext context, ICleonaService svc, String nodeIdHex, String name) {
    final locale = AppLocale.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(locale.get('delete_contact_title')),
        content: Text(locale.tr('delete_contact_confirm', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              svc.deleteContact(nodeIdHex, source: 'contacts_dialog');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(locale.tr('contact_deleted', {'name': name}))),
              );
            },
            child: Text(locale.get('delete')),
          ),
        ],
      ),
    );
  }
}

/// Birthday picker dialog. Month + day required; year optional.
/// Saving with month=null+day=null (via the Clear button) removes the birthday.
class _BirthdayDialog extends StatefulWidget {
  final ContactInfo contact;
  final void Function(int? month, int? day, int? year) onSave;

  const _BirthdayDialog({required this.contact, required this.onSave});

  @override
  State<_BirthdayDialog> createState() => _BirthdayDialogState();
}

class _BirthdayDialogState extends State<_BirthdayDialog> {
  late int? _month;
  late int? _day;
  final _yearController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _month = widget.contact.birthdayMonth;
    _day = widget.contact.birthdayDay;
    if (widget.contact.birthdayYear != null) {
      _yearController.text = '${widget.contact.birthdayYear}';
    }
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];

    // Number of days in the selected month (leap-year-safe for February
    // when a year is given; otherwise default to 29 to be permissive).
    int maxDay;
    if (_month == null) {
      maxDay = 31;
    } else {
      final y = int.tryParse(_yearController.text);
      if (_month == 2) {
        maxDay = (y != null && _isLeap(y)) ? 29 : 29;
      } else if ([4, 6, 9, 11].contains(_month)) {
        maxDay = 30;
      } else {
        maxDay = 31;
      }
    }
    if (_day != null && _day! > maxDay) _day = maxDay;

    return AlertDialog(
      title: Text(AppLocale.of(context)
          .tr('contact_birthday_title', {'name': widget.contact.displayName})),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int?>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Monat'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (var i = 1; i <= 12; i++)
                  DropdownMenuItem(value: i, child: Text(months[i - 1])),
              ],
              onChanged: (v) => setState(() => _month = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _day,
              decoration: const InputDecoration(labelText: 'Tag'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (var i = 1; i <= maxDay; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _day = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _yearController,
              decoration: const InputDecoration(
                labelText: 'Jahr (optional)',
                hintText: 'z.B. 1990',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSave(null, null, null);
            Navigator.pop(context);
          },
          child: Text(AppLocale.of(context).get('remove')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocale.of(context).get('cancel')),
        ),
        FilledButton(
          onPressed: (_month != null && _day != null)
              ? () {
                  final year = int.tryParse(_yearController.text);
                  widget.onSave(_month, _day, year);
                  Navigator.pop(context);
                }
              : null,
          child: Text(AppLocale.of(context).get('save')),
        ),
      ],
    );
  }

  bool _isLeap(int year) {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return year % 400 == 0;
  }
}
