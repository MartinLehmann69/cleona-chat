import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// The question of §16.2.2: "When every other member has left or been
/// removed and the own identity is the only member, the application asks
/// once whether to delete the group; deleting removes it as leaving does,
/// and keeping it leaves the conversation readable."
///
/// Pops `true` for delete and `false` for keep. Not dismissible by tapping
/// beside it: the question is asked once, so it waits for an answer.
class GroupAloneDialog extends StatelessWidget {
  final String groupName;

  const GroupAloneDialog({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return AlertDialog(
      title: Text(locale.get('group_alone_title')),
      content: Text(locale.tr('group_alone_body', {'name': groupName})),
      actions: [
        TextButton(
          key: const ValueKey('group_alone_keep'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(locale.get('group_alone_keep')),
        ),
        FilledButton(
          key: const ValueKey('group_alone_delete'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(locale.get('delete')),
        ),
      ],
    );
  }
}

/// Shows [GroupAloneDialog]: `true` delete, `false` keep, `null` closed
/// without an answer — then the question stays due and comes again on the
/// next opening of the group.
Future<bool?> showGroupAloneDialog(BuildContext context,
        {required String groupName}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GroupAloneDialog(groupName: groupName),
    );
