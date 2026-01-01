// lib/ui/theme/design_tokens.dart
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/tokens/spacing.dart';
import 'package:cleona/ui/theme/tokens/radius_scale.dart';
import 'package:cleona/ui/theme/tokens/cleona_typography.dart';
import 'package:cleona/ui/theme/tokens/motion.dart';
import 'package:cleona/ui/theme/tokens/elevation.dart';

@immutable
class DesignTokens extends ThemeExtension<DesignTokens> {
  final Spacing spacing;
  final RadiusScale radius;
  final CleonaTypography typography;
  final Motion motion;
  final Elevation elevation;

  const DesignTokens({
    required this.spacing,
    required this.radius,
    required this.typography,
    required this.motion,
    required this.elevation,
  });

  static const DesignTokens standard = DesignTokens(
    spacing: Spacing.standard,
    radius: RadiusScale.standard,
    typography: CleonaTypography.standard,
    motion: Motion.standard,
    elevation: Elevation.standard,
  );

  @override
  DesignTokens copyWith({
    Spacing? spacing,
    RadiusScale? radius,
    CleonaTypography? typography,
    Motion? motion,
    Elevation? elevation,
  }) {
    return DesignTokens(
      spacing: spacing ?? this.spacing,
      radius: radius ?? this.radius,
      typography: typography ?? this.typography,
      motion: motion ?? this.motion,
      elevation: elevation ?? this.elevation,
    );
  }

  @override
  DesignTokens lerp(ThemeExtension<DesignTokens>? other, double t) {
    // Tokens are discrete values; lerp returns self (design tokens don't animate)
    return this;
  }
}
