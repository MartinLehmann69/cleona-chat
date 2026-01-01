/// The own invitation card (V4.2 §12.4, §15.2, §15.3, §15.6).
///
/// Replaces `contact_share_card.dart` (V4.1: ContactSeed URI `cleona://…`,
/// invitation classes, channel matrix). V4.2 knows none of that any more: a
/// card has two kinds (one person / one group), four validities
/// and two forms, QR and a text line — "both carry the same bytes" (§12.4).
///
/// **The medium decides the hand-over (§15.5, owner decision 24.09.2026).**
/// A card "One person" is shown as a QR code to the person standing
/// there — acceptance without a second question, no text line. Copying
/// the text issues a SECOND, separate invitation, for which every request
/// is asked: the bytes of QR and text are the same, so the issuer could not
/// tell afterwards which of the two was used. The shown QR invitation lives
/// 60 s after it was shown (§15.3, owner decision 07.10.2026) — the SERVICE
/// closes it, not this view, so that closing the app does not leave it
/// standing (`invitation_face_to_face.dart`). This view only reports the one
/// showing the service cannot know: "show anyway" ([_showAnyway]). When the
/// service closes the card this view shows, the view hides the code and says
/// so, with the "Create invitation" button right below (S406-QR2 2A): it
/// reloads the standing invitations on the service's `onStateChanged` — which
/// the service raises when it closes one — while a face-to-face card is on
/// screen, and reads WHY the card is gone from
/// [StandingInvitationsResult.closedFaceToFace] (a redeemed card disappears
/// too, without that notice). No clock of its own, no polling.
///
/// The card follows §12.4, not the readiness state (§22.7.2): it is shown
/// at once when its invitation data carry a way in from the open network;
/// otherwise a waiting indicator stands for at most 30 s, the card comes as
/// soon as the way in does, and after the deadline a message says the device
/// cannot be reached from the internet right now, with the button that shows
/// the card anyway, labelled "same W/LAN only" (`invitation_way_in.dart`).
/// An invitation issued but never shown has not left the device and is
/// revoked when the view closes or a new one replaces it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart' as qr_lib;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/invitation_messages.dart';
import 'package:cleona/ui/components/invitation_way_in.dart';
import 'package:cleona/ui/components/share_cleona_dialog.dart';
import 'package:cleona/ui/theme/theme_access.dart';

class InvitationCardView extends StatefulWidget {
  final ICleonaService service;

  /// "Share Cleona" below the card — identity details and
  /// QR display show it (owner rule: sharing at most one tap
  /// from the start screen, never in the settings).
  final bool showShareCleonaButton;

  const InvitationCardView({
    super.key,
    required this.service,
    this.showShareCleonaButton = false,
  });

  @override
  State<InvitationCardView> createState() => _InvitationCardViewState();
}

class _InvitationCardViewState extends State<InvitationCardView> {
  // §15.3: "single (default)". The kind is the DOCUMENT's default, not a
  // promise in the user's name — it is visible and changeable.
  InvitationKind _kind = InvitationKind.single;
  InvitationValidity _validity =
      InvitationValidity.defaultFor(InvitationKind.single);

  /// The separate text invitation for the shown card "One person" — issued
  /// on the first copy, reused on every further one.
  InvitationCard? _textCard;

  /// The card last issued in THIS view.
  InvitationCard? _card;
  InvitationIssueRefusal? _refusal;
  bool _busy = false;

  /// §12.4: waiting for the issued card's way in.
  bool _waiting = false;

  /// §12.4: the deadline passed without a way in — offered "anyway".
  InvitationCard? _noWayIn;

  /// The issued card that has not been shown yet (waiting or [_noWayIn]).
  String? _unshown;

  /// `null` = not read yet. An empty list and "not read
  /// yet" are two statements, and only the second may stay silent.
  StandingInvitationsResult? _standing;
  String? _revokeMessageKey;

  /// §15.3 (S406-QR2 2A): the notice that the service closed the card this
  /// view offered — `card_face_to_face_closed` (shown, 60 s over) or
  /// `card_face_to_face_closed_restart` (never shown, closed at the start of
  /// the service). `null` = no notice.
  String? _closedKey;

  /// The holder of the service's single `onStateChanged` slot before this
  /// view opened; chained while it is open and given back in [dispose]
  /// (pattern `connection_sheet.dart`, `device_management_screen.dart`).
  void Function()? _previousOnStateChanged;

  @override
  void initState() {
    super.initState();
    _previousOnStateChanged = widget.service.onStateChanged;
    widget.service.onStateChanged = _onServiceState;
    unawaited(_loadStanding());
  }

  /// The service changed state — among others, it closed a face-to-face
  /// invitation (§15.3). Only while such a card is on screen does the view
  /// ask which invitations still stand.
  void _onServiceState() {
    _previousOnStateChanged?.call();
    if (!mounted) return;
    if (_card?.faceToFace == true || _noWayIn?.faceToFace == true) {
      unawaited(_loadStanding());
    }
  }

  Future<void> _loadStanding() async {
    final r = await widget.service.standingInvitations();
    if (!mounted) return;
    setState(() {
      _standing = r;
      final card = _card;
      final offered = _noWayIn;
      // §15.3 (S406-QR2 2A): the SERVICE closed the card on screen — say so
      // instead of letting the code vanish without a word.
      final closed = r.closedFaceToFace;
      if (card != null && card.faceToFace && closed.contains(card.id)) {
        _closedKey = 'card_face_to_face_closed';
      } else if (offered != null &&
          offered.faceToFace &&
          closed.contains(offered.id)) {
        _closedKey = 'card_face_to_face_closed_restart';
        _unshown = null;
      }
      // If the shown card is no longer in the list (revoked,
      // used up, expired), it is not offered any further — a
      // code that the next scanner silently rejects is a trap.
      final items = r.items;
      if (items != null &&
          _textCard != null &&
          !items.any((i) => i.id == _textCard!.id)) {
        _textCard = null;
      }
      if (items != null && card != null && !items.any((i) => i.id == card.id)) {
        _card = null;
      }
      if (items != null &&
          offered != null &&
          !items.any((i) => i.id == offered.id)) {
        _noWayIn = null;
      }
    });
  }

  @override
  void dispose() {
    widget.service.onStateChanged = _previousOnStateChanged;
    _revokeUnshown();
    super.dispose();
  }

  /// An invitation that was issued but never shown has not left the device:
  /// it is revoked at once instead of taking one of the ten places (§15.3).
  void _revokeUnshown() {
    final id = _unshown;
    _unshown = null;
    if (id != null) unawaited(widget.service.revokeInvitationCard(id));
  }

  /// "Show anyway – only in the same W/LAN" (§12.4). A face-to-face card is
  /// reported to the service first: its 60 s begin with this showing
  /// (§15.3), and a card that no longer stands is not shown.
  Future<void> _showAnyway() async {
    final card = _noWayIn;
    if (card == null) return;
    if (card.faceToFace &&
        !await widget.service.reportInvitationShown(card.id)) {
      if (!mounted) return;
      _unshown = null;
      // Read first, then hide: the list says whether the service closed it
      // (the notice of 2A) — and it is not offered any further either way.
      await _loadStanding();
      if (!mounted) return;
      setState(() {
        if (identical(_noWayIn, card)) _noWayIn = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _card = card;
      _noWayIn = null;
      _unshown = null;
    });
  }

  /// Copies the text of the separate invitation for [card] (§15.5: text
  /// line through another channel — every request is asked).
  Future<void> _copyText(AppLocale locale, InvitationCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    var copied = card.faceToFace ? _textCard : card;
    if (copied == null) {
      final r = await widget.service.issueInvitationCard(
          kind: card.kind, validity: _validity);
      if (!mounted) return;
      final issued = r.card;
      if (issued == null) {
        setState(() => _refusal = r.refusal ?? InvitationIssueRefusal.failed);
        return;
      }
      // §12.4: the out-of-band line follows the same rule as the QR code.
      final chosen =
          await invitationLineDialog(context, widget.service, issued);
      if (!mounted) return;
      if (chosen == null) {
        // Closed without copying: the line never left the device.
        unawaited(widget.service.revokeInvitationCard(issued.id));
        await _loadStanding();
        return;
      }
      setState(() => _textCard = chosen);
      copied = chosen;
      await _loadStanding();
    }
    await Clipboard.setData(ClipboardData(text: copied.text));
    messenger.showSnackBar(SnackBar(
      content: Text(copied.wayIn
          ? locale.get('copied_to_clipboard')
          : '${locale.get('copied_to_clipboard')} — '
              '${locale.get('invite_same_network_only')}'),
    ));
  }

  Future<void> _issue() async {
    // A new card replaces the shown one; a shown QR invitation runs out in
    // the service (§15.3), an unshown one is revoked at once.
    _revokeUnshown();
    _textCard = null;
    setState(() {
      _busy = true;
      _refusal = null;
      _noWayIn = null;
      _closedKey = null;
    });
    final r = await widget.service.issueInvitationCard(
        kind: _kind,
        validity: _validity,
        // §15.5: "One person" is shown as QR to the person standing there;
        // its text travels as a separate invitation ([_copyText]).
        faceToFace: _kind == InvitationKind.single);
    final issued = r.card;
    if (!mounted) {
      if (issued != null) {
        unawaited(widget.service.revokeInvitationCard(issued.id));
      }
      return;
    }
    if (issued != null && !issued.wayIn) {
      // §12.4: the new card replaces the shown one, but is not shown yet.
      _unshown = issued.id;
      setState(() {
        _card = null;
        _waiting = true;
      });
      final shown = await invitationAwaitWayIn(widget.service, issued);
      if (!mounted || _unshown != issued.id) return;
      setState(() {
        _busy = false;
        _waiting = false;
        if (shown.wayIn) {
          _card = shown;
          _unshown = null;
        } else {
          _noWayIn = shown;
        }
      });
      await _loadStanding();
      return;
    }
    setState(() {
      _busy = false;
      _card = issued ?? _card;
      _refusal = r.refusal;
    });
    await _loadStanding();
  }

  Future<void> _revoke(String id) async {
    final o = await widget.service.revokeInvitationCard(id);
    if (!mounted) return;
    setState(() {
      _revokeMessageKey = switch (o) {
        InvitationRevokeOutcome.revoked => null,
        InvitationRevokeOutcome.unknown => 'card_revoke_failed',
        InvitationRevokeOutcome.notConnected => 'card_not_connected',
      };
      if (o == InvitationRevokeOutcome.revoked && _card?.id == id) {
        _card = null;
      }
    });
    await _loadStanding();
  }

  Future<void> _revokeAll(AppLocale locale) async {
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(locale.get('card_revoke_all')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(locale.get('invite_revoke')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final r = await widget.service.revokeAllInvitationCards();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(r.notConnected
          ? locale.get('card_not_connected')
          : locale.tr('card_revoked_all', {'n': '${r.count}'})),
    ));
    if (!r.notConnected) setState(() => _card = null);
    await _loadStanding();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    // If GUI and daemon map identities differently, the card
    // may belong to a different identity than the one shown. Only
    // a new build of both halves fixes that — so nothing is issued.
    if (widget.service.identityDerivationSkew ==
        IdentityDerivationSkew.mismatch) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Text(locale.get('qr_build_skew'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error)),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(locale.get('card_title'), style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.spacing.sm),
          if (_card != null) ..._buildCard(context, locale, _card!),
          if (_closedKey != null && _card == null) ...[
            Text(locale.get(_closedKey!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
            SizedBox(height: tokens.spacing.md),
            const Divider(),
          ],
          if (_waiting)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
              child: const InvitationWayInWaiting(),
            ),
          if (_noWayIn != null) ...[
            InvitationNoWayIn(onAnyway: _showAnyway),
            SizedBox(height: tokens.spacing.md),
            const Divider(),
          ],
          ..._buildCreate(context, locale),
          ..._buildStanding(context, locale),
          if (widget.showShareCleonaButton) ...[
            SizedBox(height: tokens.spacing.md),
            const Divider(),
            SizedBox(height: tokens.spacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: Text(locale.get('share_cleona')),
              onPressed: () =>
                  ShareCleonaDialog.show(context, widget.service),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildCard(
      BuildContext context, AppLocale locale, InvitationCard card) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final radius = tokens.radius.md * theme.character.radiusMultiplier;
    final width = MediaQuery.of(context).size.width;
    final qrSize = (width * 0.55).clamp(180.0, 320.0);
    // §15.11: the QR code carries the packed card in binary form
    // ("91–413 B binary"). With the error correction M chosen here that
    // is version 6 (41x41 modules) for the smallest and version 16
    // (81x81) for the largest card (L/M/Q/H: V13/V16/V19/V22) — measured on
    // 07.10.2026 with exactly this generator on real cards, not estimated
    // (`test/smoke/smoke_invitation_card_reader.dart`, S406 E-3).
    final qr = qr_lib.QrCode.fromUint8List(
      data: card.packed,
      errorCorrectLevel: qr_lib.QrErrorCorrectLevel.M,
    );
    return [
      Text(
        // §15.5: a card for showing has no text line — the instruction
        // says to whom the code is shown, not "or send the text".
        locale.get(card.faceToFace
            ? 'card_show_face_to_face'
            : 'card_show_instruction'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      // §12.4: shown without a way in from the open network.
      if (!card.wayIn) ...[
        SizedBox(height: tokens.spacing.xs),
        const InvitationSameNetworkOnly(),
      ],
      SizedBox(height: tokens.spacing.sm),
      Center(
        child: Container(
          padding: EdgeInsets.all(tokens.spacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: QrImageView.withQr(
            qr: qr,
            size: qrSize,
            backgroundColor: Colors.white,
          ),
        ),
      ),
      SizedBox(height: tokens.spacing.sm),
      // The line is NOT rendered: since proposal E it is a `cleona:2:` line
      // of about 4,400 characters (card + the issuer's keys) — a wall of
      // text nobody reads and a partial selection would be exactly the
      // finding "truncated" (§15.6). It leaves only whole, through the copy
      // button below. A card for showing has no line at all (§15.5).
      SizedBox(height: tokens.spacing.xs),
      Text(
        invitationExpiryText(locale, card.expiryUnixSeconds),
        style: theme.textTheme.bodySmall,
      ),
      if (card.faceToFace)
        Text(
          locale.get('card_qr_valid_while_shown'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      SizedBox(height: tokens.spacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(locale.get('card_copy_text')),
          onPressed: () => _copyText(locale, card),
        ),
      ),
      if (card.faceToFace)
        Text(
          locale.get('card_handover_text_hint'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      SizedBox(height: tokens.spacing.md),
      const Divider(),
    ];
  }

  List<Widget> _buildCreate(BuildContext context, AppLocale locale) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final scheme = theme.colorScheme;
    return [
      Text(locale.get('card_kind_question'), style: theme.textTheme.bodyMedium),
      for (final k in InvitationKind.values)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _kind == k ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: _kind == k ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(locale.get(k == InvitationKind.single
              ? 'card_kind_single'
              : 'card_kind_open')),
          subtitle: Text(
            locale.get(k == InvitationKind.single
                ? 'card_kind_single_hint'
                : 'card_kind_open_hint'),
            style: theme.textTheme.bodySmall,
          ),
          onTap: () => setState(() {
            _kind = k;
            // §15.3: the default depends on the kind (90 d / 7 d).
            _validity = InvitationValidity.defaultFor(k);
          }),
        ),
      Row(
        children: [
          Expanded(child: Text(locale.get('invite_validity'))),
          DropdownButton<InvitationValidity>(
            value: _validity,
            items: [
              for (final v in InvitationValidity.values)
                DropdownMenuItem(
                  value: v,
                  child: Text(v.days == null
                      ? locale.get('invite_validity_unlimited')
                      : locale.tr('invite_validity_days', {'n': '${v.days}'})),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _validity = v);
            },
          ),
        ],
      ),
      if (_refusal != null)
        Padding(
          padding: EdgeInsets.only(bottom: tokens.spacing.sm),
          child: Text(invitationIssueRefusalText(locale, _refusal!),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: _busy ? null : _issue,
          child: Text(locale.get('invite_create')),
        ),
      ),
    ];
  }

  List<Widget> _buildStanding(BuildContext context, AppLocale locale) {
    final standing = _standing;
    if (standing == null) return const [];
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    final items = standing.items;
    final out = <Widget>[SizedBox(height: tokens.spacing.md)];
    if (items == null) {
      // The same sentence already stands below the button when issuing was
      // refused for the same reason — not twice.
      if (standing.notConnected &&
          _refusal == InvitationIssueRefusal.notConnected) {
        return const [];
      }
      out.add(Text(
          locale.get(standing.notConnected
              ? 'card_not_connected'
              : 'card_list_unavailable'),
          style: small?.copyWith(color: scheme.error)));
      return out;
    }
    out.add(Text(
      locale.tr('card_standing_count', {
        'n': '${items.length}',
        'max': '$kInvitationStandingCap',
      }),
      style: small?.copyWith(color: scheme.onSurfaceVariant),
    ));
    for (final i in items) {
      final kind = locale.get(
          i.kind == InvitationKind.single ? 'card_kind_single' : 'card_kind_open');
      final lines = <String>[
        invitationExpiryText(locale, i.expiryUnixSeconds),
        if (i.kind == InvitationKind.open)
          locale.tr('card_accepted_count',
              {'n': '${i.accepted}', 'max': '${i.maxAcceptances}'}),
      ];
      out.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(i.label.isEmpty ? kind : '$kind — ${i.label}', style: small),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lines.join('\n'), style: small),
            // §15.4 point 2: visible, with the remedy next to it — "Revoke"
            // on the right in the same line, "Create invitation" above it (ES-9).
            if (i.atBufferLimit)
              Text(locale.get('card_buffer_limit'),
                  style: small?.copyWith(color: scheme.error)),
          ],
        ),
        trailing: TextButton(
          onPressed: () => _revoke(i.id),
          child: Text(locale.get('invite_revoke')),
        ),
      ));
    }
    if (_revokeMessageKey != null) {
      out.add(Text(locale.get(_revokeMessageKey!),
          style: small?.copyWith(color: scheme.error)));
    }
    if (items.isNotEmpty) {
      out.add(Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => _revokeAll(locale),
          child: Text(locale.get('card_revoke_all')),
        ),
      ));
    }
    return out;
  }
}
