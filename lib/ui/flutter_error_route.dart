// Where a report of the Flutter framework goes (S420, finding N2-1C04).
//
// The window's `FlutterError.onError` (lib/main.dart) hands every report
// here. Every report is written to `crash.log` as before. The crash popup of
// §16.7 opens for every report with a stack — except for ONE class: an error
// a platform channel answered to a call the framework itself made, and which
// the framework caught and only reported. The app keeps running after it;
// the popup is modal and would take the keyboard from the user in the middle
// of typing (S420: on Windows `TextInput.setEditingState` without a client,
// the rest of the message and Enter went into the popup). That class is
// offered later, once no text field holds the focus ([DeferredCrashOffer]).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'focus_trace.dart';

/// The `library` the framework names in the reports of its services layer
/// (Flutter 3.44.6, packages/flutter/lib/src/services/): `_reportError` in
/// text_input.dart, used by every call of the platform text input control
/// (`_PlatformTextInputControl`); the platform stream of an event channel
/// (`EventChannel.receiveBroadcastStream` in platform_channel.dart);
/// `SystemChrome.setSystemUIOverlayStyle` in system_chrome.dart;
/// `UndoManager` in undo_manager.dart; and the platform message callbacks
/// (`_DefaultBinaryMessenger` in binding.dart). Line numbers are in
/// `mycelium/berichte/S420-BAU-CRASHDIAG.md`.
const String kFrameworkServicesLibrary = 'services library';

/// Whether [details] is a [PlatformException] the framework caught itself
/// and only reported: the framework's own call on a platform channel came
/// back with an error envelope (`decodeEnvelope` of `JSONMethodCodec` and
/// `StandardMethodCodec` in message_codecs.dart throws it), and the services
/// layer reported it under [kFrameworkServicesLibrary] instead of letting it
/// escape. Everything else — an error while building, painting or handling
/// input, an assertion of the services layer, a `PlatformException` the app's
/// own code let escape (that one reaches `PlatformDispatcher.onError`, not
/// this handler) — is not this class.
bool isCaughtPlatformChannelError(FlutterErrorDetails details) =>
    details.library == kFrameworkServicesLibrary &&
    details.exception is PlatformException;

/// What the framework says it was doing, e.g. "while setting text input
/// editing state". Only the context line — never the information collector,
/// which for an incoming text input call carries the method call and with it
/// the text (`_loudlyHandleTextInputInvocation` in text_input.dart).
String caughtErrorContext(FlutterErrorDetails details) {
  String context;
  try {
    context = details.context?.toDescription() ?? '-';
  } catch (_) {
    context = '-';
  }
  return '${details.library ?? '-'}, $context';
}

/// The window's handling of one framework report.
///
/// [logCrash] writes the entry into `crash.log` (`_logCrash` of main.dart);
/// [openCrashPopup] is `handleCrash` of the app state, which saves the state
/// and offers the report in the opt-in popup (§16.7); [note] is the GUI log
/// line of the desktop window (null elsewhere), [focus] names the primary
/// focus at the moment of the report. [deferCrashPopup] takes a report of
/// the caught class instead of [openCrashPopup] — [DeferredCrashOffer.defer]:
/// the popup comes later, when no text field holds the focus.
void routeFlutterError(
  FlutterErrorDetails details, {
  required void Function(String source, Object error, StackTrace? stack)
      logCrash,
  required void Function(Object error, StackTrace stack)? openCrashPopup,
  void Function(Object error, StackTrace stack)? deferCrashPopup,
  void Function(String line)? note,
  String Function()? focus,
}) {
  if (isCaughtPlatformChannelError(details)) {
    final where = caughtErrorContext(details);
    logCrash('FlutterError caught by the framework: $where',
        details.exception, details.stack);
    final stack = details.stack;
    final deferred = stack != null && deferCrashPopup != null;
    if (note != null) {
      final e = details.exception as PlatformException;
      note('platform channel error caught by the framework ($where): '
          'code "${e.code}", message "${e.message ?? '-'}"; primary focus '
          '${focus?.call() ?? '-'}; written to crash.log, '
          '${deferred ? 'crash popup deferred until no text field has the focus' : 'no crash popup'}');
    }
    if (deferred) deferCrashPopup(details.exception, stack);
    return;
  }
  logCrash('FlutterError', details.exception, details.stack);
  final stack = details.stack;
  if (stack != null) openCrashPopup?.call(details.exception, stack);
}

/// The [note] sink with its own budget, so that a channel that refuses every
/// keystroke does not flood the log.
void Function(String line) budgetedNote(
    void Function(String line) write, {LineBudget? budget}) {
  final b = budget ?? LineBudget(maxLines: 10);
  return (line) {
    final prefix = b.admit();
    if (prefix != null) write('$prefix$line');
  };
}

/// Holds a caught platform channel error (owner decision 11.11.2026,
/// variant B) and offers it as an ordinary crash report — the opt-in popup
/// with its preview (§16.7), nothing is sent on its own — once no text field
/// holds the primary focus.
///
/// * Triggered by a change of the primary focus only: no timer, no polling.
///   [defer] itself never offers — the error typically arises while the
///   focus moves into or out of a text field, and the next keystroke may
///   already be on its way.
/// * The offer needs the window in the foreground ([AppLifecycleState.
///   resumed]): a window that loses the foreground moves the focus to the
///   root scope, and a popup scheduled then would meet the user on return,
///   when the focus is given back to the text field
///   (`FocusManager._appLifecycleChange`).
/// * [canOffer] is the caller's own condition (the app state: a place to send
///   the report to exists); while it is false the error waits for the next
///   focus change.
/// * Several errors of the class before the offer become ONE offer: the
///   first one is kept, the others are counted in the log line.
class DeferredCrashOffer {
  DeferredCrashOffer({
    required this.offer,
    bool Function()? canOffer,
    bool Function()? textFieldFocused,
    bool Function()? inForeground,
    this.note,
  })  : _canOffer = canOffer ?? _always,
        _textFieldFocused = textFieldFocused ??
            (() => isTextFieldNode(FocusManager.instance.primaryFocus)),
        _inForeground = inForeground ?? _resumed;

  /// `handleCrash` of the app state: the existing crash path to the popup.
  final void Function(Object error, StackTrace stack) offer;
  final bool Function() _canOffer;
  final bool Function() _textFieldFocused;
  final bool Function() _inForeground;
  final void Function(String line)? note;

  (Object, StackTrace)? _held;
  int _count = 0;
  bool _installed = false;

  static bool _always() => true;

  /// Unknown counts as foreground: the binding reports the state only after
  /// the platform's first message.
  static bool _resumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Whether an error is held for an offer.
  bool get holding => _held != null;

  void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance.addListener(focusChanged);
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    FocusManager.instance.removeListener(focusChanged);
  }

  void defer(Object error, StackTrace stack) {
    _held ??= (error, stack);
    _count++;
  }

  /// The listener on [FocusManager]; public for the smoke.
  void focusChanged() {
    final held = _held;
    if (held == null) return;
    if (_textFieldFocused() || !_inForeground() || !_canOffer()) return;
    final n = _count;
    _held = null;
    _count = 0;
    note?.call('caught platform channel error offered as crash report '
        '($n held, one offer), no text field has the focus');
    offer(held.$1, held.$2);
  }
}
