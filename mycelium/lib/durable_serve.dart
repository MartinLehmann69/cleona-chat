/// The holder's side of the durable-object class — what a node answers to
/// `0x90`, `0x92`, `0x95` and `0x97` (v4_2 §16.0, §16.7, §11.5). S407 SK-1.
///
/// Every answer is an answer to exactly one request; nothing here sends on
/// its own or keeps a clock. A node that holds a channel answers for it; a
/// node that holds no channel ([DurableStock.heldChannels] empty — a phone)
/// names nothing, holds nothing, and therefore answers a deposit with `0x94`
/// and stays silent to the questions it is never asked (§16.0: only a node
/// that named an identifier or answered such a question is asked).
///
/// **Hand-out.** A fetch is answered with fresh fountain blocks of random
/// seed (rateless, as the update holder does, `update_holder.dart`): as many
/// as the object still needs by the fetching node's own count, plus a
/// margin for the coding overhead of small objects, in batches of
/// [kSendBatch] with one event-loop turn between them (§11.1).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_encoder.dart';
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_fetch.dart' show DurableSend, nodeKey;
import 'package:mycelium/durable_packets.dart';
import 'package:mycelium/durable_proof.dart';
import 'package:mycelium/durable_stock.dart';
import 'package:mycelium/send_batch.dart';

/// Blocks beyond what the object needs: a quarter of its source blocks and
/// two more — LT coding of a few blocks needs that overhead.
int durableBlocksFor(int sourceBlocks, int received) {
  final missing = sourceBlocks - received;
  return (missing < 0 ? 0 : missing) + (sourceBlocks + 3) ~/ 4 + 2;
}

/// The state root as `0x95` carries it: the application's root if it is
/// 32 B, otherwise its SHA-256 — the comparison only needs both sides to do
/// the same.
Uint8List stateRootOf(DurableStock stock, int channel) {
  final r = stock.stateRoot(channel);
  return r.length == kStateRootBytes ? r : SodiumFFI().sha256(r);
}

class DurableServe {
  final DurableStock stock;
  final DurableSend send;
  final void Function(String) report;
  final Random _random = Random.secure();

  /// Diagnostics.
  int depositsKept = 0;
  int piecesOut = 0;
  int stockAnswers = 0;

  DurableServe(this.stock, this.send, this.report);

  bool _holds(int channel) => stock.heldChannels().contains(channel);

  /// `0x90` — answered `0x91` (kept or already held) or `0x94` (not
  /// held here: no such channel, no valid proof of work, or refused by the
  /// application).
  void deposit(Uint8List p, CardAddress from) {
    final d = depositRead(p);
    if (d == null) return;
    final id = DurableId.of(d.channel, d.object);
    bool kept;
    if (!_holds(d.channel)) {
      kept = false;
    } else if (!durableProofCarries(d.channel, d.object, d.proof)) {
      kept = false; // §16.7: no valid proof of work, no deposit
      report('Durable: deposit from ${nodeKey(from)} without a valid proof');
    } else if (stock.isHeldOrRejected(id)) {
      kept = stock.object(id) != null;
    } else {
      kept = stock.offer(d.channel, d.object, fromNode: nodeKey(from)) ==
          DurableVerdict.kept;
      if (kept) depositsKept++;
    }
    unawaited(send(
        kept ? depositedPacket(d.channel, id.hash) : notHeldPacket(id), from));
  }

  /// `0x92` — fountain blocks of the object, or `0x94`.
  Future<void> fetch(Uint8List p, CardAddress from) async {
    final f = fetchRead(p);
    if (f == null) return;
    final object = _holds(f.id.channel) ? stock.object(f.id) : null;
    if (object == null || object.isEmpty) {
      unawaited(send(notHeldPacket(f.id), from));
      return;
    }
    final enc = FountainEncoder(
        objectId: Uint8List.fromList(
            f.id.hash.sublist(0, kFountainObjectIdBytes)),
        data: object);
    final count = durableBlocksFor(enc.sourceBlocks, f.received ?? 0);
    for (var sent = 0; sent < count; sent++) {
      if (sent > 0 && sent % kSendBatch == 0) await Future<void>(() {});
      unawaited(send(
          durablePiecePacket(enc.blockAt(_random.nextInt(1 << 32))), from));
      piecesOut++;
    }
  }

  /// `0x95` — "same" when the roots agree, otherwise the identifiers whose
  /// age is at most T. Silent for a channel this node does not hold.
  void stockAsk(Uint8List p, CardAddress from) {
    final a = stockAskRead(p);
    if (a == null || !_holds(a.channel)) return;
    stockAnswers++;
    final same = _equal(stateRootOf(stock, a.channel), a.root);
    final ids = same
        ? null
        : stock.held(a.channel,
            sinceHours: a.sinceHours == kSinceBeginning ? null : a.sinceHours);
    unawaited(send(stockAnswerPacket(a.channel, ids), from));
  }

  /// `0x97` — the head of the group, or "unknown". Silent for a channel
  /// this node does not hold.
  void fingerprint(Uint8List p, CardAddress from) {
    final a = fingerprintAskRead(p);
    if (a == null || !_holds(a.channel)) return;
    final head = stock.headFor(a.channel, a.fingerprint);
    unawaited(send(
        fingerprintAnswerPacket(a.channel, a.random,
            head != null && head.length <= kDurableObjectAtMost ? head : null),
        from));
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
