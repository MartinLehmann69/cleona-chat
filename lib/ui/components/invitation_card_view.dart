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
/// tell afterwards which of the two was used. The shown QR invitation is
/// revoked [kFaceToFaceRevokeDelay] after the view closes.
///
/// The card needs no network and no readiness state (§12.4,
/// §22.7.2 "The invitation is not gated"). There is therefore neither
/// a loading indicator nor a spinner here — only "issued", "refused with reason"
/// or "nothing issued yet".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart' as qr_lib;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/invitation_messages.dart';
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

/// How long a shown QR invitation stays valid after its view closed.
///
/// The scanner reads the card and then presses "send request" — a person
/// stands between scan and request, and the inviter may close the view as
/// soon as the scan happened. Measured 24.09.2026 from send to arrival:
/// 0.07 s (LAN) to 1.2 s (phone behind CGNAT over the internet); the rest
/// of the window is the scanner's decision. A request arriving later is
/// rejected silently (§15.3), like after any revocation.
const Duration kFaceToFaceRevokeDelay = Duration(seconds: 60);

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

  /// `null` = not read yet. An empty list and "not read
  /// yet" are two statements, and only the second may stay silent.
  StandingInvitationsResult? _standing;
  String? _revokeMessageKey;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStanding());
  }

  Future<void> _loadStanding() async {
    final r = await widget.service.standingInvitations();
    if (!mounted) return;
    setState(() {
      _standing = r;
      // If the shown card is no longer in the list (revoked,
      // used up, expired), it is not offered any further — a
      // code that the next scanner silently rejects is a trap.
      final items = r.items;
      final card = _card;
      if (items != null &&
          _textCard != null &&
          !items.any((i) => i.id == _textCard!.id)) {
        _textCard = null;
      }
      if (items != null && card != null && !items.any((i) => i.id == card.id)) {
        _card = null;
      }
    });
  }

  @override
  void dispose() {
    _faceToFaceRevokeLater(_card);
    super.dispose();
  }

  /// Revokes the shown QR invitation [card] after [kFaceToFaceRevokeDelay] —
  /// only if it still stands. A consumed one is left alone: revoked, it
  /// would silence the re-contact answer (§15.5, ES-11) should the
  /// scanner's answer have been lost.
  void _faceToFaceRevokeLater(InvitationCard? card) {
    if (card == null || !card.faceToFace) return;
    final service = widget.service;
    unawaited(Future<void>.delayed(kFaceToFaceRevokeDelay, () async {
      final items = (await service.standingInvitations()).items;
      if (items == null || !items.any((i) => i.id == card.id)) return;
      await service.revokeInvitationCard(card.id);
    }));
  }

  /// Copies the text of the separate invitation for [card] (§15.5: text
  /// line through another channel — every request is asked).
  Future<void> _copyText(AppLocale locale, InvitationCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    var text = card.faceToFace ? _textCard?.text : card.text;
    if (text == null) {
      final r = await widget.service.issueInvitationCard(
          kind: card.kind, validity: _validity);
      if (!mounted) return;
      final issued = r.card;
      if (issued == null) {
        setState(() => _refusal = r.refusal ?? InvitationIssueRefusal.failed);
        return;
      }
      setState(() => _textCard = issued);
      text = issued.text;
      await _loadStanding();
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(content: Text(locale.get('copied_to_clipboard'))),
    );
  }

  Future<void> _issue() async {
    // A new card replaces the shown one — a replaced QR invitation is
    // no longer shown and goes like a closed view.
    _faceToFaceRevokeLater(_card);
    _textCard = null;
    setState(() {
      _busy = true;
      _refusal = null;
    });
    final r = await widget.service.issueInvitationCard(
        kind: _kind,
        validity: _validity,
        // §15.5: "One person" is shown as QR to the person standing there;
        // its text travels as a separate invitation ([_copyText]).
        faceToFace: _kind == InvitationKind.single);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _card = r.card ?? _card;
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
    // §15.2: the QR code carries the packed card in binary form
    // ("90–380 B binary"). With the error correction M chosen here that
    // is version 6 (41x41 modules) for the smallest and version 15
    // (77x77) for the largest card — measured on 16.09.2026 with exactly
    // this generator, not estimated (§15.2).
    //
    // The cap of four own addresses is no cosmetics: with
    // error correction H the largest card would lie only THREE bytes below the
    // jump to version 21 (383 B).
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
      // The whole line, wrapping — §15.2 text is up to 519 characters long,
      // and truncated it would be exactly the finding "truncated". A card
      // for showing has NO line (§15.5): neither text nor copy button.
      if (!card.faceToFace)
        SelectableText(
          card.text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
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
