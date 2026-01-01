/// Which targets are impossible on the data path — and why this stands here.
///
/// ── WHY THIS IS A FILE OF ITS OWN ──────────────────────────────────────
///
/// `wire.dart` has set itself a limit: „if this file exceeds
/// 100 lines, something has got into it that does not belong here."
/// The classification of a target is knowledge about addresses, not about the
/// socket; it needs no socket, no state and no clock, and it
/// can be checked without a single packet. Over there is what happens to the
/// socket, here is which targets one never gives it.
///
/// ── WHAT WAS MEASURED (S389, 16.09.2026) ────────────────────────────────
///
/// Against real sockets, Dart 3.12.2 on linux_x64, per case a fresh
/// socket and afterwards a control sending to a real recipient:
///
/// | Target                                 | Error                       | Socket after  |
/// |----------------------------------------|-----------------------------|---------------|
/// | 255.255.255.255 without broadcast perm.| errno 13, asynchronous      | **dead**      |
/// | 192.168.10.255 without broadcast perm. | errno 13, asynchronous      | **dead**      |
/// | port 0                                 | errno 22, asynchronous      | **dead**      |
/// | payload 70000 B                        | errno 90, asynchronous      | **dead**      |
/// | 239.192.67.76 / 224.0.0.1 (group)      | none                        | alive         |
/// | 0.0.0.0 / 0.0.0.1                      | none                        | alive         |
///
/// „Dead" means: the socket can afterwards neither send nor RECEIVE, and it
/// does not recover (measured over 3.5 s). Not a single one of these errors
/// comes synchronously — a `try/catch` around `send` catches none of them.
///
/// ── WHAT WAS MEASURED FOR IPv6 (S390, 16.09.2026) ────────────────────────
///
/// The same construction, a socket on `anyIPv6`, witness on `[::1]`:
///
/// | Target                                 | Error                       | Socket after  |
/// |----------------------------------------|-----------------------------|---------------|
/// | `::1`                                  | none                        | alive         |
/// | `fe80::1` without and with zone id     | none                        | alive         |
/// | `ff02::1` without and with zone id     | none                        | alive         |
/// | `::` (unspecified)                     | none                        | alive         |
/// | `2001:db8::1` (no route there)         | **errno 101**, asynchronous | **dead**      |
/// | `2606:4700:4700::1111` (no route)      | **errno 101**, asynchronous | **dead**      |
/// | port 0                                 | errno 22, asynchronous      | **dead**      |
/// | payload 65527 B                        | none                        | alive         |
/// | payload 65528 B                        | errno 90, asynchronous      | **dead**      |
///
/// **errno 101 CANNOT be recognised from the address.** „No route there"
/// is a property of THIS machine at THIS point in time, not of the
/// address: the same bytes are an ordinary target on a host with global IPv6.
/// This file therefore cannot reject the case —
/// it is caught solely by the self-healing in `wire.dart`, and because there every
/// address type has its own socket, an unreachable IPv6 target does not
/// drag the IPv4 route down with it (measured S390, case F).
///
/// ── WHY MORE IS NEVERTHELESS REJECTED THAN IS DEADLY ────────────────
///
/// Group and unspecified address do not kill the socket on Linux.
/// They are rejected because on the data path they are nevertheless never a target:
/// §11.1 gives the node one data path for real packets — two
/// sockets, IPv4 and IPv6, on the same port number —, and the call in the
/// segment is the one exception with its own socket on port 41341
/// (§7.2). Sending a sealed packet to the group would mean presenting it to the
/// whole segment — and a packet to 0.0.0.0 or `::` goes back to
/// the own computer. Both can only be an error, and the
/// price of noticing it here is one comparison per packet.
///
/// What can NOT be recognised here: the broadcast of a segment
/// (192.168.10.255). For that one needs the netmask, and Dart does not
/// provide it (`NetworkInterface` knows only addresses). Exactly for that reason
/// a target check alone does not suffice — it is the first half, the
/// self-healing in `wire.dart` is the second.
library;

import 'dart:io';
import 'dart:typed_data';

/// Largest payload of a UDP packet over IPv4: 65535 minus IP header (20)
/// minus UDP header (8). Measured (S389 case M, S390 reproduced): 65507 B
/// go through, 65508 B yield errno 90 and close the socket.
const int kHighestPayloadIpv4 = 65507;

/// Largest payload of a UDP packet over IPv6: **65527**, not 65487.
///
/// The obvious computation „65535 minus IPv6 header (40) minus UDP header (8)"
/// would yield 65487 and is wrong: the length field of the IPv6 header counts only
/// what comes AFTER the header (RFC 8200 §3), so the header is not deducted from the
/// 65535. Measured on 16.09.2026 against real sockets: 65527 B go
/// through, 65528 B yield errno 90 and close the socket — exactly
/// 65535 − 8.
const int kHighestPayloadIpv6 = 65527;

/// `::ffff:a.b.c.d` → the four bytes behind it; everything else unchanged.
///
/// **Why this is needed at all.** A socket on `anyIPv6` on
/// Linux with `net.ipv6.bindv6only = 0` also accepts IPv4 traffic and presents
/// it in this form — 16 bytes, `type` = IPv6. Measured on 16.09.2026
/// with BOTH sockets on the same port number and in BOTH bind
/// orders: the IPv4 socket got the IPv4 traffic every time, so the form
/// never arrived above. **Two matching measurements are not a promise.**
/// Neither Dart nor Linux promise which of two sockets on one
/// port number gets the IPv4 traffic, `RawDatagramSocket.bind` knows
/// no `v6Only` switch, and on Windows the switch is by default
/// the other way round (unmeasured there, see report S390).
///
/// This function makes the question moot: whatever an
/// operating system presents above, the node sees the same address. Without it
/// a neighbour under `192.0.2.201:41341` and under
/// `::ffff:192.0.2.201:41341` would be two different keys (`shell.dart`,
/// `readiness.dart`, `post_box_deposit.dart`, `post_box_holder.dart`)
/// and would not even be remembered by `neighbourhood.dart`.
///
/// It applies in BOTH directions — a TARGET in this form is also
/// brought back this way so that it goes via the IPv4 socket. Throwing a v4-mapped target
/// via the IPv6 socket only succeeds as long as the host has the
/// switch set to 0; via the IPv4 socket it always succeeds.
InternetAddress asAddressKind(InternetAddress a) {
  final b = a.rawAddress;
  if (b.length != 16) return a;
  for (var i = 0; i < 10; i++) {
    if (b[i] != 0) return a;
  }
  if (b[10] != 0xFF || b[11] != 0xFF) return a;
  return InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12)));
}

/// Why [target]:[targetPort] with [payload] bytes does not work on the data path —
/// or `null` if nothing speaks against it.
///
/// The return value is the reason in plaintext, so that the caller can
/// REPORT it: a silently discarded packet would be exactly the silent failure
/// that this file is supposed to prevent.
///
/// [target] is first passed through [asAddressKind], so that a v4-mapped
/// target is checked by the same rules as the IPv4 behind it —
/// `::ffff:239.192.67.76` is the same group address as `239.192.67.76`.
String? impossibleTarget(InternetAddress target, int targetPort, int payload) {
  if (targetPort < 1 || targetPort > 0xFFFF) {
    return 'port $targetPort — nobody accepts anything on port 0, and the '
        'operating system closes the socket on it (errno 22)';
  }
  final r = asAddressKind(target).rawAddress;
  final cap =
      r.length == 4 ? kHighestPayloadIpv4 : kHighestPayloadIpv6;
  if (payload > cap) {
    return '$payload B payload — at most $cap B fit into a '
        'UDP packet of this address kind, above that the operating system closes '
        'the socket (errno 90)';
  }
  if (r.every((b) => b == 0)) {
    return '${target.address} — the unspecified address is not a neighbour';
  }
  if (r.length == 4) {
    if (r[0] >= 224 && r[0] <= 239) {
      return '${target.address} — a group address carries no post '
          '(§11.1: the call has its own socket)';
    }
    if (r.every((b) => b == 255)) {
      return '${target.address} — the broadcast carries no post, and without '
          'permission the operating system closes the socket on it (errno 13)';
    }
  } else if (r.isNotEmpty && r[0] == 0xFF) {
    return '${target.address} — a group address carries no post '
        '(§11.1: the call has its own socket)';
  }
  return null;
}
