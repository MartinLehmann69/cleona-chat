/// The holder of the public update — the side that HANDS OUT pieces
/// (V4.2 §26.6.1: "Always-on nodes hold the pieces of every current object
/// in their bulk cache"). S387.
///
/// Not every piece is held, but the object: behind [hold]
/// stands a read function that fetches it from disk. Per request
/// fresh blocks are encoded with a random seed — a holder can deliver arbitrarily many
/// different ones, and two holders practically never deliver the same ones.
/// ONE encoder lies in memory, the last used one.
///
/// **No clock.** Sending happens exclusively as an answer to a request
/// with a valid task (`update_piece.dart`).
///
/// **Checking happens BEFORE distributing.** If SHA-256 of the read
/// object does not match its name, not a single piece goes out — a
/// holder with a spoiled file would otherwise poison every assembler, and that one
/// would have to discard its whole state per §26.6.1.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_encoder.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/update_piece.dart';

/// Returns the bytes of a held object, or `null`.
typedef ObjectRead = Future<Uint8List?> Function();

class UpdateHolder {
  final UpdateSend send;
  final Tasks _tasks;
  final int piecesPerAnswer;
  final void Function(String)? report;
  final Random _random;
  final Map<String, ObjectRead> _objects = {};

  /// The names for the keys of [_objects] — [blockNow] selects an
  /// object and needs its 32 B back.
  final Map<String, Uint8List> _names = {};
  String? _encodedFor;
  Future<FountainEncoder?>? _encoder;

  /// The encoder that lies FINISHED in memory — the synchronous side of
  /// [_encoder]. Only it can serve [blockNow].
  FountainEncoder? _ready;
  String? _readyFor;

  /// Diagnostics: what this holder has handed out.
  int sentPieces = 0;
  int answeredPleas = 0;

  /// Blocks that [blockNow] has handed out — they go out via a route
  /// that knows no request (§5.5 rule 2).
  int pushedPieces = 0;

  UpdateHolder({
    required this.send,
    Tasks? tasks,
    this.piecesPerAnswer = kPiecesPerAnswer,
    this.report,
    Random? random,
  })  : _tasks = tasks ?? Tasks(),
        _random = random ?? Random.secure();

  /// Keeps [object] (SHA-256, 32 B) ready; reading happens only when needed.
  void hold(Uint8List object, ObjectRead read) {
    if (object.length != kObjectLength) {
      throw ArgumentError('Object must be $kObjectLength B');
    }
    final h = _hex(object);
    _objects[h] = read;
    _names[h] = Uint8List.fromList(object);
    _forget(h);
  }

  void release(Uint8List object) {
    final h = _hex(object);
    _objects.remove(h);
    _names.remove(h);
    _forget(h);
  }

  void _forget(String h) {
    if (_encodedFor == h) {
      _encodedFor = null;
      _encoder = null;
    }
    if (_readyFor == h) {
      _readyFor = null;
      _ready = null;
    }
  }

  bool holds(Uint8List object) => _objects.containsKey(_hex(object));

  /// A request (0x70). Every other kind is ignored.
  Future<void> receive(Uint8List packet, InternetAddress from, int fromPort) async {
    if (packet.isEmpty || packet[0] != kinds.kPiecePlea) return;
    final b = pleaOrTaskRead(packet);
    if (b == null) return;
    final source = (from, fromPort);
    if (!holds(b.object)) {
      send(noPiecesPacket(b.object), source);
      return;
    }
    if (!_tasks.valid(source, b.object, b.task)) {
      send(taskPacket(b.object, _tasks.forField(source, b.object)), source);
      return;
    }
    final encoder = await _encoderFor(b.object);
    if (encoder == null) {
      send(noPiecesPacket(b.object), source);
      return;
    }
    answeredPleas++;
    for (var i = 0; i < piecesPerAnswer; i++) {
      send(piecePacket(encoder.blockAt(_random.nextInt(1 << 32))), source);
      sentPieces++;
    }
  }

  /// ONE fountain block, **synchronously** — for a route that cannot
  /// wait. A piece replaces the filling in a packet that flies
  /// anyway (§5.5 rule 1); it must not shift any send time,
  /// so it also must not wait for the reading of a file.
  ///
  /// `null` as long as no encoder lies finished in memory. The call
  /// then triggers the encoding and returns IMMEDIATELY — the next
  /// call finds it ready. No timer, no repetition, no packet.
  ///
  /// **Which object.** The holder keeps ONE encoder in memory (a
  /// second would cost the full object bytes once more). [blockNow]
  /// therefore takes the one that is there, and chooses randomly only for warming
  /// up. The encoder thus follows the fetch path: [receive] aligns
  /// it to the object that was last ASKED for. The BLOCK is
  /// drawn randomly in any case — rateless, two holders practically never
  /// deliver the same one (§26.6.1).
  FountainBlock? blockNow() {
    if (_objects.isEmpty) return null;
    final k = _ready;
    final h = _readyFor;
    if (k != null && h != null && _objects.containsKey(h)) {
      pushedPieces++;
      return k.blockAt(_random.nextInt(1 << 32));
    }
    final warm = _objects.keys.elementAt(_random.nextInt(_objects.length));
    unawaited(_encoderFor(_names[warm]!));
    return null;
  }

  Future<FountainEncoder?> _encoderFor(Uint8List object) {
    final h = _hex(object);
    final present = _encoder;
    if (_encodedFor == h && present != null) return present;
    _encodedFor = h;
    return _encoder = _encode(object, h);
  }

  Future<FountainEncoder?> _encode(Uint8List object, String h) async {
    final read = _objects[h];
    Uint8List? data;
    try {
      data = read == null ? null : await read();
    } on Object catch (e) {
      report?.call('Update holder: ${objectShort(object)} not readable: $e');
    }
    if (data == null || data.isEmpty) return null;
    if (!sameBytes(SodiumFFI().sha256(data), object)) {
      report?.call('Update holder: ${objectShort(object)} does not match '
          'its SHA-256 — NOTHING of it is distributed');
      return null;
    }
    final k = FountainEncoder(objectId: fountainIdentifier(object), data: data);
    // Only HERE does the encoder become synchronously available (see [blockNow]).
    _ready = k;
    _readyFor = h;
    return k;
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
