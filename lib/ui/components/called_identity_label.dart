import 'package:flutter/material.dart';

/// Names the own identity a call arrived on (S418, C-3): a person mark and
/// the identity's display name, under the caller or group name of the call
/// screens. Shown only where the device holds more than one identity — the
/// caller of [calledIdentityName] decides that and passes `null` otherwise.
///
/// No sentence around the name: the mark says "your identity", the name says
/// which, and no text needs a translation (§24.2).
class CalledIdentityLabel extends StatelessWidget {
  final String name;

  const CalledIdentityLabel({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.account_circle_outlined, size: 16, color: colour),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// The display name of the identity with [nodeIdHex] among [identities]
/// (`(nodeIdHex, displayName)`), or `null` when the device holds fewer than
/// two identities or the id is unknown — then nothing is shown.
String? calledIdentityName(
    String? nodeIdHex, List<(String?, String)> identities) {
  if (nodeIdHex == null || identities.length < 2) return null;
  for (final (id, name) in identities) {
    if (id == nodeIdHex) return name;
  }
  return null;
}
