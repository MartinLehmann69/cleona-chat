import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/ui/components/contact_name.dart';

/// The dialog that creates a group (§16.2.2).
///
/// Create is enabled only with a name and at least [kGroupMinOtherMembers]
/// selected contacts — the same rule the service enforces
/// ([groupCreationAllowed]); below that the dialog says why: with one
/// other person the conversation is a direct chat.
class CreateGroupDialog extends StatefulWidget {
  final List<ContactInfo> contacts;

  /// Called with the trimmed name and the selected contacts' node ids
  /// after the dialog has closed itself.
  final Future<void> Function(String name, List<String> memberNodeIds) onCreate;

  const CreateGroupDialog({
    super.key,
    required this.contacts,
    required this.onCreate,
  });

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      groupCreationAllowed(_selected.length) &&
      _nameController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final tooFew = !groupCreationAllowed(_selected.length);
    return AlertDialog(
      title: Text(locale.get('create_group')),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                // Rebuild on every keystroke so the Create button reflects
                // the name field, not only the member checkboxes.
                onChanged: (_) => setState(() {}),
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
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.contacts.length,
                  itemBuilder: (_, i) {
                    final c = widget.contacts[i];
                    return CheckboxListTile(
                      title: Text(shownContactName(c.displayName, locale)),
                      value: _selected.contains(c.nodeIdHex),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(c.nodeIdHex);
                        } else {
                          _selected.remove(c.nodeIdHex);
                        }
                      }),
                    );
                  },
                ),
              ),
              if (tooFew) ...[
                const SizedBox(height: 8),
                Text(
                  locale.get('group_min_members_hint'),
                  key: const ValueKey('group_min_members_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locale.get('cancel')),
        ),
        FilledButton(
          key: const ValueKey('create_group_button'),
          onPressed: _canCreate
              ? () async {
                  final name = _nameController.text.trim();
                  final members = _selected.toList();
                  Navigator.pop(context);
                  await widget.onCreate(name, members);
                }
              : null,
          child: Text(locale.get('create')),
        ),
      ],
    );
  }
}
