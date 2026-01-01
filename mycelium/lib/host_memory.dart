/// What the HOST remembers restart-proof: the fixed port, the device code, the
/// neighbours of the last run and the relays from read cards. Everything
/// belongs to the device, to no identity.
///
/// ── WHY THIS FILE EXISTS (S385, cut F) ──────────────────────
///
/// Until S385 everything lay in ONE `gedaechtnis.enc` per service, and a service
/// was exactly one identity. V4.2 §4.5.1 demands one daemon with N
/// identities on ONE port. Then the port has N owners if it stands in the
/// memory of an identity — and the neighbourhood N versions
/// that contradict each other. Port and neighbours therefore stand here, once per
/// host; post box, contacts and invitations stay per mailbox in
/// `memory.dart`.
///
/// ── FILE LAYOUT ──────────────────────────────────────────────────────
/// ```
/// version (1 B)
/// port flag (1 B) | port (u16, only with flag 1)
/// number of neighbours (u16) | per neighbour: seat (1 B: 0x00 none,
///     0x01 the card's, 0x02..0x04 contact seat 1..3)
///     | number of addresses (1 B, 1..4) | per address: type byte (1 B)
///     | address (4 or 16 B) | port (u16 LE) | last (u64 ms)
/// number of relays (1 B, at most 3) | per relay: length (1 B) | text
/// source 4 on (1 B, 0x00 off, 0x01 on)
/// device code flag (1 B) | device code (16 B, only with flag 1)
/// ```
/// No legacy format is read — there are no legacy profiles.
///
/// Version 2 (S385, call D): the identifier per neighbour goes away. It was the
/// identifier from the call, and that has since been drawn anew per start — a
/// remembered identifier matched nothing on the next run. The neighbourhood
/// is kept by address:port.
///
/// Version 3 (S388, V4.2 §11.9): the relays from read cards. The same
/// encoding as the card's relay list (`card_address.dart`), the same
/// limits. Versions 1 and 2 are rejected, not converted.
///
/// Version 4 (S388, V4.2 §11.9): the switch of source 4 ("The source can
/// be switched off by the user"). A device value, because there is ONE host per device.
/// Default on. Version 3 is rejected — it lay only on the
/// unpublished branch of this session.
///
/// Version 5 (S390, V4.2 §11.1): the neighbour address carries its type byte and
/// can thus be IPv6. Up to here four raw bytes stood there, followed
/// by port and timestamp of fixed width — a 16 B entry would have shifted every
/// following field of the file, and exactly therefore the
/// bolt in `neighbourhood.dart` could not be released alone. Writing and
/// reading use [addressWrite]/[addressRead], i.e. the SAME
/// codec as the card; the port moves from big to little endian in the process.
/// That is not a side effect but the point: ONE codec, not two.
/// Version 4 is rejected, not converted.
///
/// Version 6 (S391, W7): per neighbour one byte "fixed" — the fixed seat of the
/// open set (§5.2), named by the own cards, survives the
/// restart. Since S391 "last" is the confirmation stamp
/// (`neighbourhood.dart`); a never confirmed hint carries 0. Version 5
/// is rejected and cleared by the enforcer, the port rescued from the header
/// — the header is unchanged.
///
/// Version 7 (S392, V4.2 §8.1): the device code. 16 B, drawn randomly on first start,
/// afterwards unchanged — like the fixed port, and for the same
/// reason: every registration piece carries it (`code_registration.dart`), and the
/// fixed neighbour keeps its code table by it instead of by the
/// source address. A new code per start would be a device change per start
/// and would create exactly the case that option B closes
/// (`berichte/S392-M2-ADRESSWECHSEL.md`). Version 6 is rejected, not
/// converted; the fixed port is rescued from the header as usual,
/// the device code is not — a device that loses its data is
/// a new device for the neighbour, and that is right.
///
/// Version 8 (S394, V4.2 §11.8 V4): a neighbour is a NODE with up to
/// [kAddressesPerNeighbour] addresses, each with its own stamp. What the
/// neighbour named in an address family without socket (a name) is not
/// written (§11.1 V1: "not stored"). Version 7 is rejected and cleared; the
/// device code is not rescued, as with version 6.
///
/// Version 9 (2026-09, contacts as fixed neighbours, §5.2): the byte "fixed"
/// becomes the SEAT byte — besides the card's seat up to three contact
/// seats survive the restart, like the card's. Version 8 is rejected and
/// cleared; the device code is not rescued, as with version 6.
///
/// Rejected — and since S391 also CLEARED. Until then the service ended
/// on rejection, permanently and with exit 0; measured on bootstrap and
/// Windows VM. [HostMemory.clearedOpen] removes the legacy data
/// and rescues the fixed port in doing so (§11.1); the derivation stands in
/// `memory_enforcer.dart`. [HostMemory.open] stays strict.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:mycelium/code_registration.dart' show newDevicesCode;
import 'package:mycelium/memory_enforcer.dart' show legacyDataClear;
import 'package:mycelium/memory_invitation.dart' show MemoryError, Reader;
import 'package:mycelium/card_address.dart'
    show
        addressRead,
        addressWrite,
        kRelayAtMost,
        relayRead,
        relayShortage,
        relayWrite;
import 'package:mycelium/neighbourhood.dart';
import 'package:mycelium/neighbourhood_contacts.dart' show kContactSeats;
import 'package:mycelium/pair.dart' show kCodeLength;

/// [FileEncryption] itself appends `.enc`: on disk `wirt.enc`.
const String _fileName = 'host';

/// The current version of the host file — public for the smoke of the
/// enforcer, which would otherwise have to pin a number.
const int kHostVersion = 9;
const int _version = kHostVersion;

/// The range from which a device draws its permanent port.
/// Below 20000 lie too many assigned services, above
/// 60000 the ephemeral range of many kernels — a port from there might
/// already be held by a transient connection on the next
/// start.
const int kPortFrom = 20000;
const int kPortUntil = 60000;

class HostMemory {
  final FileEncryption _enc;
  final String _path;
  int? _ownPort;
  Uint8List? _devicesCode;
  bool _devicesCodeFresh = false;
  final Random _dice = Random.secure();

  /// The neighbours of the last run, with stamp and fixed flag. Per
  /// §11.8 the FIRST source at start — immediately there and "usually enough".
  final List<Neighbour> rememberedNeighbours = [];

  /// The relays from read cards (§11.9), the most recently admitted
  /// first, at most [kRelayAtMost]. Change only via
  /// [relayAdmit].
  final List<String> relaysFromCards = [];

  /// §11.9: whether source 4 (external address entries) is on. Default on.
  bool outsideSourceOn = true;

  HostMemory._(this._enc, this._path);

  /// Loads what lies in [directory], or creates an empty one. Something unreadable
  /// (wrong key, truncated, foreign version) throws
  /// [MemoryError] instead of delivering a half instance.
  static HostMemory open(Directory directory, Uint8List key) {
    directory.createSync(recursive: true);
    final path = '${directory.path}/$_fileName';
    final enc = FileEncryption(baseDir: directory.path, key: key);
    final g = HostMemory._(enc, path);
    if (File('$path.enc').existsSync()) {
      final bytes = enc.readBinaryFile(path);
      if (bytes == null) {
        throw MemoryError('$path.enc exists, but cannot be '
            'read — wrong key or damaged file');
      }
      g._decode(bytes);
    }
    return g;
  }

  /// Like [open], but first clears away legacy data of a foreign version
  /// and rescues the fixed port in doing so (§11.1). That is the path that
  /// `hostStart` takes; [open] stays strict and does not judge.
  ///
  /// The reasoning for both stands in `memory_enforcer.dart`.
  static HostMemory clearedOpen(
    Directory directory,
    Uint8List key, {
    void Function(String)? report,
  }) {
    int? rescued;
    legacyDataClear(
      directory: directory,
      fileName: _fileName,
      runningVersion: _version,
      key: key,
      report: report,
      beforeTheDelete: (old) => rescued = _portFromHeader(old),
    );
    final g = open(directory, key);
    final port = rescued;
    if (port != null && g._ownPort == null) {
      g._ownPort = port;
      g.save();
      report?.call('mycelium: fixed port $port taken over from the old stock '
          '— a port change would invalidate every card handed out (§11.1)');
    }
    return g;
  }

  /// The HEADER of the file, which has no version: version (1 B), port flag
  /// (1 B), port (u16, big-endian). Unchanged since version 2, pinned
  /// by `test/smoke_memory_enforcer.dart`.
  ///
  /// `null` if no port was remembered or the read value does not come from
  /// the random range — then one is drawn instead of
  /// believing a bent byte.
  static int? _portFromHeader(Uint8List old) {
    try {
      final l = Reader(old)..byte(); // version, already checked
      if (l.byte() != 1) return null;
      final p = l.u16();
      return (p >= kPortFrom && p <= kPortUntil) ? p : null;
    } on MemoryError {
      return null;
    }
  }

  /// The port at which this device is permanently reachable, or `null`.
  int? get ownPort => _ownPort;

  /// The device code, or `null` as long as none has been drawn.
  Uint8List? get devicesCode => _devicesCode;

  /// Whether [devicesCodeSet] DREW one in this run — then it is
  /// to be saved, otherwise the code is gone again on the next start.
  bool get devicesCodeFresh => _devicesCodeFresh;

  /// Sets the device code: drawn randomly on the first call, afterwards
  /// the same (§8.1). [save] makes it restart-proof.
  ///
  /// Why fixed at all: the fixed neighbour keeps its code table
  /// by this value (`code_table.dart`). If it were new per start,
  /// this device would be a stranger after every restart — and its own
  /// codes would be locked by the old entry until that expires.
  Uint8List devicesCodeSet() {
    final there = _devicesCode;
    if (there != null) return there;
    _devicesCodeFresh = true;
    return _devicesCode = newDevicesCode(_dice);
  }

  /// Sets the permanent port: drawn randomly on the first call, afterwards
  /// the same. [save] makes it restart-proof.
  ///
  /// Why fixed at all: EVERY address that is remembered anywhere or written into
  /// a card carries this port. With a port assigned by the
  /// operating system every restart devalues every
  /// issued card, every learned way back, every remembered neighbour.
  int portSet() =>
      _ownPort ??= kPortFrom + _dice.nextInt(kPortUntil - kPortFrom + 1);

  /// Throws away the set port and draws anew — for the case that
  /// another program holds it in the meantime.
  int portNewRoll() {
    _ownPort = null;
    return portSet();
  }

  /// Admits [fresh] into [relaysFromCards] (§11.9): unfit and already
  /// known entries not, the newest in front, above [kRelayAtMost]
  /// the oldest falls — as many as a card can pass on.
  /// `true` if the list has changed; only then is saving needed.
  /// Does not save itself.
  bool relayAdmit(Iterable<String> fresh) {
    final before = relaysFromCards.join('\n');
    for (final r in fresh) {
      if (relayShortage(r) != null || relaysFromCards.contains(r)) continue;
      relaysFromCards.insert(0, r);
    }
    if (relaysFromCards.length > kRelayAtMost) {
      relaysFromCards.removeRange(kRelayAtMost, relaysFromCards.length);
    }
    return relaysFromCards.join('\n') != before;
  }

  /// Writes encrypted and atomically (`.enc.tmp`, then renamed).
  void save() => _enc.writeBinaryFile(_path, _encode());

  Uint8List _encode() {
    final b = BytesBuilder()..addByte(_version);
    final p = _ownPort;
    b.addByte(p == null ? 0 : 1);
    if (p != null) b.add(_u16(p));
    final neighbours = rememberedNeighbours.take(Neighbourhood.atMost).toList();
    b.add(_u16(neighbours.length));
    for (final n in neighbours) {
      b
        ..addByte(n.fixed ? 1 : (n.contactSeat == 0 ? 0 : 1 + n.contactSeat))
        ..addByte(n.addresses.length);
      for (final a in n.addresses) {
        addressWrite(b, a.asCardAddress); // type + address + port
        b.add(_u64(a.last.millisecondsSinceEpoch));
      }
    }
    relayWrite(b, relaysFromCards.take(kRelayAtMost).toList());
    b.addByte(outsideSourceOn ? 1 : 0);
    final c = _devicesCode;
    b.addByte(c == null ? 0 : 1);
    if (c != null) b.add(c);
    return b.toBytes();
  }

  void _decode(Uint8List bytes) {
    try {
      final l = Reader(bytes);
      final version = l.byte();
      if (version != _version) {
        throw MemoryError('unknown version $version');
      }
      final hasPort = l.byte();
      int? port;
      if (hasPort == 1) {
        port = l.u16();
        if (port == 0) {
          throw MemoryError('remembered port 0 is not a fixed port');
        }
      } else if (hasPort != 0) {
        throw MemoryError('invalid port flag $hasPort');
      }
      final count = l.u16();
      if (count > Neighbourhood.atMost) {
        throw MemoryError('$count remembered neighbours, at most '
            '${Neighbourhood.atMost} are provided');
      }
      final neighbours = <Neighbour>[];
      for (var i = 0; i < count; i++) {
        final seat = l.byte();
        if (seat > 1 + kContactSeats) {
          throw MemoryError('invalid seat byte $seat, neighbour ${i + 1}');
        }
        final many = l.byte();
        if (many < 1 || many > kAddressesPerNeighbour) {
          throw MemoryError('$many addresses, neighbour ${i + 1}');
        }
        final addresses = <NeighbourAddress>[
          for (var j = 0; j < many; j++)
            if (addressRead(l.bytes, 'neighbour ${i + 1}') case final w)
              NeighbourAddress(InternetAddress.fromRawAddress(w.address),
                  w.port, DateTime.fromMillisecondsSinceEpoch(l.u64())),
        ];
        neighbours.add(Neighbour.of(addresses,
            fixed: seat == 1, contactSeat: seat > 1 ? seat - 1 : 0));
      }
      final relay = relayRead(l.bytes);
      final flag = l.byte();
      if (flag > 1) {
        throw MemoryError('invalid switch of source 4: $flag');
      }
      final hasCode = l.byte();
      if (hasCode > 1) {
        throw MemoryError('invalid device code flag $hasCode');
      }
      final code = hasCode == 1 ? l.bytes(kCodeLength) : null;
      l.done();
      outsideSourceOn = flag == 1;
      _devicesCode = code;
      _devicesCodeFresh = false;
      _ownPort = port;
      rememberedNeighbours
        ..clear()
        ..addAll(neighbours);
      relaysFromCards
        ..clear()
        ..addAll(relay);
    } on MemoryError {
      rethrow;
    } catch (e) {
      throw MemoryError('Content damaged: $e');
    }
  }
}

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.big)).buffer.asUint8List();
Uint8List _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.big)).buffer.asUint8List();
