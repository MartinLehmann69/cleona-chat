/// The history files of the builds before S401 — read ONCE, taken over into
/// the identity's store, and removed.
///
/// Until S401 the history with every peer was a file of its own in the
/// mailbox's directory, `verlauf_<identifier>.enc` (german-ok: the name on
/// the disk of the last build). V4.2 keeps messages and their indices in
/// the identity's store (§4.5.3 form 1, §21.4.2), and for the mailbox's
/// directory §4.5.2 names contacts' delivery state, group pairs, first
/// contact and parked cells — no history. v4.2.0-beta and every lab
/// profile wrote such files, so a start finds them.
///
/// ── WHY THEY ARE TAKEN OVER AND NOT JUST REMOVED ───────────────────────
/// Such a file is the only place an own message that is still OPEN stands
/// for the delivery layer: removed without a look, a message the
/// application shows as on its way would never leave again — a silent
/// loss. And it is the memory against the second copy (§7.1, §20.2):
/// without the identifiers, a copy still lying in a post box would be
/// handed up again.
///
/// ── WHAT HAPPENS TO A FILE, by what the mailbox knows ──────────────────
///  * its peer is a contact or a group pair: every OWN entry goes into
///    the store as the history keeps it ([History.kept]: the frame only
///    of an own entry that is still open); every RECEIVED identifier goes
///    into the identity's received memory ([HistoryStore.incomingKeep],
///    §20.2 — since S403 a received delivery keeps no record, so the
///    round-trip of `put`/`load` no longer carries it, and its
///    verification reads the memory instead). A record the store
///    ALREADY holds is not overwritten — after an interruption between
///    this step and the removal the store is the newer state. Then the
///    store is read back and compared, and ONLY THEN the file is
///    removed. If the comparison fails the file stays and the next start
///    tries again.
///  * its peer is neither (a deleted contact, a group pair that ended):
///    removed, nothing taken over. Until S401 such a file stayed for good,
///    with the frames of the whole conversation, and came back to life
///    when the same party became a contact again (NB-12, U-11).
///  * it cannot be read (torn while appending, another key, another
///    version — U-12): reported and removed. It can never be opened again;
///    what it held is lost to this mailbox either way, and left lying it
///    would be message content outside the store that no deletion reaches.
///  * anything else of that name (`.enc.tmp`, a renamed copy): removed.
///
/// This is an enforcer over old stock with one take-over step, not a
/// second storage form: nothing here writes such a file, and after one
/// start none is left.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/history.dart';
import 'package:mycelium/history_store.dart';
import 'package:mycelium/message.dart' show DeliveryState, kIdentifierLength;

const String _prefix = 'verlauf_'; // german-ok: the old name on the disk
const int _version = 1;
const int _directionIncoming = 0;
const int _directionOutgoing = 1;
const String _fieldKeyIdentifier = 'cleona-history-enc-v1';
final RegExp _ofPeer = RegExp('^$_prefix([0-9a-f]{64})\\.enc\$');

/// Takes every history file in [directory] over into [store] and removes
/// it (file header). [known] says whether the mailbox keeps the peer with
/// this identifier (hex) — as a contact or as a group pair. [key] is the
/// mailbox's file key, from which the old build derived the key of its
/// records. Returns the number of entries taken over.
int historyFilesTakeOver({
  required Directory directory,
  required Uint8List key,
  required HistoryStore store,
  required bool Function(String peer) known,
  void Function(String)? report,
}) {
  if (!directory.existsSync()) return 0;
  final found = [
    for (final e in directory.listSync())
      if (_name(e).startsWith(_prefix)) e,
  ];
  if (found.isEmpty) return 0;
  final sodium = SodiumFFI();
  final fieldKey = sodium.hkdfSha256(
    FileEncryption(baseDir: directory.path, key: key).effectiveKey,
    info: utf8.encode(_fieldKeyIdentifier),
    length: 32,
  );
  var taken = 0;
  for (final e in found) {
    final peer = _ofPeer.firstMatch(_name(e))?.group(1);
    if (e is! File || peer == null) {
      _remove(e, report, 'a side file of the old history');
      continue;
    }
    final short = peer.substring(0, 8);
    if (!known(peer)) {
      _remove(e, report, 'the old history file of $short, which is no '
          'contact and no group pair any more — nothing taken over');
      continue;
    }
    final List<HistoryEntry> read;
    try {
      read = _fileRead(e.readAsBytesSync(), fieldKey, sodium);
    } on HistoryError catch (err) {
      _remove(e, report, 'the old history file of $short, which cannot be '
          'read ($err) — what it held is lost');
      continue;
    }
    // As the history keeps them; of two records of the same name the
    // later. A RECEIVED entry keeps no record since S403 (§20.2): its
    // identifier goes into the identity's received memory, and the
    // verification reads THAT back — a check against the records would
    // never pass again and the file would stay for good.
    final own = {
      for (final r in read.where((e) => e.outgoing))
        historyRecordKey(r): History.kept(r),
    };
    final received = {
      for (final r in read.where((e) => !e.outgoing)) r.identifier,
    }.toList();
    final before = {for (final r in store.load(peer)) historyRecordKey(r)};
    for (final w in own.entries) {
      if (!before.contains(w.key)) store.put(peer, w.value);
    }
    final freshReceived =
        received.where((id) => !store.incomingKnown(id)).length;
    for (final id in received) {
      store.incomingKeep(id);
    }
    final after = {for (final r in store.load(peer)) historyRecordKey(r): r};
    var missing = own.entries.where((w) {
      final r = after[w.key];
      return r == null || !before.contains(w.key) && !_same(r, w.value);
    }).length;
    missing += received.where((id) => !store.incomingKnown(id)).length;
    if (missing > 0) {
      report?.call('old history file of $short: $missing of '
          '${own.length + received.length} entr'
          '${own.length + received.length == 1 ? 'y' : 'ies'} did not '
          'come back from the store as written — the file stays, the next '
          'start tries again');
      continue;
    }
    final fresh =
        own.keys.where((k) => !before.contains(k)).length + freshReceived;
    taken += fresh;
    _remove(e, report, 'the old history file of $short after taking it over '
        'into the store ($fresh of ${own.length + received.length} entr'
        '${own.length + received.length == 1 ? 'y' : 'ies'} new there, '
        '${own.values.where((w) => w.open).length} open)');
  }
  return taken;
}

String _name(FileSystemEntity e) => e.uri.pathSegments
    .lastWhere((s) => s.isNotEmpty, orElse: () => '');

void _remove(FileSystemEntity e, void Function(String)? report, String what) {
  try {
    e.deleteSync(recursive: true);
    report?.call('removed $what');
  } on FileSystemException catch (err) {
    report?.call('could NOT remove $what: $err');
  }
}

bool _same(HistoryEntry a, HistoryEntry b) {
  if (a.outgoing != b.outgoing || a.state != b.state) return false;
  if (a.instant.millisecondsSinceEpoch != b.instant.millisecondsSinceEpoch) {
    return false;
  }
  return _equal(a.identifier, b.identifier) && _equal(a.content, b.content);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── THE OLD FILE, as the builds until S401 wrote it ────────────────────
//
// ```
// version (1 B)
// record: ciphertext length (u32 big-endian) | nonce (24 B) | ciphertext
// plaintext: identifier (8 B) | direction (1 B) | point in time (u64
//            big-endian, ms) | state (1 B, 0xFF for received) | content
// ```
// Every record sealed by itself (`secretBoxEncrypt`) under a key derived
// from the mailbox's file key (HKDF-SHA256, info `cleona-history-enc-v1`).

/// The entries of the file [bytes], in the order they stand there. Throws
/// [HistoryError] for a file that is empty, truncated, of another version,
/// sealed under another key or bent — never a part of it.
List<HistoryEntry> _fileRead(
    Uint8List bytes, Uint8List fieldKey, SodiumFFI sodium) {
  if (bytes.isEmpty) throw HistoryError('File is empty');
  if (bytes[0] != _version) {
    throw HistoryError('unknown version ${bytes[0]}');
  }
  final fresh = <HistoryEntry>[];
  var pos = 1;
  while (pos < bytes.length) {
    if (bytes.length - pos < 4) {
      throw HistoryError('File truncated (length field missing)');
    }
    final length =
        ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.big);
    pos += 4;
    if (bytes.length - pos < 24 + length) {
      throw HistoryError('File truncated (record incomplete)');
    }
    final nonce = Uint8List.fromList(bytes.sublist(pos, pos + 24));
    pos += 24;
    final cipher = Uint8List.fromList(bytes.sublist(pos, pos + length));
    pos += length;
    Uint8List plaintext;
    try {
      plaintext = sodium.secretBoxDecrypt(cipher, fieldKey, nonce);
    } on SodiumException catch (e) {
      throw HistoryError('Record cannot be decrypted: $e');
    }
    fresh.add(_outPlaintext(plaintext));
  }
  return fresh;
}

HistoryEntry _outPlaintext(Uint8List k) {
  const header = kIdentifierLength + 1 + 8 + 1;
  if (k.length < header) throw HistoryError('Record too short: ${k.length} B');
  var i = 0;
  final identifier = Uint8List.fromList(k.sublist(i, i += kIdentifierLength));
  final direction = k[i];
  i += 1;
  if (direction != _directionIncoming && direction != _directionOutgoing) {
    throw HistoryError('invalid direction $direction');
  }
  final ms = ByteData.sublistView(k, i, i + 8).getUint64(0, Endian.big);
  i += 8;
  final stateByte = k[i];
  i += 1;
  final content = Uint8List.fromList(k.sublist(i));
  final outgoing = direction == _directionOutgoing;
  DeliveryState? state;
  if (outgoing) {
    if (stateByte >= DeliveryState.values.length) {
      throw HistoryError('invalid state $stateByte');
    }
    state = DeliveryState.values[stateByte];
  } else if (stateByte != kHistoryNoState) {
    throw HistoryError('incoming record carries a state ($stateByte)');
  }
  return HistoryEntry(
    identifier: identifier,
    outgoing: outgoing,
    content: content,
    instant: DateTime.fromMillisecondsSinceEpoch(ms),
    state: state,
  );
}
