import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/components/app_bar_scaffold.dart';
import 'package:cleona/ui/components/contact_tile.dart';
import 'package:cleona/ui/screens/chat_screen.dart';

class ContactsScreen extends StatelessWidget {
  final ICleonaService service;
  const ContactsScreen({super.key, required this.service});

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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final svc = appState.service ?? service;
    final accepted = svc.acceptedContacts;
    final pending = svc.pendingContacts;

    return AppBarScaffold(
      title: 'Kontakte',
      body: ListView(
        children: [
          // Own info card
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meine Node-ID', style: Theme.of(context).textTheme.titleSmall),
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
                            const SnackBar(content: Text('Node-ID kopiert')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Port: ${svc.port} | Peers: ${svc.peerCount}',
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
                'Kontaktanfragen (${pending.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...pending.map((contact) => ContactTile(
                  name: contact.displayName,
                  status: contact.nodeIdHex.substring(0, 16),
                  verificationLevel: _mapVerification(contact.verificationLevel),
                  avatarOverride: contact.profilePictureBase64 != null
                      ? CircleAvatar(
                          backgroundImage: MemoryImage(base64Decode(contact.profilePictureBase64!)),
                          radius: 22,
                        )
                      : Container(
                          width: 44, height: 44,
                          decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                          child: const Icon(Icons.person_add, color: Colors.white),
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

          // Accepted contacts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Kontakte (${accepted.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (accepted.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Noch keine Kontakte')),
            ),
          ...accepted.map((contact) => ContactTile(
                name: contact.displayName,
                status: _contactSubtitle(contact),
                verificationLevel: _mapVerification(contact.verificationLevel),
                avatarOverride: contact.profilePictureBase64 != null
                    ? CircleAvatar(
                        backgroundImage: MemoryImage(base64Decode(contact.profilePictureBase64!)),
                        radius: 22,
                      )
                    : null,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDelete(context, svc, contact.nodeIdHex, contact.displayName);
                    } else if (value == 'birthday') {
                      _showBirthdayDialog(context, svc, contact);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'birthday', child: Row(children: const [
                      Icon(Icons.cake, size: 18),
                      SizedBox(width: 8),
                      Text('Geburtstag'),
                    ])),
                    const PopupMenuItem(value: 'delete', child: Text('Kontakt loeschen')),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        conversationId: contact.nodeIdHex,
                        displayName: contact.displayName,
                      ),
                    ),
                  );
                },
              )),
        ],
      ),
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

  void _confirmDelete(BuildContext context, ICleonaService svc, String nodeIdHex, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontakt loeschen?'),
        content: Text('$name und den gesamten Chatverlauf loeschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              svc.deleteContact(nodeIdHex);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$name geloescht')),
              );
            },
            child: const Text('Loeschen'),
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
      title: Text('Geburtstag · ${widget.contact.displayName}'),
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
          child: const Text('Entfernen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: (_month != null && _day != null)
              ? () {
                  final year = int.tryParse(_yearController.text);
                  widget.onSave(_month, _day, year);
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Speichern'),
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
