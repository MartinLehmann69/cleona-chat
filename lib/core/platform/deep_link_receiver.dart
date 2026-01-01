import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/network/channel_uri.dart';
import 'package:cleona/core/network/contact_seed.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/i18n/app_locale.dart';

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

    final seed = ContactSeed.fromUri(uri);
    if (seed != null) {
      if (seed.verifyIntegrity() == false) return;
      _showAddContactDialog(ctx, service, seed);
      return;
    }

    // Neither a channel URI nor a contact-seed URI — surface the failure
    // instead of silently dropping it (consistent with home_screen.dart's
    // manual-paste path).
    final locale = AppLocale.read(ctx);
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(SnackBar(
      backgroundColor: Theme.of(ctx).colorScheme.error,
      content: Text(locale.get('qr_invalid')),
    ));
  }

  static void _showAddContactDialog(
    BuildContext ctx,
    ICleonaService service,
    ContactSeed seed,
  ) {
    final locale = AppLocale.read(ctx);
    final messenger = ScaffoldMessenger.maybeOf(ctx);

    final localTag = NetworkSecret.channel == NetworkChannel.beta ? 'b' : 'l';
    if (!seed.isChannelCompatible(localTag)) {
      final localName = NetworkSecret.channel == NetworkChannel.beta ? 'Beta' : 'Live';
      messenger?.showSnackBar(SnackBar(
        backgroundColor: Theme.of(ctx).colorScheme.error,
        content: Text(locale.tr('channel_mismatch', {
          'contact': seed.channelDisplayName,
          'local': localName,
        })),
      ));
      return;
    }

    final name = seed.displayName.isNotEmpty
        ? seed.displayName
        : seed.nodeIdHex.substring(0, 16);

    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.person_add, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(
            locale.get('add_contact'),
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        content: Text(locale.tr('deeplink_contact_question', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(locale.get('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              _sendContactRequest(service, seed);
              messenger?.showSnackBar(SnackBar(
                content: Text(locale.get('contact_request_sent')),
              ));
            },
            child: Text(locale.get('send')),
          ),
        ],
      ),
    );
  }

  static void _sendContactRequest(ICleonaService service, ContactSeed seed) {
    final dxk = seed.deviceX25519Pk;
    final dmk = seed.deviceMlKemPk;
    final dxkB64 = dxk != null ? base64.encode(dxk) : null;
    final dmkB64 = dmk != null ? base64.encode(dmk) : null;
    final ep = seed.userEd25519Pk;
    final epB64 = ep != null ? base64Url.encode(ep).replaceAll('=', '') : null;
    final rn = seed.rendezvousNonce;
    final rnB64 = rn != null
        ? base64Url.encode(rn).replaceAll('=', '')
        : null;

    if (seed.seedPeers.isNotEmpty || seed.ownAddresses.isNotEmpty) {
      service.addPeersFromContactSeed(
        seed.nodeIdHex,
        seed.ownAddresses,
        seed.seedPeers.map((p) => (nodeIdHex: p.nodeIdHex, addresses: p.addresses)).toList(),
        targetDeviceIdHex: seed.deviceIdHex,
        targetDxkB64: dxkB64,
        targetDmkB64: dmkB64,
        targetEpB64: epB64,
        targetRendezvousNonceB64: rnB64,
      );
      Future.delayed(const Duration(seconds: 3), () {
        service.sendContactRequest(
          seed.nodeIdHex,
          seedDeviceIdHex: seed.deviceIdHex,
          seedDxkB64: dxkB64,
          seedDmkB64: dmkB64,
          seedEpB64: epB64,
        );
      });
    } else {
      service.sendContactRequest(
        seed.nodeIdHex,
        seedDeviceIdHex: seed.deviceIdHex,
        seedDxkB64: dxkB64,
        seedDmkB64: dmkB64,
        seedEpB64: epB64,
      );
    }
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
