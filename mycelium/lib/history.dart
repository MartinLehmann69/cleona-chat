/// The history — what a conversation with ONE peer remembers
/// restart-proof. [memory.dart] remembers the own post box and the
/// contacts; the messages themselves were gone after a restart. This
/// file supplies that.
///
/// ── ONE FILE PER PEER, NOT ONE FOR ALL ──────────────────
/// A single collective file would have to be rewritten on EVERY new message in EVERY
/// chat, because it carries a shared encryption
/// — the write load then grows with the ENTIRE history, although
/// only a single peer has changed. Separate files
/// keep the cost of a change at the size of THIS conversation.
///
/// ── APPENDING INSTEAD OF REWRITING ──────────────────────────────────────
/// Every message is a record encrypted by itself (own nonce,
/// own key MAC via [SodiumFFI.secretBoxEncrypt] — the same
/// algorithm that [FileEncryption] uses). A new message is
/// therefore APPENDED to the canonical file: the previously written
/// records are not touched in doing so, hence not re-encrypted
/// or rewritten either — the cost is independent of the previous
/// history length. A state change (e.g. receipt arrived)
/// by contrast changes a record IN THE MIDDLE of the file; that cannot be
/// appended and rewrites the ENTIRE file via a side file
/// ([atomicReplace] — the same function that [FileEncryption] uses for its
/// own tmp+rename path).
///
/// ── THE KEY ────────────────────────────────────────────────────
/// [FileEncryption] itself is used only to get at [FileEncryption.
/// effectiveKey] (the base key passed by the caller,
/// seed-derived — the same door through which the media key also
/// goes, see header comment there). Because appending needs a separate,
/// independently encrypted record per message, this
/// file cannot call [FileEncryption.writeBinaryFile] itself (that
/// ALWAYS re-encrypts the entire content — right for a
/// state change, for an append the opposite of what is
/// needed). The base key is therefore mapped via HKDF-SHA256 to
/// a separate field key (own label, so that a
/// key leak elsewhere does not affect this history as well —
/// the same principle with which `MediaCipher` separates its labels from the
/// base encryption).
///
/// ── OPEN SEAM ────────────────────────────────────────────────────────
/// Appending writes directly to the end of the file, WITHOUT a side file. That is
/// safe for all PREVIOUSLY written records — an append cannot
/// touch them, no matter when the process aborts in doing so. But if the
/// process crashes exactly DURING this one write, an
/// incomplete record remains at the end of the file; [History.load] rejects such
/// a file on the next start as truncated (the same
/// check as for deliberate damage), instead of silently discarding the
/// rest. The window is the duration of a single
/// `writeFromSync` for a few hundred bytes; a next
/// state change repairs the file anyway by complete
/// rewriting. A log compaction run that closes this window entirely
/// is not built (line budget) — see `berichte/
/// P12-verlauf.md`.
///
/// ── FILE LAYOUT ────────────────────────────────────────────────────────
/// ```
/// version (1 B)
/// record 1: ciphertext length (u32 big-endian) | nonce (24 B) | ciphertext
/// record 2: ...
/// ```
/// The plaintext per record (before encrypting):
/// ```
/// identifier (8 B) | direction (1 B) | point in time (u64 big-endian, ms) |
/// state (1 B, 0xFF for received) | content (rest, raw bytes)
/// ```
///
/// ── THE FORMAT HAS NOT CHANGED (S385) ────────────────────────
/// Until S385 the content was a [String] and was written as `utf8.encode(text)`
/// at the same place; it is now a [Uint8List] and is written there
/// unchanged. For every entry whose content was
/// valid UTF-8, the bytes on disk are therefore IDENTICAL —
/// same position, same length. The length of the content already stood
/// before it (the record's ciphertext length bounds the plaintext, the
/// content is its rest), so there is no field that would be added.
/// [_version] therefore stays at 1: an older file reads
/// on unchanged.
///
/// What GOES AWAY is a throw: until S385 a
/// `utf8.decode` ran over the content on reading, and a file with bytes that are not
/// valid UTF-8 could no longer be opened at all — a single
/// such entry would have made the ENTIRE history with this peer
/// unreadable. Raw bytes cannot be invalid.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/storage/atomic_replace.dart';
import 'package:mycelium/message.dart' show DeliveryState, kIdentifierLength;
import 'package:mycelium/envelope.dart' show Address;

/// A history is there, but unusable: wrong key, truncated,
/// unknown version, bent bytes. Thrown BEFORE the return from
/// [History.load] — there is never a half instance.
class HistoryError implements Exception {
  final String reason;
  HistoryError(this.reason);
  @override
  String toString() => 'VerlaufFehler: $reason';
}

/// A single message as it stands in the history with a peer.
class HistoryEntry {
  final Uint8List identifier;
  final bool outgoing;

  /// The payload, unchanged. This file does not interpret it — see
  /// file header and `message.dart`.
  final Uint8List content;
  final DateTime instant;

  /// Set only for [outgoing] — one of the four values from
  /// `message.dart`.
  final DeliveryState? state;

  HistoryEntry({
    required this.identifier,
    required this.outgoing,
    required this.content,
    required this.instant,
    this.state,
  }) {
    if (identifier.length != kIdentifierLength) {
      throw ArgumentError(
          'identifier must be $kIdentifierLength B, was ${identifier.length}');
    }
    if (outgoing && state == null) {
      throw ArgumentError('an outgoing entry needs a state');
    }
    if (!outgoing && state != null) {
      throw ArgumentError('an incoming entry carries no state');
    }
  }

  /// Not yet receipted and not yet given up — the caller must
  /// deliver this entry again after loading.
  bool get open =>
      outgoing &&
      state != DeliveryState.delivered &&
      state != DeliveryState.failed;

  HistoryEntry _withState(DeliveryState fresh) => HistoryEntry(
        identifier: identifier,
        outgoing: outgoing,
        content: content,
        instant: instant,
        state: fresh,
      );

  HistoryEntry _withContent(Uint8List fresh) => HistoryEntry(
        identifier: identifier,
        outgoing: outgoing,
        content: fresh,
        instant: instant,
        state: state,
      );
}

const int _version = 1;
const int _directionIncoming = 0;
const int _directionOutgoing = 1;
const int _noState = 0xFF;
const int _frameHeader = 4 + 24; // ciphertext length + nonce
const String _fieldKeyIdentifier = 'cleona-history-enc-v1';

/// The history with exactly ONE peer. One object per peer,
/// one file per object (see file header comment).
class History {
  final File _canonical;
  final File _tmp;
  final Uint8List _fieldKey;
  final SodiumFFI _sodium;
  final List<HistoryEntry> _entries = [];

  /// The identifiers of the RECEIVED entries — the memory against the
  /// second copy of the same message (§7.1 starts all steps at once).
  /// It is NO second storage: it is built from exactly this file
  /// and lives exactly as long as the conversation.
  final Set<String> _incoming = {};

  History._(this._canonical, this._tmp, this._fieldKey, this._sodium);

  /// Loads the history with [peer] from [directory], or creates an
  /// empty one. If something lies there that cannot be read with [key],
  /// this method throws [HistoryError] instead of a half
  /// instance.
  static History load(
      Directory directory, Address peer, Uint8List key) {
    directory.createSync(recursive: true);
    final sodium = SodiumFFI();
    final baseKey =
        FileEncryption(baseDir: directory.path, key: key).effectiveKey;
    final fieldKey = sodium.hkdfSha256(
      baseKey,
      info: utf8.encode(_fieldKeyIdentifier),
      length: 32,
    );
    // By the IDENTIFIER: one file per peer, across every KEM rotation.
    final basis = '${directory.path}/verlauf_${_hex(peer.identifier)}';
    final v = History._(
        File('$basis.enc'), File('$basis.enc.tmp'), fieldKey, sodium);
    if (v._canonical.existsSync()) {
      v._readIn(v._canonical.readAsBytesSync());
    }
    return v;
  }

  /// All entries, in the order of arrival/sending.
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Outgoing entries that are not yet receipted and not given up
  /// — the caller must deliver them again.
  Iterable<HistoryEntry> get openOutbounds =>
      _entries.where((e) => e.open);

  /// Whether a RECEIVED message with this identifier already stands in the conversation.
  /// An outgoing entry does not count: sender and
  /// recipient draw their identifiers independently (`message.dart`),
  /// a collision must not swallow the opposite direction.
  bool alreadyIncoming(Uint8List identifier) =>
      _incoming.contains(_hex(identifier));

  /// Appends [entry] — cheap, see file header comment.
  void append(HistoryEntry entry) {
    final frame = _encrypt(entry);
    final newFile = !_canonical.existsSync();
    _canonical.parent.createSync(recursive: true);
    final raf = _canonical.openSync(mode: FileMode.append);
    try {
      if (newFile) raf.writeByteSync(_version);
      raf.writeFromSync(frame);
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    _entries.add(entry);
    if (!entry.outgoing) _incoming.add(_hex(entry.identifier));
  }

  /// Changes the state of the outgoing entry with this identifier and
  /// rewrites the ENTIRE file for that (see file header comment).
  void stateChange(Uint8List identifier, DeliveryState fresh) {
    final idx = _entries
        .indexWhere((e) => e.outgoing && _equal(e.identifier, identifier));
    if (idx == -1) {
      throw HistoryError(
          'no outgoing entry with this identifier in the history');
    }
    _entries[idx] = _entries[idx]._withState(fresh);
    _newWrite();
  }
  /// Changes the content of an entry — the point in time stays that of the
  /// ORIGINAL. An edit is not a new message; if it
  /// slid forward, the reply to it would suddenly stand before it.
  void contentChange(Uint8List identifier, Uint8List newContent) {
    final idx = _entries.indexWhere((e) => _equal(e.identifier, identifier));
    if (idx == -1) {
      throw HistoryError('no entry with this identifier in the history');
    }
    _entries[idx] = _entries[idx]._withContent(newContent);
    _newWrite();
  }


  void _newWrite() {
    final b = BytesBuilder();
    b.addByte(_version);
    for (final e in _entries) {
      b.add(_encrypt(e));
    }
    _tmp.parent.createSync(recursive: true);
    _tmp.writeAsBytesSync(b.toBytes(), flush: true);
    atomicReplace(_tmp, _canonical);
  }

  Uint8List _encrypt(HistoryEntry e) {
    final content = e.content;
    final plaintext = Uint8List(kIdentifierLength + 1 + 8 + 1 + content.length);
    var i = 0;
    plaintext.setRange(i, i += kIdentifierLength, e.identifier);
    plaintext[i] = e.outgoing ? _directionOutgoing : _directionIncoming;
    i += 1;
    ByteData.sublistView(plaintext)
        .setUint64(i, e.instant.millisecondsSinceEpoch, Endian.big);
    i += 8;
    plaintext[i] = e.outgoing ? e.state!.index : _noState;
    i += 1;
    plaintext.setRange(i, i += content.length, content);

    final nonce = _sodium.randomBytes(24);
    final cipher = _sodium.secretBoxEncrypt(plaintext, _fieldKey, nonce);

    final frame = Uint8List(_frameHeader + cipher.length);
    ByteData.sublistView(frame).setUint32(0, cipher.length, Endian.big);
    frame.setRange(4, 28, nonce);
    frame.setRange(28, frame.length, cipher);
    return frame;
  }

  void _readIn(Uint8List bytes) {
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
        plaintext = _sodium.secretBoxDecrypt(cipher, _fieldKey, nonce);
      } on SodiumException catch (e) {
        throw HistoryError('Record cannot be decrypted: $e');
      }
      fresh.add(_outPlaintext(plaintext));
    }
    _entries
      ..clear()
      ..addAll(fresh);
    _incoming
      ..clear()
      ..addAll(fresh.where((e) => !e.outgoing).map((e) => _hex(e.identifier)));
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
    // `sublist` copies — the record's plaintext buffer is not
    // held on to.
    final content = Uint8List.fromList(k.sublist(i));
    final outgoing = direction == _directionOutgoing;
    DeliveryState? state;
    if (outgoing) {
      if (stateByte >= DeliveryState.values.length) {
        throw HistoryError('invalid state $stateByte');
      }
      state = DeliveryState.values[stateByte];
    } else if (stateByte != _noState) {
      throw HistoryError(
          'incoming record carries a state ($stateByte)');
    }
    return HistoryEntry(
      identifier: identifier,
      outgoing: outgoing,
      content: content,
      instant: DateTime.fromMillisecondsSinceEpoch(ms),
      state: state,
    );
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
