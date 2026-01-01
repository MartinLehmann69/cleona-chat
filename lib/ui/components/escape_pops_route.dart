// Escape closes the topmost page (owner decision 1A, S405, 06.10.2026).
//
// WHY AN OWN INTENT
// -----------------
// `WidgetsApp.defaultShortcuts` maps Escape to `DismissIntent`. Flutter wraps
// EVERY modal route in `Actions({DismissIntent: _DismissModalAction})`
// (`widgets/routes.dart`), and that action is enabled only when
// `route.barrierDismissible` is true — false for every `PageRoute`. The
// shortcut manager takes the NEAREST action for the intent and calls it only
// when enabled, so a root `DismissIntent` action is never reached while a page
// is shown: Escape did nothing on a page (finding R-2,
// `mycelium/berichte/S405-RCA-B1-B2.md`).
//
// With an own intent the route-level `DismissIntent` action is not in the
// lookup path, the root action below is reached, and it decides:
//   * topmost route is a page  -> `maybePop()` (respects `PopScope`); the
//     first page is left alone (no refused-pop callback on the home screen);
//   * any other route (dialog, popup, bottom sheet) -> the route's own
//     `DismissIntent` is invoked from the focus, exactly what Flutter did
//     before: a dialog with `barrierDismissible: false` stays open.
// Widgets with their own Escape shortcut (menus, dropdowns) sit closer to the
// focus and keep handling Escape themselves.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intent bound to Escape at the application root.
class PopRouteIntent extends Intent {
  const PopRouteIntent();
}

/// Shortcut map for `MaterialApp.shortcuts`: Flutter's defaults with Escape
/// re-bound to [PopRouteIntent].
Map<ShortcutActivator, Intent> escapePopsRouteShortcuts() =>
    <ShortcutActivator, Intent>{
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.escape): const PopRouteIntent(),
    };

/// Action map for `MaterialApp.actions`: Flutter's defaults plus the action
/// for [PopRouteIntent]. [navigator] is read at invoke time, because the
/// application replaces its navigator key when it switches to the home screen.
Map<Type, Action<Intent>> escapePopsRouteActions(
        NavigatorState? Function() navigator) =>
    <Type, Action<Intent>>{
      ...WidgetsApp.defaultActions,
      PopRouteIntent: PopRouteAction(navigator),
    };

/// Closes the topmost page, or hands Escape to the topmost non-page route.
class PopRouteAction extends Action<PopRouteIntent> {
  PopRouteAction(this.navigator);

  final NavigatorState? Function() navigator;

  @override
  Object? invoke(PopRouteIntent intent) {
    final nav = navigator();
    if (nav == null) return null;
    final top = _topRoute(nav);
    if (top == null || top is PageRoute) {
      // The first page is never popped by Escape. `maybePop` would still
      // report a refused pop to its `PopScope` — the home screen answers
      // that on Android with `SystemNavigator.pop()` (closes the app), which
      // is the Back button's job, not Escape's. A first page with local
      // history (e.g. a search field in the app bar) still closes that.
      if (top != null && top.isFirst && !top.willHandlePopInternally) {
        return null;
      }
      nav.maybePop();
      return null;
    }
    // Dialog, popup or sheet: let its own dismiss action decide (enabled only
    // when the route is barrier-dismissible).
    final focusContext = primaryFocus?.context;
    if (focusContext != null) {
      Actions.maybeInvoke<DismissIntent>(focusContext, const DismissIntent());
    }
    return null;
  }

  /// The topmost route of [nav]. `popUntil` with a predicate that is true at
  /// once visits only the top route and pops nothing.
  static Route<dynamic>? _topRoute(NavigatorState nav) {
    Route<dynamic>? top;
    nav.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }
}
