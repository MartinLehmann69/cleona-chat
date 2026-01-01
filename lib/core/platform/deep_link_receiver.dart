import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/contact/channel_uri.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/ui/components/invitation_messages.dart';
import 'package:cleona/ui/components/invitation_redeem.dart';

/// Entrance for links from outside: channel links (`cleona://channel…`) and
/// invitation cards in text form (`cleona:1:<base64url>`, V4.2 §15.6).
///
/// Android delivers both via the same intent filter (`scheme="cleona"`
/// in `AndroidManifest.xml`) — `cleona:1:…` is a valid, opaque URI
/// with this scheme. The ContactSeed path of the V4.1 line (`cleona://<id>?…`)
/// is removed here: V4.2 knows no ContactSeed.
class DeepLinkReceiver {
  static const _androidChannel = MethodChannel('chat.cleona/share');
  static const _iosChannel = MethodChannel('chat.cleona/deeplink');

  /// Called by [LifecycleDrainObserver] on resume and via post-frame callback
  /// on cold start.  No lifecycle handler of its own — the observer covers it.
  ///
  /// Returns `true` once the service was ready for this attempt (whether or
  /// not a deep link was actually pending), `false` if the service was still
  /// null — in that case the native stash is left untouched (checked BEFORE
  /// `consumePendingDeepLink` is invoked) so a later retry can still recover it.
  static Future<bool> drainPending(
    BuildContext Function() contextProvider,
    ICleonaService? Function() serviceProvider,
  ) async {
    final service = serviceProvider();
    if (service == null) return false;
    try {
      String? uri;
      if (Platform.isAndroid) {
        uri = await _androidChannel.invokeMethod<String>('consumePendingDeepLink');
      } else if (Platform.isIOS) {
        uri = await _iosChannel.invokeMethod<String>('consumePendingDeepLink');
      }
      if (uri == null || uri.isEmpty) return true;
      _handleUri(contextProvider(), service, uri);
    } catch (_) {}
    return true;
  }

  static void _handleUri(BuildContext ctx, ICleonaService service, String uri) {
    final channelUri = ChannelUri.parse(uri);
    if (channelUri != null) {
      _showJoinChannelDialog(ctx, service, channelUri);
      return;
    }
    // Everything else is either an invitation card or nothing — and
    // "nothing" gets the sentence from §15.6 ("no invitation in that text"),
    // not a collective message.
    handleInvitationText(ctx, service, uri);
  }

  /// Reads [text] as an invitation, shows the reason for a rejection or asks
  /// whether the request should go out. Also used by the Android share entrance
  /// (`share_receiver.dart`).
  static void handleInvitationText(
      BuildContext ctx, ICleonaService service, String text) {
    final locale = AppLocale.read(ctx);
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    // Read BEFORE the `await`: `Theme.of` after an asynchronous gap is
    // an access to a BuildContext that may be gone by then.
    final errorColor = Theme.of(ctx).colorScheme.error;

    final reading = InvitationRedeem.readText(text);
    final reason = InvitationRedeem.errorOf(locale, reading);
    if (reason != null) {
      messenger?.showSnackBar(SnackBar(
        backgroundColor: errorColor,
        content: Text(reason),
      ));
      return;
    }

    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.person_add, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(locale.get('add_contact'))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(invitationFingerprintText(locale, reading.card!.fingerprint)),
            // §15.3: expiring soon warns before the user confirms.
            if (reading.expiresSoon) ...[
              const SizedBox(height: 8),
              Text(invitationExpiryWarning(locale, reading.daysLeft!)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              InvitationRedeem.send(
                service: service,
                messenger: messenger,
                locale: locale,
                errorColor: errorColor,
                text: text,
              );
            },
            child: Text(locale.get('send')),
          ),
        ],
      ),
    );
  }

  static void _showJoinChannelDialog(
    BuildContext ctx,
    ICleonaService service,
    ChannelUri channelUri,
  ) {
    final locale = AppLocale.read(ctx);
    final messenger = ScaffoldMessenger.maybeOf(ctx);

    if (service.channels.containsKey(channelUri.channelIdHex) ||
        service.conversations.containsKey(channelUri.channelIdHex)) {
      messenger?.showSnackBar(SnackBar(
        content: Text(locale.get('channel_already_member')),
      ));
      return;
    }

    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.campaign, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(
            channelUri.name.isNotEmpty ? channelUri.name : 'Channel',
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        content: Text(locale.get('join_channel_question')
            .replaceAll('{name}', channelUri.name.isNotEmpty ? channelUri.name : channelUri.channelIdHex.substring(0, 16))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(d);
              final ok = await service.joinPublicChannel(channelUri.channelIdHex);
              if (ok) {
                messenger?.showSnackBar(SnackBar(
                  content: Text(locale.get('channel_joined_success')),
                ));
              } else {
                messenger?.showSnackBar(SnackBar(
                  content: Text(locale.get('channel_not_found')),
                ));
              }
            },
            child: Text(locale.get('channel_join')),
          ),
        ],
      ),
    );
  }
}
