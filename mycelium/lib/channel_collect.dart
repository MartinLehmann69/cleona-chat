/// The collection of a member from its keepers (V4.2 §16.2.5 step 4).
///
/// At start, on a network change and when the user opens the group or
/// channel — never on a clock (§5.4) — the application asks the first keeper
/// of its newest list that answers (`0x62`): the channel values of the days
/// it still lacks, its state root over the hashes of the entries it holds or
/// has refused under those values (the formula of §16.0), and per value the
/// collect public key with a signature. Roots that agree: one packet back,
/// "same" (`0x63`). Otherwise the keeper lists its hashes (`0x64`), the
/// member fetches what it lacks (`0x65`), the keeper hands each out (`0x66`)
/// and closes the pass with the number (`0x67`).
///
/// Silence is the transport's (§11.3a): the question goes through
/// [Silence.ask], a fetch that brings nothing within its wait is asked again
/// as [SilentRounds] counts. A keeper that does not answer gives way to the
/// next. Nothing here repeats on its own account.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/channel_chain.dart';
import 'package:mycelium/channel_keeper.dart' show ChannelSend;
import 'package:mycelium/channel_wire.dart' as w;
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/silence.dart';
import 'package:mycelium/split.dart' show endedAfter, kRestPeriod;

/// One question: the values of one generation. [wanted] decides per listed
/// entry (hash hex, kind byte) whether it is fetched now — an inline image
/// only as "always load images" allows (§9.4); `null` fetches everything.
typedef CollectAsk = ({
  Uint8List generationPk,
  List<({Uint8List value, Uint8List collectPk, Uint8List collectSk})> values,
  Set<String> heldOrRefused,
  bool Function(String hash, int kind)? wanted,
});

/// How a collection ended: [same] — the keeper's root agreed; [keeper] — the
/// one that answered, `null` when none did; [got] entries taken.
typedef CollectEnd = ({bool same, CardAddress? keeper, int got});

class _Pass {
  final Completer<Uint8List> first = Completer();
  final List<List<w.Listed>?> parts = [];
  Completer<void> partsDone = Completer();
  Completer<void>? ended;
  DateTime last = DateTime.now();
  void Function(Uint8List value, Uint8List entry)? onEntry;
  int got = 0;
}

class ChannelCollector {
  final ChannelSend send;
  final Silence silence;
  final void Function(String)? report;
  final Random _random = Random.secure();
  final Map<String, _Pass> _passes = {};

  ChannelCollector({required this.send, required this.silence, this.report});

  /// `0x63`, `0x64`, `0x66`, `0x67` — matched to their pass by the request.
  void onAnswer(Uint8List p) {
    final r = w.requestOf(p);
    final pass = r == null ? null : _passes[hexOf(r)];
    if (pass == null) return;
    pass.last = DateTime.now();
    final list = w.listRead(p);
    if (list != null) {
      if (pass.parts.isEmpty) pass.parts.addAll(List.filled(list.parts, null));
      if (list.parts == pass.parts.length) {
        pass.parts[list.part] = list.items;
      }
      if (!pass.parts.contains(null) && !pass.partsDone.isCompleted) {
        pass.partsDone.complete();
      }
      if (!pass.first.isCompleted) pass.first.complete(p);
      return;
    }
    final e = w.entryRead(p);
    if (e != null) {
      pass.got++;
      pass.onEntry?.call(e.value, e.entry);
      return;
    }
    if (!pass.first.isCompleted) pass.first.complete(p);
    if (p.isNotEmpty && w.endRead(p) != null) {
      final c = pass.ended;
      if (c != null && !c.isCompleted) c.complete();
    }
  }

  /// Asks [keepers] in order until one answers; [onEntry] gets every entry
  /// handed out, as it arrives.
  Future<CollectEnd> collect(CollectAsk ask, List<CardAddress> keepers,
      void Function(Uint8List value, Uint8List entry) onEntry) async {
    for (final k in keepers) {
      final end = await _at(k, ask, onEntry);
      if (end != null) return end;
    }
    return (same: false, keeper: null, got: 0);
  }

  Future<CollectEnd?> _at(CardAddress k, CollectAsk ask,
      void Function(Uint8List value, Uint8List entry) onEntry) async {
    final request = Uint8List.fromList(List<int>.generate(
        w.kChannelRequestLength, (_) => _random.nextInt(256)));
    final key = hexOf(request);
    final root = stateRoot(ask.heldOrRefused.map(hexBytes));
    final packet = w.question((
      request: request,
      root: root,
      generationPk: ask.generationPk,
      items: [
        for (final v in ask.values.take(w.kValuesPerQuestion))
          (
            value: v.value,
            collectPk: v.collectPk,
            signature:
                sign(w.questionSigned(request, root, v.value, k), v.collectSk),
          )
      ],
    ));
    final pass = _Pass()..onEntry = onEntry;
    _passes[key] = pass;
    try {
      final at = await silence.ask(pass.first.future,
          to: InternetAddress.fromRawAddress(k.address),
          port: k.port,
          send: (a, p) => send(packet, CardAddress(a.rawAddress, p)),
          others: false,
          what: 'channel question 0x62');
      if (at == null || !pass.first.isCompleted) return null;
      final first = await pass.first.future;
      if (first.isEmpty || first[0] != kinds.kChannelList) {
        // "same", or "nothing here".
        return (same: first[0] == kinds.kChannelSame, keeper: k, got: 0);
      }
      // The other parts of the list arrive behind the first; what is still
      // missing after a quiet period is collected at the next edge.
      await _quiet(pass, pass.partsDone.future);
      final missing = <Uint8List>[
        for (final part in pass.parts.whereType<List<w.Listed>>())
          for (final it in part)
            if (!ask.heldOrRefused.contains(hexOf(it.hash)) &&
                (ask.wanted?.call(hexOf(it.hash), it.kind) ?? true))
              it.hash,
      ];
      for (var i = 0; i < missing.length; i += w.kHashesPerPacket) {
        final chunk = missing.sublist(
            i, min(i + w.kHashesPerPacket, missing.length));
        await _fetch(k, request, pass, chunk);
      }
      return (same: false, keeper: k, got: pass.got);
    } finally {
      _passes.remove(key);
    }
  }

  /// One fetch of [chunk], asked again for what is still missing as
  /// [SilentRounds] counts (§11.3a); a keeper that answered nothing at all has
  /// failed at that address.
  Future<void> _fetch(CardAddress k, Uint8List request, _Pass pass,
      List<Uint8List> chunk) async {
    final rounds = SilentRounds();
    var open = List.of(chunk);
    final onEntry = pass.onEntry;
    final seen = <String>{};
    pass.onEntry = (v, e) {
      seen.add(hexOf(entryHash(e)));
      onEntry?.call(v, e);
    };
    try {
      while (open.isNotEmpty) {
        final before = seen.length;
        pass.ended = Completer();
        pass.last = DateTime.now();
        send(w.fetch(request, open), k);
        await _quiet(pass, pass.ended!.future);
        open = open.where((h) => !seen.contains(hexOf(h))).toList();
        if (seen.length > before) rounds.progress();
        // The keeper closed the pass: what it did not hand out it does not
        // hold any more.
        if (open.isEmpty || pass.ended!.isCompleted) break;
        if (!rounds.again()) {
          if (seen.isEmpty) {
            silence.failedAddress(
                InternetAddress.fromRawAddress(k.address), k.port, 'channel fetch 0x65');
          }
          break;
        }
      }
    } finally {
      pass.onEntry = onEntry;
    }
  }

  /// Waits for [done], or until no answer has arrived for a quiet period —
  /// no timer runs while answers are arriving (§8.2).
  Future<void> _quiet(_Pass pass, Future<void> done) {
    final c = Completer<void>();
    final quiet = endedAfter(kRestPeriod);
    Timer? t;
    void arm() {
      final left = quiet - DateTime.now().difference(pass.last);
      t = Timer(left.isNegative ? Duration.zero : left, () {
        if (DateTime.now().difference(pass.last) >= quiet) {
          if (!c.isCompleted) c.complete();
        } else {
          arm(); // an answer arrived meanwhile: the quiet period starts over
        }
      });
    }

    arm();
    unawaited(done.then((_) {
      t?.cancel();
      if (!c.isCompleted) c.complete();
    }));
    return c.future;
  }
}
