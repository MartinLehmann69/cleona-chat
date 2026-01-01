import 'package:mycelium/card.dart';
import 'package:mycelium/ladder.dart' show LadderStep;

/// Which route last carried per counterpart — the memory of the
/// ladder that does not belong to the ladder.
///
/// Its own file because it is its own thing: `ladder.dart` decides
/// WHICH steps a sending takes, and only looks up here which one carried the
/// last time. It is exported via `ladder.dart`
/// (`export`), so that no caller needs two imports.

/// After this many failed attempts in a row a remembered route is
/// discarded. Two, because a single packet loss should not devalue an
/// address.
const int kFailedAttemptsUntilDropped = 2;

/// A route that has proven itself.
class Route {
  final LadderStep step;

  /// Where to — for the post box null, it goes to the own neighbours.
  final CardAddress? destination;

  int failedAttempts;

  Route(this.step, this.destination, {this.failedAttempts = 0});

  @override
  String toString() => '${step.name}${destination == null ? "" : " an $destination"}';
}

/// Which route last carried per counterpart.
///
/// Without it every message starts all four steps again, although for
/// weeks the same one has been carrying. The caller holds this memory and stores
/// it with the contacts; the ladder only reads it.
class RouteMemory {
  final Map<String, Route> _routes = {};

  /// [identifier] is the designator of the counterpart — what the caller
  /// uses for it is left to him.
  Route? forField(String identifier) => _routes[identifier];

  void remember(String identifier, LadderStep step, CardAddress? destination) {
    _routes[identifier] = Route(step, destination);
  }

  /// The remembered route has not carried. After
  /// [kFailedAttemptsUntilDropped] times it is discarded.
  void failed(String identifier) {
    final w = _routes[identifier];
    if (w == null) return;
    w.failedAttempts++;
    if (w.failedAttempts >= kFailedAttemptsUntilDropped) _routes.remove(identifier);
  }

  void forget(String identifier) => _routes.remove(identifier);

  int get count => _routes.length;
}
