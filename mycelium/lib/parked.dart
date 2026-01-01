/// Parked cells (V4.2 §4.5.4, D-40, E7 = c): a cell collected from the post
/// box that no held KEM generation of the identity opens.
///
/// ── WHY ──────────────────────────────────────────────────────────────────
///
/// With more than one device, ONE device rotates the KEM generation and
/// places it to the others as Type 19 before it announces to contacts. A
/// contact that already seals under the new generation can still reach
/// another own device first — its cell lies under the identity's day value,
/// and whichever device collects first deletes it at the holder (§8.2). That
/// device cannot open it yet. Discarded, the message would be lost silently;
/// so it is kept here, up to [kParkedKeep] and at most [kParkedAtMost]
/// cells, and opened once the generation arrives (`mailbox_parked.dart`).
///
/// ── WHAT IS PARKED ───────────────────────────────────────────────────────
///
/// Only a COLLECTED cell of the message or amendment kinds, only for the
/// identity whose question collected it, only while its own line is active
/// (another own device exists), and only when the failure is the KEM itself
/// ([EnvelopeBroken.kemClosed]) — a bent signature is not cured by a later
/// generation. With one device nothing is parked: the node behaves as before.
///
/// ── LOST CELLS ARE COUNTED ───────────────────────────────────────────────
///
/// A cell that expires unopened, or is pushed out by the cap (oldest first,
/// as a holder does, §8.2), is counted in [ParkedCells.lost] and reported —
/// the count is persisted and read by the application for its statistics.
///
/// ── NO CLOCK ─────────────────────────────────────────────────────────────
///
/// Expiry is checked at the collection edges that run anyway
/// (`node_post_box.dart`), when parking, and when the count is read.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/envelope.dart' show Envelope, EnvelopeBroken, PostBox;
import 'package:mycelium/identity.dart';
import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/node.dart';
import 'package:mycelium/node_first_contact_box.dart' show NodeFirstContactBox;
import 'package:mycelium/own_line.dart' show ownLineOf;

/// How long a parked cell is kept: the retention of the post box (§8.2) —
/// a cell older than that would not have been held for this device either.
const Duration kParkedKeep = Duration(days: 7);

/// At most this many parked cells per identity (§8.2: per day value).
const int kParkedAtMost = 100;

/// The file of the parked cells in the mailbox directory (`.enc` appended by
/// [FileEncryption]).
const String kFileParked = 'parked';

const int _version = 1;

/// One parked cell: its bytes, where it was collected, when it was parked.
typedef ParkedCell = ({Uint8List cell, CardAddress origin, DateTime at});

/// The parked cells of ONE identity, encrypted on disk next to its memory.
class ParkedCells {
  final FileEncryption? _enc;
  final List<ParkedCell> _cells = [];
  final void Function(String)? report;

  /// The clock against which [kParkedKeep] runs. A smoke moves it by days;
  /// nothing else sets it.
  DateTime Function() now = DateTime.now;

  /// Cells lost unopened — expired or pushed out by the cap. Persisted.
  int _lost = 0;

  /// Loads what lies in [directory] under [key]; without [directory]
  /// everything stays in memory. An unreadable file is reported and
  /// replaced — the cells in it are counted as lost only if their number can
  /// be read, which it cannot; so it is reported, not guessed.
  ParkedCells({Directory? directory, Uint8List? key, this.report})
      : _enc = directory == null
            ? null
            : FileEncryption(baseDir: directory.path, key: key) {
    final enc = _enc;
    if (enc == null) return;
    final bytes = enc.readBinaryFile('${enc.baseDir}/$kFileParked');
    if (bytes == null) {
      if (File('${enc.baseDir}/$kFileParked.enc').existsSync()) {
        report?.call('parked: file unreadable — starting empty');
      }
      return;
    }
    try {
      _decode(bytes);
    } on Object catch (e) {
      _cells.clear();
      report?.call('parked: file unreadable ($e) — starting empty');
    }
  }

  /// How many cells are parked right now.
  int get held => _cells.length;

  /// Cells lost unopened so far (after expiring what is due).
  int get lost {
    sweep();
    return _lost;
  }

  /// Parks [cell]. A cell already parked is not parked twice. Returns `true`
  /// when it is (now) held.
  bool park(Uint8List cell, CardAddress origin) {
    sweep();
    if (_cells.any((c) => _same(c.cell, cell))) return true;
    var pushed = 0;
    while (_cells.length >= kParkedAtMost) {
      _cells.removeAt(0);
      pushed++;
    }
    if (pushed > 0) {
      _lost += pushed;
      report?.call('parked: $pushed cell(s) pushed out unopened by the cap of '
          '$kParkedAtMost — lost, $_lost in all (D-40)');
    }
    _cells.add((cell: Uint8List.fromList(cell), origin: origin, at: now()));
    save();
    return true;
  }

  /// Expires what is older than [kParkedKeep]; counts and reports it.
  /// Returns how many expired.
  int sweep() {
    final limit = now().subtract(kParkedKeep);
    final before = _cells.length;
    _cells.removeWhere((c) => !c.at.isAfter(limit));
    final gone = before - _cells.length;
    if (gone > 0) {
      _lost += gone;
      report?.call('parked: $gone cell(s) expired unopened after '
          '${kParkedKeep.inDays} days — lost, $_lost in all (D-40)');
      save();
    }
    return gone;
  }

  /// Takes every parked cell out, oldest first; what does not open goes
  /// back with [putBack].
  List<ParkedCell> takeAll() {
    sweep();
    final all = List.of(_cells);
    _cells.clear();
    return all;
  }

  /// Puts [c] back, keeping when it was parked.
  void putBack(ParkedCell c) => _cells.add(c);

  /// Writes the state encrypted and atomically — nothing without a disk.
  void save() {
    final enc = _enc;
    if (enc == null) return;
    final b = BytesBuilder()
      ..addByte(_version)
      ..add(_u32(_lost))
      ..add(_u32(_cells.length));
    for (final c in _cells) {
      b
        ..add(_u64(c.at.millisecondsSinceEpoch))
        ..addByte(c.origin.address.length)
        ..add(c.origin.address)
        ..add(_u16(c.origin.port))
        ..add(_u32(c.cell.length))
        ..add(c.cell);
    }
    enc.writeBinaryFile('${enc.baseDir}/$kFileParked', b.toBytes());
  }

  void _decode(Uint8List b) {
    final v = ByteData.sublistView(b);
    var p = 0;
    if (b.isEmpty || b[p++] != _version) throw const FormatException('version');
    _lost = v.getUint32(p);
    p += 4;
    final n = v.getUint32(p);
    p += 4;
    for (var k = 0; k < n; k++) {
      final at = DateTime.fromMillisecondsSinceEpoch(v.getUint64(p));
      p += 8;
      final aLen = b[p++];
      final address = Uint8List.fromList(b.sublist(p, p += aLen));
      final port = v.getUint16(p);
      p += 2;
      final len = v.getUint32(p);
      p += 4;
      if (p + len > b.length) throw const FormatException('truncated');
      final cell = Uint8List.fromList(b.sublist(p, p += len));
      _cells.add((cell: cell, origin: CardAddress(address, port), at: at));
    }
  }
}

final Expando<ParkedCells> _parked = Expando<ParkedCells>('parked');
final Expando<Identity> _collectingFor = Expando<Identity>('collectingFor');

/// The parked cells of [i], or `null` while none are attached (a node without
/// mailbox, a probe).
ParkedCells? parkedOf(Identity i) => _parked[i];

/// Attaches [p] to [i] — by its mailbox (`mailbox_parked.dart`).
void parkedPut(Identity i, ParkedCells? p) => _parked[i] = p;

extension NodeParking on Node {
  /// The identity whose questions the pieces being fed right now answered
  /// (set by `node_post_box.dart` around `feedCollected`).
  set collectingFor(Identity? i) => _collectingFor[this] = i;

  /// Where no identity opened [data]: parks it if it is a collected cell of
  /// an identity with another own device that its held generations do not
  /// open (see the file header). `true` when parked.
  bool parkUnopened(Uint8List data, CardAddress origin) {
    final i = _collectingFor[this];
    if (!feedingCollected || i == null || data.isEmpty) return false;
    if (!(kinds.isMessage(data[0]) || kinds.isAmendment(data[0]))) return false;
    final line = ownLineOf(i);
    final store = parkedOf(i);
    if (line == null || !line.active || store == null) return false;
    if (!kemClosed(data, i.postBox)) return false;
    store.park(data, origin);
    report('parked: ${data.length} B collected that no held KEM generation '
        'opens — kept until the generation arrives (D-40), ${store.held} '
        'parked');
    return true;
  }
}

/// Whether [data] (kind byte + envelope) fails at the KEM for [me] — the one
/// failure a later generation cures.
bool kemClosed(Uint8List data, PostBox me) {
  try {
    Envelope.unseal(envelope: Uint8List.sublistView(data, 1), recipient: me);
    return false;
  } on EnvelopeBroken catch (e) {
    return e.reason == EnvelopeBroken.kemClosed;
  } on Object {
    return false;
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _u16(int x) => Uint8List(2)..buffer.asByteData().setUint16(0, x);
Uint8List _u32(int x) => Uint8List(4)..buffer.asByteData().setUint32(0, x);
Uint8List _u64(int x) => Uint8List(8)..buffer.asByteData().setUint64(0, x);
