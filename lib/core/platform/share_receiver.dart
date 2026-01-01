// Android-Share-Target (Bug #U16). Kotlin stasht ACTION_SEND-Payload,
// wir drainen per MethodChannel und zeigen einen Kontakt-Picker.
// sendMediaMessage triggert intern Two-Stage bei >256KB (docs/MESSAGING.md).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/service/service_interface.dart';

class ShareReceiver {
  static const _channel = MethodChannel('chat.cleona/share');
  static bool _wired = false;

  static void init({
    required BuildContext Function() contextProvider,
    required ICleonaService? Function() serviceProvider,
  }) {
    if (!Platform.isAndroid || _wired) return;
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
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('consumePendingShare');
      if (raw == null) return;
      final text = (raw['text'] as String?) ?? '';
      final files = ((raw['files'] as List?) ?? const []).cast<String>();
      if (text.isEmpty && files.isEmpty) return;
      final service = serviceProvider();
      if (service == null) return;
      await _promptAndSend(contextProvider(), service, text, files);
    } catch (_) {/* Share-Empfang darf App-Start nie brechen. */}
  }

  static Future<void> _promptAndSend(
    BuildContext ctx, ICleonaService service, String text, List<String> files,
  ) async {
    final contacts = service.acceptedContacts;
    // Messenger VOR await capturen — BuildContext darf nicht ueber async-gap.
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (contacts.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('Keine Kontakte vorhanden.')));
      return;
    }
    final nodeIdHex = await showDialog<String>(
      context: ctx,
      builder: (d) => SimpleDialog(
        title: const Text('Mit Cleona teilen'),
        children: [
          for (final c in contacts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, c.nodeIdHex),
              child: Text(c.displayName.isNotEmpty ? c.displayName : c.nodeIdHex.substring(0, 16)),
            ),
        ],
      ),
    );
    if (nodeIdHex == null) return;
    if (text.isNotEmpty) await service.sendTextMessage(nodeIdHex, text);
    for (final path in files) {
      if (!File(path).existsSync()) continue;
      // conversationId == nodeIdHex fuer DMs; sendMediaMessage entscheidet inline vs. two-stage.
      await service.sendMediaMessage(nodeIdHex, path);
    }
    final label = contacts.firstWhere((c) => c.nodeIdHex == nodeIdHex, orElse: () => contacts.first).displayName;
    messenger?.showSnackBar(SnackBar(content: Text('An $label gesendet.')));
  }
}
