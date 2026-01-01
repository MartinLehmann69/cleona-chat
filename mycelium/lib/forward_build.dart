/// The byte layout of `0x20`, `0x21` and `0x23` (V4.2 §8.1; table in
/// `forward.dart`). Separate from `forward.dart` for the line budget
/// (mycelium/README.md rule 2) when the forwarder's bound per target came in
/// (S399 step 2, §20.2).
library;

import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;
import 'package:mycelium/pair.dart' show kCodeLength;

void _codeCheck(Uint8List code) {
  if (code.length != kCodeLength) {
    throw ArgumentError('Code must have $kCodeLength B, has ${code.length}');
  }
}

/// `kind | hop count | code | content` — a `0x20` or a `0x23`.
Uint8List codePacket(int kind, int hopCount, Uint8List code, Uint8List content) {
  _codeCheck(code);
  if (hopCount < 0 || hopCount > 0xFF) {
    throw ArgumentError('Hop count must be between 0 and 255, was $hopCount');
  }
  return (BytesBuilder(copy: false)
        ..addByte(kind)
        ..addByte(hopCount)
        ..add(code)
        ..add(content))
      .toBytes();
}

/// `0x21 | code` — unknown to me, or the way is closed (§8.1).
Uint8List unknownCodePacket(Uint8List code) {
  _codeCheck(code);
  return (BytesBuilder(copy: false)
        ..addByte(kinds.kUnknownCode)
        ..add(code))
      .toBytes();
}
