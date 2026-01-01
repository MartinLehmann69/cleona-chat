// Message-boundary navigation for the chat list (docs/UI.md
// "Chat-Scroll-Navigation"): the up/down buttons put exactly the previous or
// next message edge at the leading edge of the viewport — measured on the
// built items, never estimated from an average item height.
//
// Every list item is wrapped in a [MessageBoundaryAnchor]. A boundary is the
// leading or trailing edge of a built item, in scroll offset of the list's
// own [ScrollPosition] (`RenderAbstractViewport.getOffsetToReveal`, so list
// padding, date separators inside an item and `reverse` lists are covered by
// the viewport itself).
//
// Why the built items are enough: "next" from the leading edge `r` is at the
// latest the trailing edge of the item that covers `r`, and that item is
// always built. "Previous" is at the earliest the leading edge of the item
// directly before it; its trailing edge touches `r`, so it lies in the
// sliver's cache extent and is built too. Only with no cache extent can it be
// missing — then [step] moves one viewport towards it, lets the list build,
// and measures again (bounded).
//
// The chat search uses the same anchors by index ([revealIndex]): the hit is
// put at the leading edge, approached in bounded, re-measured jumps when it
// is not built yet. Before, the search guessed `index * 72 px`.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MessageBoundaryNav {
  final Set<_MessageBoundaryAnchorState> _anchors = {};

  /// Target of a step still animating. A second click during the animation
  /// steps from there, not from a half-way position.
  double? _pendingTarget;

  /// Wraps one list item so its edges count as message boundaries. With
  /// [index] the item can also be reached by [revealIndex].
  Widget anchor({Key? key, int? index, required Widget child}) =>
      MessageBoundaryAnchor(key: key, nav: this, index: index, child: child);

  /// Forgets a step in progress (e.g. after a jump to the bottom).
  void reset() => _pendingTarget = null;

  /// The nearest boundary after (`forward`) or before the reference offset,
  /// measured on the items built in [position]'s viewport; `null` if none of
  /// the built items has one.
  @visibleForTesting
  double? boundaryFrom(ScrollPosition position, double reference,
      {required bool forward}) {
    const eps = 0.5;
    double? best;
    for (final a in _anchors) {
      if (!a.mounted) continue;
      final ro = a.context.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      if (Scrollable.maybeOf(a.context)?.position != position) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      final leading = viewport.getOffsetToReveal(ro, 0.0).offset;
      final extent = position.axis == Axis.vertical
          ? ro.size.height
          : ro.size.width;
      for (final edge in [leading, leading + extent]) {
        if (forward) {
          if (edge > reference + eps && (best == null || edge < best)) {
            best = edge;
          }
        } else {
          if (edge < reference - eps && (best == null || edge > best)) {
            best = edge;
          }
        }
      }
    }
    return best;
  }

  /// Leading-edge offset and extent of every built, indexed item of
  /// [position]'s viewport, by index.
  Map<int, ({double leading, double extent})> _builtByIndex(
      ScrollPosition position) {
    final out = <int, ({double leading, double extent})>{};
    for (final a in _anchors) {
      final i = a.widget.index;
      if (i == null || !a.mounted) continue;
      final ro = a.context.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      if (Scrollable.maybeOf(a.context)?.position != position) continue;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) continue;
      out[i] = (
        leading: viewport.getOffsetToReveal(ro, 0.0).offset,
        extent: position.axis == Axis.vertical ? ro.size.height : ro.size.width,
      );
    }
    return out;
  }

  /// Scrolls [controller] so that the item with [index] starts at the leading
  /// edge of the viewport (clamped to the scroll range, so an item near the
  /// end is at least fully visible).
  ///
  /// An item that is not built is approached first: the jump covers the
  /// index distance to the nearest built item times the mean height of the
  /// built items, the list builds there, and the next jump is measured again
  /// — at most [maxApproachSteps] jumps. Each jump lands closer, because the
  /// estimate is re-taken from the items actually built at the new place.
  Future<void> revealIndex(
    ScrollController controller,
    int index, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    int maxApproachSteps = 12,
  }) async {
    _pendingTarget = null;
    for (var step = 0; step <= maxApproachSteps; step++) {
      if (!controller.hasClients) return;
      final pos = controller.position;
      final built = _builtByIndex(pos);
      final hit = built[index];
      if (hit != null) {
        final target =
            hit.leading.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if (step == 0) {
          await controller.animateTo(target, duration: duration, curve: curve);
        } else {
          pos.jumpTo(target);
        }
        return;
      }
      if (built.isEmpty || step == maxApproachSteps) return;
      final indices = built.keys.toList()..sort();
      final first = indices.first, last = indices.last;
      final nearest = index < first ? first : last;
      var sum = 0.0;
      for (final e in built.values) {
        sum += e.extent;
      }
      final mean = sum / built.length;
      final from = built[nearest]!.leading;
      final probe = (from + (index - nearest) * mean)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((probe - pos.pixels).abs() < 0.5) {
        // Clamped at an end of the range; nudge one viewport further so the
        // lazy extent can grow, or stop if even that does not move.
        final nudge = (pos.pixels +
                (index < first ? -1 : 1) * pos.viewportDimension)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((nudge - pos.pixels).abs() < 0.5) return;
        pos.jumpTo(nudge);
      } else {
        pos.jumpTo(probe);
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Scrolls [controller] so that the next (`forward`) or previous message
  /// boundary lands at the leading edge of the viewport. At either end of the
  /// list the offset is clamped to the scroll range.
  Future<void> step(
    ScrollController controller, {
    required bool forward,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    if (!controller.hasClients) return;
    final position = controller.position;
    final reference = _pendingTarget ?? position.pixels;
    double? target = boundaryFrom(position, reference, forward: forward);

    // No built item carries the boundary: move one viewport towards it so
    // the list builds the items there, then measure again.
    for (var attempt = 0; target == null && attempt < 4; attempt++) {
      final probe = (reference +
              (forward ? 1 : -1) * position.viewportDimension * (attempt + 1))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (probe == position.pixels) break;
      position.jumpTo(probe);
      await WidgetsBinding.instance.endOfFrame;
      if (!controller.hasClients) return;
      target = boundaryFrom(controller.position, reference, forward: forward);
    }
    if (!controller.hasClients) return;
    final pos = controller.position;
    final clamped = (target ??
            (forward ? pos.maxScrollExtent : pos.minScrollExtent))
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _pendingTarget = clamped;
    try {
      await controller.animateTo(clamped, duration: duration, curve: curve);
    } finally {
      if (_pendingTarget == clamped) _pendingTarget = null;
    }
  }
}

/// One list item of a [MessageBoundaryNav]; registers itself while mounted.
class MessageBoundaryAnchor extends StatefulWidget {
  final MessageBoundaryNav nav;

  /// Position of the item in the list, for [MessageBoundaryNav.revealIndex].
  final int? index;
  final Widget child;

  const MessageBoundaryAnchor(
      {super.key, required this.nav, this.index, required this.child});

  @override
  State<MessageBoundaryAnchor> createState() => _MessageBoundaryAnchorState();
}

class _MessageBoundaryAnchorState extends State<MessageBoundaryAnchor> {
  @override
  void initState() {
    super.initState();
    widget.nav._anchors.add(this);
  }

  @override
  void didUpdateWidget(MessageBoundaryAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nav, widget.nav)) {
      oldWidget.nav._anchors.remove(this);
      widget.nav._anchors.add(this);
    }
  }

  @override
  void dispose() {
    widget.nav._anchors.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
