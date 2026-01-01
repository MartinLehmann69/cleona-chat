/// One side of the wire (`wire.dart`): a socket, the address to which it is
/// bound, and the care for it — once per address type, one class so the
/// self-healing does not stand twice (a second copy is where one half is
/// repaired, not both). Out of `wire.dart` for its line budget (S427, when
/// both sides became optional: §11.1, owner 18.11.2026 — an address that is
/// present is used, where none is, socket and protocol stay off).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/link_io/native_send_path.dart';

import 'package:mycelium/wire_counters.dart';
import 'package:mycelium/wire_port.dart' show bindAgain;
import 'package:mycelium/wire_target.dart';

/// Packets processed per event-loop turn (§11.1 „Reading.": „processes
/// afterwards, in batches"). Between two batches the event loop runs once,
/// so the next read event drains the socket before more work is done.
/// Measured (S398 drain proposal, variant „drainturn", batches of 32): 0
/// re-request rounds for 367 parts between two processes.
const int kReceiveBatch = 32;

/// What a side needs of its wire — nothing else of it.
abstract class WireSideOwner {
  void sideSay(String what);
  WireCounters get counters;

  /// The wire is closed for good: nobody above takes packets any more.
  bool get closedForGood;

  /// Whether [s] is still this wire's side of its kind (not replaced, not given up).
  bool holds(WireSide s);
  void Function(Uint8List packet, InternetAddress from, int fromPort)? get packetTaker;

  /// [s] did not get its socket back, or gave it up: it drops away until the
  /// next network change (§11.1).
  void sideLost(WireSide s);
}

class WireSide {
  final WireSideOwner _d;
  final InternetAddress to;
  final String kind;
  RawDatagramSocket sock;
  bool _reopening = false; // [againOpen] in flight (S407)
  bool routeSeen = false; // a send to a global IPv6 was accepted on this network (S422)

  /// The native send path of this side — only on Windows, `null` elsewhere
  /// ([NativeSendPath.usesNativeSendPath]); receiving stays on [sock].
  NativeSendPath? native;

  /// Send failures, said once per series, each one counted (S420, S422).
  late final SendFailures failures = SendFailures(
      () => '$kind socket of port ${sock.port}', _d.sideSay, () => _d.counters.failed(kind));

  WireSide(this._d, this.to, this.kind, this.sock) {
    _nativeOpen();
  }

  void _nativeOpen() => native = NativeSendPath.tryOpen(
      port: sock.port, ipv6: kind == 'IPv6', log: _d.sideSay);

  void shut() {
    native?.close();
    native = null;
    sock.close();
  }

  /// Read, not yet processed. It lives on the side, not on the socket:
  /// [againOpen] replaces the socket and the queue carries on.
  final Queue<Datagram> _read = ListQueue();

  /// A batch is scheduled for the next event-loop turn.
  bool _batchDue = false;

  /// §11.1 „Reading.": at every read event the socket is read until
  /// empty, and only then processed — in batches of [kReceiveBatch], one
  /// batch per event-loop turn, and the socket is emptied again before
  /// every batch. Without that second read, 3 of 30 bursts of 367 parts
  /// still lost 10–42 parts in the kernel (S399 probe, two processes):
  /// read events queued behind a batch arrived too late. With it: 0 of 30.
  ///
  /// Until S399 one datagram per read event: a 367-part burst overran the
  /// 212 992-B kernel buffer, 100–144 dropped (`smoke_burst_loss`).
  ///
  /// Nothing is evicted and nothing is dropped: the queue is bounded by
  /// the flow of the senders (§11.3, §20.2). `Timer.run` is no clock —
  /// it yields the event loop once and is scheduled only while the queue
  /// is not empty.
  void subscribe() {
    final s = sock; // an error of a replaced socket reopens nothing (S407)
    s.listen((e) {
      if (e == RawSocketEvent.read) {
        _drain();
        _schedule();
      } else if (e != RawSocketEvent.write) {
        closedUnder(s, '$e');
      }
    }, onError: (Object e) => identical(s, sock) ? error(e) : null,
        onDone: () => closedUnder(s, 'end of its events'));
  }

  /// §31.3: a socket the operating system closed WITHOUT an error is dead the
  /// same way (field 11.11./12.11.2026, S422: an iPhone's data port silent, no
  /// error line). Our own closes pass: a reopen is under way, the wire is
  /// closed, the socket was replaced, or the side was given up.
  void closedUnder(RawDatagramSocket s, String how) {
    if (!identical(s, sock) || _reopening || _d.closedForGood) return;
    if (!_d.holds(this)) return;
    _d.sideSay('wire: the operating system closed the $kind socket of port '
        '${sock.port} without an error ($how) — opened again (§31.3)');
    againOpen();
  }

  /// Reads [sock] until `receive()` returns nothing. On a socket that
  /// [againOpen] has just closed `receive()` returns null.
  void _drain() {
    for (var g = sock.receive(); g != null; g = sock.receive()) {
      _d.counters.received(g.data.length);
      _read.add(g);
    }
  }

  void _schedule() {
    if (_batchDue || _read.isEmpty) return;
    _batchDue = true;
    Timer.run(_batch);
  }

  void _batch() {
    _batchDue = false;
    // The wire is closed for good: nobody above takes packets any more.
    if (_d.closedForGood) return _read.clear();
    _drain();
    try {
      for (var i = 0; i < kReceiveBatch && _read.isNotEmpty; i++) {
        final g = _read.removeFirst();
        // [asAddressKind]: what comes in as `::ffff:a.b.c.d` goes up as the
        // four bytes behind it. As measured, the IPv4 socket got the
        // IPv4 traffic, so the form never occurred — that is not promised,
        // and above it the neighbour list and four address keys depend on it.
        _d.packetTaker
            ?.call(Uint8List.fromList(g.data), asAddressKind(g.address), g.port);
      }
    } finally {
      // A throwing handler above must not leave the rest of the queue
      // waiting for the next read event.
      _schedule();
    }
  }

  /// The operating system's error for an earlier send. Dart closes the socket
  /// on every error it reports (SDK `socket_patch.dart` `reportError`: "For all
  /// errors we close the socket") — hence dead (S389), hence reopened. Except
  /// "no route" ([noRoute]) on the IPv6 side before [routeSeen]: this network
  /// has no way out over IPv6, a fresh socket meets the same (S422, §11.1).
  void error(Object e) {
    if (kind == 'IPv6' && noRoute(e) && !routeSeen) {
      if (_reopening || !_d.holds(this)) return; // once per burst
      _d.sideSay('wire: no route for IPv6 ($e) — the IPv6 socket of port '
          '${sock.port} stays closed until the next network change (§11.1)');
      shut();
      return _d.sideLost(this);
    }
    // `sock.port` still names the old number even on the dead socket
    // (measured S389) — exactly the one that is about to be bound anew.
    _d.sideSay('wire: send error from the operating system ($e) — the $kind socket '
        'is dead with that, port ${sock.port} is opened again');
    againOpen();
  }

  /// Reopen the SAME port (it is the node's address, §11.1, every card names
  /// it); after `close()` it binds again at once (measured S390, case E).
  /// One error burst reopens ONCE: the OS reports two errors per dead socket,
  /// and two concurrent reopens left one socket open, unread (S407: 35).
  /// Returns whether THIS call bound a fresh socket (`false` also while
  /// another reopen is under way — that one binds). A side that cannot get
  /// its port back drops away until the next network change — IPv4 the same
  /// as IPv6 (S427: both kinds are equal, §11.1).
  Future<bool> againOpen() async {
    if (_d.closedForGood || _reopening) return false;
    _reopening = true;
    final old = sock.port;
    shut();
    try {
      sock = await bindAgain(() => RawDatagramSocket.bind(to, old)); // §31.3
    } on Object catch (e) {
      _d.sideSay('Wire: port $old cannot be had again for $kind ($e) — this '
          'node continues without $kind until the next network change (§11.1).');
      _d.sideLost(this);
      return false;
    } finally {
      _reopening = false;
    }
    if (_d.closedForGood) sock.close();
    if (_d.closedForGood) return false;
    _nativeOpen();
    subscribe();
    _d.sideSay('wire: port $old open again ($kind).');
    return true;
  }
}
