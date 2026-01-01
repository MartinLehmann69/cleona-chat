import 'dart:async';

/// Who is typing right now, as the received typing indicators say.
///
/// An indicator counts for [window] after its arrival, and its END is
/// announced by itself (S405 A-3): until S405 the window was only applied
/// when a state snapshot was built, and after the last indicator nothing
/// built one — the desktop GUI showed "tippt…" until some unrelated event
/// came (lab 05.10.2026: 16 s and > 30 s). One one-shot timer per typing
/// contact; it exists only while somebody types, so idle costs nothing
/// (working rule 5). Out of `cleona_service.dart` so that the expiry can be
/// tested on its own (`smoke_typing_expiry`).
class TypingTracker {
  /// How long one received indicator counts.
  final Duration window;

  /// Called when the set of typing contacts changed — also at the end of a
  /// window.
  final void Function() onChanged;

  final DateTime Function() _now;
  final Map<String, DateTime> _since = {};
  final Map<String, Timer> _ends = {};

  TypingTracker({
    required this.onChanged,
    this.window = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// A typing indicator of [sender] arrived.
  void note(String sender, {required bool typing}) {
    _ends.remove(sender)?.cancel();
    if (typing) {
      _since[sender] = _now();
      _ends[sender] = Timer(window, () {
        _ends.remove(sender);
        if (_since.remove(sender) != null) onChanged();
      });
    } else {
      _since.remove(sender);
    }
    onChanged();
  }

  bool isTyping(String sender) {
    final t = _since[sender];
    return t != null && _now().difference(t) < window;
  }

  /// The contacts typing now.
  List<String> get typingNow =>
      [for (final e in _since.entries) if (_now().difference(e.value) < window) e.key];

  /// The service stops: no timer outlives it.
  void close() {
    for (final t in _ends.values) {
      t.cancel();
    }
    _ends.clear();
    _since.clear();
  }
}
