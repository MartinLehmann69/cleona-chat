/// A face-to-face invitation lives 60 s (V4.2 §15.3, owner decision
/// 07.10.2026).
///
/// "A QR code shown person to person and an NFC exchange are handed over with
/// both people present and online, so the redemption takes seconds. If the
/// invitation has not been redeemed 60 s after it was shown, the device that
/// holds the identity closes it — the service, not the screen, so that
/// closing the app does not leave it standing."
///
/// ── WHAT THIS FILE HOLDS ─────────────────────────────────────────────────
///
/// The ONE rule, on the invitation record of the identity's mailbox:
///
/// * [MailboxFaceToFace.faceToFaceShown] — the front end shows an [inPerson]
///   invitation now; the moment goes into the record and to disk
///   (`inv.Invitation.shownAtMs`, `memory_invitation.dart`). The first
///   showing counts; the clock starts there and nowhere else.
/// * [MailboxFaceToFace.faceToFaceClose] — closes (revokes) every such
///   invitation whose 60 s since showing are over and which nobody redeemed.
///   The mailbox calls it at start (`Mailbox` constructor), so a restart
///   after the deadline does not leave one standing; the service calls it
///   when its local clock runs out.
/// * **At start, also the never-shown ones** ([MailboxFaceToFace.faceToFaceClose]
///   with `atStart`, owner decision 07.10.2026, S406-QR2 1A): a face-to-face
///   invitation that was issued but never shown — the app ended during the
///   wait of §12.4 or while "show anyway" was offered — never left the
///   device, and the front end that would have shown it is gone with the
///   run that issued it: a new mailbox has no waiting `invitationWayInAwait`,
///   and a front end that survived (a desktop GUI over IPC whose daemon
///   restarted) cannot be told apart at this moment. Its "show anyway" is
///   then answered `false` and it says so (`invitation_card_view.dart`).
/// * [MailboxFaceToFace.faceToFaceClosed] — the codes this rule closed in
///   this run, so the front end can say why a shown code disappeared
///   (closed, not redeemed — S406-QR2 2A).
/// * [MailboxFaceToFace.faceToFaceNext] — how long until the next one is
///   due, for that one local clock. No packet, no polling (working rule 5):
///   the clock begins at a showing and ends at the last close.
///
/// **A redeemed one is not closed.** Its first request was accepted
/// (`accepted > 0`, §15.3 "spent after the first accepted request"), and its
/// record keeps the re-contact answer possible (§15.5). An open invitation —
/// posted or printed — is never [inPerson] (`node_invitation.dart` refuses
/// that pair) and keeps its validity.
library;

import 'dart:math' show max;

import 'package:mycelium/invitation.dart' as inv;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/node_helpers.dart' show hexFrom;

/// §15.3: "If the invitation has not been redeemed 60 s after it was shown".
const Duration kFaceToFaceLife = Duration(seconds: 60);

Duration _life = kFaceToFaceLife;

/// The life in force — [kFaceToFaceLife] outside tests.
Duration get faceToFaceLife => _life;

/// Tests only: a shorter life, so a smoke need not wait a minute (pattern
/// `ownSegmentAssumeAllForTests`, `own_segment.dart`).
void faceToFaceLifeForTests(Duration life) => _life = life;

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Face to face, standing, not redeemed.
bool _open(inv.Invitation e) => e.inPerson && !e.revoke && e.accepted == 0;

/// Shown, standing, not redeemed: its clock runs.
bool _running(inv.Invitation e) => _open(e) && e.shownAtMs != null;

/// The codes (hex) [MailboxFaceToFace.faceToFaceClose] closed, per mailbox,
/// for this run only — at most a handful (§15.3: ten standing at most).
final Expando<Set<String>> _closed = Expando('faceToFaceClosed');

extension MailboxFaceToFace on Mailbox {
  /// The front end shows [e] now (§12.4: at once with a way in, after the
  /// wait, or "anyway" in the same W/LAN). Stamps the first showing and saves
  /// it. Returns whether [e] still stands — a closed or spent one must not be
  /// shown any more.
  bool faceToFaceShown(inv.Invitation e, {int? nowMs}) {
    final t = nowMs ?? _nowMs();
    if (!e.validAt(t ~/ 1000)) return false;
    if (!e.inPerson || e.shownAtMs != null) return true;
    e.shownAtMs = t;
    invitationsRemember(codes: false); // the code set did not change
    node.report('Invitation ${hexFrom(e.code).substring(0, 8)}: shown face to '
        'face — closed in ${_life.inSeconds} s unless redeemed (§15.3)');
    return true;
  }

  /// Closes every face-to-face invitation of this identity that was shown
  /// [faceToFaceLife] ago or longer and not redeemed. Returns their number.
  /// [atStart] (the `Mailbox` constructor): also those never shown (1A,
  /// see the file head), and without re-registering the own codes — that
  /// follows the construction anyway (`Host` → `codesAdmit`).
  int faceToFaceClose({int? nowMs, bool atStart = false}) {
    final t = nowMs ?? _nowMs();
    final closed = _closed[this] ??= <String>{};
    var n = 0;
    for (final e in identity.invitations.all) {
      if (!_open(e)) continue;
      final shown = e.shownAtMs;
      if (shown == null ? !atStart : t < shown + _life.inMilliseconds) {
        continue;
      }
      e.withdraw();
      closed.add(hexFrom(e.code));
      n++;
      node.report('Invitation ${hexFrom(e.code).substring(0, 8)}: face to '
          'face, ${shown == null ? 'never shown before this start' : 'not '
              'redeemed ${(t - shown) ~/ 1000} s after it was shown'} — '
          'closed (§15.3)');
    }
    if (n > 0) invitationsRemember(codes: !atStart);
    return n;
  }

  /// The codes (hex) of the face-to-face invitations [faceToFaceClose]
  /// closed in this run of the mailbox.
  Set<String> get faceToFaceClosed =>
      Set.unmodifiable(_closed[this] ?? const <String>{});

  /// How long until the next face-to-face invitation of this identity is due
  /// ([faceToFaceClose]); `null` = none is running.
  Duration? faceToFaceNext({int? nowMs}) {
    final t = nowMs ?? _nowMs();
    int? soonest;
    for (final e in identity.invitations.all) {
      if (!_running(e)) continue;
      final left = e.shownAtMs! + _life.inMilliseconds - t;
      soonest = soonest == null ? left : (left < soonest ? left : soonest);
    }
    return soonest == null ? null : Duration(milliseconds: max(0, soonest));
  }
}
