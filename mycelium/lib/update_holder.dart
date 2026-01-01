/// The holder of the public update — the side that HANDS OUT pieces
/// (V4.2 §26.6.1: "Always-on nodes hold the pieces of every current object
/// in their bulk cache"). S387.
///
/// Not every piece is held, but the object: behind [holdFile] stands the
/// path of the file, behind [hold] a read function for small in-memory
/// objects (probes). Per request fresh blocks are encoded with a random
/// seed — a holder can deliver arbitrarily many different ones, and two
/// holders practically never deliver the same ones. ONE encoder is kept,
/// the last used one.
///
/// **A held file is never in memory (S406-OOM).** Its check streams the
/// file ([sha256OfFile]), its encoder reads the source blocks a block needs
/// from the file ([FountainEncoder.reader]): O(1 block), not O(file) — a
/// held ~200 MB APK in memory OOM-killed the bootstrap daemon (07.10.2026).
///
/// **No clock.** Sending happens exclusively as an answer to a request
/// with a valid task (`update_piece.dart`). An answer carries the count the
/// request names (at most [kPiecesPerAnswerMax]; none named:
/// [kPiecesPerAnswer]) and leaves in batches of [kSendBatch] with one
/// event-loop turn between them (§11.1 "a sending loop yields to the event
/// loop after each batch, without waiting") — never as one burst that keeps
/// the node from reading (S406-UPDPKG, P7).
///
/// **Checked once, at holding (S406-UPDPKG).** Not at the first request:
/// a streamed SHA-256 of a ~200 MB APK takes seconds, and a collector
/// meeting that silence turns to the next holder. A file whose size and
/// modification time still match its check is not hashed again.
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

import 'package:cleona/core/crypto/file_sha256.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/fountain/fountain_block.dart';
import 'package:cleona/core/fountain/fountain_encoder.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/send_batch.dart';
import 'package:mycelium/update_piece.dart';
import 'package:mycelium/update_trace.dart';

/// Returns the bytes of a held object, or `null`.
typedef ObjectRead = Future<Uint8List?> Function();

class UpdateHolder {
  final UpdateSend send;
  final Tasks _tasks;
  final int piecesPerAnswer;
  final void Function(String)? report;
  final Random _random;
  final Map<String, _Held> _objects = {};

  /// The 32 B behind each key of [_objects] (for [blockNow]).
  final Map<String, Uint8List> _names = {};

  /// Files that passed their check: size and modification time at the check.
  final Map<String, (int, DateTime)> _checked = {};
  String? _encodedFor;
  Future<_Coded?>? _encoder;

  /// The FINISHED encoder — the synchronous side of [_encoder] ([blockNow]).
  _Coded? _ready;
  String? _readyFor;

  /// Diagnostics: what this holder has handed out.
  int sentPieces = 0;
  int answeredPleas = 0;

  /// Blocks [blockNow] handed out — a route without request (§5.5 rule 2).
  int pushedPieces = 0;

  UpdateHolder({
    required this.send,
    Tasks? tasks,
    this.piecesPerAnswer = kPiecesPerAnswer,
    this.report,
    Random? random,
  })  : _tasks = tasks ?? Tasks(),
        _random = random ?? Random.secure();

  /// Keeps [object] (SHA-256, 32 B) ready. [read] returns the WHOLE object —
  /// only for small in-memory objects; a file goes through [holdFile].
  void hold(Uint8List object, ObjectRead read) => _hold(object, _Held(read, null));

  /// Keeps the file at [path] ready as [object] (SHA-256, 32 B) without
  /// ever loading it: checked by streaming, encoded block by block.
  void holdFile(Uint8List object, String path) =>
      _hold(object, _Held(null, path));

  void _hold(Uint8List object, _Held held) {
    if (object.length != kObjectLength) {
      throw ArgumentError('Object must be $kObjectLength B');
    }
    final h = _hex(object);
    updateTrace('object-hold',
        object: object,
        reason: held.path == null
            ? 'in memory (read function)'
            : '${held.path} (${_sizeOf(held.path!)})');
    // The same file held again keeps its check (its stat decides).
    if (_objects[h]?.path != held.path) _checked.remove(h);
    _objects[h] = held;
    _names[h] = Uint8List.fromList(object);
    _forget(h);
    // The check now, not at the first request (see header).
    unawaited(_encoderFor(object));
  }

  void release(Uint8List object) {
    final h = _hex(object);
    _objects.remove(h);
    _names.remove(h);
    _checked.remove(h);
    _forget(h);
  }

  void _forget(String h) {
    if (_encodedFor == h) {
      _encodedFor = null;
      _encoder = null;
    }
    if (_readyFor == h) {
      _readyFor = null;
      _ready?.close();
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
    final who = '${from.address}:$fromPort';
    if (!holds(b.object)) {
      updateTrace('no-pieces-out', object: b.object, reason: 'to $who — not held');
      send(noPiecesPacket(b.object), source);
      return;
    }
    if (!_tasks.valid(source, b.object, b.task)) {
      updateTrace('task-out',
          object: b.object,
          reason: 'to $who — the request carried '
              '${b.task.every((x) => x == 0) ? 'no task' : 'a task not valid for this address/port/window'}');
      send(taskPacket(b.object, _tasks.forField(source, b.object)), source);
      return;
    }
    final coded = await _encoderFor(b.object);
    if (coded == null) {
      updateTrace('no-pieces-out',
          object: b.object, reason: 'to $who — object not readable or check failed');
      send(noPiecesPacket(b.object), source);
      return;
    }
    final count = (b.count ?? piecesPerAnswer).clamp(1, kPiecesPerAnswerMax);
    var sent = 0;
    int? firstSeed;
    try {
      while (sent < count) {
        final batch = count - sent < kSendBatch ? count - sent : kSendBatch;
        for (var i = 0; i < batch; i++) {
          final block = coded.k.blockAt(_random.nextInt(1 << 32));
          firstSeed ??= block.blockSeed;
          send(piecePacket(block), source);
          sentPieces++;
        }
        sent += batch;
        // §11.1: one event-loop turn between batches, no clock.
        if (sent < count) await Future<void>(() {});
      }
    } on FileSystemException catch (e) {
      _unreadable(b.object, e);
    } finally {
      coded.close();
    }
    if (sent == 0) {
      updateTrace('no-pieces-out',
          object: b.object, reason: 'to $who — file changed or unreadable');
      send(noPiecesPacket(b.object), source);
      return;
    }
    updateTrace('pieces-out',
        object: b.object,
        reason: 'to $who — $sent of $count piece(s) (count '
            '${b.count == null ? 'not named' : 'named'}), first block $firstSeed');
    answeredPleas++;
  }

  /// The held file changed or vanished after its check: nothing more of
  /// it goes out until a new check has passed.
  void _unreadable(Uint8List object, FileSystemException e) {
    report?.call('Update holder: ${objectShort(object)} not readable: $e');
    _forget(_hex(object));
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
      try {
        final block = k.k.blockAt(_random.nextInt(1 << 32));
        pushedPieces++;
        return block;
      } on FileSystemException catch (e) {
        _unreadable(_names[h]!, e);
        return null;
      } finally {
        k.close();
      }
    }
    final warm = _objects.keys.elementAt(_random.nextInt(_objects.length));
    unawaited(_encoderFor(_names[warm]!));
    return null;
  }

  Future<_Coded?> _encoderFor(Uint8List object) {
    final h = _hex(object);
    final present = _encoder;
    if (_encodedFor == h && present != null) return present;
    _encodedFor = h;
    return _encoder = _encode(object, h);
  }

  Future<_Coded?> _encode(Uint8List object, String h) async {
    final held = _objects[h];
    _Coded? coded;
    try {
      coded = held == null
          ? null
          : held.path != null
              ? await _encodeFile(object, held.path!, h)
              : await _encodeBytes(object, held.read!);
    } on Object catch (e) {
      report?.call('Update holder: ${objectShort(object)} not readable: $e');
    }
    if (coded == null) return null;
    // Only HERE does the encoder become synchronously available (see [blockNow]).
    if (_readyFor != h) _ready?.close();
    _ready = coded;
    _readyFor = h;
    return coded;
  }

  Future<_Coded?> _encodeBytes(Uint8List object, ObjectRead read) async {
    final data = await read();
    if (data == null || data.isEmpty) {
      updateTrace('object-check', object: object, reason: 'read nothing');
      return null;
    }
    final ok = _matches(SodiumFFI().sha256(data), object);
    updateTrace('object-check',
        object: object,
        reason: '${data.length} B in memory — '
            '${ok ? 'SHA-256 matches' : 'SHA-256 does NOT match'}');
    if (!ok) return null;
    return _Coded(
        FountainEncoder(objectId: fountainIdentifier(object), data: data), null);
  }

  /// Checked by streaming, then encoded from the file. The file's size and
  /// modification time at the check are kept: a file that differs from
  /// them later is not read ([_FileSource]).
  Future<_Coded?> _encodeFile(Uint8List object, String path, String h) async {
    final before = await File(path).stat();
    if (before.type != FileSystemEntityType.file || before.size == 0) {
      updateTrace('object-check',
          object: object, reason: '$path missing or empty (${before.type})');
      return null;
    }
    final known = _checked[h];
    if (known == null ||
        known.$1 != before.size ||
        known.$2 != before.modified) {
      final hash = await sha256OfFile(path);
      final after = await File(path).stat();
      if (after.size != before.size || after.modified != before.modified) {
        updateTrace('object-check',
            object: object, reason: '$path changed during its check');
        report?.call('Update holder: ${objectShort(object)} changed during '
            'its check — not distributed');
        return null;
      }
      final ok = _matches(hash, object);
      updateTrace('object-check',
          object: object,
          reason: '$path ${before.size} B mtime ${before.modified.toIso8601String()} '
              '— SHA-256 ${ok ? 'matches' : 'is ${updateObjectShort(hash)}, does NOT match'}');
      if (!ok) return null;
      _checked[h] = (before.size, before.modified);
    }
    final source = _FileSource(path, before.size, before.modified);
    return _Coded(
        FountainEncoder.reader(
            objectId: fountainIdentifier(object),
            objectLength: before.size,
            read: source.read),
        source);
  }

  bool _matches(Uint8List hash, Uint8List object) {
    if (sameBytes(hash, object)) return true;
    report?.call('Update holder: ${objectShort(object)} does not match '
        'its SHA-256 — NOTHING of it is distributed');
    return false;
  }
}

/// What [UpdateHolder] holds for an object: a read function OR a path.
class _Held {
  final ObjectRead? read;
  final String? path;
  const _Held(this.read, this.path);
}

/// A finished encoder and, for a held file, its source (to close).
class _Coded {
  final FountainEncoder k;
  final _FileSource? source;
  const _Coded(this.k, this.source);
  void close() => source?.close();
}

/// The file behind a [FountainEncoder.reader]. Opened on the first read
/// after a [close], closed by the holder after every answer and every
/// pushed block — no handle stays open between uses. On opening, size and
/// modification time must still be those of the check; otherwise the read
/// throws and the holder forgets the encoder (a file replaced under a held
/// name would poison every assembler, §26.6.1).
class _FileSource {
  final String path;
  final int length;
  final DateTime modified;
  RandomAccessFile? _file;

  _FileSource(this.path, this.length, this.modified);

  void read(int offset, Uint8List into) {
    final f = _file ??= _open();
    f.setPositionSync(offset);
    var got = 0;
    while (got < into.length) {
      final n = f.readIntoSync(into, got);
      if (n <= 0) throw FileSystemException('short read at $offset', path);
      got += n;
    }
  }

  RandomAccessFile _open() {
    final s = File(path).statSync();
    if (s.size != length || s.modified != modified) {
      throw FileSystemException('changed since its check', path);
    }
    return File(path).openSync();
  }

  void close() {
    _file?.closeSync();
    _file = null;
  }
}

/// The size of the file at [path] for a trace line — never throws.
String _sizeOf(String path) {
  try {
    return '${File(path).lengthSync()} B';
  } on Object {
    return 'not readable';
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
