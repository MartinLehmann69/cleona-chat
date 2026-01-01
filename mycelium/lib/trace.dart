/// Diagnosis of delivery (S405, owner approval 06.10.2026, proposal D:
/// "where which data arrives, or why not"; cut back in S406, owner
/// decision 07.10.2026 "A": nothing per datagram or per packet on the
/// transport path — socket, link and splitter write no TRACE line).
///
/// Every line starts with `TRACE <layer>` so one grep follows a packet:
///
/// | layer | where | what |
/// |---|---|---|
/// | `shell` | `shell.dart` | a handshake started, a link set up (events, not datagrams) |
/// | `split` | `split.dart` | a transmission failed and was dropped |
/// | `assign` | `node_helpers.dart` | a first-contact packet arriving: origin, direct/forwarded/collected, who takes it or why nobody |
/// | `ladder` | `ladder.dart` | each step of a sending with its target, delivered, given up |
/// | `step3` | `CodeRoute.recording` | `0x20`–`0x25` in/out with code, hop count, next addresses, inner packet |
/// | `card`, `seat` | `trace_first_contact.dart`, `host_network.dart` | a card field by field when issued and when read; who holds which seat and why the card names no neighbour |
/// | `contact` | `memory.dart` | every change of a contact's last observed address |
///
/// THE PACKET ID: the first 4 B of SHA-256 over the whole packet ([packetId]).
/// A forwarded packet keeps it (the inner packet is the same bytes), so the
/// same id shows up at sender, forwarder and recipient.
///
/// No content of a message is ever written — only kinds, lengths, ids and
/// code prefixes; addresses go through the log redaction of the app like
/// every other line. No packet is sent and nothing is decided here: every
/// function reads and writes a line.
///
/// On in the beta network (lab and test phones), off in the live network
/// ([traceOn]).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/config/network_channel.dart'
    show NetworkChannel, activeNetworkChannel;
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/forward_detour.dart' show detourRead;
import 'package:mycelium/kinds.dart' as kinds;

/// What every diagnosis line starts with. The app's start paths hand such
/// lines to the TRACE level of their logger (`hostStart`, S406).
const String kTraceLinePrefix = 'TRACE ';

/// Whether the diagnosis writes (beta network only).
bool get traceOn => _forced ?? activeNetworkChannel == NetworkChannel.beta;
bool? _forced;

/// Tests switch it explicitly.
set traceForced(bool? on) => _forced = on;

/// The process-wide sink for layers that hold no node (`memory.dart`). Set
/// by the node that starts ([traceSinkSet]); with several nodes in one
/// process (smokes) the last one started gets these lines.
void Function(String)? _sink;
void traceSinkSet(void Function(String) report) => _sink = report;

/// A line for the process-wide sink.
void traceNote(String line) {
  if (traceOn) _sink?.call('TRACE $line');
}

/// The first 4 B of SHA-256 over [p], hex — the id of a whole packet.
String packetId(Uint8List p) => _hex(SodiumFFI().sha256(p), 4);

/// The first 4 B of [b] as hex — the prefix every code line uses.
String hexShort(Uint8List b) => _hex(b, 4);

String _hex(Uint8List b, [int n = 0]) =>
    (n == 0 || n > b.length ? b : b.sublist(0, n))
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();

/// The kind byte as `0xNN name`.
String kindName(int k) => '0x${k.toRadixString(16).padLeft(2, '0')} '
    '${_names[k] ?? "?"}';

const Map<int, String> _names = {
  kinds.kBundlePlea: 'bundle-plea', kinds.kBundle: 'bundle',
  kinds.kRequest: 'request', kinds.kAnswer: 'answer',
  kinds.kReceiptFirstContact: 'receipt-fc', kinds.kMessage: 'message',
  kinds.kDeliveryReceipt: 'delivery-receipt', kinds.kReaction: 'reaction',
  kinds.kEdit: 'edit', kinds.kReadMark: 'read-mark', kinds.kDayKey: 'day-key',
  kinds.kForward: 'forward', kinds.kUnknownCode: 'unknown-code',
  kinds.kDetour: 'detour', kinds.kWhereAreYou: 'where-are-you',
  kinds.kRegistration: 'registration', kinds.kRegistered: 'registered',
  kinds.kDeposit: 'deposit', kinds.kDeposited: 'deposited',
  kinds.kCollect: 'collect', kinds.kHereItIs: 'here-it-is',
  kinds.kNothingThere: 'nothing-there', kinds.kCollectTask: 'collect-task',
  kinds.kCollectProof: 'collect-proof', kinds.kRefused: 'refused',
  kinds.kWhatIsMyAddress: 'what-is-my-address',
  kinds.kYourAddressIs: 'your-address-is', kinds.kKnock: 'knock',
  kinds.kMediaAnnouncement: 'media-announcement',
  kinds.kMediaPiece: 'media-piece', kinds.kGroupsMessage: 'group-message',
  kinds.kKeyDelivery: 'key-delivery',
};

/// A whole packet in one phrase: id, kind, length — and for a step-3
/// packet its code and inner packet ([step3Describe]).
String packetDescribe(Uint8List p) {
  if (p.isEmpty) return 'empty';
  final base = '${packetId(p)} ${kindName(p[0])} ${p.length} B';
  final s3 = kinds.isForward(p[0]) ? step3Describe(p) : '';
  return s3.isEmpty ? base : '$base $s3';
}

/// `0x20`/`0x23`: hop count, code, inner packet; `0x21`: code; `0x22`: next
/// addresses and the inner `0x20`. Unreadable says so.
String step3Describe(Uint8List p) {
  try {
    switch (p[0]) {
      case kinds.kForward:
      case kinds.kWhereAreYou:
        if (p.length < 18) return '(short)';
        final inner = Uint8List.sublistView(p, 18);
        return 'hop ${p[1]} code ${_hex(Uint8List.sublistView(p, 2, 18), 4)}'
            '${p[0] == kinds.kForward && inner.isNotEmpty ? " inner ${packetId(inner)} ${kindName(inner[0])} ${inner.length} B" : ""}';
      case kinds.kUnknownCode:
        return p.length < 17 ? '(short)' : 'code ${_hex(Uint8List.sublistView(p, 1, 17), 4)}';
      case kinds.kDetour:
        final d = detourRead(p);
        return 'hop ${d.hopCount} next ${d.next.join(", ")} inner '
            '${packetDescribe(d.inner)}';
      default:
        return '';
    }
  } on Object catch (e) {
    return '(unreadable: $e)';
  }
}

/// `split.dart`: the transmission [identifier] failed with [got] of [count].
void traceSplitFailed(void Function(String) say, Uint8List identifier, int got, int count,
    InternetAddress from, int port) {
  if (!traceOn) return;
  say('TRACE split in from ${from.address}:$port transmission ${_hex(identifier, 4)} '
      'FAILED: $got of $count part(s) arrived — dropped (§11.3)');
}
