/// The registration of the own codes with EACH fixed neighbour (V4.2 §8.1
/// "Every node tells each of its fixed neighbours", proposal "contacts as
/// fixed neighbours", §6.2).
///
/// Until 2026-09 there was one fixed neighbour and one [Registrant]. Now a
/// node has up to four fixed neighbours — up to three contact seats and the
/// card's seat (`neighbourhood_contacts.dart`) — and every one of them must
/// hold the same codes, because a sender hands its packet to whichever of
/// them the recipient named. Each fixed neighbour therefore gets its own
/// [Registrant]: what one of them has received says nothing about another.
///
/// The pieces travel as `0x24` packets of their own, at the edges of §8.1
/// only (`CodeRoute.edge`, `code_registration_send.dart`; F-B). What a
/// neighbour has received is kept by its [Neighbour.id], not by its first
/// address: when a `0x25` from another address of the same node moves that
/// address to the front, the node has the codes all the same, and the list
/// is not sent again.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/code_registration.dart';
import 'package:mycelium/neighbour.dart';

/// One [Registrant] per fixed neighbour, kept by [Neighbour.id].
class Registrants {
  final Registrant Function() _make;
  final Map<int, Registrant> _by = {};

  /// The registrant that handed out the last piece — the one [sent] counts.
  Registrant? _last;

  /// Pieces sent to all fixed neighbours together — read only.
  int piecesSent = 0;

  Registrants(this._make);

  /// The next piece for [target] on day [today] if [target] is an address
  /// of one of the [fixed] neighbours — `null` otherwise, or if that
  /// neighbour has everything. A registrant of a neighbour that is no
  /// longer fixed is dropped; one that becomes fixed again starts afresh.
  Uint8List? next(
      List<Neighbour> fixed, (InternetAddress, int) target, int today) {
    _by.removeWhere((id, _) => !fixed.any((n) => n.id == id));
    for (final n in fixed) {
      if (!n.has(target.$1, target.$2)) continue;
      final r = _last = _by.putIfAbsent(n.id, _make);
      return r.next('${n.id}', today);
    }
    _last = null;
    return null;
  }

  /// The piece [next] handed out last has left the wire.
  void sent() {
    final r = _last;
    if (r == null || r.pending == 0) return;
    r.sent();
    piecesSent++;
  }

  /// Pieces still outstanding for the neighbour of the last [next].
  int get pending => _last?.pending ?? 0;

  /// Forgets every state — the next opportunity sends everything anew to
  /// every fixed neighbour (edge: the codes changed).
  void forget() {
    for (final r in _by.values) {
      r.forget();
    }
  }
}
