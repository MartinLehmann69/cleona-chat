import 'dart:io';
import 'dart:typed_data';

/// What a caller needs from the wire — packet out, packet in. Nothing more.
///
/// This contract exists since `shell.dart` lies between [Wire] and `Splitter`
/// (§4.2: „an additional shell underneath it"): [Splitter] and
/// [OutsideRoute] serve either the naked wire (probes) or the
/// shell (operation), and neither of the two has to know which of the two
/// it currently has.
///
/// Its own file since S420: `wire.dart` is at its line budget; `wire.dart`
/// exports it, so every `import 'package:mycelium/wire.dart' show
/// PacketRoute` stays as it is.
abstract interface class PacketRoute {
  /// Sends [packet] to [target]:[targetPort]. See [Wire.send] — the
  /// return value says whether it was accepted, not whether it arrived.
  bool send(Uint8List packet, InternetAddress target, int targetPort);

  /// Calls [onPacket] for every arriving packet.
  void listen(
      void Function(Uint8List packet, InternetAddress from, int fromPort) onPacket);
}
