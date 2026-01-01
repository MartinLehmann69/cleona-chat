/// The registration of the own codes with the fixed neighbour (V4.2 §8.1, §5.5;
/// proposal M, S391).
///
/// ── WHAT TRAVELS ────────────────────────────────────────────────────────────
///
/// The codes under which the contacts of this device reach it — for
/// TODAY and TOMORROW (UTC). One list per day, padded with random codes
/// to a multiple of [kCodesPerPiece] (at least one), so that its
/// length says little about the number of contacts. A piece carries exactly
/// [kCodesPerPiece] codes and fits into ONE cover packet (content byte `0x03`):
///
/// ```
/// day u32 BE | piece u8 | pieces u8 | count u8 | device code 16 B
///                                              | count × 16 B
/// ```
///
/// Every piece stands for itself: the neighbour registers what arrives, and
/// needs no order (`code_table.dart`). The piece counter only says
/// how many belong to a list.
///
/// ── THE DEVICE CODE (S392, option B) ─────────────────────────────────────
///
/// The DEVICE's own code: 16 B, randomly drawn on first start, afterwards
/// restart-proof (`host_memory.dart`, like the fixed port). The neighbour
/// keeps its table by it instead of by `address:port`.
///
/// Why it has to exist: until S392 the neighbour recognised a device by the
/// source address of the registration — exactly the quantity that changes on a move
/// (NAT rebinding, Wi-Fi → cellular, new port mapping). "Whoever registers
/// first keeps the code" (§8.1) then rejected the registration of the OWN
/// device, and step 3 failed for 24–48 h for ALL contacts
/// (`berichte/S392-M2-ADRESSWECHSEL.md`, finding B-1). With the device code
/// the sentence stays literally in force — "whoever" now means the device.
///
/// It reveals nothing: it travels exclusively in the pairwise shell to the
/// fixed neighbour, which holds the table anyway. And it is a **code**,
/// not a new noun of the delivery layer (§3.6).
///
/// ── WHEN ─────────────────────────────────────────────────────────────────
///
/// No packet of its own. The pieces travel in packets that go to the
/// fixed neighbour anyway (cover stream, keep-alive). A rebuild happens when
/// one of the lists, the UTC day or the fixed neighbour has changed —
/// measured by a fingerprint that is recomputed at every opportunity.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/code_table.dart' show kCodesPerDevice;
import 'package:mycelium/pair.dart' show kCodeLength;

/// Codes per piece — and the multiple to which padding happens.
const int kCodesPerPiece = 64;

/// Codes per day: two days fit together within the limit per device.
const int kCodesPerDay = kCodesPerDevice ~/ 2;

/// Day, piece counter and count — the device code stands before them.
const int _kBeforeCode = 4 + 1 + 1 + 1;
const int _kHeader = _kBeforeCode + kCodeLength;

/// Length of a piece: 23 + 64 × 16 = 1047 B (limit 1156 B,
/// `tarnstrom_inhalt.dart`).
const int kPieceLength = _kHeader + kCodesPerPiece * kCodeLength;

/// A read piece.
typedef RegisterPiece = ({
  int day,
  Uint8List device,
  int piece,
  int pieces,
  List<Uint8List> codes
});

/// A fresh device code. Only the first start of a device draws one
/// (`HostMemory.devicesCodeSet`); a node without memory
/// gets one per run so that it does not stand there without one.
Uint8List newDevicesCode([Random? random]) {
  final z = random ?? Random.secure();
  return Uint8List.fromList(List.generate(kCodeLength, (_) => z.nextInt(256)));
}

/// Splits the codes of a day into pieces.
List<Uint8List> registrationBuild(
    int day, Uint8List device, List<Uint8List> codes, Random random) {
  if (device.length != kCodeLength) {
    throw ArgumentError('device code ${device.length} B, $kCodeLength expected');
  }
  final list = codes.length > kCodesPerDay ? codes.sublist(0, kCodesPerDay) : codes;
  final target = max(kCodesPerPiece,
      (list.length + kCodesPerPiece - 1) ~/ kCodesPerPiece * kCodesPerPiece);
  final all = [
    ...list,
    for (var i = list.length; i < target; i++)
      Uint8List.fromList(List.generate(kCodeLength, (_) => random.nextInt(256))),
  ]..shuffle(random);
  final pieces = target ~/ kCodesPerPiece;
  return [
    for (var s = 0; s < pieces; s++)
      (() {
        final b = BytesBuilder(copy: false)
          ..add((ByteData(4)..setUint32(0, day)).buffer.asUint8List())
          ..addByte(s)
          ..addByte(pieces)
          ..addByte(kCodesPerPiece)
          ..add(device);
        for (var i = 0; i < kCodesPerPiece; i++) {
          b.add(all[s * kCodesPerPiece + i]);
        }
        return b.toBytes();
      })(),
  ];
}

/// Reads a piece; `null` if it is none. Never throws.
RegisterPiece? registrationRead(Uint8List p) {
  if (p.length < _kHeader) return null;
  final d = ByteData.sublistView(p);
  final count = p[6];
  if (p.length != _kHeader + count * kCodeLength || p[4] >= p[5]) return null;
  return (
    day: d.getUint32(0),
    device: Uint8List.fromList(Uint8List.sublistView(p, _kBeforeCode, _kHeader)),
    piece: p[4],
    pieces: p[5],
    codes: [
      for (var i = 0; i < count; i++)
        Uint8List.fromList(Uint8List.sublistView(
            p, _kHeader + i * kCodeLength, _kHeader + (i + 1) * kCodeLength)),
    ],
  );
}

/// The state of the own registration: what is still to be sent.
class Registrant {
  /// The codes of a day (all mailboxes together).
  final Iterable<Uint8List> Function(int day) codes;

  /// The own code of this device — in EVERY piece.
  final Uint8List device;
  final Random _random;

  String? _sent;
  String? _planned;
  final List<Uint8List> _pieces = [];

  /// Counters — read only.
  int piecesSent = 0;
  int listenBuilt = 0;

  Registrant(this.codes, {required this.device, Random? random})
      : _random = random ?? Random.secure();

  /// How many pieces are still outstanding (after the last [next]).
  int get pending => _pieces.length;

  /// The next piece for the fixed neighbour [fixed] on day [today] —
  /// `null` if everything has been sent.
  Uint8List? next(String fixed, int today) {
    final todayCodes = codes(today).toList();
    final tomorrowCodes = codes(today + 1).toList();
    final fingerprint = _fingerprint(fixed, today, todayCodes, tomorrowCodes);
    if (fingerprint == _sent) return null;
    if (fingerprint != _planned) {
      _planned = fingerprint;
      listenBuilt++;
      _pieces
        ..clear()
        ..addAll(registrationBuild(today, device, todayCodes, _random))
        ..addAll(registrationBuild(today + 1, device, tomorrowCodes, _random));
    }
    return _pieces.isEmpty ? null : _pieces.first;
  }

  /// The last delivered piece has gone out.
  void sent() {
    if (_pieces.isEmpty) return;
    _pieces.removeAt(0);
    piecesSent++;
    if (_pieces.isEmpty) _sent = _planned;
  }

  /// Forgets the state — the next opportunity sends everything anew.
  void forget() {
    _sent = null;
    _planned = null;
    _pieces.clear();
  }

  static String _fingerprint(
      String fixed, int today, List<Uint8List> a, List<Uint8List> b) {
    String list(List<Uint8List> l) =>
        (l.map(_hex).toList()..sort()).join();
    final h = SodiumFFI()
        .sha256(utf8.encode('$fixed|$today|${list(a)}|${list(b)}'));
    return _hex(h);
  }
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
