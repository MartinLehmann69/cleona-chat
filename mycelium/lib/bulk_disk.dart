/// The disk under lane 3 (§9.4): what a holder keeps for others, and the
/// opened blocks of an object ONE identity is collecting — across a restart.
///
/// TWO PLACES, TWO KEYS (§4.5.3 "Keys — two, and the distinction is
/// normative"; S401). The holder's side lies in the HOST's folder under the
/// device-wide key: sealed pieces of third parties, held by the node. The
/// recipient's opened blocks are content of one identity: they lie in THAT
/// identity's folder under its key (`<profile>/mycelium/bulk`), so the key
/// of another identity does not open them and they go with the identity's
/// folder (§21.4.1). WHICH collections are open is not on this disk at all:
/// the layer above keeps them in the identity's store and hands them over
/// again after a restart (`bulk_collect.dart`).
///
/// The holder's side is NOT one file like `post_box_disk.dart`: the bulk
/// cache is up to 1 GB (§21.3.3), and rewriting all of it for every
/// transfer would cost more than the transfer. Instead there is one small
/// index and one file per identifier; a transfer writes only its own file,
/// once, when its pieces have come to rest. Eviction rewrites only the file
/// it shortens.
///
/// Encrypted and atomic like every other store of the tree
/// ([FileEncryption], `.enc.tmp` + rename). The pieces are already sealed
/// by their sender; the encryption at rest hides the identifiers and the
/// file names are a hash of the identifier, not the identifier.
///
/// ── FILE LAYOUTS (all integers big-endian unless named) ─────────────────
/// ```
/// bulk_index:  version 1 | n u32 | per identifier: tag 16 | inserted u64 ms
///              | allowed u16 | held u32
/// h_<hash>:    version 1 | n u32 | per piece: stripe u16 | no u8 | sealed 1040
/// o_<hash>_<i>: version 1 | n u32 | per stripe: stripe u32 | k u8
///              | per piece: no u8 | block 1024
/// ```
/// The `o_` chunks (S398-W1) are the recipient's OPENED blocks — plaintext
/// of the object, hence encrypted like everything here. A collection
/// appends a chunk when enough stripes completed (`bulk_collect.dart`); a
/// restart reads them back and asks only from the first open stripe on. A
/// fallen-back stream leaves its pieces here too, before its collection
/// exists.
/// A file that does not read is dropped, not repaired: the holder's pieces
/// are third-party data of the lowest priority (§21.3.3), and an opened
/// block that is lost is asked from its holder again.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/bulk_piece.dart';

typedef StoredPiece = ({int stripe, int no, Uint8List sealed});
typedef HeldIndex = ({Uint8List tag, DateTime inserted, int allowed, int held});

const int _version = 1;
const String _index = 'bulk_index';

class BulkDisk {
  final FileEncryption _enc;
  final Directory directory;
  final void Function(String)? report;

  BulkDisk._(this._enc, this.directory, this.report);

  /// The folder `bulk` under [base] — the host's folder with the device-wide
  /// key for the holder's side, an identity's folder with its key for its
  /// opened blocks; created, nothing read yet.
  static BulkDisk open(Directory base, Uint8List key,
      {void Function(String)? report}) {
    final d = Directory('${base.path}/bulk')..createSync(recursive: true);
    return BulkDisk._(FileEncryption(baseDir: d.path, key: key), d, report);
  }

  String _path(String name) => '${directory.path}/$name';

  String _pieceFile(Uint8List tag) =>
      _path('h_${tagHex(SodiumFFI().sha256(tag)).substring(0, 32)}');

  Uint8List? _read(String path) {
    final there = ['.enc', '.enc.tmp', '.enc.old']
        .any((e) => File('$path$e').existsSync());
    if (!there) return null;
    final b = _enc.readBinaryFile(path);
    if (b == null) _drop(path, 'does not decrypt');
    return b;
  }

  void _drop(String path, String why) {
    report?.call('Bulk: $path dropped — $why');
    _enc.deleteFile(path);
  }

  // ── Holder ────────────────────────────────────────────────────────────

  List<HeldIndex> indexLoad() {
    final path = _path(_index);
    final b = _read(path);
    if (b == null) return [];
    try {
      final r = _Reader(b);
      if (r.u8() != _version) throw const FormatException('version');
      final out = <HeldIndex>[
        for (var i = r.u32(); i > 0; i--)
          (
            tag: r.bytes(kTagLength),
            inserted: DateTime.fromMillisecondsSinceEpoch(r.u64()),
            allowed: r.u16(),
            held: r.u32(),
          )
      ];
      r.done();
      return out;
    } on Object catch (e) {
      _drop(path, '$e');
      return [];
    }
  }

  void indexSave(Iterable<HeldIndex> all) {
    final list = all.toList();
    final b = BytesBuilder()
      ..addByte(_version)
      ..add(_u(list.length, 4));
    for (final x in list) {
      b
        ..add(x.tag)
        ..add(_u(x.inserted.millisecondsSinceEpoch, 8))
        ..add(_u(x.allowed, 2))
        ..add(_u(x.held, 4));
    }
    _enc.writeBinaryFile(_path(_index), b.toBytes());
  }

  List<StoredPiece> piecesLoad(Uint8List tag) {
    final path = _pieceFile(tag);
    final b = _read(path);
    if (b == null) return [];
    try {
      final r = _Reader(b);
      if (r.u8() != _version) throw const FormatException('version');
      final out = <StoredPiece>[
        for (var i = r.u32(); i > 0; i--)
          (stripe: r.u16(), no: r.u8(), sealed: r.bytes(kSealedLength))
      ];
      r.done();
      return out;
    } on Object catch (e) {
      _drop(path, '$e');
      return [];
    }
  }

  void piecesSave(Uint8List tag, List<StoredPiece> pieces) {
    if (pieces.isEmpty) return piecesDrop(tag);
    final b = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(_u(pieces.length, 4));
    for (final p in pieces) {
      b
        ..add(_u(p.stripe, 2))
        ..addByte(p.no)
        ..add(p.sealed);
    }
    _enc.writeBinaryFile(_pieceFile(tag), b.toBytes());
  }

  void piecesDrop(Uint8List tag) => _enc.deleteFile(_pieceFile(tag));

  /// Piece files no index entry names — left by a crash between writing a
  /// piece file and the index. Removed at start.
  void orphansDrop(Iterable<Uint8List> known) {
    final keep = {for (final t in known) '${_pieceFile(t)}.enc'};
    for (final f in directory.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('h_') || keep.contains(f.path)) continue;
      try {
        f.deleteSync();
      } on Object catch (_) {
        // a side file vanished in between — nothing to do
      }
    }
  }

  /// The enforcer for what an earlier build left in the HOST's folder
  /// (S401): the list of open collections (`collect.enc`) and the opened
  /// blocks (`o_*.enc`) — data of ONE identity under the device-wide key
  /// (§4.5.3), left behind when that identity was deleted (§21.4.1). Removed
  /// with their sidecars and reported. Nothing is converted: every open
  /// collection stands in the store of its identity, which hands it over
  /// again, and a block removed here is asked from its holder again.
  void identityStockDrop() {
    var n = 0;
    for (final f in directory.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('o_') && !name.startsWith('collect.enc')) continue;
      try {
        f.deleteSync();
        n++;
      } on Object catch (_) {
        // vanished in between — nothing to do
      }
    }
    if (n > 0) {
      report?.call('Bulk: $n file(s) of an earlier build removed from the '
          'host folder — open collections and opened blocks belong to their '
          'identity (§4.5.3)');
    }
  }

  // ── Recipient: opened blocks (S398-W1) ─────────────────────────────

  String _openedStem(Uint8List tag) =>
      'o_${tagHex(SodiumFFI().sha256(tag)).substring(0, 32)}_';

  /// The chunks under [stem]; with [sidecars] also what an interrupted
  /// write left (`.enc.tmp`) — for removing, never for reading.
  List<File> _openedFiles([String stem = 'o_', bool sidecars = false]) => [
        for (final f in directory.listSync().whereType<File>())
          if (f.uri.pathSegments.last.startsWith(stem) &&
              (sidecars || f.path.endsWith('.enc')))
            f
      ];

  void _remove(File f) {
    try {
      f.deleteSync();
    } on Object catch (_) {
      // vanished in between — nothing to do
    }
  }

  /// Appends [stripes] (stripe -> number -> 1024 B block) as one chunk;
  /// returns the bytes written.
  int openedAppend(Uint8List tag, Map<int, Map<int, Uint8List>> stripes) {
    if (stripes.isEmpty) return 0;
    final stem = _openedStem(tag);
    final b = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(_u(stripes.length, 4));
    for (final e in stripes.entries) {
      b
        ..add(_u(e.key, 4))
        ..addByte(e.value.length);
      for (final x in e.value.entries) {
        b
          ..addByte(x.key)
          ..add(x.value);
      }
    }
    final bytes = b.toBytes();
    var i = _openedFiles(stem).length;
    while (File('${_path('$stem$i')}.enc').existsSync()) {
      i++;
    }
    _enc.writeBinaryFile(_path('$stem$i'), bytes);
    return bytes.length;
  }

  /// Every block kept for [tag]; a chunk that does not read is dropped.
  Map<int, Map<int, Uint8List>> openedLoad(Uint8List tag) {
    final out = <int, Map<int, Uint8List>>{};
    for (final f in _openedFiles(_openedStem(tag))) {
      final path = f.path.substring(0, f.path.length - 4);
      final b = _read(path);
      if (b == null) continue;
      try {
        final r = _Reader(b);
        if (r.u8() != _version) throw const FormatException('version');
        for (var i = r.u32(); i > 0; i--) {
          final m = out[r.u32()] ??= {};
          for (var k = r.u8(); k > 0; k--) {
            final no = r.u8();
            m[no] = r.bytes(1024);
          }
        }
        r.done();
      } on Object catch (e) {
        _drop(path, '$e');
      }
    }
    return out;
  }

  /// Every chunk of [tag], sidecars of an interrupted write included.
  void openedDrop(Uint8List tag) =>
      _openedFiles(_openedStem(tag), true).forEach(_remove);

  /// Bytes of opened blocks on disk, all tags together.
  int openedBytes() => _openedFiles().fold(0, (n, f) => n + f.lengthSync());

  /// Chunks (and sidecars) of tags not in [keep] and older than [age]: a
  /// stash no announcement came for, blocks of a transfer the layer above
  /// no longer knows.
  void openedOrphansDrop(Iterable<Uint8List> keep, Duration age) {
    final stems = [for (final t in keep) _openedStem(t)];
    final limit = DateTime.now().subtract(age);
    for (final f in _openedFiles('o_', true)) {
      final name = f.uri.pathSegments.last;
      if (stems.any(name.startsWith)) continue;
      try {
        if (!f.lastModifiedSync().isAfter(limit)) f.deleteSync();
      } on Object catch (_) {
        // vanished in between — nothing to do
      }
    }
  }
}

Uint8List _u(int v, int n) {
  final b = Uint8List(n);
  for (var i = n - 1; i >= 0; i--) {
    b[i] = v & 0xFF;
    v >>= 8;
  }
  return b;
}

/// A byte reader that throws past the end — the same handwriting as the
/// readers of `post_box_disk.dart` and `memory.dart`, file-private there.
class _Reader {
  final Uint8List _b;
  int _i = 0;
  _Reader(this._b);

  Uint8List bytes(int n) {
    if (n < 0 || _b.length - _i < n) {
      throw FormatException('needs $n B, ${_b.length - _i} B left');
    }
    return Uint8List.fromList(_b.sublist(_i, _i += n));
  }

  int _int(int n) => bytes(n).fold(0, (v, x) => (v << 8) | x);
  int u8() => _int(1);
  int u16() => _int(2);
  int u32() => _int(4);
  int u64() => _int(8);

  void done() {
    if (_i != _b.length) throw FormatException('${_b.length - _i} surplus B');
  }
}
