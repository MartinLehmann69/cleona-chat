/// The re-request and end mark of the splitter (V4.2 §11.3, D-41): the
/// header layout is described in `split.dart`. Out of `split.dart` for the
/// line budget (mycelium/README.md rule 2) when the layer diagnosis came in
/// (S405, owner approval 06.10.2026, proposal D) — moved unchanged.
library;

import 'dart:typed_data';

import 'package:mycelium/split.dart' show kHeader, kMaxPayload;

/// field2 of a re-request — never a valid seq no (`split.dart`).
const int kSentinelMissingRequest = 0xFFFF;

/// A re-request for [missing] of the transmission [identifier]; empty
/// [missing] is the end mark.
Uint8List buildMissingRequest(Uint8List identifier, List<int> missing) {
  final n = missing.length > kMaxPayload ~/ 2 ? kMaxPayload ~/ 2 : missing.length;
  final p = Uint8List(kHeader + n * 2);
  p.setRange(0, 8, identifier);
  final bd = ByteData.sublistView(p);
  bd.setUint16(8, n, Endian.little);
  bd.setUint16(10, kSentinelMissingRequest, Endian.little);
  for (var i = 0; i < n; i++) {
    bd.setUint16(kHeader + i * 2, missing[i], Endian.little);
  }
  return p;
}
