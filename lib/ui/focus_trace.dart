// Focus trace of the window (S420, finding N2-1C04).
//
// WHY THIS EXISTS
//
// On Windows the engine answered `TextInput.setEditingState` with
// "Set editing state has been invoked, but no client is set." while a test
// typed into the chat field. The embedder clears its client only on
// `TextInput.clearClient`, which the framework sends when a text field loses
// the primary focus. Which focus change came first could not be decided from
// the logs: the window logged no focus change at all. This file logs exactly
// that — the kind of the node that holds the primary focus, never a text.
//
// WHY NOT THE TEXT INPUT CHANNEL ITSELF
//
// The outgoing calls on `flutter/textinput` cannot be observed without
// changing what the framework sends (Flutter 3.44.6,
// packages/flutter/lib/src/services/text_input.dart; line numbers in
// `mycelium/berichte/S420-BAU-CRASHDIAG.md`):
//   * `TextInput.setChannel` only takes effect with asserts enabled — never
//     in a release build;
//   * an observing `TextInputControl` installed with
//     `TextInput.setInputControl` becomes the CURRENT control, and the
//     platform control then sends `inputType: none` to the engine
//     (`_PlatformTextInputControl._configurationToJson`) — the on-screen
//     keyboard and the input method would change;
//   * wrapping the binary messenger means replacing the app's binding
//     (`ServicesBinding.createBinaryMessenger`) for every platform message.
// What the framework does report — a failed call on the channel, with the
// method in its context — is logged by `flutter_error_route.dart` together
// with the focus at that moment.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// At most [maxLines] lines per [window]; what is cut is counted and named
/// with the next line that is let through. No timer: nothing is written
/// while nothing happens.
class LineBudget {
  LineBudget({
    required this.maxLines,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxLines;
  final Duration window;
  final DateTime Function() _clock;

  DateTime? _windowStart;
  int _used = 0;
  int _cut = 0;

  /// Null when the line must be dropped; otherwise the prefix to put in
  /// front of it (empty, or the count of lines cut before it).
  String? admit() {
    final now = _clock();
    final start = _windowStart;
    if (start == null || now.difference(start) >= window) {
      _windowStart = now;
      _used = 0;
    }
    if (_used >= maxLines) {
      _cut++;
      return null;
    }
    _used++;
    if (_cut == 0) return '';
    final prefix = '($_cut earlier lines not logged) ';
    _cut = 0;
    return prefix;
  }
}

/// The kind of [node] without any content: `none`, `root scope`,
/// `text field`, `scope` or `node`, a short identity to tell nodes apart,
/// and the debug label where the build keeps one (debug builds only, see
/// `FocusNode.debugLabel`).
String describeFocusNode(FocusNode? node) {
  if (node == null) return 'none';
  final id = (identityHashCode(node) & 0xffffff).toRadixString(16);
  final String kind;
  if (identical(node, FocusManager.instance.rootScope)) {
    kind = 'root scope';
  } else if (isTextFieldNode(node)) {
    kind = 'text field';
  } else if (node is FocusScopeNode) {
    kind = 'scope';
  } else {
    kind = 'node';
  }
  final label = node.debugLabel;
  return label == null ? '$kind #$id' : '$kind #$id "$label"';
}

/// Whether [node] is the focus node of an [EditableText]: its `Focus`
/// widget lies inside the EditableText's state (`EditableTextState.build`
/// wraps its content in `Focus(focusNode: widget.focusNode)`).
bool isTextFieldNode(FocusNode? node) {
  if (node == null) return false;
  final context = node.context;
  if (context == null || !context.mounted) return false;
  try {
    return context.findAncestorStateOfType<EditableTextState>() != null;
  } catch (_) {
    // An element in the middle of being deactivated refuses the lookup in
    // debug builds; the kind is then simply not a text field.
    return false;
  }
}

/// One line per change of the primary focus, at most [budget] lines per
/// minute. The window's lifecycle state is named with it, because a window
/// that loses the foreground moves the primary focus to the root scope
/// (`FocusManager._appLifecycleChange`).
class FocusTrace {
  FocusTrace(this._write, {LineBudget? budget})
      : _budget = budget ?? LineBudget(maxLines: 30);

  final void Function(String line) _write;
  final LineBudget _budget;
  FocusNode? _last;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _last = FocusManager.instance.primaryFocus;
    FocusManager.instance.addListener(_onChange);
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FocusManager.instance.removeListener(_onChange);
  }

  void _onChange() {
    final now = FocusManager.instance.primaryFocus;
    if (identical(now, _last)) return;
    final before = _last;
    _last = now;
    final prefix = _budget.admit();
    if (prefix == null) return;
    final lifecycle =
        WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';
    _write('${prefix}focus ${describeFocusNode(before)} -> '
        '${describeFocusNode(now)} (lifecycle $lifecycle)');
  }
}

/// S425 N4-3 measurement (00w.05: field 14 had the focus, the engine said
/// "no client is set", the word never stood there): one line per key press
/// that reaches the window — the kind of event and the focus node, NEVER
/// the key or a character. Beta builds only (the caller decides), at most
/// [budget] lines per minute. Observes only: the handler never consumes.
class KeyTrace {
  KeyTrace(this._write, {LineBudget? budget})
      : _budget = budget ?? LineBudget(maxLines: 300);

  final void Function(String line) _write;
  final LineBudget _budget;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final prefix = _budget.admit();
    if (prefix != null) {
      _write('${prefix}key down -> '
          '${describeFocusNode(FocusManager.instance.primaryFocus)}');
    }
    return false;
  }
}
