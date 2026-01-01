/// Fetching a durable object from the node that named it (v4_2 §16.0
/// "Fetching is an event, never a clock", §11.5 `0x92`–`0x94`). S407 SK-1.
///
/// **The procedure is the update's (§26.6.1), reused, not invented.** The
/// object comes in fountain blocks (`lib/core/fountain/`), one request
/// names the object and never a block, the next request follows the end
/// of the previous answer, and the bookkeeping of one run — the quiet gap
/// that ends an answer (§11.3), the count of answers without a new block,
/// the upper bound per holder — is [UpdateRun] of `update_run.dart`. What
/// differs from the update is named:
/// * the request names the identifier (20 B) and, after the first answer,
///   the number of blocks already taken in (the "fountain state" of §11.5);
/// * a request that stays without an answer has failed ([DurableAsk]; the
///   repeats on silence belong to the transport alone, §11.3a); then, after
///   three answers without a new block, or at `0x94` the run fails and the
///   namer is written off for the day (§16.0) — the caller does that, this
///   file reports it;
/// * there is ONE namer per run: an object is fetched only from the node
///   that named it (§16.0).
///
/// One run per namer at a time; what that namer named further waits in its
/// queue. An identifier already being fetched from one namer is not fetched
/// from a second.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_decoder.dart';
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/durable_ask.dart';
import 'package:mycelium/durable_id.dart';
import 'package:mycelium/durable_packets.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/split.dart' show SendEnd;
import 'package:mycelium/update_run.dart';

typedef DurableSend = Future<SendEnd> Function(Uint8List packet, CardAddress to);

/// The most source blocks an object of [kDurableObjectAtMost] has.
final int kDurableBlocksAtMost =
    FountainBlock.sourceBlockCount(kDurableObjectAtMost);

String nodeKey(CardAddress a) =>
    '${InternetAddress.fromRawAddress(a.address).address}:${a.port}';

class _Run {
  final DurableId id;
  final CardAddress namer;
  final UpdateRun run = UpdateRun(const [], kDurableBlocksAtMost);
  FountainDecoder? decoder;
  DurableAsk? ask;
  Timer? quiet;
  _Run(this.id, this.namer);

  bool matches(FountainBlock b) =>
      FountainBlock.sameObject(b.objectId, id.hash.sublist(0, kFountainObjectIdBytes));

  void stop() {
    ask?.cancel();
    quiet?.cancel();
  }
}

class DurableFetcher {
  final DurableSend send;
  final void Function(String) report;

  /// A complete object whose hash matches its identifier.
  final void Function(DurableId id, Uint8List object, CardAddress namer) onObject;

  /// A run failed: the namer is written off for the day (§16.0).
  final void Function(CardAddress namer, String why) onFailed;

  final Map<String, _Run> _runs = {};
  final Map<String, Queue<DurableId>> _queues = {};
  final Set<String> _wanted = {};

  /// Diagnostics.
  int fetched = 0;
  int failed = 0;
  int requests = 0;

  DurableFetcher(
      {required this.send,
      required this.report,
      required this.onObject,
      required this.onFailed});

  /// Whether [id] is being fetched or waits to be.
  bool wanted(DurableId id) => _wanted.contains(id.key);

  /// Fetch [id] from [namer] — at once if no run with it is going.
  void want(DurableId id, CardAddress namer) {
    if (!_wanted.add(id.key)) return;
    final k = nodeKey(namer);
    (_queues[k] ??= Queue()).add(id);
    if (!_runs.containsKey(k)) _next(namer);
  }

  void _next(CardAddress namer) {
    final k = nodeKey(namer);
    final q = _queues[k];
    if (q == null || q.isEmpty) {
      _queues.remove(k);
      return;
    }
    final r = _Run(q.removeFirst(), namer);
    _runs[k] = r;
    _request(r);
  }

  void _request(_Run r) {
    r.run.roundStart();
    requests++;
    final received = r.decoder?.blocksAccepted;
    r.ask = DurableAsk(
        () => send(fetchPacket(r.id, received: received), r.namer),
        (why) => _fail(r, why))
      ..start();
  }

  /// `0x93` and `0x94` from [from].
  void receive(Uint8List p, CardAddress from) {
    final r = _runs[nodeKey(from)];
    if (r == null) return;
    if (p[0] == kinds.kDurableNotHeld) {
      final id = notHeldRead(p);
      if (id != null && id == r.id) _fail(r, 'not held there (0x94)');
      return;
    }
    final block = durablePieceRead(p);
    if (block == null || !r.matches(block)) return;
    r.ask?.answered();
    if (block.objectLength > kDurableObjectAtMost) {
      _fail(r, 'object of ${block.objectLength} B');
      return;
    }
    final d = r.decoder ??= FountainDecoder(
        objectId: block.objectId, objectLength: block.objectLength);
    final o = d.offer(block);
    r.run.piece(
        fresh: o != FountainOffer.duplicate && o != FountainOffer.foreign);
    if (d.isComplete) return _complete(r);
    if (r.run.piecesFromHolder > r.run.upperLimitPerHolder) {
      _fail(r, 'no object after ${r.run.piecesFromHolder} blocks');
      return;
    }
    r.quiet?.cancel();
    r.quiet = Timer(r.run.gap(), () => _answerEnded(r));
  }

  /// §11.3: the quiet gap ended the answer. Three answers without a new
  /// block end the run (§16.0), otherwise the next request follows.
  void _answerEnded(_Run r) {
    if (_runs[nodeKey(r.namer)] != r) return;
    if (r.run.newInRound == 0 && ++r.run.emptyAnswers >= kEmptyAnswersPerHolder) {
      _fail(r, '$kEmptyAnswersPerHolder answers without a new block');
      return;
    }
    _request(r);
  }

  void _complete(_Run r) {
    r.stop();
    final object = r.decoder!.takeObject()!;
    if (!_same(objectHash(object), r.id.hash)) {
      _fail(r, 'object does not match its identifier');
      return;
    }
    _end(r);
    fetched++;
    onObject(r.id, object, r.namer);
    _next(r.namer);
  }

  void _fail(_Run r, String why) {
    r.stop();
    if (_runs[nodeKey(r.namer)] != r) return;
    _end(r);
    failed++;
    report('Durable: fetch of ${r.id} from ${nodeKey(r.namer)} failed — $why');
    // Written off for the day: what it named further counts for nothing.
    for (final id in _queues.remove(nodeKey(r.namer)) ?? Queue<DurableId>()) {
      _wanted.remove(id.key);
    }
    onFailed(r.namer, why);
  }

  void _end(_Run r) {
    _runs.remove(nodeKey(r.namer));
    _wanted.remove(r.id.key);
  }

  void stop() {
    for (final r in _runs.values) {
      r.stop();
    }
    _runs.clear();
    _queues.clear();
    _wanted.clear();
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
