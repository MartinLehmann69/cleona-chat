import 'package:flutter/foundation.dart';

@immutable
class RadiusScale {
  final double none;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double pill;

  const RadiusScale({
    required this.none,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
  });

  static const RadiusScale standard = RadiusScale(
    none: 0, sm: 4, md: 8, lg: 12, xl: 16, pill: 9999,
  );
}
