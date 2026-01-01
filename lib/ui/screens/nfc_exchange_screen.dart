import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cleona/core/contact/invitation_card_reader.dart'
    show InvitationReading;
import 'package:cleona/core/contact/nfc_platform_bridge.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/invitation_messages.dart';
import 'package:cleona/ui/components/invitation_redeem.dart';

/// NFC contact exchange (V4.2 §15.5, §15.10 "NFC exchange").
///
/// ── THE PATH (S388-BAU-KONTAKT) ─────────────────────────────────────────
///
///   1. On opening, the screen issues a card "One person" for the
///      IN-PERSON hand-over (`issueInvitationCard(faceToFace: true)`)
///      — without a text line. An NFC session begins only here; both devices
///      must have opened this screen (owner decision 15.09.2026:
///      automatic ONLY if both are actively in the contact function).
///   2. The touch exchanges the packed cards of both sides.
///   3. The received card is read like a QR code; "Accept" redeems
///      it. The other side accepts the request without a second question, because
///      ITS card was issued in person. If both do it, these are two
///      mutual requests, and each is answered automatically.
///
/// Until S388 the V3 exchange with `addNfcContact` stood here: a tap created
/// an `accepted` contact immediately, without request and without answer.
///
/// If the screen is left before any touch, it revokes its card
/// again — otherwise after ten visits the cap would be reached (§15.3).
class NfcExchangeScreen extends StatefulWidget {
  final ICleonaService service;
  const NfcExchangeScreen({super.key, required this.service});

  @override
  State<NfcExchangeScreen> createState() => _NfcExchangeScreenState();
}

class _NfcExchangeScreenState extends State<NfcExchangeScreen> {
  NfcSessionManager? _session;
  NfcSessionState _state = NfcSessionState.idle;
  InvitationReading? _reading;
  String? _error;
  String? _result;
  bool _starting = true;
  bool _sending = false;

  /// The card issued for this session (identifier for the revocation).
  String? _ownCard;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final locale = AppLocale.read(context);
    final r = await widget.service.issueInvitationCard(faceToFace: true);
    if (!mounted) return;
    final card = r.card;
    if (card == null) {
      setState(() {
        _state = NfcSessionState.failed;
        _error = invitationIssueRefusalText(
            locale, r.refusal ?? InvitationIssueRefusal.failed);
        _starting = false;
      });
      return;
    }
    _ownCard = card.id;

    _session = NfcSessionManager(
      onSessionUpdate: (state, payload, error) {
        if (!mounted) return;
        setState(() {
          _state = state;
          _error = error;
          if (payload != null) {
            _touched = true;
            final reading = InvitationRedeem.readBytes(payload);
            _reading = reading;
            if (state == NfcSessionState.pendingConfirmation &&
                !InvitationRedeem.isCard(reading)) {
              _state = NfcSessionState.failed;
              _error = InvitationRedeem.errorOf(locale, reading);
            }
          }
        });
      },
    );

    final started = await _session!.startSession(card.packed);
    if (!mounted) return;
    setState(() {
      _starting = false;
      if (!started) {
        _state = NfcSessionState.failed;
        _error ??= locale.get('nfc_start_failed');
      }
    });
  }

  @override
  void dispose() {
    _session?.cancelSession();
    final id = _ownCard;
    if (id != null && !_touched) {
      unawaited(widget.service.revokeInvitationCard(id));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final locale = AppLocale.of(context);
    final activeIdentity = IdentityManager().getActiveIdentity();
    final myName = activeIdentity?.displayName ?? widget.service.displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.get('nfc_contact_exchange')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _session?.cancelSession();
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _buildContent(context, colorScheme, myName),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, ColorScheme colorScheme, String myName) {
    if (_starting) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(AppLocale.of(context).get('nfc_preparing')),
        ],
      );
    }

    switch (_state) {
      case NfcSessionState.idle:
      case NfcSessionState.waitingForTap:
        return _buildWaitingState(colorScheme, myName);

      case NfcSessionState.pendingConfirmation:
        return _buildConfirmationState(context, colorScheme);

      case NfcSessionState.completed:
        return _buildCompletedState(colorScheme);

      case NfcSessionState.failed:
        return _buildFailedState(colorScheme);
    }
  }

  Widget _buildWaitingState(ColorScheme colorScheme, String myName) {
    final locale = AppLocale.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.nfc, size: 80, color: colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          locale.get('nfc_exchange_as'),
          style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          myName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.phonelink_ring, size: 48, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                locale.get('nfc_hold_phones'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                locale.get('nfc_both_apps_open'),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onPrimaryContainer.withAlpha(180),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          backgroundColor: colorScheme.surfaceContainerHighest,
          color: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildConfirmationState(
      BuildContext context, ColorScheme colorScheme) {
    final locale = AppLocale.of(context);
    final reading = _reading;
    final card = reading?.card;
    final lock = reading == null ? null : InvitationRedeem.errorOf(locale, reading);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_add, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          locale.get('nfc_contact_found'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        if (card != null) ...[
          const SizedBox(height: 12),
          Text(invitationFingerprintText(locale, card.fingerprint),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
        if (lock != null) ...[
          const SizedBox(height: 8),
          Text(lock,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error)),
        ] else if (reading != null && reading.expiresSoon) ...[
          const SizedBox(height: 8),
          Text(invitationExpiryWarning(locale, reading.daysLeft!),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        Text(
          locale.get('nfc_add_as_contact_question'),
          style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                _session?.cancelSession();
                Navigator.pop(context);
              },
              child: Text(locale.get('reject')),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(locale.get('accept')),
              onPressed: (_sending || lock != null) ? null : _confirm,
            ),
          ],
        ),
      ],
    );
  }

  /// Redeems the received card — the same service function as the
  /// QR scanner. The acceptance follows at the issuer without a second question.
  Future<void> _confirm() async {
    final locale = AppLocale.read(context);
    final bytes = _session?.confirm();
    if (bytes == null) return;
    setState(() => _sending = true);
    final r = await widget.service.redeemInvitationCardBytes(Uint8List.fromList(bytes));
    if (!mounted) return;
    final ok = r.outcome == InvitationRedeemOutcome.requestSent;
    setState(() {
      _sending = false;
      _result = invitationRedeemText(locale, r);
      _state = ok ? NfcSessionState.completed : NfcSessionState.failed;
      if (!ok) _error = _result;
    });
    if (ok) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context); // ignore: use_build_context_synchronously
      });
    }
  }

  Widget _buildCompletedState(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 80, color: Colors.green),
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text(
            _result!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: colorScheme.onSurface),
          ),
        ],
      ],
    );
  }

  Widget _buildFailedState(ColorScheme colorScheme) {
    final locale = AppLocale.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 64, color: colorScheme.error),
        const SizedBox(height: 16),
        Text(
          locale.get('nfc_exchange_failed'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.error,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            final old = _ownCard;
            if (old != null && !_touched) {
              unawaited(widget.service.revokeInvitationCard(old));
            }
            setState(() {
              _state = NfcSessionState.idle;
              _error = null;
              _reading = null;
              _ownCard = null;
              _touched = false;
              _starting = true;
            });
            _initSession();
          },
          child: Text(locale.get('retry')),
        ),
      ],
    );
  }
}
