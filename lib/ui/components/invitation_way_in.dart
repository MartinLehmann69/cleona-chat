/// When an invitation is shown (V4.2 §12.4, owner decision 06.10.2026) — the
/// one rule for all three ways of handing it over: QR code, NFC exchange and
/// out-of-band invitation.
///
/// A card is shown at once only if its invitation data carry a way in from
/// the open network ([InvitationCard.wayIn]). Otherwise the front end shows a
/// waiting indicator while the service waits for that way in — event-driven
/// in the delivery layer, at most [kInvitationWayInWait] —, and shows the
/// card as soon as it comes. After the deadline it says plainly that the
/// device cannot be reached from the internet right now, and offers the card
/// anyway below, labelled as usable only in the same W/LAN (§7.2).
library;

import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';

/// The card to show for [card]: itself if it carries a way in; otherwise the
/// card the service rebuilt once the way in came ([InvitationCard.wayIn]
/// `true`) or, after the deadline, the last one known ([InvitationCard.wayIn]
/// `false`). The deadline holds HERE too — a lost answer must not leave the
/// waiting indicator standing; the second added covers the local round trip.
Future<InvitationCard> invitationAwaitWayIn(
    ICleonaService service, InvitationCard card) async {
  if (card.wayIn) return card;
  final r = await service
      .awaitInvitationWayIn(card.id)
      .timeout(kInvitationWayInWait + const Duration(seconds: 1),
          onTimeout: () => InvitationIssueResult.issued(card));
  return r.card ?? card;
}

/// The waiting indicator of §12.4.
class InvitationWayInWaiting extends StatelessWidget {
  const InvitationWayInWaiting({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(locale.get('invite_way_in_waiting'), textAlign: TextAlign.center),
      ],
    );
  }
}

/// The message after the deadline, with the button below it (§12.4).
/// [anywayKey] names the button: `invite_show_anyway` for QR and NFC,
/// `invite_copy_anyway` for the out-of-band line.
class InvitationNoWayIn extends StatelessWidget {
  const InvitationNoWayIn({
    super.key,
    required this.onAnyway,
    this.anywayKey = 'invite_show_anyway',
  });

  final VoidCallback onAnyway;
  final String anywayKey;

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(locale.get('invite_no_way_in'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.wifi, size: 18),
          label: Text(locale.get(anywayKey), textAlign: TextAlign.center),
          onPressed: onAnyway,
        ),
      ],
    );
  }
}

/// The label of a card shown without a way in from the open network.
class InvitationSameNetworkOnly extends StatelessWidget {
  const InvitationSameNetworkOnly({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.wifi, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 6),
        Flexible(
          child: Text(AppLocale.of(context).get('invite_same_network_only'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ),
      ],
    );
  }
}

/// The out-of-band line without a way in (§12.4): waits in a dialog and
/// returns the card to copy — with a way in, or the one the user chose to copy
/// anyway — or `null` if the dialog was closed without copying.
Future<InvitationCard?> invitationLineDialog(
    BuildContext context, ICleonaService service, InvitationCard card) {
  if (card.wayIn) return Future.value(card);
  return showDialog<InvitationCard>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LineDialog(service: service, card: card),
  );
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.service, required this.card});
  final ICleonaService service;
  final InvitationCard card;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  InvitationCard? _noWayIn;

  @override
  void initState() {
    super.initState();
    invitationAwaitWayIn(widget.service, widget.card).then((c) {
      if (!mounted) return;
      if (c.wayIn) {
        Navigator.pop(context, c);
      } else {
        setState(() => _noWayIn = c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final noWayIn = _noWayIn;
    return AlertDialog(
      content: noWayIn == null
          ? const InvitationWayInWaiting()
          : InvitationNoWayIn(
              anywayKey: 'invite_copy_anyway',
              onAnyway: () => Navigator.pop(context, noWayIn)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locale.get('cancel')),
        ),
      ],
    );
  }
}
