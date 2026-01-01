/// The deposit of a post with its keepers (V4.2 §16.2.5 step 2): the author
/// leaves the entry with the first three keepers of the list that answer
/// (`0x60`); the post is placed at the second acknowledgement (`0x61`). A
/// keeper that does not answer — §11.3a, through [Silence] — or that refuses
/// gives way to the next on the list.
///
/// No clock and no repeat of its own: every `0x60` is a request of the
/// transport (`silence.dart`), which repeats it and gives up. A post that is
/// not placed is the application's to deposit again at the edges of §8.2
/// (§9.3) — as a new sending.
///
/// The proof of work is computed once per value and shown to a keeper until
/// that keeper has acknowledged an entry under the value
/// (`channel_proof.dart`).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/channel_chain.dart';
import 'package:mycelium/channel_keeper.dart' show ChannelSend;
import 'package:mycelium/channel_proof.dart';
import 'package:mycelium/channel_wire.dart' as w;
import 'package:mycelium/silence.dart';
import 'package:mycelium/split.dart' show endedAfter, kRestPeriod;

/// Keepers an author leaves a post with (§16.2.5 step 2).
const int kDepositAt = 3;

/// Acknowledgements that place a post.
const int kPlacedAt = 2;

/// What an author needs to deposit under one value.
typedef DepositKeys = ({
  Uint8List value,
  Uint8List collectPk,
  Uint8List generationPk,
  Uint8List authorPk,
  Uint8List authorSk,
  Uint8List certificate,
});

/// How a deposit ended: [held] keepers took the entry; [failed] the
/// keepers which refused or whose address the transport declared failed
/// (§11.3a: only with counter-evidence — a congested or dead uplink fails
/// nobody) — the owner's next list leaves them out (§16.2.5 "Keepers").
typedef DepositEnd = ({bool placed, List<CardAddress> held, List<CardAddress> failed});

class ChannelDepositor {
  final ChannelSend send;
  final Silence silence;
  final void Function(String)? report;
  final Random _random = Random.secure();

  final Map<String, Completer<w.HeldVerdict>> _waiting = {};
  final Map<String, ({Uint8List proof, int window})> _proofs = {};
  final Set<String> _provenAt = {};

  /// Addresses the transport declared failed while a hold to them ran
  /// (`address:port`, filled by `host_channel.dart` from the readiness).
  final Set<String> declared = {};

  ChannelDepositor({required this.send, required this.silence, this.report});

  static String keyOf(CardAddress k) =>
      '${InternetAddress.fromRawAddress(k.address).address}:${k.port}';

  Uint8List _request() => Uint8List.fromList(
      List<int>.generate(w.kChannelRequestLength, (_) => _random.nextInt(256)));

  /// `0x61` from a keeper.
  void onHeld(Uint8List p) {
    final h = w.heldRead(p);
    if (h == null) return;
    final c = _waiting.remove(hexOf(h.request));
    if (c != null && !c.isCompleted) c.complete(h.verdict);
  }

  Future<Uint8List> _proof(Uint8List value) async {
    final k = hexOf(value);
    final p = _proofs[k];
    if (p != null && channelProofWindow() - p.window < 1) return p.proof;
    final proof = await channelProof(value);
    _proofs[k] = (proof: proof, window: channelProofWindow());
    while (_proofs.length > 64) {
      _proofs.remove(_proofs.keys.first);
    }
    return proof;
  }

  /// Deposits [entry] under [keys] with [keepers], in their order.
  /// [onPlaced] fires once, at the second acknowledgement.
  Future<DepositEnd> deposit(Uint8List entry, DepositKeys keys,
      List<CardAddress> keepers, {void Function()? onPlaced}) async {
    final held = <CardAddress>[], failed = <CardAddress>[];
    var next = 0;
    var placedNoted = false;
    Future<void> one(CardAddress k) async {
      final v = await _at(k, entry, keys);
      if (v == w.HeldVerdict.held) {
        held.add(k);
        if (held.length >= kPlacedAt && !placedNoted) {
          placedNoted = true;
          onPlaced?.call();
        }
        return;
      }
      // A refusal, or an address declared failed, leaves the list; silence
      // without counter-evidence does not (§11.3a).
      if (v != null || declared.remove(keyOf(k))) failed.add(k);
      // Gives way to the next keeper of the list (§16.2.5 step 2): the post
      // goes to the first three that answer.
      if (held.length < kDepositAt && next < keepers.length) {
        await one(keepers[next++]);
      }
    }

    final first = <Future<void>>[];
    while (next < keepers.length && first.length < kDepositAt) {
      first.add(one(keepers[next++]));
    }
    await Future.wait(first);
    final placed = held.length >= kPlacedAt;
    report?.call('channel deposit under ${hexOf(keys.value).substring(0, 8)}: '
        '${held.length} held, ${failed.length} failed or refused — '
        '${placed ? 'placed' : 'not placed'}');
    return (placed: placed, held: held, failed: failed);
  }

  /// One keeper: the verdict, or `null` when its addresses failed.
  Future<w.HeldVerdict?> _at(
      CardAddress k, Uint8List entry, DepositKeys keys) async {
    final mark = '${k.toString()}|${hexOf(keys.value)}';
    for (var withProof = _provenAt.contains(mark) ? false : true;;) {
      final request = _request();
      final packet = w.hold((
        request: request,
        value: keys.value,
        collectPk: keys.collectPk,
        generationPk: keys.generationPk,
        authorPk: keys.authorPk,
        certificate: keys.certificate,
        signature: sign(w.holdSigned(keys.value, entry, k), keys.authorSk),
        proof: withProof ? await _proof(keys.value) : null,
        entry: entry,
      ));
      final answer = Completer<w.HeldVerdict>();
      _waiting[hexOf(request)] = answer;
      final to = await silence.ask(answer.future,
          to: InternetAddress.fromRawAddress(k.address),
          port: k.port,
          send: (a, p) => send(packet, CardAddress(a.rawAddress, p)),
          wait: endedAfter(kRestPeriod),
          others: false,
          what: 'channel hold 0x60');
      _waiting.remove(hexOf(request));
      if (to == null || !answer.isCompleted) return null;
      final v = await answer.future;
      if (v == w.HeldVerdict.proofWanted && !withProof) {
        withProof = true; // the keeper lost the value: once more, with proof
        continue;
      }
      if (v == w.HeldVerdict.held) _provenAt.add(mark);
      return v;
    }
  }
}
