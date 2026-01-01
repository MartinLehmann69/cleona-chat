/// The enrolment of an own device at the node (V4.2 §14.6.1, §13.0, D-39,
/// D-40): the one kind dispatch for `0x80..0x83`, the direct handover, and
/// the mark "search only".
///
/// ── SEARCH ONLY (D-40) ───────────────────────────────────────────────────
///
/// A fresh install that entered the words searches for the bundle only and
/// collects no post of the identity before the bundle is found or the user
/// chooses recovery — a device that collected and deleted it would take it
/// from a living device that never sees it (§13.0). The node keeps the
/// identity registered (a host needs one to start), but while it is HELD
/// its collection pass asks none of its values (`node_post_box.dart`) and
/// it answers no search call in its name (`node_call.dart`).
///
/// ── THE DIRECT HANDOVER ──────────────────────────────────────────────────
///
/// "Directly while both are present, otherwise in the post box"
/// (§14.6.1 step 4): [NodeEnrolment.enrolDirect] sends every piece once to
/// the address the request named and waits for its acknowledgement until a
/// deadline; what is not acknowledged is returned, and the caller deposits
/// it. No retry here, no clock after the deadline.
///
/// Next to the node in [Expando]s: `node.dart` is at its line budget.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/identity.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';

/// The length of a value (§8.2) and of a piece digest in `0x83`.
const int kEnrolValueLength = 16;

/// How long a direct handover waits for the acknowledgements.
const Duration kEnrolDirectDeadline = Duration(seconds: 5);

/// What an enrolment packet is given to: `true` when it was taken.
typedef EnrolReceiver = bool Function(
    int kind, Uint8List value, Uint8List rest, CardAddress from);

final Expando<Set<Identity>> _held = Expando<Set<Identity>>('postHeld');
final Expando<List<EnrolReceiver>> _receivers =
    Expando<List<EnrolReceiver>>('enrolReceivers');
final Expando<Map<String, Completer<void>>> _waiting =
    Expando<Map<String, Completer<void>>>('enrolAcks');

final SodiumFFI _na = SodiumFFI();

extension NodeEnrolment on Node {
  /// Whether [i] is held: search only, no own post (D-40).
  bool postHeld(Identity i) => _held[this]?.contains(i) ?? false;

  /// Holds [i] (`true`) or releases it. Releasing is no collection edge of
  /// its own: the caller collects when it releases (the user's choice).
  void postHold(Identity i, bool held) {
    final s = _held[this] ??= <Identity>{};
    if (held ? s.add(i) : s.remove(i)) {
      report('enrolment: identity ${_short(i.identifier)} '
          '${held ? "held — search only, no own post (D-40)" : "released"}');
    }
  }

  /// Registers [r] for the packets `0x80`/`0x82` (`enrol_window.dart`,
  /// `enrol_wait.dart`); [enrolReceiverRemove] ends it.
  void enrolReceiverAdd(EnrolReceiver r) => (_receivers[this] ??= []).add(r);
  void enrolReceiverRemove(EnrolReceiver r) => _receivers[this]?.remove(r);

  /// The kind dispatch for `0x80..0x83` (`node_helpers.dart`). A packet
  /// nobody takes is discarded without an answer.
  void enrolmentReceive(Uint8List data, InternetAddress from, int fromPort) {
    if (data.length < 1 + kEnrolValueLength) return;
    final kind = data[0];
    final value = Uint8List.sublistView(data, 1, 1 + kEnrolValueLength);
    final rest = Uint8List.sublistView(data, 1 + kEnrolValueLength);
    if (kind == kinds.kEnrolHeard || kind == kinds.kEnrolPieceHeard) {
      final key = kind == kinds.kEnrolHeard
          ? 'call:${_hex(value)}'
          : '${_hex(value)}:${_hex(rest)}';
      final c = _waiting[this]?.remove(key);
      if (c != null && !c.isCompleted) c.complete();
      return;
    }
    final at = CardAddress(Uint8List.fromList(from.rawAddress), fromPort);
    for (final r in List.of(_receivers[this] ?? const <EnrolReceiver>[])) {
      if (r(kind, Uint8List.fromList(value), Uint8List.fromList(rest), at)) {
        return;
      }
    }
  }

  /// Sends `kind | value | rest` to [to].
  void enrolSend(int kind, Uint8List value, Uint8List rest, CardAddress to) =>
      rawSend(
          Uint8List.fromList([kind, ...value, ...rest]), to);

  /// The call of [value] was heard (`0x81`) within [deadline].
  Future<bool> enrolCallHeard(Uint8List value, Duration deadline) =>
      _await('call:${_hex(value)}', deadline);

  /// Sends [pieces] directly to [to] under [value] and waits up to
  /// [deadline] for their acknowledgements. Returns the pieces NOT
  /// acknowledged — for the post box. Does not throw.
  Future<List<Uint8List>> enrolDirect(
      CardAddress to, Uint8List value, List<Uint8List> pieces,
      {Duration deadline = kEnrolDirectDeadline}) async {
    final waits = <Future<bool>>[];
    for (final p in pieces) {
      final key = '${_hex(value)}:${_hex(enrolDigest(p))}';
      waits.add(_await(key, deadline));
      try {
        enrolSend(kinds.kEnrolPiece, value, p, to);
      } on Object catch (e) {
        report('enrolment: direct piece not sent — $e');
      }
    }
    final heard = await Future.wait(waits);
    final rest = [
      for (var i = 0; i < pieces.length; i++)
        if (!heard[i]) pieces[i],
    ];
    report('enrolment: ${pieces.length - rest.length} of ${pieces.length} '
        'piece(s) acknowledged directly');
    return rest;
  }

  Future<bool> _await(String key, Duration deadline) {
    final c = Completer<void>();
    (_waiting[this] ??= {})[key] = c;
    return c.future.then((_) => true).timeout(deadline, onTimeout: () {
      _waiting[this]?.remove(key);
      return false;
    });
  }
}

/// The first 16 B of SHA-256 of a piece — its acknowledgement in `0x83`.
Uint8List enrolDigest(Uint8List piece) =>
    Uint8List.fromList(_na.sha256(piece).sublist(0, kEnrolValueLength));

bool enrolSame(Uint8List a, Uint8List b) => _hex(a) == _hex(b);

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _short(Uint8List b) => _hex(b.sublist(0, 4));
