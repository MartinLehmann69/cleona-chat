import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/network/channel_uri.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/i18n/app_locale.dart';

class DeepLinkReceiver {
  static const _androidChannel = MethodChannel('chat.cleona/share');
  static const _iosChannel = MethodChannel('chat.cleona/deeplink');
  static bool _wired = false;

  static void init({
    required BuildContext Function() contextProvider,
    required ICleonaService? Function() serviceProvider,
  }) {
    if (_wired) return;
    _wired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drain(contextProvider, serviceProvider);
    });
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == 'AppLifecycleState.resumed') {
        await _drain(contextProvider, serviceProvider);
      }
      return null;
    });
  }

  static Future<void> _drain(
    BuildContext Function() contextProvider,
    ICleonaService? Function() serviceProvider,
  ) async {
    try {
      String? uri;
      if (Platform.isAndroid) {
        uri = await _androidChannel.invokeMethod<String>('consumePendingDeepLink');
      } else if (Platform.isIOS) {
        uri = await _iosChannel.invokeMethod<String>('consumePendingDeepLink');
      }
      if (uri == null || uri.isEmpty) return;
      final service = serviceProvider();
      if (service == null) return;
      _handleUri(contextProvider(), service, uri);
    } catch (_) {}
  }

  static void _handleUri(BuildContext ctx, ICleonaService service, String uri) {
    final channelUri = ChannelUri.parse(uri);
    if (channelUri != null) {
      _showJoinChannelDialog(ctx, service, channelUri);
      return;
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
