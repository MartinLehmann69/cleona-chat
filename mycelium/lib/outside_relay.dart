/// The wire to a relay (V4.2 §11.9) — ONE WebSocket per operation, then
/// closed again.
///
/// Deliberately without connection pool, without retry and without clock. A
/// node reads at most at the edges „sources 1–3 without neighbours" (start,
/// network change) and writes at most once per address change
/// (`host_outside.dart`). A connection kept open would be traffic without
/// cause (work rule 5).
///
/// The messages are the subset of NIP-01
/// (https://github.com/nostr-protocol/nips/blob/master/01.md) that is
/// needed: `["REQ", <sub>, <filter>]` → `["EVENT", <sub>, <ereignis>]`… and
/// `["EOSE", <sub>]` (or `["CLOSED", <sub>, …]`), then `["CLOSE", <sub>]`;
/// `["EVENT", <ereignis>]` → `["OK", <id>, true|false, <text>]`.
///
/// Deadlines: 10 s for setup, 10 s for the answer — the same values as
/// `kRelayConnectTimeout`/`kRelayResponseTimeout` in
/// `lib/core/rendezvous/nostr_provider.dart`. Both END an operation;
/// neither repeats it.
///
/// `wss://` and `ws://` are both accepted. The content is public
/// (an address entry that everyone is supposed to read); what an unencrypted
/// connection additionally reveals is only that this computer asks a
/// relay for the keyword — the same statement an observer sees
/// with `wss://` from the name of the relay. The app configuration
/// (`RendezvousRelays`) lets only `wss://` through anyway.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration kRelaySetup = Duration(seconds: 10);
const Duration kRelayAnswer = Duration(seconds: 10);

var _subscription = 0;

/// Fetches the events for [filter] from [uri]. Empty if the relay cannot be
/// reached or does not answer — a relay without answer is
/// one without content. Does not throw.
Future<List<Map<String, dynamic>>> entriesFetch(
    String uri, Map<String, dynamic> filter,
    {void Function(String)? report}) async {
  final out = <Map<String, dynamic>>[];
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(uri).timeout(kRelaySetup);
    final sub = 'mycelium${_subscription++}';
    final done = Completer<void>();
    void end() {
      if (!done.isCompleted) done.complete();
    }

    ws.listen((d) {
      try {
        final m = jsonDecode('$d') as List<dynamic>;
        if (m.length >= 3 && m[0] == 'EVENT' && m[1] == sub) {
          out.add((m[2] as Map).cast<String, dynamic>());
        } else if (m.length >= 2 &&
            (m[0] == 'EOSE' || m[0] == 'CLOSED') &&
            m[1] == sub) {
          end();
        }
      } on Object {
        // An unreadable line of a relay is not an answer.
      }
    }, onDone: end, onError: (Object _) => end());
    ws.add(jsonEncode(['REQ', sub, filter]));
    await done.future.timeout(kRelayAnswer, onTimeout: () {
      report?.call('Relay $uri: no complete answer in '
          '${kRelayAnswer.inSeconds} s — ${out.length} event(s)');
    });
    try {
      ws.add(jsonEncode(['CLOSE', sub]));
    } on Object {
      // already closed
    }
  } on Object catch (e) {
    report?.call('Relay $uri not readable: $e');
  } finally {
    await _to(ws);
  }
  return out;
}

/// Deposits [event] at [uri]. `true` only on `["OK", <id>, true, …]`.
/// Does not throw.
Future<bool> entryDeposit(String uri, Map<String, dynamic> event,
    {void Function(String)? report}) async {
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(uri).timeout(kRelaySetup);
    final ok = Completer<bool>();
    void end(bool yes) {
      if (!ok.isCompleted) ok.complete(yes);
    }

    ws.listen((d) {
      try {
        final m = jsonDecode('$d') as List<dynamic>;
        if (m.length >= 3 && m[0] == 'OK' && m[1] == event['id']) {
          end(m[2] == true);
          if (m[2] != true) {
            report?.call('relay $uri refuses: ${m.length > 3 ? m[3] : ''}');
          }
        }
      } on Object {
        // unreadable — no answer
      }
    }, onDone: () => end(false), onError: (Object _) => end(false));
    ws.add(jsonEncode(['EVENT', event]));
    return await ok.future.timeout(kRelayAnswer, onTimeout: () => false);
  } on Object catch (e) {
    report?.call('Relay $uri not writable: $e');
    return false;
  } finally {
    await _to(ws);
  }
}

Future<void> _to(WebSocket? ws) async {
  if (ws == null) return;
  try {
    await ws.close().timeout(const Duration(seconds: 1));
  } on Object {
    // A relay that does not acknowledge the farewell holds nothing up.
  }
}
