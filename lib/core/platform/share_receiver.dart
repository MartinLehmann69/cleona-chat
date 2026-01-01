// Android share target (bug #U16). Kotlin stashes the ACTION_SEND payload,
// we drain it via MethodChannel and show a contact picker.
//
// ── THE LINE ABOUT THE TWO-STAGE TRANSFER IS GONE (02.09.2026) ──────
//
// Here it said: "sendMediaMessage internally triggers two-stage at >256KB
// (docs/MESSAGING.md)". The two-stage path fell with the CUT of 31.08.,
// and so did the 256 KB — the lower limit of the media lanes
// lies at 32 KB (§9.3, `kFountainWorthwhileBytes`). A comment that
// describes a torn-down path is worse than none.
//
// ── AND THERE IS NO MODE QUESTION ANY MORE (S389) ────────────────────────
//
// This path is a FULL send path, not a side entrance: what comes in via
// "Share" goes out through the same `sendMediaMessage` as a
// file from the chat. Until S389 the same consent dialog as
// in the chat stood here — triggered by the chat being set to high-secure. The
// switch is gone (§12.1: "No per-chat setting, no explanatory dialog,
// no switch"), and thus also its trigger. What §24.4.5 demands at this place
// instead stands as finding B-M2 in
// `mycelium/berichte/S389-BAU-MODUS.md`.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/deep_link_receiver.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/service_interface.dart';

class ShareReceiver {
  static const _channel = MethodChannel('chat.cleona/share');
  static final _log = CLogger.get('share-receiver', profileDir: AppPaths.dataDir);

  /// Called by [LifecycleDrainObserver] on resume and via post-frame callback
  /// on cold start.  No lifecycle handler of its own — the observer covers it.
  ///
  /// Returns `true` once the service was ready for this attempt (whether or
  /// not a payload was actually pending), `false` if the service was still
  /// null — in that case the native stash is left untouched (checked BEFORE
  /// `consumePendingShare` is invoked) so a later retry can still recover it.
  ///
  /// ANDROID-ONLY (S372, channel 1). `chat.cleona/share` has no counterpart
  /// under `ios/` or `macos/` — no Share Extension target exists there, so
  /// nothing ever stashes a payload for `consumePendingShare` to drain.
  /// This used to run unconditionally (this observer is armed on Android
  /// AND iOS, `lifecycle_drain_observer.dart:40`), throwing a
  /// `MissingPluginException` on every iOS cold start/resume that the
  /// blanket `catch` below silently discarded. Restricting the call to
  /// Android is the honest state of the world, not a workaround: building
  /// the iOS side needs a new Xcode extension target, which is out of
  /// scope here and is not something to hand-edit into project.pbxproj
  /// unverified.
  static Future<bool> drainPending(
    BuildContext Function() contextProvider,
    ICleonaService? Function() serviceProvider,
  ) async {
    if (!Platform.isAndroid) return true;
    final service = serviceProvider();
    if (service == null) return false;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('consumePendingShare');
      if (raw == null) return true;
      final text = (raw['text'] as String?) ?? '';
      final files = ((raw['files'] as List?) ?? const []).cast<String>();
      if (text.isEmpty && files.isEmpty) return true;
      // V4.2 §15.2: "one line of text … for pasting into a chat, a mail, a
      // note". Whoever SHARES such a line from another program with Cleona
      // wants to redeem it, not forward it to a contact.
      // Plain text only: with files it stays the usual share path.
      if (files.isEmpty && text.contains('cleona:1:')) {
        DeepLinkReceiver.handleInvitationText(contextProvider(), service, text);
        return true;
      }
      await _promptAndSend(contextProvider(), service, text, files);
    } catch (e) {
      // Named instead of swallowed (S372, channel 1) — share reception must
      // still never break the app start, that is why it stays a
      // log instead of a rethrow.
      _log.warn('Share receive failed: $e — start continues');
    }
    return true;
  }

  static Future<void> _promptAndSend(
    BuildContext ctx, ICleonaService service, String text, List<String> files,
  ) async {
    final contacts = service.acceptedContacts;
    // Capture messenger BEFORE await — BuildContext must not cross an async gap.
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (contacts.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('No contacts available.')));
      return;
    }
    final nodeIdHex = await showDialog<String>(
      context: ctx,
      builder: (d) => SimpleDialog(
        title: const Text('Share with Cleona'),
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
      // conversationId == nodeIdHex for DMs; the lane choice goes by
      // SIZE (§9.4), not by a mode.
      //
      // NO CONSENT QUESTION AT THIS PLACE ANY MORE (S389). Here
      // the question was asked when the chat was set to high-secure — i.e. only
      // when the user had flipped the switch from §12.1 that must not
      // exist. With the switch its condition falls, and
      // with it the special handling for a missing window: without a
      // dialog this path no longer needs `ctx.mounted`.
      //
      // §24.4.5 demands consent per transfer as soon as a
      // file takes a media lane; that it is missing today stands as
      // finding B-M2 in `mycelium/berichte/S389-BAU-MODUS.md` — with the
      // measurement that the bulk lane has no transport in 4.2 anyway.
      await service.sendMediaMessage(nodeIdHex, path);
    }
    final label = contacts.firstWhere((c) => c.nodeIdHex == nodeIdHex, orElse: () => contacts.first).displayName;
    messenger?.showSnackBar(SnackBar(
        content: Text('Sent to $label.')));
  }

}
