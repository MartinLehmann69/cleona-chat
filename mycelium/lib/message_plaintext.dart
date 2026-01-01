import 'dart:typed_data';

import 'package:mycelium/card.dart';
import 'package:mycelium/message.dart' show MessageError, kIdentifierLength;
import 'package:mycelium/neighbour_list.dart';

/// The sealed plaintext of every kind `message.dart` sends — message, pair
/// notice and acknowledgement (`0x11`), laid out in that file's header:
///
/// ```
/// identifier 8 ‖ fixed neighbours ‖ rest
/// ```
///
/// Writer and reader stand together so the layout has ONE place.

/// identifier ‖ [neighbours] ‖ [rest]. Whoever builds such a plaintext
/// outside `Messages` builds it here.
Uint8List messagePlaintext(
    Uint8List identifier, List<CardAddress> neighbours, List<int> rest,
    {bool keys = false}) {
  final b = BytesBuilder()..add(identifier);
  neighbourListWrite(b, neighbourListClean(neighbours), withKeys: keys);
  return (b..add(rest)).toBytes();
}

/// Counterpart to [messagePlaintext]: the identifier, the fixed neighbours
/// (and whether the list carried the S407 key bit) and the rest — copies, a
/// view would keep the unsealed buffer alive.
({
  Uint8List identifier,
  List<CardAddress> neighbours,
  bool keyed,
  Uint8List rest
}) messagePlaintextRead(Uint8List plaintext) {
  var pos = 0;
  Uint8List read(int n) {
    if (pos + n > plaintext.length) {
      throw MessageError('plaintext too short (${plaintext.length} B)');
    }
    return Uint8List.sublistView(plaintext, pos, pos += n);
  }

  final identifier = Uint8List.fromList(read(kIdentifierLength));
  final keyed =
      pos < plaintext.length && neighbourListShowsKeys(plaintext[pos]);
  final List<CardAddress> list;
  try {
    list = neighbourListRead(read, 'fixed neighbours', withKeys: true);
  } on CardFormatError catch (e) {
    throw MessageError('$e');
  }
  return (
    identifier: identifier,
    neighbours: list,
    keyed: keyed,
    rest: Uint8List.fromList(Uint8List.sublistView(plaintext, pos)),
  );
}
