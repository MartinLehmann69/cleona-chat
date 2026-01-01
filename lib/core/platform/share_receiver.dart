// Android share target (bug #U16). Kotlin stashes the ACTION_SEND payload,
// we drain it via MethodChannel and show a contact picker.
//
// ── ONE QUESTION PER FILE, NO MODE QUESTION ──────────────────────────────
//
// This path is a FULL send path, not a side entrance: what comes in via
// "Share" goes out through the same `sendMediaMessage` as a file from the
// chat, and a file that takes a media lane is asked for through the same
// gate (`mediaLaneConsentFor`, §9.4 "Consent", §24.4.5). There is no
// per-chat switch that triggers it (§12.1): the size of the file does —
// below 256 KB it is one message (lane 1), from there on a media lane
// (`laneChoose`, §9.4).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/deep_link_receiver.dart';
import 'package:cleona/core/media/transient_files.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/ui/components/media_consent_dialog.dart';

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
      // S401: the shared files are COPIES the Android side laid into the
      // app's cache (`cacheDir/shared_in`) — plaintext of what is about to
      // become a message. [promptAndSend] deletes them when the operation
      // is over. What a process death in between left behind goes here,
      // ONCE per process: at this edge the pending share has just been
      // handed over, so a file in that directory that is neither in it nor
      // in a share still being asked about belongs to no operation.
      _inFlight.addAll(files);
      if (!_leftoversCleared) {
        _leftoversCleared = true;
        TransientFiles.sweepSharedIn(keep: _inFlight);
      }
      if (text.isEmpty && files.isEmpty) return true;
      // V4.2 §15.2: "one line of text … for pasting into a chat, a mail, a
      // note". Whoever SHARES such a line from another program with Cleona
      // wants to redeem it, not forward it to a contact.
      // Plain text only: with files it stays the usual share path.
      // Both line forms: `cleona:1:` (card) and `cleona:2:` (card + keys,
      // proposal E) — the only form an issuer hands out since then.
      if (files.isEmpty &&
          (text.contains('cleona:1:') || text.contains('cleona:2:'))) {
        DeepLinkReceiver.handleInvitationText(contextProvider(), service, text);
        return true;
      }
      await promptAndSend(contextProvider(), service, text, files);
    } catch (e) {
      // Named instead of swallowed (S372, channel 1) — share reception must
      // still never break the app start, that is why it stays a
      // log instead of a rethrow.
      _log.warn('Share receive failed: $e — start continues');
    }
    return true;
  }

  /// The contact picker and the sending of a drained share payload. Public
  /// for widget tests only: the way in is [drainPending].
  ///
  /// S401: THE ONE PLACE AT WHICH A SHARED-IN FILE GOES. However this ends
  /// — sent, no contact chosen, the question declined, no contacts at all —
  /// the operation is over and the copies in the app's cache have no
  /// purpose any more. `sendMediaMessage` has returned by then, i.e. the
  /// service has read the file and laid the attachment down sealed.
  @visibleForTesting
  static Future<void> promptAndSend(
    BuildContext ctx, ICleonaService service, String text, List<String> files,
  ) async {
    try {
      await _promptAndSend(ctx, service, text, files);
    } finally {
      for (final path in files) {
        TransientFiles.discardSurface(path);
      }
      _inFlight.removeAll(files);
    }
  }

  /// Shared-in files of a share that is still being asked about; the
  /// start-edge sweep in [drainPending] leaves them alone.
  static final Set<String> _inFlight = {};
  static bool _leftoversCleared = false;

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
    var handedOver = text.isNotEmpty;
    if (text.isNotEmpty) await service.sendTextMessage(nodeIdHex, text);
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      // conversationId == nodeIdHex for DMs; the lane choice goes by
      // SIZE (§9.4), not by a mode. A file that takes a media lane is asked
      // for, per file, through the same gate as a file from the chat
      // (§9.4 "Consent", §24.4.5); without a yes it is not sent. Without a
      // window nothing can be asked, so the rest stays unsent.
      if (!ctx.mounted) break;
      final consent = await mediaLaneConsentFor(ctx,
          length: file.lengthSync(), isGroup: false);
      if (consent == null) continue;
      await service.sendMediaMessage(nodeIdHex, path, consent: consent);
      handedOver = true;
    }
    if (!handedOver) return;
    final label = contacts.firstWhere((c) => c.nodeIdHex == nodeIdHex, orElse: () => contacts.first).displayName;
    messenger?.showSnackBar(SnackBar(
        content: Text('Sent to $label.')));
  }

}
