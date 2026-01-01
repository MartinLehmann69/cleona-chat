import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

@immutable
class Motion {
  final Duration instant;
  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve enter;
  final Curve exit;
  final Curve emphasized;

  const Motion({
    required this.instant,
    required this.fast,
    required this.normal,
    required this.slow,
    required this.enter,
    required this.exit,
    required this.emphasized,
  });

  static const Motion standard = Motion(
    instant:    Duration.zero,
    fast:       Duration(milliseconds: 120),
    normal:     Duration(milliseconds: 200),
    slow:       Duration(milliseconds: 400),
    enter:      Curves.easeOut,
    exit:       Curves.easeIn,
    emphasized: Cubic(0.2, 0.0, 0.0, 1.0),
  );
}
